/******************************************************************************
 * @file    DC_CNNLayer_MaxPool2D.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   MaxPool2D layer implementation for neural networks
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
#include "DC_CNNComputeKernel.h"

#include <stdexcept>

namespace DC_ConvNet {

    struct LayerStats;

    /**
     * @brief 2D Max Pooling layer implementation
     *
     * Performs max pooling operation to reduce spatial dimensions.
     */
    class DC_CNNLayer_MaxPool2D final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a 2D max pooling layer
         *
         * @param pool_size Size of the pooling window
         * @param stride Stride of the pooling operation (-1 for same as pool_size)
         */
        DC_CNNLayer_MaxPool2D(int pool_size, int stride = -1);

        /**
         * @brief Performs forward propagation through the max pooling layer
         *
         * @param input Input tensor
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         * 
         * This method is not supported for the max pooling layer as it only accepts
         * a single input tensor.
         * 
         * @param layer_outputs Vector of input tensors
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

    private:

        float compute_kernel(
            const float* const ,
            const float* const ,
            const DC_ComputeKernelParams* const ,
            StrideMode ,
            MEM_ORDER ,
            LayerStats& 
        ) const override {
			return 0.f; // Not used
        }
        /**
         * @brief Computes kernel operation for 2D max pooling layer
         * 
         * Performs 2D max pooling operation at a specific spatial position
         * for a given output channel. This function implements the core max pooling
         * operation, finding the maximum value within a pooling window across
         * all input channels and spatial dimensions.
         * 
         * The function applies a 2D pooling window of size (kernel_size x kernel_size)
         * to the input tensor at position (out_row_idx, out_col_idx), computing:
         * max(input[y][x][c]) for all spatial positions (y,x) in the pooling window
         * and all channels c. The weights parameter is ignored for max pooling.
         * 
         * @param input Input tensor containing feature maps
         * @param weights Pointer to weight vector (ignored for max pooling)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (VALID, SAME, or MULTIPLY)
         * @param mem_order Memory order (HWC or CHW) for index calculation
         * @param stats Performance statistics recorder for operation counting
         * @return float Maximum value found in the pooling window
         */
        float compute_kernel(
            const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats) const;

        int m_pool_size;
        int m_stride;
    };

} // namespace DC_ConvNet 
