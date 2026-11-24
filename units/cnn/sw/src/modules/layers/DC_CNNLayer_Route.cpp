#include "DC_CNNLayer_Route.h"
#include "DC_CNNHelper.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Route::DC_CNNLayer_Route(const std::vector<std::pair<int, DC_Tensor>>& layers, int groups, int group_id)
        : m_groups(groups), m_group_id(group_id), m_outputs(0) {
        m_layer_type = Layer_Type::ROUTE;

        calculate_input_sizes_and_output(layers);
    }

    /**
     * @brief Calculates input sizes and output dimensions
     */
    void DC_CNNLayer_Route::calculate_input_sizes_and_output(const std::vector<std::pair<int, DC_Tensor>>& layers)
    {
        // Calculate input sizes and total output size
        for (const auto& layer : layers)
        {
            m_layers.push_back(layer.first);

            const DC_Tensor& source = layer.second;
            const auto input_size = source.m_height * source.m_width * source.m_channels;
            m_input_sizes.push_back(input_size);

            const auto part_size = input_size / m_groups;
            m_outputs += part_size;
        }

        const DC_Tensor& first_input = layers[0].second;
        m_output_height = first_input.m_height;
        m_output_width = first_input.m_width;
        m_output_channels = m_outputs / (first_input.m_height * first_input.m_width);
    }

    std::pair<const DC_Tensor&, int> DC_CNNLayer_Route::determine_source_layer(
        int out_channel,
        const std::vector<int>& channels_per_group_per_layer,
        const std::vector<int>& start_channels_per_layer,
        const std::vector<DC_Tensor>& layer_outputs) const
    {
        int layer_id = 0;
        int channel_offset = out_channel;

        for (size_t i = 0; i < channels_per_group_per_layer.size(); ++i) {
            if (channel_offset < channels_per_group_per_layer[i]) {
                layer_id = static_cast<int>(i);
                break;
            }
            channel_offset -= channels_per_group_per_layer[i];
        }

        return { layer_outputs[m_layers[layer_id]], start_channels_per_layer[layer_id] + channel_offset };
    }

    float DC_CNNLayer_Route::compute_kernel(
        const DC_Tensor* const input,
        [[maybe_unused]] const float* const weights,
        const DC_ComputeKernelParams* const compute_params,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        LayerStats& stats) const
    {
        const int in_idx = calculate_input_array_index(
            compute_params->out_row_idx, compute_params->out_col_idx,
            0, 0,  // kernel_row_idx, kernel_col_idx (no kernel for route)
            compute_params->input_channel_start_idx,
            compute_params->input_height,
            compute_params->input_width,
            compute_params->stride, compute_params->padding,  // stride=1, padding=0
            compute_params->num_input_channels,
            stride_mode,
            mem_order
        );

        // Record one load for reading the input element
        stats.record_operation(OperationType::MEMORY_LOAD, 1);
        return input->m_data[in_idx];
    }

    /**
     * @brief Forward pass for the Route layer.
     */
    DC_Tensor DC_CNNLayer_Route::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        // Create output tensor with correct size and memory layout
        DC_Tensor output(m_output_height, m_output_width, m_output_channels, layer_outputs[m_layers[0]].m_mem_order);

        DC_ComputeKernelParams compute_params(
            0,
            0,
            0,
            0,
            m_output_height,
            m_output_width,
            0, //kernel size
            1, //stride
            0, //padding
            0,
            m_output_channels
        );

        // Precompute channels per group for each input layer
        std::vector<int> channels_per_group_per_layer;
        std::vector<int> start_channels_per_layer;
        int cumulative_output_channels = 0;

        for (size_t i = 0; i < m_layers.size(); ++i) {
            const DC_Tensor& input = layer_outputs[m_layers[i]];
            const int input_channels = input.m_channels;
            const int channels_per_group = input_channels / m_groups;
            const int start_channel = channels_per_group * m_group_id;

            channels_per_group_per_layer.push_back(channels_per_group);
            start_channels_per_layer.push_back(start_channel);
            cumulative_output_channels += channels_per_group;
        }

        for (int out_row_idx = 0; out_row_idx < m_output_height; ++out_row_idx) 
        {
            for (int out_col_idx = 0; out_col_idx < m_output_width; ++out_col_idx) 
            {
                for (int out_channel_idx = 0; out_channel_idx < m_output_channels; ++out_channel_idx) 
                {
                    // Determine which input layer this output channel belongs to
                    const auto [input, input_channel_start_idx] = determine_source_layer(out_channel_idx, channels_per_group_per_layer, start_channels_per_layer, layer_outputs);

                    compute_params.input_channel_start_idx = input_channel_start_idx;
                    compute_params.out_channel_idx = out_channel_idx;
                    compute_params.out_row_idx = out_row_idx;
                    compute_params.out_col_idx = out_col_idx;
                    compute_params.num_input_channels = input.m_channels;

                    const auto value = compute_kernel(
                        &input,
                        nullptr,
                        &compute_params,
                        StrideMode::MULTIPLY,
                        layer_outputs[m_layers[0]].m_mem_order,
                        stats);

                    store_result(output, 
                        value,
                        out_channel_idx,
                        out_row_idx, 
                        out_col_idx, 
                        m_output_height, 
                        m_output_width, 
                        stats);
                }
            }
        }

        // Update statistics
        populate_stats_route(layer_outputs, m_layers, m_input_sizes, m_groups, output.m_height, output.m_width, output.m_channels, stats);
        try {
            dump_output_if_enabled(output, layer_outputs[m_layers[0]].m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }
} // namespace DC_ConvNet 
