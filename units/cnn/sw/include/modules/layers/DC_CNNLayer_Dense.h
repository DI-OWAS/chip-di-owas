/******************************************************************************
 * @file    DC_CNNLayer_Dense.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Dense (fully connected) layer implementation for neural networks
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
#include "DC_CNNComputeKernel.h"

#include <stdexcept>

namespace DC_ConvNet {

    struct LayerStats;

    /**
     * @brief Dense (fully connected) layer implementation
     * 
     * Performs a linear transformation of the input followed by an optional bias term
     * and activation function.
     */
    class DC_CNNLayer_Dense final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a dense layer
         * 
         * @param output_units Number of output units
         * @param use_bias Whether to use bias terms
         * @param activation Type of activation function to apply
         * @param leaky_alpha Alpha parameter for Leaky ReLU (default: 0.1)
         */
        explicit DC_CNNLayer_Dense(int output_units, bool use_bias = true,
                ActivationType activation = ActivationType::NONE,
                float leaky_alpha = 0.1f);

        // Helper functions for weight loading
        /**
         * @brief Checks if weights have been loaded for this layer
         * @return true if weights are loaded, false otherwise
         */
        bool weights_loaded() const { return !m_weights.empty(); }
        bool get_use_bias() const { return m_use_bias; }

        /**
         * @brief Checks if bias values have been loaded for this layer
         * @return true if bias values are loaded, false otherwise
         */
        bool bias_loaded() const { return !m_bias.empty(); }
        
        /**
         * @brief Loads weights for the dense layer
         * 
         * Assigns pre-trained weights to the layer. The weights should be
         * properly shaped for the layer's input and output dimensions.
         *
         * @param weights Vector of weight values
         */
        void load_weights(const std::vector<float>& weights) { m_weights = weights; }
        
        /**
         * @brief Loads bias values for the dense layer
         * 
         * Assigns pre-trained bias values to the layer. The bias vector
         * should have a size equal to the number of output units.
         *
         * @param bias Vector of bias values
         */
        void load_bias(const std::vector<float>& bias) { m_bias = bias; }
        
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

        DC_Tensor forward(const DC_Tensor& input) const override;
        
    private:

        /**
         * @brief Computes the weighted sum for a single output unit in the dense layer
         * 
         * Performs matrix multiplication between input features and weights for one output unit.
         * For dense layers, this operates on the entire flattened input (treated as a 1x1 spatial
         * convolution with kernel size equal to input dimensions).
         * 
         * @param input Input tensor containing feature data
         * @param weights Pointer to weight vector (in CHW or HWC format based on mem_order)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (MULTIPLY for standard convolution stepping)
         * @param mem_order Memory layout (CHW or HWC) for indexing
         * @param stats Reference to LayerStats for recording operations
         * 
         * @return float Weighted sum of inputs for the specified output unit (before bias and activation)
         */
        float compute_kernel(const float* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats) const override;

        // config dependent on network architecture
        int m_output_channels;
        bool m_use_bias;
        ActivationType m_activation_type;
        bool m_is_channel_first = true;
    
        // network parameters/weights
        float m_leaky_alpha;
        std::vector<float> m_weights;
        std::vector<float> m_bias;
    };

} // namespace DC_ConvNet 
