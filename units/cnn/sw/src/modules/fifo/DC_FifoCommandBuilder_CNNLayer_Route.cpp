#include "DC_FifoCommandBuilder_CNNLayer_Route.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_HW_CommandBuilder.h"
#include "DC_CNNLayer_Stats.h"

namespace DC_ConvNet {

    DC_FifoCommandBuilder_CNNLayer_Route::DC_FifoCommandBuilder_CNNLayer_Route(const std::vector<std::pair<int, DC_Tensor>>& layers, int groups, int group_id)
        : m_groups(groups), m_group_id(group_id), m_outputs(0) {
        m_layer_type = Layer_Type::ROUTE;

        calculate_input_sizes_and_output(layers);
    }

    /**
     * @brief Calculates input sizes and output dimensions
     */
    void DC_FifoCommandBuilder_CNNLayer_Route::calculate_input_sizes_and_output(const std::vector<std::pair<int, DC_Tensor>>& layers)
    {
        // Calculate input sizes and total output size
        for (const auto& layer : layers)
        {
            m_route_layer_indices.push_back(layer.first);

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

    std::vector<DC_HW_Params_Layer> DC_FifoCommandBuilder_CNNLayer_Route::build_layer_parameter_set(const std::vector<DC_Tensor>& layer_outputs) const {
        
        std::vector<DC_HW_Params_Layer> layers_params;

        for (size_t i = 0; i < m_route_layer_indices.size(); ++i) {
            DC_HW_Params_Layer layer_params;

           layer_params.m_num_output_channels = m_output_channels;
           layer_params.m_kernel_size = 1;
           layer_params.m_input_height = layer_outputs[m_route_layer_indices[0]].m_height;
           layer_params.m_input_width = layer_outputs[m_route_layer_indices[0]].m_width;
           layer_params.m_stride = 1;
           layer_params.m_padding = 0;
           layer_params.m_out_height = layer_params.m_input_height;
           layer_params.m_out_width = layer_params.m_input_width;
           layer_params.m_route_channel_offset = (m_groups == 1) ? layer_outputs[m_route_layer_indices[i]].m_channels : m_output_channels;
           layer_params.m_num_input_channels = layer_outputs[m_route_layer_indices[i]].m_channels;
           layer_params.m_input_mem_seeks = layer_outputs[m_route_layer_indices[i]].m_output_mem_seeks;
           layer_params.m_output_mem_seeks = layer_outputs.back().m_output_mem_seeks + layer_outputs.back().get_tensor_size();
           layer_params.m_active_off_chip_input_buffer = i;
           layer_params.m_active_on_chip_input_buffer = i;
           layer_params.m_off_chip_input_channel_start_idx = m_group_id * layer_params.m_route_channel_offset;
           layer_params.m_layer_stats_ptr = &DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

           // Update statistics
           populate_stats_route(layer_outputs, m_route_layer_indices, m_input_sizes, m_groups, 
               layer_params.m_out_height, layer_params.m_out_width, layer_params.m_num_output_channels, *layer_params.m_layer_stats_ptr);

		   layers_params.push_back(layer_params);
        }

		return layers_params;
    }

    std::list<std::unique_ptr<DC_CNN_HW_Command>>
        DC_FifoCommandBuilder_CNNLayer_Route::build_fifo_commands(DC_Tensor& output, const std::vector<DC_HW_Params_Layer>& layer_params) const
    {
        std::list<std::unique_ptr<DC_CNN_HW_Command>> fifo_cmds;

        auto out_channel_start_index = 0;
        auto out_channel_end_index = 0;

        for (size_t i = 0; i < m_route_layer_indices.size(); ++i) {
            out_channel_start_index = out_channel_end_index;
            out_channel_end_index += layer_params[i].m_route_channel_offset;

            DC_HW_Params_Instruction instruction_params;
            instruction_params.m_layer_id = layer_params[i].m_layer_id;
			instruction_params.m_out_channel_start_index = out_channel_start_index;
			instruction_params.m_out_channel_end_index = out_channel_end_index;

            for (int out_row_idx = 0; out_row_idx < m_output_height; ++out_row_idx)
            {
                instruction_params.m_out_row_idx = out_row_idx;

                fifo_cmds.emplace_back(
                    std::move(DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_inputs_command(instruction_params)));

                // COMPUTE_INSTRUCTION: ...
                fifo_cmds.emplace_back(
                    std::move(DC_CNN_HW_CommandBuilder::create_compute_route_command(instruction_params)));

                fifo_cmds.emplace_back(
                    std::move(DC_CNN_HW_CommandBuilder::create_dma_store_off_chip_outputs_command(instruction_params)));
            }
        }

        DC_HW_Params_Instruction instruction_params;

        fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_on_chip_reset_command(instruction_params)));

		output.m_height = m_output_height;
		output.m_width = m_output_width;
		output.m_channels = m_output_channels;

        return fifo_cmds;
    }
} // namespace DC_ConvNet 
