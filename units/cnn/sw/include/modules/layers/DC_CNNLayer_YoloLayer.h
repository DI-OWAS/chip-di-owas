/******************************************************************************
 * @file    DC_CNNLayer_YoloLayer.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   YOLO detection layer implementation for neural networks
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

#include "DC_layer.h"

#include <stdexcept>

namespace DC_ConvNet {
 
    struct LayerStats;

    /**
     * @brief YOLO Detection layer implementation
     * 
     * Implements the YOLO detection layer used in YOLOv3 and YOLOv4 architectures.
     * Processes feature maps to extract bounding box predictions.
     */
    class DC_CNNLayer_YoloLayer final: public DC_Layer {
    public:
        /**
         * @brief Constructs a YOLO detection layer
         * 
         * @param num_anchors Number of anchor boxes for this layer
         * @param num_classes Number of object classes
         * @param anchors Vector of anchor box dimensions (width and height pairs)
         * @param scale_x_y Scale factor for x and y coordinates (YOLOv4 improvement)
         */
        explicit DC_CNNLayer_YoloLayer(int num_anchors, int num_classes, const std::vector<float>& anchors, float scale_x_y);

        /**
         * @brief Processes the input tensor through the YOLO detection layer
         * 
         * @param input Input tensor containing feature maps
         * @return DC_Tensor Output tensor with transformed detection data
         */
        DC_Tensor forward(const DC_Tensor& input) const override;
        
        /**
         * @brief Forward propagation with multiple inputs (not supported)
         * 
         * This method is not supported for the YOLO detection layer as it only accepts
         * a single input tensor.
         * 
         * @param layer_outputs Vector of input tensors
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(layer_outputs) instead.)");
        }

    private:
        // Layer configuration
        int m_num_anchors;                // Number of anchor boxes for this layer
        int m_num_classes;                // Number of object classes to detect
        std::vector<float> m_anchors;     // Vector of anchor box dimensions (width and height pairs)
        float m_scale_x_y;                // Scale factor for x and y coordinates (YOLOv4 improvement)
        float m_beta;                     // Offset value for coordinate scaling

        /**
         * @brief Calculates the index for accessing values in the YOLO output tensor
         * 
         * @param location Location index in the grid
         * @param entry Entry type (0-3: box coords, 4: objectness, 5+: class scores)
         * @param w Grid width
         * @param h Grid height
         * @return int Index into the data array
         */
        int entry_index(int location, int entry, int w, int h) const {
            int n = location / (w * h);
            int loc = location % (w * h);
            return n * w * h * (4 + m_num_classes + 1) +
                entry * w * h + loc;
        }

        /**
         * @brief Applies activation function to array elements
         * 
         * Applies the layer's activation function to a range of elements in a data array.
         *
         * @param data Vector containing the data to activate
         * @param start_idx Starting index for activation
         * @param n Number of elements to activate
         */
        static void activate_array(std::vector<float>& data, int start_idx, int n, LayerStats& stats);

        /**
         * @brief Performs scale and add operation on array elements
         * 
         * Computes: data[i] = data[i]*alpha + beta for a range of elements.
         * Similar to the BLAS saxpy operation but operating on a subset of vector elements.
         *
         * @param data Vector to modify
         * @param start_idx Starting index for operation
         * @param n Number of elements to process
         * @param alpha Scaling factor for original values
         * @param beta Value to add after scaling
         * @param incx Increment step for index (typically 1)
         */
        static void scale_add_cpu(std::vector<float>& data, int start_idx, int n, 
                                 float alpha, float beta, int incx, LayerStats& stats);
    };

} // namespace DC_ConvNet 
