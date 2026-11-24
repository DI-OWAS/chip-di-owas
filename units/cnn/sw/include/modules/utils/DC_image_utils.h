/******************************************************************************
 * @file    DC_image_utils.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Image processing utility functions
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
#include "DC_cnn_weights_types.h"

#include <string>
#include <vector>

namespace DC_ConvNet {

/**
 * @brief Utility functions for image processing and manipulation in CNN/YOLO context
 * 
 * This class provides comprehensive functionality for:
 * - Image loading and saving in various formats
 * - Preprocessing for neural network input
 * - Tensor operations and manipulations
 * - Visualization utilities for object detection
 */
class DC_ImageUtils final {
public:
    /**
     * @brief Loads an image file into memory
     * 
     * Supports common image formats (PNG, JPG, BMP) through STB library.
     * Automatically handles different color channels and bit depths.
     *
     * @param filename Path to the image file
     * @return std::vector<unsigned char> Raw image data in RGB format
     * @throws std::runtime_error If file cannot be opened or is invalid
     */
    static std::vector<unsigned char> load_image(const std::string& filename);

    /**
     * @brief Saves raw image data to a file
     * 
     * @param filename Output file path (format determined by extension)
     * @param data Raw image data in RGB format
     * @param width Image width in pixels
     * @param height Image height in pixels
     * @throws std::runtime_error If file cannot be written
     */
    static void save_image(const std::string& filename, const std::vector<unsigned char>& data, 
                   int width, int height);
    
    /**
     * @brief Sets a pixel value in a tensor at specified coordinates
     * 
     * @param tensor Target tensor to modify
     * @param x X-coordinate (width dimension)
     * @param y Y-coordinate (height dimension)
     * @param c Channel index (0=R, 1=G, 2=B typically)
     * @param value New pixel value to set
     * @throws std::out_of_range If coordinates are invalid
     */
    static void set_pixel(DC_Tensor& tensor, int x, int y, int c, float value);

    /**
     * @brief Resizes an image tensor to specified dimensions
     * 
     * Uses bilinear interpolation for smooth scaling.
     * Maintains aspect ratio if only one dimension is specified.
     *
     * @param input Source image tensor
     * @param target_width Desired width in pixels
     * @param target_height Desired height in pixels
     * @return DC_Tensor Resized image tensor
     */
    static DC_Tensor resize_image(const DC_Tensor& input, int target_width, int target_height);
    
    /**
     * @brief Loads a tensor from a file
     * 
     * Supports various tensor storage formats and automatically handles:
     * - Data type conversion
     * - Shape inference
     * - Channel ordering
     *
     * @param filename Path to tensor file
     * @param mem_order Memory layout order (CHW or HWC)
     * @return DC_Tensor Loaded tensor data
     * @throws std::runtime_error If file cannot be read or format is invalid
     */
    static DC_Tensor load_tensor(const std::string& filename, MEM_ORDER mem_order);

    /**
     * @brief Draws a bounding box on an image tensor
     * 
     * @param image Image tensor to draw on (modified in-place)
     * @param x Center X coordinate (normalized [0,1])
     * @param y Center Y coordinate (normalized [0,1])
     * @param width Box width (normalized [0,1])
     * @param height Box height (normalized [0,1])
     * @param r Red channel value [0,1]
     * @param g Green channel value [0,1]
     * @param b Blue channel value [0,1]
     * @param thickness Line thickness in pixels
     */
    static void draw_bounding_box(DC_Tensor& image, float x, float y, float width, float height, 
                          float r, float g, float b, float thickness = 2.0f);
       
    /**
     * @brief Saves an image tensor to a PNG file
     * 
     * @param filename Output file path
     * @param image Source image tensor
     * @return bool True if save successful, false otherwise
     */
    static bool save_image_png(const std::string& filename, const DC_Tensor& image);
    
    /**
     * @brief Converts normalized coordinates to absolute pixel coordinates
     * 
     * Transforms coordinates from normalized [0,1] range to actual pixel positions.
     * Useful for visualization and bounding box drawing.
     *
     * @param[in,out] x X coordinate to convert
     * @param[in,out] y Y coordinate to convert
     * @param[in,out] width Width to convert
     * @param[in,out] height Height to convert
     * @param image_width Actual image width in pixels
     * @param image_height Actual image height in pixels
     */
    static void normalize_to_pixel_coords(float& x, float& y, float& width, float& height,
        int image_width, int image_height);

    /**
     * @brief Loads and preprocesses multiple images from a directory
     * 
     * Handles:
     * 1. Directory traversal
     * 2. Image loading
     * 3. Preprocessing according to model requirements
     * 4. Batch tensor creation
     *
     * @param data_dir Directory containing input images
     * @param weights_format Format specification affecting preprocessing
     * @return std::vector<DC_Tensor> Batch of preprocessed image tensors
     * @throws std::runtime_error If directory cannot be read or processing fails
     */
    static std::vector<DC_Tensor> get_images(const std::string& data_dir, WeightsFormat weights_format, MEM_ORDER mem_order);

private:
    /**
     * @brief Draws a line segment on an image tensor
     * 
     * Used internally by draw_bounding_box to create box edges.
     * Uses Bresenham's line algorithm for efficient rasterization.
     *
     * @param image Image tensor to draw on
     * @param x1 Start point X coordinate
     * @param y1 Start point Y coordinate
     * @param x2 End point X coordinate
     * @param y2 End point Y coordinate
     * @param r Red channel value [0,1]
     * @param g Green channel value [0,1]
     * @param b Blue channel value [0,1]
     * @param thickness Line thickness in pixels
     */
    static void draw_line(DC_Tensor& image, int x1, int y1, int x2, int y2,
                  float r, float g, float b, float thickness);
};

} // namespace DC_ConvNet 
