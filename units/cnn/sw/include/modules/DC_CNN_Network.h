/******************************************************************************
 * @file    DC_CNN_Network.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Main CNN network implementation
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
#include "DC_tensor.h"

#include <vector>
#include <memory>

namespace DC_OWAS
{
    class DC_OWAS_TopLevel;
}

namespace DC_ConvNet {

    /**
     * @brief Sequential CNN executor that runs a forward pass over owned layers
     *
     * Holds a list of @ref DC_Layer instances and executes classification (or other)
     * tasks by iterating layers, collecting outputs that match a requested
     * @ref Layer_Type. Overloads support CPU-only and OWAS/HW-backed execution.
     */
    class DC_CNN_Network final {
    public:
        /**
         * @brief Set the layers of the network by moving in a vector of unique pointers to DC_Layer objects.
         *
         * @param layers Vector of unique pointers to DC_Layer objects representing the network architecture.
         */
        void set_layers(std::vector<std::unique_ptr<DC_Layer>>&& layers);
        /**
         * @brief Perform a forward pass through the network up to the specified output layer type.
         *
         * @param input_image The input tensor to the network (e.g., an image or feature tensor).
         * @param output_layer The type of layer whose outputs should be collected and returned.
         * @return std::vector<DC_Tensor> Vector of output tensors from layers of the specified type.
         */
        std::vector<DC_Tensor> execute_classification_task(DC_OWAS::DC_OWAS_TopLevel& owas_top_level, const DC_Tensor& input_image, Layer_Type output_layer);
        /**
         * @brief Perform a forward pass through the network up to the specified output layer type.
         *
         * @param input_image The input tensor to the network (e.g., an image or feature tensor).
         * @param output_layer The type of layer whose outputs should be collected and returned.zl
         * @return std::vector<DC_Tensor> Vector of output tensors from layers of the specified type.
         */
        std::vector<DC_Tensor> execute_classification_task(const DC_Tensor& input_image, Layer_Type output_layer);
    private:
        std::vector<std::unique_ptr<DC_Layer>> m_layers;
    };

} // namespace DC_ConvNet 

