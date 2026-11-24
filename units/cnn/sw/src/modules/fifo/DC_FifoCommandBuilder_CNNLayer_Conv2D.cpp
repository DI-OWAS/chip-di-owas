#include "DC_FifoCommandBuilder_CNNLayer_Conv2D.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_HW_CommandBuilder.h"
#include "DC_tensor.h"
#include "DC_CNN_Accelerator_Const.h"
#include "DC_CNNLayer_Stats.h"

namespace DC_ConvNet {

    DC_FifoCommandBuilder_CNNLayer_Conv2D::DC_FifoCommandBuilder_CNNLayer_Conv2D(int in_channels, int out_channels, int kernel_size,
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
            m_batch_norm, m_weights_off_chip_memory, m_bias_off_chip_memory, m_bn_gamma, m_bn_beta, m_bn_mean, m_bn_var);
    }

    DC_HW_Params_Layer DC_FifoCommandBuilder_CNNLayer_Conv2D::build_layer_parameter_set(const DC_Tensor& input) const
    {
        DC_HW_Params_Layer layer_params;

        layer_params.m_num_input_channels = m_num_input_channels;
        layer_params.m_num_output_channels = m_num_output_channels;
        layer_params.m_kernel_size = m_kernel_size;
        layer_params.m_input_height = input.m_height;
        layer_params.m_input_width = input.m_width;
        layer_params.m_stride = m_stride;
        layer_params.m_padding = m_padding;
        layer_params.m_out_height = (input.m_height + 2 * m_padding - m_kernel_size) / m_stride + 1;
        layer_params.m_out_width = (input.m_width + 2 * m_padding - m_kernel_size) / m_stride + 1;
        layer_params.m_weights_mem_seeks = input.m_weights_mem_seeks;
        layer_params.m_biases_mem_seeks = input.m_biases_mem_seeks;
        layer_params.m_input_mem_seeks = input.m_input_mem_seeks;
        layer_params.m_output_mem_seeks = input.m_output_mem_seeks;
        layer_params.m_use_bias = m_use_bias;
        layer_params.m_activation_type = m_activation_type;
        layer_params.m_leaky_alpha = m_leaky_alpha;
        layer_params.m_layer_stats_ptr = &DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        //Update statistics
        populate_stats_conv(input, m_use_bias, m_batch_norm, m_num_output_channels,
            layer_params.m_out_height, layer_params.m_out_width, m_num_input_channels, 
            m_kernel_size, m_stride, m_padding, m_activation_type, *layer_params.m_layer_stats_ptr);

        return layer_params;
    }

    std::list<std::unique_ptr<DC_CNN_HW_Command>>
        DC_FifoCommandBuilder_CNNLayer_Conv2D::build_fifo_commands(DC_Tensor& output, const DC_HW_Params_Layer& layer_params) const
    {
		std::list<std::unique_ptr<DC_CNN_HW_Command>> fifo_cmds;

        const auto storage_size_internal_bytes = weights_memory_size_bytes;
        const auto weight_byte_size = sizeof(float);
        const auto storage_size_internal_mem_num_rows_of_2D_weight_matrix =
            storage_size_internal_bytes / (m_num_input_channels * layer_params.m_kernel_size * layer_params.m_kernel_size * weight_byte_size);
        const auto num_weight_sets = m_num_output_channels / storage_size_internal_mem_num_rows_of_2D_weight_matrix + 1;

		DC_HW_Params_Instruction instruction_params;
		
        instruction_params.m_layer_id = layer_params.m_layer_id;

        // LOAD_BIASES_INSTRUCTION: load all biases into internal memory, can be loaded by output channel tail. 
        // Bias array size is equal to output channels
        fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_biases_command(instruction_params)));

        //  COPY_INSTRUCTION: copy weight set into internal memory
        for (auto weight_set_index = 0u; weight_set_index < num_weight_sets; weight_set_index++)
        {
            // Calculate the range of output channels for this weight set
            const auto out_channel_start_index = weight_set_index * storage_size_internal_mem_num_rows_of_2D_weight_matrix;
            auto out_channel_end_index = out_channel_start_index + storage_size_internal_mem_num_rows_of_2D_weight_matrix;
            if (out_channel_end_index >= m_num_output_channels) out_channel_end_index = m_num_output_channels;

            instruction_params.m_out_channel_start_index = out_channel_start_index;
            instruction_params.m_out_channel_end_index = out_channel_end_index;

            fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_weights_command(instruction_params)));

            // For each output position - fuse conv + bias + BN + activation
            for (auto out_row_idx = 0u; out_row_idx < layer_params.m_out_height; ++out_row_idx)
            {
                // COPY_INSTRUCTION: copy input row(s)m into internal memory
                instruction_params.m_out_row_idx = out_row_idx;

                fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_inputs_command(instruction_params)));

                //===============================================================================================================
                // COMPUTE_INSTRUCTION: ...
                fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_compute_conv_command(instruction_params)));

                //STORE_OFF_INSTRUCTION
                fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_store_off_chip_outputs_command(instruction_params)));
            }
        }

        fifo_cmds.emplace_back(std::move(DC_CNN_HW_CommandBuilder::create_dma_on_chip_reset_command(instruction_params)));

		output.m_height = layer_params.m_out_height;
		output.m_width = layer_params.m_out_width;
		output.m_channels = m_num_output_channels;

        return fifo_cmds;
    }
} // namespace DC_ConvNet 
