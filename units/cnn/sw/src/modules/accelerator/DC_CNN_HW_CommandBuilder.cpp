#include "DC_CNN_HW_CommandBuilder.h"
#include "DC_CNN_HW_ComputeConvCommand.h"
#include "DC_CNN_HW_ComputeMaxPoolCommand.h"
#include "DC_CNN_HW_ComputeDenseCommand.h"
#include "DC_CNN_HW_ComputeRouteCommand.h"
#include "DC_CNN_HW_ComputeUpSampleCommand.h"
#include "DC_CNN_HW_DMA_Command.h"

using namespace DC_ConvNet;

// Create a convolution compute command
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_compute_conv_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_ComputeConvCommand(instruction_params));
}

// Create a max-pooling compute command
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_compute_max_pool_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_ComputeMaxPoolCommand(instruction_params));
}

// Create a dense compute command
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_compute_dense_command(const DC_CNN_HW_ComputeDenseCommand::Params& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_ComputeDenseCommand(instruction_params));
}

// Create a route compute command
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_compute_route_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_ComputeRouteCommand(instruction_params));
}

// Create an upsample compute command
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_compute_upsample_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_ComputeUpSampleCommand(instruction_params));
}

// Create a DMA command with explicit instruction type LOAD_WEIGHTS
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_weights_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_DMA_Command(InstructionType::LOAD_ON_CHIP_WEIGHTS, instruction_params));
}

// Create a DMA command with explicit instruction type LOAD_INPUTS
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_inputs_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_DMA_Command(InstructionType::LOAD_ON_CHIP_INPUTS, instruction_params));
}

// Create a DMA command with explicit instruction type LOAD_INPUTS
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_dma_store_off_chip_outputs_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_DMA_Command(InstructionType::STORE_OFF_CHIP_OUTPUTS, instruction_params));
}

// Create a DMA command with explicit instruction type LOAD_BIASES
std::unique_ptr<DC_CNN_HW_Command> DC_CNN_HW_CommandBuilder::create_dma_load_on_chip_biases_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_DMA_Command(InstructionType::LOAD_ON_CHIP_BIASES, instruction_params));
}

std::unique_ptr<DC_CNN_HW_Command> DC_ConvNet::DC_CNN_HW_CommandBuilder::create_dma_on_chip_reset_command(const DC_HW_Params_Instruction& instruction_params)
{
	return std::unique_ptr<DC_CNN_HW_Command>(new DC_CNN_HW_DMA_Command(InstructionType::RESET_ON_CHIP_MEMORY, instruction_params));
}
