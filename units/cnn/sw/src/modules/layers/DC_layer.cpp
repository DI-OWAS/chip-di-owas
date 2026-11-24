#include "DC_layer.h"
#include <filesystem>
#include <fstream>

namespace DC_ConvNet {
    // Layer is an abstract base class with default implementations
    // for some methods. No additional implementation is needed here.

    std::string layerTypeToString(Layer_Type type) {
        switch (type) {
        case Layer_Type::CONV:
            return "Conv2D";
        case Layer_Type::DECONV2D:
            return "DeConv2D";
        case Layer_Type::MAXPOOL:
            return "MaxPool2D";
        case Layer_Type::ROUTE:
            return "Route";
        case Layer_Type::UPSAMPLE:
            return "Upsample";
        case Layer_Type::YOLO:
            return "Yolo";
        case Layer_Type::FLATTEN:
            return "Flatten";
        case Layer_Type::DENSE:
            return "Dense";
        case Layer_Type::SOFTMAX:
            return "Softmax";
        case Layer_Type::SOFTMAX_ND:
            return "SoftmaxND";
        case Layer_Type::SHORTCUT:
            return "Shortcut";
        case Layer_Type::AVGPOOL:
            return "AvgPool2D";
        case Layer_Type::L2NORM:
            return "L2Norm";
        case Layer_Type::RESHAPE:
            return "Reshape";
        case Layer_Type::TRANSPOSE:
            return "Transpose";
        case Layer_Type::CONCAT:
            return "Concat";
        case Layer_Type::ADD:
            return "Add";
        case Layer_Type::LAYERNORM:
            return "LayerNorm";
        case Layer_Type::SKIP_LAYERNORM:
            return "SkipLayerNorm";
        case Layer_Type::GEMM:
            return "Gemm";
        case Layer_Type::GATHER:
            return "Gather";
        case Layer_Type::MUL:
            return "Mul";
        case Layer_Type::MATMUL:
            return "MatMul";
        case Layer_Type::GELU:
            return "Gelu";
        case Layer_Type::RELU:
            return "Relu";
        case Layer_Type::SLICE:
            return "Slice";
        case Layer_Type::RESIZE:
            return "Resize";
        case Layer_Type::UNKNOWN:
            return "Unknown";
        default:
            return "Unknown";
        }
    }

    void DC_Layer::dump_output_if_enabled(const DC_Tensor& output, MEM_ORDER mem_order) const
    {
        if (!m_dump_enabled) {
            return;
        }

        namespace fs = std::filesystem;

        const std::string base_dir = m_dump_directory + std::string(mem_order == MEM_ORDER::CHW ? "out_chw" : "out_hwc");
        const std::string safe_layer = m_layer_name.empty() ? std::string("layer") : m_layer_name;

        fs::create_directories(base_dir);

        const std::string file_name = safe_layer + std::string("_") + std::to_string(m_dump_counter++) + std::string(".txt");
        const fs::path file_path = fs::path(base_dir) / file_name;

        const size_t expected_count = static_cast<size_t>(output.m_height) * static_cast<size_t>(output.m_width) * static_cast<size_t>(output.m_channels);

        if (fs::exists(file_path)) {
            // Compare with existing golden file
            std::ifstream ifs(file_path.string());
            if (ifs) {
                std::vector<float> golden;
                golden.reserve(expected_count);
                float v = 0.f;
                while (ifs >> v) {
                    golden.push_back(v);
                }

                bool match = golden.size() == expected_count;
                size_t mismatch_index = static_cast<size_t>(-1);
                float expected_val = 0.f;
                float actual_val = 0.f;
                if (match) {
                    constexpr float kTol = 1e-5f;
                    for (size_t i = 0; i < expected_count; ++i) {
                        const float gv = golden[i];
                        const float av = output.m_data[i];
                        if (std::abs(gv - av) > kTol) {
                            match = false;
                            mismatch_index = i;
                            expected_val = gv;
                            actual_val = av;
                            break;
                        }
                    }
                }

                if (!match) {
                    // Write the actual output to a sidecar file without any headers
                    const fs::path actual_path = fs::path(file_path.string() + ".actual");
                    std::ofstream aofs(actual_path.string(), std::ios::out | std::ios::trunc);
                    if (aofs) {
                        aofs << std::setprecision(9) << std::fixed;
                        for (int c = 0; c < output.m_channels; ++c) {
                            for (int h = 0; h < output.m_height; ++h) {
                                for (int w = 0; w < output.m_width; ++w) {
                                    const size_t idx = static_cast<size_t>(c) * output.m_height * output.m_width
                                        + static_cast<size_t>(h) * output.m_width + static_cast<size_t>(w);
                                    aofs << output.m_data[idx] << '\n';
                                }
                            }
                        }
                    }

                    if (golden.size() != expected_count) {
                        throw std::runtime_error("Golden file size mismatch for '" + file_path.string() + "': expected "
                            + std::to_string(expected_count) + ", got " + std::to_string(golden.size()));
                    }
                    else {
                        throw std::runtime_error("Output mismatch for '" + file_path.string() + "' at index "
                            + std::to_string(mismatch_index) + ": expected=" + std::to_string(expected_val)
                            + ", actual=" + std::to_string(actual_val));
                    }
                }
                // If match, do nothing
            }
            // If cannot read, fall through to write a new file
        }

        if (!fs::exists(file_path)) {
            std::ofstream ofs(file_path.string(), std::ios::out | std::ios::trunc);
            if (!ofs) {
                return;
            }

            ofs << std::setprecision(9) << std::fixed;

            // Dump in CHW linear order to be unambiguous regardless of m_mem_order
            for (int c = 0; c < output.m_channels; ++c) {
                for (int h = 0; h < output.m_height; ++h) {
                    for (int w = 0; w < output.m_width; ++w) {
                        const size_t idx = static_cast<size_t>(c) * output.m_height * output.m_width
                            + static_cast<size_t>(h) * output.m_width + static_cast<size_t>(w);
                        ofs << output.m_data[idx] << '\n';
                    }
                }
            }
        }

    }
} // namespace DC_ConvNet 
