#include "DC_CNNLayer_Add.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Add::DC_CNNLayer_Add(std::vector<int> relative_layer_indices)
        : m_relative_layer_indices(std::move(relative_layer_indices)) {
        m_layer_type = Layer_Type::ADD;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Add::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const DC_Tensor& base = tensor_at_relative(layer_outputs, m_relative_layer_indices.front());
        DC_Tensor output(base.m_height, base.m_width, base.m_channels, base.m_mem_order);
        output.m_data = base.m_data;

        const size_t elements = output.m_data.size();
        stats.record_operation(OperationType::MEMORY_LOAD, elements);
        stats.record_operation(OperationType::MEMORY_STORE, elements);

        int num_tensor_addends = 0;
        for (size_t i = 1; i < m_relative_layer_indices.size(); ++i) {
            const DC_Tensor& addend = tensor_at_relative(layer_outputs, m_relative_layer_indices[i]);
            if (addend.m_height != output.m_height ||
                addend.m_width != output.m_width ||
                addend.m_channels != output.m_channels) {
                throw std::runtime_error("Add layer inputs must have the same dimensions");
            }
            for (size_t j = 0; j < output.m_data.size(); ++j) {
                output.m_data[j] += addend.m_data[j];
                stats.record_operation(OperationType::MEMORY_LOAD, 2);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                stats.record_operation(OperationType::MEMORY_STORE, 1);
            }
            ++num_tensor_addends;
        }

        const bool has_operand = !m_operand.empty();
        if (has_operand) {
            if (m_operand.size() != output.m_data.size()) {
                throw std::runtime_error("Add operand size does not match output tensor");
            }
            for (size_t i = 0; i < output.m_data.size(); ++i) {
                output.m_data[i] += m_operand[i];
                stats.record_operation(OperationType::MEMORY_LOAD, 2);
                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                stats.record_operation(OperationType::MEMORY_STORE, 1);
            }
        }

        stats.record_layer_configuration(
            base, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_add(elements, num_tensor_addends, has_operand, stats);

        try {
            dump_output_if_enabled(output, base.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
