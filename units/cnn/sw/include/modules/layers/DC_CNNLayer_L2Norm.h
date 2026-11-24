/******************************************************************************
 * @file    DC_CNNLayer_L2Norm.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   L2Norm layer implementation for neural networks
 * @version 1.0.0
 * @date    2025-04-07
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

    struct LayerStats;

    /**
     * @brief L2 Normalization layer implementation
     * 
     * Performs L2 normalization across the channel dimension.
     * 
     * @verbatim
     * Projects the feature vector onto a unit hypersphere (length = 1.0).
     *
     *    [Input Vector (v)]        [Magnitude Calculation]        [Unit Vector (v̂)]
     *     (512 dimensions)          ||v||₂ = √(Σ xᵢ²)              (v / ||v||₂)
     * 
     *           |                         |                         |
     *     [ x₁ , x₂ , ... ]               V                 [ x̂₁ , x̂₂ , ... ]
     *           |                +-----------------+                |
     *           |                |  Square All     |                |
     *           +--------------> |  Sum & SQRT     | -------------->+
     *                            +-----------------+                |
     *                                     |                         |
     *                                     V                         V
     *                             (Single Scalar)           (Final Embedding)
     * @endverbatim
     * @note L2 Normalization transforms the raw feature vector into a point on a 
     *       unit sphere. This ensures that the distance between two different 
     *       embeddings is determined solely by the angle (direction) of the 
     *       features, making it compatible with Cosine Similarity for tasks 
     *       like feature matching and re-identification.
     */
    class DC_CNNLayer_L2Norm final : public DC_Layer {
    public:
        /**
         * @brief Constructs an L2 normalization layer
         */
        DC_CNNLayer_L2Norm();

        /**
         * @brief Performs forward propagation through the L2 normalization layer
         *
         * @param input Input tensor
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error("Use forward(input) instead.");
        }
    };

} // namespace DC_ConvNet