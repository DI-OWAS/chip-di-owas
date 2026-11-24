/******************************************************************************
 * @file    DC_yolo_utils.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Utility functions for YOLO object detection
 * @version 1.0.0
 * @date    2025-04-07
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (c) 2025 DC Vision Systems GmbH
 ******************************************************************************/

#pragma once

#include "DC_tensor.h"
#include "DC_config_parser.h"

#include <vector>
#include <string>
#include <map>

namespace DC_ConvNet {

/**
 * @brief Utility class for YOLO operations
 * 
 * Provides functions for loading YOLO weights, parsing configurations,
 * processing detections, and performing post-processing operations.
 */
class DC_YoloUtils final{
public:
    /**
     * @brief Structure to hold YOLO detection results
     */
    struct DC_YoloDetection {
        float x;              // Center x coordinate (normalized)
        float y;              // Center y coordinate (normalized)
        float width;          // Width of bounding box (normalized)
        float height;         // Height of bounding box (normalized)
        float confidence;     // Object confidence score
        int class_id;         // Predicted class ID
        float class_prob;     // Class probability
        std::string class_name; // Class name (optional)

        // Constructor
        DC_YoloDetection(float x_ = 0.0f, float y_ = 0.0f,
            float w = 0.0f, float h = 0.0f,
            float conf = 0.0f, int id = -1,
            float prob = 0.0f,
            const std::string& name = "")
            : x(x_), y(y_), width(w), height(h),
            confidence(conf), class_id(id), class_prob(prob),
            class_name(name) {
        }
    };

    // Class name loading
    /**
     * @brief Loads class names from a file in COCO format
     * 
     * @param filename Path to the file containing class names (one per line)
     * @return std::vector<std::string> Vector of class names
     */
    static std::vector<std::string> load_coco_class_names(const std::string& filename = "data/yolo/coco.names");
    
    // YOLO weight loading
    /**
     * @brief Loads YOLO weights from a binary weights file
     * 
     * @param weights_file Path to the binary weights file
     * @return std::map<std::string, std::vector<float>> Map of layer names to weight vectors
     */
    static std::map<std::string, std::vector<float>> load_yolo_weights(
        const std::string& weights_file);
    
    // Anchor box processing
    /**
     * @brief Parses anchor box dimensions from a string
     * 
     * @param anchor_string String containing comma-separated anchor dimensions
     * @return std::vector<float> Vector of anchor dimensions
     */
    static std::vector<float> parse_anchors(const std::string& anchor_string);
    
    // Detection processing
    /**
     * @brief Extracts YOLO detections from layer output tensor
     * 
     * @param layer_output Output tensor from YOLO layer
     * @param img_width Original image width
     * @param img_height Original image height
     * @param net_width Network input width
     * @param net_height Network input height
     * @param confidence_threshold Minimum confidence threshold for detections
     * @param anchors Vector of anchor box dimensions
     * @param mask Vector of anchor indices to use
     * @param detections Output vector to store detected objects
     * @param relative Whether coordinates are relative (0-1) or absolute
     * @param letter_box Whether letter box padding was used
     * @return int Number of detections found
     */
    static int get_yolo_detections(
        const DC_Tensor& layer_output,
        int img_width,
        int img_height,
        int net_width,
        int net_height,
        float confidence_threshold,
        const std::vector<float>& anchors,
        const std::vector<int>& mask,
        std::vector<DC_YoloDetection>& detections,
        bool relative = true,
        bool letter_box = false);

    /**
     * @brief Extracts a single bounding box from YOLO predictions
     * 
     * @param predictions Raw prediction values from YOLO layer
     * @param anchors Anchor box dimensions
     * @param anchor_idx Index of the anchor box
     * @param box_idx Index of the bounding box within the anchor
     * @param col Column position in the grid
     * @param row Row position in the grid
     * @param grid_width Width of the detection grid
     * @param grid_height Height of the detection grid
     * @param net_width Network input width
     * @param net_height Network input height
     * @param stride Stride of the detection layer
     * @return DC_YoloDetection Extracted bounding box with coordinates and confidence
     */
    static DC_YoloDetection get_yolo_box(
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
        int stride);

    /**
     * @brief Corrects YOLO bounding box coordinates for image scaling and letter box padding
     * 
     * @param dets Vector of detections to correct
     * @param img_width Original image width
     * @param img_height Original image height
     * @param net_width Network input width
     * @param net_height Network input height
     * @param relative Whether coordinates are relative (0-1) or absolute
     * @param letter_box Whether letter box padding was used
     */
    static void correct_yolo_boxes(
        std::vector<DC_YoloDetection>& dets,
        int img_width,
        int img_height,
        int net_width,
        int net_height,
        bool relative,
        bool letter_box);
       
    // Helper functions
    // NMS implementation
    /**
     * @brief Applies Non-Maximum Suppression to filter overlapping detections
     * 
     * @param detections Vector of detections to filter
     * @param iou_threshold IoU threshold for considering detections as overlapping
     * @return std::vector<DC_YoloDetection> Filtered detections after NMS
     */
    static std::vector<DC_YoloDetection> apply_nms(
        const std::vector<DC_YoloDetection>& detections,
        float iou_threshold = 0.45f);

    // IOU calculation
    /**
     * @brief Calculates the Intersection over Union (IoU) between two bounding boxes
     * 
     * @param box1 First bounding box
     * @param box2 Second bounding box
     * @return float IoU value between 0.0 and 1.0
     */
    static float calculate_iou(
        const DC_YoloDetection& box1,
        const DC_YoloDetection& box2);

    /**
     * @brief Visualizes YOLO output by drawing bounding boxes on the input image
     * 
     * @param input_id Identifier for the input image
     * @param input_image Original input image tensor
     * @param outputs Vector of YOLO layer output tensors
     * @param net_conf Network configuration containing layer information
     */
    static void visualize_yolo_output(int input_id, const DC_Tensor& input_image, const std::vector<DC_Tensor>& outputs,
        const DC_ConvNet::DC_NetConfig& net_conf);

    /**
     * @brief Process YOLO outputs to extract detections from all YOLO layers
     * 
     * @param outputs Vector of tensors containing YOLO layer outputs
     * @param net_conf Network configuration containing layer information
     * @param confidence_threshold Threshold for filtering detections by confidence
     * @param nms_threshold Threshold for Non-Maximum Suppression
     * @return std::vector<DC_YoloDetection> Vector of final detections after NMS
     */
    static std::vector<DC_YoloDetection> processYoloOutputs(
        const std::vector<DC_Tensor>& outputs,
        const DC_NetConfig& net_conf,
        float confidence_threshold = 0.25f,
        float nms_threshold = 0.45f);

private:
    // Private helper methods

    /**
     * @brief Converts tensor from Height-Width-Channel (HWC) to Channel-Height-Width (CHW) format
     * 
     * @param input Input tensor in HWC format
     * @return DC_Tensor Converted tensor in CHW format
     */
    static DC_ConvNet::DC_Tensor convert_HWC_to_CHW(const DC_ConvNet::DC_Tensor& input);

    /**
     * @brief Splits a string by a delimiter character
     * 
     * @param str String to split
     * @param delimiter Character to split by
     * @return std::vector<std::string> Vector of substrings
     */
    static std::vector<std::string> split_string(const std::string& str, char delimiter);
    
    /**
     * @brief Parses a string to an integer value
     * 
     * @param str String to parse
     * @return int Parsed integer value
     */
    static int parse_int(const std::string& str);
    
    /**
     * @brief Calculates the index for accessing YOLO output tensor entries
     * 
     * @param batch Batch index
     * @param location Location index in the grid
     * @param entry Entry type (0-3: bbox coords, 4: confidence, 5+: class probs)
     * @param grid_width Width of the detection grid
     * @param grid_height Height of the detection grid
     * @param num_anchors Number of anchor boxes
     * @param num_classes Number of object classes
     * @return int Calculated index into the output tensor
     */
    static int entry_index(
        int batch,
        int location,
        int entry,
        int grid_width,
        int grid_height,
        int num_anchors,
        int num_classes)
    {
        int n = location / (grid_width * grid_height);
        int loc = location % (grid_width * grid_height);
        int outputs = grid_width * grid_height * num_anchors * (4 + num_classes + 1);
        return batch * outputs + n * grid_width * grid_height * (4 + num_classes + 1) + entry * grid_width * grid_height + loc;
    }
};

} // namespace DC_ConvNet 
