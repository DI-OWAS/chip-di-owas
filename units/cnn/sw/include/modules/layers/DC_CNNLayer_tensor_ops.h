/******************************************************************************
 * @file    DC_CNNLayer_tensor_ops.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Shared tensor helpers for structural CNN layers
 * @version 1.0.0
 * @date    2026-07-01
 ******************************************************************************/

#pragma once

#include "DC_tensor.h"

#include <cmath>
#include <algorithm>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace DC_ConvNet {

    /**
     * @brief Resolve a relative layer index into an absolute index in layer_outputs
     *
     * Negative indices count from the end (Python-style). Throws if out of bounds.
     *
     * @param relative_index Relative or absolute index
     * @param layer_outputs_size Number of tensors in the history
     * @return size_t Absolute index into layer_outputs
     * @throws std::runtime_error If the resolved index is out of range
     */
    inline size_t resolve_relative_index(int relative_index, size_t layer_outputs_size) {
        int resolved = relative_index;
        if (relative_index < 0) {
            resolved = static_cast<int>(layer_outputs_size) + relative_index;
        }
        if (resolved < 0 || static_cast<size_t>(resolved) >= layer_outputs_size) {
            throw std::runtime_error(
                "Relative layer index " + std::to_string(relative_index) +
                " is out of bounds for " + std::to_string(layer_outputs_size) + " layer outputs");
        }
        return static_cast<size_t>(resolved);
    }

    /**
     * @brief Total number of elements in a tensor (height × width × channels)
     *
     * @param tensor Input tensor
     * @return int Element count
     */
    inline int tensor_element_count(const DC_Tensor& tensor) {
        return tensor.m_height * tensor.m_width * tensor.m_channels;
    }

    /**
     * @brief Map a generic shape vector to HWC dimensions (pack trailing dims into channels)
     *
     * @param shape Logical shape (1D–ND)
     * @param[out] height Resulting height
     * @param[out] width Resulting width
     * @param[out] channels Resulting channels (product of dims from index 2)
     * @throws std::runtime_error If @p shape is empty
     */
    inline void shape_to_hwc(const std::vector<int>& shape, int& height, int& width, int& channels) {
        if (shape.empty()) {
            throw std::runtime_error("Shape must not be empty");
        }
        if (shape.size() == 1) {
            height = shape[0];
            width = 1;
            channels = 1;
            return;
        }
        if (shape.size() == 2) {
            height = shape[0];
            width = shape[1];
            channels = 1;
            return;
        }
        height = shape[0];
        width = shape[1];
        channels = 1;
        for (size_t i = 2; i < shape.size(); ++i) {
            channels *= shape[i];
        }
    }

    /**
     * @brief Product of shape dimensions starting at @p start_index
     *
     * @param shape Logical shape
     * @param start_index First dimension included in the product
     * @return int Product of shape[start_index..]
     */
    inline int shape_tail_product(const std::vector<int>& shape, size_t start_index) {
        int product = 1;
        for (size_t i = start_index; i < shape.size(); ++i) {
            product *= shape[i];
        }
        return product;
    }

    /**
     * @brief Convert logical ONNX coordinates to HWC (height, width, channel) indices
     *
     * @param logical_shape Logical tensor shape
     * @param coords Coordinates in the logical layout
     * @param[out] height HWC height index
     * @param[out] width HWC width index
     * @param[out] channels HWC channel index
     */
    inline void logical_coords_to_hwc(
        const std::vector<int>& logical_shape,
        const std::vector<int>& coords,
        int& height,
        int& width,
        int& channels) {
        if (logical_shape.size() == 4) {
            channels = coords[1];
            height = coords[2];
            width = coords[3];
            return;
        }

        if (logical_shape.size() == 3) {
            if (logical_shape[0] == 1 && logical_shape[1] == logical_shape[2]) {
                height = coords[1];
                width = coords[2];
                channels = 0;
                return;
            }
            height = coords[0];
            width = coords[1];
            channels = coords[2];
            return;
        }

        if (logical_shape.size() == 2) {
            height = coords[0];
            width = coords[1];
            channels = 0;
            return;
        }

        if (logical_shape.size() == 1) {
            height = coords[0];
            width = 0;
            channels = 0;
            return;
        }

        height = coords[0];
        width = coords[1];
        channels = 0;
        int stride = 1;
        for (int i = static_cast<int>(logical_shape.size()) - 1; i >= 2; --i) {
            channels += coords[i] * stride;
            stride *= logical_shape[i];
        }
    }

    /**
     * @brief Write a value at HWC coordinates, respecting the tensor memory order
     *
     * @param tensor Destination tensor
     * @param height Height index
     * @param width Width index
     * @param channels Channel index
     * @param value Value to store
     */
    inline void tensor_set_hwc(DC_Tensor& tensor, int height, int width, int channels, float value) {
        if (tensor.m_mem_order == MEM_ORDER::HWC) {
            tensor.m_data[static_cast<size_t>(
                (height * tensor.m_width + width) * tensor.m_channels + channels)] = value;
            return;
        }

        tensor.m_data[static_cast<size_t>(
            channels * tensor.m_height * tensor.m_width + height * tensor.m_width + width)] = value;
    }

    /**
     * @brief Read a value at HWC coordinates, respecting the tensor memory order
     *
     * @param tensor Source tensor
     * @param height Height index
     * @param width Width index
     * @param channels Channel index
     * @return float Value at the given coordinates
     */
    inline float tensor_at_hwc(const DC_Tensor& tensor, int height, int width, int channels) {
        if (tensor.m_mem_order == MEM_ORDER::HWC) {
            return tensor.m_data[static_cast<size_t>(
                (height * tensor.m_width + width) * tensor.m_channels + channels)];
        }

        return tensor.m_data[static_cast<size_t>(
            channels * tensor.m_height * tensor.m_width + height * tensor.m_width + width)];
    }

    /**
     * @brief Map a logical ONNX shape to DC_Tensor height/width/channels.
     *
     * Matches Depth-Anything-V2/export_layer_fixtures.py logical_shape_to_tensor_dims.
     * 4D [N, C, H, W] -> (H, W, C)
     * 3D [d0, d1, d2] -> (d0, d1, d2) except square batch-1 maps to (d1, d2, 1)
     */
    inline void logical_shape_to_tensor_dims(
        const std::vector<int>& logical_shape,
        int& height,
        int& width,
        int& channels) {
        if (logical_shape.empty()) {
            height = 1;
            width = 1;
            channels = 1;
            return;
        }

        if (logical_shape.size() == 4) {
            channels = logical_shape[1];
            height = logical_shape[2];
            width = logical_shape[3];
            return;
        }

        if (logical_shape.size() == 3
            && logical_shape[0] == 1
            && logical_shape[1] == logical_shape[2]) {
            height = logical_shape[1];
            width = logical_shape[2];
            channels = 1;
            return;
        }

        if (logical_shape.size() == 1) {
            height = logical_shape[0];
            width = 1;
            channels = 1;
            return;
        }

        if (logical_shape.size() == 2) {
            height = logical_shape[0];
            width = logical_shape[1];
            channels = 1;
            return;
        }

        if (logical_shape.size() == 3) {
            height = logical_shape[0];
            width = logical_shape[1];
            channels = shape_tail_product(logical_shape, 2);
            return;
        }

        shape_to_hwc(logical_shape, height, width, channels);
    }

    /**
     * @brief Build a 3-element HWC shape vector
     *
     * @param height Height
     * @param width Width
     * @param channels Channels
     * @return std::vector<int> {height, width, channels}
     */
    inline std::vector<int> hwc_to_shape(int height, int width, int channels) {
        return { height, width, channels };
    }

    /**
     * @brief Resolve a shape that may contain a single -1 inferred dimension
     *
     * @param shape Shape with at most one -1 entry
     * @param total_elements Total element count that the shape must match
     * @return std::vector<int> Fully resolved positive shape
     * @throws std::runtime_error On invalid shapes or element-count mismatch
     */
    inline std::vector<int> resolve_shape_with_negative_dim(
        const std::vector<int>& shape,
        int total_elements) {
        std::vector<int> resolved = shape;
        int negative_count = 0;
        int known_product = 1;
        size_t negative_index = 0;

        for (size_t i = 0; i < resolved.size(); ++i) {
            if (resolved[i] == -1) {
                ++negative_count;
                negative_index = i;
            } else if (resolved[i] < 0) {
                throw std::runtime_error("Invalid negative dimension in shape (only -1 is allowed)");
            } else {
                known_product *= resolved[i];
            }
        }

        if (negative_count > 1) {
            throw std::runtime_error("Shape may contain at most one -1 dimension");
        }
        if (negative_count == 1) {
            if (known_product == 0 || total_elements % known_product != 0) {
                throw std::runtime_error("Cannot infer -1 dimension for reshape");
            }
            resolved[negative_index] = total_elements / known_product;
        }

        const auto resolved_product = std::accumulate(
            resolved.begin(), resolved.end(), 1, std::multiplies<int>());
        if (resolved_product != total_elements) {
            throw std::runtime_error("Reshape shape does not match input element count");
        }

        return resolved;
    }

    /**
     * @brief Convert multi-dimensional indices to a flat row-major linear index
     *
     * @param indices Per-dimension indices
     * @param shape Tensor shape
     * @return size_t Linear index
     */
    inline size_t linear_index(
        const std::vector<int>& indices,
        const std::vector<int>& shape) {
        size_t index = 0;
        size_t stride = 1;
        for (int dim = static_cast<int>(shape.size()) - 1; dim >= 0; --dim) {
            index += static_cast<size_t>(indices[static_cast<size_t>(dim)]) * stride;
            stride *= static_cast<size_t>(shape[static_cast<size_t>(dim)]);
        }
        return index;
    }

    /**
     * @brief Convert a flat row-major index into multi-dimensional coordinates
     *
     * @param linear Linear index
     * @param shape Tensor shape
     * @return std::vector<int> Per-dimension indices
     */
    inline std::vector<int> unravel_index(size_t linear, const std::vector<int>& shape) {
        std::vector<int> indices(shape.size());
        for (int dim = static_cast<int>(shape.size()) - 1; dim >= 0; --dim) {
            const auto dim_size = static_cast<size_t>(shape[static_cast<size_t>(dim)]);
            indices[static_cast<size_t>(dim)] = static_cast<int>(linear % dim_size);
            linear /= dim_size;
        }
        return indices;
    }

    /**
     * @brief Pack a row-major logical buffer into a DC_Tensor using ONNX→HWC mapping
     *
     * @param data Row-major float buffer in logical layout
     * @param logical_shape Logical ONNX shape
     * @param mem_order Destination memory order
     * @return DC_Tensor Tensor with remapped data
     * @throws std::runtime_error If data size does not match the mapped shape
     */
    inline DC_Tensor logical_to_tensor(
        const std::vector<float>& data,
        const std::vector<int>& logical_shape,
        MEM_ORDER mem_order) {
        int height = 0;
        int width = 0;
        int channels = 0;
        logical_shape_to_tensor_dims(logical_shape, height, width, channels);

        DC_Tensor output(height, width, channels, mem_order);
        if (output.m_data.size() != data.size()) {
            throw std::runtime_error("Logical shape does not match output data size");
        }

        for (size_t i = 0; i < data.size(); ++i) {
            const auto coords = unravel_index(i, logical_shape);
            int out_h = 0;
            int out_w = 0;
            int out_c = 0;
            logical_coords_to_hwc(logical_shape, coords, out_h, out_w, out_c);
            tensor_set_hwc(output, out_h, out_w, out_c, data[i]);
        }

        return output;
    }

    /**
     * @brief Unpack a DC_Tensor into a row-major logical buffer
     *
     * @param tensor Source tensor
     * @param logical_shape Logical ONNX shape of the destination buffer
     * @return std::vector<float> Row-major logical data
     * @throws std::runtime_error If element counts do not match
     */
    inline std::vector<float> tensor_to_logical(
        const DC_Tensor& tensor,
        const std::vector<int>& logical_shape) {
        const auto element_count = static_cast<size_t>(std::accumulate(
            logical_shape.begin(), logical_shape.end(), 1, std::multiplies<int>()));
        if (element_count != tensor.m_data.size()) {
            throw std::runtime_error("Logical shape does not match tensor data size");
        }

        std::vector<float> row_major(element_count);
        for (size_t i = 0; i < element_count; ++i) {
            const auto coords = unravel_index(i, logical_shape);
            int height = 0;
            int width = 0;
            int channels = 0;
            logical_coords_to_hwc(logical_shape, coords, height, width, channels);
            row_major[i] = tensor_at_hwc(tensor, height, width, channels);
        }

        return row_major;
    }

    /**
     * @brief Evaluate the GELU activation at a scalar value
     *
     * @param x Input value
     * @return float 0.5 * x * (1 + erf(x / sqrt(2)))
     */
    inline float gelu_value(float x) {
        return 0.5f * x * (1.0f + std::erf(x / std::sqrt(2.0f)));
    }

    /**
     * @brief Normalize a possibly negative axis index into [0, rank)
     *
     * @param[in,out] axis Axis index (negative values wrap from the end)
     * @param rank Tensor rank
     * @throws std::runtime_error If the normalized axis is out of bounds
     */
    inline void normalize_axis(int& axis, int rank) {
        if (axis < 0) {
            axis += rank;
        }
        if (axis < 0 || axis >= rank) {
            throw std::runtime_error("Axis is out of bounds for tensor rank");
        }
    }

    /**
     * @brief Compute the output shape of an ONNX Gather along @p axis
     *
     * A single scalar index removes the gather axis; multiple indices replace
     * that axis size with the number of indices.
     *
     * @param input_shape Logical input shape
     * @param axis Gather axis (supports negative indexing)
     * @param indices Gather indices along @p axis
     * @return std::vector<int> Logical output shape
     * @throws std::runtime_error On empty indices or out-of-bounds values
     */
    inline std::vector<int> compute_gather_output_shape(
        const std::vector<int>& input_shape,
        int axis,
        const std::vector<int>& indices) {
        if (indices.empty()) {
            throw std::runtime_error("Gather layer requires at least one index");
        }

        int normalized_axis = axis;
        normalize_axis(normalized_axis, static_cast<int>(input_shape.size()));

        const int axis_size = input_shape[static_cast<size_t>(normalized_axis)];
        for (const int gather_index : indices) {
            if (gather_index < 0 || gather_index >= axis_size) {
                throw std::runtime_error("Gather index out of bounds");
            }
        }

        auto output_shape = input_shape;
        if (indices.size() == 1) {
            // ONNX scalar-index Gather removes the gather axis from the output shape.
            output_shape.erase(output_shape.begin() + normalized_axis);
        }
        else {
            output_shape[static_cast<size_t>(normalized_axis)] = static_cast<int>(indices.size());
        }

        return output_shape;
    }

    /**
     * @brief Compute the output shape of a contiguous slice [start, end) along @p axis
     *
     * @param input_shape Logical input shape
     * @param axis Slice axis (supports negative indexing)
     * @param start Inclusive start index
     * @param end Exclusive end index (clamped to axis size)
     * @return std::vector<int> Logical output shape
     * @throws std::runtime_error On empty shape or invalid start/end
     */
    inline std::vector<int> compute_slice_output_shape(
        const std::vector<int>& input_shape,
        int axis,
        int start,
        int end) {
        if (input_shape.empty()) {
            throw std::runtime_error("Slice input shape must not be empty");
        }

        int normalized_axis = axis;
        normalize_axis(normalized_axis, static_cast<int>(input_shape.size()));

        const int axis_size = input_shape[static_cast<size_t>(normalized_axis)];
        int resolved_end = end;
        if (resolved_end < 0 || resolved_end > axis_size) {
            resolved_end = axis_size;
        }
        resolved_end = std::min(resolved_end, axis_size);

        const int resolved_start = std::max(0, start);
        if (resolved_start > resolved_end) {
            throw std::runtime_error("Slice start is greater than end");
        }

        auto output_shape = input_shape;
        output_shape[static_cast<size_t>(normalized_axis)] = resolved_end - resolved_start;
        return output_shape;
    }

    /**
     * @brief Fetch a tensor from layer_outputs using a relative index
     *
     * @param layer_outputs History of layer output tensors
     * @param relative_index Relative or absolute index
     * @return const DC_Tensor& Selected tensor
     */
    inline const DC_Tensor& tensor_at_relative(
        const std::vector<DC_Tensor>& layer_outputs,
        int relative_index) {
        return layer_outputs[resolve_relative_index(relative_index, layer_outputs.size())];
    }

    /**
     * @brief Interpret a tensor as a 2D matrix (rows × cols) for matmul helpers
     *
     * Single-channel tensors use (height, width); multi-channel use (H×W, C).
     *
     * @param tensor Source tensor
     * @return std::pair<int,int> (rows, cols)
     */
    inline std::pair<int, int> tensor_matrix_dims(const DC_Tensor& tensor) {
        if (tensor.m_channels == 1) {
            return { tensor.m_height, tensor.m_width };
        }
        return { tensor.m_height * tensor.m_width, tensor.m_channels };
    }

    /**
     * @brief Read a matrix element at (row, col) using tensor_matrix_dims layout
     *
     * @param tensor Source tensor
     * @param row Row index
     * @param col Column index
     * @return float Element value
     */
    inline float tensor_matrix_at(const DC_Tensor& tensor, int row, int col) {
        if (tensor.m_channels == 1) {
            return tensor.m_data[static_cast<size_t>(row * tensor.m_width + col)];
        }
        return tensor.m_data[static_cast<size_t>(row * tensor.m_channels + col)];
    }

    /**
     * @brief Write a matrix element at (row, col) using tensor_matrix_dims layout
     *
     * @param tensor Destination tensor
     * @param row Row index
     * @param col Column index
     * @param value Value to store
     */
    inline void tensor_matrix_set(DC_Tensor& tensor, int row, int col, float value) {
        if (tensor.m_channels == 1) {
            tensor.m_data[static_cast<size_t>(row * tensor.m_width + col)] = value;
            return;
        }
        tensor.m_data[static_cast<size_t>(row * tensor.m_channels + col)] = value;
    }

} // namespace DC_ConvNet
