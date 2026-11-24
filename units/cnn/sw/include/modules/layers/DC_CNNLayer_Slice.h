/******************************************************************************
 * @file    DC_CNNLayer_Slice.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Contiguous single-axis slice layer for neural networks
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
     * Contiguous single-axis Slice (step = 1).
     * Used by Depth-Anything to drop the CLS token on axis 1.
     */
    class DC_CNNLayer_Slice final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Slice layer that extracts [start, end) along one axis
         *
         * @param input_shape Logical shape of the input tensor
         * @param axis Axis to slice (supports negative indexing)
         * @param start Inclusive start index along @p axis
         * @param end Exclusive end index along @p axis
         */
        DC_CNNLayer_Slice(
            std::vector<int> input_shape,
            int axis,
            int start,
            int end);

        /**
         * @brief Extract the configured contiguous slice from the input
         *
         * @param input Input tensor
         * @return DC_Tensor Sliced output tensor
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
        std::vector<int> m_output_shape;
        int m_axis;
        int m_start;
    };

} // namespace DC_ConvNet
