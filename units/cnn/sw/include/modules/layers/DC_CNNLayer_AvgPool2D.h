/******************************************************************************
 * @file    DC_CNNLayer_AvgPool2D.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   AvgPool2D layer implementation for neural networks
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
     * @brief 2D Global Average Pooling layer implementation
     * 
     * Performs global average pooling operation to reduce spatial dimensions to 1x1.
     * 
     * Collapses spatial dimensions (H,W) into a single mean value per channel.
     * @verbatim
     *       [Input Feature Map]          [Summation & Scaling]         [Output Vector]
     *    (Channels x H:8 x W:4)           (Mean of 32 pixels)          (Channels x 1 x 1)
     * 
     *          Depth (C:512)                   1 / (8 * 4)                    |
     *             /|                             |                            |
     *            / |  ________                   V                            |
     *    H:8 -> |_|__|       |            +---------------+            +---------------+
     *           | |  | Pixels|  ------>   |  Sum(P1..P32) |  ------>   | Feature Value |
     *           |_|__|_______|            +---------------+            +---------------+
     *                ^                                                  (1 Float per 
     *               W:4                                                   Channel)
     * @endverbatim
     * @note The (8,4) kernel matches the final feature map dimensions (H/16, W/16).
     *       It calculates the arithmetic mean of all 32 pixels in each channel 
     *       to provide spatial invariance, ensuring the 512-dimensional output 
     * 
     */
    class DC_CNNLayer_AvgPool2D final : public DC_Layer {
    public:
        /**
         * @brief Constructs a 2D average pooling layer
         *
         * @param kernel_height Height of the pooling window (-1 for global average pooling)
         * @param kernel_width Width of the pooling window (-1 for global average pooling)
         * @param stride_y Stride in the y direction
         * @param stride_x Stride in the x direction
         */
        explicit DC_CNNLayer_AvgPool2D(int kernel_height = -1, int kernel_width = -1, int stride_y = 1, int stride_x = 1);

        /**
         * @brief Performs forward propagation through the average pooling layer
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

    private:
        int m_kernel_height;
        int m_kernel_width;
        int m_stride_y;
        int m_stride_x;
    };

} // namespace DC_ConvNet