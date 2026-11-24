/******************************************************************************
 * @file    DC_CNNLayer_SoftmaxND.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   N-dimensional softmax over contiguous blocks
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
     * Last-axis Softmax over contiguous blocks.
     * Used by Depth-Anything attention: softmax(axis=-1) on scores.
     */
    class DC_CNNLayer_SoftmaxND final : public DC_Layer {
    public:
        /**
         * @brief Constructs an N-D Softmax layer
         *
         * @param axis Axis along which softmax is applied (supports negative indexing)
         * @param input_shape Logical ONNX shape used to size contiguous softmax blocks
         */
        DC_CNNLayer_SoftmaxND(int axis, std::vector<int> input_shape);

        /**
         * @brief Apply softmax over contiguous blocks along the configured axis
         *
         * @param input Input tensor (logits)
         * @return DC_Tensor Softmax-normalized output
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
        int m_axis_size;
    };

} // namespace DC_ConvNet
