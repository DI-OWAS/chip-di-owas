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

#include <stdexcept>

namespace DC_ConvNet {

    /**
     * @brief 2D Max Pooling layer implementation
     *
     * Performs max pooling operation to reduce spatial dimensions.
     */
    class DC_FifoCommandBuilder_CNNLayer_MaxPool2D final : public DC_Layer{
    public:
        /**
         * @brief Constructs a 2D max pooling layer
         *
         * @param pool_size Size of the pooling window
         * @param stride Stride of the pooling operation (-1 for same as pool_size)
         */
        DC_FifoCommandBuilder_CNNLayer_MaxPool2D(int pool_size, int stride = -1);

        /**
         * @brief Performs forward propagation through the max pooling layer
         *
         * @param input Input tensor
         * @return DC_Tensor Output tensor
         */
        DC_Tensor forward(const DC_Tensor& input) const override { return input; }

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

        DC_HW_Params_Layer build_layer_parameter_set(const DC_Tensor& input) const override;

        /**
         * @brief Builds a FIFO of hardware commands for this MaxPool2D layer.
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

        int m_pool_size;
        int m_stride;
    };

} // namespace DC_ConvNet 
