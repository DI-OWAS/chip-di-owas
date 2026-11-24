/******************************************************************************
 * @file    stats.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Statistics utilities for CNN layer performance monitoring
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

#include "DC_PerformanceStats.h"
#include "DC_CNN_activation_types.h"
#include "DC_tensor.h"

namespace DC_ConvNet {

    /**
     * @brief Populates convolution layer statistics for performance monitoring
     * 
     * @param input Input tensor
     * @param use_bias Whether bias is used
     * @param batch_norm Whether batch normalization is used
     * @param out_channels Number of output channels
     * @param out_height Output height
     * @param out_width Output width
     * @param in_channels Number of input channels
     * @param kernel_size Size of the convolutional kernel
     * @param stride Stride of the convolution
     * @param padding Padding size
     * @param activation_type Type of activation function
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_conv(
        const DC_Tensor& input,
        bool use_bias,
        bool batch_norm,
        int out_channels,
        int out_height,
        int out_width,
        int in_channels,
        int kernel_size,
        int stride,
        int padding,
        ActivationType activation_type,
        LayerStats& stats
    );

    /**
     * @brief Populates DeConv2D (transposed convolution) layer statistics
     *
     * Unlike dense convolution, transposed convolution only performs a MAC when
     * (out + pad - kernel) is divisible by stride and lands in the input. Theoretical
     * counts therefore use the number of valid contributions, not out * in * k * k.
     */
    void populate_stats_deconv(
        const DC_Tensor& input,
        bool use_bias,
        int out_channels,
        int out_height,
        int out_width,
        int in_channels,
        int kernel_size,
        int stride,
        int padding,
        ActivationType activation_type,
        LayerStats& stats
    );

    /**
     * @brief Populates MaxPool2D layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads, stores and comparisons for the pooling operation.
     *
     * @param input Input tensor used to calculate statistics
     * @param out_height Height of the output tensor
     * @param out_width Width of the output tensor
     * @param channels Number of channels
     * @param kernel_size Size of the pooling kernel
     * @param stride Stride of the pooling operation
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_maxpool(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int channels,
        int kernel_size,
        int stride,
        LayerStats& stats
    );

    /**
     * @brief Populates Route layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads and stores for the routing operation.
     *
     * @param layer_outputs Vector of input tensors
     * @param layer_indices Indices of layers used by the route layer
     * @param input_sizes Precomputed total input sizes (h*w*c) per routed layer
     * @param groups Number of groups used in the route layer
     * @param stats Reference to LayerStats object to populate
     * @param output Output tensor used for dimension information
     */
    void populate_stats_route(
        const std::vector<DC_Tensor>& layer_outputs,
        const std::vector<int>& layer_indices,
        const std::vector<int>& input_sizes,
        int groups,
        int height,
        int width,
        int channels,
        LayerStats& stats
    );

    /**
     * @brief Populates Upsample layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads and stores for the upsampling operation.
     *
     * @param input Input tensor used to calculate statistics
     * @param out_height Height of the output tensor
     * @param out_width Width of the output tensor
     * @param stride Upsampling factor
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_upsample(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int stride,
        LayerStats& stats
    );

    /**
     * @brief Populates Flatten layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads and stores for the flattening operation.
     *
     * @param stats Reference to LayerStats object to populate
     * @param input Input tensor used to calculate statistics
     */
    void populate_stats_flatten(
        const DC_Tensor& input,
        LayerStats& stats
    );

    /**
     * @brief Populates Softmax layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads and stores for the softmax operation.
     *
     * @param stats Reference to LayerStats object to populate
     * @param input Input tensor used to calculate statistics
     */
    void populate_stats_softmax(
        const DC_Tensor& input,
        LayerStats& stats
    );

    /**
     * @brief Populates Dense layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads, stores, and arithmetic operations for the dense layer.
     *
     * @param stats Reference to LayerStats object to populate
     * @param input Input tensor used to calculate statistics
     * @param input_channels Number of input channels
     * @param output_channels Number of output channels
     * @param use_bias Whether bias is used
     * @param activation_type Type of activation function
     */
    void populate_stats_dense(
        const DC_Tensor& input,
        int input_channels,
        int output_channels,
        bool use_bias,
        ActivationType activation_type,
        LayerStats& stats
    );

    /**
     * @brief Populates YOLO layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads, stores, and arithmetic operations for the YOLO detection operations.
     *
     * @param num_xy_entries Number of x,y coordinate entries across all grid cells
     * @param num_confidence_class_entries Number of objectness and class probability entries
     * @param num_anchors Number of anchor boxes
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_yolo(
        size_t num_xy_entries,
        size_t num_confidence_class_entries,
        size_t num_anchors,
        LayerStats& stats
    );

    /**
     * @brief Populates Shortcut layer statistics for performance monitoring
     *
     * Records memory operations and layer configuration for performance tracking.
     * Calculates theoretical memory loads and stores for the element-wise addition operation.
     *
     * @param input Input tensor used to calculate statistics
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_shortcut(
        const DC_Tensor& input,
        LayerStats& stats
    );

    /**
     * @brief Populates AvgPool layer statistics for performance monitoring
     *
     * @param input Input tensor used to calculate statistics
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_avgpool(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int kernel_height,
        int kernel_width,
        int stride_y,
        int stride_x,
        LayerStats& stats
    );

    /**
     * @brief Populates L2Norm layer statistics for performance monitoring
     *
     * @param input Input tensor used to calculate statistics
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_l2norm(
        const DC_Tensor& input,
        LayerStats& stats
    );

    /**
     * @brief Populates Gemm layer statistics for performance monitoring
     *
     * Records theoretical memory and arithmetic ops for Y = X @ W^T (+ bias).
     *
     * @param rows Number of input/output row vectors
     * @param in_features Input feature dimension (K)
     * @param out_features Output feature dimension (N)
     * @param use_bias Whether bias is added
     * @param stats Reference to LayerStats object to populate
     */
    void populate_stats_gemm(
        int rows,
        int in_features,
        int out_features,
        bool use_bias,
        LayerStats& stats
    );

    /**
     * @brief Populates MatMul layer statistics for performance monitoring
     *
     * Records theoretical ops for batched Y = A @ B with shapes (batch, m, k) @ (batch, k, n).
     */
    void populate_stats_matmul(
        int batch,
        int m,
        int k,
        int n,
        LayerStats& stats
    );

    void populate_stats_reshape(
        size_t elements,
        bool hwc_round_trip,
        LayerStats& stats
    );

    void populate_stats_transpose(
        size_t elements,
        LayerStats& stats
    );

    void populate_stats_concat(
        size_t output_elements,
        LayerStats& stats
    );

    void populate_stats_add(
        size_t elements,
        int num_tensor_addends,
        bool has_operand,
        LayerStats& stats
    );

    void populate_stats_layernorm(
        size_t elements,
        int normalized_size,
        LayerStats& stats
    );

    void populate_stats_gather(
        size_t output_elements,
        LayerStats& stats
    );

    void populate_stats_mul(
        size_t elements,
        bool use_loaded_operand,
        LayerStats& stats
    );

    void populate_stats_softmax_nd(
        size_t elements,
        LayerStats& stats
    );

    void populate_stats_skip_layernorm(
        size_t elements,
        LayerStats& stats
    );

    void populate_stats_gelu(
        size_t elements,
        LayerStats& stats
    );

    void populate_stats_slice(
        size_t output_elements,
        LayerStats& stats
    );

    void populate_stats_relu(
        size_t elements,
        LayerStats& stats
    );

    void populate_stats_resize(
        size_t output_elements,
        LayerStats& stats
    );

} // namespace DC_ConvNet

