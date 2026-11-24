/******************************************************************************
 * @file    DC_CNNLayer_Relu.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   ReLU activation layer for neural networks
 * @version 1.0.0
 * @date    2026-07-01
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
     * @brief Rectified Linear Unit (ReLU) activation layer
     *
     * Applies the element-wise activation max(0, x) to the input tensor.
     */
    class DC_CNNLayer_Relu final : public DC_Layer {
    public:
        /**
         * @brief Constructs a ReLU activation layer
         */
        DC_CNNLayer_Relu() { m_layer_type = Layer_Type::RELU; }

        /**
         * @brief Performs forward propagation through the ReLU layer
         *
         * @param input Input tensor
         * @return DC_Tensor Output tensor after ReLU activation
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         *
         * @param layer_outputs Vector of input tensors
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error("Use forward(input) instead.");
        }
    };

} // namespace DC_ConvNet
