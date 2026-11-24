#include "DC_CNNLayer_Conv2D.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_axillary.h"
#include "DC_CNNHelper.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>
#include <cmath>

namespace DC_ConvNet {

    DC_CNNLayer_Conv2D::DC_CNNLayer_Conv2D(int in_channels, int out_channels, int kernel_size,
        int stride, int padding, bool use_bias,
        bool batch_norm,
        ActivationType activation, float leaky_alpha,
        float eps)
        : m_batch_norm(batch_norm), m_num_input_channels(in_channels), m_num_output_channels(out_channels),
        m_kernel_size(kernel_size), m_stride(stride), m_padding(padding),
        m_use_bias(!batch_norm && use_bias), // Ignore use_bias if batch_norm is true
        m_activation_type(activation), m_leaky_alpha(leaky_alpha),
        m_eps(eps) {

        m_layer_type = Layer_Type::CONV;

        initialize_parameters(kernel_size, in_channels, out_channels, m_use_bias,
            m_batch_norm, m_weights, m_bias, m_bn_gamma, m_bn_beta, m_bn_mean, m_bn_var);

        set_dump_enabled(true);
    }

    /**
     * @brief Performs forward propagation through the convolutional layer
     */
    DC_Tensor DC_CNNLayer_Conv2D::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        // Compute convolution at this output position
        DC_ComputeKernelParams compute_params(
            0, //start input channel index
            0,
            0,
            0,
            input.m_height,
            input.m_width,
            m_kernel_size,
            m_stride,
            m_padding,
            m_num_input_channels,
            m_num_output_channels
        );

        // Calculate output dimensions with padding
        const auto out_height = (input.m_height + 2 * m_padding - m_kernel_size) / m_stride + 1;
        const auto out_width = (input.m_width + 2 * m_padding - m_kernel_size) / m_stride + 1;

        // Create output tensor
        DC_Tensor output(out_height, out_width, m_num_output_channels, input.m_mem_order);

        // Precompute BatchNorm scale/shift per channel if enabled
        const auto [bn_scale, bn_shift] = precompute_batch_norm_params(stats);

        // For each output position - fuse conv + bias + BN + activation
        for (auto out_row_idx = 0; out_row_idx < out_height; ++out_row_idx)
        {
            for (auto out_col_idx = 0; out_col_idx < out_width; ++out_col_idx)
            {
                for (auto out_channel_idx = 0; out_channel_idx < m_num_output_channels; ++out_channel_idx)
                {
                    compute_params.out_channel_idx = out_channel_idx;
                    compute_params.out_row_idx = out_row_idx;
                    compute_params.out_col_idx = out_col_idx;

                    auto value = compute_kernel(
                        &input,
                        m_weights.data(),
                        &compute_params,
                        StrideMode::MULTIPLY,
                        input.m_mem_order,
                        stats);

                    // Fused bias
                    // Branch check for bias
                    stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                    if (m_use_bias)
                    {
                        // Load bias value for this channel once per element
                        value += m_bias[out_channel_idx];
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                    }

                    // Fused BatchNorm
                    // Branch check for batch norm
                    stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                    if (m_batch_norm)
                    {
                        // value = value * scale + shift
                        value = value * bn_scale[out_channel_idx] + bn_shift[out_channel_idx];
                        stats.record_operation(OperationType::MEMORY_LOAD, 2);
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                    }

                    // Fused activation
                    value = activate_value(m_activation_type, value, m_leaky_alpha, stats);

                    // Store final result
                    store_result(
                        output,
                        value,
                        out_channel_idx,
                        out_row_idx,
                        out_col_idx,
                        out_height,
                        out_width,
                        stats);
                }
            }
        }

        //Update statistics
        populate_stats_conv(input, m_use_bias, m_batch_norm, m_num_output_channels,
            out_height, out_width, m_num_input_channels, m_kernel_size,m_stride, m_padding, m_activation_type, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

    /**
     * @brief Precomputes batch normalization scale and shift parameters
     */
    std::tuple<std::vector<float>, std::vector<float>> 
        DC_CNNLayer_Conv2D::precompute_batch_norm_params(LayerStats& stats) const
    {
        if (!m_batch_norm) {
            return {};
        }

        std::vector<float> bn_scale;
        std::vector<float> bn_shift;

        bn_scale.resize(m_num_output_channels);
        bn_shift.resize(m_num_output_channels);

        const float min_variance = 1e-5f;
        for (int c = 0; c < m_num_output_channels; ++c)
        {
            // Load BN params
            const float gamma = m_bn_gamma[c];
            const float beta  = m_bn_beta[c];
            const float mean  = m_bn_mean[c];
            const float var   = m_bn_var[c];
            stats.record_operation(OperationType::MEMORY_LOAD, 4);

            float variance_plus_eps = var + m_eps;
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);

            if (variance_plus_eps < min_variance)
            {
                stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                variance_plus_eps = min_variance;
            }

            const float inv_std = 1.0f / std::sqrt(variance_plus_eps);
            stats.record_operation(OperationType::ARITHMETIC_OTHER, 1); // sqrt
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1);   // division as mul

            // Precompute fused scale/shift: y = x * scale + shift
            const float scale = gamma * inv_std;             // 1 mul
            const float shift = beta - mean * scale;         // 1 mul + 1 add
            stats.record_operation(OperationType::ARITHMETIC_MUL, 2);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);

            bn_scale[c] = scale;
            bn_shift[c] = shift;
            // Store precomputed parameters (account memory store)
            stats.record_operation(OperationType::MEMORY_STORE, 2);
        }

        return {bn_scale, bn_shift};
    }

    /**
     * @brief Computes the convolution result at a specific output position for a given output channel.
     */
    float DC_CNNLayer_Conv2D::compute_kernel(
        const DC_Tensor* const input,
        const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats
    ) const 
    {
        auto sum = 0.0f;

        // For each input channel
        for (auto input_channel_idx = compute_params->input_channel_start_idx; input_channel_idx < compute_params->num_input_channels; ++input_channel_idx)
        {
            for (auto kernel_row_idx = 0; kernel_row_idx < compute_params->kernel_size; ++kernel_row_idx)
            {
                // Convolve kernel with input at current position
                for (auto kernel_col_idx = 0; kernel_col_idx < compute_params->kernel_size; ++kernel_col_idx)
                {
                    const int weight_array_index = calculate_weight_array_index(
                        input_channel_idx,
                        compute_params->kernel_size,
                        kernel_row_idx,
                        kernel_col_idx,
                        compute_params->out_channel_idx,
                        compute_params->num_input_channels,
                        compute_params->num_output_channels,
                        mem_order
                    );

                    const int input_array_index = calculate_input_array_index(
                        compute_params->out_row_idx,
                        compute_params->out_col_idx,
                        kernel_row_idx,
                        kernel_col_idx,
                        input_channel_idx,
                        compute_params->input_height,
                        compute_params->input_width,
                        compute_params->stride,
                        compute_params->padding,
                        compute_params->num_input_channels,
                        stride_mode,
                        mem_order
                    );

                    if (input_array_index < 0) {
                        continue;
                    }

                    // Process valid position
                    {
                        // Get input value
                        const auto input_val = input->m_data[input_array_index];

                        // Get weight value
                        const auto weight_val = weights[weight_array_index];

                        sum += input_val * weight_val;

                        stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load input value
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load weight value
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);  // Multiplication
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);  // Addition (sum +=)
                    }
                }
            }
        }

        return sum;
    }
} // namespace DC_ConvNet 
