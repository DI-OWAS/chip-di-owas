/******************************************************************************
 * @file    DC_yolo_detection_layer.cpp
 * @author  Oleksandr Karpenko
 * @brief   YOLO Detection layer implementation for object detection networks
 * @version 1.0.0
 * @date    2024-04-07
 *
 * @copyright Copyright (c) 2024 DC Vision Systems GmbH
 * All rights reserved.
 ******************************************************************************/

#include "DC_CNNLayer_YoloLayer.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>
#include <cmath>

namespace DC_ConvNet {

    DC_CNNLayer_YoloLayer::DC_CNNLayer_YoloLayer(int num_anchors,
        int num_classes,
        const std::vector<float>& anchors,
        float scale_x_y)
        : m_num_anchors(num_anchors)
        , m_num_classes(num_classes)
        , m_anchors(anchors)
        , m_scale_x_y(scale_x_y)
        , m_beta(-0.5f * (scale_x_y - 1.f))
    {
        m_layer_type = Layer_Type::YOLO;
    }

    /**
    * @brief Applies activation function to array elements
    */
    void DC_CNNLayer_YoloLayer::activate_array(
        std::vector<float>& data,
        int start_idx,
        int n,
        LayerStats& stats) {
        for (int i = 0; i < n; ++i) {
            float val = data[start_idx + i];

            val = 1.0f / (1.0f + std::exp(-val));  // Sigmoid activation

            data[start_idx + i] = val;
        }

        stats.record_operation(OperationType::ARITHMETIC_ADD, n);
        stats.record_operation(OperationType::ARITHMETIC_OTHER, n);
        stats.record_operation(OperationType::ARITHMETIC_MUL, n);
        stats.record_operation(OperationType::MEMORY_LOAD, n);
        stats.record_operation(OperationType::MEMORY_STORE, n);
    }

    /**
    * @brief Performs scale and add operation on array elements
    */
    void DC_CNNLayer_YoloLayer::scale_add_cpu(std::vector<float>& data,
        int start_idx,
        int n,
        float alpha,
        float beta,
        int incx,
        LayerStats& stats) {
        for (int i = 0; i < n; ++i) {
            float val = data[start_idx + i * incx];

            val = val * alpha + beta;

            data[start_idx + i * incx] = val;
        }

        stats.record_operation(OperationType::MEMORY_LOAD, n);// Load data[start_idx + i * incx]
        stats.record_operation(OperationType::MEMORY_STORE, n);// Store data[start_idx + i * incx]
        stats.record_operation(OperationType::ARITHMETIC_MUL, n);// Multiplication: val * alpha
        stats.record_operation(OperationType::ARITHMETIC_ADD, n);// Addition: val*alpha + beta
    }


    /**
     * @brief Performs forward propagation through the YOLO layer.
     */
    DC_Tensor DC_CNNLayer_YoloLayer::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);

        output.m_data = input.m_data;

        const auto width = input.m_width;
        const auto height = input.m_height;
        const auto wh = width * height;
        const auto num_xy_entries = 2 * wh;  // Number of x,y coordinate entries across all grid cells
        const auto num_confidence_class_entries = (1 + m_num_classes) * wh;  // Objectness score + class probabilities across grid cells
        const int entries_per_anchor = 4 + m_num_classes + 1;
        const int total_channels = entries_per_anchor * m_num_anchors;

        if (input.m_mem_order == MEM_ORDER::CHW) {
            for (int n = 0; n < m_num_anchors; ++n) {
                // Activate x,y coordinates
                const auto bbox_index = entry_index(n * wh, 0, width, height);
                activate_array(output.m_data, bbox_index, num_xy_entries, stats);

                // Activate objectness and class probabilities
                const auto obj_index = entry_index(n * wh, 4, width, height);
                activate_array(output.m_data, obj_index, num_confidence_class_entries, stats);

                // Scale and shift x,y
                scale_add_cpu(output.m_data, bbox_index, num_xy_entries, m_scale_x_y, m_beta, 1, stats);
            }
        } else
        {
            // HWC layout: apply activations and scale with HWC indexing
            for (int n = 0; n < m_num_anchors; ++n) {
                for (int loc = 0; loc < wh; ++loc) {
                    const int base = loc * total_channels + n * entries_per_anchor;

                    // x, y activation (sigmoid) and then scale-add
                    for (int e = 0; e < 2; ++e) {
                        const int idx = base + e;
                        float val = output.m_data[idx];
                        // Sigmoid activation
                        val = 1.0f / (1.0f + std::exp(-val));
                        output.m_data[idx] = val;
                        // Mirror activate_array stats for one element
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_OTHER, 1);
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::MEMORY_STORE, 1);

                        // Scale-add: val = val * m_scale_x_y + m_beta
                        val = val * m_scale_x_y + m_beta;
                        output.m_data[idx] = val;
                        // Mirror scale_add_cpu stats for one element
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                    }

                    // objectness + class probabilities activation (sigmoid)
                    for (int e = 4; e < entries_per_anchor; ++e) {
                        const int idx = base + e;
                        float val = output.m_data[idx];
                        val = 1.0f / (1.0f + std::exp(-val));
                        output.m_data[idx] = val;
                        // Mirror activate_array stats for one element
                        stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                        stats.record_operation(OperationType::ARITHMETIC_OTHER, 1);
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
                        stats.record_operation(OperationType::MEMORY_LOAD, 1);
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                    }
                }
            }
        }

        //Update statistics
        populate_stats_yolo(num_xy_entries, num_confidence_class_entries, m_num_anchors, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }
} // namespace DC_ConvNet 
