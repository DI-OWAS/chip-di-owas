#pragma once

#include "DC_OnChipMemory.h"
#include "DC_CNN_HW_ComputeConvCommand.h"
#include "DC_CNN_HW_ComputeMaxPoolCommand.h"
#include "DC_CNN_HW_ComputeDenseCommand.h"
#include "DC_CNN_HW_ComputeRouteCommand.h"
#include "DC_CNN_HW_ComputeUpSampleCommand.h"
#include "DC_PerformanceStats.h"

namespace DC_ConvNet {
    struct DC_Register_Bank;  // todo: forward declaration????

    /**
     * @class DC_CNN_HW_Compute_Engine
     * @brief Hardware compute engine model that executes fused CNN layer commands.
     *
     * The engine dispatches generic compute commands to specific handlers for
     * convolution, max pooling, dense, route, and upsample layers, operating
     * purely on `DC_OnChipMemory`. It can optionally collect per-layer statistics.
     */
	class DC_CNN_HW_Compute_Engine final {
	public:
        /**
         * @brief Construct the compute engine with its on-chip memory and register bank.
         * @param on_chip_memory On-chip memory used for all compute operations.
         * @param register_bank  Register bank used to track memory access statistics.
         */
        DC_CNN_HW_Compute_Engine(
            DC_OnChipMemory& on_chip_memory
            , DC_Register_Bank& register_bank
            , const DC_HW_Params_Global& global_params
            , const std::vector<DC_HW_Params_Layer>& layer_params);

        /**
         * @brief Process a generic compute command and dispatch to the appropriate handler.
         * @param command Base compute command to interpret.
         */
		void ProcessCommand(const DC_CNN_HW_Command& command);

        /**
         * @brief Attach a statistics collector to accumulate per-layer metrics.
         * @param stats Reference to the `LayerStats` structure to be updated.
         */
        void SetStatsCollector(LayerStats& stats) { m_stats = &stats; }

	private:
        /// Handle a convolution layer command, processed row by row.
        void ProcessCommandConvolutionLayerByRow(const DC_CNN_HW_ComputeConvCommand& command);

        /// Handle a max-pooling layer command, processed row by row.
        void ProcessCommandMaxPoolLayerByRow(const DC_CNN_HW_ComputeMaxPoolCommand& command);

        /// Handle a dense (fully-connected) layer command.
        void ProcessCommandDenseLayer(const DC_CNN_HW_ComputeDenseCommand& command);

        /// Handle a route layer command, combining multiple inputs row by row.
        void ProcessCommandRouteLayerByRow(const DC_CNN_HW_ComputeRouteCommand& command);

        /// Handle an upsample layer command, processed row by row.
        void ProcessCommandUpSampleLayerByRow(const DC_CNN_HW_ComputeUpSampleCommand& command);

        /// On-chip memory backing all compute operations.
        DC_OnChipMemory& m_on_chip_memory;

        /// Register bank used for tracking memory access statistics.
		DC_Register_Bank& m_register_bank;

        /// Global parameters for the currently executing network.
        const DC_HW_Params_Global& m_global_params;

        /// Layer parameters for the currently executing network.
        const std::vector<DC_HW_Params_Layer>& m_layer_params;

        //DC_CNN_HW_Compute_Engine m_parameters;

        /// Optional statistics collector (may be null when stats are disabled).
        LayerStats* m_stats = nullptr;
	};

} // namespace DC_ConvNet


