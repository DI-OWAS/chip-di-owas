/******************************************************************************
 * @file    DC_CNNLayer_Mul.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Element-wise multiply layer for neural networks
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
#include <string>

namespace DC_ConvNet {

    /**
     * @brief Element-wise multiply by scalar, loaded operand, or another layer output
     *
     * Supports three modes: input × scalar factor, input × loaded constant tensor,
     * or tensor × tensor via a relative left-hand-side layer index.
     */
    class DC_CNNLayer_Mul final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Mul layer that scales the input by a scalar factor
         *
         * @param scalar_factor Multiplicative scale applied to the input (default 1.0)
         */
        explicit DC_CNNLayer_Mul(float scalar_factor = 1.0f);

        /**
         * @brief Constructs a Mul layer that multiplies against a prior layer output
         *
         * @param relative_lhs_index Relative index of the left-hand operand in layer_outputs
         */
        explicit DC_CNNLayer_Mul(int relative_lhs_index);

        /**
         * @brief Set the manifest name used to locate a constant operand during weight load
         *
         * @param name Constant tensor name from the network weight manifest
         */
        void set_const_tensor_name(std::string name) { m_const_tensor_name = std::move(name); }

        /**
         * @brief Get the constant tensor name used for weight loading
         *
         * @return const std::string& Manifest name of the constant operand
         */
        const std::string& const_tensor_name() const { return m_const_tensor_name; }

        /**
         * @brief Override the scalar multiplicative factor
         *
         * @param factor New scalar factor
         */
        void set_scalar_factor(float factor) { m_scalar_factor = factor; }

        /**
         * @brief Load a constant operand tensor for element-wise multiply
         *
         * @param operand Flat float buffer used as the second multiply operand
         */
        void load_operand(const std::vector<float>& operand) { m_operand = operand; }

        /**
         * @brief Forward pass: multiply input by scalar or loaded operand
         *
         * @param input Input tensor
         * @return DC_Tensor Element-wise product
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward pass using prior layer outputs as operands
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Element-wise product
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

        /**
         * @brief Whether forward() requires the full layer_outputs history
         *
         * @return true When a loaded/relative operand is used; otherwise false
         */
        bool requires_layer_outputs() const override {
            return m_use_loaded_operand;
        }

    private:
        bool m_use_loaded_operand = false;
        float m_scalar_factor = 1.0f;
        int m_relative_lhs_index = -1;
        std::string m_const_tensor_name;
        std::vector<float> m_operand;
    };

} // namespace DC_ConvNet
