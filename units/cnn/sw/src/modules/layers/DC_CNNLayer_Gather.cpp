#include "DC_CNNLayer_Gather.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Gather::DC_CNNLayer_Gather(int axis, std::vector<int> input_shape, std::vector<int> indices, std::vector<int> relative_indices)
        : m_axis(axis), m_input_shape(std::move(input_shape)), m_indices(std::move(indices)), m_relative_indices(std::move(relative_indices)){
        m_layer_type = Layer_Type::GATHER;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Gather::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto output_shape = compute_gather_output_shape(m_input_shape, m_axis, m_indices);

        const auto output_size = static_cast<size_t>(std::accumulate(
            output_shape.begin(), output_shape.end(), 1, std::multiplies<int>()));
        std::vector<float> output_data(output_size);

        int axis = m_axis;
        normalize_axis(axis, static_cast<int>(m_input_shape.size()));

        const DC_Tensor& input = tensor_at_relative(layer_outputs, m_relative_indices[0]);

        for (size_t out_linear = 0; out_linear < output_size; ++out_linear) {
            const auto output_coords = unravel_index(out_linear, output_shape);

            if (m_indices.size() == 1) {
                auto input_coords = output_coords;
                input_coords.insert(input_coords.begin() + axis, m_indices.front());
                output_data[out_linear] = input.m_data[linear_index(input_coords, m_input_shape)];
                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                stats.record_operation(OperationType::MEMORY_STORE, 1);
                continue;
            }

            const int gather_output_index = output_coords[static_cast<size_t>(axis)];
            if (gather_output_index < 0 || gather_output_index >= static_cast<int>(m_indices.size())) {
                throw std::runtime_error("Gather output axis index out of bounds");
            }

            const int gather_index = m_indices[static_cast<size_t>(gather_output_index)];
            auto input_coords = output_coords;
            input_coords[static_cast<size_t>(axis)] = gather_index;
            output_data[out_linear] = input.m_data[linear_index(input_coords, m_input_shape)];
            stats.record_operation(OperationType::MEMORY_LOAD, 1);
            stats.record_operation(OperationType::MEMORY_STORE, 1);
        }

        auto output = logical_to_tensor(output_data, output_shape, input.m_mem_order);
        // Materialize logical gather buffer into the activation tensor layout.
        stats.record_operation(OperationType::MEMORY_LOAD, output_size);
        stats.record_operation(OperationType::MEMORY_STORE, output_size);
        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_gather(output_size, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
