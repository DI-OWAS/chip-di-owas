/******************************************************************************
 * @file    DC_CNNLayer_Concat.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Concatenation layer for neural networks
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
     * @brief Concatenate tensors along an axis from relative layers and optional constant
     *
     * Joins tensors selected by relative layer indices along @p axis. An optional
     * constant operand may be appended via load_constant_operand(). Output shape is
     * fixed at construction time.
     */
    class DC_CNNLayer_Concat final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Concat layer
         *
         * @param relative_layer_indices Relative indices into the layer output history
         * @param axis Logical axis along which tensors are concatenated
         * @param output_shape Expected logical output shape after concatenation
         */
        DC_CNNLayer_Concat(std::vector<int> relative_layer_indices, int axis, std::vector<int> output_shape);

        /**
         * @brief Load an optional constant operand tensor to concatenate
         *
         * @param operand Flat float buffer of the constant tensor
         * @param operand_shape Logical shape of the constant operand
         */
        void load_constant_operand(const std::vector<float>& operand, std::vector<int> operand_shape) {
            m_constant_operand = operand;
            m_constant_shape = std::move(operand_shape);
        }

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
         * @return true Always; Concat reads multiple prior layer outputs
         */
        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Concatenate selected layer outputs (and optional constant) along axis
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Concatenated result
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

    private:
        std::vector<int> m_relative_layer_indices;
        int m_axis;
        std::vector<int> m_output_shape;
        std::vector<float> m_constant_operand;
        std::vector<int> m_constant_shape;
    };

} // namespace DC_ConvNet
