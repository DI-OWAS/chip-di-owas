#include "DC_config_parser.h"
#include "DC_baremetal_log.h"

#include <fstream>
#include <iostream>

namespace DC_ConvNet {

    // Utility function to trim leading/trailing whitespace
    std::string trim(const std::string& str) {
        size_t first = str.find_first_not_of(" \t\r\n");
        if (std::string::npos == first) {
            return str; // No non-whitespace characters
        }
        size_t last = str.find_last_not_of(" \t\r\n");
        return str.substr(first, (last - first + 1));
    }

    // Convert string to float
    float str_to_float(const std::string& str) {
        try {
            return std::stof(str);
        }
        catch (const std::exception& e) {
            std::cerr << "Warning: Could not convert '" << str << "' to float: " << e.what() << std::endl;
            return 0.0f;
        }
    }

    // Convert string to int
    int str_to_int(const std::string& str) {
        try {
            return std::stoi(str);
        }
        catch (const std::exception& e) {
            std::cerr << "Warning: Could not convert '" << str << "' to int: " << e.what() << std::endl;
            return 0;
        }
    }

    // Helper function to extract a string value from a JSON field
    std::string extract_json_string(const std::string& json_line, const std::string& field_name) {
        // Find the field name with quotes and colon
        std::string search_pattern = "\"" + field_name + "\"";
        size_t field_pos = json_line.find(search_pattern);
        if (field_pos == std::string::npos) {
            return "";
        }

        // Find the colon after the field name
        size_t colon_pos = json_line.find(':', field_pos + search_pattern.length());
        if (colon_pos == std::string::npos) {
            return "";
        }

        // Find the opening quote for the value
        size_t value_start = json_line.find('"', colon_pos + 1);
        if (value_start == std::string::npos) {
            return "";
        }

        // Find the closing quote for the value
        size_t value_end = json_line.find('"', value_start + 1);
        if (value_end == std::string::npos) {
            return "";
        }

        // Extract and return the value
        return json_line.substr(value_start + 1, value_end - value_start - 1);
    }

    // Helper function to extract a float value from a JSON field
    float extract_json_float(const std::string& json_line, const std::string& field_name, float default_value = 0.0f) {
        // Find the field name with quotes and colon
        std::string search_pattern = "\"" + field_name + "\"";
        size_t field_pos = json_line.find(search_pattern);
        if (field_pos == std::string::npos) {
            return default_value;
        }

        // Find the colon after the field name
        size_t colon_pos = json_line.find(':', field_pos + search_pattern.length());
        if (colon_pos == std::string::npos) {
            return default_value;
        }

        // Skip whitespace after colon
        size_t value_start = colon_pos + 1;
        while (value_start < json_line.length() && std::isspace(json_line[value_start])) {
            value_start++;
        }

        // Find the end of the value (comma, closing brace, or end of line)
        size_t value_end = json_line.find_first_of(",}", value_start);
        if (value_end == std::string::npos) {
            value_end = json_line.length();
        }

        // Extract the value as string and convert to float
        std::string value_str = trim(json_line.substr(value_start, value_end - value_start));
        try {
            return std::stof(value_str);
        }
        catch (const std::exception& e) {
            std::cerr << "Warning: Could not convert JSON value to float: " << e.what() << std::endl;
            return default_value;
        }
    }

    static void apply_config_line(
        DC_NetConfig& config,
        DC_NetConfig::LayerConfig& current_layer,
        bool& first_layer,
        const std::string& line)
    {
        if (line.empty() || line[0] == '#') {
            return;
        }

        if (line[0] == '[' && line.back() == ']') {
            if (!first_layer && !current_layer.type.empty()) {
                config.layers.push_back(current_layer);
            }

            current_layer = DC_NetConfig::LayerConfig();
            current_layer.type = line.substr(1, line.length() - 2);
            first_layer = false;
            return;
        }

        if (first_layer) {
            return;
        }

        const size_t equals_pos = line.find('=');
        if (equals_pos == std::string::npos) {
            return;
        }

        const std::string key = trim(line.substr(0, equals_pos));
        const std::string value = trim(line.substr(equals_pos + 1));

        if (key.empty() || value.empty()) {
            return;
        }

        current_layer.params[key] = value;

        if (current_layer.type == "net") {
            if (key == "batch") {
                config.batch = str_to_int(value);
            }
            else if (key == "subdivisions") {
                config.subdivisions = str_to_int(value);
            }
            else if (key == "width") {
                config.width = str_to_int(value);
            }
            else if (key == "height") {
                config.height = str_to_int(value);
            }
            else if (key == "channels") {
                config.channels = str_to_int(value);
            }
            else if (key == "momentum") {
                config.momentum = str_to_float(value);
            }
            else if (key == "decay") {
                config.decay = str_to_float(value);
            }
            else if (key == "angle") {
                config.angle = str_to_float(value);
            }
            else if (key == "saturation") {
                config.saturation = str_to_float(value);
            }
            else if (key == "exposure") {
                config.exposure = str_to_float(value);
            }
            else if (key == "hue") {
                config.hue = str_to_float(value);
            }
            else if (key == "data_format") {
                config.is_channel_first = value != "channels_last";
            }
        }
    }

    static DC_NetConfig finalize_network_config(
        DC_NetConfig config,
        DC_NetConfig::LayerConfig& current_layer,
        bool first_layer,
        const char* source_label)
    {
        if (!first_layer && !current_layer.type.empty()) {
            config.layers.push_back(current_layer);
        }

        if (config.layers.empty()) {
            throw std::runtime_error(std::string("Error: No layer configurations found in config: ") + source_label);
        }

        return config;
    }

    static DC_NetConfig parse_network_config_stream(std::istream& input, const char* source_label) {
        DC_NetConfig config;
        DC_NetConfig::LayerConfig current_layer;
        bool first_layer = true;

        std::string line;
        while (std::getline(input, line)) {
            apply_config_line(config, current_layer, first_layer, trim(line));
        }

        return finalize_network_config(config, current_layer, first_layer, source_label);
    }

    DC_NetConfig parse_network_config(const std::string& config_file) {
        std::ifstream file(config_file);
        if (!file.is_open()) {
            throw std::runtime_error("Error: Could not open config file: " + config_file);
        }
        return parse_network_config_stream(file, config_file.c_str());
    }

    DC_NetConfig parse_network_config_from_memory(const char* data, std::size_t size) {
        if (data == nullptr || size == 0U) {
            throw std::runtime_error("Error: Empty network config buffer");
        }

        DC_NetConfig config;
        DC_NetConfig::LayerConfig current_layer;
        bool first_layer = true;

        const char* cursor = data;
        const char* const end = data + size;

        while (cursor < end) {
            const char* line_start = cursor;
            while (cursor < end && *cursor != '\n') {
                ++cursor;
            }

            std::string line(line_start, static_cast<std::size_t>(cursor - line_start));
            if (cursor < end) {
                ++cursor;
            }

            while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
                line.pop_back();
            }

            apply_config_line(config, current_layer, first_layer, trim(line));
        }

        DC_CNN_LOG("CNN: cfg buffer scan complete\r\n");

        return finalize_network_config(config, current_layer, first_layer, "embedded_cfg");
    }

    DC_JsonConfig parse_json_config(const std::string& json_file) {
        std::ifstream file(json_file);
        if (!file.is_open()) {
            throw std::runtime_error("Error: Could not open JSON config file: " + json_file);
        }

        DC_JsonConfig config;
        std::string json_content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
        file.close();

        // Parse required fields
        config.network_topology_file = extract_json_string(json_content, "network_topology_file");
        if (config.network_topology_file.empty()) {
            throw std::runtime_error("Error: Missing 'network_topology_file' in JSON config: " + json_file);
        }

        config.weights_file = extract_json_string(json_content, "weights_file");
        if (config.weights_file.empty()) {
            throw std::runtime_error("Error: Missing 'weights_file' in JSON config: " + json_file);
        }

        config.image_inputs_dir = extract_json_string(json_content, "image_inputs_dir");
        if (config.image_inputs_dir.empty()) {
            throw std::runtime_error("Error: Missing 'image_inputs_dir' in JSON config: " + json_file);
        }

        config.weight_format_str = extract_json_string(json_content, "weight_format");
        if (config.weight_format_str.empty()) {
            throw std::runtime_error("Error: Missing 'weight_format' in JSON config: " + json_file);
        }

        return config;
    }

} // namespace DC_ConvNet 
