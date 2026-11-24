#include "DC_CNNLayer_AvgPool2D.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

#include <iostream>

namespace DC_ConvNet {

    DC_CNNLayer_AvgPool2D::DC_CNNLayer_AvgPool2D(int kernel_height, int kernel_width, int stride_y, int stride_x)
        : m_kernel_height(kernel_height), m_kernel_width(kernel_width), m_stride_y(stride_y), m_stride_x(stride_x) {
        m_layer_type = Layer_Type::AVGPOOL;
    }

    DC_Tensor DC_CNNLayer_AvgPool2D::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const auto num_channels = input.m_channels;
        const auto input_height = input.m_height;
        const auto input_width = input.m_width;

        // If kernel sizes are -1, it's Global Average Pooling
        const int k_h = (m_kernel_height == -1) ? input_height : m_kernel_height;
        const int k_w = (m_kernel_width == -1) ? input_width : m_kernel_width;
        const int s_y = m_stride_y;
        const int s_x = m_stride_x;

        const auto out_height = (m_kernel_height == -1) ? 1 : (input_height - k_h) / s_y + 1;
        const auto out_width = (m_kernel_width == -1) ? 1 : (input_width - k_w) / s_x + 1;

        DC_Tensor output(out_height, out_width, num_channels, input.m_mem_order);

        for (int out_y = 0; out_y < out_height; ++out_y) {
            for (int out_x = 0; out_x < out_width; ++out_x) {
                const int in_y_start = out_y * s_y;
                const int in_x_start = out_x * s_x;

                for (int c = 0; c < num_channels; ++c) {
                    float sum = 0.0f;
                    int count = 0;

                    for (int ky = 0; ky < k_h; ++ky) {
                        for (int kx = 0; kx < k_w; ++kx) {
                            const int in_y = in_y_start + ky;
                            const int in_x = in_x_start + kx;

                            if (in_y < input_height && in_x < input_width) {
                                int input_idx;
                                if (input.m_mem_order == MEM_ORDER::HWC) {
                                    input_idx = (in_y * input_width + in_x) * num_channels + c;
                                } else {
                                    input_idx = c * (input_height * input_width) + (in_y * input_width + in_x);
                                }
                                sum += input.m_data[input_idx];
                                count++;
                                stats.record_operation(OperationType::MEMORY_LOAD, 1);
                                stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
                            }
                        }
                    }

                    int out_idx;
                    if (output.m_mem_order == MEM_ORDER::HWC) {
                        out_idx = (out_y * out_width + out_x) * num_channels + c;
                    } else {
                        out_idx = c * (out_height * out_width) + (out_y * out_width + out_x);
                    }
                    output.m_data[out_idx] = count > 0 ? (sum / count) : 0.0f;
                    if (count > 0) {
                        stats.record_operation(OperationType::ARITHMETIC_MUL, 1); // div as mul
                    }
                    stats.record_operation(OperationType::MEMORY_STORE, 1);
                }
            }
        }

        populate_stats_avgpool(input, out_height, out_width, k_h, k_w, s_y, s_x, stats);
        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }

        return output;
    }

} // namespace DC_ConvNet
