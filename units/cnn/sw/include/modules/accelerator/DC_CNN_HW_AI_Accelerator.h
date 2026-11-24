#pragma once

#include "DC_CNN_HW_Command.h"
#include <DC_CNN_HW_DMA_Engine.h>
#include <DC_CNN_HW_Compute_Engine.h>
#include "DC_OnChipMemory.h"
#include "DC_HW_Memory_IF.h"
#include "DC_Register_Bank.h"

namespace DC_ConvNet {

	/**
	 * @class DC_CNN_HW_AI_Accelerator
	 * @brief Top-level CNN hardware accelerator model orchestrating DMA and compute engines.
	 *
	 * The accelerator owns on-chip memory, a DMA engine, a compute engine, and a simple
	 * command FIFO. Commands pushed into the FIFO are processed in order, moving data
	 * between off-chip and on-chip memory and executing CNN layer computations.
	 */
	class DC_CNN_HW_AI_Accelerator final {
	public:
		/**
		 * @brief Construct the accelerator bound to a given off-chip memory interface.
		 * @param memory_if Hardware-like interface used by the internal DMA engine.
		 */
		DC_CNN_HW_AI_Accelerator(DC_HW_Memory_IF& memory_if);

		/**
		 * @brief Process all commands currently queued in the FIFO.
		 *
		 * Commands are popped in FIFO order and dispatched either to the DMA engine
		 * or the compute engine depending on their instruction type.
		 */
		void ProcessCommandFifo();

		/**
		 * @brief Enqueue a new hardware command for later execution.
		 * @param cmd Unique pointer to a dynamically allocated command.
		 */
		void PushBackCommand(std::unique_ptr<DC_CNN_HW_Command>&& cmd);

		size_t PushBackLayerParams(const DC_HW_Params_Layer& params);

		void SetGlobalParams(const DC_HW_Params_Global& params);
		/**
		 * @brief Clear the pending command FIFO without executing its contents.
		 */
		void ResetCommandFifo()
		{
			m_command_fifo.clear();
			m_layer_params.clear();
		}

		// Debugging only
		/**
		 * @brief Attach a statistics collector to the underlying compute engine.
		 * @param stats Reference to a `LayerStats` structure to be updated.
		 */
		void SetStatsCollector(LayerStats& stats) { m_compute_engine.SetStatsCollector(stats); }
		
	private:

		/// On-chip memory shared between DMA and compute engines.
		DC_OnChipMemory m_on_chip_memory;

		/// FIFO of pending hardware commands to be executed.
		std::list<std::unique_ptr<DC_CNN_HW_Command>> m_command_fifo;

		/// DMA engine responsible for off-chip ↔ on-chip transfers.
		DC_CNN_HW_DMA_Engine m_dma_engine;

		/// Compute engine responsible for executing CNN layer commands.
		DC_CNN_HW_Compute_Engine m_compute_engine;

		/// Register bank used to track memory access statistics.
		DC_Register_Bank m_register_bank;

		DC_HW_Params_Global m_global_params;

		std::vector<DC_HW_Params_Layer> m_layer_params;
	};
} // namespace DC_ConvNet


