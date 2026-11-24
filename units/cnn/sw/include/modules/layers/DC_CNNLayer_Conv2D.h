/******************************************************************************
 * @file    DC_CNNLayer_Conv2D.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   2D Convolutional layer implementation for neural networks
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
#include "DC_CNNComputeKernel.h"

#include <stdexcept>

namespace DC_ConvNet {

    struct LayerStats;
    struct DC_Tensor;

    /**
     * @brief 2D Convolutional layer implementation
     * 
     * Performs 2D convolution with optional bias terms, padding, and activation function.
     * Supports batch normalization for improved training stability and faster convergence.
     */
    class DC_CNNLayer_Conv2D final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a 2D convolutional layer
         * 
         * @param in_channels Number of input channels
         * @param out_channels Number of output channels
         * @param kernel_size Size of the convolutional kernel
         * @param stride Stride of the convolution
         * @param padding Padding size (0 for no padding)
         * @param use_bias Whether to use bias terms (ignored if batch_norm is true)
         * @param batch_norm Whether to use batch normalization
         * @param activation Type of activation function to apply
         * @param leaky_alpha Alpha parameter for Leaky ReLU (default: 0.1)
         * @param eps Small value added to variance for numerical stability
         */
        explicit DC_CNNLayer_Conv2D(int in_channels, int out_channels, int kernel_size, 
                 int stride = 1, int padding = 0, bool use_bias = true,
                 bool batch_norm = false,
                 ActivationType activation = ActivationType::NONE,
                 float leaky_alpha = 0.1f,
                 float eps = 1e-5f);
     
        // Helper functions for weight loading
        /**
         * @brief Checks if weights have been loaded for this layer
         * @return true if weights are loaded, false otherwise
         */
        bool weights_loaded() const { return !m_weights.empty(); }

        /**
         * @brief Checks if bias values have been loaded for this layer
         * @return true if bias values are loaded, false otherwise
         */
        bool bias_loaded() const { return !m_bias.empty(); }

        /**
         * @brief Checks if batch normalization parameters have been loaded
         * @return true if all batch norm parameters are loaded, false otherwise
         */
        bool batch_norm_loaded() const { 
            return m_batch_norm && !m_bn_gamma.empty() && !m_bn_beta.empty() && 
                   !m_bn_mean.empty() && !m_bn_var.empty(); 
        }

        /**
         * @brief Gets the number of input channels
         * @return Number of input channels
         */
        int get_in_channels() const { return m_num_input_channels; }

        /**
         * @brief Gets the number of output channels
         * @return Number of output channels
         */
        int get_out_channels() const { return m_num_output_channels; }

        /**
         * @brief Gets the kernel size
         * @return Size of the convolutional kernel
         */
        int get_kernel_size() const { return m_kernel_size; }

        /**
         * @brief Checks if batch normalization is enabled
         * @return true if batch normalization is enabled, false otherwise
         */
        bool uses_batch_norm() const { return m_batch_norm; }

        // Add batch normalization methods
        /**
         * @brief Sets the batch normalization parameters for this layer
         * 
         * @param gamma Scale parameter for each output channel
         * @param beta Shift parameter for each output channel
         * @param mean Running mean for each output channel
         * @param var Running variance for each output channel
         */
        void set_batch_norm_params(const std::vector<float>& gamma,
            const std::vector<float>& beta,
            const std::vector<float>& mean,
            const std::vector<float>& var)
        {
            m_batch_norm = true;
            m_bn_gamma = gamma;
            m_bn_beta = beta;
            m_bn_mean = mean;
            m_bn_var = var;
        }
        
        // Add weight loading methods
        /**
         * @brief Loads pre-trained weights for the convolutional layer
         * 
         * Sets the convolutional kernel weights. The size of the weights vector
         * should match kernel_size * kernel_size * in_channels * out_channels.
         *
         * @param weights Vector of weight values organized in the expected format
         */
        void load_weights(const std::vector<float>& weights) { m_weights = weights; }
        
        /**
         * @brief Loads bias values for the convolutional layer
         * 
         * Sets the bias values for each output channel. The size of the bias vector
         * should match the number of output channels.
         *
         * @param bias Vector of bias values (one per output channel)
         */
        void load_bias(const std::vector<float>& bias) { m_bias = bias; }

        // Batch normalization fusion methods
        /**
         * @brief Disables batch normalization for this layer
         * 
         * Used after fusing batch normalization parameters into the weights and biases
         * to prevent duplicate application of normalization.
         */
        void disable_batch_norm() { m_batch_norm = false; }
        
        /**
         * @brief Gets the batch normalization scale parameters (gamma)
         * @return Reference to the gamma parameters vector
         */
        const std::vector<float>& get_bn_gamma() const { return m_bn_gamma; }

        /**
         * @brief Gets the batch normalization shift parameters (beta)
         * @return Reference to the beta parameters vector
         */
        const std::vector<float>& get_bn_beta() const { return m_bn_beta; }

        /**
         * @brief Gets the batch normalization running mean
         * @return Reference to the running mean vector
         */
        const std::vector<float>& get_bn_mean() const { return m_bn_mean; }

        /**
         * @brief Gets the batch normalization running variance
         * @return Reference to the running variance vector
         */
        const std::vector<float>& get_bn_var() const { return m_bn_var; }

        /**
         * @brief Gets the layer's weights
         * @return Reference to the weights vector
         */
        std::vector<float>& get_weights() { return m_weights; }

        /**
         * @brief Gets the layer's bias values
         * @return Reference to the bias vector
         */
        std::vector<float>& get_biases() { return m_bias; }

        /**
         * @brief Gets the batch normalization epsilon value
         * @return Epsilon value used for numerical stability
         */
        float get_bn_epsilon() const { return m_eps; }

        /**
         * @brief Enables or disables the use of bias in this layer
         * @param enable True to enable bias, false to disable
         */
        void enable_bias(bool enable) { m_use_bias = enable; }

        /**
         * @brief Checks if the layer uses bias terms
         * @return true if bias is used, false otherwise
         */
        bool get_use_bias() const { return m_use_bias; }

        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

        DC_Tensor forward(const DC_Tensor& input) const override;

    private:
        bool m_batch_norm = false;

        /**
         * @brief Initializes the layer's parameters
         * 
         * @param kernel_size Size of the convolutional kernel
         * @param in_channels Number of input channels
         * @param out_channels Number of output channels
         * @param use_bias Whether to use bias terms
         * @param batch_norm Whether to use batch normalization
         * @param weights Reference to weights vector to initialize
         * @param bias Reference to bias vector to initialize
         * @param bn_gamma Reference to batch norm gamma vector to initialize
         * @param bn_beta Reference to batch norm beta vector to initialize
         * @param bn_mean Reference to batch norm mean vector to initialize
         * @param bn_var Reference to batch norm variance vector to initialize
         */
        static void initialize_parameters(
            int kernel_size,
            int in_channels,
            int out_channels,
            bool use_bias,
            bool batch_norm,
            std::vector<float>& weights,
            std::vector<float>& bias,
            std::vector<float>& bn_gamma,
            std::vector<float>& bn_beta,
            std::vector<float>& bn_mean,
            std::vector<float>& bn_var
        )
        {
            // Initialize weights
            weights.resize(kernel_size * kernel_size * in_channels * out_channels);

            // Initialize bias if used (not used with batch norm)
            if (use_bias) {
                bias.resize(out_channels);
            }

            // Initialize batch normalization parameters if used
            if (batch_norm) {
                bn_gamma.resize(out_channels, 1.0f);     // Initialize scale to 1
                bn_beta.resize(out_channels, 0.0f);      // Initialize shift to 0
                bn_mean.resize(out_channels, 0.0f);      // Initialize mean to 0
                bn_var.resize(out_channels, 1.0f);       // Initialize variance to 1
            }
        }

        /**
         * @brief Precomputes batch normalization scale and shift parameters
         *
         * Calculates fused batch normalization parameters for each output channel
         * to optimize the convolution computation. The parameters are computed as:
         * scale = gamma / sqrt(variance + epsilon)
         * shift = beta - mean * scale
         *
         * @param stats Performance statistics tracker
         * @return tuple of vectors for precomputed scale parameters and precomputed shift parameters
         */
        std::tuple<std::vector<float>, std::vector<float>> precompute_batch_norm_params(LayerStats& stats) const;

        float compute_kernel(
            const float* const ,
            const float* const ,
            const DC_ComputeKernelParams* const ,
            StrideMode ,
            MEM_ORDER ,
            LayerStats& 
        ) const override {
			return 0.f; // Not used in this layer
        }


        /**
         * @brief Computes kernel operation for 2D convolution layer
         * 
         * Performs 2D convolution kernel computation at a specific spatial position
         * for a given output channel. This function implements the core convolution
         * operation, computing the dot product between input patches and kernel weights
         * across all input channels and kernel spatial dimensions.
         * 
         * The function applies a 2D kernel of size (kernel_size x kernel_size) to
         * the input tensor at position (out_row_idx, out_col_idx), computing:
         * sum(input[y][x][c] * kernel[ky][kx][c][out_channel]) for all spatial
         * positions (y,x) in the kernel and all channels c.
         * 
         * @param input Input tensor containing feature maps
         * @param weights Pointer to weight vector (flattened kernel weights)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (VALID, SAME, or MULTIPLY)
         * @param mem_order Memory order (HWC or CHW) for index calculation
         * @param stats Performance statistics recorder for operation counting
         * @return float Computed convolution result for the specified output channel
         */
        float compute_kernel(
            const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats
        ) const;

        // Layer configuration
        int m_num_input_channels;
        int m_num_output_channels;
        int m_kernel_size;
        int m_stride;
        int m_padding;
        bool m_use_bias;
        ActivationType m_activation_type;
        float m_leaky_alpha;
        float m_eps;  // Batch norm epsilon

        // Convolution parameters
        std::vector<float> m_weights;
        std::vector<float> m_bias;

        // Batch normalization parameters
        std::vector<float> m_bn_gamma;     // Scale parameter
        std::vector<float> m_bn_beta;      // Shift parameter
        std::vector<float> m_bn_mean;      // Running mean
        std::vector<float> m_bn_var;       // Running variance
    };

} // namespace DC_ConvNet 
