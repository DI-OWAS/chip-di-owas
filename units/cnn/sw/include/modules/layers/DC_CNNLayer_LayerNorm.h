/******************************************************************************
 * @file    DC_CNNLayer_LayerNorm.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Layer normalization with learnable scale and shift
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
     * @brief Layer normalization with learnable scale (gamma) and shift (beta)
     *
     * Normalizes over the last @p normalized_size elements per logical row, then
     * applies affine transform y = gamma * (x - mean) / sqrt(var + eps) + beta.
     */
    class DC_CNNLayer_LayerNorm final : public DC_Layer {
    public:
        /**
         * @brief Constructs a LayerNorm layer
         *
         * @param relative_input_index Relative index of the input in layer_outputs
         * @param normalized_size Number of trailing elements normalized per row
         * @param epsilon Small value added to variance for numerical stability (default 1e-5)
         */
        DC_CNNLayer_LayerNorm(int relative_input_index, int normalized_size, float epsilon = 1e-5f);

        /**
         * @brief Whether gamma and beta weights have been loaded
         *
         * @return true If both weight vectors match @c normalized_size
         */
        bool weights_loaded() const {
            return m_gamma.size() == static_cast<size_t>(m_normalized_size) &&
                   m_beta.size() == static_cast<size_t>(m_normalized_size);
        }

        /**
         * @brief Load the learnable scale (gamma) weights
         *
         * @param gamma Scale vector of length @c normalized_size
         */
        void load_gamma(const std::vector<float>& gamma) { m_gamma = gamma; }

        /**
         * @brief Load the learnable shift (beta) weights
         *
         * @param beta Bias vector of length @c normalized_size
         */
        void load_beta(const std::vector<float>& beta) { m_beta = beta; }

        /**
         * @brief Get the number of elements normalized per row
         *
         * @return int Normalized size
         */
        int get_normalized_size() const { return m_normalized_size; }

        /**
         * @brief Forward pass on a single input tensor
         *
         * @param input Input tensor to normalize
         * @return DC_Tensor Normalized output
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward pass reading input from layer_outputs via relative index
         *
         * @param layer_outputs History of layer output tensors
         * @return DC_Tensor Normalized output
         */
        DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const override;

        /**
         * @brief Whether forward() requires the full layer_outputs history
         *
         * @return true Always; LayerNorm selects its input via relative index
         */
        bool requires_layer_outputs() const override { return true; }

    private:
        int m_relative_input_index;
        int m_normalized_size;
        float m_epsilon;
        std::vector<float> m_gamma;
        std::vector<float> m_beta;
    };

} // namespace DC_ConvNet
