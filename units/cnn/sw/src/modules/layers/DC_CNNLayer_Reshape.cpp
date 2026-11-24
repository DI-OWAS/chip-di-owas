#include "DC_CNNLayer_Reshape.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    namespace {

        // ONNX-style logical shapes used by the transformer path ([1,...] batch).
        // Spatial HWC trackers like [14,14,384] after Conv must stay byte-identity views.
        bool is_onnx_style_logical_shape(const std::vector<int>& shape) {
            return !shape.empty() && shape[0] == 1
                && (shape.size() == 3 || shape.size() == 4 || shape.size() == 5);
        }

    } // namespace

    DC_CNNLayer_Reshape::DC_CNNLayer_Reshape(
        std::vector<int> input_shape,
        std::vector<int> target_shape)
        : m_input_shape(std::move(input_shape)),
          m_target_shape(std::move(target_shape)) {
        m_layer_type = Layer_Type::RESHAPE;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_Reshape::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto resolved_shape = resolve_shape_with_negative_dim(
            m_target_shape,
            tensor_element_count(input));

        const bool hwc_round_trip = input.m_mem_order == MEM_ORDER::HWC
            && is_onnx_style_logical_shape(m_input_shape)
            && is_onnx_style_logical_shape(resolved_shape);

        DC_Tensor output = hwc_round_trip
            ? [&]() {
                const auto logical = tensor_to_logical(input, m_input_shape);
                auto tensor = logical_to_tensor(logical, resolved_shape, input.m_mem_order);
                tensor.set_logical_shape(resolved_shape);
                return tensor;
            }()
            : [&]() {
                int height = 0;
                int width = 0;
                int channel = 0;
                logical_shape_to_tensor_dims(resolved_shape, height, width, channel);
                DC_Tensor tensor(height, width, channel, input.m_mem_order);
                tensor.m_data = input.m_data;
                tensor.set_logical_shape(resolved_shape);
                return tensor;
            }();

        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);

        const size_t elements = input.m_data.size();
        const size_t passes = hwc_round_trip ? 2 : 1;
        stats.record_operation(OperationType::MEMORY_LOAD, elements * passes);
        stats.record_operation(OperationType::MEMORY_STORE, elements * passes);
        populate_stats_reshape(elements, hwc_round_trip, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
