/******************************************************************************
 * @file    DC_CNNLayer_Add.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Element-wise addition layer for neural networks
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
     * @brief Element-wise addition of relative layer outputs and optional constant operand
     *
     * Resolves tensors from previous layer outputs via relative indices and adds them
     * element-wise. An optional constant operand may be loaded and included in the sum.
     */
    class DC_CNNLayer_Add final : public DC_Layer {
    public:
        /**
         * @brief Constructs an element-wise Add layer
         *
         * @param relative_layer_indices Relative indices into the layer output history
         *        (negative indices count from the end)
         */
        explicit DC_CNNLayer_Add(std::vector<int> relative_layer_indices);

        /**
         * @brief Load a constant operand tensor to include in the element-wise sum
         *
         * @param operand Flat float buffer matching the resolved tensor element count
         */
        void load_operand(const std::vector<float>& operand) { m_operand = operand; }

        /**
         * @brief Forward propagation with a single input (not supported)
         *
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws; use forward(layer_outputs) instead
         */
        DC_Tensor forward(const DC_Tensor&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

        /**
         * @brief Whether forward() requires the full layer_outputs history
         *
         * @return true Always; Add reads multiple prior layer outputs
         */
        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Element-wise sum of tensors selected by relative indices
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Result of element-wise addition
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

    private:
        std::vector<int> m_relative_layer_indices;
        std::vector<float> m_operand;
    };

} // namespace DC_ConvNet
