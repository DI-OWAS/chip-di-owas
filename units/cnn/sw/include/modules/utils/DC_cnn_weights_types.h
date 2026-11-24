/******************************************************************************
 * @file    DC_cnn_weights_types.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Type definitions for CNN weight formats and related enumerations
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
     * @brief Supported weight file formats for neural network models
     *
     * This enumeration defines the supported formats for loading pre-trained
     * network weights. Each format has specific characteristics and requirements:
     *
     * YOLO:
     * - Darknet binary format
     * - Sequential layer organization
     * - Includes header with version info
     * - Supports both float32 and int8 quantization
     *
     * TENSORFLOW:
     * - Protocol buffer format
     * - Graph-based representation
     * - Variable tensors with names
     * - Supports multiple precision types
     *
     * DEPTH_ANYTHING:
     * - DC binary manifest format exported from ONNX initializers
     * - Preserves ONNX tensor order, names, shapes, and dtypes
     * - Conv weights stored in OIHW layout (converted at load time via MEM_ORDER)
     */
    enum class WeightsFormat
    {
        /**
         * @brief Darknet YOLO format
         *
         * Characteristics:
         * - Binary file format
         * - Big-endian byte order
         * - 32-bit floating point weights
         * - Optional weight quantization
         * - Includes convolutional and batch norm parameters
         */
        YOLO = 0,

        /**
         * @brief TensorFlow saved model format
         *
         * Characteristics:
         * - Protocol buffer serialization
         * - Named variable tensors
         * - Multiple precision support
         * - Platform-independent representation
         * - Includes gradient and optimizer states (if saved)
         */
        TENSORFLOW,

        /**
         * @brief Depth Anything ONNX-exported binary weights
         *
         * Characteristics:
         * - Magic header "DCWA" + version
         * - Sequence of named tensors in ONNX initializer order
         * - float32 and int64 dtypes
         * - JSON sidecar manifest for validation
         */
        DEPTH_ANYTHING,
        UNKNOWN
    };

} // namespace DC_ConvNet