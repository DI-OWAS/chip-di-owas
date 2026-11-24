#include "DC_CNNLayer_Transpose.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

#include <iostream>

namespace DC_ConvNet {

    namespace {

        bool perm_equals(const std::vector<int>& perm, std::initializer_list<int> expected) {
            if (perm.size() != expected.size()) {
                return false;
            }
            size_t i = 0;
            for (const int value : expected) {
                if (perm[i++] != value) {
                    return false;
                }
            }
            return true;
        }

        bool is_perfect_square(int value, int& side) {
            if (value <= 0) {
                return false;
            }
            side = static_cast<int>(std::lround(std::sqrt(static_cast<double>(value))));
            return side * side == value;
        }

        // After Conv->Reshape view, HWC bytes are still [S,S,C] while logical shape is
        // ONNX [1,C,S*S]. perm 0,2,1 is then an identity on that buffer.
        bool hwc_spatial_021_is_identity(const std::vector<int>& input_shape) {
            if (input_shape.size() != 3 || input_shape[0] != 1) {
                return false;
            }
            const int channels = input_shape[1];
            const int spatial = input_shape[2];
            int side = 0;
            return is_perfect_square(spatial, side) && channels != spatial;
        }

        // [A,B,C] -> [A,C,B]
        void transpose_0_2_1(const float* input, float* output, int a, int b, int c) {
            for (int ia = 0; ia < a; ++ia) {
                for (int ib = 0; ib < b; ++ib) {
                    for (int ic = 0; ic < c; ++ic) {
                        output[static_cast<size_t>((ia * c + ic) * b + ib)] =
                            input[static_cast<size_t>((ia * b + ib) * c + ic)];
                    }
                }
            }
        }

        // [A,B,C,D] -> [A,B,D,C] on ONNX / CHW-flat buffers
        void transpose_0_1_3_2(const float* input, float* output, int a, int b, int c, int d) {
            const int plane = c * d;
            for (int outer = 0; outer < a * b; ++outer) {
                const float* in = input + static_cast<size_t>(outer) * static_cast<size_t>(plane);
                float* out = output + static_cast<size_t>(outer) * static_cast<size_t>(plane);
                for (int ic = 0; ic < c; ++ic) {
                    for (int id = 0; id < d; ++id) {
                        out[static_cast<size_t>(id * c + ic)] =
                            in[static_cast<size_t>(ic * d + id)];
                    }
                }
            }
        }

        // Gather/logical_to_tensor stores 4D [1,C,H,W] as HWC (H,W,C).
        // ONNX perm 0,1,3,2 -> [1,C,W,H] is an (H,W) swap per channel.
        void transpose_0_1_3_2_hwc(const float* input, float* output, int height, int width, int channels) {
            for (int c = 0; c < channels; ++c) {
                for (int h = 0; h < height; ++h) {
                    for (int w = 0; w < width; ++w) {
                        output[static_cast<size_t>((w * height + h) * channels + c)] =
                            input[static_cast<size_t>((h * width + w) * channels + c)];
                    }
                }
            }
        }

        // [A,B,C,D] -> [A,C,B,D]
        void transpose_0_2_1_3(const float* input, float* output, int a, int b, int c, int d) {
            for (int ia = 0; ia < a; ++ia) {
                for (int ib = 0; ib < b; ++ib) {
                    for (int ic = 0; ic < c; ++ic) {
                        for (int id = 0; id < d; ++id) {
                            output[static_cast<size_t>(((ia * c + ic) * b + ib) * d + id)] =
                                input[static_cast<size_t>(((ia * b + ib) * c + ic) * d + id)];
                        }
                    }
                }
            }
        }

        // Input HWC (H,W,C)=(tokens,dim,heads) from [1,heads,tokens,dim].
        // ONNX perm 0,2,1,3 -> [1,tokens,heads,dim] stored as HWC (heads,dim,tokens).
        void transpose_0_2_1_3_hwc(
            const float* input,
            float* output,
            int tokens,
            int dim,
            int heads) {
            for (int tok = 0; tok < tokens; ++tok) {
                for (int d = 0; d < dim; ++d) {
                    for (int head = 0; head < heads; ++head) {
                        output[static_cast<size_t>((head * dim + d) * tokens + tok)] =
                            input[static_cast<size_t>((tok * dim + d) * heads + head)];
                    }
                }
            }
        }

        // [A,B,C,D,E] -> [C,A,D,B,E]
        void transpose_2_0_3_1_4(
            const float* input,
            float* output,
            int a,
            int b,
            int c,
            int d,
            int e) {
            for (int ia = 0; ia < a; ++ia) {
                for (int ib = 0; ib < b; ++ib) {
                    for (int ic = 0; ic < c; ++ic) {
                        for (int id = 0; id < d; ++id) {
                            for (int ie = 0; ie < e; ++ie) {
                                const size_t in_idx = static_cast<size_t>(
                                    ((((ia * b + ib) * c + ic) * d + id) * e + ie));
                                const size_t out_idx = static_cast<size_t>(
                                    ((((ic * a + ia) * d + id) * b + ib) * e + ie));
                                output[out_idx] = input[in_idx];
                            }
                        }
                    }
                }
            }
        }

    } // namespace

    DC_CNNLayer_Transpose::DC_CNNLayer_Transpose(
        std::vector<int> perm,
        std::vector<int> input_shape)
        : m_perm(std::move(perm)),
          m_input_shape(std::move(input_shape)),
          m_out_height(1),
          m_out_width(1),
          m_out_channels(1) {
        m_layer_type = Layer_Type::TRANSPOSE;
        set_dump_enabled(true);

        if (m_perm.size() != m_input_shape.size()) {
            throw std::runtime_error("Transpose perm rank does not match input shape rank");
        }

        const bool supported =
            perm_equals(m_perm, {0, 2, 1}) ||
            perm_equals(m_perm, {0, 1, 3, 2}) ||
            perm_equals(m_perm, {0, 2, 1, 3}) ||
            perm_equals(m_perm, {2, 0, 3, 1, 4});
        if (!supported) {
            throw std::runtime_error("Transpose perm is not one of the supported Depth-Anything patterns");
        }

        m_output_shape.resize(m_perm.size());
        for (size_t i = 0; i < m_perm.size(); ++i) {
            const int src_axis = m_perm[i];
            if (src_axis < 0 || static_cast<size_t>(src_axis) >= m_input_shape.size()) {
                throw std::runtime_error("Transpose perm axis out of bounds");
            }
            m_output_shape[i] = m_input_shape[static_cast<size_t>(src_axis)];
        }

        // Match Gather / logical_to_tensor 4D mapping: [N,C,H,W] -> (H,W,C).
        logical_shape_to_tensor_dims(m_output_shape, m_out_height, m_out_width, m_out_channels);
    }

    DC_Tensor DC_CNNLayer_Transpose::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(m_out_height, m_out_width, m_out_channels, input.m_mem_order);
        output.set_logical_shape(m_output_shape);

        const float* in = input.m_data.data();
        float* out = output.m_data.data();

        if (perm_equals(m_perm, {0, 2, 1})) {
            if (input.m_mem_order == MEM_ORDER::HWC
                && hwc_spatial_021_is_identity(m_input_shape)) {
                std::copy_n(in, input.m_data.size(), out);
            }
            else {
                transpose_0_2_1(
                    in, out,
                    m_input_shape[0], m_input_shape[1], m_input_shape[2]);
            }
        }
        else if (perm_equals(m_perm, {0, 1, 3, 2})) {
            if (input.m_mem_order == MEM_ORDER::HWC
                && m_input_shape.size() == 4
                && m_input_shape[0] == 1) {
                // Input is HWC (H,W,C) = (shape[2], shape[3], shape[1]).
                transpose_0_1_3_2_hwc(
                    in, out,
                    m_input_shape[2], m_input_shape[3], m_input_shape[1]);
            }
            else {
                transpose_0_1_3_2(
                    in, out,
                    m_input_shape[0], m_input_shape[1], m_input_shape[2], m_input_shape[3]);
            }
        }
        else if (perm_equals(m_perm, {0, 2, 1, 3})) {
            if (input.m_mem_order == MEM_ORDER::HWC
                && m_input_shape.size() == 4
                && m_input_shape[0] == 1) {
                // Input HWC (tokens,dim,heads) = (shape[2], shape[3], shape[1]).
                transpose_0_2_1_3_hwc(
                    in, out,
                    m_input_shape[2], m_input_shape[3], m_input_shape[1]);
            }
            else {
                transpose_0_2_1_3(
                    in, out,
                    m_input_shape[0], m_input_shape[1], m_input_shape[2], m_input_shape[3]);
            }
        }
        else {
            transpose_2_0_3_1_4(
                in, out,
                m_input_shape[0], m_input_shape[1], m_input_shape[2],
                m_input_shape[3], m_input_shape[4]);
        }

        stats.record_layer_configuration(
            input, output.m_height, output.m_width, output.m_channels,
            false, 0, 0, 0, false, ActivationType::NONE);

        const size_t elements = input.m_data.size();
        stats.record_operation(OperationType::MEMORY_LOAD, elements);
        stats.record_operation(OperationType::MEMORY_STORE, elements);
        populate_stats_transpose(elements, stats);

        try {
            dump_output_if_enabled(output, input.m_mem_order);
        }
        catch (const std::exception& e) {
            std::cerr << "Error dumping : " << e.what() << std::endl;
        }
        return output;
    }

} // namespace DC_ConvNet
