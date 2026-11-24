#include "DC_CNNLayer_Shortcut.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNN_axillary.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_Shortcut::DC_CNNLayer_Shortcut(int from_layer_index, ActivationType activation)
        : m_from_layer_index(from_layer_index), m_activation(activation) {
        m_layer_type = Layer_Type::SHORTCUT;
    }

    DC_Tensor DC_CNNLayer_Shortcut::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        if (layer_outputs.empty()) {
            throw std::runtime_error("Shortcut layer requires at least one previous layer output");
        }

        const DC_Tensor& input1 = layer_outputs.back();
        
        if (m_from_layer_index < 0 || m_from_layer_index >= static_cast<int>(layer_outputs.size())) {
            throw std::runtime_error("Shortcut layer 'from' index out of bounds: " + std::to_string(m_from_layer_index));
        }
        
        const DC_Tensor& input2 = layer_outputs[m_from_layer_index];

        if (input1.m_height != input2.m_height || 
            input1.m_width != input2.m_width || 
            input1.m_channels != input2.m_channels) {
            throw std::runtime_error("Shortcut layer inputs must have the same dimensions. "
                "Input1: " + std::to_string(input1.m_height) + "x" + std::to_string(input1.m_width) + "x" + std::to_string(input1.m_channels) + 
                ", Input2: " + std::to_string(input2.m_height) + "x" + std::to_string(input2.m_width) + "x" + std::to_string(input2.m_channels) +
                " (input2 is from layer index " + std::to_string(m_from_layer_index) + ")");
        }

        // Create output tensor with the same dimensions as the inputs
        DC_Tensor output(input1.m_height, input1.m_width, input1.m_channels, input1.m_mem_order);

        // Perform element-wise addition
        for (size_t i = 0; i < input1.m_data.size(); ++i) {
            float val = input1.m_data[i] + input2.m_data[i];
            stats.record_operation(OperationType::MEMORY_LOAD, 2);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);

            val = activate_value(m_activation, val, 0.1f, stats);

            output.m_data[i] = val;
            stats.record_operation(OperationType::MEMORY_STORE, 1);
        }

        // Update statistics
        populate_stats_shortcut(input1, stats);
        try {
            dump_output_if_enabled(output, input1.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        
        return output;
    }

} // namespace DC_ConvNet
