#include "DC_CNNLayer_SoftmaxND.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    namespace {

        void softmax_contiguous_blocks(
            const float* input,
            float* output,
            size_t total,
            size_t axis_size,
            LayerStats& stats) {
            for (size_t offset = 0; offset < total; offset += axis_size) {
                const float* in = input + offset;
                float* out = output + offset;

                float max_val = -std::numeric_limits<float>::max();
                for (size_t i = 0; i < axis_size; ++i) {
                    max_val = std::max(max_val, in[i]);
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                }

                float sum = 0.0f;
                for (size_t i = 0; i < axis_size; ++i) {
                    const float exp_val = std::exp(in[i] - max_val);
                    out[i] = exp_val;
                    sum += exp_val;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);   // sub
                    stats.record_operation(OperationType::ARITHMETIC_OTHER, 1); // exp
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);   // sum
                }

                for (size_t i = 0; i < axis_size; ++i) {
                    out[i] /= sum;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // div as mul
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            }
        }

        // 4D [1,C,H,W] stored as HWC (H,W,C): softmax over W for each (h,c).
        void softmax_hwc_last_spatial(
            const float* input,
            float* output,
            int height,
            int width,
            int channels,
            LayerStats& stats) {
            for (int h = 0; h < height; ++h) {
                for (int c = 0; c < channels; ++c) {
                    float max_val = -std::numeric_limits<float>::max();
                    for (int w = 0; w < width; ++w) {
                        const size_t idx = static_cast<size_t>((h * width + w) * channels + c);
                        max_val = std::max(max_val, input[idx]);
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
                    }

                    float sum = 0.0f;
                    for (int w = 0; w < width; ++w) {
                        const size_t idx = static_cast<size_t>((h * width + w) * channels + c);
                        const float exp_val = std::exp(input[idx] - max_val);
                        output[idx] = exp_val;
                        sum += exp_val;
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_OTHER, 1);
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                    }

                    for (int w = 0; w < width; ++w) {
                        const size_t idx = static_cast<size_t>((h * width + w) * channels + c);
                        output[idx] /= sum;
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                    }
                }
            }
        }

    } // namespace

    DC_CNNLayer_SoftmaxND::DC_CNNLayer_SoftmaxND(int axis, std::vector<int> input_shape)
        : m_input_shape(std::move(input_shape)),
          m_axis_size(0) {
        m_layer_type = Layer_Type::SOFTMAX_ND;
        set_dump_enabled(true);

        if (m_input_shape.empty()) {
            throw std::runtime_error("SoftmaxND requires a non-empty input shape");
        }

        int normalized_axis = axis;
        normalize_axis(normalized_axis, static_cast<int>(m_input_shape.size()));
        if (normalized_axis != static_cast<int>(m_input_shape.size()) - 1) {
            throw std::runtime_error("SoftmaxND supports last-axis softmax only");
        }

        m_axis_size = m_input_shape.back();
        if (m_axis_size <= 0) {
            throw std::runtime_error("SoftmaxND axis size must be positive");
        }
    }

    DC_Tensor DC_CNNLayer_SoftmaxND::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const size_t axis_size = static_cast<size_t>(m_axis_size);
        if (input.m_data.size() % axis_size != 0) {
            throw std::runtime_error("SoftmaxND input size is not divisible by axis size");
        }

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);
        output.set_logical_shape(m_input_shape);

        if (input.m_mem_order == MEM_ORDER::HWC
            && m_input_shape.size() == 4
            && m_input_shape[0] == 1) {
            // HWC (H,W,C) with H=shape[2], W=shape[3], C=shape[1].
            const int height = m_input_shape[2];
            const int width = m_input_shape[3];
            const int channels = m_input_shape[1];
            if (height != input.m_height || width != input.m_width || channels != input.m_channels) {
                throw std::runtime_error("SoftmaxND HWC tensor dims do not match logical shape");
            }
            softmax_hwc_last_spatial(
                input.m_data.data(),
                output.m_data.data(),
                height,
                width,
                channels,
                stats);
        }
        else {
            softmax_contiguous_blocks(
                input.m_data.data(),
                output.m_data.data(),
                input.m_data.size(),
                axis_size,
                stats);
        }

        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_softmax_nd(input.m_data.size(), stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
