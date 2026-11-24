#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_Parameters.h"

#include <vector>

namespace DC_ConvNet {

	/**
	 * @brief DMA command for transferring data between off-chip and on-chip memory.
	 *
	 * The command encapsulates a single DMA transaction. The base instruction type
	 * should be set to either LOAD_INPUTS or LOAD_WEIGHTS depending on the payload.
	 * A direction_code is provided to allow explicit STORE (on-chip to off-chip)
	 * semantics if needed by the control logic.
	 */
	class DC_CNN_HW_DMA_Command final : public DC_CNN_HW_Command {
	public:
		/**
		 * @brief Construct a DMA transfer command
		 *
		 * @param type Instruction type (load weights/inputs/biases or store outputs)
		 * @param instruction_params DMA transaction parameters
		 */
		DC_CNN_HW_DMA_Command(InstructionType type, const DC_HW_Params_Instruction& instruction_params) noexcept
			: DC_CNN_HW_Command(type)
			, m_instruction_params(instruction_params) {}

		/**
		 * @brief Access the stored DMA instruction parameters
		 * @return const DC_HW_Params_Instruction& Instruction parameter block
		 */
		const DC_HW_Params_Instruction& get_params() const noexcept { return m_instruction_params; }

		/**
		 * @brief Serialize this DMA command for the HW FIFO (currently a stub)
		 * @return std::vector<unsigned char> Encoded bytes
		 */
		std::vector<unsigned char> serialize() const override { return {}; }

	private:
		DC_HW_Params_Instruction m_instruction_params;
	};

} // namespace DC_ConvNet


