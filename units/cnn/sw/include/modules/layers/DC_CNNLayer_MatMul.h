/******************************************************************************
 * @file    DC_CNNLayer_MatMul.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Matrix multiplication layer for neural networks
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
     * @brief Matrix multiplication of two tensors from the layer output history
     *
     * Multiplies LHS × RHS tensors selected by relative indices. Optional
     * @p lhs_shape / @p rhs_shape override inferred dimensions for batched matmul.
     */
    class DC_CNNLayer_MatMul final : public DC_Layer {
    public:
        /**
         * @brief Constructs a MatMul layer
         *
         * @param relative_lhs_index Relative index of the left-hand operand
         * @param relative_rhs_index Relative index of the right-hand operand
         * @param lhs_shape Optional logical shape override for the LHS tensor
         * @param rhs_shape Optional logical shape override for the RHS tensor
         */
        DC_CNNLayer_MatMul(
            int relative_lhs_index,
            int relative_rhs_index,
            std::vector<int> lhs_shape = {},
            std::vector<int> rhs_shape = {});

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
         * @return true Always; MatMul reads two prior layer outputs
         */
        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Matrix-multiply two tensors from the layer output history
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Matrix product
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

    private:
        int m_relative_lhs_index;
        int m_relative_rhs_index;
        std::vector<int> m_lhs_shape;
        std::vector<int> m_rhs_shape;
    };

} // namespace DC_ConvNet
