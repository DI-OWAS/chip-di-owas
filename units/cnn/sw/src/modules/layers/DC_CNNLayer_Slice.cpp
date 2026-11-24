#include "DC_CNNLayer_Slice.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Slice::DC_CNNLayer_Slice(
        std::vector<int> input_shape,
        int axis,
        int start,
        int end)
        : m_input_shape(std::move(input_shape)),
          m_axis(axis),
          m_start(start) {
        m_layer_type = Layer_Type::SLICE;
        set_dump_enabled(true);

        if (m_input_shape.empty()) {
            throw std::runtime_error("Slice input shape must not be empty");
        }

        normalize_axis(m_axis, static_cast<int>(m_input_shape.size()));

        const int axis_size = m_input_shape[static_cast<size_t>(m_axis)];
        m_start = std::max(0, m_start);

        int resolved_end = end;
        if (resolved_end < 0 || resolved_end > axis_size) {
            resolved_end = axis_size;
        }
        resolved_end = std::min(resolved_end, axis_size);

        if (m_start > resolved_end) {
            throw std::runtime_error("Slice start is greater than end");
        }

        m_output_shape = m_input_shape;
        m_output_shape[static_cast<size_t>(m_axis)] = resolved_end - m_start;
    }

    DC_Tensor DC_CNNLayer_Slice::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        int out_h = 1;
        int out_w = 1;
        int out_c = 1;
        logical_shape_to_tensor_dims(m_output_shape, out_h, out_w, out_c);

        DC_Tensor output(out_h, out_w, out_c, input.m_mem_order);
        output.set_logical_shape(m_output_shape);

        int outer = 1;
        for (int i = 0; i < m_axis; ++i) {
            outer *= m_input_shape[static_cast<size_t>(i)];
        }

        const int axis_size = m_input_shape[static_cast<size_t>(m_axis)];
        const int slice_len = m_output_shape[static_cast<size_t>(m_axis)];

        int inner = 1;
        for (size_t i = static_cast<size_t>(m_axis) + 1; i < m_input_shape.size(); ++i) {
            inner *= m_input_shape[i];
        }

        const size_t block = static_cast<size_t>(slice_len) * static_cast<size_t>(inner);
        for (int o = 0; o < outer; ++o) {
            const size_t src_offset =
                (static_cast<size_t>(o) * static_cast<size_t>(axis_size) + static_cast<size_t>(m_start))
                * static_cast<size_t>(inner);
            const size_t dst_offset = static_cast<size_t>(o) * block;
            std::copy_n(
                input.m_data.begin() + static_cast<std::ptrdiff_t>(src_offset),
                block,
                output.m_data.begin() + static_cast<std::ptrdiff_t>(dst_offset));
            stats.record_operation(OperationType::MEMORY_LOAD, block);
            stats.record_operation(OperationType::MEMORY_STORE, block);
        }

        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);
        populate_stats_slice(output.m_data.size(), stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
