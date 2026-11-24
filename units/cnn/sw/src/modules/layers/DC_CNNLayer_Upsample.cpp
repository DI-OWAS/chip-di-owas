#include "DC_CNNLayer_Upsample.h"
#include "DC_CNNHelper.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Upsample::DC_CNNLayer_Upsample(int stride) : m_stride(stride) {
        m_layer_type = Layer_Type::UPSAMPLE;
    }

    float DC_CNNLayer_Upsample::compute_kernel(const DC_Tensor* const input,
        [[maybe_unused]] const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats) const 
    {
        // Calculate input index using helper function
        const int in_index = calculate_input_array_index(
            compute_params->out_row_idx,
            compute_params->out_col_idx,
            0, 0,
            compute_params->out_channel_idx,
            compute_params->input_height,
            compute_params->input_width,
            compute_params->stride, 0,
            compute_params->num_output_channels,
            stride_mode,
            mem_order
        );

        const auto in_val = input->m_data[in_index];

        // Load input_tensor value
        stats.record_operation(OperationType::MEMORY_LOAD, 1);

        return in_val;
    }

    /**
     * @brief Performs forward propagation through the upsample layer.
     */
    DC_Tensor DC_CNNLayer_Upsample::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        // Calculate output dimensions
        const auto out_height = input.m_height * m_stride;
        const auto out_width = input.m_width * m_stride;

        // Create output tensor
        DC_Tensor output(out_height, out_width, input.m_channels, input.m_mem_order);

        const auto input_height = input.m_height;
        const auto input_width = input.m_width;
        const auto num_output_channels = input.m_channels;

        DC_ComputeKernelParams compute_params(
            0,  // input_channel_start_idx (not used)
            0,
            0,
            0,
            input_height,
            input_width,
            1,  // kernel_size (not used for upsample)
            m_stride,  // stride (not used in compute_kernel)
            0,  // padding
            num_output_channels,  // num_input_channels
            num_output_channels
        );

        // Process each element in the output tensor
        for (auto out_row_idx = 0; out_row_idx < out_height; ++out_row_idx)
        {
            for (auto out_col_idx = 0; out_col_idx < out_width; ++out_col_idx)
            {
                for (auto out_channel_idx = 0; out_channel_idx < num_output_channels; ++out_channel_idx)
                {
                    compute_params.out_channel_idx = out_channel_idx;
                    compute_params.out_row_idx = out_row_idx;
                    compute_params.out_col_idx = out_col_idx;

                    // Compute upsampled value using compute_kernel
                    const auto value = compute_kernel(
                        &input,
                        nullptr,  // no weights for upsample
                        &compute_params,
                        StrideMode::DIVIDE,
                        input.m_mem_order,
                        stats
                    );

                    // Store result using helper function
                    store_result(output,
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
        populate_stats_upsample(input, out_height, out_width, m_stride, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }
} // namespace DC_ConvNet 
