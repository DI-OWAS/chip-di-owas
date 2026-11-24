#include "DC_CNNLayer_LayerNorm.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_LayerNorm::DC_CNNLayer_LayerNorm(int relative_input_index, int normalized_size, float epsilon)
        : m_relative_input_index(relative_input_index),
          m_normalized_size(normalized_size),
          m_epsilon(epsilon) {
        m_layer_type = Layer_Type::LAYERNORM;
        m_gamma.assign(static_cast<size_t>(normalized_size), 1.0f);
        m_beta.assign(static_cast<size_t>(normalized_size), 0.0f);
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_LayerNorm::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        const DC_Tensor& input = tensor_at_relative(layer_outputs, m_relative_input_index);
        return forward(input);
    }

    DC_Tensor DC_CNNLayer_LayerNorm::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        if (!weights_loaded()) {
            throw std::runtime_error("LayerNorm gamma/beta are not loaded");
        }

        const int feature_axis_size = m_normalized_size;
        const int outer_size = tensor_element_count(input) / feature_axis_size;
        if (outer_size * feature_axis_size != tensor_element_count(input)) {
            throw std::runtime_error("LayerNorm normalized size does not divide input tensor");
        }

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);
        for (int outer = 0; outer < outer_size; ++outer) {
            const auto base = static_cast<size_t>(outer * feature_axis_size);

            float mean = 0.0f;
            for (int i = 0; i < feature_axis_size; ++i) {
                mean += input.m_data[base + static_cast<size_t>(i)];
                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
            }
            mean /= static_cast<float>(feature_axis_size);
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // division as mul

            float variance = 0.0f;
            for (int i = 0; i < feature_axis_size; ++i) {
                const float diff = input.m_data[base + static_cast<size_t>(i)] - mean;
                variance += diff * diff;
                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 2); // sub + accumulate
                stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // diff * diff
            }
            variance /= static_cast<float>(feature_axis_size);
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // division as mul
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1); // + epsilon
            const float inv_std = 1.0f / std::sqrt(variance + m_epsilon);
            stats.record_operation(OperationType::ARITHMETIC_OTHER, 1); // sqrt
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1);   // reciprocal as mul

            for (int i = 0; i < feature_axis_size; ++i) {
                const auto idx = base + static_cast<size_t>(i);
                const float normalized = (input.m_data[idx] - mean) * inv_std;
                output.m_data[idx] = normalized * m_gamma[static_cast<size_t>(i)] + m_beta[static_cast<size_t>(i)];
                stats.record_operation(OperationType::MEMORY_LOAD, 3); // input + gamma + beta
                stats.record_operation(OperationType::ARITHMETIC_ADD, 2); // sub mean + add beta
                stats.record_operation(OperationType::ARITHMETIC_MUL, 2); // * inv_std + * gamma
                stats.record_operation(OperationType::MEMORY_STORE, 1);
            }
        }

        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_layernorm(input.m_data.size(), feature_axis_size, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
