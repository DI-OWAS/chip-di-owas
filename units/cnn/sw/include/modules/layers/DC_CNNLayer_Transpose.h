/******************************************************************************
 * @file    DC_CNNLayer_Transpose.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Transpose / permute layer for Depth-Anything tensor layouts
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
     * Transpose for the Depth-Anything perm set:
     * 0,2,1 / 0,1,3,2 / 0,2,1,3 / 2,0,3,1,4
     *
     * HWC notes:
     * - perm 0,2,1 on ONNX [1,C,S*S] after Conv view: identity ([S,S,C] already).
     * - perm 0,1,3,2 on ONNX [1,C,H,W]: swap H/W in the Gather HWC (H,W,C) buffer.
     * - perm 0,2,1,3 on ONNX [1,heads,tokens,dim]: (tok,dim,head)->(head,dim,tok).
     */
    class DC_CNNLayer_Transpose final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Transpose layer
         *
         * @param perm Axis permutation applied to the logical input shape
         * @param input_shape Logical shape of the input tensor before permutation
         */
        DC_CNNLayer_Transpose(std::vector<int> perm, std::vector<int> input_shape);

        /**
         * @brief Permute the input tensor according to the configured axis order
         *
         * @param input Input tensor
         * @return DC_Tensor Transposed output tensor
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
        std::vector<int> m_perm;
        std::vector<int> m_input_shape;
        std::vector<int> m_output_shape;
        int m_out_height;
        int m_out_width;
        int m_out_channels;
    };

} // namespace DC_ConvNet
