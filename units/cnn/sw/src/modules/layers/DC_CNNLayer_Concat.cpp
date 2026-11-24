#include "DC_CNNLayer_Concat.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Concat::DC_CNNLayer_Concat(
        std::vector<int> relative_layer_indices,
        int axis,
        std::vector<int> output_shape)
        : m_relative_layer_indices(std::move(relative_layer_indices)),
          m_axis(axis),
          m_output_shape(std::move(output_shape)) {
        m_layer_type = Layer_Type::CONCAT;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Concat::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const DC_Tensor& tensor = tensor_at_relative(layer_outputs, m_relative_layer_indices[0]);

        DC_Tensor output(
            tensor.m_height,
            tensor.m_width + m_constant_shape[1],
            tensor.m_channels,
            tensor.m_mem_order);

        std::copy(m_constant_operand.begin(), m_constant_operand.end(), output.m_data.begin());
        std::copy(tensor.m_data.begin(), tensor.m_data.end(), output.m_data.begin() + m_constant_operand.size());

        stats.record_layer_configuration(
            tensor, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);

        const size_t output_elements = output.m_data.size();
        stats.record_operation(OperationType::MEMORY_LOAD, output_elements);
        stats.record_operation(OperationType::MEMORY_STORE, output_elements);
        populate_stats_concat(output_elements, stats);

        try {
            dump_output_if_enabled(output, output.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
