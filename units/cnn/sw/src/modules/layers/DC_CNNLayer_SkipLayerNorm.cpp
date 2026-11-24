#include "DC_CNNLayer_SkipLayerNorm.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_SkipLayerNorm::DC_CNNLayer_SkipLayerNorm(
        int relative_skip_index,
        int relative_input_index)
        : m_relative_skip_index(relative_skip_index),
          m_relative_input_index(relative_input_index) {
        m_layer_type = Layer_Type::SKIP_LAYERNORM;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_SkipLayerNorm::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const DC_Tensor& skip = tensor_at_relative(layer_outputs, m_relative_skip_index);
        const DC_Tensor& input = tensor_at_relative(layer_outputs, m_relative_input_index);

        if (skip.m_height != input.m_height ||
            skip.m_width != input.m_width ||
            skip.m_channels != input.m_channels) {
            throw std::runtime_error("SkipLayerNorm inputs must have the same dimensions");
        }

        DC_Tensor output(skip.m_height, skip.m_width, skip.m_channels, skip.m_mem_order);
        for (size_t i = 0; i < skip.m_data.size(); ++i) {
            output.m_data[i] = skip.m_data[i] + input.m_data[i];
            stats.record_operation(OperationType::MEMORY_LOAD, 2);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
            stats.record_operation(OperationType::MEMORY_STORE, 1);
        }

        stats.record_layer_configuration(
            skip, skip.m_height, skip.m_width, skip.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_skip_layernorm(skip.m_data.size(), stats);

        try {
            dump_output_if_enabled(output, output.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
