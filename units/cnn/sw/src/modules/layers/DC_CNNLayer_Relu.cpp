#include "DC_CNNLayer_Relu.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_Tensor DC_CNNLayer_Relu::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);
        for (size_t i = 0; i < input.m_data.size(); ++i) {
            output.m_data[i] = std::max(0.0f, input.m_data[i]);
            stats.record_operation(OperationType::MEMORY_LOAD, 1);
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1);
            stats.record_operation(OperationType::MEMORY_STORE, 1);
        }

        stats.record_layer_configuration(
            input, input.m_height, input.m_width, input.m_channels,
            false, 0, 0, 0, false, ActivationType::RELU);
        populate_stats_relu(input.m_data.size(), stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
