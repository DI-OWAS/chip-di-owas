#pragma once
#include "DC_CNN_activation_types.h"
#include "DC_tensor.h"

#include <cstddef>

namespace DC_ConvNet
{
	struct LayerStats;

	struct DC_HW_Params_Global
	{
		// Memory order code (encodes MEM_ORDER).
		MEM_ORDER m_mem_order_code{0};
		// Number of input rows to load into on-chip memory.
		size_t m_number_of_rows_to_load{0};
	};

	struct DC_HW_Params_Layer
	{
		size_t m_layer_id{0};
		/// Base seek/index into external memory for weights.
		size_t m_weights_mem_seeks{0};
		/// Base seek/index into external memory for biases.
		size_t m_biases_mem_seeks{0};
		/// Base seek/index into external memory for inputs.
		size_t m_input_mem_seeks{0};
		/// Base seek/index into external memory for outputs.
		size_t m_output_mem_seeks{0};
		// Number of input and output channels.
		size_t m_num_input_channels{0};
		size_t m_num_output_channels{0};
		// Kernel size (spatial extent of the convolution filter).
		size_t m_kernel_size{0};
		// Input spatial dimensions.
		size_t m_input_height{0};
		size_t m_input_width{0};
		// Fused ops configuration
		float m_leaky_alpha{0.0f};
		bool m_use_bias{false};
		ActivationType m_activation_type{ActivationType::NONE};
		// Output spatial dimensions.
		size_t m_out_height{0};
		size_t m_out_width{0};
		// Stride and padding used when mapping outputs back to inputs.
		size_t m_stride{0};
		size_t m_padding{0};
		/// Encoded stride mode (matches StrideMode used in compute commands).
		StrideMode m_stride_mode_code{StrideMode::MULTIPLY};
		/// Index of the active off-chip input buffer to use.
		size_t m_active_off_chip_input_buffer{0}; // Index of the off-chip input buffer to use
		/// Index of the active on-chip input buffer to use.
		size_t m_active_on_chip_input_buffer{0}; // Index of the off-chip input buffer to use
		// Starting input channel index in off-chip memory to copy from.
		size_t m_off_chip_input_channel_start_idx{0};
		size_t m_route_channel_offset{0};
		LayerStats *m_layer_stats_ptr{nullptr};
	};

	struct DC_HW_Params_Instruction
	{
		size_t m_input_channel_start_idx{0}; // unused currently, is always 0, but reserved for future use in tailing by input channels
		// Output channel range [start, end) to be copied.
		size_t m_out_channel_start_index{0};
		size_t m_out_channel_end_index{0};
		// Output row to start loading for.
		size_t m_out_row_idx{0};
		size_t m_layer_id{0};
	};
}