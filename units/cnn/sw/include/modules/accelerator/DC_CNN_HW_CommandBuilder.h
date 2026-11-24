#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_ComputeDenseCommand.h"
#include "DC_CNN_HW_Parameters.h"

#include <memory>

namespace DC_ConvNet {

	/**
	 * @brief Factory for creating hardware command objects.
	 */
	class DC_CNN_HW_CommandBuilder final {
	public:
		/**
		 * @brief Create a convolution compute command
		 *
		 * @param instruction_params HW instruction parameters for one compute step
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned COMPUTE_CONV command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_compute_conv_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a max-pooling compute command
		 *
		 * @param instruction_params HW instruction parameters for one compute step
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned COMPUTE_MAX_POOL command
		 */
        static std::unique_ptr<DC_CNN_HW_Command> create_compute_max_pool_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a dense (fully-connected) compute command
		 *
		 * @param instruction_params Dense-specific instruction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned COMPUTE_DENSE command
		 */
        static std::unique_ptr<DC_CNN_HW_Command> create_compute_dense_command(const DC_CNN_HW_ComputeDenseCommand::Params& instruction_params);

		/**
		 * @brief Create a route compute command
		 *
		 * @param instruction_params HW instruction parameters for route/data movement
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned COMPUTE_ROUTE command
		 */
        static std::unique_ptr<DC_CNN_HW_Command> create_compute_route_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create an upsample compute command
		 *
		 * @param instruction_params HW instruction parameters for upsampling
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned COMPUTE_UPSAMPLE command
		 */
        static std::unique_ptr<DC_CNN_HW_Command> create_compute_upsample_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a DMA command that loads weights into on-chip memory
		 *
		 * @param instruction_params DMA transaction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned LOAD_ON_CHIP_WEIGHTS command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_dma_load_on_chip_weights_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a DMA command that loads inputs into on-chip memory
		 *
		 * @param instruction_params DMA transaction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned LOAD_ON_CHIP_INPUTS command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_dma_load_on_chip_inputs_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a DMA command that stores outputs to off-chip memory
		 *
		 * @param instruction_params DMA transaction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned STORE_OFF_CHIP_OUTPUTS command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_dma_store_off_chip_outputs_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a DMA command that loads biases into on-chip memory
		 *
		 * @param instruction_params DMA transaction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned LOAD_ON_CHIP_BIASES command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_dma_load_on_chip_biases_command(const DC_HW_Params_Instruction& instruction_params);

		/**
		 * @brief Create a command that resets on-chip memory buffers
		 *
		 * @param instruction_params Reset instruction parameters
		 * @return std::unique_ptr<DC_CNN_HW_Command> Owned RESET_ON_CHIP_MEMORY command
		 */
		static std::unique_ptr<DC_CNN_HW_Command> create_dma_on_chip_reset_command(const DC_HW_Params_Instruction& instruction_params);
	};

} // namespace DC_ConvNet
