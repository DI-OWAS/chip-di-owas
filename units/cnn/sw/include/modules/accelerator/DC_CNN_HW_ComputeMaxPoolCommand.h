#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_Parameters.h"

#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Hardware compute command describing a max-pooling instruction.
     *
     * The command encapsulates parameters needed by the HW compute engine to process
     * one output row for a subset of channels using a max-pooling window.
     */
    class DC_CNN_HW_ComputeMaxPoolCommand final : public DC_CNN_HW_Command {
    public:
        /**
         * @brief Construct a max-pooling compute command
         *
         * @param instruction_params Parameters describing one pooling compute step
         */
        DC_CNN_HW_ComputeMaxPoolCommand(const DC_HW_Params_Instruction& instruction_params) noexcept
            : DC_CNN_HW_Command(InstructionType::COMPUTE_MAX_POOL)
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