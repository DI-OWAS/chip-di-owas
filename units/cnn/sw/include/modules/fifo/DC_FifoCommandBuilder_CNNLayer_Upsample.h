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

#include <stdexcept>

namespace DC_ConvNet {

    /**
     * @brief Upsampling layer implementation
     *
     * Performs upsampling of the input tensor by the specified stride factor.
     * Uses nearest neighbor interpolation as required by YOLOv4.
     */
    class DC_FifoCommandBuilder_CNNLayer_Upsample final : public DC_Layer {
    public:
        /**
         * @brief Constructs an upsampling layer
         *
         * Creates a layer that increases spatial dimensions of input tensors
         * by a specified stride factor in both height and width dimensions.
         *
         * @param stride Upsampling factor (e.g., 2 doubles height and width)
         */
        explicit DC_FifoCommandBuilder_CNNLayer_Upsample(int stride);

        /**
         * @brief Forward pass for upsampling layer
         *
         * @param input Input tensor
         * @return DC_Tensor Upsampled output tensor
         */
        DC_Tensor forward(const DC_Tensor& input) const override { return input; }

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

        DC_HW_Params_Layer build_layer_parameter_set(const DC_Tensor& input) const override;

        /**
         * @brief Builds a FIFO of hardware commands for this Upsample layer.
         *
         * Mirrors the behavior of the software `forward` method but instead of executing
         * on the CPU it creates a list of accelerator commands that can be pushed to the
         * hardware command FIFO.
         *
         * @param output Output tensor descriptor that will be resized to the correct
         *               output geometry (data is not written here, only shape).
         * @param input  Input tensor descriptor used to derive command parameters.
         * @return std::list<std::unique_ptr<DC_CNN_HW_Command>> List of HW commands.
         */
        std::list<std::unique_ptr<DC_CNN_HW_Command>> build_fifo_commands(
            DC_Tensor& output,
            const DC_HW_Params_Layer& layer_params) const override;

    private:

        int m_stride;  // Upsampling factor
    };

} // namespace DC_ConvNet 
