/******************************************************************************
 * @file    DC_CNNLayer_Upsample.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Upsample layer implementation for neural networks
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
     * @brief Upsampling layer implementation
     *
     * Performs upsampling of the input tensor by the specified stride factor.
     * Uses nearest neighbor interpolation as required by YOLOv4.
     */
    class DC_CNNLayer_Upsample final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs an upsampling layer
         *
         * Creates a layer that increases spatial dimensions of input tensors
         * by a specified stride factor in both height and width dimensions.
         *
         * @param stride Upsampling factor (e.g., 2 doubles height and width)
         */
        explicit DC_CNNLayer_Upsample(int stride);

        /**
         * @brief Forward pass for upsampling layer
         *
         * @param input Input tensor
         * @return DC_Tensor Upsampled output tensor
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         * 
         * This method is not supported for the upsampling layer as it only accepts
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
        ) const {
			return 0.f;
        }

        /**
         * @brief Computes kernel operation for upsampling layer
         * 
         * Performs upsampling operation at a specific spatial position for a given
         * output channel. This function implements the core upsampling operation,
         * which increases the spatial resolution of input feature maps by
         * duplicating or interpolating values according to the upsampling method.
         * 
         * The function maps output positions back to corresponding input positions
         * and retrieves the appropriate input value, potentially with interpolation
         * for fractional positions. The weights parameter is ignored for upsampling.
         * 
         * @param input Input tensor containing feature maps
         * @param weights Pointer to weight vector (ignored for upsampling)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (ignored for upsampling)
         * @param mem_order Memory order (HWC or CHW) for index calculation
         * @param stats Performance statistics recorder for operation counting
         * @return float Upsampled value from corresponding input position
         */
        float compute_kernel(const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats) const;

        int m_stride;  // Upsampling factor
    };

} // namespace DC_ConvNet 
