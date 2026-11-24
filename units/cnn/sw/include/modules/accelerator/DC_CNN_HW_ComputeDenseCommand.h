#pragma once

#include "DC_CNN_HW_Command.h"
#include "DC_CNN_activation_types.h"
#include "DC_PerformanceStats.h"

#include <cstdint>
#include <vector>

namespace DC_ConvNet {

	/**
	 * @brief Hardware compute command describing a dense (fully-connected) instruction.
	 *
	 * The command encapsulates parameters needed by a HW compute engine to process
	 * all output units for a given flattened input vector with a given weight matrix.
	 */
	class DC_CNN_HW_ComputeDenseCommand final : public DC_CNN_HW_Command {
	public:
		/**
		 * @brief Parameter block for a dense (fully-connected) HW compute instruction
		 */
		struct Params {
			size_t m_active_on_chip_input_buffer{ 0 };  /**< Index of the on-chip input buffer to use */

			/** @name Kernel / compute configuration */
			///@{
			int32_t m_input_channel_start_idx{ 0 }; /**< Reserved; currently always 0 */
			int32_t m_input_height{ 0 };            /**< Flattened input height */
			int32_t m_input_width{ 0 };             /**< Flattened input width */
			int32_t m_kernel_size{ 0 };             /**< Effective kernel size (typically 1 for dense) */
			int32_t m_stride{ 1 };                  /**< Stride */
			int32_t m_padding{ 0 };                 /**< Padding */
			int32_t m_num_input_channels{ 0 };      /**< Number of input features / channels */
			int32_t m_num_output_channels{ 0 };     /**< Number of output units */
			int32_t m_local_buffer_rows_capacity{ 0 }; /**< On-chip row buffer capacity */
			///@}

			/** @name Output traversal */
			///@{
			int32_t m_out_row_idx{ 0 };             /**< Current output row index */
			int32_t m_out_width{ 0 };               /**< Output width */
			int32_t m_out_channel_start_index{ 0 }; /**< Inclusive start of output-channel range */
			int32_t m_out_channel_end_index{ 0 };   /**< Exclusive end of output-channel range */
			///@}

			/** @name Fused ops configuration */
			///@{
			bool m_use_bias{ false };                                  /**< Whether bias is applied */
			ActivationType m_activation_type{ ActivationType::NONE }; /**< Fused activation */
			float m_leaky_alpha{ 0.0f };                               /**< Leaky ReLU alpha */
			///@}

			/** @name Execution policy */
			///@{
			StrideMode m_stride_mode_code{ StrideMode::MULTIPLY }; /**< Stride addressing mode */
			MEM_ORDER m_mem_order_code{ 0 };                       /**< Memory layout code */
			///@}

			LayerStats* m_layer_stats_ptr{ nullptr }; /**< Optional stats hook (debug only) */
		};

		/**
		 * @brief Construct a dense compute command
		 *
		 * @param params Dense instruction parameter block
		 */
		DC_CNN_HW_ComputeDenseCommand(Params params) noexcept
			: DC_CNN_HW_Command(InstructionType::COMPUTE_DENSE)
			, m_params(params) {}

		/**
		 * @brief Access the stored dense instruction parameters
		 * @return const Params& Parameter block
		 */
		const Params& get_params() const noexcept { return m_params; }

		/**
		 * @brief Serialize this command for the HW FIFO (currently a stub)
		 * @return std::vector<unsigned char> Encoded bytes
		 */
		std::vector<unsigned char> serialize() const override { return {}; }

	private:
		Params m_params;
	};

} // namespace DC_ConvNet