#include "DC_CNNLayer_Softmax.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <cmath>

namespace DC_ConvNet {

    /**
     * @brief Performs forward propagation through the softmax layer
     */
    DC_Tensor DC_CNNLayer_Softmax::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);

        // Find max value for numerical stability
        auto max_val = -std::numeric_limits<float>::max();
        for (size_t i = 0; i < input.m_data.size(); ++i) {
            if (input.m_data[i] > max_val) {
                max_val = input.m_data[i];
            }

            stats.record_operation(OperationType::MEMORY_LOAD, 1); // Load from input
            stats.record_operation(OperationType::ARITHMETIC_COMP, 1); // Comparison for max
        }

        // Compute exp(x - max) for each element
        std::vector<float> exp_values(input.m_data.size());
        auto sum = 0.0f;

        for (size_t i = 0; i < input.m_data.size(); ++i) {
            const auto exp_val = std::exp(input.m_data[i] - max_val);
            exp_values[i] = exp_val;
            sum += exp_val;

            stats.record_operation(OperationType::MEMORY_LOAD, 1); // Load from input
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1); // Subtraction (input - max)
            stats.record_operation(OperationType::ARITHMETIC_OTHER, 1); // Exponential operation
            stats.record_operation(OperationType::MEMORY_STORE, 1); // Store to exp_values
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1); // Addition to sum
        }

        // Normalize by sum of exponentials
        for (size_t i = 0; i < input.m_data.size(); ++i) {
            output.m_data[i] = exp_values[i] / sum;

            stats.record_operation(OperationType::MEMORY_LOAD, 1); // Load from exp_values
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // Division by sum
            stats.record_operation(OperationType::MEMORY_STORE, 1); // Store to output
        }

        //Update statistics
        populate_stats_softmax(input, stats);

        return output;
    }
} // namespace DC_ConvNet 
