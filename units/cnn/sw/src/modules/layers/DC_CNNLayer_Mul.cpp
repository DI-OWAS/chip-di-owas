#include "DC_CNNLayer_Mul.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Mul::DC_CNNLayer_Mul(float scalar_factor)
        : m_scalar_factor(scalar_factor) {
        m_layer_type = Layer_Type::MUL;
        set_dump_enabled(true);
    }

    DC_CNNLayer_Mul::DC_CNNLayer_Mul(int relative_lhs_index)
        : m_use_loaded_operand(true),
          m_relative_lhs_index(relative_lhs_index) {
        m_layer_type = Layer_Type::MUL;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Mul::forward(const DC_Tensor& input) const {
        if (m_use_loaded_operand) {
            throw std::logic_error("Use forward(layer_outputs) for operand multiply.");
        }

        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);
        for (size_t i = 0; i < input.m_data.size(); ++i) {
            output.m_data[i] = input.m_data[i] * m_scalar_factor;
            stats.record_operation(OperationType::MEMORY_LOAD, 1);
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
            stats.record_operation(OperationType::MEMORY_STORE, 1);
        }

        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_mul(input.m_data.size(), false, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

    DC_Tensor DC_CNNLayer_Mul::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        if (!m_use_loaded_operand) {
            throw std::logic_error("Use forward(input) for scalar multiply.");
        }

        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const DC_Tensor& lhs = tensor_at_relative(layer_outputs, m_relative_lhs_index);
        DC_Tensor output(lhs.m_height, lhs.m_width, lhs.m_channels, lhs.m_mem_order);
        output.m_data = lhs.m_data;

        const size_t elements = lhs.m_data.size();
        stats.record_operation(OperationType::MEMORY_LOAD, elements);
        stats.record_operation(OperationType::MEMORY_STORE, elements);

        if (m_operand.empty()) {
            throw std::runtime_error("Mul layer operand is not loaded");
        }

        if (m_operand.size() != static_cast<size_t>(lhs.m_channels)) {
            throw std::runtime_error("Mul operand size does not match output tensor");
        }

        for (int y = 0; y < lhs.m_height; ++y) {
            for (int x = 0; x < lhs.m_width; ++x) {
                for (int c = 0; c < lhs.m_channels; ++c) {
                    const size_t idx = static_cast<size_t>((y * lhs.m_width + x) * lhs.m_channels + c);
                    output.m_data[idx] *= m_operand[static_cast<size_t>(c)];
                    stats.record_operation(OperationType::MEMORY_LOAD, 2); // dst + operand
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            }
        }

        stats.record_layer_configuration(
            lhs, lhs.m_height, lhs.m_width, lhs.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_mul(elements, true, stats);

        try {
            dump_output_if_enabled(output, lhs.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
