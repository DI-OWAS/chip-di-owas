/******************************************************************************
 * @file    DC_cnn_activations_type.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Activation function type definitions for CNN layers
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

namespace DC_ConvNet {

    /**
     * @brief Activation function types
     */
    enum class ActivationType {
        NONE,       /**< No activation */
        RELU,       /**< ReLU: f(x) = max(0, x) */
        LEAKY_RELU  /**< Leaky ReLU: f(x) = x if x > 0, else alpha * x */
    };
}