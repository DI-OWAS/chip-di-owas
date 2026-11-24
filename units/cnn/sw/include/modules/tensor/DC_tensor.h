/******************************************************************************
 * @file    DC_tensor.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Tensor data structure implementation
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

#include <cstddef>
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Memory layout order for tensor data storage
     * 
     * Defines how multi-dimensional tensor data is arranged in memory:
     * - CHW: Channel-Height-Width format (channels first)
     * - HWC: Height-Width-Channel format (channels last)
     */
    enum class MEM_ORDER {
        CHW,    ///< Channel-Height-Width memory layout
        HWC     ///< Height-Width-Channel memory layout
    };

    enum class StrideMode {
        MULTIPLY,          // stride multiplies (downsampling)
        DIVIDE     // stride divides (upsampling)
    };

    /**
     * @brief Tensor structure representing 3D data
     * Data is stored in CHW or HWC format
     */
    struct DC_Tensor {
        std::vector<int> m_shape;
        int m_height;    ///< Height of the tensor
        int m_width;     ///< Width of the tensor
        int m_channels;  ///< Number of channels
        std::vector<float> m_data; ///< Raw data in CHW or HWC format
        MEM_ORDER m_mem_order; ///< Memory layout order (CHW or HWC) for this tensor
        std::size_t m_weights_mem_seeks;
        std::size_t m_biases_mem_seeks;
        std::size_t m_input_mem_seeks;
        std::size_t m_output_mem_seeks;

        void set_logical_shape(const std::vector<int>& shape)
        {
            m_shape = shape;
        }

        std::size_t get_tensor_size() const {
            return m_height * m_width * m_channels;
		}
        /**
         * @brief Constructs a tensor with given dimensions
         * 
         * @param height Height of the tensor
         * @param width Width of the tensor
         * @param channels Number of channels
         * @param mem_order Memory layout order (CHW or HWC)
         */
        DC_Tensor(int height, int width, int channels, MEM_ORDER mem_order, bool allocate_data = true)
            : m_height(height), m_width(width), m_channels(channels), m_mem_order(mem_order) {
            if (allocate_data) {
                m_data.resize(static_cast<std::size_t>(height) * static_cast<std::size_t>(width)
                              * static_cast<std::size_t>(channels));
            }
        }

        //DC_Tensor(const std::vector<int>& shape, MEM_ORDER mem_order)
        //    : m_shape(shape), m_mem_order(mem_order) {
        //    auto data_size = 1;
        //    for (auto d : m_shape)
        //    {
        //        data_size *= d;
        //    }
        //    m_data.resize(data_size);
        //}
    };

} // namespace DC_ConvNet 
