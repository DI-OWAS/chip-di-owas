#include "DC_CNNLayer_Gemm.h"
#include "DC_CNNHelper.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Gemm::DC_CNNLayer_Gemm(int in_features, int out_features, bool use_bias)
        : m_in_features(in_features),
          m_out_features(out_features),
          m_use_bias(use_bias) {
        m_layer_type = Layer_Type::GEMM;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Gemm::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto [rows, input_cols] = tensor_matrix_dims(input);
        if (input_cols != m_in_features) {
            throw std::runtime_error("Gemm input feature dimension does not match in_features");
        }
        if (!weights_loaded()) {
            throw std::runtime_error("Gemm layer weights are not loaded");
        }
        if (m_use_bias && !bias_loaded()) {
            throw std::runtime_error("Gemm layer bias is not loaded");
        }

        // Use the real tensor layout so calculate_*_array_index honor mem_order.
        DC_ComputeKernelParams compute_params(
            0, // start input channel index
            0,
            0,
            0,
            input.m_height,
            input.m_width,
            1, // 1x1 over the contracting feature dimension
            1,
            0,
            input.m_channels,
            m_out_features
        );

        DC_Tensor output(rows, m_out_features, 1, input.m_mem_order);

        for (int row = 0; row < rows; ++row) {
            if (input.m_channels == 1) {
                // Matrix is HxW with C=1: features along width, row = out_row_idx
                compute_params.out_row_idx = row;
                compute_params.out_col_idx = 0;
            }
            else {
                // Matrix is (H*W) x C: features along channels
                compute_params.out_row_idx = row / input.m_width;
                compute_params.out_col_idx = row % input.m_width;
            }

            for (int out_col = 0; out_col < m_out_features; ++out_col) {
                compute_params.out_channel_idx = out_col;

                auto value = compute_kernel(
                    &input,
                    m_weights.data(),
                    &compute_params,
                    StrideMode::MULTIPLY,
                    input.m_mem_order,
                    stats);

                // Fused bias (same pattern as Conv2D: after compute_kernel)
                stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                if (m_use_bias)
                {
                    value += m_bias[static_cast<size_t>(out_col)];
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                }

                // Matrix output is HxW with 1 channel: store at (row, out_col)
                store_result(output, value, 0, row, out_col, rows, m_out_features, stats);
            }
        }

        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            m_use_bias, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_gemm(rows, m_in_features, m_out_features, m_use_bias, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

    float DC_CNNLayer_Gemm::compute_kernel(
        const DC_Tensor* const input,
        const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats
    ) const
    {
        auto sum = 0.0f;

        // C==1: features lie along width. Weight still contracts over in_features
        // as input channels of a 1x1 kernel (same as Conv2D/Dense weight layout).
        if (compute_params->num_input_channels == 1) {
            for (int feature_idx = 0; feature_idx < m_in_features; ++feature_idx) {
                const int weight_array_index = calculate_weight_array_index(
                    feature_idx,
                    1,
                    0,
                    0,
                    compute_params->out_channel_idx,
                    m_in_features,
                    m_out_features,
                    mem_order
                );

                const int input_array_index = calculate_input_array_index(
                    compute_params->out_row_idx,
                    feature_idx,
                    0,
                    0,
                    0,
                    compute_params->input_height,
                    compute_params->input_width,
                    compute_params->stride,
                    compute_params->padding,
                    1,
                    stride_mode,
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
            return sum;
        }

        // Features along channels — same structure as Conv2D
        for (auto input_channel_idx = compute_params->input_channel_start_idx;
             input_channel_idx < compute_params->num_input_channels;
             ++input_channel_idx)
        {
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
