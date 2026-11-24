#include "DC_CNNLayer_L2Norm.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>
#include <cmath>

namespace DC_ConvNet {

    DC_CNNLayer_L2Norm::DC_CNNLayer_L2Norm() {
        m_layer_type = Layer_Type::L2NORM;
    }

    DC_Tensor DC_CNNLayer_L2Norm::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto num_channels = input.m_channels;
        const auto input_height = input.m_height;
        const auto input_width = input.m_width;
        const int spatial_size = input_height * input_width;

        DC_Tensor output(input_height, input_width, num_channels, input.m_mem_order);

        for (int i = 0; i < spatial_size; ++i) {
            float sum_sq = 0.0f;

            // First pass: Calculate sum of squares
            if (input.m_mem_order == MEM_ORDER::HWC) {
                for (int c = 0; c < num_channels; ++c) {
                    float val = input.m_data[i * num_channels + c];
                    sum_sq += val * val;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                }
            } else {
                for (int c = 0; c < num_channels; ++c) {
                    float val = input.m_data[c * spatial_size + i];
                    sum_sq += val * val;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                    stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                }
            }

            // Calculate L2 Norm with epsilon to prevent division by zero
            float norm = std::sqrt(std::max(sum_sq, 1e-6f));
            stats.record_operation(OperationType::ARITHMETIC_OTHER, 1); // sqrt

            // Second pass: Normalize
            if (input.m_mem_order == MEM_ORDER::HWC) {
                for (int c = 0; c < num_channels; ++c) {
                    output.m_data[i * num_channels + c] = input.m_data[i * num_channels + c] / norm;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // div as mul
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            } else {
                for (int c = 0; c < num_channels; ++c) {
                    output.m_data[c * spatial_size + i] = input.m_data[c * spatial_size + i] / norm;
                    stats.record_operation(OperationType::MEMORY_LOAD, 1);
                    stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // div as mul
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            }
        }

        populate_stats_l2norm(input, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }

        return output;
    }

} // namespace DC_ConvNet
