/******************************************************************************
 * @file    DC_network_builder.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Neural network builder utility
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

#include "DC_config_parser.h"
#include "DC_layer.h"
#include "DC_cnn_weights_types.h"
#include "DC_CNNLayer_YoloLayer.h"
#include "DC_CNNLayer_Dense.h"
#include "DC_tensor.h"
#include "DC_OWAS_TopLevel.h"

#include <cstdint>
#include <memory>
#include <vector>
#include <map>

namespace DC_ConvNet {

    /**
     * @brief Structure to hold comprehensive information about the constructed neural network
     *
     * This structure maintains all essential information about a built neural network,
     * including layer configurations, topology mappings, and YOLO-specific parameters.
     * It serves as a central repository for network architecture and detection parameters.
     */
    struct DC_NetworkInfo {
        /**
         * @brief Vector of unique pointers to network layers
         *
         * Stores the actual layer objects in sequence. Each layer is dynamically allocated
         * and managed through unique_ptr for automatic memory management.
         * Order corresponds to forward pass sequence.
         */
        std::vector<std::unique_ptr<DC_Layer>> layers;

        /**
         * @brief Mapping between configuration indices and actual layer indices
         *
         * Used to translate between layer indices in the configuration file
         * and their corresponding positions in the runtime layer sequence.
         * Essential for handling skip connections and route layers.
         */
        std::map<size_t, size_t> config_to_layer_index;

        /**
         * @brief Number of output channels for each layer
         *
         * Tracks the number of output channels (feature maps) produced by each layer.
         * Used for shape inference and validation during network construction.
         * Index corresponds to layer position in the network.
         */
        std::vector<int> layer_output_channels;

        /**
         * @brief Indices of YOLO detection layers in the network
         *
         * Stores the positions of YOLO detection layers in the layer sequence.
         * Used during inference to identify where detection outputs should be processed.
         * Multiple indices for multi-scale detection (e.g., YOLOv4).
         */
        std::vector<int> yolo_layer_indices;

        /**
         * @brief Anchor box masks for each YOLO layer
         *
         * Specifies which anchor boxes are used by each YOLO detection layer.
         * Outer vector corresponds to YOLO layers, inner vectors contain indices
         * into the global anchor array for that layer.
         */
        std::vector<std::vector<int>> yolo_masks;

        /**
         * @brief Anchor box dimensions for object detection
         *
         * Stores width and height of anchor boxes used in YOLO detection.
         * Values are in normalized coordinates [0,1].
         * Pairs of values (width, height) are stored sequentially.
         */
        std::vector<float> anchors;
    };

    /**
     * @brief Constructs a CNN layer sequence from configuration and weights files
     *
     * This function performs the complete network construction process:
     * 1. Parses the network configuration file
     * 2. Creates appropriate layer objects based on configuration
     * 3. Loads and assigns weights to layers
     * 4. Establishes layer connections and topology
     * 5. Validates network structure
     *
     * The function supports different network architectures and weight formats,
     * particularly optimized for YOLO and similar detection networks.
     *
     * @param config_file Path to the network configuration file (e.g., .cfg for YOLO)
     * @param weights_file Path to the pre-trained weights file
     * @param weights_format Format specification for the weights file (YOLO/TensorFlow)
     * @param verbose Whether to print detailed information during construction (default: false)
     *
     * @return std::vector<std::unique_ptr<DC_Layer>> Sequence of constructed network layers
     *
     * @throws std::runtime_error If configuration is invalid or weights cannot be loaded
     * @throws std::invalid_argument If file paths are invalid
     * @throws std::bad_alloc If memory allocation for layers fails
     *
     * @note The returned layers are owned by unique_ptrs for automatic memory management
     * @note Layer sequence corresponds to the order of forward pass execution
     */
	template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
    std::vector<std::unique_ptr<DC_Layer>> build_cnn_layers_from_config(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& config_file,
        const std::string& weights_file,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose = false);

    /**
     * @brief Build layers from parsed config; load weights from ROM (memory) or file path.
     *
     * When @p weights_data is non-null, @p weights_file is ignored and weights are read
     * from the embedded buffer. Layer dumps are disabled for ROM builds.
     */
    template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
    std::vector<std::unique_ptr<DC_Layer>> build_cnn_layers_from_net_config(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const DC_NetConfig& net_conf,
        const std::string& weights_file,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose = false,
        const std::string& config_path_hint = std::string());

    /**
     * @brief Build layers for embedded CPU inference (no OWAS, shape-only topology tracker).
     *
     * Loads YOLO weights from ROM into layer objects only; does not allocate off-chip sim memory.
     */
    template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
    std::vector<std::unique_ptr<DC_Layer>> build_cnn_layers_from_net_config_cpu(
        const DC_NetConfig& net_conf,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose = false,
        const std::string& config_path_hint = std::string());

    /**
     * @brief Creates a convolutional layer with the specified parameters
     *
     * @param params Map of layer parameters from the configuration
     * @param current_in_channels Number of input channels for the layer
     * @param verbose Whether to print debug information
     * @return std::unique_ptr<DC_CNNLayer_Conv2D> Configured convolutional layer
     * @throws std::runtime_error If required parameters are missing or invalid
     */
	template<typename ConvT>
    std::unique_ptr<ConvT> create_conv_layer(
        const std::map<std::string, std::string>& params,
        int current_in_channels,
        bool verbose);

    /**
     * @brief Creates a route layer with the specified parameters
     *
     * @param params Map of layer parameters from the configuration
     * @param current_layer_idx Current layer index in the configuration
     * @param config_to_layer_index Mapping between configuration indices and built layer indices
     * @param layer_output_tracker Vector tracking output dimensions of each layer
     * @param route_output_channels Output parameter to store the number of output channels
     * @param route_output_height Output parameter to store the output height
     * @param route_output_width Output parameter to store the output width
     * @param verbose Whether to print debug information
     * @return std::unique_ptr<DC_CNNLayer_Route> Configured route layer
     * @throws std::runtime_error If required parameters are missing or invalid
     */
    template<typename RouteT>
    std::unique_ptr<RouteT> create_route_layer(
        const std::map<std::string, std::string>& params,
        size_t current_layer_idx,
        const std::map<size_t, size_t>& config_to_layer_index,
        const std::vector<DC_Tensor>& layer_output_tracker,
        int& route_output_channels,
        int& route_output_height,
        int& route_output_width,
        bool verbose);

    /**
     * @brief Creates a YOLO layer with the specified parameters
     *
     * This function handles the parsing and validation of YOLO-specific parameters including:
     * - Number of classes
     * - Anchor box dimensions
     * - Anchor mask indices
     * - Scale factors
     *
     * @param params Map of layer parameters from the configuration
     * @param layer_idx Current layer index for error reporting
     * @param verbose Whether to print debug information about anchor configurations
     * @return std::unique_ptr<DC_CNNLayer_YoloLayer> Configured YOLO layer
     * @throws std::runtime_error If required parameters are missing or invalid
     */
    std::unique_ptr<DC_CNNLayer_YoloLayer> create_yolo_layer(
        const std::map<std::string, std::string>& params,
        size_t layer_idx,
        bool verbose);

    /**
     * @brief Creates a dense (fully connected) layer with the specified parameters
     *
     * This function handles the parsing and configuration of dense layer parameters including:
     * - Output units
     * - Activation function
     * - Bias configuration
     *
     * @param params Map of layer parameters from the configuration
     * @param current_in_channels Number of input units for the layer
     * @param verbose Whether to print debug information
     * @return std::pair<std::unique_ptr<DC_CNNLayer_Dense>, int> Pair of configured dense layer and number of output units
     * @throws std::runtime_error If required parameters are missing or invalid
     */
    std::pair<std::unique_ptr<DC_CNNLayer_Dense>, int> create_dense_layer(
        const std::map<std::string, std::string>& params,
        int current_in_channels,
        bool verbose);

} // namespace DC_ConvNet 
