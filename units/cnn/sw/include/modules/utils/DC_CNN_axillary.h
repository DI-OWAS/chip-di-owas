/******************************************************************************
 * @file    DC_CNN_axillary.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Auxiliary functions for CNN operations
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

#include "DC_CNN_activation_types.h"
#include "DC_PerformanceStats.h"

namespace DC_ConvNet {

	/**
	 * @brief Applies activation function to a single value
	 * 
	 * Applies the specified activation function (ReLU or Leaky ReLU) to the input value
	 * and records the operation statistics.
	 * 
	 * @param activation_type Type of activation function to apply
	 * @param sum Input value to activate
	 * @param leaky_alpha Alpha parameter for Leaky ReLU
	 * @param stats Reference to LayerStats object for operation tracking
	 * @return float Activated value
	 */
	inline float activate_value(ActivationType activation_type, float sum, float leaky_alpha, LayerStats& stats) {
        switch (activation_type)
        {
        case ActivationType::RELU:
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
            return std::max(0.0f, sum);
            break;
        case ActivationType::LEAKY_RELU:
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
            if (sum > 0.0f)
            {
                return sum;
            } 
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
            return leaky_alpha * sum;
            break;
        default:
            break;
        }

        return sum;
	}
}