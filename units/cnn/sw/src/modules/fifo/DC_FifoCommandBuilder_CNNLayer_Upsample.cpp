#include "DC_FifoCommandBuilder_CNNLayer_Upsample.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_HW_CommandBuilder.h"
#include "DC_CNNLayer_Stats.h"

namespace DC_ConvNet {

    DC_FifoCommandBuilder_CNNLayer_Upsample::DC_FifoCommandBuilder_CNNLayer_Upsample(int stride) : m_stride(stride) {
        m_layer_type = Layer_Type::UPSAMPLE;
    }

    DC_HW_Params_Layer DC_FifoCommandBuilder_CNNLayer_Upsample::build_layer_parameter_set(const DC_Tensor& input) const {
        // Configure parameters
        DC_HW_Params_Layer layer_params;

        layer_params.m_num_input_channels = input.m_channels;
        layer_params.m_num_output_channels = input.m_channels;
        layer_params.m_kernel_size = 1;
        layer_params.m_input_height = input.m_height;
        layer_params.m_input_width = input.m_width;
        layer_params.m_stride = m_stride;
        layer_params.m_padding = 0;
        layer_params.m_out_height = input.m_height * m_stride;
        layer_params.m_out_width = input.m_width * m_stride;
        layer_params.m_stride_mode_code = StrideMode::DIVIDE;
        layer_params.m_input_mem_seeks = input.m_input_mem_seeks;
        layer_params.m_output_mem_seeks = input.m_output_mem_seeks;
        layer_params.m_layer_stats_ptr = &DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        //Update statistics
        populate_stats_upsample(input, layer_params.m_out_height, layer_params.m_out_width, m_stride, *layer_params.m_layer_stats_ptr);

		return layer_params;
    }

    std::list<std::unique_ptr<DC_CNN_HW_Command>>
        DC_FifoCommandBuilder_CNNLayer_Upsample::build_fifo_commands(DC_Tensor& output, const DC_HW_Params_Layer& layer_params) const  {
        // Configure parameters
		DC_HW_Params_Instruction instruction_params;

        instruction_params.m_layer_id = layer_params.m_layer_id;
        instruction_params.m_out_channel_start_index = 0;
        instruction_params.m_out_channel_end_index = layer_params.m_num_input_channels;

        std::list<std::unique_ptr<DC_CNN_HW_Command>> fifo_cmds;

        // For each output row, emit LOAD_INPUTS, COMPUTE_UPSAMPLE, STORE_OUTPUTS
        for (auto out_row_idx = 0u; out_row_idx < layer_params.m_out_height; ++out_row_idx) {
            instruction_params.m_out_row_idx = out_row_idx;

            fifo_cmds.emplace_back(
                std::move(DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_inputs_command(instruction_params)));

            fifo_cmds.emplace_back(
                std::move(DC_CNN_HW_CommandBuilder::create_compute_upsample_command(instruction_params)));

            fifo_cmds.emplace_back(
                std::move(DC_CNN_HW_CommandBuilder::create_dma_store_off_chip_outputs_command(instruction_params)));
        }

        fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_on_chip_reset_command(instruction_params)));

        output.m_height = layer_params.m_out_height;
        output.m_width = layer_params.m_out_width;
        output.m_channels = layer_params.m_num_input_channels;

        return fifo_cmds;
    }

} // namespace DC_ConvNet 
