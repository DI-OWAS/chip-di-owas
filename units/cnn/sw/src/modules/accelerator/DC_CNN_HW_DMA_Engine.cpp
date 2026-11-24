#include "DC_CNN_HW_DMA_Engine.h"
#include "DC_CNNHelper.h"
#include "DC_Register_Bank.h"

#include <cassert>

using namespace DC_ConvNet;

DC_CNN_HW_DMA_Engine::DC_CNN_HW_DMA_Engine(DC_OnChipMemory& on_chip_memory
	, DC_HW_Memory_IF& memory_if
	, DC_Register_Bank& register_bank
	, const DC_HW_Params_Global& global_params
	, const std::vector<DC_HW_Params_Layer>& layer_params) :
	m_on_chip_memory(on_chip_memory),
	m_memory_if(memory_if),
	m_register_bank(register_bank),
	m_global_params(global_params),
	m_layer_params(layer_params){
}

void DC_CNN_HW_DMA_Engine::ProcessCommand(const DC_CNN_HW_Command& command){
	const auto& dma_cmd = static_cast<const DC_CNN_HW_DMA_Command&>(command);

	ProcessCommand(dma_cmd);
}

void DC_CNN_HW_DMA_Engine::ProcessCommand(const DC_CNN_HW_DMA_Command& command){

	const auto& instruction_params = command.get_params();
	const auto& layer_params = m_layer_params[instruction_params.m_layer_id];

	if (command.get_instruction_type() == InstructionType::LOAD_ON_CHIP_WEIGHTS){
		for (auto& itm : m_register_bank.m_inputs_mem_seeks) itm = 0u;
		for (auto& itm : m_is_first_load_input) itm = 0u;
		
		if (m_is_first_load_weights == 0u){
			m_register_bank.m_weights_on_chip_mem_seeks = m_on_chip_mem_seek;
			m_is_first_load_weights = 1u;
		}
		else{
			m_on_chip_mem_seek = m_register_bank.m_weights_on_chip_mem_seeks;
		}

		m_on_chip_mem_seek += copy_weights_to_on_chip_memory(
			m_memory_if.GetOffChipWeightsByAddr(
				layer_params.m_weights_mem_seeks,
				layer_params.m_num_input_channels *
				layer_params.m_num_output_channels *
				layer_params.m_kernel_size *
				layer_params.m_kernel_size),
			m_on_chip_memory,
			m_register_bank.m_weights_on_chip_mem_seeks,
			layer_params.m_num_input_channels,
			layer_params.m_num_output_channels,
			layer_params.m_kernel_size,
			instruction_params.m_out_channel_start_index,
			instruction_params.m_out_channel_end_index,
			m_global_params.m_mem_order_code);

		return;
	}

	if (command.get_instruction_type() == InstructionType::LOAD_ON_CHIP_INPUTS)	{
		if (m_is_first_load_input[layer_params.m_active_on_chip_input_buffer] == 0u){
			m_register_bank.m_inputs_mem_seeks[layer_params.m_active_on_chip_input_buffer] = m_on_chip_mem_seek;
		}

		const auto input_size = load_input_rows_to_on_chip_memory(
			m_memory_if.GetOffChipInputByAddr(
				layer_params.m_input_mem_seeks,
				layer_params.m_num_input_channels *
				layer_params.m_input_height *
				layer_params.m_input_width),
			m_on_chip_memory,
			m_register_bank.m_inputs_mem_seeks[layer_params.m_active_on_chip_input_buffer],
			layer_params.m_active_on_chip_input_buffer,
			layer_params.m_input_height,
			layer_params.m_input_width,
			layer_params.m_num_input_channels,
			layer_params.m_off_chip_input_channel_start_idx,
			instruction_params.m_out_row_idx,
			layer_params.m_kernel_size,
			layer_params.m_stride,
			layer_params.m_padding,
			layer_params.m_stride_mode_code,
			m_global_params.m_mem_order_code,
			m_global_params.m_number_of_rows_to_load);

		if (m_is_first_load_input[layer_params.m_active_on_chip_input_buffer] == 0u){
			m_on_chip_mem_seek += input_size;
			m_register_bank.m_outputs_mem_seeks = m_on_chip_mem_seek;

			m_is_first_load_input[layer_params.m_active_on_chip_input_buffer] = 1u;
		}

		return;
	}

	if (command.get_instruction_type() == InstructionType::STORE_OFF_CHIP_OUTPUTS){
		store_to_off_chip_memory(
			m_memory_if.GetOffChipBuffer(),
			layer_params.m_output_mem_seeks,
			m_on_chip_memory,
			m_register_bank.m_outputs_mem_seeks,
			instruction_params.m_out_channel_start_index,
			instruction_params.m_out_channel_end_index,
			layer_params.m_num_output_channels,
			instruction_params.m_out_row_idx,
			layer_params.m_out_height,
			layer_params.m_out_width,
			m_global_params.m_mem_order_code);
		return;
	}

	if (command.get_instruction_type() == InstructionType::LOAD_ON_CHIP_BIASES)
	{
		m_is_first_load_weights = 0;
		m_on_chip_mem_seek = 0;

		m_register_bank.m_biases_mem_seeks = m_on_chip_mem_seek;

		m_on_chip_mem_seek += load_biases_to_on_chip_memory(
			m_on_chip_memory,
			m_register_bank.m_biases_mem_seeks,
			m_memory_if.GetOffChipBiasByAddr(
				layer_params.m_biases_mem_seeks,
				static_cast<size_t>(layer_params.m_num_output_channels)),
			layer_params.m_num_output_channels);

		return;
	}

	if (command.get_instruction_type() == InstructionType::RESET_ON_CHIP_MEMORY)
	{
		for (auto& itm : m_register_bank.m_inputs_mem_seeks) itm = 0u;

		for (auto& itm : m_is_first_load_input) itm = 0u;

		m_is_first_load_weights = 0;

		m_on_chip_mem_seek = 0;

		return;
	}

	assert(false && "Wrong DMA command. Should not get this place.");
}
