#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_Parameters.h"

#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Hardware compute command describing a route (concatenation/selection) instruction.
     *
     * Route is a pure data-movement op; there is no math, bias, or activation.
     * The parameters describe how to traverse the output space and which input
     * channels to pull from.
     */
    class DC_CNN_HW_ComputeRouteCommand final : public DC_CNN_HW_Command {
    public:
        /**
         * @brief Construct a route (data-movement) compute command
         *
         * @param instruction_params Parameters describing channel/output traversal
         */
        DC_CNN_HW_ComputeRouteCommand(const DC_HW_Params_Instruction& instruction_params) noexcept
            : DC_CNN_HW_Command(InstructionType::COMPUTE_ROUTE)
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