/******************************************************************************
 * @file    DC_CNNLayer_Route.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Route layer implementation for neural networks
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

#include "DC_layer.h"
#include "DC_CNNComputeKernel.h"

#include <stdexcept>

namespace DC_ConvNet {

    struct LayerStats;

    /**
     * @brief Route layer implementation for feature concatenation and CSP blocks
     */
    class DC_CNNLayer_Route final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a route layer
         *
         * Creates a layer that concatenates or routes outputs from previous layers.
         * Can perform either basic routing (concatenating whole feature maps) or
         * grouped routing (slicing feature maps by channel groups).
         *
         * @param layers Vector of layer indices to concatenate from
         * @param groups Number of groups for grouped routing (default: 1)
         * @param group_id Group ID to select in grouped routing (default: 0)
         */
        explicit DC_CNNLayer_Route(const std::vector<std::pair<int, DC_Tensor>>& layers, int groups = 1, int group_id = 0);

        /**
         * @brief Forward pass using layer outputs
         *
         * @param layer_outputs Output tensors from previous layers
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Base forward method (not used for Route layer)
         */
        DC_Tensor forward(const DC_Tensor&) const override {
            throw std::logic_error("Base forward() called on DC_CNNLayer_Route. Use forward(layer_outputs) instead.");
        }

    private:

        /**
         * @brief Calculates input sizes and output dimensions
         * 
         * Computes the total size of each input tensor and determines the output
         * dimensions based on the input tensors and group configuration.
         * 
         * @param layers Vector of layer indices and their corresponding tensors
         */
        void calculate_input_sizes_and_output(const std::vector<std::pair<int, DC_Tensor>>& layers);

        /**
         * @brief Determines which input layer an output channel belongs to
         * 
         * Maps an output channel index to the corresponding input layer and returns
         * the input tensor reference and the calculated input channel index.
         * 
         * @param out_channel Output channel index
         * @param channels_per_group_per_layer Vector of channels per group for each input layer
         * @param start_channels_per_layer Vector of start channel indices for each input layer
         * @param layer_outputs Vector of all layer output tensors
         * @return std::pair<const DC_Tensor&, int> First: input tensor reference, Second: input_channel
         */
        std::pair<const DC_Tensor&, int> determine_source_layer(
            int out_channel,
            const std::vector<int>& channels_per_group_per_layer,
            const std::vector<int>& start_channels_per_layer,
            const std::vector<DC_Tensor>& layer_outputs) const;

        float compute_kernel(
            const float* const ,
            const float* const ,
            const DC_ComputeKernelParams* const ,
            StrideMode ,
            MEM_ORDER ,
            LayerStats& 
        ) const {
			return 0.f; // Not used in this context
        }


        /**
         * @brief Computes kernel operation for route layer
         * 
         * Performs routing operation at a specific spatial position for a given
         * output channel. This function implements the core routing operation,
         * which simply passes through input values from specified input channels
         * to corresponding output channels without any computation.
         * 
         * The function routes input data from input_channel_start_idx to
         * out_channel_idx, essentially performing a channel selection and
         * pass-through operation. The weights parameter is ignored for routing.
         * 
         * @param input Input tensor containing feature maps
         * @param weights Pointer to weight vector (ignored for routing)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (ignored for routing)
         * @param mem_order Memory order (HWC or CHW) for index calculation
         * @param stats Performance statistics recorder for operation counting
         * @return float Routed input value from specified input channel
         */
        float compute_kernel(
            const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats) const;

        std::vector<int> m_layers;              // Indices of layers to route from
        mutable std::vector<int> m_input_sizes; // Total size of each input (h*w*c)
        int m_groups;                           // Number of groups for splitting
        int m_group_id;                         // Group ID to select
        mutable int m_outputs;                  // Total output size
        int m_output_height;                    // Height of the output tensor
        int m_output_width;                     // Width of the output tensor
        int m_output_channels;                  // Number of channels in the output tensor
    };

} // namespace DC_ConvNet 
