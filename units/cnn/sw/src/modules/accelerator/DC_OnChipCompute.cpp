#include "DC_OnChipCompute.h"
#include "DC_CNNHelper.h"
#include "DC_CNN_axillary.h"

#include <limits>

float DC_ConvNet::DC_OnChipCompute::compute_kernel_conv2D(
    const DC_OnChipMemory& on_chip_input
	, size_t on_chip_input_mem_address_offset
	, size_t on_chip_weights_mem_address_offset
    , int num_output_channels_in_tail
    , int out_channel_idx
    , int out_row_idx
    , int out_col_idx
    , const DC_HW_Params_Global& global_params
    , const DC_HW_Params_Layer& layer_params
    , const DC_HW_Params_Instruction& instruction_params
    , StrideMode stride_mode
    , MEM_ORDER mem_order
    , LayerStats& stats)
{
    const int weight_out_ch_offset = calculate_on_chip_weight_out_channel_offset(
        layer_params.m_kernel_size,
        out_channel_idx,
        layer_params.m_num_input_channels,
        mem_order
    );

    auto conv_accumulator = 0.0f;

    // For each on_chip_input channel
    for (auto input_channel_idx = instruction_params.m_input_channel_start_idx; input_channel_idx < layer_params.m_num_input_channels; ++input_channel_idx)
    {
        const int weight_in_ch_offset = calculate_on_chip_weight_in_channel_offset(
            input_channel_idx,
            layer_params.m_kernel_size,
            num_output_channels_in_tail,
            mem_order
        );

        for (auto kernel_row_idx = 0u; kernel_row_idx < layer_params.m_kernel_size; ++kernel_row_idx)
        {
            const int weight_kernel_row_offset = calculate_on_chip_weight_kernel_row_offset(
                layer_params.m_kernel_size,
                kernel_row_idx,
                layer_params.m_num_input_channels,
                num_output_channels_in_tail,
                mem_order
            );

            // Convolve kernel with on_chip_input at current position
            for (auto kernel_col_idx = 0u; kernel_col_idx < layer_params.m_kernel_size; ++kernel_col_idx)
            {

                const int weight_kernel_col_offset = calculate_on_chip_weight_kernel_col_offset(
                    kernel_col_idx,
                    layer_params.m_num_input_channels,
                    num_output_channels_in_tail,
                    mem_order
                );

                const int on_chip_row_offset = calculate_on_chip_input_row_offset(
                    out_row_idx,
                    kernel_row_idx,
                    layer_params.m_input_height,
                    layer_params.m_input_width,
                    layer_params.m_stride,
                    layer_params.m_padding,
                    layer_params.m_num_input_channels,
                    stride_mode,
                    mem_order,
                    global_params.m_number_of_rows_to_load
                );

                const int on_chip_col_offset = calculate_on_chip_input_col_offset(
                    out_col_idx,
                    kernel_col_idx,
                    layer_params.m_input_width,
                    layer_params.m_stride,
                    layer_params.m_padding,
                    layer_params.m_num_input_channels,
                    stride_mode,
                    mem_order
                );

                const int on_chip_ch_offset = calculate_on_chip_input_channel_offset(
                    input_channel_idx,
                    layer_params.m_input_width,
                    mem_order,
                    global_params.m_number_of_rows_to_load
                );

                if (on_chip_row_offset < 0 || on_chip_col_offset < 0 || on_chip_ch_offset < 0) {
                    continue;
                }

                // Process valid position
                {
                    uint32_t input_channel_address = on_chip_input_mem_address_offset + on_chip_row_offset + on_chip_col_offset + on_chip_ch_offset;
                    uint32_t weight_address = on_chip_weights_mem_address_offset + weight_out_ch_offset + weight_in_ch_offset + weight_kernel_row_offset + weight_kernel_col_offset;

                    // Get on_chip_input value
                    const auto input_val = on_chip_input.Read(input_channel_address);
                    // Get weight value
                    const auto weight_val = on_chip_input.Read(weight_address);

                    conv_accumulator += input_val * weight_val;

                    stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load on_chip_input value
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load on_chip_weights value
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1);  // Multiplication
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);  // Addition (sum +=)
                }
            }
        }
    }

    return conv_accumulator;
}

void DC_ConvNet::DC_OnChipCompute::compute_instruction_conv2D(
    DC_OnChipMemory& on_chip_memory
    , size_t on_chip_input_address_offset
    , size_t on_chip_weights_mem_address_offset
    , size_t on_chip_biases_address_offset
    , size_t on_chip_output_address_offset
    , const DC_HW_Params_Global& global_params
    , const DC_HW_Params_Layer& layer_params
    , const DC_HW_Params_Instruction& instruction_params
    , LayerStats& stats)
{
    // COMPUTE_INSTRUCTION: process all columns and channels for this row
    for (auto out_col_idx = 0u; out_col_idx < layer_params.m_out_width; ++out_col_idx)
    {
        for (auto out_channel_idx = instruction_params.m_out_channel_start_index; out_channel_idx < instruction_params.m_out_channel_end_index; ++out_channel_idx)
        {
            auto num_output_channels_in_tail = instruction_params.m_out_channel_end_index - instruction_params.m_out_channel_start_index;
            auto out_channel_idx_in_tail = out_channel_idx - instruction_params.m_out_channel_start_index;

            /*
            Notes:
            data storage structure of weights as in diagram (2D matrix with 9 elements each,flattened from 4D structure)
            use local data for weight set

            use internal memory for input rows
            */

            auto value = compute_kernel_conv2D(
                on_chip_memory,
                on_chip_input_address_offset,
				on_chip_weights_mem_address_offset,
                num_output_channels_in_tail,
                out_channel_idx_in_tail,
                instruction_params.m_out_row_idx,
                out_col_idx,
				global_params,
				layer_params,
                instruction_params,
                layer_params.m_stride_mode_code,
                global_params.m_mem_order_code,
                stats
            );

            // Fused bias
            // Branch check for bias
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
            if (layer_params.m_use_bias)
            {
                // Load bias value for this channel once per element
                value += on_chip_memory.Read(on_chip_biases_address_offset + out_channel_idx);
                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
            }

            // Fused activation
            value = activate_value(layer_params.m_activation_type, value, layer_params.m_leaky_alpha, stats);

            // Store final result
            store_to_on_chip_memory(on_chip_memory,
				on_chip_output_address_offset,
                value,
                out_channel_idx,
                out_col_idx,
                layer_params.m_out_width,
                layer_params.m_num_output_channels,
                global_params.m_mem_order_code,
                stats);
        }
    }
}

float DC_ConvNet::DC_OnChipCompute::compute_kernel_max_pool(
    const DC_OnChipMemory& on_chip_input
	, size_t on_chip_input_address_offset
    , int num_output_channels
    , int out_channel_idx
    , int out_row_idx
    , int out_col_idx
    , const DC_HW_Params_Global& global_params
    , const DC_HW_Params_Layer& layer_params
    , StrideMode stride_mode
    , MEM_ORDER mem_order
    , LayerStats& stats) {

    const int on_chip_ch_offset = calculate_on_chip_input_channel_offset(
        out_channel_idx,
        layer_params.m_input_width,
        mem_order,
        global_params.m_number_of_rows_to_load
    );

    // Initialize max tracking
    auto max_val = -std::numeric_limits<float>::max();

    // Pooling window loop
    for (auto kernel_row_idx = 0u; kernel_row_idx < layer_params.m_kernel_size; ++kernel_row_idx)
    {
        for (auto kernel_col_idx = 0u; kernel_col_idx < layer_params.m_kernel_size; ++kernel_col_idx)
        {
            const int on_chip_row_offset = calculate_on_chip_input_row_offset(
                out_row_idx,
                kernel_row_idx,
                layer_params.m_input_height,
                layer_params.m_input_width,
                layer_params.m_stride,
                layer_params.m_padding,
                num_output_channels,
                stride_mode,
                mem_order,
                global_params.m_number_of_rows_to_load
            );

            const int on_chip_col_offset = calculate_on_chip_input_col_offset(
                out_col_idx,
                kernel_col_idx,
                layer_params.m_input_width,
                layer_params.m_stride,
                layer_params.m_padding,
                num_output_channels,
                stride_mode,
                mem_order
            );

            if (on_chip_row_offset < 0 || on_chip_col_offset < 0 || on_chip_ch_offset < 0) {
                continue;
            }

            const auto input_val = on_chip_input.Read(on_chip_input_address_offset + on_chip_row_offset + on_chip_col_offset + on_chip_ch_offset);

            // Update max value and index if necessary
            if (input_val > max_val) {
                max_val = input_val;
            }

            stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Loading from input
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);  // Comparison
        }
    }

    return max_val;
}

float DC_ConvNet::DC_OnChipCompute::compute_kernel_dense(
    const DC_OnChipMemory& on_chip_input
	, size_t on_chip_input_address_offset
    , size_t on_chip_weights_mem_address_offset
    , int num_output_channels_in_tail
    , int out_channel_idx
    , int out_row_idx
    , int out_col_idx
    , const DC_CNN_HW_ComputeDenseCommand::Params& compute_params
    , StrideMode stride_mode
    , MEM_ORDER mem_order
    , LayerStats& stats) {
    auto sum = 0.0f;

    // For each input channel
    for (auto input_channel_idx = compute_params.m_input_channel_start_idx; input_channel_idx < compute_params.m_num_input_channels; ++input_channel_idx)
    {
        // Convolve kernel with input at current position
        for (auto kernel_row_idx = 0; kernel_row_idx < compute_params.m_kernel_size; ++kernel_row_idx)
        {
            for (auto kernel_col_idx = 0; kernel_col_idx < compute_params.m_kernel_size; ++kernel_col_idx)
            {
                const int weight_out_ch_offset = calculate_on_chip_weight_out_channel_offset(
                    compute_params.m_kernel_size,
                    out_channel_idx,
                    compute_params.m_num_input_channels,
                    mem_order
                );

                const int weight_in_ch_offset = calculate_on_chip_weight_in_channel_offset(
                    input_channel_idx,
                    compute_params.m_kernel_size,
                    num_output_channels_in_tail,
                    mem_order
                );

                const int weight_kernel_row_offset = calculate_on_chip_weight_kernel_row_offset(
                    compute_params.m_kernel_size,
                    kernel_row_idx,
                    compute_params.m_num_input_channels,
                    num_output_channels_in_tail,
                    mem_order
                );

                const int weight_kernel_col_offset = calculate_on_chip_weight_kernel_col_offset(
                    kernel_col_idx,
                    compute_params.m_num_input_channels,
                    num_output_channels_in_tail,
                    mem_order
                );

                const int on_chip_row_offset = calculate_on_chip_input_row_offset(
                    out_row_idx,
                    kernel_row_idx,
                    compute_params.m_input_height,
                    compute_params.m_input_width,
                    compute_params.m_stride,
                    compute_params.m_padding,
                    compute_params.m_num_input_channels,
                    stride_mode,
                    mem_order,
                    compute_params.m_local_buffer_rows_capacity
                );

                const int on_chip_col_offset = calculate_on_chip_input_col_offset(
                    out_col_idx,
                    kernel_col_idx,
                    compute_params.m_input_width,
                    compute_params.m_stride,
                    compute_params.m_padding,
                    compute_params.m_num_input_channels,
                    stride_mode,
                    mem_order
                );

                const int on_chip_ch_offset = calculate_on_chip_input_channel_offset(
                    input_channel_idx,
                    compute_params.m_input_width,
                    mem_order,
                    compute_params.m_local_buffer_rows_capacity
                );

                if (on_chip_row_offset < 0 || on_chip_col_offset < 0 || on_chip_ch_offset < 0) {
                    continue;
                }
				const int input_array_index = on_chip_input_address_offset + on_chip_row_offset + on_chip_col_offset + on_chip_ch_offset;
				const int weight_array_index = on_chip_weights_mem_address_offset + weight_out_ch_offset + weight_in_ch_offset + weight_kernel_row_offset + weight_kernel_col_offset;

                // Get on_chip_input value
                const auto input_val = on_chip_input.Read(input_array_index);

                // Get weight value
                const auto weight_val = on_chip_input.Read(weight_array_index);

                sum += input_val * weight_val;

                stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load input value
                stats.record_operation(OperationType::MEMORY_LOAD, 1);  // Load weight value
                stats.record_operation(OperationType::ARITHMETIC_MUL, 1);  // Multiplication
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);  // Addition (sum +=)
            }
        }
    }

    return sum;
}

void DC_ConvNet::DC_OnChipCompute::compute_instruction_max_pool(
    DC_OnChipMemory& on_chip_memory
	, size_t on_chip_input_address_offset
	, size_t on_chip_output_address_offset
    , const DC_HW_Params_Global& global_params
    , const DC_HW_Params_Layer& layer_params
    , const DC_HW_Params_Instruction& instruction_params
    , LayerStats& stats) {
    for (auto out_col_idx = 0u; out_col_idx < layer_params.m_out_width; ++out_col_idx)
    {
        for (auto out_channel_idx = 0u; out_channel_idx < layer_params.m_num_output_channels; ++out_channel_idx)
        {
            // Compute maximum value in pooling window
            const auto value = compute_kernel_max_pool(
                on_chip_memory,
				on_chip_input_address_offset,
                layer_params.m_num_output_channels,
                out_channel_idx,
                instruction_params.m_out_row_idx,
				out_col_idx,
				global_params,
				layer_params,
                StrideMode::MULTIPLY,
                global_params.m_mem_order_code,
                stats);

            store_to_on_chip_memory(on_chip_memory,
                on_chip_output_address_offset,
                value,
                out_channel_idx,
                out_col_idx,
                layer_params.m_out_width,
                layer_params.m_num_output_channels,
                global_params.m_mem_order_code,
                stats);
        }
    }
}

void DC_ConvNet::DC_OnChipCompute::compute_instruction_dense(
    DC_OnChipMemory& on_chip_memory
	, size_t on_chip_input_address_offset
    , size_t on_chip_weights_mem_address_offset
    , size_t on_chip_biases_address_offset
	, size_t on_chip_output_address_offset
    , const DC_CNN_HW_ComputeDenseCommand::Params& compute_params
    , LayerStats& stats) {

    const auto out_col_idx = 0;

    // For each output unit
    for (auto out_channel_idx = compute_params.m_out_channel_start_index; out_channel_idx < compute_params.m_out_channel_end_index; ++out_channel_idx)
    {
        auto num_output_channels_in_tail = compute_params.m_out_channel_end_index - compute_params.m_out_channel_start_index;
        auto out_channel_idx_in_tail = out_channel_idx - compute_params.m_out_channel_start_index;

        auto value = compute_kernel_dense(
            on_chip_memory,
			on_chip_input_address_offset,
			on_chip_weights_mem_address_offset,
            num_output_channels_in_tail,
            out_channel_idx_in_tail,
            compute_params.m_out_row_idx,
            out_col_idx,
            compute_params,
            compute_params.m_stride_mode_code,
            compute_params.m_mem_order_code,
            stats
        );

        // Branch check for bias
        stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
        // Initialize with bias if enabled
        if (compute_params.m_use_bias) {
            value += on_chip_memory.Read(on_chip_biases_address_offset + out_channel_idx);
            stats.record_operation(OperationType::MEMORY_LOAD, 1);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
        }

        // Fused activation
        value = activate_value(compute_params.m_activation_type, value, compute_params.m_leaky_alpha, stats);

        // Store final result
        store_to_on_chip_memory(on_chip_memory,
			on_chip_output_address_offset,
            value,
            out_channel_idx,
            out_col_idx,
            compute_params.m_out_width,
            compute_params.m_num_output_channels,
            compute_params.m_mem_order_code,
            stats);
    }
}

void DC_ConvNet::DC_OnChipCompute::compute_instruction_route(
    DC_OnChipMemory& on_chip_memory,
    size_t on_chip_input_0_address_offset,
    size_t on_chip_input_1_address_offset,
    size_t on_chip_output_address_offset,
    const DC_HW_Params_Global& global_params,
    const DC_HW_Params_Layer& layer_params,
    const DC_HW_Params_Instruction& instruction_params,
    LayerStats& stats)
{
    for (auto out_col_idx = 0u; out_col_idx < layer_params.m_out_width; ++out_col_idx)
    {
        for (auto out_channel_idx = instruction_params.m_out_channel_start_index; 
            out_channel_idx < instruction_params.m_out_channel_end_index; ++out_channel_idx)
        {
            auto input_channel_idx = out_channel_idx;
			auto on_chip_input_address_offset = on_chip_input_0_address_offset;

            if (layer_params.m_active_on_chip_input_buffer == 1u &&
                out_channel_idx >= (layer_params.m_num_output_channels - layer_params.m_num_input_channels))
            {
                input_channel_idx = out_channel_idx - (layer_params.m_num_output_channels - layer_params.m_num_input_channels);
				on_chip_input_address_offset = on_chip_input_1_address_offset;
            }

            const int on_chip_row_offset = calculate_on_chip_input_row_offset(
                instruction_params.m_out_row_idx,
                0,
                layer_params.m_input_height,
                layer_params.m_input_width,
                1,
                0,
                layer_params.m_num_input_channels,
                layer_params.m_stride_mode_code,
                global_params.m_mem_order_code,
                global_params.m_number_of_rows_to_load
            );

            const int on_chip_col_offset = calculate_on_chip_input_col_offset(
                out_col_idx,
                0,
                layer_params.m_input_width,
                1,
                0,
                layer_params.m_num_input_channels,
                layer_params.m_stride_mode_code,
                global_params.m_mem_order_code
            );

            const int on_chip_ch_offset = calculate_on_chip_input_channel_offset(
                input_channel_idx,
                layer_params.m_input_width,
                global_params.m_mem_order_code,
                global_params.m_number_of_rows_to_load
            );

            if (on_chip_row_offset < 0 || on_chip_col_offset < 0 || on_chip_ch_offset < 0) {
                continue;
            }

            auto value = on_chip_memory.Read(on_chip_input_address_offset + on_chip_row_offset + on_chip_col_offset + on_chip_ch_offset);

            // Store final result
            store_to_on_chip_memory(on_chip_memory,
				on_chip_output_address_offset,
                value,
                out_channel_idx,
                out_col_idx,
                layer_params.m_out_width,
                layer_params.m_num_output_channels,
                global_params.m_mem_order_code,
                stats);
        }
    }
}

void DC_ConvNet::DC_OnChipCompute::compute_instruction_upsample(
    DC_OnChipMemory& on_chip_memory,
	size_t on_chip_input_address_offset,
	size_t on_chip_output_address_offset,
    const DC_HW_Params_Global& global_params,
    const DC_HW_Params_Layer& layer_params,
    const DC_HW_Params_Instruction& instruction_params,
    LayerStats& stats)
{
    const int on_chip_row_offset = calculate_on_chip_input_row_offset(
        instruction_params.m_out_row_idx,
        0,
        layer_params.m_input_height,
        layer_params.m_input_width,
        layer_params.m_stride,
        0,
        layer_params.m_num_input_channels,
        layer_params.m_stride_mode_code,
        global_params.m_mem_order_code,
        global_params.m_number_of_rows_to_load
    );

    for (auto out_col_idx = 0u; out_col_idx < layer_params.m_out_width; ++out_col_idx)
    {
        for (auto out_channel_idx = 0u; out_channel_idx < layer_params.m_num_output_channels; ++out_channel_idx)
        {
            const int on_chip_col_offset = calculate_on_chip_input_col_offset(
                out_col_idx,
                0,
                layer_params.m_input_width,
                layer_params.m_stride,
                0,
                layer_params.m_num_input_channels,
                layer_params.m_stride_mode_code,
                global_params.m_mem_order_code
            );

            const int on_chip_ch_offset = calculate_on_chip_input_channel_offset(
                out_channel_idx,
                layer_params.m_input_width,
                global_params.m_mem_order_code,
                global_params.m_number_of_rows_to_load
            );

            if (on_chip_row_offset < 0 || on_chip_col_offset < 0 || on_chip_ch_offset < 0) {
                continue;
            }

            auto value = on_chip_memory.Read(on_chip_input_address_offset + on_chip_row_offset + on_chip_col_offset + on_chip_ch_offset);

            // Store final result
            store_to_on_chip_memory(on_chip_memory,
				on_chip_output_address_offset,
                value,
                out_channel_idx,
                out_col_idx,
                layer_params.m_out_width,
                layer_params.m_num_output_channels,
                global_params.m_mem_order_code,
                stats);
        }
    }
}