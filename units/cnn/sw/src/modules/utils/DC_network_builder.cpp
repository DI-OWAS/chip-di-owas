#include "DC_network_builder.h"
#include "DC_baremetal_log.h"
#include "DC_CNNLayer_Flatten.h"
#include "DC_CNNLayer_Dense.h"
#include "DC_CNNLayer_Softmax.h"
#include "DC_CNNLayer_SoftmaxND.h"
#include "DC_CNNLayer_SkipLayerNorm.h"
#include "DC_CNNLayer_YoloLayer.h"
#include "DC_CNNLayer_Conv2D.h"
#include "DC_CNNLayer_MaxPool2D.h"
#include "DC_CNNLayer_Route.h"
#include "DC_CNNLayer_Shortcut.h"
#include "DC_CNNLayer_AvgPool2D.h"
#include "DC_CNNLayer_L2Norm.h"
#include "DC_CNNLayer_Upsample.h"
#include "DC_CNNLayer_Reshape.h"
#include "DC_CNNLayer_Transpose.h"
#include "DC_CNNLayer_Concat.h"
#include "DC_CNNLayer_Add.h"
#include "DC_CNNLayer_LayerNorm.h"
#include "DC_CNNLayer_Relu.h"
#include "DC_CNNLayer_Gelu.h"
#include "DC_CNNLayer_Slice.h"
#include "DC_CNNLayer_Resize.h"
#include "DC_CNNLayer_DeConv2D.h"
#include "DC_CNNLayer_Gemm.h"
#include "DC_CNNLayer_Gather.h"
#include "DC_CNNLayer_Mul.h"
#include "DC_CNNLayer_MatMul.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_CNN_activation_types.h"
#include "DC_config_parser.h"
#include "DC_weight_loader.h"
#include "DC_FifoCommandBuilder_CNNLayer_Conv2D.h"
#include "DC_FifoCommandBuilder_CNNLayer_MaxPool2D.h"
#include "DC_FifoCommandBuilder_CNNLayer_Route.h"
#include "DC_FifoCommandBuilder_CNNLayer_Upsample.h"

#include <iostream>
#include <sstream>
#include <filesystem>

namespace
{
    // Utility function to trim leading/trailing whitespace
    std::string trim(const std::string& str) {
        size_t first = str.find_first_not_of(" \t\r\n");
        if (std::string::npos == first) {
            return str; // No non-whitespace characters
        }
        size_t last = str.find_last_not_of(" \t\r\n");
        return str.substr(first, (last - first + 1));
    }

    // Utility function to parse anchors string into a vector of floats
    std::vector<float> parse_anchors(const std::string& anchor_string) {
        std::vector<float> anchors;

        // Remove any whitespace
        std::string cleaned = anchor_string;
        cleaned.erase(std::remove_if(cleaned.begin(), cleaned.end(),
            [](char c) { return std::isspace(c); }), cleaned.end());

        std::stringstream ss(cleaned);
        std::string token;

        while (std::getline(ss, token, ',')) {
            if (!token.empty()) {
                try {
                    float val = std::stof(token);
                    anchors.push_back(val);
                }
                catch (const std::exception& e) {
                    std::cerr << "Warning: Failed to parse anchor value '" << token << "': " << e.what() << std::endl;
                }
            }
        }

        return anchors;
    }

    std::vector<int> parse_int_list(const std::string& value_string, const char* param_name) {
        std::vector<int> values;
        std::stringstream ss(value_string);
        std::string token;

        while (std::getline(ss, token, ',')) {
            const auto cleaned = trim(token);
            if (!cleaned.empty()) {
                values.push_back(std::stoi(cleaned));
            }
        }

        if (values.empty()) {
            throw std::runtime_error(std::string(param_name) + " requires a non-empty comma-separated integer list");
        }

        return values;
    }

    std::vector<int> parse_slice_int_list(const std::string& value_string, const char* param_name) {
        std::vector<int> values;
        std::stringstream ss(value_string);
        std::string token;

        while (std::getline(ss, token, ',')) {
            const auto cleaned = trim(token);
            if (!cleaned.empty()) {
                const auto parsed = std::stoll(cleaned);
                if (parsed > static_cast<long long>(std::numeric_limits<int>::max())) {
                    values.push_back(std::numeric_limits<int>::max());
                }
                else if (parsed < static_cast<long long>(std::numeric_limits<int>::min())) {
                    values.push_back(std::numeric_limits<int>::min());
                }
                else {
                    values.push_back(static_cast<int>(parsed));
                }
            }
        }

        if (values.empty()) {
            throw std::runtime_error(std::string(param_name) + " requires a non-empty comma-separated integer list");
        }

        return values;
    }

    std::vector<float> parse_float_list(const std::string& value_string, const char* param_name) {
        std::vector<float> values;
        std::stringstream ss(value_string);
        std::string token;

        while (std::getline(ss, token, ',')) {
            const auto cleaned = trim(token);
            if (!cleaned.empty()) {
                values.push_back(std::stof(cleaned));
            }
        }

        if (values.empty()) {
            throw std::runtime_error(std::string(param_name) + " requires a non-empty comma-separated float list");
        }

        return values;
    }

    std::vector<int> compute_resize_output_shape_from_scales(
        const std::vector<int>& input_shape,
        const std::vector<float>& scales) {
        if (input_shape.size() != scales.size()) {
            throw std::runtime_error(
                "Resize scales rank " + std::to_string(scales.size())
                + " does not match input shape rank " + std::to_string(input_shape.size()));
        }

        std::vector<int> output_shape(input_shape.size());
        for (size_t i = 0; i < input_shape.size(); ++i) {
            output_shape[i] = static_cast<int>(std::lround(input_shape[i] * scales[i]));
        }

        return output_shape;
    }

    int shape_element_count(const std::vector<int>& shape) {
        return std::accumulate(shape.begin(), shape.end(), 1, std::multiplies<int>());
    }

    void resolve_nchw_spatial_dims(
        const DC_ConvNet::DC_Tensor& tensor,
        const std::vector<int>& logical_shape,
        int& in_channels,
        int& spatial_h,
        int& spatial_w) {
        if (logical_shape.size() == 4) {
            in_channels = logical_shape[1];
            spatial_h = logical_shape[2];
            spatial_w = logical_shape[3];
            return;
        }

        in_channels = tensor.m_channels;
        spatial_h = tensor.m_height;
        spatial_w = tensor.m_width;
    }

    std::vector<int> make_nchw_output_shape(
        const std::vector<int>& input_logical,
        int out_channels,
        int spatial_h,
        int spatial_w) {
        if (input_logical.size() == 4) {
            return {input_logical[0], out_channels, spatial_h, spatial_w};
        }

        return DC_ConvNet::hwc_to_shape(spatial_h, spatial_w, out_channels);
    }

    void logical_shape_to_tensor_dims(
        const std::vector<int>& logical_shape,
        int& height,
        int& width,
        int& channels) {
        DC_ConvNet::logical_shape_to_tensor_dims(logical_shape, height, width, channels);
    }

    DC_ConvNet::ActivationType parse_activation_type(const std::string& activation) {
        if (activation == "leaky") {
            return DC_ConvNet::ActivationType::LEAKY_RELU;
        }
        if (activation == "relu") {
            return DC_ConvNet::ActivationType::RELU;
        }
        if (activation == "linear") {
            return DC_ConvNet::ActivationType::NONE;
        }

        throw std::runtime_error("Unsupported activation type: " + activation);
    }

    std::vector<int> apply_transpose_perm(
        const std::vector<int>& input_shape,
        const std::vector<int>& perm) {
        if (perm.size() != input_shape.size()) {
            throw std::runtime_error("Transpose perm rank does not match input shape rank");
        }

        std::vector<int> output_shape(perm.size());
        for (size_t i = 0; i < perm.size(); ++i) {
            output_shape[i] = input_shape[static_cast<size_t>(perm[i])];
        }

        return output_shape;
    }

    template<bool kShapeOnlyTracker>
    void append_layer_output(
        std::vector<DC_ConvNet::DC_Tensor>& output_tracker,
        std::vector<std::vector<int>>& logical_tracker,
        int height,
        int width,
        int channels,
        DC_ConvNet::MEM_ORDER mem_order,
        const std::vector<int>& logical_shape) {
        if constexpr (kShapeOnlyTracker) {
            output_tracker.emplace_back(height, width, channels, mem_order, false);
        }
        else {
            output_tracker.emplace_back(height, width, channels, mem_order);
        }
        logical_tracker.push_back(logical_shape);
    }

    std::vector<int> resolve_transpose_input_shape(
        const DC_ConvNet::DC_Tensor& input_tensor,
        const std::vector<int>& perm,
        const std::vector<std::vector<int>>& logical_tracker) {
        const auto hwc_shape = DC_ConvNet::hwc_to_shape(
            input_tensor.m_height, input_tensor.m_width, input_tensor.m_channels);
        const auto input_elements = DC_ConvNet::tensor_element_count(input_tensor);

        if (!logical_tracker.empty()) {
            const auto& logical_shape = logical_tracker.back();
            if (logical_shape.size() == perm.size() && shape_element_count(logical_shape) == input_elements) {
                return logical_shape;
            }
        }

        if (hwc_shape.size() == perm.size()) {
            return hwc_shape;
        }

        throw std::runtime_error(
            "Cannot infer input shape for transpose with perm rank " + std::to_string(perm.size()));
    }

    std::vector<int> logical_shape_for_relative_output(
        int relative_index,
        size_t built_layer_count,
        const std::vector<std::vector<int>>& logical_tracker) {
        const auto forward_index = DC_ConvNet::resolve_relative_index(relative_index, built_layer_count);
        const auto tracker_index = forward_index + 1;

        if (tracker_index >= logical_tracker.size()) {
            throw std::runtime_error(
                "Logical shape tracker out of bounds for relative layer index "
                + std::to_string(relative_index));
        }

        return logical_tracker[tracker_index];
    }

    std::vector<int> compute_concat_output_shape(
        const std::vector<std::vector<int>>& input_shapes,
        int axis) {

        auto output_shape = input_shapes.front();
        int normalized_axis = axis;
        DC_ConvNet::normalize_axis(normalized_axis, static_cast<int>(output_shape.size()));

        if (input_shapes.size() == 1)
        {
            //+1 CLS token
            output_shape[static_cast<size_t>(normalized_axis)] += 1;
        }

        for (size_t i = 1; i < input_shapes.size(); ++i) {
            if (input_shapes[i].size() != output_shape.size()) {
                throw std::runtime_error("Concat inputs must have the same rank");
            }

            for (int dim = 0; dim < static_cast<int>(output_shape.size()); ++dim) {
                if (dim == normalized_axis) {
                    output_shape[static_cast<size_t>(dim)] += input_shapes[i][static_cast<size_t>(dim)];
                }
                else if (input_shapes[i][static_cast<size_t>(dim)] != output_shape[static_cast<size_t>(dim)]) {
                    throw std::runtime_error("Concat inputs must match on non-concat axes");
                }
            }
        }

        return output_shape;
    }

    std::pair<int, int> matrix_dims_from_logical_shape(const std::vector<int>& shape) {
        int height = 0;
        int width = 0;
        int channels = 0;
        DC_ConvNet::shape_to_hwc(shape, height, width, channels);

        if (channels == 1) {
            return {height, width};
        }

        return {height * width, channels};
    }

    std::vector<int> compute_matmul_output_shape(
        const std::vector<int>& lhs_shape,
        const std::vector<int>& rhs_shape) {
        if (lhs_shape.size() == 4 && rhs_shape.size() == 4) {
            if (lhs_shape[0] != rhs_shape[0] || lhs_shape[1] != rhs_shape[1]) {
                throw std::runtime_error("Batched MatMul batch dimensions must match");
            }
            if (lhs_shape[3] != rhs_shape[2]) {
                throw std::runtime_error("MatMul inner dimensions do not match");
            }

            return {lhs_shape[0], lhs_shape[1], lhs_shape[2], rhs_shape[3]};
        }

        const auto [lhs_rows, lhs_cols] = matrix_dims_from_logical_shape(lhs_shape);
        const auto [rhs_rows, rhs_cols] = matrix_dims_from_logical_shape(rhs_shape);
        if (lhs_cols != rhs_rows) {
            throw std::runtime_error(
                "MatMul inner dimensions do not match: lhs cols="
                + std::to_string(lhs_cols) + ", rhs rows=" + std::to_string(rhs_rows));
        }

        return DC_ConvNet::hwc_to_shape(lhs_rows, rhs_cols, 1);
    }

    // Function to determine test data path based on config file
    std::string determine_test_data_path(const std::string& config_file) {
        namespace fs = std::filesystem;

        std::string source_dir = SOURCE_DIR;

        std::string test_data_path = "./";

        try {
            if (config_file.find("yolo") != std::string::npos) {
                test_data_path = source_dir + "/test_data/yolo_inference/";
            }
            else if (config_file.find("cifar") != std::string::npos) {
                test_data_path = source_dir + "/test_data/cifar_inference/";
            }
        }
        catch (const std::exception& e) {
            std::cerr << "Error determining test data path: " << e.what() << std::endl;
        }

        return test_data_path;
    }
}

using namespace DC_ConvNet;

// Add the new function before the build_cnn_layers_from_config function
template<typename ConvT>
std::unique_ptr<ConvT> DC_ConvNet::create_conv_layer(
    const std::map<std::string, std::string>& params,
    int current_in_channels,
    bool verbose) {
    
    const auto filters = std::stoi(params.at("filters"));
    const auto ksize = std::stoi(params.at("size"));
    const auto stride = std::stoi(params.at("stride"));
    const auto pad = params.count("pad") ? std::stoi(params.at("pad")) : 0;
    const auto padding = (pad == 1) ? (ksize / 2) : 0;
    const auto batch_normalize = params.count("batch_normalize") && params.at("batch_normalize") == "1";
    const auto use_bias = !batch_normalize && (params.count("bias") ? params.at("bias") == "1" : false);
    const auto activation = params.at("activation");

    if (verbose) {
        // Enhanced debug output
        std::cout << " (Filters: " << filters << ", Kernel: " << ksize
            << ", Stride: " << stride << ", Pad: " << padding
            << ", BN: " << (batch_normalize ? "yes" : "no")
            << ", Bias: " << (use_bias ? "yes" : "no")
            << ", Act: " << activation
            << ", In Ch: " << current_in_channels << ")" << std::endl;
    }

    // Determine activation type and parameters
    const auto act_type = parse_activation_type(activation);

    // Create and return convolutional layer
    return std::make_unique<ConvT>(
        current_in_channels,    // in_channels
        filters,               // out_channels
        ksize,                // kernel_size
        stride,               // stride
        padding,              // padding
        use_bias,            // use_bias (only if no batch norm and bias=1)
        batch_normalize,      // batch_norm
        act_type             // activation
    );
}

// Add after create_conv_layer function and before build_cnn_layers_from_config
template<typename RouteT>
std::unique_ptr<RouteT> DC_ConvNet::create_route_layer(
    const std::map<std::string, std::string>& params,
    size_t current_layer_idx,
    const std::map<size_t, size_t>& config_to_layer_index,
    const std::vector<DC_Tensor>& layer_output_tracker,
    int& route_output_channels,
    int& route_output_height,
    int& route_output_width,
    bool verbose) {
    
    const auto layers_str = params.at("layers");
    const auto groups = params.count("groups") ? std::stoi(params.at("groups")) : 1;
    const auto group_id = params.count("group_id") ? std::stoi(params.at("group_id")) : 0;

    std::stringstream ss(layers_str);
    std::string segment;
    std::vector<std::pair<int, DC_Tensor>> absolute_built_indices;
    std::vector<int> source_channels;
    std::vector<const DC_Tensor*> source_tensors;

    while (std::getline(ss, segment, ',')) {
        try {
            const auto original_idx = std::stoi(trim(segment));
            const auto is_relative = original_idx < 0;

            // Calculate the target *config* index
            const auto target_cfg_idx = is_relative ? 
                static_cast<int>(current_layer_idx) + original_idx : original_idx;

            // Find the corresponding *built layer index* using the map
            if (config_to_layer_index.count(target_cfg_idx)) {
                const auto built_layer_idx = is_relative ? 
                    static_cast<unsigned>(config_to_layer_index.at(target_cfg_idx)) 
                    : static_cast<unsigned>(target_cfg_idx);

                const DC_Tensor& source_tensor = layer_output_tracker[built_layer_idx + 1];
                absolute_built_indices.push_back({ built_layer_idx, source_tensor });

                // Get channels from the channel tracker using the *built* index + 1
                if (built_layer_idx + 1 < layer_output_tracker.size()) {
                    source_channels.push_back(source_tensor.m_channels);
                    source_tensors.push_back(&source_tensor);
                }
                else {
                    throw std::runtime_error("Channel tracker out of bounds for built layer index " + std::to_string(built_layer_idx));
                }
            }
            else {
                throw std::runtime_error("Route target config index " + std::to_string(target_cfg_idx)
                    + " (from original index " + std::to_string(original_idx)
                    + ") does not correspond to a built layer.");
            }
        }
        catch (const std::invalid_argument&) {
            throw std::runtime_error("Invalid index in route layer: " + segment);
        }
        catch (const std::out_of_range& e) {
            throw std::runtime_error("Out of range error accessing config/channel map for route layer: " + std::string(e.what()));
        }
    }

    if (source_tensors.empty()) {
        throw std::runtime_error("Route layer has no valid source tensors");
    }

    // Spatial size follows the routed source(s), not the immediately preceding layer.
    route_output_height = source_tensors[0]->m_height;
    route_output_width = source_tensors[0]->m_width;
    for (size_t i = 1; i < source_tensors.size(); ++i) {
        if (source_tensors[i]->m_height != route_output_height ||
            source_tensors[i]->m_width != route_output_width) {
            throw std::runtime_error(
                "Route layer source tensors must share the same spatial dimensions");
        }
    }

    // Calculate the output channels for this route layer
    route_output_channels = 0;
    if (groups > 1 && absolute_built_indices.size() == 1) {
        // CSP block with channel splitting
        route_output_channels = source_channels[0] / groups;
    }
    else {
        // Regular route layer or CSP concatenation
        for (auto ch : source_channels) {
            route_output_channels += ch;
        }
    }

    if (verbose) {
        std::cout << " (Indices(cfg): " << layers_str;
        if (groups > 1) {
            std::cout << ", Groups: " << groups << ", Group ID: " << group_id;
        }
        std::cout << ") -> Out: " << route_output_height << "x" << route_output_width
            << "x" << route_output_channels << std::endl;
    }

    return std::make_unique<RouteT>(absolute_built_indices, groups, group_id);
}

// Add after create_route_layer function and before build_cnn_layers_from_config
std::unique_ptr<DC_CNNLayer_YoloLayer> DC_ConvNet::create_yolo_layer(
    const std::map<std::string, std::string>& params,
    size_t layer_idx,
    bool verbose) {
    
    // Validate required parameters
    if (params.find("classes") == params.end() ||
        params.find("anchors") == params.end() ||
        params.find("mask") == params.end()) {
        throw std::runtime_error("YOLO layer missing required parameters at index " + std::to_string(layer_idx));
    }

    const auto num_classes = std::stoi(params.at("classes"));

    // Parse anchors
    const auto all_anchors = parse_anchors(params.at("anchors"));
    if (all_anchors.empty()) {
        throw std::runtime_error("No valid anchors found in config");
    }

    // Parse anchor masks
    std::vector<int> mask;
    std::string mask_str = params.at("mask");
    std::stringstream mask_ss(mask_str);
    std::string mask_token;
    while (std::getline(mask_ss, mask_token, ',')) {
        // Trim whitespace
        mask_token.erase(0, mask_token.find_first_not_of(" \t\r\n"));
        mask_token.erase(mask_token.find_last_not_of(" \t\r\n") + 1);
        if (!mask_token.empty()) {
            try {
                const auto val = std::stoi(mask_token);
                mask.push_back(val);
            }
            catch (const std::exception& e) {
                throw std::runtime_error("Failed to parse mask value '" + mask_token + "': " + e.what());
            }
        }
    }

    // Get anchors for this specific YOLO layer using mask
    std::vector<float> layer_anchors;
    for (auto mask_idx : mask) {
        // Each anchor is a pair (width, height), so multiply index by 2
        const auto anchor_idx = static_cast<unsigned>(mask_idx) * 2u;
        if (anchor_idx + 1 >= all_anchors.size()) {
            std::stringstream err;
            err << "Invalid anchor mask index " << mask_idx
                << " for layer with " << all_anchors.size() / 2 << " anchor pairs";
            throw std::runtime_error(err.str());
        }
        layer_anchors.push_back(all_anchors[anchor_idx]);     // width
        layer_anchors.push_back(all_anchors[anchor_idx + 1]); // height
    }

    if (verbose) {
        std::cout << "   YOLO layer using " << mask.size() << " anchor pairs\n";
        for (size_t j = 0; j < layer_anchors.size(); j += 2) {
            std::cout << "   Anchor " << (j / 2) << ": ("
                << layer_anchors[j] << ", " << layer_anchors[j + 1] << ")\n";
        }
    }

    return std::make_unique<DC_CNNLayer_YoloLayer>(
        static_cast<int>(mask.size()),  // num_anchors for this specific layer
        num_classes,
        layer_anchors,
        std::stof(params.at("scale_x_y"))
    );
}

// Add after create_yolo_layer function and before build_cnn_layers_from_config
std::pair<std::unique_ptr<DC_CNNLayer_Dense>, int> DC_ConvNet::create_dense_layer(
    const std::map<std::string, std::string>& params,
    int current_in_channels,
    bool verbose) {
    
    const auto output_units = (params.count("output")) ? std::stoi(params.at("output")) : 1;
    const auto activation = (params.count("activation")) ? params.at("activation") : "linear";
    const auto use_bias = true;  // Default to true for dense layers

    // Determine activation type
    auto act_type = ActivationType::NONE;
    const auto leaky_alpha = 0.1f;

    if (activation == "relu") {
        act_type = ActivationType::RELU;
    }
    else if (activation == "leaky") {
        act_type = ActivationType::LEAKY_RELU;
    }

    if (verbose) {
        std::cout << "  Dense: OutputUnits=" << output_units
            << ", Activation=" << activation
            << ", InputUnits=" << current_in_channels << std::endl;
    }

    return {
        std::make_unique<DC_CNNLayer_Dense>(
            output_units,         // output units
            use_bias,             // use bias
            act_type,             // activation type
            leaky_alpha           // leaky alpha
        ),
        output_units
    };
}

namespace {

template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT, bool kShapeOnlyTracker>
std::vector<std::unique_ptr<DC_Layer>> build_cnn_layers_from_net_config_impl(
    DC_OWAS::DC_OWAS_TopLevel* owas_top_level,
    const DC_NetConfig& net_conf,
    const std::string& weights_file,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    bool verbose,
    const std::string& config_path_hint) {
    std::map<size_t, size_t> config_to_layer_index;
    std::vector<DC_Tensor> layer_output_tracker;
    std::vector<std::vector<int>> layer_logical_shape_tracker;
    std::vector<std::unique_ptr<DC_Layer>> layers;

    const bool weights_from_rom = (weights_data != nullptr) && (weights_size > 0U);

    append_layer_output<kShapeOnlyTracker>(
        layer_output_tracker,
        layer_logical_shape_tracker,
        net_conf.height,
        net_conf.width,
        net_conf.channels,
        mem_order,
        hwc_to_shape(net_conf.height, net_conf.width, net_conf.channels));

    // Second Pass: Build the actual network layers
    for (auto i = 0u; i < net_conf.layers.size(); ++i) {
        const auto& layer_config = net_conf.layers[i];
        const auto& params = layer_config.params;
        const auto type = layer_config.type;

        if (type == "net") {
            continue;
        }

        if constexpr (kShapeOnlyTracker) {
            if ((i <= 1U) || ((i % 5U) == 0U)) {
                DC_CNN_LOG(
                    "CNN build: cfg %u [%s]\r\n",
                    static_cast<unsigned>(i),
                    type.c_str());
            }
        }

        if (verbose) {
            std::cout << "Layer " << i << ": Type = [" << type << "]";
        }

        // Get input channels from the output of the *immediately preceding* layer
        const auto current_in_channels = layer_output_tracker.back().m_channels;

        try {
            if (type == "convolutional") {
                const auto& input_tensor = layer_output_tracker.back();
                const auto& input_logical = layer_logical_shape_tracker.back();

                int in_channels = current_in_channels;
                int spatial_h = input_tensor.m_height;
                int spatial_w = input_tensor.m_width;
                resolve_nchw_spatial_dims(input_tensor, input_logical, in_channels, spatial_h, spatial_w);

                auto conv = create_conv_layer<ConvT>(params, in_channels, verbose);

                const auto ksize = std::stoi(params.at("size"));
                const auto stride = std::stoi(params.at("stride"));
                const auto pad = params.count("pad") ? std::stoi(params.at("pad")) : 0;
                const auto padding = (pad == 1) ? (ksize / 2) : 0;
                const auto filters = std::stoi(params.at("filters"));

                const auto out_spatial_h = (spatial_h + 2 * padding - ksize) / stride + 1;
                const auto out_spatial_w = (spatial_w + 2 * padding - ksize) / stride + 1;
                const auto output_logical = make_nchw_output_shape(
                    input_logical,
                    filters,
                    out_spatial_h,
                    out_spatial_w);

                layers.push_back(std::move(conv));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_spatial_h,
                    out_spatial_w,
                    filters,
                    mem_order,
                    output_logical);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "deconvolutional") {
                const auto filters = std::stoi(params.at("filters"));
                const auto ksize = std::stoi(params.at("size"));
                const auto stride = std::stoi(params.at("stride"));
                const auto pad = params.count("pad") ? std::stoi(params.at("pad")) : 0;
                const auto padding = (pad == 1) ? (ksize / 2) : pad;
                const auto batch_normalize = params.count("batch_normalize") && params.at("batch_normalize") == "1";
                const auto use_bias = params.count("bias") ? params.at("bias") == "1" : !batch_normalize;
                const auto activation = params.at("activation");
                const auto act_type = parse_activation_type(activation);

                const auto& input_tensor = layer_output_tracker.back();
                const auto& input_logical = layer_logical_shape_tracker.back();

                int in_channels = current_in_channels;
                int spatial_h = input_tensor.m_height;
                int spatial_w = input_tensor.m_width;
                resolve_nchw_spatial_dims(input_tensor, input_logical, in_channels, spatial_h, spatial_w);

                const auto out_spatial_h = (spatial_h - 1) * stride - 2 * padding + ksize;
                const auto out_spatial_w = (spatial_w - 1) * stride - 2 * padding + ksize;
                const auto output_logical = make_nchw_output_shape(
                    input_logical,
                    filters,
                    out_spatial_h,
                    out_spatial_w);

                if (verbose) {
                    std::cout << " (Filters: " << filters << ", Kernel: " << ksize
                        << ", Stride: " << stride << ", Pad: " << padding
                        << ", Bias: " << (use_bias ? "yes" : "no")
                        << ", Act: " << activation
                        << ", In Ch: " << in_channels << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_DeConv2D>(
                    in_channels,
                    filters,
                    ksize,
                    stride,
                    padding,
                    use_bias,
                    act_type));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_spatial_h,
                    out_spatial_w,
                    filters,
                    mem_order,
                    output_logical);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "maxpool") {
                const auto ksize = std::stoi(params.at("size"));

                const auto stride = std::stoi(params.at("stride"));

                if (verbose) {
                    std::cout << " (Size: " << ksize << ", Stride: " << stride << ")" << std::endl;
                }

                const auto out_h = (layer_output_tracker.back().m_height - ksize) / stride + 1;
                const auto out_w = (layer_output_tracker.back().m_width - ksize) / stride + 1;

                layers.push_back(std::make_unique<MaxPoolT>(ksize, stride));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    current_in_channels,
                    mem_order,
                    hwc_to_shape(out_h, out_w, current_in_channels));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "route") {
                int route_output_channels = 0;
                int route_output_height = 0;
                int route_output_width = 0;

                auto route_layer = create_route_layer<RouteT>(params, i, config_to_layer_index,
                    layer_output_tracker, route_output_channels, route_output_height,
                    route_output_width, verbose);

                layers.push_back(std::move(route_layer));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    route_output_height,
                    route_output_width,
                    route_output_channels,
                    mem_order,
                    hwc_to_shape(
                        route_output_height,
                        route_output_width,
                        route_output_channels));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "shortcut") {
                const auto from_offset = std::stoi(params.at("from"));
                const auto activation_str = params.count("activation") ? params.at("activation") : "linear";
                
                ActivationType act_type = ActivationType::NONE;
                if (activation_str == "relu") {
                    act_type = ActivationType::RELU;
                } else if (activation_str == "leaky") {
                    act_type = ActivationType::LEAKY_RELU;
                }
                
                int from_cfg_idx = static_cast<int>(i) + from_offset;
                int target_built_idx = static_cast<int>(config_to_layer_index.at(from_cfg_idx));

                if (verbose) {
                    std::cout << " (From: " << from_offset << " [idx: " << target_built_idx << "], Act: " << activation_str << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Shortcut>(target_built_idx, act_type));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    layer_output_tracker.back().m_height,
                    layer_output_tracker.back().m_width,
                    layer_output_tracker.back().m_channels,
                    mem_order,
                    layer_logical_shape_tracker.back());

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "avgpool") {
                int size_h = params.count("size_h") ? std::stoi(params.at("size_h")) : (params.count("size") ? std::stoi(params.at("size")) : -1);
                int size_w = params.count("size_w") ? std::stoi(params.at("size_w")) : (params.count("size") ? std::stoi(params.at("size")) : -1);
                int stride_y = params.count("stride_y") ? std::stoi(params.at("stride_y")) : (params.count("stride") ? std::stoi(params.at("stride")) : 1);
                int stride_x = params.count("stride_x") ? std::stoi(params.at("stride_x")) : (params.count("stride") ? std::stoi(params.at("stride")) : 1);

                if (verbose) {
                    if (size_h == -1) {
                        std::cout << "  AvgPool: Global Average Pooling" << std::endl;
                    } else {
                        std::cout << "  AvgPool: Size " << size_h << "x" << size_w << ", Stride " << stride_y << "x" << stride_x << std::endl;
                    }
                }

                layers.push_back(std::make_unique<DC_CNNLayer_AvgPool2D>(size_h, size_w, stride_y, stride_x));

                int out_h = (size_h == -1) ? 1 : (layer_output_tracker.back().m_height - size_h) / stride_y + 1;
                int out_w = (size_w == -1) ? 1 : (layer_output_tracker.back().m_width - size_w) / stride_x + 1;

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    current_in_channels,
                    mem_order,
                    hwc_to_shape(out_h, out_w, current_in_channels));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "l2norm") {
                if (verbose) {
                    std::cout << "  L2Norm: Normalizing across channels" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_L2Norm>());

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    layer_output_tracker.back().m_height,
                    layer_output_tracker.back().m_width,
                    layer_output_tracker.back().m_channels,
                    mem_order,
                    layer_logical_shape_tracker.back());

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "upsample") {
                const auto stride = std::stoi(params.at("stride"));

                if (verbose) {
                    std::cout << " (Stride: " << stride << ")" << std::endl;
                }

                // Create upsample layer
                auto upsample = std::make_unique<UpsampleT>(stride);
                layers.push_back(std::move(upsample));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    stride * layer_output_tracker.back().m_height,
                    stride * layer_output_tracker.back().m_width,
                    layer_output_tracker.back().m_channels,
                    mem_order,
                    hwc_to_shape(
                        stride * layer_output_tracker.back().m_height,
                        stride * layer_output_tracker.back().m_width,
                        layer_output_tracker.back().m_channels));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "yolo") {
                auto yolo_layer = create_yolo_layer(layer_config.params, i, verbose);

                layers.push_back(std::move(yolo_layer));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    layer_output_tracker.back().m_height,
                    layer_output_tracker.back().m_width,
                    1,
                    mem_order,
                    hwc_to_shape(layer_output_tracker.back().m_height, layer_output_tracker.back().m_width, 1));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "reshape") {
                if (!params.count("shape")) {
                    throw std::runtime_error("Reshape layer missing required 'shape' parameter");
                }

                const auto target_shape = parse_int_list(params.at("shape"), "Reshape layer 'shape'");

                if (verbose) {
                    std::cout << " (Shape: " << params.at("shape") << ")" << std::endl;
                }

                const auto& input_tensor = layer_output_tracker.back();
                const auto input_logical = layer_logical_shape_tracker.back();
                const auto resolved_shape = resolve_shape_with_negative_dim(
                    target_shape,
                    tensor_element_count(input_tensor));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                logical_shape_to_tensor_dims(resolved_shape, out_h, out_w, out_c);

                layers.push_back(std::make_unique<DC_CNNLayer_Reshape>(input_logical, target_shape));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    resolved_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "transpose") {
                if (!params.count("perm")) {
                    throw std::runtime_error("Transpose layer missing required 'perm' parameter");
                }

                const auto perm = parse_int_list(params.at("perm"), "Transpose layer 'perm'");
                const auto& input_tensor = layer_output_tracker.back();
                const auto input_shape = resolve_transpose_input_shape(
                    input_tensor,
                    perm,
                    layer_logical_shape_tracker);

                if (verbose) {
                    std::cout << " (Perm: " << params.at("perm") << ")" << std::endl;
                }

                const auto output_shape = apply_transpose_perm(input_shape, perm);

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                layers.push_back(std::make_unique<DC_CNNLayer_Transpose>(perm, input_shape));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "concat") {
                if (!params.count("layers")) {
                    throw std::runtime_error("Concat layer missing required 'layers' parameter");
                }
                if (!params.count("axis")) {
                    throw std::runtime_error("Concat layer missing required 'axis' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "Concat layer 'layers'");
                const auto axis = std::stoi(params.at("axis"));
                const auto built_layer_count = layers.size();

                std::vector<std::vector<int>> input_shapes;
                if (params.count("operand_shape")) {
                    input_shapes.push_back(parse_int_list(params.at("operand_shape"), "Concat layer 'operand_shape'"));
                }

                for (const int relative_index : relative_indices) {
                    input_shapes.push_back(logical_shape_for_relative_output(
                        relative_index,
                        built_layer_count,
                        layer_logical_shape_tracker));
                }

                std::vector<int> output_shape;
                if (params.count("output_shape")) {
                    output_shape = parse_int_list(params.at("output_shape"), "Concat layer 'output_shape'");
                }

                output_shape = compute_concat_output_shape(input_shapes, axis);

                if (verbose) {
                    std::cout << " (Layers: " << params.at("layers")
                        << ", Axis: " << axis;
                    if (params.count("operand_shape")) {
                        std::cout << ", Operand shape: " << params.at("operand_shape");
                    }
                    std::cout << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Concat>(
                    relative_indices,
                    axis,
                    output_shape));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "add") {
                if (!params.count("layers")) {
                    throw std::runtime_error("Add layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "Add layer 'layers'");
                const auto built_layer_count = layers.size();

                const auto output_shape = logical_shape_for_relative_output(
                    relative_indices.front(),
                    built_layer_count,
                    layer_logical_shape_tracker);

                for (size_t input_idx = 1; input_idx < relative_indices.size(); ++input_idx) {
                    const auto addend_shape = logical_shape_for_relative_output(
                        relative_indices[input_idx],
                        built_layer_count,
                        layer_logical_shape_tracker);

                    if (addend_shape != output_shape) {
                        throw std::runtime_error("Add layer inputs must have matching logical shapes");
                    }
                }

                if (verbose) {
                    std::cout << " (Layers: " << params.at("layers");
                    if (params.count("operand_shape")) {
                        std::cout << ", Operand shape: " << params.at("operand_shape");
                    }
                    std::cout << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Add>(relative_indices));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                logical_shape_to_tensor_dims(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "layernorm") {
                if (!params.count("size")) {
                    throw std::runtime_error("LayerNorm layer missing required 'size' parameter");
                }
                if (!params.count("layers")) {
                    throw std::runtime_error("Add layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "Layernorm layer 'layers'");
                const auto normalized_size = std::stoi(params.at("size"));
                const auto epsilon = params.count("epsilon") ? std::stof(params.at("epsilon")) : 1e-5f;
                const auto built_layer_count = layers.size();

                const auto input_logical = logical_shape_for_relative_output(
                    relative_indices[0],
                    built_layer_count,
                    layer_logical_shape_tracker);
                const auto& input_tensor = layer_output_tracker[layer_output_tracker.size() + relative_indices[0]];
                if (tensor_element_count(input_tensor) % normalized_size != 0) {
                    throw std::runtime_error(
                        "LayerNorm size " + std::to_string(normalized_size)
                        + " does not divide input tensor element count "
                        + std::to_string(tensor_element_count(input_tensor)));
                }

                if (verbose) {
                    std::cout << " (Layers: " << params.at("layers")
                        << ", Size: " << normalized_size
                        << ", Epsilon: " << epsilon << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_LayerNorm>(
                    relative_indices[0],
                    normalized_size,
                    epsilon));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                logical_shape_to_tensor_dims(input_logical, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    input_logical);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "relu") {
                const auto& input_tensor = layer_output_tracker.back();
                const auto input_shape = layer_logical_shape_tracker.back();

                int out_h = input_tensor.m_height;
                int out_w = input_tensor.m_width;
                int out_c = input_tensor.m_channels;
                logical_shape_to_tensor_dims(input_shape, out_h, out_w, out_c);

                if (verbose) {
                    std::cout << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Relu>());

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    input_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "gelu") {
                const auto& input_tensor = layer_output_tracker.back();
                const auto input_shape = layer_logical_shape_tracker.back();

                int out_h = input_tensor.m_height;
                int out_w = input_tensor.m_width;
                int out_c = input_tensor.m_channels;
                logical_shape_to_tensor_dims(input_shape, out_h, out_w, out_c);

                if (verbose) {
                    std::cout << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Gelu>());

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    input_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "slice") {
                if (!params.count("starts")) {
                    throw std::runtime_error("Slice layer missing required 'starts' parameter");
                }
                if (!params.count("ends")) {
                    throw std::runtime_error("Slice layer missing required 'ends' parameter");
                }

                const auto starts = parse_int_list(params.at("starts"), "Slice layer 'starts'");
                const auto ends = parse_slice_int_list(params.at("ends"), "Slice layer 'ends'");
                const auto axes = params.count("axes")
                    ? parse_int_list(params.at("axes"), "Slice layer 'axes'")
                    : std::vector<int>{};
                const auto steps = params.count("steps")
                    ? parse_int_list(params.at("steps"), "Slice layer 'steps'")
                    : std::vector<int>{};

                if (starts.size() != 1 || ends.size() != 1) {
                    throw std::runtime_error("Slice layer supports a single axis only");
                }
                if (!axes.empty() && axes.size() != 1) {
                    throw std::runtime_error("Slice layer supports a single axis only");
                }
                if (!steps.empty() && (steps.size() != 1 || steps[0] != 1)) {
                    throw std::runtime_error("Slice layer supports step=1 only");
                }

                const int axis = axes.empty() ? 0 : axes[0];
                const int start = starts[0];
                const int end = ends[0];

                const auto input_shape = layer_logical_shape_tracker.back();
                const auto output_shape = compute_slice_output_shape(input_shape, axis, start, end);

                if (verbose) {
                    std::cout << " (Axis: " << axis
                        << ", Start: " << start
                        << ", End: " << params.at("ends")
                        << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Slice>(
                    input_shape,
                    axis,
                    start,
                    end));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "resize") {
                const auto input_shape = layer_logical_shape_tracker.back();

                const auto coordinate_mode = params.count("coordinate_transformation_mode")
                    ? params.at("coordinate_transformation_mode")
                    : "align_corners";

                std::vector<int> output_shape;
                if (params.count("size")) {
                    output_shape = parse_int_list(params.at("size"), "Resize layer 'size'");
                }
                else if (params.count("scales")) {
                    std::vector<float> scales;
                    if (params.at("scales") == "dynamic") {
                        if (!params.count("operand_scales")) {
                            throw std::runtime_error(
                                "Resize layer with scales=dynamic requires 'operand_scales' parameter");
                        }
                        scales = parse_float_list(params.at("operand_scales"), "Resize layer 'operand_scales'");
                    }
                    else {
                        scales = parse_float_list(params.at("scales"), "Resize layer 'scales'");
                    }
                    output_shape = compute_resize_output_shape_from_scales(input_shape, scales);
                }
                else {
                    throw std::runtime_error("Resize layer missing required 'size' or 'scales' parameter");
                }

                if (verbose) {
                    std::cout << " (Coordinate mode: " << coordinate_mode;
                    if (params.count("size")) {
                        std::cout << ", Size: " << params.at("size");
                    }
                    if (params.count("scales")) {
                        std::cout << ", Scales: " << params.at("scales");
                    }
                    std::cout << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Resize>(
                    output_shape,
                    coordinate_mode));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                logical_shape_to_tensor_dims(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "gemm") {
                if (!params.count("in_features") || !params.count("out_features")) {
                    throw std::runtime_error("Gemm layer missing required 'in_features' or 'out_features' parameter");
                }

                const auto in_features = std::stoi(params.at("in_features"));
                const auto out_features = std::stoi(params.at("out_features"));
                const auto use_bias = params.count("bias") ? params.at("bias") == "1" : true;

                const auto& input_tensor = layer_output_tracker.back();
                const auto [rows, input_cols] = tensor_matrix_dims(input_tensor);
                if (input_cols != in_features) {
                    throw std::runtime_error(
                        "Gemm in_features " + std::to_string(in_features)
                        + " does not match input feature dimension " + std::to_string(input_cols));
                }

                if (verbose) {
                    std::cout << " (In: " << in_features
                        << ", Out: " << out_features
                        << ", Bias: " << (use_bias ? "yes" : "no") << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Gemm>(in_features, out_features, use_bias));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    rows,
                    out_features,
                    1,
                    mem_order,
                    hwc_to_shape(rows, out_features, 1));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "gather") {
                if (!params.count("axis")) {
                    throw std::runtime_error("Gather layer missing required 'axis' parameter");
                }
                if (!params.count("indices")) {
                    throw std::runtime_error("Gather layer missing required 'indices' parameter");
                }
                if (!params.count("layers")) {
                    throw std::runtime_error("Add layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "Gather layer 'layers'");
                const auto axis = std::stoi(params.at("axis"));
                const auto indices = parse_int_list(params.at("indices"), "Gather layer 'indices'");
                const auto input_shape = layer_logical_shape_tracker[layer_logical_shape_tracker.size() + relative_indices[0]];
                const auto output_shape = compute_gather_output_shape(input_shape, axis, indices);

                if (verbose) {
                    std::cout << " (Axis: " << axis
                        << ", Indices: " << params.at("indices") << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Gather>(axis, input_shape, indices, relative_indices));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "mul") {
                if (!params.count("layers")) {
                    throw std::runtime_error("Mul layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "Mul layer 'layers'");
                const auto built_layer_count = layers.size();
                std::vector<int> output_shape;

                if (relative_indices.size() != 1) {
                    throw std::runtime_error(
                        "Mul layer requires exactly one 'layers' entry (scalar factor or loaded operand)");
                }

                if (params.count("operand_shape")) {
                    output_shape = logical_shape_for_relative_output(
                        relative_indices.front(),
                        built_layer_count,
                        layer_logical_shape_tracker);

                    if (verbose) {
                        std::cout << " (Layers: " << params.at("layers")
                            << ", Operand shape: " << params.at("operand_shape") << ")" << std::endl;
                    }

                    layers.push_back(std::make_unique<DC_CNNLayer_Mul>(relative_indices.front()));
                }
                else if (!params.count("factor")) {
                    throw std::runtime_error(
                        "Mul layer with a single 'layers' entry requires 'factor', 'const', or 'operand_shape'");
                }
                else {
                    output_shape = layer_logical_shape_tracker.back();
                    const auto& factor_str = params.at("factor");
                    const auto scalar_factor = (factor_str == "dynamic")
                        ? 1.0f
                        : std::stof(factor_str);

                    if (verbose) {
                        std::cout << " (Layers: " << params.at("layers")
                            << ", Factor: " << factor_str << ")" << std::endl;
                    }

                    layers.push_back(std::make_unique<DC_CNNLayer_Mul>(scalar_factor));
                }

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "matmul") {
                if (!params.count("layers")) {
                    throw std::runtime_error("MatMul layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "MatMul layer 'layers'");
                if (relative_indices.size() != 2) {
                    throw std::runtime_error("MatMul layer requires exactly two 'layers' entries");
                }

                const auto lhs_index = relative_indices[0];
                const auto rhs_index = relative_indices[1];
                const auto built_layer_count = layers.size();

                auto lhs_shape = params.count("lhs_shape")
                    ? parse_int_list(params.at("lhs_shape"), "MatMul layer 'lhs_shape'")
                    : logical_shape_for_relative_output(lhs_index, built_layer_count, layer_logical_shape_tracker);

                auto rhs_shape = params.count("rhs_shape")
                    ? parse_int_list(params.at("rhs_shape"), "MatMul layer 'rhs_shape'")
                    : logical_shape_for_relative_output(rhs_index, built_layer_count, layer_logical_shape_tracker);

                const auto output_shape = compute_matmul_output_shape(lhs_shape, rhs_shape);
                const bool use_batched_shapes = lhs_shape.size() == 4 && rhs_shape.size() == 4;

                if (verbose) {
                    std::cout << " (Layers: " << params.at("layers") << ")" << std::endl;
                }

                if (use_batched_shapes) {
                    layers.push_back(std::make_unique<DC_CNNLayer_MatMul>(
                        lhs_index,
                        rhs_index,
                        std::move(lhs_shape),
                        std::move(rhs_shape)));
                }
                else {
                    layers.push_back(std::make_unique<DC_CNNLayer_MatMul>(lhs_index, rhs_index));
                }

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(output_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    output_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "flatten") {
                // Create a flatten layer
                if (verbose) {
                    std::cout << "  Flatten: Converting 3D to 1D" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_Flatten>());

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    layer_output_tracker.back().m_height,
                    layer_output_tracker.back().m_width,
                    layer_output_tracker.back().m_channels,
                    mem_order,
                    layer_logical_shape_tracker.back());

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "dense") {
                auto [dense_layer, output_units] = create_dense_layer(params, current_in_channels, verbose);

                layers.push_back(std::move(dense_layer));

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    1,
                    1,
                    output_units,
                    mem_order,
                    hwc_to_shape(1, 1, output_units));

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "skiplayernorm") {
                if (!params.count("layers")) {
                    throw std::runtime_error("SkipLayerNorm layer missing required 'layers' parameter");
                }

                const auto relative_indices = parse_int_list(params.at("layers"), "SkipLayerNorm layer 'layers'");
                if (relative_indices.size() != 2) {
                    throw std::runtime_error("SkipLayerNorm layer requires exactly two 'layers' entries");
                }

                const auto skip_index = relative_indices[0];
                const auto input_index = relative_indices[1];
                const auto built_layer_count = layers.size();

                const auto skip_shape = logical_shape_for_relative_output(
                    skip_index,
                    built_layer_count,
                    layer_logical_shape_tracker);
                const auto input_shape = logical_shape_for_relative_output(
                    input_index,
                    built_layer_count,
                    layer_logical_shape_tracker);

                if (skip_shape != input_shape) {
                    throw std::runtime_error("SkipLayerNorm inputs must have matching logical shapes");
                }

                if (verbose) {
                    std::cout << " (Layers: " << params.at("layers") << ")" << std::endl;
                }

                layers.push_back(std::make_unique<DC_CNNLayer_SkipLayerNorm>(
                    skip_index,
                    input_index));

                int out_h = 0;
                int out_w = 0;
                int out_c = 0;
                shape_to_hwc(skip_shape, out_h, out_w, out_c);

                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    out_h,
                    out_w,
                    out_c,
                    mem_order,
                    skip_shape);

                config_to_layer_index[i] = layers.size() - 1;
            }
            else if (type == "softmax") {
                if (params.count("axis")) {
                    const auto axis = std::stoi(params.at("axis"));
                    const auto& input_tensor = layer_output_tracker.back();
                    const auto input_shape = layer_logical_shape_tracker.back();

                    int normalized_axis = axis;
                    normalize_axis(normalized_axis, static_cast<int>(input_shape.size()));
                    if (normalized_axis != static_cast<int>(input_shape.size()) - 1) {
                        throw std::runtime_error("SoftmaxND supports last-axis softmax only");
                    }

                    if (verbose) {
                        std::cout << " (Axis: " << axis << " -> last)" << std::endl;
                    }

                    layers.push_back(std::make_unique<DC_CNNLayer_SoftmaxND>(axis, input_shape));

                    append_layer_output<kShapeOnlyTracker>(
                        layer_output_tracker,
                        layer_logical_shape_tracker,
                        input_tensor.m_height,
                        input_tensor.m_width,
                        input_tensor.m_channels,
                        mem_order,
                        input_shape);
                }
                else {
                    if (verbose) {
                        std::cout << "  Softmax: Normalizing outputs to probabilities" << std::endl;
                    }

                    layers.push_back(std::make_unique<DC_CNNLayer_Softmax>());

                    append_layer_output<kShapeOnlyTracker>(
                        layer_output_tracker,
                        layer_logical_shape_tracker,
                        1,
                        1,
                        current_in_channels,
                        mem_order,
                        hwc_to_shape(1, 1, current_in_channels));
                }

                config_to_layer_index[i] = layers.size() - 1;
            }
            else {
                std::cerr << "\nWarning: Unsupported layer type encountered: [" << type << "]. Skipping." << std::endl;
                append_layer_output<kShapeOnlyTracker>(
                    layer_output_tracker,
                    layer_logical_shape_tracker,
                    1,
                    1,
                    current_in_channels,
                    mem_order,
                    hwc_to_shape(1, 1, current_in_channels));
            }
            // Assign generic parameters
            if (!layers.empty()) {
                auto& current_layer = layers.back();
                if (params.count("operand_shape")) {
                    current_layer->set_operand_shape(parse_int_list(params.at("operand_shape"), "Layer 'operand_shape'"));
                }
            }
        }
        catch (const std::exception& e) {
            std::cerr << "\nError processing layer index " << i
                << " (Type: [" << type << "]): " << e.what() << std::endl;
            throw;
        }
    }
    DC_CNN_LOG(
        "CNN: topology built — %u runtime layer(s)\r\n",
        static_cast<unsigned>(layers.size()));

    if (verbose) {
        std::cout << "Network building complete. Total layers created: " << layers.size() << std::endl;
    }

    if constexpr (kShapeOnlyTracker) {
        if (!weights_from_rom) {
            throw std::runtime_error("CPU embedded build requires ROM weights buffer");
        }
        if (weights_format != WeightsFormat::YOLO) {
            throw std::runtime_error("CPU embedded build supports YOLO weights only");
        }
        DC_CNN_LOG("CNN: loading yolov4-tiny.weights from ROM (CPU)...\r\n");
        load_yolo_weights_from_memory_cpu<ConvT>(
            weights_data, weights_size, layers, mem_order, verbose);
        DC_CNN_LOG("CNN: ROM weights load finished\r\n");
    }
    else if (weights_from_rom) {
        DC_CNN_LOG("CNN: loading yolov4-tiny.weights from ROM...\r\n");
        load_weights_from_memory<ConvT>(
            *owas_top_level,
            layer_output_tracker,
            weights_format,
            mem_order,
            weights_data,
            weights_size,
            layers,
            verbose);
        DC_CNN_LOG("CNN: ROM weights load finished\r\n");
    }
    else {
        owas_top_level->EnsureLayerMemSeekCapacity(layers.size());
        load_weights<ConvT>(
            *owas_top_level, layer_output_tracker, weights_format, mem_order, weights_file, layers, verbose);
    }

    const auto test_data_path = weights_from_rom ? std::string()
                                                : determine_test_data_path(
                                                      config_path_hint.empty() ? weights_file : config_path_hint);

    for (size_t i = 0; i < layers.size(); i++) {
        layers[i]->set_layer_id(i);
        layers[i]->set_layer_name("layer_" + std::to_string(i) + "_" + layerTypeToString(layers[i]->get_layer_type()));
        layers[i]->set_dump_directory(test_data_path);
        if (weights_from_rom) {
            layers[i]->set_dump_enabled(false);
        }
    }

    return layers;
}

} /* anonymous namespace */

template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_net_config(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const DC_NetConfig& net_conf,
    const std::string& weights_file,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    bool verbose,
    const std::string& config_path_hint) {
    return build_cnn_layers_from_net_config_impl<ConvT, MaxPoolT, RouteT, UpsampleT, false>(
        &owas_top_level,
        net_conf,
        weights_file,
        weights_data,
        weights_size,
        weights_format,
        mem_order,
        verbose,
        config_path_hint);
}

template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_net_config_cpu(
    const DC_NetConfig& net_conf,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    bool verbose,
    const std::string& config_path_hint) {
    return build_cnn_layers_from_net_config_impl<ConvT, MaxPoolT, RouteT, UpsampleT, true>(
        nullptr,
        net_conf,
        std::string(),
        weights_data,
        weights_size,
        weights_format,
        mem_order,
        verbose,
        config_path_hint);
}

template<typename ConvT, typename MaxPoolT, typename RouteT, typename UpsampleT>
std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_config(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::string& config_file,
    const std::string& weights_file,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    bool verbose) {
    const auto net_conf = parse_network_config(config_file);
    return build_cnn_layers_from_net_config<ConvT, MaxPoolT, RouteT, UpsampleT>(
        owas_top_level,
        net_conf,
        weights_file,
        nullptr,
        0U,
        weights_format,
        mem_order,
        verbose,
        config_file);
}

template std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_net_config<
    DC_FifoCommandBuilder_CNNLayer_Conv2D,
    DC_FifoCommandBuilder_CNNLayer_MaxPool2D,
    DC_FifoCommandBuilder_CNNLayer_Route,
    DC_FifoCommandBuilder_CNNLayer_Upsample>(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const DC_NetConfig& net_conf,
        const std::string& weights_file,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose,
        const std::string& config_path_hint);

template std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_net_config<
    DC_CNNLayer_Conv2D,
    DC_CNNLayer_MaxPool2D,
    DC_CNNLayer_Route,
    DC_CNNLayer_Upsample>(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const DC_NetConfig& net_conf,
        const std::string& weights_file,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose,
        const std::string& config_path_hint);

template std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_config<
    DC_FifoCommandBuilder_CNNLayer_Conv2D,
    DC_FifoCommandBuilder_CNNLayer_MaxPool2D,
    DC_FifoCommandBuilder_CNNLayer_Route,
    DC_FifoCommandBuilder_CNNLayer_Upsample>(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& config_file,
        const std::string& weights_file,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose);

template std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_config<
    DC_CNNLayer_Conv2D,
    DC_CNNLayer_MaxPool2D,
    DC_CNNLayer_Route,
    DC_CNNLayer_Upsample>(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& config_file,
        const std::string& weights_file,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose);

template std::vector<std::unique_ptr<DC_Layer>> DC_ConvNet::build_cnn_layers_from_net_config_cpu<
    DC_CNNLayer_Conv2D,
    DC_CNNLayer_MaxPool2D,
    DC_CNNLayer_Route,
    DC_CNNLayer_Upsample>(
        const DC_NetConfig& net_conf,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        bool verbose,
        const std::string& config_path_hint);
