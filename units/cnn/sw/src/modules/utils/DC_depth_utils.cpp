#include "DC_depth_utils.h"
#include "DC_image_utils.h"

#include <algorithm>
#include <iostream>

namespace DC_ConvNet {

    void DC_DepthUtils::visualize_depth_output(int input_id, const DC_Tensor& input_image,
        const std::vector<DC_Tensor>& outputs, const DC_NetConfig& net_conf) {
        if (outputs.empty()) {
            throw std::runtime_error("Depth Anything inference produced no output tensors");
        }
        if (net_conf.height <= 0 || net_conf.width <= 0) {
            throw std::runtime_error("Network configuration is missing valid width/height");
        }

        const DC_Tensor& predicted = outputs.back();
        const auto expected_size = static_cast<size_t>(net_conf.height * net_conf.width);
        if (predicted.m_data.size() != expected_size) {
            throw std::runtime_error(
                "Depth output size mismatch: expected " + std::to_string(expected_size)
                + " values, got " + std::to_string(predicted.m_data.size()));
        }

        DC_Tensor depth(net_conf.height, net_conf.width, 1, input_image.m_mem_order);
        depth.m_data = predicted.m_data;

        if (depth.m_width != input_image.m_width || depth.m_height != input_image.m_height) {
            depth = DC_ImageUtils::resize_image(depth, input_image.m_width, input_image.m_height);
        }

        const auto [min_it, max_it] = std::minmax_element(depth.m_data.begin(), depth.m_data.end());
        const float depth_min = *min_it;
        const float depth_max = *max_it;
        const float range = depth_max - depth_min;

        DC_Tensor normalized(depth.m_height, depth.m_width, 1, depth.m_mem_order);
        if (range <= 0.f) {
            std::fill(normalized.m_data.begin(), normalized.m_data.end(), 0.f);
        } else {
            for (size_t i = 0; i < depth.m_data.size(); ++i) {
                normalized.m_data[i] = (depth.m_data[i] - depth_min) / range;
            }
        }

        std::cout << "\nDepth map (" << input_image.m_width << "x" << input_image.m_height << "):"
            << " min=" << depth_min
            << " max=" << depth_max
            << std::endl;

        const std::string output_filename = "depth_" + std::to_string(input_id) + ".png";
        if (!DC_ImageUtils::save_image_png(output_filename, normalized)) {
            throw std::runtime_error("Failed to save depth map to " + output_filename);
        }
        std::cout << "Saved depth map to " << output_filename << std::endl;
    }

} // namespace DC_ConvNet
