/******************************************************************************
 * @file    DC_PerformanceStats.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Singleton class for collecting performance statistics across CNN layers
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
#include "DC_CNN_activation_types.h"

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Enumeration of operation types for performance tracking
     */
    enum class OperationType {
        MEMORY_LOAD = 0,       // Memory load operations
        MEMORY_STORE,      // Memory store operations
        ARITHMETIC_ADD,    // Addition operations (including subtraction)
        ARITHMETIC_MUL,    // Multiplication operations (including division)
        ARITHMETIC_COMP,   // Comparison operations
        ARITHMETIC_OTHER,   // Other arithmetic operations (sqrt, exp, etc.)
        END
    };

    /**
     * @brief Layer statistics structure to hold per-layer performance metrics
     */
    struct LayerStats {
        std::string layer_name;                       // Name of the layer
        std::string layer_type;                       // Type of the layer (Conv2D, MaxPool, etc.)
        std::vector<uint64_t> operation_counts;  // Counts by operation type
        std::vector<uint64_t> theoretical_operation_counts;  // Counts by operation type

        /**
         * @brief Static layer geometry and configuration captured for reporting
         */
        struct {
            int input_height = 0;    /**< Input spatial height */
            int input_width = 0;     /**< Input spatial width */
            int input_channels = 0;  /**< Input channel count */
            int output_height = 0;   /**< Output spatial height */
            int output_width = 0;    /**< Output spatial width */
            int output_channels = 0; /**< Output channel count */
            int kernel_size = 0;     /**< Convolution / pool kernel size */
            int stride = 0;          /**< Stride */
            int padding = 0;         /**< Padding */
            bool use_bias = false;   /**< Whether bias is used */
            bool batch_norm = false; /**< Whether batch norm is fused */
            std::string activation = "None"; /**< Activation name for the report */
        } config;

        /**
         * @brief Increment the measured count for an operation type
         *
         * @param operation_type Kind of operation
         * @param count Number of operations to add
         */
        void record_operation(OperationType operation_type, uint64_t count) {
            operation_counts[static_cast<uint64_t>(operation_type)] += count;
        }

        /**
         * @brief Record layer I/O geometry and configuration for the report
         *
         * @param input Input tensor (provides input H/W/C)
         * @param output_height Output height
         * @param output_width Output width
         * @param output_channels Output channels
         * @param use_bias Whether bias is used
         * @param kernel_size Kernel size
         * @param stride Stride
         * @param padding Padding
         * @param batch_norm Whether batch normalization is enabled
         * @param activation_type Activation applied by the layer
         */
        void record_layer_configuration(const DC_Tensor& input,
            int output_height,
            int output_width,
            int output_channels,
            bool use_bias,
            int kernel_size,
            int stride,
            int padding,
            bool batch_norm,
            ActivationType activation_type) {
            config.input_height = input.m_height;
            config.input_width = input.m_width;
            config.input_channels = input.m_channels;
            config.output_height = output_height;
            config.output_width = output_width;
            config.output_channels = output_channels;
            config.use_bias = use_bias;
            config.kernel_size = kernel_size;
            config.stride = stride;
            config.padding = padding;
            config.batch_norm = batch_norm;

            switch (activation_type) {
            case ActivationType::RELU:
                config.activation = "ReLU";
                break;
            case ActivationType::LEAKY_RELU:
                config.activation = "LeakyReLU";
                break;
            default:
                config.activation = "None";
                break;
            }
        }

        /**
         * @brief Set the theoretical (expected) operation count for a type
         *
         * @param operation_type Kind of operation
         * @param count Expected number of operations
         */
        void theoretical_operations(OperationType operation_type, uint64_t count) {
            theoretical_operation_counts[static_cast<uint64_t>(operation_type)] = count;
        }

        /**
         * @brief Construct statistics storage for a named layer
         *
         * @param name Layer name
         * @param type Layer type string (e.g. "Conv2D")
         */
        LayerStats(const std::string& name, const std::string& type)
            : layer_name(name), layer_type(type) {
            operation_counts.resize(static_cast<size_t>(OperationType::END));
            theoretical_operation_counts.resize(static_cast<size_t>(OperationType::END));
        }
    };

    /**
     * @brief Singleton class for collecting and managing performance statistics
     *
     * This class provides a centralized way to track performance metrics across
     * all CNN layers, including memory operations and arithmetic operations.
     */
    class DC_PerformanceStats {
    public:
        /**
         * @brief Get the singleton instance
         *
         * @return Reference to the singleton instance
         */
        static DC_PerformanceStats& getInstance();

        /**
         * @brief Allocate (or look up) a LayerStats entry for the given layer
         *
         * @param layer_name Unique name of the layer
         * @param layer_type Layer type used to initialize the stats record
         * @return LayerStats& Mutable reference to the allocated statistics
         */
        LayerStats& AllocateLayerStats(const std::string& layer_name, Layer_Type layer_type);

        /**
         * @brief Insert pre-built layer statistics under @p layer_name
         *
         * @param layer_name Key used to look up the stats later
         * @param layer_stats Statistics object to take ownership of
         */
        void addLayerStats(const std::string& layer_name, LayerStats&& layer_stats);

        /**
         * @brief Reset all statistics
         */
        void resetAllStats();

        /**
         * @brief Get statistics for a specific layer
         *
         * @param layer_name Name of the layer
         * @return Pointer to the layer stats, or nullptr if not found
         */
        const LayerStats* getLayerStats(const std::string& layer_name) const;

        /**
         * @brief Get statistics for all layers
         *
         * @return Vector of all layer statistics
         */
        std::vector<const LayerStats*> getAllLayerStats() const;

        /**
         * @brief Get total statistics across all layers
         *
         * @return Map of operation types to total counts
         */
        std::unordered_map<OperationType, uint64_t> getTotalStats() const;

        /**
         * @brief Generate a summary report of all statistics
         *
         * @param include_layers Whether to include per-layer details
         * @return String containing the report
         */
        std::string generateReport(bool include_layers = true) const;

    private:
        // Private constructor (singleton pattern)
        DC_PerformanceStats() 
        {
            m_layer_stats.reserve(1000);
        }

        // Deleted copy constructor and assignment operator
        DC_PerformanceStats(const DC_PerformanceStats&) = delete;
        DC_PerformanceStats& operator=(const DC_PerformanceStats&) = delete;

        // Map of layer names to statistics
        std::vector<std::pair<std::string, LayerStats>> m_layer_stats;
    };

    // Helper function to convert OperationType to string
    std::string operationTypeToString(OperationType op_type);

} // namespace DC_ConvNet 