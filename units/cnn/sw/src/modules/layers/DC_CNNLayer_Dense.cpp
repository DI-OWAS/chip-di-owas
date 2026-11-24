#include "DC_CNNLayer_Dense.h"
#include "DC_CNN_axillary.h"
#include "DC_CNNHelper.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>

namespace DC_ConvNet
{
    /**
     * @brief Constructs a dense layer
     */
    DC_CNNLayer_Dense::DC_CNNLayer_Dense(int output_units, bool use_bias,
        ActivationType activation, float leaky_alpha)
        : m_output_channels(output_units),
        m_use_bias(use_bias), m_activation_type(activation), m_leaky_alpha(leaky_alpha)
    {
        m_layer_type = Layer_Type::DENSE;

        // Initialize weights and bias

        if (use_bias)
        {
            m_bias.resize(output_units);
        }
    }

    /**
     * @brief Computes the convolution result at a specific output position for a given output channel.
     */
    float DC_CNNLayer_Dense::compute_kernel(
        const float* const input,
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
            // Convolve kernel with input at current position
            for (auto kernel_row_idx = 0; kernel_row_idx < compute_params->kernel_size; ++kernel_row_idx)
            {
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

                    // Get input value
                    const auto input_val = input[input_array_index];

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

        return sum;
    }

    /**
     * @brief Performs forward propagation through the dense layer
     */
    DC_Tensor DC_CNNLayer_Dense::forward(const DC_Tensor& input) const
    {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto kernel_size = input.m_height;

        DC_ComputeKernelParams compute_params(
            0, 0, 0, 0,
            input.m_height,
            input.m_width,
            kernel_size,
            1, 0,
            input.m_channels,
            m_output_channels
        );

        DC_Tensor output(1, 1, m_output_channels, input.m_mem_order);

        // For each output unit
        for (auto out_channel_idx = 0; out_channel_idx < m_output_channels; ++out_channel_idx)
        {
            compute_params.out_channel_idx = out_channel_idx;

            auto value = compute_kernel(
                input.m_data.data(),
                m_weights.data(),
                &compute_params,
                StrideMode::MULTIPLY,
                input.m_mem_order,
                stats);

            // Branch check for bias
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
            // Initialize with bias if enabled
            if (m_use_bias) {
                value += m_bias[out_channel_idx];
                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
            }

            // Apply activation function
            value = activate_value(m_activation_type, value, m_leaky_alpha, stats);

            // Store result in output tensor
            // 0,0 -> out_row_idx, out_col_idx; 1,1 -> out_height, out_width (dense has 1x1)
            store_result(output, value, out_channel_idx, 0, 0, 1, 1, stats);
        }

        const auto input_size = input.m_channels * input.m_height * input.m_width;

        // Update statistics
        populate_stats_dense(input, input_size, m_output_channels, m_use_bias, m_activation_type, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
