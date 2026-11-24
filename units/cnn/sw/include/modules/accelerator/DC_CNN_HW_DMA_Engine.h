#pragma once

#include "DC_CNN_HW_DMA_Command.h"
#include "DC_CNN_HW_Command.h"
#include "DC_OnChipMemory.h"

#include "DC_HW_Memory_IF.h"

namespace DC_ConvNet {
	struct DC_Register_Bank;

	/**
	 * @class DC_CNN_HW_DMA_Engine
	 * @brief Simple DMA engine model that moves data between off-chip and on-chip memory.
	 *
	 * The engine interprets DMA commands, performs the corresponding transfers via
	 * `DC_HW_Memory_IF` into `DC_OnChipMemory`, and updates the `DC_Register_Bank`
	 * with memory access statistics. It provides a generic `ProcessCommand` entry
	 * point taking a `DC_CNN_HW_Command` plus an internal overload for DMA commands.
	 */
	class DC_CNN_HW_DMA_Engine final {
	public:

		/**
		 * @brief Construct the DMA engine with its memory back-ends and register bank.
		 * @param on_chip_memory Reference to the on-chip memory model.
		 * @param memory_if      Hardware-like interface to off-chip memory.
		 * @param register_bank  Register bank used to collect access statistics.
		 */
		DC_CNN_HW_DMA_Engine(DC_OnChipMemory& on_chip_memory
			, DC_HW_Memory_IF& memory_if
			, DC_Register_Bank& register_bank
			, const DC_HW_Params_Global& global_params
			, const std::vector<DC_HW_Params_Layer>& layer_params
		);

		/**
		 * @brief Process a generic hardware command; dispatches to DMA handling when applicable.
		 * @param command Base command to be interpreted.
		 */
		void ProcessCommand(const DC_CNN_HW_Command& command);

	private:
		/// Process a concrete DMA command.
		void ProcessCommand(const DC_CNN_HW_DMA_Command& command);
		
		/// On-chip memory that acts as the DMA destination/source.
		DC_OnChipMemory& m_on_chip_memory;

		/// Interface used to access off-chip (external) memory.
		DC_HW_Memory_IF& m_memory_if;

		/// Register bank for tracking DMA-related memory access statistics.
		DC_Register_Bank& m_register_bank;

		/// Global parameters for the currently executing network.
		const DC_HW_Params_Global& m_global_params;

		/// Layer parameters for the currently executing network.
		const std::vector<DC_HW_Params_Layer>& m_layer_params;

		/// Current seek/index into on-chip memory used for DMA transfers.
		size_t m_on_chip_mem_seek = 0u;

		/// Per-buffer flags indicating whether the first input load has been performed.
		std::vector<size_t> m_is_first_load_input = std::vector<size_t>(2, 0u);

		/// Flag indicating whether the first weights load has been performed.
		size_t m_is_first_load_weights = 0u;
	};

} // namespace DC_ConvNet


