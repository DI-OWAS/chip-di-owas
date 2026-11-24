/******************************************************************************
 * @file    DC_config_parser.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Configuration parser utility functions
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
#include <DC_cnn_weights_types.h>
#include <DC_layer.h>

#include <cstddef>
#include <string>
#include <vector>
#include <map>

namespace DC_ConvNet {

    /**
     * @brief Structure to hold the network configuration parameters.
     */
    struct DC_NetConfig {
        // Global network parameters
        int batch = 0;
        int subdivisions = 0;
        int width = 0;
        int height = 0;
        int channels = 0;
        float momentum = 0.f;
        float decay = 0.f;
        float angle = 0.f;
        float saturation = 0.f;
        float exposure = 0.f;
        float hue = 0.f;
        bool is_channel_first = true;

        // Layer configurations
        struct LayerConfig {
            std::string type;                          ///< Layer type (e.g., "net", "convolutional", "route", "yolo")
            std::map<std::string, std::string> params; ///< Layer parameters as key-value pairs
        };

        std::vector<LayerConfig> layers;               ///< All layer configurations
    };

    /**
     * @brief Structure to hold JSON configuration parameters for YOLO models.
     */
    struct DC_JsonConfig {
        std::string network_topology_file;   ///< Path to network topology (cfg) file
        std::string weights_file;            ///< Path to weights file
        std::string image_inputs_dir;        ///< Directory containing input images
        std::string weight_format_str;        ///< Format of weights file (e.g., "yolo", "tensorflow")

        WeightsFormat get_weights_format() const {
            if (weight_format_str == "yolo") return WeightsFormat::YOLO;

            if (weight_format_str == "tensorflow") return WeightsFormat::TENSORFLOW;

            if (weight_format_str == "depth_anything") return WeightsFormat::DEPTH_ANYTHING;

            return WeightsFormat::UNKNOWN;
        }

        Layer_Type get_output_layer() const {
            if (weight_format_str == "yolo") return Layer_Type::YOLO;

            if (weight_format_str == "tensorflow") return Layer_Type::SOFTMAX;
            
            if (weight_format_str == "feature") return Layer_Type::L2NORM;

            if (weight_format_str == "depth_anything") return Layer_Type::GATHER;

            return Layer_Type::UNKNOWN;
        }
    };

    /**
     * @brief Parses a network configuration file
     *
     * Reads a YOLO-style configuration file and converts it into a structured
     * representation containing network and layer parameters.
     *
     * @param config_file Path to the configuration file
     * @return DC_NetConfig Structured representation of the network configuration
     */
    DC_NetConfig parse_network_config(const std::string& config_file);

    /**
     * @brief Parses a Darknet-style .cfg from a memory buffer (ROM / embedded assets).
     */
    DC_NetConfig parse_network_config_from_memory(const char* data, std::size_t size);

    /**
     * @brief Parses a JSON configuration file
     *
     * Reads a JSON configuration file and converts it into a structured
     * representation containing parameters such as network topology file,
     * weights file, etc.
     *
     * @param json_file Path to the JSON configuration file
     * @return DC_JsonConfig Structured representation of the JSON configuration
     * @throws std::runtime_error If the file cannot be opened or parsed
     */
    DC_JsonConfig parse_json_config(const std::string& json_file);

} // namespace DC_ConvNet 
