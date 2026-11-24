/******************************************************************************
 * @file    stats.cpp
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Statistics utilities implementation for CNN layer performance monitoring
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

#include "DC_CNNLayer_Stats.h"

namespace DC_ConvNet {

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
        LayerStats& stats) {
        stats.record_layer_configuration(input,
            out_height, out_width, out_channels, use_bias, kernel_size,
            stride, padding, batch_norm, activation_type);

        // Theoretical counts aligned with runtime accounting
        const size_t elements = static_cast<size_t>(out_channels) * out_height * out_width;
        const size_t kernel_elems = static_cast<size_t>(in_channels) * kernel_size * kernel_size;

        // Memory loads
        size_t loads_conv = elements * kernel_elems * 2; // input + weight per kernel element
        size_t loads_bias = (use_bias && !batch_norm) ? elements : 0; // bias per output element
        size_t loads_bn_per_element = batch_norm ? elements * 2 : 0; // scale + shift per element
        size_t loads_bn_precompute = batch_norm ? static_cast<size_t>(out_channels) * 4 : 0; // gamma, beta, mean, var per channel
        stats.theoretical_operations(OperationType::MEMORY_LOAD, loads_conv + loads_bias + loads_bn_per_element + loads_bn_precompute);

        // Memory stores
        size_t stores_output = elements; // one store per output element
        size_t stores_bn_precompute = batch_norm ? static_cast<size_t>(out_channels) * 2 : 0; // store precomputed scale, shift
        stats.theoretical_operations(OperationType::MEMORY_STORE, stores_output + stores_bn_precompute);

        // Arithmetic operations
        size_t mul_conv = elements * kernel_elems; // one multiply per kernel element
        size_t add_conv = mul_conv; // one addition per multiply-accumulate
        size_t add_bias = (use_bias && !batch_norm) ? elements : 0; // add bias per element
        size_t mul_bn = batch_norm ? elements : 0; // value * scale
        size_t add_bn = batch_norm ? elements : 0; // + shift
        size_t mul_bn_pre = batch_norm ? static_cast<size_t>(out_channels) * 3 : 0; // div (as mul) + scale mul + shift mul
        size_t add_bn_pre = batch_norm ? static_cast<size_t>(out_channels) * 2 : 0; // var+eps + shift add
        size_t comp_bias = (use_bias && !batch_norm) ? elements : 0; // bias branch check per element
        size_t comp_bn = batch_norm ? elements : 0; // bn branch check per element
        size_t comp_bn_pre = batch_norm ? static_cast<size_t>(out_channels) : 0; // variance clamp check per channel
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, mul_conv + mul_bn + mul_bn_pre);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, add_conv + add_bias + add_bn + add_bn_pre);
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, comp_bias + comp_bn + comp_bn_pre);
    }

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
        LayerStats& stats)
    {
        stats.record_layer_configuration(
            input, out_height, out_width, out_channels, use_bias, kernel_size,
            stride, padding, false, activation_type);

        // Count valid spatial kernel applications (same predicate as compute_kernel skips).
        // Input-centric: each (ih, iw, kh, kw) maps to one output if in bounds.
        size_t valid_spatial = 0;
        for (int ih = 0; ih < input.m_height; ++ih) {
            for (int iw = 0; iw < input.m_width; ++iw) {
                for (int kh = 0; kh < kernel_size; ++kh) {
                    for (int kw = 0; kw < kernel_size; ++kw) {
                        const int oh = ih * stride - padding + kh;
                        const int ow = iw * stride - padding + kw;
                        if (oh >= 0 && oh < out_height && ow >= 0 && ow < out_width) {
                            ++valid_spatial;
                        }
                    }
                }
            }
        }

        const size_t num_macs =
            valid_spatial * static_cast<size_t>(in_channels) * static_cast<size_t>(out_channels);
        const size_t elements =
            static_cast<size_t>(out_channels) * static_cast<size_t>(out_height) * static_cast<size_t>(out_width);
        const size_t loads_bias = use_bias ? elements : 0;
        const size_t add_bias = use_bias ? elements : 0;
        const size_t comp_bias = use_bias ? elements : 0;

        stats.theoretical_operations(OperationType::MEMORY_LOAD, num_macs * 2 + loads_bias);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, num_macs);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, num_macs + add_bias);
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, comp_bias);
    }

    void populate_stats_maxpool(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int channels,
        int kernel_size,
        int stride,
        LayerStats& stats)
    {
        // Populate layer configuration for performance stats
        stats.record_layer_configuration(
            input, out_height, out_width, channels, false,
            kernel_size, stride, 0, false, ActivationType::NONE
        );

        const size_t elements = static_cast<size_t>(channels) * out_height * out_width;
        const size_t window_elems = static_cast<size_t>(kernel_size) * kernel_size;

        size_t theory_pool_loads = elements * window_elems;   // one load per window element
        size_t theory_pool_stores = elements;                 // one store per output element
        size_t theory_pool_comps = elements * window_elems;   // one comparison per window element
        stats.theoretical_operations(OperationType::MEMORY_LOAD, theory_pool_loads);
        stats.theoretical_operations(OperationType::MEMORY_STORE, theory_pool_stores);
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, theory_pool_comps);
    }

    void populate_stats_route(
        const std::vector<DC_Tensor>& layer_outputs,
        const std::vector<int>& layer_indices,
        const std::vector<int>& input_sizes,
        int groups,
        int height,
        int width,
        int channels,
        LayerStats& stats)
    {
        size_t theory_route_loads = 0u;
        size_t theory_route_stores = 0u;

        // Sum input channels across all routed layers
        int total_input_channels = 0;
        for (size_t i = 0; i < layer_indices.size(); ++i) {
            const DC_Tensor& source = layer_outputs[layer_indices[i]];
            total_input_channels += source.m_channels;

            const auto input_size = input_sizes[i];
            const auto part_input_size = input_size / groups;
            theory_route_loads += part_input_size;
            theory_route_stores += part_input_size;
        }

        // Populate layer configuration for performance stats
        stats.config.input_height = height;
        stats.config.input_width = width;
        stats.config.input_channels = total_input_channels;
        stats.config.output_height = height;
        stats.config.output_width = width;
        stats.config.output_channels = channels;

        // Theoretical operations counts
        stats.theoretical_operations(OperationType::MEMORY_LOAD, theory_route_loads);
        stats.theoretical_operations(OperationType::MEMORY_STORE, theory_route_stores);
    }

    void populate_stats_upsample(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int stride,
        LayerStats& stats)
    {
        // Populate layer configuration for performance stats
        stats.config.input_height = input.m_height;
        stats.config.input_width = input.m_width;
        stats.config.input_channels = input.m_channels;
        stats.config.output_height = out_height;
        stats.config.output_width = out_width;
        stats.config.output_channels = input.m_channels;
        stats.config.stride = stride;

        // Theoretical operations counts: each output element corresponds to one load + one store
        const size_t input_size = static_cast<size_t>(input.m_width) *
                                  static_cast<size_t>(input.m_height) *
                                  static_cast<size_t>(input.m_channels) *
                                  static_cast<size_t>(stride) *
                                  static_cast<size_t>(stride);
        stats.theoretical_operations(OperationType::MEMORY_LOAD, input_size);
        stats.theoretical_operations(OperationType::MEMORY_STORE, input_size);
    }

    void populate_stats_flatten(
        const DC_Tensor& input,
        LayerStats& stats)
    {
        stats.record_operation(OperationType::MEMORY_LOAD, input.m_data.size());  // Reading all input data
        stats.record_operation(OperationType::MEMORY_STORE, input.m_data.size()); // Writing all data to output

        stats.record_layer_configuration(
            input, 1, 1, input.m_height * input.m_width * input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE
        );

        // Add theoretical operations counts
        size_t theory_flatten_ops = static_cast<size_t>(input.m_height) *
                                    static_cast<size_t>(input.m_width) *
                                    static_cast<size_t>(input.m_channels);
        stats.theoretical_operations(OperationType::MEMORY_LOAD, theory_flatten_ops);
        stats.theoretical_operations(OperationType::MEMORY_STORE, theory_flatten_ops);
    }

    void populate_stats_softmax(
        const DC_Tensor& input,
        LayerStats& stats)
    {
        // Populate layer configuration for performance stats
        stats.record_layer_configuration(
            input, input.m_height, input.m_width,
            input.m_channels, false, 1, 1, 0, false, ActivationType::NONE
        );

        // Add theoretical operations counts
        stats.theoretical_operations(OperationType::MEMORY_LOAD, 3 * input.m_data.size());
        stats.theoretical_operations(OperationType::MEMORY_STORE, 2 * input.m_data.size());
    }

    void populate_stats_dense(
        const DC_Tensor& input,
        int input_channels,
        int output_channels,
        bool use_bias,
        ActivationType activation_type,
        LayerStats& stats)
    {
        stats.record_layer_configuration(input, 1, 1, output_channels, use_bias, 0, 0, 0, false, activation_type);
        // Theoretical memory ops: for each output unit, load one input and one weight per input element, plus optional bias load
        stats.theoretical_operations(OperationType::MEMORY_LOAD, output_channels * (2 * input_channels + (use_bias ? 1 : 0)));
        stats.theoretical_operations(OperationType::MEMORY_STORE, output_channels);

        // Theoretical compute ops: one multiply and one add per input element; bias adds one extra addition per output unit
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, output_channels * input_channels);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, output_channels * input_channels + (use_bias ? output_channels : 0));
        // Theoretical comparison ops: branch check for bias per output unit when bias is used
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, use_bias ? output_channels : 0);
    }

    void populate_stats_yolo(
        size_t num_xy_entries,
        size_t num_confidence_class_entries,
        size_t num_anchors,
        LayerStats& stats)
    {
        // Calculate theoretical memory operations
        size_t theory_coord_size = num_xy_entries * num_anchors; // x,y coordinates per anchor
        size_t theory_obj_class_size = num_confidence_class_entries * num_anchors; // objectness and classes
        size_t theory_scale_size = num_xy_entries * num_anchors; // scaling operations

        // Total theoretical memory operations
        size_t theory_yolo_loads = theory_coord_size + theory_obj_class_size + theory_scale_size;
        size_t theory_yolo_stores = theory_coord_size + theory_obj_class_size + theory_scale_size;

        stats.theoretical_operations(OperationType::MEMORY_LOAD, theory_yolo_loads);
        stats.theoretical_operations(OperationType::MEMORY_STORE, theory_yolo_stores);

        // Theoretical arithmetic operations
        // Sigmoid activations on x,y and objectness+classes: each has 1 ADD, 1 OTHER (exp), 1 MUL (division as multiply)
        size_t activations_count = (num_xy_entries + num_confidence_class_entries) * num_anchors;
        // Scale-add on x,y: each has 1 MUL, 1 ADD
        size_t scale_add_count = num_xy_entries * num_anchors;

        size_t theory_yolo_adds = activations_count + scale_add_count;  // sigmoid ADD + scale-add ADD
        size_t theory_yolo_muls = activations_count + scale_add_count;  // sigmoid MUL + scale-add MUL
        size_t theory_yolo_other = activations_count;                   // exp operations in sigmoid

        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, theory_yolo_adds);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, theory_yolo_muls);
        stats.theoretical_operations(OperationType::ARITHMETIC_OTHER, theory_yolo_other);
    }

    void populate_stats_shortcut(
        const DC_Tensor& input,
        LayerStats& stats)
    {
        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE
        );

        const size_t elements = input.m_data.size();
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 2); // Load from two input tensors
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);    // Store to output tensor
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements);  // Element-wise addition
    }

    void populate_stats_avgpool(
        const DC_Tensor& input,
        int out_height,
        int out_width,
        int kernel_height,
        int kernel_width,
        int stride_y,
        int stride_x,
        LayerStats& stats)
    {
        stats.record_layer_configuration(
            input, out_height, out_width, input.m_channels,
            false, kernel_height, stride_y, 0, false, ActivationType::NONE
        );

        const size_t elements = static_cast<size_t>(out_height) * out_width * input.m_channels;
        const size_t window_size = static_cast<size_t>(kernel_height) * kernel_width;
        
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * window_size);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements * window_size);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements); // div as mul
    }

    void populate_stats_l2norm(
        const DC_Tensor& input,
        LayerStats& stats)
    {
        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE
        );

        const size_t elements = input.m_data.size();
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 2); // Two passes
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements * 2); // val*val and val/norm
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements); // sum
        stats.theoretical_operations(OperationType::ARITHMETIC_OTHER, input.m_height * input.m_width); // sqrt
    }

    void populate_stats_gemm(
        int rows,
        int in_features,
        int out_features,
        bool use_bias,
        LayerStats& stats)
    {
        const uint64_t num_outputs = static_cast<uint64_t>(rows) * static_cast<uint64_t>(out_features);
        const uint64_t num_macs = num_outputs * static_cast<uint64_t>(in_features);

        // Per MAC: load input + weight; per output: optional bias load; one store per output
        stats.theoretical_operations(
            OperationType::MEMORY_LOAD,
            num_macs * 2 + (use_bias ? num_outputs : 0));
        stats.theoretical_operations(OperationType::MEMORY_STORE, num_outputs);

        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, num_macs);
        stats.theoretical_operations(
            OperationType::ARITHMETIC_ADD,
            num_macs + (use_bias ? num_outputs : 0));
    }

    void populate_stats_matmul(
        int batch,
        int m,
        int k,
        int n,
        LayerStats& stats)
    {
        const uint64_t num_outputs =
            static_cast<uint64_t>(batch) * static_cast<uint64_t>(m) * static_cast<uint64_t>(n);
        const uint64_t num_macs = num_outputs * static_cast<uint64_t>(k);

        stats.theoretical_operations(OperationType::MEMORY_LOAD, num_macs * 2);
        stats.theoretical_operations(OperationType::MEMORY_STORE, num_outputs);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, num_macs);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, num_macs);
    }

    void populate_stats_reshape(
        size_t elements,
        bool hwc_round_trip,
        LayerStats& stats)
    {
        // Identity reshape: one copy. HWC ONNX round-trip: logical convert + materialize.
        const size_t passes = hwc_round_trip ? 2 : 1;
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * passes);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements * passes);
    }

    void populate_stats_transpose(
        size_t elements,
        LayerStats& stats)
    {
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
    }

    void populate_stats_concat(
        size_t output_elements,
        LayerStats& stats)
    {
        stats.theoretical_operations(OperationType::MEMORY_LOAD, output_elements);
        stats.theoretical_operations(OperationType::MEMORY_STORE, output_elements);
    }

    void populate_stats_add(
        size_t elements,
        int num_tensor_addends,
        bool has_operand,
        LayerStats& stats)
    {
        // Copy base, then for each addend/operand: load dst + src, add, store.
        const size_t add_passes =
            static_cast<size_t>(num_tensor_addends) + (has_operand ? 1u : 0u);
        stats.theoretical_operations(
            OperationType::MEMORY_LOAD,
            elements + add_passes * elements * 2);
        stats.theoretical_operations(
            OperationType::MEMORY_STORE,
            elements + add_passes * elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, add_passes * elements);
    }

    void populate_stats_layernorm(
        size_t elements,
        int normalized_size,
        LayerStats& stats)
    {
        const size_t outer = elements / static_cast<size_t>(normalized_size);

        // Mean: N loads + N adds + 1 div(mul) per group
        // Var:  N loads + N sub + N mul + N add + 1 div + 1 add(eps) + 1 sqrt + 1 recip(mul)
        // Norm: N loads + N sub + N mul + N gamma load + N mul + N beta load + N add + N store
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 5);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements * 5 + outer);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements * 3 + outer * 3);
        stats.theoretical_operations(OperationType::ARITHMETIC_OTHER, outer);
    }

    void populate_stats_gather(
        size_t output_elements,
        LayerStats& stats)
    {
        // Gather into logical buffer, then logical_to_tensor materializes HWC/CHW.
        stats.theoretical_operations(OperationType::MEMORY_LOAD, output_elements * 2);
        stats.theoretical_operations(OperationType::MEMORY_STORE, output_elements * 2);
    }

    void populate_stats_mul(
        size_t elements,
        bool use_loaded_operand,
        LayerStats& stats)
    {
        if (use_loaded_operand) {
            // Copy lhs, then per element: load dst + channel operand, mul, store.
            stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 3);
            stats.theoretical_operations(OperationType::MEMORY_STORE, elements * 2);
            stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements);
        }
        else {
            // Scalar: load input, multiply by factor, store.
            stats.theoretical_operations(OperationType::MEMORY_LOAD, elements);
            stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
            stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements);
        }
    }

    void populate_stats_softmax_nd(
        size_t elements,
        LayerStats& stats)
    {
        // max: load+comp; exp: load+sub+exp+store+add; normalize: load+div+store
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 3);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements * 2);
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements * 2);
        stats.theoretical_operations(OperationType::ARITHMETIC_OTHER, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements);
    }

    void populate_stats_skip_layernorm(
        size_t elements,
        LayerStats& stats)
    {
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements * 2);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements);
    }

    void populate_stats_gelu(
        size_t elements,
        LayerStats& stats)
    {
        // gelu = 0.5 * x * (1 + erf(x / sqrt(2))): load, 3 mul, 1 add, 1 erf, store
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, elements * 3);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_OTHER, elements);
    }

    void populate_stats_slice(
        size_t output_elements,
        LayerStats& stats)
    {
        stats.theoretical_operations(OperationType::MEMORY_LOAD, output_elements);
        stats.theoretical_operations(OperationType::MEMORY_STORE, output_elements);
    }

    void populate_stats_relu(
        size_t elements,
        LayerStats& stats)
    {
        stats.theoretical_operations(OperationType::MEMORY_LOAD, elements);
        stats.theoretical_operations(OperationType::MEMORY_STORE, elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_COMP, elements);
    }

    void populate_stats_resize(
        size_t output_elements,
        LayerStats& stats)
    {
        // Bilinear: 4 neighbor loads, 6 muls + 7 adds for lerps, 1 store per output.
        stats.theoretical_operations(OperationType::MEMORY_LOAD, output_elements * 4);
        stats.theoretical_operations(OperationType::MEMORY_STORE, output_elements);
        stats.theoretical_operations(OperationType::ARITHMETIC_MUL, output_elements * 6);
        stats.theoretical_operations(OperationType::ARITHMETIC_ADD, output_elements * 7);
    }

} // namespace DC_ConvNet

