#include "DC_image_utils.h"

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#ifdef _MSC_VER
#define __STDC_LIB_EXT1__
#endif
#include "stb_image.h"
#include "stb_image_write.h"

#include <iostream>
#include <fstream>
#include <filesystem>
#include <algorithm>

namespace fs = std::filesystem;

namespace DC_ConvNet {

    /**
     * @brief Load an image from a binary file
     *
     * @param filename Path to the image file
     * @return std::vector<unsigned char> Raw image data
     */
    std::vector<unsigned char> DC_ImageUtils::load_image(const std::string& filename) {
        int width, height, channels;
        unsigned char* data = stbi_load(filename.c_str(), &width, &height, &channels, 3);

        if (!data) {
            throw std::runtime_error("Failed to load image: " + filename);
        }

        std::vector<unsigned char> image_data(data, data + width * height * 3);
        stbi_image_free(data);

        return image_data;
    }

    /**
     * @brief Save an image to a binary file
     *
     * @param filename Path to save the image file
     * @param data Raw image data
     * @param width Image width
     * @param height Image height
     */
    void DC_ImageUtils::save_image(const std::string& filename, const std::vector<unsigned char>& data,
        int width, int height) {
        std::ofstream file(filename, std::ios::binary);
        if (!file) {
            throw std::runtime_error("Failed to open file for writing: " + filename);
        }

        // Write image dimensions
        file.write(reinterpret_cast<const char*>(&width), sizeof(width));
        file.write(reinterpret_cast<const char*>(&height), sizeof(height));

        // Write image data
        file.write(reinterpret_cast<const char*>(data.data()), data.size());

        if (!file) {
            throw std::runtime_error("Failed to write image data to file: " + filename);
        }
    }

    void DC_ImageUtils::set_pixel(DC_Tensor& tensor, int x, int y, int c, float value) {
        if (x < 0 || y < 0 || c < 0 || x >= tensor.m_width || y >= tensor.m_height || c >= tensor.m_channels) return;
        assert(x < tensor.m_width && y < tensor.m_height && c < tensor.m_channels);
        if (tensor.m_mem_order == MEM_ORDER::CHW) {
            tensor.m_data[c * tensor.m_height * tensor.m_width + y * tensor.m_width + x] = value;
        } else {
            tensor.m_data[y * tensor.m_width * tensor.m_channels + x * tensor.m_channels + c] = value;
        }
    }

    DC_Tensor DC_ImageUtils::resize_image(const DC_Tensor& input, int target_width, int target_height) {
        // If no resize needed, return a copy
        if (input.m_width == target_width && input.m_height == target_height) {
            DC_Tensor output(target_height, target_width, input.m_channels, input.m_mem_order);
            std::copy(input.m_data.begin(), input.m_data.end(), output.m_data.begin());
            return output;
        }

        // Create intermediate and output tensors
        DC_Tensor part(input.m_height, target_width, input.m_channels, input.m_mem_order);
        DC_Tensor resized(target_height, target_width, input.m_channels, input.m_mem_order);

        // Calculate scaling factors
        float w_scale = static_cast<float>(input.m_width - 1) / (target_width - 1);
        float h_scale = static_cast<float>(input.m_height - 1) / (target_height - 1);

        // Index helpers for CHW/HWC
        auto get_idx = [&](const DC_Tensor& t, int x, int y, int c) -> int {
            if (input.m_mem_order == MEM_ORDER::CHW) {
                return c * t.m_height * t.m_width + y * t.m_width + x;
            } else {
                return y * t.m_width * t.m_channels + x * t.m_channels + c;
            }
        };

        // First pass - horizontal interpolation
        for (int k = 0; k < input.m_channels; ++k) {
            for (int r = 0; r < input.m_height; ++r) {
                for (int c = 0; c < target_width; ++c) {
                    float val = 0;
                    if (c == target_width - 1 || input.m_width == 1) {
                        val = input.m_data[get_idx(input, input.m_width - 1, r, k)];
                    }
                    else {
                        float sx = c * w_scale;
                        int ix = static_cast<int>(sx);
                        float dx = sx - ix;
                        val = (1 - dx) * input.m_data[get_idx(input, ix, r, k)] +
                            dx * input.m_data[get_idx(input, ix + 1, r, k)];
                    }
                    part.m_data[get_idx(part, c, r, k)] = val;
                }
            }
        }

        // Second pass - vertical interpolation
        for (int k = 0; k < input.m_channels; ++k) {
            for (int r = 0; r < target_height; ++r) {
                float sy = r * h_scale;
                int iy = static_cast<int>(sy);
                float dy = sy - iy;

                for (int c = 0; c < target_width; ++c) {
                    float val = (1 - dy) * part.m_data[get_idx(part, c, iy, k)];
                    resized.m_data[get_idx(resized, c, r, k)] = val;
                }

                if (r == target_height - 1 || input.m_height == 1) continue;

                for (int c = 0; c < target_width; ++c) {
                    float val = dy * part.m_data[get_idx(part, c, iy + 1, k)];
                    resized.m_data[get_idx(resized, c, r, k)] += val;
                }
            }
        }

        return resized;
    }

    /**
     * @brief Load an image directly into a tensor with normalized values [0,1]
     *
     * @param filename Path to the image file
     * @return DC_Tensor Image tensor in HWC format (h x w x 3 c)
     */
    DC_Tensor DC_ImageUtils::load_tensor(const std::string& filename, MEM_ORDER mem_order) {
        int w, h, c;
        unsigned char* data = stbi_load(filename.c_str(), &w, &h, &c, 3);

        if (!data) {
            throw std::runtime_error("Failed to load image: " + filename);
        }

        // Create tensor with appropriate dimensions
        DC_Tensor tensor(h, w, 3, mem_order);

        if (mem_order == MEM_ORDER::CHW) {
            // CHW format: channel first, then height, then width
            for (auto k = 0; k < c; ++k) {
                for (auto j = 0; j < h; ++j) {
                    for (auto i = 0; i < w; ++i) {
                        int dst_index = k * h * w + j * w + i;
                        int src_index = k + c * i + c * w * j;
                        tensor.m_data[dst_index] = static_cast<float>(data[src_index]) / 255.f;
                    }
                }
            }
        } else {
            // HWC format: height first, then width, then channel
            for (auto j = 0; j < h; ++j) {
                for (auto i = 0; i < w; ++i) {
                    for (auto k = 0; k < c; ++k) {
                        int dst_index = j * w * c + i * c + k;
                        int src_index = k + c * i + c * w * j;
                        tensor.m_data[dst_index] = static_cast<float>(data[src_index]) / 255.f;
                    }
                }
            }
        }

        // Free the original image data
        stbi_image_free(data);

        return tensor;
    }

    void DC_ImageUtils::normalize_to_pixel_coords(float& x, float& y, float& width, float& height,
        int image_width, int image_height) {
        // Convert from normalized coordinates (0-1) to pixel coordinates
        x = x * image_width;
        y = y * image_height;
        width = width * image_width;
        height = height * image_height;
    }

    std::vector<DC_Tensor> DC_ImageUtils::get_images(const std::string& data_dir, WeightsFormat weights_format, MEM_ORDER mem_order)
    {
        DC_ImageUtils utils;
        std::vector<std::string> image_paths;

        // Create the directory if it doesn't exist
        if (!fs::exists(data_dir)) {
            std::cout << "Creating data directory..." << std::endl;
            fs::create_directory(data_dir);
        }

        std::cout << "Scanning for PNG files in " << data_dir << " directory..." << std::endl;

        // Find all PNG files in the data directory
        for (const auto& entry : fs::directory_iterator(data_dir)) {
            if (entry.path().extension() == ".png" || entry.path().extension() == ".jpg") {
                image_paths.push_back(entry.path().string());
            }
        }

        if (image_paths.empty()) {
            std::cerr << "No PNG or JPG files found in the data directory." << std::endl;
            return {};
        }

        std::cout << "Found " << image_paths.size() << " image files." << std::endl;

        std::vector<DC_Tensor> inputs;

        std::sort(image_paths.begin(), image_paths.end());

        for (const auto& image_path : image_paths)
        {
            inputs.push_back(utils.load_tensor(image_path, mem_order));
        }

        // yolo only accepts 416x416 images
        if (weights_format == WeightsFormat::YOLO)
        {
            for (auto& input : inputs)
            {
                input = DC_ImageUtils::resize_image(input, 416, 416);
            }
        }

        return inputs;
    }

    void DC_ImageUtils::draw_line(DC_Tensor& image, int x1, int y1, int x2, int y2,
        float r, float g, float b, float thickness) {
        // Bresenham's line algorithm with thickness
        int dx = abs(x2 - x1);
        int dy = abs(y2 - y1);
        int sx = (x1 < x2) ? 1 : -1;
        int sy = (y1 < y2) ? 1 : -1;
        int err = dx - dy;

        while (true) {
            // Draw thick point
            for (auto tx = -thickness; tx <= thickness; tx++) {
                for (auto ty = -thickness; ty <= thickness; ty++) {
                    if (tx * tx + ty * ty <= thickness * thickness) {
                        set_pixel(image, x1 + static_cast<int>(tx), y1 + static_cast<int>(ty), 0, r);
                        set_pixel(image, x1 + static_cast<int>(tx), y1 + static_cast<int>(ty), 1, g);
                        set_pixel(image, x1 + static_cast<int>(tx), y1 + static_cast<int>(ty), 2, b);
                    }
                }
            }

            if (x1 == x2 && y1 == y2) break;
            int e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x1 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y1 += sy;
            }
        }
    }

    void DC_ImageUtils::draw_bounding_box(DC_Tensor& image, float x, float y, float width, float height,
        float r, float g, float b, float thickness) {
        // Convert normalized coordinates to pixel coordinates
        normalize_to_pixel_coords(x, y, width, height, image.m_width, image.m_height);

        // Calculate corner coordinates
        int x1 = static_cast<int>(x - width / 2);
        int y1 = static_cast<int>(y - height / 2);
        int x2 = static_cast<int>(x + width / 2);
        int y2 = static_cast<int>(y + height / 2);

        // Draw the rectangle
        draw_line(image, x1, y1, x2, y1, r, g, b, thickness); // Top
        draw_line(image, x2, y1, x2, y2, r, g, b, thickness); // Right
        draw_line(image, x2, y2, x1, y2, r, g, b, thickness); // Bottom
        draw_line(image, x1, y2, x1, y1, r, g, b, thickness); // Left
    }

    bool DC_ImageUtils::save_image_png(const std::string& filename, const DC_Tensor& image) {
        // Allocate buffer for the image data (converting from float [0-1] to uint8 [0-255])
        std::vector<unsigned char> buffer(image.m_width * image.m_height * image.m_channels);

        // Convert and normalize the image data
        if (image.m_mem_order == MEM_ORDER::CHW) {
            for (auto k = 0; k < image.m_channels; ++k) {
                for (auto j = 0; j < image.m_height; ++j) {
                    for (auto i = 0; i < image.m_width; ++i) {
                        int src_index = k * image.m_height * image.m_width + j * image.m_width + i; // CHW
                        int dst_index = j * image.m_width * image.m_channels + i * image.m_channels + k; // HWC
                        float pixel = std::max(0.0f, std::min(1.0f, image.m_data[src_index]));
                        buffer[dst_index] = static_cast<unsigned char>(pixel * 255.0f);
                    }
                }
            }
        } else 
        {
            for (auto j = 0; j < image.m_height; ++j) {
                for (auto i = 0; i < image.m_width; ++i) {
                    for (auto k = 0; k < image.m_channels; ++k) {
                        int src_index = j * image.m_width * image.m_channels + i * image.m_channels + k; // HWC
                        int dst_index = j * image.m_width * image.m_channels + i * image.m_channels + k; // HWC
                        float pixel = std::max(0.0f, std::min(1.0f, image.m_data[src_index]));
                        buffer[dst_index] = static_cast<unsigned char>(pixel * 255.0f);
                    }
                }
            }
        }

        // Save as PNG
        int result = stbi_write_png(filename.c_str(), image.m_width, image.m_height, image.m_channels,
            buffer.data(), image.m_width * image.m_channels);

        return result != 0;
    }

} // namespace DC_ConvNet 
