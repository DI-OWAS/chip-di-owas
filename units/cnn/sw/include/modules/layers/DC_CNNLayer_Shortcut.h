/******************************************************************************
 * @file    DC_CNNLayer_Shortcut.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Shortcut layer implementation for residual connections
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
#include "DC_CNN_activation_types.h"

#include <stdexcept>
#include <vector>

namespace DC_ConvNet {

    struct LayerStats;

    /**
     *  @brief Shortcut layer implementation for residual connections
     * 
     * Illustrates the Shortcut (Residual) Connection Mechanism
     * 
     * This diagram represents the [shortcut] logic from the .cfg file:
     * The identity path ("Skip") is added element-wise to the residual path.
     * @verbatim
     *          [Input Tensor] (e.g., Output of Layer N)
     *                |
     *      __________|__________
     *     |                     |
     * [Identity Path]     [Residual Path]
     *     |               (Deep Processing)
     *     |                     |
     *     |              [Convolutional] (Stride 1, Pad 1)
     *     |                     |
     *     |              [Batch Norm / Activation]
     *     |                     |
     *     |              [Convolutional] (Linear Activation)
     *     |                     |
     *     |__________ __________|
     *                |
     *          [Element-wise Sum] <--- This is the [shortcut] node
     *                |
     *         [ReLU Activation] (Optional, if defined in shortcut)
     *                |
     *          [Output Tensor]
     * @endverbatim
    */
    class DC_CNNLayer_Shortcut final : public DC_Layer {
    public:
        /**
         * @brief Constructs a shortcut layer
         *
         * @param from_layer_index The absolute index of the layer to add to the previous layer's output
         * @param activation Activation function to apply after addition
         */
        explicit DC_CNNLayer_Shortcut(int from_layer_index, ActivationType activation = ActivationType::NONE);

        /**
         * @brief Forward pass using layer outputs
         *
         * @param layer_outputs Output tensors from previous layers
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Base forward method (not used for Shortcut layer)
         */
        DC_Tensor forward(const DC_Tensor&) const override {
            throw std::logic_error("Base forward() called on DC_CNNLayer_Shortcut. Use forward(layer_outputs) instead.");
        }

    private:
        int m_from_layer_index;
        ActivationType m_activation;
    };

} // namespace DC_ConvNet
