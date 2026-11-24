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

#include <stdexcept>

namespace DC_ConvNet {

    /**
     * @brief Route layer implementation for feature concatenation and CSP blocks
     */
    class DC_FifoCommandBuilder_CNNLayer_Route final : public DC_Layer{
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
        explicit DC_FifoCommandBuilder_CNNLayer_Route(const std::vector<std::pair<int, DC_Tensor>>& layers, int groups = 1, int group_id = 0);

        /**
         * @brief Forward pass using layer outputs
         *
         * @param layer_outputs Output tensors from previous layers
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override {
            return layer_outputs[0];
        }

        /**
         * @brief Base forward method (not used for Route layer)
         */
        DC_Tensor forward(const DC_Tensor&) const override {
            throw std::logic_error("Base forward() called on DC_CNNLayer_Route. Use forward(layer_outputs) instead.");
        }

        std::vector<DC_HW_Params_Layer> build_layer_parameter_set(const std::vector<DC_Tensor>& inputs) const override;

        /**
         * @brief Builds a FIFO of hardware commands for this Route layer.
         *
         * Mirrors the behavior of the software `forward(layer_outputs)` method but instead of
         * executing on the CPU it creates a list of accelerator commands that can be pushed
         * to the hardware command FIFO.
         *
         * @param output        Output tensor descriptor that will be resized to the correct
         *                      output geometry (data is not written here, only shape).
         * @param layer_outputs Input tensors from previous layers used to derive parameters.
         * @return std::list<std::unique_ptr<DC_CNN_HW_Command>> List of HW commands.
         */
        std::list<std::unique_ptr<DC_CNN_HW_Command>> build_fifo_commands(
            DC_Tensor& output,
            const std::vector<DC_HW_Params_Layer>& layer_params) const override;

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

        std::vector<int> m_route_layer_indices;              // Indices of layers to route from
        mutable std::vector<int> m_input_sizes; // Total size of each input (h*w*c)
        int m_groups;                           // Number of groups for splitting
        int m_group_id;                         // Group ID to select
        mutable int m_outputs;                  // Total output size
        int m_output_height;                    // Height of the output tensor
        int m_output_width;                     // Width of the output tensor
        int m_output_channels;                  // Number of channels in the output tensor
    };

} // namespace DC_ConvNet 
