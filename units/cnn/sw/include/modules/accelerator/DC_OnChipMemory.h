/******************************************************************************
 * @file    DC_OnChipMemory.h
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
     * @class DC_OnChipMemory
     * @brief Lightweight on-chip memory model providing indexed access to on-chip buffers
     *        (e.g., inputs, outputs, weights) along with simple state (last loaded input row).
     *
     * The class is intentionally minimal and does not model bus protocols or timing.
     * It simply exposes a flat address space via Write()/Read() as well as per-buffer
     * bookkeeping of which input row was loaded most recently.
     */
    class DC_OnChipMemory final {

    public:

        /**
         * @brief Write a single value to the on-chip memory buffer.
         * @param idx Linear index into the internal memory buffer.
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
         * @brief Read a single value from the on-chip memory buffer.
         * @param idx Linear index into the internal memory buffer.
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
         * @brief Record the last loaded input row index into on-chip memory.
         * @param buff_id          Logical buffer identifier (e.g., ping/pong buffer index).
         * @param input_row_index  Row index that was last loaded for the given buffer.
         */
        void WriteLastLoadedInputRowIndex(size_t buff_id, size_t input_row_index)
        {
            m_last_input_row_index[buff_id] = input_row_index;
        }

        /**
         * @brief Get the last loaded input row index for a given buffer.
         * @param buff_id Logical buffer identifier (e.g., ping/pong buffer index).
         * @return The most recently recorded input row index for that buffer.
         */
        int ReadLastLoadedInputRowIndex(size_t buff_id) const
        {
            return m_last_input_row_index[buff_id];
        }
        
    private:
        /// Per-buffer last loaded input row indices (e.g., for double-buffered inputs).
        std::vector<int> m_last_input_row_index = std::vector<int>(2, -1);

        /// Backing storage for the on-chip memory (currently 4 MiB addressed as floats).
        std::vector<float> m_mem_buffer = std::vector<float>(4096 * 1024 / sizeof(float), 0.f);
    };

} // namespace DC_ConvNet


