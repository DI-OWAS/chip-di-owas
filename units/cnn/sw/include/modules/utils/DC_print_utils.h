/******************************************************************************
 * @file    DC_print_utils.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Utility functions for printing and logging
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
#include "DC_tensor.h"
#include "DC_cnn_weights_types.h"

#include <vector>
#include <string>

namespace DC_ConvNet {

/**
 * @brief Prints TensorFlow model output information for analysis and debugging
 * 
 * Formats and displays:
 * - Output tensor shapes and dimensions
 * - Activation statistics (min/max/mean values)
 * - Classification probabilities (if applicable)
 * - Layer-wise activation summaries
 *
 * @param outputs Vector of output tensors from TensorFlow model inference
 * @throws std::runtime_error If tensor format is invalid or incompatible
 * 
 * @note Output format is designed for easy parsing and analysis
 * @note For classification models, probabilities are sorted by confidence
 */
void visualize_tensorflow_output(const std::vector<DC_ConvNet::DC_Tensor>& outputs);

/**
 * @brief Prints comprehensive CNN output information based on network type
 * 
 * Provides detailed output visualization and analysis:
 * - For YOLO: Detection boxes, classes, confidences and save detections in image format
 * - For Classification: Class probabilities and top predictions
 * - For Custom architectures: Layer-specific output formatting
 *
 * @param input_image Original input image tensor for reference
 * @param net_outputs Vector of network output tensors
 * @param weights_format Format specification (YOLO/TensorFlow) affecting output interpretation
 * @param config_file Path to network configuration file for parameter reference
 * 
 * @throws std::runtime_error If output processing fails
 * @throws std::invalid_argument If configuration file is invalid
 * 
 * @note Output format adapts to network architecture
 * @note For YOLO, includes non-maximum suppression results
 * @note For classification, includes top-k predictions
 */
void visualize_cnn_outputs(int input_id, const DC_Tensor& input_image
	, const std::vector<DC_Tensor>& net_outputs
	, WeightsFormat weights_format
	, const std::string& config_file);
}