#include "DC_CNN_HW_Compute_Engine.h"
#include "DC_OnChipCompute.h"
#include "DC_Register_Bank.h"

using namespace DC_ConvNet;

DC_CNN_HW_Compute_Engine::DC_CNN_HW_Compute_Engine(DC_OnChipMemory& on_chip_memory
	, DC_Register_Bank& register_bank
	, const DC_HW_Params_Global& global_params
	, const std::vector<DC_HW_Params_Layer>& layer_params)
	: m_on_chip_memory(on_chip_memory),
	m_register_bank(register_bank),
	m_global_params(global_params),
	m_layer_params(layer_params){
}

void DC_CNN_HW_Compute_Engine::ProcessCommand(const DC_CNN_HW_Command& command){
	if (command.get_instruction_type() == InstructionType::COMPUTE_CONV) {
		const auto& compute_conv_cmd = static_cast<const DC_CNN_HW_ComputeConvCommand&>(command);

		ProcessCommandConvolutionLayerByRow(compute_conv_cmd);

		return;
	}

	if (command.get_instruction_type() == InstructionType::COMPUTE_MAX_POOL) {
		const auto& compute_max_pool_cmd = static_cast<const DC_CNN_HW_ComputeMaxPoolCommand&>(command);

		ProcessCommandMaxPoolLayerByRow(compute_max_pool_cmd);

		return;
	}

	if (command.get_instruction_type() == InstructionType::COMPUTE_DENSE) {
		const auto& compute_dense_cmd = static_cast<const DC_CNN_HW_ComputeDenseCommand&>(command);

		ProcessCommandDenseLayer(compute_dense_cmd);

		return;
	}

	if (command.get_instruction_type() == InstructionType::COMPUTE_ROUTE) {
		const auto& compute_route_cmd = static_cast<const DC_CNN_HW_ComputeRouteCommand&>(command);

		ProcessCommandRouteLayerByRow(compute_route_cmd);

		return;
	}

	if (command.get_instruction_type() == InstructionType::COMPUTE_UPSAMPLE) {
		const auto& compute_upsample_cmd = static_cast<const DC_CNN_HW_ComputeUpSampleCommand&>(command);

		ProcessCommandUpSampleLayerByRow(compute_upsample_cmd);

		return;
	}
}

void DC_CNN_HW_Compute_Engine::ProcessCommandConvolutionLayerByRow(const DC_CNN_HW_ComputeConvCommand& command) {
	const auto& instruction_params = command.get_params();
	const auto& layer_params = m_layer_params[instruction_params.m_layer_id];

	DC_OnChipCompute::compute_instruction_conv2D(m_on_chip_memory
		, m_register_bank.m_inputs_mem_seeks[layer_params.m_active_on_chip_input_buffer]
		, m_register_bank.m_weights_on_chip_mem_seeks
		, m_register_bank.m_biases_mem_seeks
		, m_register_bank.m_outputs_mem_seeks
		, m_global_params
		, layer_params
		, command.get_params()
		, *layer_params.m_layer_stats_ptr);
}

void DC_CNN_HW_Compute_Engine::ProcessCommandMaxPoolLayerByRow(const DC_CNN_HW_ComputeMaxPoolCommand& command) {
	const auto& instruction_params = command.get_params();
	const auto& layer_params = m_layer_params[instruction_params.m_layer_id];

	DC_OnChipCompute::compute_instruction_max_pool(m_on_chip_memory
		, m_register_bank.m_inputs_mem_seeks[0]
		, m_register_bank.m_outputs_mem_seeks
		, m_global_params
		, layer_params
		, command.get_params()
		, *layer_params.m_layer_stats_ptr);
}

void DC_CNN_HW_Compute_Engine::ProcessCommandDenseLayer(const DC_CNN_HW_ComputeDenseCommand&) {
	//DC_OnChipCompute::compute_instruction_dense(m_on_chip_memory
	//	, m_register_bank.m_inputs_mem_seeks[0]
	//	, m_register_bank.m_weights_mem_seeks
	//	, m_register_bank.m_biases_mem_seeks
	//	, m_register_bank.m_outputs_mem_seeks
	//	, command.get_params()
	//	, *command.get_params().m_layer_stats_ptr);
}

void DC_CNN_HW_Compute_Engine::ProcessCommandRouteLayerByRow(const DC_CNN_HW_ComputeRouteCommand& command) {
	const auto& instruction_params = command.get_params();
	const auto& layer_params = m_layer_params[instruction_params.m_layer_id];

	DC_OnChipCompute::compute_instruction_route(m_on_chip_memory
		, m_register_bank.m_inputs_mem_seeks[0]
		, m_register_bank.m_inputs_mem_seeks[1]
		, m_register_bank.m_outputs_mem_seeks
		, m_global_params
		, layer_params
		, command.get_params()
		, *layer_params.m_layer_stats_ptr);
}

void DC_CNN_HW_Compute_Engine::ProcessCommandUpSampleLayerByRow(const DC_CNN_HW_ComputeUpSampleCommand& command) {
	const auto& instruction_params = command.get_params();
	const auto& layer_params = m_layer_params[instruction_params.m_layer_id];

	DC_OnChipCompute::compute_instruction_upsample(m_on_chip_memory
		, m_register_bank.m_inputs_mem_seeks[0]
		, m_register_bank.m_outputs_mem_seeks
		, m_global_params
		, layer_params
		, command.get_params()
		, *layer_params.m_layer_stats_ptr);
}
