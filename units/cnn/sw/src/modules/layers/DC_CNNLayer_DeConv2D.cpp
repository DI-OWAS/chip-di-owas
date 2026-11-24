#include "DC_CNNLayer_DeConv2D.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_axillary.h"
#include "DC_CNNHelper.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_DeConv2D::DC_CNNLayer_DeConv2D(
        int in_channels,
        int out_channels,
        int kernel_size,
        int stride,
        int padding,
        bool use_bias,
        ActivationType activation)
        : m_in_channels(in_channels),
          m_out_channels(out_channels),
          m_kernel_size(kernel_size),
          m_stride(stride),
          m_padding(padding),
          m_use_bias(use_bias),
          m_activation(activation),
          m_leaky_alpha(0.1f) {
        m_layer_type = Layer_Type::DECONV2D;
        if (m_use_bias) {
            m_bias.assign(static_cast<size_t>(out_channels), 0.0f);
        }
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_DeConv2D::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        if (!weights_loaded()) {
            throw std::runtime_error("DeConv2D layer weights are not loaded");
        }
        if (m_use_bias && !bias_loaded()) {
            throw std::runtime_error("DeConv2D layer bias is not loaded");
        }

        DC_ComputeKernelParams compute_params(
            0, // start input channel index
            0,
            0,
            0,
            input.m_height,
            input.m_width,
            m_kernel_size,
            m_stride,
            m_padding,
            m_in_channels,
            m_out_channels
        );

        const auto out_height = (input.m_height - 1) * m_stride - 2 * m_padding + m_kernel_size;
        const auto out_width = (input.m_width - 1) * m_stride - 2 * m_padding + m_kernel_size;

        DC_Tensor output(out_height, out_width, m_out_channels, input.m_mem_order);

        // Output-centric loop: fuse DeConv2D + bias + activation (same pattern as Conv2D)
        for (auto out_row_idx = 0; out_row_idx < out_height; ++out_row_idx)
        {
            for (auto out_col_idx = 0; out_col_idx < out_width; ++out_col_idx)
            {
                for (auto out_channel_idx = 0; out_channel_idx < m_out_channels; ++out_channel_idx)
                {
                    compute_params.out_channel_idx = out_channel_idx;
                    compute_params.out_row_idx = out_row_idx;
                    compute_params.out_col_idx = out_col_idx;

                    auto value = compute_kernel(
                        &input,
                        m_weights.data(),
                        &compute_params,
                        StrideMode::MULTIPLY, // unused; DeConv2D uses dedicated index helper
                        input.m_mem_order,
                        stats);

                    stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                    if (m_use_bias)
                    {
                        value += m_bias[static_cast<size_t>(out_channel_idx)];
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                    }

                    value = activate_value(m_activation, value, m_leaky_alpha, stats);

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

        populate_stats_deconv(
            input,
            m_use_bias,
            m_out_channels,
            out_height,
            out_width,
            m_in_channels,
            m_kernel_size,
            m_stride,
            m_padding,
            m_activation,
            stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

    float DC_CNNLayer_DeConv2D::compute_kernel(
        const DC_Tensor* const input,
        const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        [[maybe_unused]] StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats
    ) const
    {
        auto sum = 0.0f;

        for (auto input_channel_idx = compute_params->input_channel_start_idx;
             input_channel_idx < compute_params->num_input_channels;
             ++input_channel_idx)
        {
            for (auto kernel_row_idx = 0; kernel_row_idx < compute_params->kernel_size; ++kernel_row_idx)
            {
                for (auto kernel_col_idx = 0; kernel_col_idx < compute_params->kernel_size; ++kernel_col_idx)
                {
                    // ConvTranspose weights stay in IOHW ([in, out, kh, kw]) regardless of
                    // activation tensor mem_order — same layout as the previous implementation.
                    const int weight_array_index = calculate_weight_array_index(
                        compute_params->out_channel_idx,
                        compute_params->kernel_size,
                        kernel_row_idx,
                        kernel_col_idx,
                        input_channel_idx,
                        compute_params->num_output_channels,
                        compute_params->num_input_channels,
                        MEM_ORDER::CHW
                    );

                    const int input_array_index = calculate_deconv_input_array_index(
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
                        mem_order
                    );

                    if (input_array_index < 0) {
                        continue;
                    }

                    const auto input_val = input->m_data[static_cast<size_t>(input_array_index)];
                    const auto weight_val = weights[weight_array_index];

                    sum += input_val * weight_val;

                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                }
            }
        }

        return sum;
    }

} // namespace DC_ConvNet
