#include "DC_yolo_utils.h"
#include "DC_baremetal_log.h"
#include "DC_config_parser.h"
#include "DC_image_utils.h"

#include <iomanip>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <numeric>

namespace DC_ConvNet {

std::vector<std::string> DC_YoloUtils::load_coco_class_names(const std::string& filename) {
    std::vector<std::string> class_names;
    std::ifstream file(filename);
    if (!file.is_open()) {
        throw std::runtime_error("Failed to open class names file: " + filename);
    }

    std::string line;
    while (std::getline(file, line)) {
        if (!line.empty()) {
            class_names.push_back(line);
        }
    }

    if (class_names.size() != 80) {
        throw std::runtime_error("Expected 80 COCO classes, got " + std::to_string(class_names.size()));
    }

    return class_names;
}

std::map<std::string, std::vector<float>> DC_YoloUtils::load_yolo_weights(
    const std::string& weights_file) {
    
    std::map<std::string, std::vector<float>> weights;
    std::ifstream file(weights_file, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Failed to open weights file: " + weights_file);
    }

    // Read header
    int32_t header[5];
    file.read(reinterpret_cast<char*>(header), sizeof(header));
    
    // Read weights for each layer
    while (file.peek() != EOF) {
        // Read layer name
        int32_t name_length;
        file.read(reinterpret_cast<char*>(&name_length), sizeof(name_length));
        if (name_length <= 0 || name_length > 1000) break; // Sanity check
        
        std::string layer_name(name_length, '\0');
        file.read(&layer_name[0], name_length);
        
        // Read weights
        int32_t num_weights;
        file.read(reinterpret_cast<char*>(&num_weights), sizeof(num_weights));
        
        std::vector<float> layer_weights(num_weights);
        file.read(reinterpret_cast<char*>(layer_weights.data()), num_weights * sizeof(float));
        
        weights[layer_name] = std::move(layer_weights);
    }

    return weights;
}

std::vector<float> DC_YoloUtils::parse_anchors(const std::string& anchor_string) {
    std::vector<float> anchors;
    std::stringstream ss(anchor_string);
    std::string token;

    // Remove all spaces and split by comma
    std::string cleaned;
    std::copy_if(anchor_string.begin(), anchor_string.end(),
        std::back_inserter(cleaned),
        [](char c) { return !std::isspace(c); });

    std::stringstream cleaned_ss(cleaned);
    while (std::getline(cleaned_ss, token, ',')) {
        try {
            float value = std::stof(token);
            anchors.push_back(value);
        }
        catch (const std::exception&) {
            throw std::runtime_error("Failed to parse anchor value: " + token);
        }
    }

    // Validate that we have pairs of numbers
    if (anchors.size() % 2 != 0) {
        throw std::runtime_error("Anchor configuration must contain pairs of numbers");
    }

    return anchors;
}

std::vector<DC_YoloUtils::DC_YoloDetection> DC_YoloUtils::apply_nms(
    const std::vector<DC_YoloDetection>& detections,
    float iou_threshold) {

    std::vector<DC_YoloDetection> result;
    std::vector<bool> suppressed(detections.size(), false);

    // Sort by confidence
    std::vector<size_t> indices(detections.size());
    std::iota(indices.begin(), indices.end(), 0);
    std::sort(indices.begin(), indices.end(),
        [&detections](size_t i1, size_t i2) {
            return detections[i1].confidence > detections[i2].confidence;
        });

    // Apply NMS
    for (size_t i = 0; i < indices.size(); ++i) {
        if (suppressed[indices[i]]) continue;

        result.push_back(detections[indices[i]]);

        for (size_t j = i + 1; j < indices.size(); ++j) {
            if (suppressed[indices[j]]) continue;

            if (calculate_iou(detections[indices[i]], detections[indices[j]]) > iou_threshold) {
                suppressed[indices[j]] = true;
            }
        }
    }

    return result;
}

float DC_YoloUtils::calculate_iou(const DC_YoloDetection& box1, const DC_YoloDetection& box2) {
    // Convert from center format to min/max format
    float box1_x1 = box1.x - box1.width / 2;
    float box1_y1 = box1.y - box1.height / 2;
    float box1_x2 = box1.x + box1.width / 2;
    float box1_y2 = box1.y + box1.height / 2;

    float box2_x1 = box2.x - box2.width / 2;
    float box2_y1 = box2.y - box2.height / 2;
    float box2_x2 = box2.x + box2.width / 2;
    float box2_y2 = box2.y + box2.height / 2;

    // Calculate intersection area
    float x1 = std::max(box1_x1, box2_x1);
    float y1 = std::max(box1_y1, box2_y1);
    float x2 = std::min(box1_x2, box2_x2);
    float y2 = std::min(box1_y2, box2_y2);

    float intersection = std::max(0.0f, x2 - x1) * std::max(0.0f, y2 - y1);

    // Calculate union area
    float box1_area = box1.width * box1.height;
    float box2_area = box2.width * box2.height;
    float union_area = box1_area + box2_area - intersection;

    return intersection / union_area;
}

DC_Tensor DC_ConvNet::DC_YoloUtils::convert_HWC_to_CHW(const DC_Tensor& input) {
    DC_Tensor converted(input.m_height, input.m_width, input.m_channels, MEM_ORDER::CHW);

    // Convert from HWC to CHW format
    for (int h = 0; h < input.m_height; ++h) {
        for (int w = 0; w < input.m_width; ++w) {
            for (int c = 0; c < input.m_channels; ++c) {
                // HWC index: h * width * channels + w * channels + c
                int hwc_index = h * input.m_width * input.m_channels + w * input.m_channels + c;

                // CHW index: c * height * width + h * width + w
                int chw_index = c * input.m_height * input.m_width + h * input.m_width + w;

                converted.m_data[chw_index] = input.m_data[hwc_index];
            }
        }
    }

    return converted;
}

std::vector<DC_ConvNet::DC_YoloUtils::DC_YoloDetection> DC_ConvNet::DC_YoloUtils::processYoloOutputs(
    const std::vector<DC_Tensor>& outputs,
    const DC_NetConfig& net_conf,
    float confidence_threshold,
    float nms_threshold)
{
    std::vector<DC_YoloDetection> all_detections;

    DC_CNN_LOG(
        "CNN NMS: begin (%u YOLO output tensor(s))\r\n",
        static_cast<unsigned>(outputs.size()));

    unsigned yolo_head = 0U;

    // Process each YOLO layer output
    for (size_t i = 0, layer_idx = 0; i < net_conf.layers.size(); ++i) {
        if (net_conf.layers[i].type != "yolo") continue;

        ++yolo_head;

        DC_Tensor yolo_output = (outputs[layer_idx].m_mem_order == MEM_ORDER::CHW)
            ? outputs[layer_idx]
            : convert_HWC_to_CHW(outputs[layer_idx]);

        DC_CNN_LOG(
            "CNN NMS: head %u cfg[%u] feature %dx%dx%d\r\n",
            yolo_head,
            static_cast<unsigned>(i),
            yolo_output.m_height,
            yolo_output.m_width,
            yolo_output.m_channels);

#ifndef TARGET_OS_BAREMETAL
        std::cout << "\nProcessing YOLO layer " << i << ":\n";
        std::cout << "  Feature map size: " << yolo_output.m_height << "x"
            << yolo_output.m_width << "x" << yolo_output.m_channels << "\n";
#endif

        /////////////////////////////////////////////////////////////////
        // Parse anchor masks
        std::vector<int> mask;
        std::string mask_str = net_conf.layers[i].params.at("mask");
        std::stringstream mask_ss(mask_str);
        std::string mask_token;
        while (std::getline(mask_ss, mask_token, ',')) {
            // Trim whitespace
            mask_token.erase(0, mask_token.find_first_not_of(" \t\r\n"));
            mask_token.erase(mask_token.find_last_not_of(" \t\r\n") + 1);
            if (!mask_token.empty()) {
                try {
                    int val = std::stoi(mask_token);
                    mask.push_back(val);
                }
                catch (const std::exception& e) {
                    throw std::runtime_error("Failed to parse mask value '" + mask_token + "': " + e.what());
                }
            }
        }

        const std::vector<float> anchors =
            DC_YoloUtils::parse_anchors(net_conf.layers[i].params.at("anchors"));
        for (int mask_idx : mask) {
            const size_t anchor_idx = static_cast<size_t>(mask_idx) * 2U;
            if (anchor_idx + 1U >= anchors.size()) {
                std::stringstream err;
                err << "Invalid anchor mask index " << mask_idx
                    << " for layer with " << anchors.size() / 2 << " anchor pairs";
                throw std::runtime_error(err.str());
            }
        }

        std::vector<DC_YoloDetection> layer_detections;
        const int num_detections = get_yolo_detections(
            yolo_output,
            net_conf.width,
            net_conf.height,
            net_conf.width,
            net_conf.height,
            confidence_threshold,
            anchors,
            mask,
            layer_detections);

        DC_CNN_LOG(
            "CNN NMS: head %u raw candidates %d (layer vec %u)\r\n",
            yolo_head,
            num_detections,
            static_cast<unsigned>(layer_detections.size()));

#ifndef TARGET_OS_BAREMETAL
        std::cout << "  Found " << num_detections << " detections\n";
#endif

        all_detections.insert(
            all_detections.end(),
            layer_detections.begin(),
            layer_detections.end());

        ++layer_idx;
    }

#ifdef TARGET_OS_BAREMETAL
    constexpr std::size_t kMaxPreNmsCandidates = 4096U;
    if (all_detections.size() > kMaxPreNmsCandidates) {
        DC_CNN_LOG(
            "CNN NMS: capping pre-NMS candidates %u -> %u\r\n",
            static_cast<unsigned>(all_detections.size()),
            static_cast<unsigned>(kMaxPreNmsCandidates));
        std::partial_sort(
            all_detections.begin(),
            all_detections.begin() + static_cast<std::ptrdiff_t>(kMaxPreNmsCandidates),
            all_detections.end(),
            [](const DC_YoloDetection& a, const DC_YoloDetection& b) {
                return a.class_prob > b.class_prob;
            });
        all_detections.resize(kMaxPreNmsCandidates);
    }
#else
    for (const auto& det : all_detections) {
        std::cout << det.class_id << " "
            << std::fixed << std::setprecision(6)
            << det.class_prob << " "
            << det.x << " "
            << det.y << " "
            << det.width << " "
            << det.height << "\n";
    }
#endif

    DC_CNN_LOG(
        "CNN NMS: applying NMS on %u candidates (iou<=%.2f)\r\n",
        static_cast<unsigned>(all_detections.size()),
        nms_threshold);

    const auto final_detections = DC_YoloUtils::apply_nms(all_detections, nms_threshold);

    DC_CNN_LOG(
        "CNN NMS: complete — %u detection(s) after NMS\r\n",
        static_cast<unsigned>(final_detections.size()));

    return final_detections;
}

void DC_YoloUtils::visualize_yolo_output(int input_id, const DC_Tensor& input_image, 
    const std::vector<DC_Tensor>& outputs, const DC_ConvNet::DC_NetConfig& net_conf)
{
    const float confidence_threshold = 0.25f;
    const float nms_threshold = 0.45f;
    
    // Process YOLO outputs to get detections
    const auto final_detections = processYoloOutputs(outputs, net_conf,
        confidence_threshold, nms_threshold);

    // Draw detections on the visualization tensor
    DC_ImageUtils image_utils;

    // Define some colors for different classes (you can extend this)
    const std::vector<std::tuple<float, float, float>> colors = {
        {1.0f, 0.0f, 0.0f},  // Red
        {0.0f, 1.0f, 0.0f},  // Green
        {0.0f, 0.0f, 1.0f},  // Blue
        {1.0f, 1.0f, 0.0f},  // Yellow
        {1.0f, 0.0f, 1.0f},  // Magenta
        {0.0f, 1.0f, 1.0f}   // Cyan
    };
    
    DC_Tensor visualization = input_image;

    // Draw each detection
    for (const auto& det : final_detections) {
        // Get color for this class
        auto color = colors[det.class_id % colors.size()];
        float r = std::get<0>(color);
        float g = std::get<1>(color);
        float b = std::get<2>(color);

        // Draw bounding box
        image_utils.draw_bounding_box(visualization, det.x, det.y, det.width, det.height, r, g, b, 2.0f);
    }

    // Save the visualization
    std::string output_filename = "detections" + std::to_string(input_id) + ".png";
    if (image_utils.save_image_png(output_filename, visualization)) {
        std::cout << "\nSaved detection visualization to " << output_filename << std::endl;
    }
    else {
        std::cerr << "\nFailed to save detection visualization" << std::endl;
    }
}

std::vector<std::string> DC_YoloUtils::split_string(const std::string& str, char delimiter) {
    std::vector<std::string> tokens;
    std::string token;
    std::istringstream tokenStream(str);
    
    while (std::getline(tokenStream, token, delimiter)) {
        if (!token.empty()) {
            tokens.push_back(token);
        }
    }
    
    return tokens;
}

int DC_YoloUtils::parse_int(const std::string& str) {
    try {
        return std::stoi(str);
    } catch (const std::exception&) {
        throw std::runtime_error("Failed to parse int: " + str);
    }
}

DC_YoloUtils::DC_YoloDetection DC_YoloUtils::get_yolo_box(
    const std::vector<float>& predictions,
    const std::vector<float>& anchors,
    int anchor_idx,
    int box_idx,
    int col,
    int row,
    int grid_width,
    int grid_height,
    int net_width,
    int net_height,
    int stride)
{
    DC_YoloDetection det;
    
    // Get anchor dimensions
    float anchor_w = anchors[2 * anchor_idx];
    float anchor_h = anchors[2 * anchor_idx + 1];

    // Get box coordinates
    float x = (col + (predictions[box_idx + 0 * stride])) / grid_width;
    float y = (row + (predictions[box_idx + 1 * stride])) / grid_height;
    float w = std::exp(predictions[box_idx + 2 * stride]) * anchor_w / net_width;
    float h = std::exp(predictions[box_idx + 3 * stride]) * anchor_h / net_height;

    // Set detection box
    det.x = x;
    det.y = y;
    det.width = w;
    det.height = h;

    return det;
}

void DC_YoloUtils::correct_yolo_boxes(
    std::vector<DC_YoloDetection>& dets,
    int img_width,
    int img_height,
    int net_width,
    int net_height,
    bool relative,
    bool letter_box)
{
    float new_w = 0.f;
    float new_h = 0.f;

    if (letter_box) {
        if (((float)net_width / img_width) < ((float)net_height / img_height)) {
            new_w = static_cast<float>(net_width);
            new_h = static_cast<float>(img_height * net_width) / static_cast<float>(img_width);
        }
        else {
            new_h = static_cast<float>(net_height);
            new_w = static_cast<float>(img_width * net_height) / static_cast<float>(img_height);
        }
    }
    else {
        new_w = static_cast<float>(net_width);
        new_h = static_cast<float>(net_height);
    }

    // Calculate the differences and ratios
    float deltaw = net_width - new_w;
    float deltah = net_height - new_h;
    float ratiow = new_w / net_width;
    float ratioh = new_h / net_height;

    for (auto& det : dets) {
        float x = det.x;
        float y = det.y;
        float w = det.width;
        float h = det.height;

        // Apply corrections using the same formula as the original implementation
        x = (x - deltaw / 2.0f / net_width) / ratiow;
        y = (y - deltah / 2.0f / net_height) / ratioh;
        w *= 1.0f / ratiow;
        h *= 1.0f / ratioh;

        if (!relative) {
            x *= img_width;
            w *= img_width;
            y *= img_height;
            h *= img_height;
        }

        det.x = x;
        det.y = y;
        det.width = w;
        det.height = h;
    }
}

int DC_YoloUtils::get_yolo_detections(
    const DC_Tensor& layer_output,
    int img_width,
    int img_height,
    int net_width,
    int net_height,
    float confidence_threshold,
    const std::vector<float>& anchors,
    const std::vector<int>& mask,
    std::vector<DC_YoloDetection>& detections,
    bool relative,
    bool letter_box)
{
    int count = 0;
    const int grid_width = layer_output.m_width;
    const int grid_height = layer_output.m_height;
    const auto num_anchors = mask.size();
    const int num_classes = (layer_output.m_channels / static_cast<int>(num_anchors)) - 5;
    const std::vector<float>& predictions = layer_output.m_data;

    // Process each grid cell
    for (int i = 0; i < grid_width * grid_height; ++i) {
        int row = i / grid_width;
        int col = i % grid_width;

        // Process each anchor
        for (auto n = 0u; n < num_anchors; ++n) {
            // Get objectness score
            int obj_index = entry_index(0,  // batch
                                      n * grid_width * grid_height + i,    // location
                                      4,    // entry (objectness)
                                      grid_width,
                                      grid_height,
                                      static_cast<int>(num_anchors),
                                      num_classes);
            float objectness = predictions[obj_index];

            if (objectness > confidence_threshold) {
                // Get box coordinates
                DC_YoloDetection det;
                
                int box_index = entry_index(0,  // batch
                                            n * grid_width * grid_height + i,    // location
                                            0,    // entry (objectness)
                                            grid_width,
                                            grid_height,
                                            static_cast<int>(num_anchors),
                                            num_classes);

                det = get_yolo_box(
                    predictions,
                    anchors,
                    mask[n],
                    box_index,  // box_idx is now location
                    col,
                    row,
                    grid_width,
                    grid_height,
                    net_width,
                    net_height,
                    grid_width * grid_height
                );

                det.confidence = objectness;
                det.class_id = -1;
                det.class_prob = 0;

                // Get class probabilities
                for (int j = 0; j < num_classes; ++j) {
                    int class_index = entry_index(0,    // batch
                                                n * grid_width * grid_height + i,      // location
                                                5 + j,  // entry (class probabilities start after box coords and objectness)
                                                grid_width,
                                                grid_height,
                                                static_cast<int>(num_anchors),
                                                num_classes);
                    float prob = objectness * predictions[class_index];
                    
                    if (prob > det.class_prob) {
                        det.class_prob = prob;
                        det.class_id = j;
                    }
                }

                if (det.class_prob > confidence_threshold) {
                    detections.push_back(det);
                }

                count++;
            }
        }
    }

    // Correct boxes for image dimensions
    correct_yolo_boxes(detections, img_width, img_height, net_width, net_height, 
                      relative, letter_box);

    return count;
}

} // namespace DC_ConvNet 
