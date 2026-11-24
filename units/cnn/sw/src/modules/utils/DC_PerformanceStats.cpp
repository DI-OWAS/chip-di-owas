#include "DC_PerformanceStats.h"

#include <sstream>
#include <iomanip>
#include <algorithm>

namespace DC_ConvNet {

    // Singleton instance getter
    DC_PerformanceStats& DC_PerformanceStats::getInstance() {
        static DC_PerformanceStats instance;
        return instance;
    }

    LayerStats& DC_PerformanceStats::AllocateLayerStats(const std::string& layer_name, Layer_Type layer_type) {
        return m_layer_stats.emplace_back(layer_name, LayerStats(layer_name, layerTypeToString(layer_type))).second;
    }

    void DC_PerformanceStats::addLayerStats(const std::string& layer_name, LayerStats&& layer_stats) {
        m_layer_stats.push_back({ layer_name, std::move(layer_stats) });
    }

    // Reset all performance statistics
    void DC_PerformanceStats::resetAllStats() {
        m_layer_stats.clear();
    }

    // Get statistics for a specific layer
    const LayerStats* DC_PerformanceStats::getLayerStats(const std::string& layer_name) const {

        auto it = std::find_if(m_layer_stats.cbegin(), m_layer_stats.cend(), [layer_name](const std::pair<std::string, LayerStats>& val) { return val.first == layer_name; });
        /*  auto it = m_layer_stats.find(layer_name);*/
        if (it != m_layer_stats.end()) {
            return &it->second;
        }
        return nullptr;
    }

    // Get statistics for all layers
    std::vector<const LayerStats*> DC_PerformanceStats::getAllLayerStats() const {

        std::vector<const LayerStats*> result;
        result.reserve(m_layer_stats.size());

        for (const auto& pair : m_layer_stats) {
            result.push_back(&pair.second);
        }

        return result;
    }

    // Get total statistics across all layers
    std::unordered_map<OperationType, uint64_t> DC_PerformanceStats::getTotalStats() const {

        std::unordered_map<OperationType, uint64_t> totals;

        // Initialize totals
        totals[OperationType::MEMORY_LOAD] = 0;
        totals[OperationType::MEMORY_STORE] = 0;
        totals[OperationType::ARITHMETIC_ADD] = 0;
        totals[OperationType::ARITHMETIC_MUL] = 0;
        totals[OperationType::ARITHMETIC_COMP] = 0;
        totals[OperationType::ARITHMETIC_OTHER] = 0;

        // Sum up all layer statistics
        for (const auto& pair : m_layer_stats) {
            const LayerStats* stats = &pair.second;
            for (auto i = 0u; i < stats->operation_counts.size(); ++i) {
                totals[static_cast<OperationType>(i)] += stats->operation_counts[i];
            }
        }

        return totals;
    }

    // Generate a summary report of all statistics
    std::string DC_PerformanceStats::generateReport(bool include_layers) const {
        std::stringstream ss;

        // Get total statistics
        auto totals = getTotalStats();

        // Calculate grand total of all operations
        uint64_t grand_total = 0;
        for (const auto& pair : totals) {
            grand_total += pair.second;
        }

        // Get all layer statistics sorted by name
        std::vector<const LayerStats*> layer_stats = getAllLayerStats();

        // Report header
        ss << "===== CNN Performance Statistics Report =====\n\n";

        // Summary section
        ss << "Summary Statistics:\n";
        ss << "----------------------------\n";
        ss << "Total Layers: " << m_layer_stats.size() << "\n";
        ss << "Total Operations: " << grand_total << "\n\n";

        // Operation totals
        ss << "Operation Totals:\n";
        ss << "----------------------------\n";
        for (int i = 0; i < 6; ++i) {
            OperationType op_type = static_cast<OperationType>(i);
            ss << std::setw(20) << std::left << operationTypeToString(op_type)
                << ": " << std::setw(12) << std::right << totals[op_type];

            // Add percentage
            if (grand_total > 0) {
                float percentage = (static_cast<float>(totals[op_type]) / grand_total) * 100.0f;
                ss << " (" << std::fixed << std::setprecision(2) << percentage << "%)";
            }
            ss << "\n";
        }
        ss << "\n";

        // Add memory and arithmetic totals
        uint64_t total_memory = totals[OperationType::MEMORY_LOAD] + totals[OperationType::MEMORY_STORE];
        uint64_t total_arithmetic = totals[OperationType::ARITHMETIC_ADD] +
            totals[OperationType::ARITHMETIC_MUL] +
            totals[OperationType::ARITHMETIC_COMP] +
            totals[OperationType::ARITHMETIC_OTHER];

        ss << "Total Memory Operations: " << total_memory;
        if (grand_total > 0) {
            float percentage = (static_cast<float>(total_memory) / grand_total) * 100.0f;
            ss << " (" << std::fixed << std::setprecision(2) << percentage << "%)";
        }
        ss << "\n";

        ss << "Total Arithmetic Operations: " << total_arithmetic;
        if (grand_total > 0) {
            float percentage = (static_cast<float>(total_arithmetic) / grand_total) * 100.0f;
            ss << " (" << std::fixed << std::setprecision(2) << percentage << "%)";
        }
        ss << "\n\n";

        // Per-layer details
        if (include_layers && !layer_stats.empty()) {
            ss << "Per-Layer Statistics:\n";
            ss << "----------------------------\n";

            // Table header
            ss << std::setw(25) << std::left << "Layer Name"
                << std::setw(15) << std::left << "Layer Type"
                << std::setw(20) << std::right << "Mem Load(Calc)"
                << std::setw(30) << std::right << "Mem Store(Calc)"
                << std::setw(25) << std::right << "Arith Add(Calc)"
                << std::setw(30) << std::right << "Arith Mul(Calc)"
                << std::setw(15) << std::right << "Arith Comp"
                << std::setw(15) << std::right << "Arith Other"
                << std::setw(15) << std::right << "Total"
                << "\n";

            // Add a separator line
            ss << std::string(190, '-') << "\n";

            // Table rows
            for (const LayerStats* stats : layer_stats) {
                const auto& counts = stats->operation_counts;

                uint64_t layer_total = 0;
                for (const auto& count : counts) {
                    layer_total += count;
                }

                ss << std::setw(25) << std::left << stats->layer_name
                    << std::setw(15) << std::left << stats->layer_type;

                // Memory load with theoretical calculation
                ss << std::setw(10) << std::right << counts[static_cast<uint64_t>(OperationType::MEMORY_LOAD)]
                    << " (" << std::setw(10) << std::right << stats->theoretical_operation_counts[static_cast<uint64_t>(OperationType::MEMORY_LOAD)] << ")";

                // Memory store with theoretical calculation
                ss << std::setw(15) << std::right << counts[static_cast<uint64_t>(OperationType::MEMORY_STORE)]
                    << " (" << std::setw(10) << std::right << stats->theoretical_operation_counts[static_cast<uint64_t>(OperationType::MEMORY_STORE)] << ")";

                // Arithmetic operations
                ss << std::setw(15) << std::right << counts[static_cast<uint64_t>(OperationType::ARITHMETIC_ADD)]
                    << " (" << std::setw(10) << std::right << stats->theoretical_operation_counts[static_cast<uint64_t>(OperationType::ARITHMETIC_ADD)] << ")";

                ss << std::setw(15) << std::right << counts[static_cast<uint64_t>(OperationType::ARITHMETIC_MUL)]
                    << " (" << std::setw(10) << std::right << stats->theoretical_operation_counts[static_cast<uint64_t>(OperationType::ARITHMETIC_MUL)] << ")";

                ss << std::setw(15) << std::right << counts[static_cast<uint64_t>(OperationType::ARITHMETIC_COMP)]
                    << std::setw(15) << std::right << counts[static_cast<uint64_t>(OperationType::ARITHMETIC_OTHER)]
                    << std::setw(15) << std::right << layer_total
                    << "\n";
            }

            // Add detailed layer configurations
            ss << "\nLayer Configurations:\n";
            ss << "----------------------------\n";

            // Table header for layer configurations
            ss << std::setw(25) << std::left << "Layer Name"
                << std::setw(15) << std::left << "Layer Type"
                << std::setw(25) << std::left << "Input Shape"
                << std::setw(25) << std::left << "Output Shape"
                << std::setw(15) << std::left << "Kernel"
                << std::setw(10) << std::left << "Stride"
                << std::setw(10) << std::left << "Padding"
                << std::setw(10) << std::left << "Bias"
                << std::setw(10) << std::left << "BN"
                << std::setw(15) << std::left << "Activation"
                << "\n";

            // Add a separator line
            ss << std::string(150, '-') << "\n";

            // Table rows for layer configurations
            for (const LayerStats* stats : layer_stats) {
                std::string input_shape = "-";
                std::string output_shape = "-";
                std::string kernel = "-";
                std::string stride = "-";
                std::string padding = "-";
                std::string use_bias = "-";
                std::string batch_norm = "-";
                std::string activation = "-";

                const auto& cfg = stats->config;
                const bool has_config =
                    cfg.input_height > 0 || cfg.input_width > 0 || cfg.input_channels > 0 ||
                    cfg.output_height > 0 || cfg.output_width > 0 || cfg.output_channels > 0;

                if (has_config) {
                    input_shape = "(" + std::to_string(cfg.input_height) + ", "
                        + std::to_string(cfg.input_width) + ", "
                        + std::to_string(cfg.input_channels) + ")";

                    // Dense/Flatten historically report a flat (C, 1, 1) output layout.
                    if (stats->layer_type == "Dense" || stats->layer_type == "Flatten") {
                        output_shape = "(" + std::to_string(cfg.output_channels) + ", 1, 1)";
                    }
                    else {
                        output_shape = "(" + std::to_string(cfg.output_height) + ", "
                            + std::to_string(cfg.output_width) + ", "
                            + std::to_string(cfg.output_channels) + ")";
                    }

                    if (cfg.kernel_size > 0) {
                        kernel = std::to_string(cfg.kernel_size) + "x" + std::to_string(cfg.kernel_size);
                        stride = std::to_string(cfg.stride);
                        padding = std::to_string(cfg.padding);
                    }
                    else if (cfg.stride > 0) {
                        stride = std::to_string(cfg.stride);
                    }

                    use_bias = cfg.use_bias ? "Yes" : "No";
                    batch_norm = cfg.batch_norm ? "Yes" : "No";
                    activation = cfg.activation.empty() ? "None" : cfg.activation;
                }

                ss << std::setw(25) << std::left << stats->layer_name
                    << std::setw(15) << std::left << stats->layer_type
                    << std::setw(25) << std::left << input_shape
                    << std::setw(25) << std::left << output_shape
                    << std::setw(15) << std::left << kernel
                    << std::setw(10) << std::left << stride
                    << std::setw(10) << std::left << padding
                    << std::setw(10) << std::left << use_bias
                    << std::setw(10) << std::left << batch_norm
                    << std::setw(15) << std::left << activation
                    << "\n";
            }
        }

        return ss.str();
    }

    // Helper function to convert OperationType to string
    std::string operationTypeToString(OperationType op_type) {
        switch (op_type) {
        case OperationType::MEMORY_LOAD:
            return "Memory Load";
        case OperationType::MEMORY_STORE:
            return "Memory Store";
        case OperationType::ARITHMETIC_ADD:
            return "Arithmetic Add";
        case OperationType::ARITHMETIC_MUL:
            return "Arithmetic Mul";
        case OperationType::ARITHMETIC_COMP:
            return "Arithmetic Comp";
        case OperationType::ARITHMETIC_OTHER:
            return "Arithmetic Other";
        default:
            return "Unknown";
        }
    }

} // namespace DC_ConvNet 