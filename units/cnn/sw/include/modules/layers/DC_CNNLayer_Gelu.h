/******************************************************************************
 * @file    DC_CNNLayer_Gelu.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   GELU activation layer for neural networks
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
     * @brief Gaussian Error Linear Unit (GELU) activation layer
     *
     * Applies the element-wise activation 0.5 * x * (1 + erf(x / sqrt(2))) to the input.
     */
    class DC_CNNLayer_Gelu final : public DC_Layer {
    public:
        /**
         * @brief Constructs a GELU activation layer
         */
        DC_CNNLayer_Gelu();

        /**
         * @brief Performs forward propagation through the GELU layer
         *
         * @param input Input tensor
         * @return DC_Tensor Output tensor after GELU activation
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
