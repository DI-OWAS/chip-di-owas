/******************************************************************************
 * @file    DC_CNN_Accelerator_Const.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   On-chip accelerator memory sizing constants
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

namespace DC_ConvNet {
	/** @brief Total on-chip weight buffer capacity in bytes (2 × 16384). */
	constexpr auto weights_memory_size_bytes = (2 * 16384);
	/** @brief Number of input rows loaded into the on-chip circular buffer per convolution step. */
	constexpr auto number_of_rows_to_load = 3;
}
