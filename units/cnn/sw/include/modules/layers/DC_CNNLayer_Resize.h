/******************************************************************************
 * @file    DC_CNNLayer_Resize.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Bilinear spatial resize layer for neural networks
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
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Bilinear spatial resize to a target HWC output shape
     *
     * Resizes the spatial dimensions of the input using bilinear interpolation.
     * @p coordinate_transformation_mode selects the ONNX-style coordinate mapping
     * (default "half_pixel").
     */
    class DC_CNNLayer_Resize final : public DC_Layer {
    public:
        /**
         * @brief Constructs a Resize layer
         *
         * @param output_shape Target output shape (typically H, W, C)
         * @param coordinate_transformation_mode ONNX coordinate mode (default "half_pixel")
         */
        DC_CNNLayer_Resize(
            std::vector<int> output_shape,
            std::string coordinate_transformation_mode = "half_pixel");

        /**
         * @brief Bilinearly resize the input tensor to the configured output shape
         *
         * @param input Input tensor
         * @return DC_Tensor Resized output tensor
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
        std::vector<int> m_output_shape;
        std::string m_coordinate_transformation_mode;
    };

} // namespace DC_ConvNet
