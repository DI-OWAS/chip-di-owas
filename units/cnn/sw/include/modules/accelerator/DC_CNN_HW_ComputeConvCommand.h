#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_Parameters.h"

#include <vector>

namespace DC_ConvNet {

	/**
	 * @brief Hardware compute command describing a fused compute instruction.
	 *
	 * The command encapsulates parameters needed by a HW compute engine to process
	 * one output row for a subset of output channels with a given kernel setup.
	 * The byte layout produced by serialize() is little-endian and starts with
	 * a one-byte opcode equal to InstructionType::COMPUTE.
	 */
	class DC_CNN_HW_ComputeConvCommand final : public DC_CNN_HW_Command {
	public:
		/**
		 * @brief Construct a convolution compute command
		 *
		 * @param instruction_params Parameters describing one fused compute step
		 */
		DC_CNN_HW_ComputeConvCommand(const DC_HW_Params_Instruction& instruction_params) noexcept
			: DC_CNN_HW_Command(InstructionType::COMPUTE_CONV)
			, m_instruction_params(instruction_params) {}

		/**
		 * @brief Access the stored instruction parameters
		 * @return const DC_HW_Params_Instruction& Instruction parameter block
		 */
		const DC_HW_Params_Instruction& get_params() const noexcept { return m_instruction_params; }

		/**
		 * @brief Serialize this command for the HW FIFO (currently a stub)
		 * @return std::vector<unsigned char> Encoded bytes
		 */
		std::vector<unsigned char> serialize() const override { return {}; }

	private:
		DC_HW_Params_Instruction m_instruction_params;
	};

} // namespace DC_ConvNet