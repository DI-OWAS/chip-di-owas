#include "DC_CNN_HW_AI_Accelerator.h"

#include <assert.h>

DC_ConvNet::DC_CNN_HW_AI_Accelerator::DC_CNN_HW_AI_Accelerator(DC_HW_Memory_IF& memory_if) :
	m_dma_engine(m_on_chip_memory, memory_if, m_register_bank, m_global_params, m_layer_params),
	m_compute_engine(m_on_chip_memory, m_register_bank, m_global_params, m_layer_params){
}

void DC_ConvNet::DC_CNN_HW_AI_Accelerator::ProcessCommandFifo(){
	for (const auto& cmd : m_command_fifo)	{
		switch (cmd->get_instruction_type()) {
		case InstructionType::LOAD_ON_CHIP_WEIGHTS:
		case InstructionType::LOAD_ON_CHIP_INPUTS:
		case InstructionType::LOAD_ON_CHIP_BIASES:
		case InstructionType::STORE_OFF_CHIP_OUTPUTS:
		case InstructionType::RESET_ON_CHIP_MEMORY:
			m_dma_engine.ProcessCommand(*cmd);
			break;
		case InstructionType::COMPUTE_CONV:
		case InstructionType::COMPUTE_MAX_POOL:
		case InstructionType::COMPUTE_DENSE:
		case InstructionType::COMPUTE_ROUTE:
		case InstructionType::COMPUTE_UPSAMPLE:
			m_compute_engine.ProcessCommand(*cmd);
			break;
		case InstructionType::IDLE:
			break;
		default:
			assert(false && "Worng instruction type. Should not get this place.");
			break;
		}
	}
}

void DC_ConvNet::DC_CNN_HW_AI_Accelerator::PushBackCommand(std::unique_ptr<DC_CNN_HW_Command>&& cmd) {
	m_command_fifo.emplace_back(std::move(cmd)); 
}

size_t DC_ConvNet::DC_CNN_HW_AI_Accelerator::PushBackLayerParams(const DC_HW_Params_Layer& params) {
	m_layer_params.push_back(params);
	return m_layer_params.size() - 1;
}

void DC_ConvNet::DC_CNN_HW_AI_Accelerator::SetGlobalParams(const DC_HW_Params_Global& params) {
	m_global_params = params;
}
