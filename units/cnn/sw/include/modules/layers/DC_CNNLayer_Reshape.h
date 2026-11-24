/******************************************************************************
 * @file    DC_CNNLayer_Reshape.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Reshape layer for neural networks
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
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Change tensor shape without altering data (supports one inferred -1 dim)
     *
     * Reinterprets the input buffer as @p target_shape while preserving element count.
     * At most one dimension may be -1 and is inferred from the total element count.
     */
    class DC_CNNLayer_Reshape final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Reshape layer
         *
         * @param input_shape Logical shape of the input tensor
         * @param target_shape Desired output shape (may contain a single -1)
         */
        DC_CNNLayer_Reshape(std::vector<int> input_shape, std::vector<int> target_shape);

        /**
         * @brief Reshape the input tensor to the configured target shape
         *
         * @param input Input tensor
         * @return DC_Tensor Tensor with the target shape
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

    private:
        std::vector<int> m_input_shape;
        std::vector<int> m_target_shape;
    };

} // namespace DC_ConvNet
