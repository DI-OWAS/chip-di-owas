/******************************************************************************
 * @file    DC_CNNLayer_Softmax.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Softmax layer implementation for neural networks
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

    struct LayerStats;

    /**
     * @brief Softmax layer that converts logits to probabilities
     *
     * This layer applies the softmax function to the input tensor, normalizing
     * the outputs to form a probability distribution.
     */
    class DC_CNNLayer_Softmax final : public DC_Layer {
    public:
        /**
         * @brief Constructs a softmax layer
         * 
         * Creates a layer that applies the softmax function to convert logits to probabilities.
         * No parameters are needed as this layer only performs normalization.
         */
        DC_CNNLayer_Softmax() { m_layer_type = Layer_Type::SOFTMAX; }

        /**
         * @brief Performs forward propagation through the softmax layer
         *
         * @param input Input tensor (logits)
         * @return DC_Tensor Output tensor (probabilities)
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         * 
         * This method is not supported for the softmax layer as it only accepts
         * a single input tensor.
         * 
         * @param layer_outputs Vector of input tensors
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

    };

} // namespace DC_ConvNet 
