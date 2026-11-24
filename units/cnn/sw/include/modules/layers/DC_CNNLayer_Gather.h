/******************************************************************************
 * @file    DC_CNNLayer_Gather.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   ONNX Gather layer for neural networks
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
     * @brief Index-select slices along an axis (ONNX Gather)
     *
     * Selects elements/slices from input tensor(s) identified by relative indices,
     * using a fixed set of gather indices along @p axis. A single scalar index
     * removes that axis from the output shape.
     */
    class DC_CNNLayer_Gather final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Gather layer
         *
         * @param axis Axis along which indices are applied (supports negative indexing)
         * @param input_shape Logical ONNX shape of the gather input
         * @param indices Fixed gather indices along @p axis
         * @param relative_indices Relative indices into layer_outputs for the input tensor(s)
         */
        DC_CNNLayer_Gather(int axis, std::vector<int> input_shape, std::vector<int> indices, std::vector<int> relative_indices);

        /**
         * @brief Whether forward() requires the full layer_outputs history
         *
         * @return true Always; Gather reads prior layer outputs
         */
        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Forward propagation with a single input (not supported)
         *
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws; use forward(layer_outputs) instead
         */
        DC_Tensor forward(const DC_Tensor&) const override {
            throw std::logic_error("Use forward(layer_outputs) instead.");
        }

        /**
         * @brief Gather elements from tensors in the layer output history
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Gathered output tensor
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override;

    private:
        int m_axis;
        std::vector<int> m_input_shape;
        std::vector<int> m_indices;
        std::vector<int> m_relative_indices;
    };

} // namespace DC_ConvNet
