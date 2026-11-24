/******************************************************************************
 * @file    DC_CNNLayer_SkipLayerNorm.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Residual add followed by layer normalization
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
     * @brief Residual add of a skip connection followed by layer normalization
     *
     * Computes LayerNorm(skip + input) where both tensors are selected from the
     * layer output history via relative indices.
     */
    class DC_CNNLayer_SkipLayerNorm final : public DC_Layer {
    public:
        /**
         * @brief Constructs a SkipLayerNorm layer
         *
         * @param relative_skip_index Relative index of the residual/skip tensor
         * @param relative_input_index Relative index of the main input tensor
         */
        DC_CNNLayer_SkipLayerNorm(int relative_skip_index, int relative_input_index);

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
         * @return true Always; SkipLayerNorm reads two prior layer outputs
         */
        bool requires_layer_outputs() const override { return true; }

        /**
         * @brief Add skip and input tensors, then apply layer normalization
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Normalized residual output
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

    private:
        int m_relative_skip_index;
        int m_relative_input_index;
    };

} // namespace DC_ConvNet
