/******************************************************************************
 * @file    DC_OnChipCompute.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   On-chip compute operations for convolutional layers
 * @version 1.0.0
 * @date    2025-01-01
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

#include "DC_OnChipMemory.h"
#include "DC_PerformanceStats.h"
#include "DC_CNN_HW_ComputeDenseCommand.h"
#include "DC_CNN_HW_Parameters.h"
#include "DC_tensor.h"

 namespace DC_ConvNet {

     /**
      * @class DC_OnChipCompute
      * @brief On-chip compute operations for convolutional and related layers.
      *
      * This helper class encapsulates the core primitive operations performed on-chip,
      * including convolution kernels, max pooling, dense kernels, and the corresponding
      * high-level "instruction" style calls that operate on on-chip memory buffers.
      */
     class DC_OnChipCompute {
     public:

        /**
         * @brief Compute a single convolution output element on-chip.
         *
         * Evaluates the convolution kernel (plus optional fused operations) for one
         * output position and channel, using on-chip input and weight buffers.
         *
         * @param on_chip_input               On-chip memory containing inputs.
         * @param on_chip_input_address_offset      Base seek/index into input buffer.
         * @param active_on_chip_input_buffer Logical input buffer identifier.
         * @param on_chip_weights_address_offset    Base seek/index into weights buffer.
         * @param num_output_channels_in_tail Number of output channels in current tail.
         * @param out_channel_idx             Output channel index to compute.
         * @param out_row_idx                 Output row index to compute.
         * @param out_col_idx                 Output column index to compute.
         * @param compute_params              Convolution compute parameters.
         * @param stride_mode                 Stride mode policy.
         * @param mem_order                   Memory layout order.
         * @param stats                       Layer statistics collector.
         * @return Computed output value for the given position and channel.
         */
        static float compute_kernel_conv2D(
            const DC_OnChipMemory& on_chip_input,
            size_t on_chip_input_address_offset,
            size_t on_chip_weights_address_offset,
            int num_output_channels_in_tail,
            int out_channel_idx,
            int out_row_idx,
            int out_col_idx,
            const DC_HW_Params_Global& global_params,
            const DC_HW_Params_Layer& layer_params,
            const DC_HW_Params_Instruction& instruction_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats
        );

        /**
         * @brief Execute a full convolution instruction on-chip.
         *
         * Traverses the required output region and writes results into the on-chip
         * output buffer, applying bias and activation as configured.
         *
         * @param on_chip_memory           On-chip memory with inputs/weights/biases/outputs.
         * @param on_chip_input_address_offset   Base seek for input tensor.
         * @param on_chip_weights_address_offset Base seek for weight tensor.
         * @param on_chip_biases_address_offset  Base seek for bias tensor.
         * @param on_chip_output_address_offset  Base seek for output tensor.
         * @param compute_params           Convolution compute parameters.
         * @param stats                    Layer statistics collector.
         */
        static void compute_instruction_conv2D(
            DC_OnChipMemory& on_chip_memory
            , size_t on_chip_input_address_offset
            , size_t on_chip_weights_address_offset
            , size_t on_chip_biases_address_offset
            , size_t on_chip_output_address_offset
			, const DC_HW_Params_Global& global_params
			, const DC_HW_Params_Layer& layer_params
            , const DC_HW_Params_Instruction& instruction_params
            , LayerStats& stats);

        /**
         * @brief Compute a single max-pooling output element on-chip.
         *
         * @param on_chip_input          On-chip memory containing inputs.
         * @param on_chip_input_address_offset Base seek/index into input buffer.
         * @param num_output_channels    Total number of output channels.
         * @param out_channel_idx        Output channel index to compute.
         * @param out_row_idx            Output row index to compute.
         * @param out_col_idx            Output column index to compute.
         * @param compute_params         Max-pooling compute parameters.
         * @param stride_mode            Stride mode policy.
         * @param mem_order              Memory layout order.
         * @param stats                  Layer statistics collector.
         * @return Max-pooled value for the given position and channel.
         */
        static float compute_kernel_max_pool(
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
            , LayerStats& stats);

        /**
         * @brief Compute a single dense (fully-connected) output element on-chip.
         *
         * @param on_chip_input               On-chip memory containing inputs.
         * @param on_chip_input_address_offset      Base seek/index into input buffer.
         * @param on_chip_weights_address_offset    Base seek/index into weights buffer.
         * @param active_on_chip_input_buffer Logical input buffer identifier.
         * @param num_output_channels_in_tail Number of output channels in current tail.
         * @param out_channel_idx             Output channel index to compute.
         * @param out_row_idx                 Output row index (typically 0 for dense).
         * @param out_col_idx                 Output column index (typically 0 for dense).
         * @param compute_params              Dense compute parameters.
         * @param stride_mode                 Stride mode policy.
         * @param mem_order                   Memory layout order.
         * @param stats                       Layer statistics collector.
         * @return Computed dense output value.
         */
        static float compute_kernel_dense(
            const DC_OnChipMemory& on_chip_input
            , size_t on_chip_input_address_offset
            , size_t on_chip_weights_address_offset
            , int num_output_channels_in_tail
            , int out_channel_idx
            , int out_row_idx
            , int out_col_idx
            , const DC_CNN_HW_ComputeDenseCommand::Params& compute_params
            , StrideMode stride_mode
            , MEM_ORDER mem_order
            , LayerStats& stats
        );

        /**
         * @brief Execute a full max-pooling instruction on-chip.
         */
        static void compute_instruction_max_pool(DC_OnChipMemory& on_chip_memory,
            size_t on_chip_input_address_offset,
            size_t on_chip_output_address_offset,
            const DC_HW_Params_Global& global_params,
            const DC_HW_Params_Layer& layer_params,
            const DC_HW_Params_Instruction& instruction_params,
            LayerStats& stats);

        /**
         * @brief Execute a full dense (fully-connected) instruction on-chip.
         */
        static void compute_instruction_dense(DC_OnChipMemory& on_chip_memory,
            size_t on_chip_input_address_offset,
            size_t on_chip_weights_address_offset,
            size_t on_chip_biases_address_offset,
            size_t on_chip_output_address_offset,
            const DC_CNN_HW_ComputeDenseCommand::Params& compute_params,
            LayerStats& stats);

        /**
         * @brief Execute a route instruction on-chip, combining two input buffers.
         */
        static void compute_instruction_route(DC_OnChipMemory& on_chip_memory,
            size_t on_chip_input_0_address_offset,
            size_t on_chip_input_1_address_offset,
            size_t on_chip_output_address_offset,
            const DC_HW_Params_Global& global_params,
            const DC_HW_Params_Layer& layer_params,
            const DC_HW_Params_Instruction& instruction_params,
            LayerStats& stats);

        /**
         * @brief Execute an upsample instruction on-chip.
         */
        static void compute_instruction_upsample(DC_OnChipMemory& on_chip_memory,
            size_t on_chip_input_address_offset,
            size_t on_chip_output_address_offset,
            const DC_HW_Params_Global& global_params,
            const DC_HW_Params_Layer& layer_params,
            const DC_HW_Params_Instruction& instruction_params,
            LayerStats& stats);
     };
 
 } // namespace DC_ConvNet
 
 