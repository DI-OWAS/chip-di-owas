#include "DC_CNNLayer_Resize.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    namespace {

        float sample_bilinear(
            const DC_Tensor& input,
            float y,
            float x,
            int channel,
            LayerStats& stats) {
            const int in_h = input.m_height;
            const int in_w = input.m_width;

            const float y_clamped = std::clamp(y, 0.0f, static_cast<float>(in_h - 1));
            const float x_clamped = std::clamp(x, 0.0f, static_cast<float>(in_w - 1));

            const int y0 = static_cast<int>(std::floor(y_clamped));
            const int x0 = static_cast<int>(std::floor(x_clamped));
            const int y1 = std::min(y0 + 1, in_h - 1);
            const int x1 = std::min(x0 + 1, in_w - 1);

            const float wy = y_clamped - static_cast<float>(y0);
            const float wx = x_clamped - static_cast<float>(x0);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 2); // wy, wx

            auto read = [&](int row, int col) -> float {
                if (input.m_mem_order == MEM_ORDER::HWC) {
                    return input.m_data[static_cast<size_t>((row * in_w + col) * input.m_channels + channel)];
                }
                return input.m_data[static_cast<size_t>(channel * in_h * in_w + row * in_w + col)];
            };

            const float v00 = read(y0, x0);
            const float v01 = read(y0, x1);
            const float v10 = read(y1, x0);
            const float v11 = read(y1, x1);
            stats.record_operation(OperationType::MEMORY_LOAD, 4);

            const float top = v00 * (1.0f - wx) + v01 * wx;
            const float bottom = v10 * (1.0f - wx) + v11 * wx;
            // (1-wx): add; 2 muls + 1 add per row lerp
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1 + 2); // (1-wx) once reused + 2 blends
            stats.record_operation(OperationType::ARITHMETIC_MUL, 4);

            const float result = top * (1.0f - wy) + bottom * wy;
            stats.record_operation(OperationType::ARITHMETIC_ADD, 2); // (1-wy) + blend
            stats.record_operation(OperationType::ARITHMETIC_MUL, 2);

            return result;
        }

        float map_output_coordinate(
            int out_index,
            int in_size,
            int out_size,
            const std::string& coordinate_transformation_mode) {
            if (coordinate_transformation_mode == "align_corners") {
                if (in_size > 1 && out_size > 1) {
                    return static_cast<float>(out_index) * static_cast<float>(in_size - 1) /
                           static_cast<float>(out_size - 1);
                }
                return static_cast<float>(out_index) * static_cast<float>(in_size) /
                       static_cast<float>(out_size);
            }

            // ONNX half_pixel / pytorch_half_pixel style mapping.
            return (static_cast<float>(out_index) + 0.5f) * static_cast<float>(in_size) /
                   static_cast<float>(out_size) - 0.5f;
        }

    } // namespace

    DC_CNNLayer_Resize::DC_CNNLayer_Resize(
        std::vector<int> output_shape,
        std::string coordinate_transformation_mode)
        : m_output_shape(std::move(output_shape)),
          m_coordinate_transformation_mode(std::move(coordinate_transformation_mode)) {
        m_layer_type = Layer_Type::RESIZE;
    }

    DC_Tensor DC_CNNLayer_Resize::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        int out_height = 0;
        int out_width = 0;
        int out_channels = 0;

        if (m_output_shape.size() == 4) {
            out_channels = m_output_shape[1];
            out_height = m_output_shape[2];
            out_width = m_output_shape[3];
        } else {
            shape_to_hwc(m_output_shape, out_height, out_width, out_channels);
            if (out_channels <= 0) {
                out_channels = input.m_channels;
            }
        }

        if (out_channels != input.m_channels) {
            throw std::runtime_error("Resize output channels must match input channels");
        }

        DC_Tensor output(out_height, out_width, out_channels, input.m_mem_order);

        for (int out_y = 0; out_y < out_height; ++out_y) {
            const float in_y = map_output_coordinate(
                out_y, input.m_height, out_height, m_coordinate_transformation_mode);
            for (int out_x = 0; out_x < out_width; ++out_x) {
                const float in_x = map_output_coordinate(
                    out_x, input.m_width, out_width, m_coordinate_transformation_mode);
                for (int c = 0; c < out_channels; ++c) {
                    const float value = sample_bilinear(input, in_y, in_x, c, stats);
                    if (input.m_mem_order == MEM_ORDER::HWC) {
                        output.m_data[static_cast<size_t>((out_y * out_width + out_x) * out_channels + c)] = value;
                    } else {
                        output.m_data[static_cast<size_t>(c * out_height * out_width + out_y * out_width + out_x)] = value;
                    }
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            }
        }

        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);

        const size_t output_elements = output.m_data.size();
        populate_stats_resize(output_elements, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
