/******************************************************************************
 * @file    DC_OffChipMemory.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   On-chip memory utilities and structures (e.g., circular buffers)
 * @version 1.0.0
 * @date    2025-10-30
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

#include <vector>
#include <cstddef>

namespace DC_ConvNet {

    /**
     * @class DC_OffChipMemory
     * @brief Lightweight off-chip (external) memory model providing indexed access to a
     *        large backing buffer used for inputs, outputs, and weights.
     *
     * This class abstracts a flat external memory space and exposes simple read/write
     * accessors plus a direct reference to the underlying buffer for bulk operations.
     * It does not model bus protocols, latency, or caching effects.
     */
    class DC_OffChipMemory final {

    public:

        /**
         * @brief Write a single value to the off-chip memory buffer.
         * @param idx Linear index into the external memory buffer.
         * @param val Value to be written at the specified index.
         *
         * The caller is responsible for ensuring that @p idx is within bounds of the
         * underlying buffer.
         */
        void Write(size_t idx, float val)
        {
            m_mem_buffer[idx] = val;
        }

        /**
         * @brief Read a single value from the off-chip memory buffer.
         * @param idx Linear index into the external memory buffer.
         * @return The value stored at the specified index.
         *
         * The caller is responsible for ensuring that @p idx is within bounds of the
         * underlying buffer.
         */
        float Read(size_t idx) const
        {
            return m_mem_buffer[idx];
        }

        /**
         * @brief Access the underlying external memory buffer.
         * @return Reference to the internal float buffer for bulk operations.
         */
        std::vector<float>& GetBuffer()
        {
            return m_mem_buffer;
        }
              
    private:

        /// Underlying storage for the external memory (currently 1 GiB addressed as floats).
        std::vector<float> m_mem_buffer = std::vector<float>(1024 * 1024 * 1024 / sizeof(float), 0.f);
    };

} // namespace DC_ConvNet


