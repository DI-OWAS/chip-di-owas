/******************************************************************************
 * @file    DC_CNNHelper.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Shared indexing and memory helpers for CNN compute kernels
 * @version 1.0.0
 * @date    2025-04-07
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (c) 2025 DC Vision Systems GmbH
 ******************************************************************************/

#pragma once

#include "DC_tensor.h"
#include "DC_PerformanceStats.h"
#include "DC_OnChipMemory.h"

#include <cassert>
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Calculates the input tensor array index based on memory layout and convolution parameters
     * 
     * This function is essential for CNN operations (convolution, pooling, etc.) as it determines
     * the correct index in the input tensor array for a given output position and kernel position.
     * It handles different stride modes, padding, and memory layouts (CHW vs HWC).
     * 
     * @param out_row_idx Row index in the output feature map
     * @param out_col_idx Column index in the output feature map
     * @param kernel_row_idx Row index within the kernel/filter
     * @param kernel_col_idx Column index within the kernel/filter
     * @param input_channel_idx Channel index in the input tensor
     * @param input_height Height of the input tensor
     * @param input_width Width of the input tensor
     * @param stride Stride value for the convolution operation
     * @param padding Padding applied to the input tensor
     * @param num_input_channels Total number of input channels
     * @param stride_mode How stride is applied (MULTIPLY or DIVIDE)
     * @param mem_order Memory layout order (CHW or HWC)
     * 
     * @return The calculated array index in the input tensor, or -1 if the position is invalid (in padding)
     * 
     * @note The function handles two stride modes:
     *       - MULTIPLY: input_pos = output_pos * stride + kernel_pos - padding
     *       - DIVIDE: input_pos = output_pos / stride + kernel_pos - padding
     * 
     * @note Memory layout considerations:
     *       - CHW: channel * height * width + row * width + col
     *       - HWC: row * width * channels + col * channels + channel
     * 
     * @warning Returns -1 for positions that fall outside the valid input bounds (padding areas)
     */
    static inline int calculate_input_array_index(
        int out_row_idx,
        int out_col_idx,
        int kernel_row_idx,
        int kernel_col_idx,
        int input_channel_idx,
        int input_height,
        int input_width,
        int stride,
        int padding,
        int num_input_channels,
        StrideMode stride_mode,
        MEM_ORDER mem_order
    ) {
        // Calculate input position with padding
        auto input_row_idx = 0, input_col_idx = 0;

        if (stride_mode == StrideMode::MULTIPLY)
        {
            input_row_idx = out_row_idx * stride + kernel_row_idx - padding;
            input_col_idx = out_col_idx * stride + kernel_col_idx - padding;
        }
        else if (stride_mode == StrideMode::DIVIDE)
        {
            input_row_idx = out_row_idx / stride + kernel_row_idx - padding;
            input_col_idx = out_col_idx / stride + kernel_col_idx - padding;
        }
        else
        {
            assert(false && "Unknown stride mode");
        }

        // Check if input position is valid (not in padding)
        if (!(input_row_idx >= 0 && input_row_idx < input_height &&
            input_col_idx >= 0 && input_col_idx < input_width)) {
            return -1;  // Invalid position
        }

        // Calculate input array index based on memory layout
        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: channel * height * width + row * width + col
            
            const int input_channel_idx_offset = (input_height * input_width);
            const int input_row_idx_offset = input_width;

            return  input_channel_idx * input_channel_idx_offset + 
                    input_row_idx * input_row_idx_offset +
                    input_col_idx;
        }
        else {
            // HWC format: row * width * channels + col * channels + channel
            
            const int input_row_idx_offset = (input_width * num_input_channels);
            const int input_col_idx_offset = num_input_channels;

            return  input_row_idx * input_row_idx_offset +
                    input_col_idx * input_col_idx_offset +
                    input_channel_idx;
        }
    }

    /**
     * @brief Map an output position back to an input index for DeConv2D (transposed convolution).
     *
     * For DeConv2D, out = in * stride + kernel - padding. The inverse is:
     * in = (out + padding - kernel) / stride, only when that difference is divisible
     * by stride and lands inside the input spatial bounds.
     */
    static inline int calculate_deconv_input_array_index(
        int out_row_idx,
        int out_col_idx,
        int kernel_row_idx,
        int kernel_col_idx,
        int input_channel_idx,
        int input_height,
        int input_width,
        int stride,
        int padding,
        int num_input_channels,
        MEM_ORDER mem_order
    ) {
        const int h_im = out_row_idx + padding - kernel_row_idx;
        const int w_im = out_col_idx + padding - kernel_col_idx;

        if (h_im < 0 || w_im < 0 || (h_im % stride) != 0 || (w_im % stride) != 0) {
            return -1;
        }

        const int input_row_idx = h_im / stride;
        const int input_col_idx = w_im / stride;

        if (!(input_row_idx >= 0 && input_row_idx < input_height &&
            input_col_idx >= 0 && input_col_idx < input_width)) {
            return -1;
        }

        if (mem_order == MEM_ORDER::CHW) {
            const int input_channel_idx_offset = (input_height * input_width);
            const int input_row_idx_offset = input_width;

            return input_channel_idx * input_channel_idx_offset +
                   input_row_idx * input_row_idx_offset +
                   input_col_idx;
        }

        const int input_row_idx_offset = (input_width * num_input_channels);
        const int input_col_idx_offset = num_input_channels;

        return input_row_idx * input_row_idx_offset +
               input_col_idx * input_col_idx_offset +
               input_channel_idx;
    }

    /**
     * @brief Load all biases from off-chip memory into on-chip memory.
     *
     * Copies bias values for all output channels from the provided off-chip bias
     * buffer into the accelerator's on-chip memory starting at @p on_chip_mem_seek.
     *
     * @param on_chip_memory On-chip memory interface to write biases into.
     * @param on_chip_mem_seek Base index in on-chip memory where biases are written.
     * @param off_chip_biases Off-chip bias buffer (length >= num_output_channels).
     * @param num_output_channels Number of output channels (biases) to load.
     * @return Number of biases written (equals @p num_output_channels).
     */
    static inline size_t load_biases_to_on_chip_memory(
        DC_OnChipMemory& on_chip_memory,
        size_t on_chip_mem_seek,
        const std::vector<float>& off_chip_biases,
        int num_output_channels)
    {
        for (int out_channel_idx = 0; out_channel_idx < num_output_channels; ++out_channel_idx) {
            on_chip_memory.Write(on_chip_mem_seek + static_cast<size_t>(out_channel_idx), off_chip_biases[static_cast<size_t>(out_channel_idx)]);
        }

        return num_output_channels;
    }

    /**
     * @brief Calculate on-chip input row offset for convolution operations
     * 
     * Maps output row coordinates to on-chip buffer row indices, handling stride, padding,
     * and kernel positioning for memory-efficient convolution processing.
     * 
     * @param out_row_idx Current output row being computed (0-based)
     * @param kernel_row_idx Kernel row offset (0 to kernel_size-1)
     * @param input_height Total height of input tensor
     * @param input_width Total width of input tensor
     * @param stride Convolution stride value
     * @param padding Row padding applied to input
     * @param num_input_channels Number of input channels
     * @param stride_mode How stride is applied (MULTIPLY or DIVIDE)
     * @param mem_order Memory layout (CHW or HWC)
     * @param local_buffer_rows_capacity Height capacity of circular buffer
     * 
     * @return On-chip buffer row offset, or -1 if invalid position
     */
    static inline int calculate_on_chip_input_row_offset(
        int out_row_idx,
        int kernel_row_idx,
        int input_height,
        int input_width,
        int stride,
        int padding,
        int num_input_channels,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        int local_buffer_rows_capacity
    ) {
        // Compute the global input row that this kernel position accesses
        int glob_row_idx = 0;
        if (stride_mode == StrideMode::MULTIPLY)
        {
            glob_row_idx = out_row_idx * stride + kernel_row_idx - padding;
        }
        else if (stride_mode == StrideMode::DIVIDE)
        {
            glob_row_idx = out_row_idx / stride + kernel_row_idx - padding;
        }
        else
        {
            assert(false && "Unknown stride mode");
        }

        // Check if input position is valid (not in padding)
        if (glob_row_idx < 0 || glob_row_idx >= input_height) {
            return -1;  // Invalid position
        }

        const auto local_row_idx = glob_row_idx % local_buffer_rows_capacity;
        
        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: channel * height * width + row * width + col
            return local_row_idx * input_width;
        }
        else {
            // HWC format: row * width * channels + col * channels + channel
            return local_row_idx * input_width * num_input_channels;
        }
    }


    /**
     * @brief Calculate on-chip input column offset for convolution operations
     * 
     * Maps output column coordinates to on-chip buffer column indices, handling stride, padding,
     * and channel positioning for memory-efficient convolution processing.
     * 
     * @param out_col_idx Current output column being computed (0-based)
     * @param kernel_col_idx Kernel column offset (0 to kernel_size-1)
     * @param input_width Total width of input tensor
     * @param stride Convolution stride value
     * @param padding Column padding applied to input
     * @param num_input_channels Number of input channels
     * @param stride_mode How stride is applied (MULTIPLY or DIVIDE)
     * @param mem_order Memory layout (CHW or HWC)
     * 
     * @return On-chip buffer column offset, or -1 if invalid position
     */
    static inline int calculate_on_chip_input_col_offset(
        int out_col_idx,
        int kernel_col_idx,
        int input_width,
        int stride,
        int padding,
        int num_input_channels,
        StrideMode stride_mode,
        MEM_ORDER mem_order
    ) {
        // Compute the global input column that this kernel position accesses
        int input_col_idx = 0;
        if (stride_mode == StrideMode::MULTIPLY)
        {
            input_col_idx = out_col_idx * stride + kernel_col_idx - padding;
        }
        else if (stride_mode == StrideMode::DIVIDE)
        {
            input_col_idx = out_col_idx / stride + kernel_col_idx - padding;
        }
        else
        {
            assert(false && "Unknown stride mode");
        }

        // Check if input position is valid (not in padding)
        if (!(input_col_idx >= 0 && input_col_idx < input_width)) {
            return -1;  // Invalid position
        }

        if (mem_order == MEM_ORDER::CHW)
        {
            return input_col_idx;
        }
        else
        {
            return input_col_idx * num_input_channels;
        }
    }

    /**
     * @brief Calculate on-chip input channel offset for convolution operations
     * 
     * Computes the memory offset for accessing a specific input channel within the
     * on-chip buffer, handling different memory layouts (CHW vs HWC) for efficient data access.
     * 
     * @param input_channel_idx Input channel index (0-based)
     * @param input_width Total width of input tensor
     * @param mem_order Memory layout (CHW or HWC)
     * @param local_buffer_rows_capacity Height capacity of circular buffer
     * 
     * @return Channel offset within on-chip buffer
     */
    static inline int calculate_on_chip_input_channel_offset(
        int input_channel_idx,
        int input_width,
        MEM_ORDER mem_order,
        int local_buffer_rows_capacity
    ) {
        if (mem_order == MEM_ORDER::CHW)
        {
            return input_channel_idx * local_buffer_rows_capacity * input_width;
        }

        return input_channel_idx;
    }

    /**
     * @brief Calculates the output tensor array index based on memory layout and output coordinates
     * 
     * This function is essential for CNN operations as it determines the correct index in the output
     * tensor array for storing computed values. It handles different memory layouts (CHW vs HWC)
     * and provides the proper indexing for output feature maps.
     * 
     * @param out_channel_idx Channel index in the output tensor
     * @param out_row_idx Row index in the output feature map
     * @param out_col_idx Column index in the output feature map
     * @param out_height Height of the output tensor
     * @param out_width Width of the output tensor
     * @param num_output_channels Total number of output channels
     * @param mem_order Memory layout order (CHW or HWC)
     * 
     * @return The calculated array index in the output tensor for storing the computed value
     * 
     * @note Memory layout considerations:
     *       - CHW: channel * height * width + row * width + col
     *       - HWC: row * width * channels + col * channels + channel
     * 
     * @note This function is typically used in conjunction with calculate_input_array_index()
     *       for complete CNN layer operations (convolution, pooling, etc.)
     * 
     * @warning Ensure all indices are within valid bounds before calling this function
     */
    static inline int calculate_output_array_index(
        int out_channel_idx,
        int out_row_idx,
        int out_col_idx,
        int out_height,
        int out_width,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: channel * height * width + row * width + col
            
            const int out_channel_idx_offset = (out_height * out_width);
            const int out_row_idx_offset = out_width;

            return  out_channel_idx * out_channel_idx_offset + 
                    out_row_idx * out_row_idx_offset +
                    out_col_idx;
        }
        else {
            // HWC format: row * width * channels + col * channels + channel
            
            const int out_row_idx_offset = (out_width * num_output_channels);
            const int out_col_idx_offset = num_output_channels;

            return  out_row_idx * out_row_idx_offset +
                    out_col_idx * out_col_idx_offset +
                    out_channel_idx;
        }
    }

    /**
     * @brief Calculate output tensor channel offset for a given memory layout
     *
     * Computes the base offset for the specified output channel in the output tensor,
     * respecting CHW or HWC memory layout.
     *
     * @param out_channel_idx Output channel index (0-based)
     * @param out_height Output tensor height
     * @param out_width Output tensor width
     * @param mem_order Memory layout (CHW or HWC)
     * @return Channel offset to add when addressing output tensor
     */
    static int calculate_output_out_channel_offset(
        int out_channel_idx,
        int out_height,
        int out_width,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return  out_channel_idx * (out_height * out_width);
        }

        return out_channel_idx;
    }

    /**
     * @brief Calculate output tensor row offset for a given memory layout
     *
     * Computes the base offset of a specific output row, taking into account
     * CHW or HWC memory layout and the number of output channels.
     *
     * @param out_row_idx Output row index (0-based)
     * @param out_width Output tensor width
     * @param num_output_channels Number of output channels
     * @param mem_order Memory layout (CHW or HWC)
     * @return Row offset to add when addressing output tensor
     */
    static int calculate_output_out_row_offset(
        int out_row_idx,
        int out_width,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return out_row_idx * out_width;
        }

        return  out_row_idx * (out_width * num_output_channels);
    }

    /**
     * @brief Calculate output tensor column offset for a given memory layout
     *
     * Computes the base offset of a specific output column, taking into account
     * CHW or HWC memory layout and the number of output channels.
     *
     * @param out_col_idx Output column index (0-based)
     * @param num_output_channels Number of output channels
     * @param mem_order Memory layout (CHW or HWC)
     * @return Column offset to add when addressing output tensor
     */
    static int calculate_output_out_col_offset(
        int out_col_idx,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return out_col_idx;
        }

        return out_col_idx * num_output_channels;
    }

    /**
     * @brief Calculates the weight tensor array index based on memory layout and convolution parameters
     * 
     * This function is essential for CNN convolution operations as it determines the correct index
     * in the weight/kernel tensor array for accessing specific filter weights. It handles different
     * memory layouts (CHW vs HWC) and provides proper indexing for multi-dimensional weight tensors.
     * 
     * @param input_channel_idx Input channel index for the weight connection
     * @param kernel_size Size of the kernel/filter (assumed square)
     * @param kernel_row_idx Row index within the kernel/filter
     * @param kernel_col_idx Column index within the kernel/filter
     * @param out_channel_idx Output channel index for the weight connection
     * @param num_input_channels Total number of input channels
     * @param num_output_channels Total number of output channels
     * @param mem_order Memory layout order (CHW or HWC)
     * 
     * @return The calculated array index in the weight tensor for accessing the specific weight value
     * 
     * @note Memory layout considerations:
     *       - CHW: out_channel_offset + input_channel_idx * (kernel_size²) + kernel_row_idx * kernel_size + kernel_col_idx
     *       - HWC: kernel_row_idx * (kernel_size * in_channels * out_channels) + kernel_col_idx * (in_channels * out_channels) + input_channel_idx * out_channels + out_channel_idx
     * 
     * @note This function is typically used in convolution operations to access the correct weight
     *       for the computation: output[out_channel][out_row][out_col] += input[in_channel][in_row][in_col] * weight[out_channel][in_channel][kernel_row][kernel_col]
     * 
     * @warning Ensure all indices are within valid bounds before calling this function
     */
    static inline int calculate_weight_array_index(
        int input_channel_idx,
        int kernel_size,
        int kernel_row_idx,
        int kernel_col_idx,
        int out_channel_idx,
        int num_input_channels,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: out_channel_offset + input_channel_idx * (kernel_size * kernel_size) + kernel_row_idx * kernel_size + kernel_col_idx

            const int out_channel_idx_offset = (num_input_channels * kernel_size * kernel_size);
            const int in_channel_idx_offset = (kernel_size * kernel_size);
            const int kernel_row_idx_offset = kernel_size;

            return  out_channel_idx * out_channel_idx_offset + 
                    input_channel_idx * in_channel_idx_offset +
                    kernel_row_idx * kernel_row_idx_offset +
                    kernel_col_idx;
        }
        else {
            // HWC format: kernel_row_idx * (kernel_size * in_channels * out_channels) + kernel_col_idx * (in_channels * out_channels) + input_channel_idx * out_channels + out_channel_idx

            const int kernel_row_idx_offset = (kernel_size * num_input_channels * num_output_channels);
            const int kernel_col_idx_offset = (num_input_channels * num_output_channels);
            const int in_channel_idx_offset = num_output_channels;

            return  kernel_row_idx * kernel_row_idx_offset +
                    kernel_col_idx * kernel_col_idx_offset +
                    input_channel_idx * in_channel_idx_offset +
                    out_channel_idx;
        }
    }

    /**
     * @brief Calculate on-chip weight output channel offset for convolution operations
     * 
     * Computes the memory offset for accessing a specific output channel's weights within the
     * on-chip buffer, handling different memory layouts (CHW vs HWC) for efficient weight access.
     * 
     * @param kernel_size Size of convolution kernel
     * @param out_channel_idx Output channel index (0-based)
     * @param num_input_channels Number of input channels
     * @param mem_order Memory layout (CHW or HWC)
     * 
     * @return Weight output channel offset within on-chip buffer
     */
    static inline int calculate_on_chip_weight_out_channel_offset(
        int kernel_size,
        int out_channel_idx,
        int num_input_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return out_channel_idx * (num_input_channels * kernel_size * kernel_size);
        }

        return out_channel_idx;
    }

    /**
     * @brief Calculate on-chip weight input channel offset for convolution operations
     * 
     * Computes the memory offset for accessing a specific input channel's weights within the
     * on-chip buffer, handling different memory layouts (CHW vs HWC) for efficient weight access.
     * 
     * @param input_channel_idx Input channel index (0-based)
     * @param kernel_size Size of convolution kernel
     * @param num_output_channels Number of output channels
     * @param mem_order Memory layout (CHW or HWC)
     * 
     * @return Weight input channel offset within on-chip buffer
     */
    static inline int calculate_on_chip_weight_in_channel_offset(
        int input_channel_idx,
        int kernel_size,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return input_channel_idx * (kernel_size * kernel_size);
        }

        return input_channel_idx * num_output_channels;
    }

    /**
     * @brief Calculate on-chip weight kernel row offset for convolution operations
     * 
     * Computes the memory offset for accessing a specific kernel row's weights within the
     * on-chip buffer, handling different memory layouts (CHW vs HWC) for efficient weight access.
     * 
     * @param kernel_size Size of convolution kernel
     * @param kernel_row_idx Kernel row index (0-based)
     * @param num_input_channels Number of input channels
     * @param num_output_channels Number of output channels
     * @param mem_order Memory layout (CHW or HWC)
     * 
     * @return Weight kernel row offset within on-chip buffer
     */
    static inline int calculate_on_chip_weight_kernel_row_offset(
        int kernel_size,
        int kernel_row_idx,
        int num_input_channels,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return kernel_row_idx * kernel_size;
        }

        return  kernel_row_idx * (kernel_size * num_input_channels * num_output_channels);
    }

    /**
     * @brief Calculate on-chip weight kernel column offset for convolution operations
     * 
     * Computes the memory offset for accessing a specific kernel column's weights within the
     * on-chip buffer, handling different memory layouts (CHW vs HWC) for efficient weight access.
     * 
     * @param kernel_col_idx Kernel column index (0-based)
     * @param num_input_channels Number of input channels
     * @param num_output_channels Number of output channels
     * @param mem_order Memory layout (CHW or HWC)
     * 
     * @return Weight kernel column offset within on-chip buffer
     */
    static inline int calculate_on_chip_weight_kernel_col_offset(
        int kernel_col_idx,
        int num_input_channels,
        int num_output_channels,
        MEM_ORDER mem_order
    ) {
        if (mem_order == MEM_ORDER::CHW) {
            return kernel_col_idx;
        }

        return kernel_col_idx * (num_input_channels * num_output_channels);
    }

    /**
     * @brief Store the result of a CNN layer operation in the output tensor with performance tracking
     * 
     * This function is essential for CNN operations as it stores computed values (from convolution,
     * pooling, activation, etc.) in the output tensor at the correct memory location. It handles
     * different memory layouts and tracks performance statistics for optimization and debugging.
     * 
     * @param output Reference to the output tensor where the result will be stored
     * @param val The computed value to store in the output tensor
     * @param out_channel_idx Channel index in the output tensor
     * @param out_row_idx Row index in the output feature map
     * @param out_col_idx Column index in the output feature map
     * @param out_height Height of the output tensor
     * @param out_width Width of the output tensor
     * @param stats Reference to LayerStats object for performance tracking
     * 
     * @note This function automatically calculates the correct memory index based on the output
     *       tensor's memory layout (CHW or HWC) using calculate_output_array_index()
     * 
     * @note Performance tracking: Records a MEMORY_STORE operation in the stats object for
     *       performance monitoring and optimization analysis
     * 
     * @note The function is designed to be used across different CNN layer types:
     *       - Convolution layers: storing computed feature maps
     *       - Pooling layers: storing max/average pooled values
     *       - Activation layers: storing activated values
     *       - Dense layers: storing fully connected outputs
     * 
     * @warning Ensure the output tensor has sufficient allocated memory before calling this function
     * 
     * @warning The function assumes all indices are within valid bounds - bounds checking should
     *          be performed by the calling layer implementation
     */
    static inline void store_result(DC_Tensor& output, 
        float val,
        int out_channel_idx,
        int out_row_idx, 
        int out_col_idx, 
        int out_height,
        int out_width,
        LayerStats& stats) {

        const int on_chip_out_ch_offset = calculate_output_out_channel_offset(
            out_channel_idx,
            out_height,
            out_width,
            output.m_mem_order
        );

        const int on_chip_out_row_offset = calculate_output_out_row_offset(
            out_row_idx,
            out_width,
            output.m_channels,
            output.m_mem_order
        );

        const int on_chip_out_col_offset = calculate_output_out_col_offset(
            out_col_idx,
            output.m_channels,
            output.m_mem_order
        );

        // Store results
        output.m_data[on_chip_out_row_offset + on_chip_out_col_offset + on_chip_out_ch_offset] = val;
        stats.record_operation(OperationType::MEMORY_STORE, 1);  // Storing max_val
    }

    /**
     * @brief Store a single output value into on-chip output buffer with stats.
     *
     * Computes on-chip offsets and writes the provided value to the on-chip output
     * memory, then records a MEMORY_STORE operation in the provided statistics.
     *
     * @param on_chip_memory On-chip memory interface where value is written.
     * @param on_chip_output_mem_seek Base seek for on-chip output buffer.
     * @param val Value to store.
     * @param out_channel_idx Output channel index.
     * @param out_col_idx Output column index.
     * @param out_width Output tensor width.
     * @param num_output_channels Number of output channels.
     * @param mem_order Memory layout (CHW or HWC).
     * @param stats Performance statistics collector.
     */
    static inline void store_to_on_chip_memory(DC_OnChipMemory& on_chip_memory,
        size_t on_chip_output_mem_seek,
        float val,
        int out_channel_idx,
        int out_col_idx,
        int out_width,
        int num_output_channels,
        MEM_ORDER mem_order,
        LayerStats& stats) {

        const int on_chip_out_ch_offset = calculate_output_out_channel_offset(
            out_channel_idx,
            1,
            out_width,
            mem_order
        );

        const int on_chip_out_col_offset = calculate_output_out_col_offset(
            out_col_idx,
            num_output_channels,
            mem_order
        );

        on_chip_memory.Write(on_chip_output_mem_seek + on_chip_out_col_offset + on_chip_out_ch_offset, val);

        // Store results
        stats.record_operation(OperationType::MEMORY_STORE, 1);
    }

    /**
     * @brief Flush a slice of on-chip output buffer to the global output tensor.
     *
     * Copies values for a range of output channels at a given output row from the
     * on-chip output buffer to the off-chip/global output tensor.
     *
     * @param output Destination output tensor (off-chip/global).
     * @param output_start_address Base offset in @p output where data will be written.
     * @param on_chip_memory Source on-chip memory interface.
     * @param on_chip_output_mem_seek Base seek for on-chip output buffer.
     * @param out_channel_start_index First output channel index to copy (inclusive).
     * @param out_channel_end_index Last output channel index to copy (exclusive).
     * @param num_output_channels Total number of output channels in the tensor.
     * @param out_row_idx Output row index being flushed.
     * @param out_height Output tensor height.
     * @param out_width Output tensor width.
     * @param mem_order Memory layout (CHW or HWC).
     */
    static inline void store_to_off_chip_memory(std::vector<float>& output,
		size_t output_start_address,
        DC_OnChipMemory& on_chip_memory,
        size_t on_chip_output_mem_seek,
        int out_channel_start_index,
        int out_channel_end_index,
        int num_output_channels,
        int out_row_idx,
        int out_height,
        int out_width,
        MEM_ORDER mem_order) {

        for (auto out_col_idx = 0; out_col_idx < out_width; ++out_col_idx)
        {
            for (auto out_channel_idx = out_channel_start_index; out_channel_idx < out_channel_end_index; ++out_channel_idx)
            {
                const int glob_out_ch_offset = calculate_output_out_channel_offset(
                    out_channel_idx,
                    out_height,
                    out_width,
                    mem_order
                );

                const int glob_out_row_offset = calculate_output_out_row_offset(
                    out_row_idx,
                    out_width,
                    num_output_channels,
                    mem_order
                );

                const int glob_out_col_offset = calculate_output_out_col_offset(
                    out_col_idx,
                    num_output_channels,
                    mem_order
                );

                const int on_chip_out_ch_offset = calculate_output_out_channel_offset(
                    out_channel_idx,
                    1,
                    out_width,
                    mem_order
                );

                const int on_chip_out_col_offset = calculate_output_out_col_offset(
                    out_col_idx,
                    num_output_channels,
                    mem_order
                );

                assert(output.size() > output_start_address + glob_out_row_offset + glob_out_col_offset + glob_out_ch_offset);

                // Store results
                output[output_start_address + glob_out_row_offset + glob_out_col_offset + glob_out_ch_offset] =
                    on_chip_memory.Read(on_chip_output_mem_seek + 0 + on_chip_out_col_offset + on_chip_out_ch_offset);

                // Store results
                //stats.record_operation(OperationType::MEMORY_STORE, 1);
            }
        }
    }

    /**
     * @brief Copies input rows to circular buffer for memory-efficient convolution.
     * 
     * This function manages a circular buffer to efficiently copy input rows needed for
     * convolution operations. It maintains a sliding window of input data in local memory,
     * reusing buffer rows to minimize memory transfers and optimize cache performance.
     * 
     * @param global_input Global input tensor buffer.
     * @param input_height Total height of input tensor
     * @param input_width Total width of input tensor  
     * @param num_input_channels Number of input channels
     * @param out_row_idx Current output row being processed
     * @param kernel_size Size of convolution kernel
     * @param stride Convolution stride value
     * @param padding Padding applied to input
     * @param mem_order Memory layout (CHW or HWC)
     * @param rows_capacity Height capacity of circular buffer.
     * @return Number of values written into on-chip memory.
     */
    static inline size_t
        load_input_rows_to_on_chip_memory(
        const std::vector<float>& global_input,
        DC_OnChipMemory& on_chip_memory,
        size_t on_chip_input_mem_seek,
        size_t active_on_chip_input_buffer,
        int input_height,
        int input_width,
        int num_input_channels,
        int off_chip_input_channel_start_idx,
        int out_row_idx,
        int kernel_size,
        int stride,
        int padding,
        StrideMode stride_mode,
        MEM_ORDER mem_order,
        const int rows_capacity)
    {
        int start_row;

        // Determine the base input row accessed by the top of the kernel for this output row
        if (stride_mode == StrideMode::MULTIPLY)
        {
            start_row = out_row_idx * stride - padding;
        }
        else if (stride_mode == StrideMode::DIVIDE)
        {
            start_row = out_row_idx / stride - padding;
        }
        else
        {
            assert(false && "Unknown stride mode");
        }

        // Choose a 3-row window that best covers the kernel's needed rows

        if (kernel_size > rows_capacity){
            // Kernel larger than buffer - center buffer on kernel
            start_row = start_row + (kernel_size - rows_capacity) / 2;
        }

        // Clamp start_row to valid input range [0, input_height - rows_capacity]
        if (start_row < 0) {
            start_row = 0;
        }

        if (out_row_idx == 0) {
            on_chip_memory.WriteLastLoadedInputRowIndex(active_on_chip_input_buffer, 0);
        }

        const auto adjusted_rows_capacity = std::min(input_height - start_row, rows_capacity);

        auto curr_row = on_chip_memory.ReadLastLoadedInputRowIndex(active_on_chip_input_buffer);
        size_t writes_count = 0;

        // Copy rows into local buffer preserving CHW/HWC layout
        for (; curr_row < start_row + adjusted_rows_capacity; ++curr_row) {
            const auto ir = curr_row % rows_capacity;
            const int src_row = curr_row;
            if (mem_order == MEM_ORDER::CHW) {
                // Destination: CHW with height=3 => index: c * (3 * W) + ir * W + x
                for (int c = 0; c < num_input_channels; ++c) {
                    const size_t channel_offset_global = static_cast<size_t>(c + off_chip_input_channel_start_idx) * static_cast<size_t>(input_height) * static_cast<size_t>(input_width);
                    const size_t src_row_offset = channel_offset_global + static_cast<size_t>(src_row) * static_cast<size_t>(input_width);
                    const size_t channel_offset_local = static_cast<size_t>(c) * static_cast<size_t>(rows_capacity) * static_cast<size_t>(input_width);
                    const size_t dst_row_offset_local = channel_offset_local + static_cast<size_t>(ir) * static_cast<size_t>(input_width);
                    for (int x = 0; x < input_width; ++x) {
                        const size_t src_idx = src_row_offset + static_cast<size_t>(x);
                        const size_t dst_idx = dst_row_offset_local + static_cast<size_t>(x);
                        on_chip_memory.Write(on_chip_input_mem_seek + dst_idx, global_input[src_idx]);
						writes_count++;
                    }
                }
            }
            else { // HWC
                // Destination: HWC with height=3 => index: ir * (W*C) + x * C + c
                const size_t dst_row_offset = static_cast<size_t>(ir) * static_cast<size_t>(input_width) * static_cast<size_t>(num_input_channels);;
                const size_t src_row_offset = static_cast<size_t>(src_row) * static_cast<size_t>(input_width) * static_cast<size_t>(num_input_channels);
                for (int x = 0; x < input_width; ++x) {
                    const size_t src_col_offset = static_cast<size_t>(x) * static_cast<size_t>(num_input_channels);
                    for (int c = 0; c < num_input_channels; ++c) {
                        const size_t src_idx = src_row_offset + src_col_offset + static_cast<size_t>(c + off_chip_input_channel_start_idx);
                        const size_t dst_idx = dst_row_offset + src_col_offset + static_cast<size_t>(c);
                        on_chip_memory.Write(on_chip_input_mem_seek + dst_idx, global_input[src_idx]);
						writes_count++;
                    }
                }
            }
        }

        on_chip_memory.WriteLastLoadedInputRowIndex(active_on_chip_input_buffer, curr_row);
		return writes_count;
    }

    /**
     * @brief Copies a chunk of weight filters from global storage to on-chip memory.
     * 
     * This function copies filters for a specified range of output channels from the global
     * weight storage into a fast local buffer (simulating on-chip/internal memory).
     * Each filter has shape [num_input_channels, kernel_size, kernel_size].
     * 
     * @param global_weights Global weight storage array.
     * @param num_input_channels Number of input channels per filter
     * @param num_output_channels Total number of output channels in the layer
     * @param kernel_size Size of the convolution kernel (assumed square)
     * @param out_channel_start_index First output channel index to copy (inclusive)
     * @param out_channel_end_index Last output channel index to copy (exclusive)
     * @param mem_order Memory layout order (CHW or HWC).
     * @param on_chip_memory On-chip memory interface where weights are written.
     * @param on_chip_mem_seek Base index in on-chip memory where the first weight is written.
     *
     * @note Weight layout:
     *       - CHW: [out_ch, in_ch, kernel_h, kernel_w]
     *         Index = out_ch * (in_ch * kh * kw) + in_ch * (kh * kw) + kh * kw + kw
     *       - HWC: [kernel_h, kernel_w, in_ch, out_ch]
     *         Index = kh * (kw * in_ch * out_ch) + kw * (in_ch * out_ch) + in_ch * out_ch + out_ch
     * 
     * @note Weights are written contiguously into on-chip memory for the specified
     *       output channel range: (out_channel_end - out_channel_start) * in_channels * kernel_size^2.
     *
     * @return Number of weights written into on-chip memory.
     */
    static inline size_t copy_weights_to_on_chip_memory(
        const std::vector<float>& global_weights,
        DC_OnChipMemory& on_chip_memory,
        size_t on_chip_mem_seek,
        int num_input_channels,
        int num_output_channels,
        int kernel_size,
        int out_channel_start_index,
        int out_channel_end_index,
        MEM_ORDER mem_order)
    {
        // Calculate the number of output channels in this chunk
        const int num_out_channels_chunk = out_channel_end_index - out_channel_start_index;
        
        // Calculate total elements needed in local buffer
        // Each output channel has: num_input_channels * kernel_size * kernel_size weights
        const size_t weights_per_output_channel = static_cast<size_t>(num_input_channels) * 
                                                   static_cast<size_t>(kernel_size) * 
                                                   static_cast<size_t>(kernel_size);
     
        size_t writes_count = 0;

        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: weights are organized as [out_ch][in_ch][kernel_h][kernel_w]
            // Global index: out_ch * (in_ch * kh * kw) + in_ch * (kh * kw) + kh * kw + kw
            // Local index: (out_ch - start) * (in_ch * kh * kw) + in_ch * (kh * kw) + kh * kw + kw
            
            const size_t out_channel_stride = weights_per_output_channel;
            const size_t in_channel_stride = static_cast<size_t>(kernel_size) * static_cast<size_t>(kernel_size);
            const size_t kernel_row_stride = static_cast<size_t>(kernel_size);

            for (int oc = out_channel_start_index; oc < out_channel_end_index; ++oc) {
                const int local_oc = oc - out_channel_start_index;
                
                for (int ic = 0; ic < num_input_channels; ++ic) {
                    for (int kh = 0; kh < kernel_size; ++kh) {
                        for (int kw = 0; kw < kernel_size; ++kw) {
                            // Global weight index
                            const size_t global_idx = static_cast<size_t>(oc) * out_channel_stride +
                                                      static_cast<size_t>(ic) * in_channel_stride +
                                                      static_cast<size_t>(kh) * kernel_row_stride +
                                                      static_cast<size_t>(kw);
                            
                            // Local buffer index
                            const size_t local_idx = static_cast<size_t>(local_oc) * out_channel_stride +
                                                     static_cast<size_t>(ic) * in_channel_stride +
                                                     static_cast<size_t>(kh) * kernel_row_stride +
                                                     static_cast<size_t>(kw);
                            
                            on_chip_memory.Write(on_chip_mem_seek + local_idx, global_weights[global_idx]);
							++writes_count;
                        }
                    }
                }
            }
        } else { // HWC format
            // HWC format: weights are organized as [kernel_h][kernel_w][in_ch][out_ch]
            // Global index: kh * (kw * in_ch * out_ch) + kw * (in_ch * out_ch) + in_ch * out_ch + out_ch
            // Local index: kh * (kw * in_ch * num_out_ch_chunk) + kw * (in_ch * num_out_ch_chunk) + in_ch * num_out_ch_chunk + (out_ch - start)
            
            const size_t global_kh_stride = static_cast<size_t>(kernel_size) * 
                                            static_cast<size_t>(num_input_channels) * 
                                            static_cast<size_t>(num_output_channels);
            const size_t global_kw_stride = static_cast<size_t>(num_input_channels) * 
                                            static_cast<size_t>(num_output_channels);
            const size_t global_ic_stride = static_cast<size_t>(num_output_channels);

            const size_t local_kh_stride = static_cast<size_t>(kernel_size) * 
                                           static_cast<size_t>(num_input_channels) * 
                                           static_cast<size_t>(num_out_channels_chunk);
            const size_t local_kw_stride = static_cast<size_t>(num_input_channels) * 
                                           static_cast<size_t>(num_out_channels_chunk);
            const size_t local_ic_stride = static_cast<size_t>(num_out_channels_chunk);

            for (int kh = 0; kh < kernel_size; ++kh) {
                for (int kw = 0; kw < kernel_size; ++kw) {
                    for (int ic = 0; ic < num_input_channels; ++ic) {
                        for (int oc = out_channel_start_index; oc < out_channel_end_index; ++oc) {
                            const int local_oc = oc - out_channel_start_index;
                            
                            // Global weight index
                            const size_t global_idx = static_cast<size_t>(kh) * global_kh_stride +
                                                      static_cast<size_t>(kw) * global_kw_stride +
                                                      static_cast<size_t>(ic) * global_ic_stride +
                                                      static_cast<size_t>(oc);
                            
                            // Local buffer index
                            const size_t local_idx = static_cast<size_t>(kh) * local_kh_stride +
                                                     static_cast<size_t>(kw) * local_kw_stride +
                                                     static_cast<size_t>(ic) * local_ic_stride +
                                                     static_cast<size_t>(local_oc);
                            
                            on_chip_memory.Write(on_chip_mem_seek + local_idx, global_weights[global_idx]);
							++writes_count;
                        }
                    }
                }
            }
        }
        return writes_count;
    }
}