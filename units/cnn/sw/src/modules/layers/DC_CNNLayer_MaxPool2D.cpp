#include "DC_CNNLayer_MaxPool2D.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNHelper.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>
#include <limits>

namespace DC_ConvNet {

    /**
     * @brief Constructs a 2D max pooling layer
     */
    DC_CNNLayer_MaxPool2D::DC_CNNLayer_MaxPool2D(int pool_size, int stride)
        : m_pool_size(pool_size),
          m_stride(stride == -1 ? pool_size : stride) {
        m_layer_type = Layer_Type::MAXPOOL;
    }

    /**
     * @brief Performs forward propagation through the max pooling layer
     */
    DC_Tensor DC_CNNLayer_MaxPool2D::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        // Calculate output dimensions
        const auto num_output_channels = input.m_channels;
        const auto input_height = input.m_height;
        const auto input_width = input.m_width;
        const auto kernel_size = m_pool_size;

        // Calculate output dimensions
        const auto out_height = (input_height - kernel_size) / m_stride + 1;
        const auto out_width = (input_width - kernel_size) / m_stride + 1;

        DC_ComputeKernelParams compute_params(
            0, 0, 0, 0,
            input_height,
            input_width,
            kernel_size,
            m_stride,
            0,
            input.m_channels,
            num_output_channels
        );

        // Create output tensor
        DC_Tensor output(out_height, out_width, num_output_channels, input.m_mem_order);

        // Main pooling loop with optimized memory access based on memory layout
        for (auto out_row_idx = 0; out_row_idx < out_height; ++out_row_idx)
        {
            for (auto out_col_idx = 0; out_col_idx < out_width; ++out_col_idx)
            {
                for (auto out_channel_idx = 0; out_channel_idx < num_output_channels; ++out_channel_idx)
                {
                    compute_params.input_channel_start_idx = out_channel_idx;
                    compute_params.out_channel_idx = out_channel_idx;
                    compute_params.out_row_idx = out_row_idx;
                    compute_params.out_col_idx = out_col_idx;

                    // Compute maximum value in pooling window
                    const auto value = compute_kernel(
                        &input,
                        nullptr,
                        &compute_params,
                        StrideMode::MULTIPLY,
                        input.m_mem_order,
                        stats);

                    // Store the pooling result
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
        populate_stats_maxpool(input, out_height, out_width, num_output_channels, kernel_size, m_stride, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

    /**
     * @brief Computes the maximum value within a pooling window for MaxPool2D.
     */
    float DC_CNNLayer_MaxPool2D::compute_kernel(
        const DC_Tensor* const input,
        [[maybe_unused]] const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats) const {
        
        // Initialize max tracking
        auto max_val = -std::numeric_limits<float>::max();

        // Pooling window loop
        for (auto kernel_row_idx = 0; kernel_row_idx < compute_params->kernel_size; ++kernel_row_idx)
        {
            for (auto kernel_col_idx = 0; kernel_col_idx < compute_params->kernel_size; ++kernel_col_idx)
            {
                const int input_array_index = calculate_input_array_index(
                    compute_params->out_row_idx,
                    compute_params->out_col_idx,
                    kernel_row_idx,
                    kernel_col_idx,
                    compute_params->out_channel_idx,
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

                // Get the value from input tensor
                const auto val = input->m_data[input_array_index];

                // Update max value and index if necessary
                if (val > max_val) {
                    max_val = val;
                }

                stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Loading from input
                stats.record_operation(OperationType::ARITHMETIC_COMP, 1);  // Comparison
            }
        }

        return max_val;
    }

} // namespace DC_ConvNet 
