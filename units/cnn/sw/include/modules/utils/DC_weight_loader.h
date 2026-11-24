/******************************************************************************
 * @file    DC_weight_loader.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Weight loading utility functions for neural networks
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
#include "DC_cnn_weights_types.h"
#include "DC_OWAS_TopLevel.h"

#include <string>
#include <vector>
#include <memory>


namespace DC_ConvNet {

    /**
     * @brief Generic weight loader entry point for different network formats.
     * 
     * Dispatches to the appropriate weight loading routine based on @p weights_format:
     * - WeightsFormat::YOLO       → Darknet-style YOLO binary weights
     * - WeightsFormat::TENSORFLOW → DC ConvNet binary weights exported from TF
     * - WeightsFormat::DEPTH_ANYTHING → ONNX-exported DCWA binary + manifest sidecar
     *
     * @param owas_top_level           Top-level OWAS object used to write weights off-chip.
     * @param output_tensor_per_layer  Output tensor descriptors per layer (used by ConvNet loader).
     * @param weights_format           Enumeration of the weights format.
     * @param mem_order                Memory layout order (CHW or HWC).
     * @param weights_file             Path to the weights file.
     * @param layers                   Vector of network layers to load weights into.
     * @param verbose                  Whether to print detailed loading information (default: true).
     * 
     * @return Pair containing (number_of_weight_parameters, number_of_bias_parameters) loaded.
     *
     * @throws std::runtime_error  If the file cannot be opened or format is invalid.
     * @throws std::bad_alloc      If insufficient memory for weight loading.
     * @throws std::invalid_argument If layer configuration does not match weights.
     */
	template<typename ConvT>
    void load_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        bool verbose = true);

    /**
     * @brief Specialized loader for YOLO-style convolutional network weights.
     * 
     * Loads pre-trained weights from a Darknet binary weights file and assigns them
     * to convolutional layers (including optional batch-normalization parameters),
     * then performs batch-norm fusion for efficient inference.
     *
     * @param owas_top_level Top-level OWAS object used to write fused weights/biases off-chip.
     * @param weights_file   Path to the Darknet format weights file.
     * @param layers         Vector of network layers to load weights into.
     * @param mem_order      Memory layout order (CHW or HWC).
     * @param verbose        Whether to print detailed loading information (default: true).
     * 
     * @return Pair containing (number_of_weight_parameters, number_of_bias_parameters) loaded.
     *
     * @throws std::runtime_error  If file is corrupted or incompatible.
     * @throws std::bad_alloc      If insufficient memory.
     * @throws std::invalid_argument If layer configuration does not match weights.
     */
    template<typename ConvT>
    void load_yolo_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose = true);

    template<typename ConvT>
    void load_yolo_weights_from_memory(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose = true);

    template<typename ConvT>
    void load_weights_from_memory(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        bool verbose = true);

    /**
     * @brief Loader for DC ConvNet binary weights exported from TensorFlow.
     * 
     * Expects a simple binary container with a sequence of weight arrays, each
     * preceded by shape metadata. The first arrays are mapped to Conv2D weights
     * and biases, and the last arrays to Dense layer weights and biases.
     *
     * @param owas_top_level          Top-level OWAS object used to write weights/biases off-chip.
     * @param output_tensor_per_layer Output tensor descriptors for each layer (used for Dense shapes).
     * @param filename                Path to the ConvNet weights file.
     * @param layers                  Vector of network layers to load weights into.
     * @param mem_order               Memory layout order (CHW or HWC).
     * 
     * @return Pair containing (number_of_weight_parameters, number_of_bias_parameters) loaded.
     *
     * @throws std::runtime_error     If file format is invalid or file cannot be opened.
     * @throws std::bad_alloc         If insufficient memory.
     * @throws std::invalid_argument  If layer configuration is incompatible with weights.
     */
    template<typename ConvT>
    void load_convnet_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        const std::string& filename,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order);

    /**
     * @brief Loader for Depth Anything ONNX-exported weights (DCWA binary + manifest).
     *
     * Reads tensor data from a `.weights.bin` file and uses a sibling `.manifest`
     * file to map ONNX tensor names onto built network layers. An optional
     * `.weights.json` sidecar is validated when present.
     */
    template<typename ConvT>
    void load_depth_anything_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose = true);

    /**
     * @brief Convert convolution weights from TensorFlow-style HWIO to CHW (OIHW).
     * 
     * Reorders a 4D convolution kernel from layout [kh, kw, in_channels, out_channels]
     * into [out_channels, in_channels, kh, kw] without changing values.
     *
     * @param original_weights Source weights array in HWIO layout.
     * @param kernel_size      Convolution kernel size (height = width assumed).
     * @param in_channels      Number of input channels.
     * @param out_channels     Number of output channels.
     * @return Re-ordered weights array in CHW/OIHW layout.
     */
    std::vector<float> convert_weights_to_CHW(
        const std::vector<float>& original_weights,
        int kernel_size,
        int in_channels,
        int out_channels);

    /**
     * @brief Convert convolution weights from CHW/OIHW to HWC/HWIO layout.
     */
    std::vector<float> convert_weights_to_HWC(
        const std::vector<float>& original_weights,
        int kernel_size,
        int in_channels,
        int out_channels);

    /**
     * @brief Fuse batch-normalization parameters into convolution weights and biases.
     * 
     * For each convolution layer with batch-normalization enabled, folds the BN
     * parameters into the convolution weights and biases and writes the fused
     * tensors to off-chip memory via @p owas_top_level.
     *
     * @param owas_top_level Top-level OWAS object used to write fused parameters off-chip.
     * @param layers         Vector of network layers to optimize in-place.
     * @param mem_order      Memory layout order (CHW or HWC).
     * 
     * @note Operation is irreversible for the lifetime of the layer objects
     *       and is intended for inference-time optimization.
     */
    template<typename ConvT>
    void fuse_conv_batchnorm(DC_OWAS::DC_OWAS_TopLevel& owas_top_level, std::vector<std::unique_ptr<DC_Layer>>& layers, MEM_ORDER mem_order);

    /**
     * @brief Fuse batch-norm into conv weights in-place (no off-chip memory writes).
     *
     * For embedded CPU inference (COMPUTE_IN_LAYERS) where OWAS is not used.
     */
    template<typename ConvT>
    void fuse_conv_batchnorm_inplace(std::vector<std::unique_ptr<DC_Layer>>& layers, MEM_ORDER mem_order);

    template<typename ConvT>
    void load_yolo_weights_from_memory_cpu(
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose = false);
} // namespace DC_ConvNet 
