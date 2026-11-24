#include "DC_CNNLayer_MatMul.h"
#include "DC_CNNLayer_Stats.h"
#include "DC_CNNLayer_tensor_ops.h"
#include "DC_PerformanceStats.h"

namespace DC_ConvNet {

    namespace {

        void record_mac(LayerStats& stats) {
            stats.record_operation(OperationType::MEMORY_LOAD, 2);  // lhs + rhs
            stats.record_operation(OperationType::ARITHMETIC_MUL, 1);
            stats.record_operation(OperationType::ARITHMETIC_ADD, 1);
        }

        DC_Tensor batched_matmul_nchw(
            const DC_Tensor& lhs,
            const DC_Tensor& rhs,
            const std::vector<int>& lhs_shape,
            const std::vector<int>& rhs_shape,
            LayerStats& stats) {
            if (lhs_shape.size() != 4 || rhs_shape.size() != 4) {
                throw std::runtime_error("Batched MatMul requires 4D lhs/rhs shapes");
            }

            const int batch = lhs_shape[0] * lhs_shape[1];
            const int m = lhs_shape[2];
            const int k = lhs_shape[3];
            const int rhs_k = rhs_shape[2];
            const int n = rhs_shape[3];

            if (k != rhs_k) {
                throw std::runtime_error("Batched MatMul inner dimension mismatch");
            }

            DC_Tensor output(m, n, batch, lhs.m_mem_order);
            output.set_logical_shape({lhs_shape[0], lhs_shape[1], m, n});
            for (int b = 0; b < batch; ++b) {
                const size_t lhs_batch_offset = static_cast<size_t>(b * m * k);
                const size_t rhs_batch_offset = static_cast<size_t>(b * k * n);
                const size_t out_batch_offset = static_cast<size_t>(b * m * n);

                for (int row = 0; row < m; ++row) {
                    for (int col = 0; col < n; ++col) {
                        float sum = 0.0f;
                        for (int inner = 0; inner < k; ++inner) {
                            sum += lhs.m_data[lhs_batch_offset + static_cast<size_t>(row * k + inner)] *
                                   rhs.m_data[rhs_batch_offset + static_cast<size_t>(inner * n + col)];
                            record_mac(stats);
                        }
                        output.m_data[out_batch_offset + static_cast<size_t>(row * n + col)] = sum;
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                    }
                }
            }

            populate_stats_matmul(batch, m, k, n, stats);
            stats.record_layer_configuration(
                lhs, output.m_height, output.m_width, output.m_channels,
                false, 0, 0, 0, false, ActivationType::NONE);
            return output;
        }

        // Gather/Transpose store 4D [1,C,H,W] as HWC (H,W,C). MatMul over heads is
        // per-channel: out[h,w,c] = sum_k lhs[h,k,c] * rhs[k,w,c].
        DC_Tensor batched_matmul_hwc(
            const DC_Tensor& lhs,
            const DC_Tensor& rhs,
            const std::vector<int>& lhs_shape,
            const std::vector<int>& rhs_shape,
            LayerStats& stats) {
            if (lhs_shape.size() != 4 || rhs_shape.size() != 4) {
                throw std::runtime_error("Batched MatMul requires 4D lhs/rhs shapes");
            }
            if (lhs_shape[0] != 1 || rhs_shape[0] != 1) {
                throw std::runtime_error("HWC MatMul currently requires batch size 1");
            }
            if (lhs_shape[1] != rhs_shape[1]) {
                throw std::runtime_error("HWC MatMul head/channel dimensions must match");
            }

            const int channels = lhs_shape[1];
            const int m = lhs_shape[2];
            const int k = lhs_shape[3];
            const int rhs_k = rhs_shape[2];
            const int n = rhs_shape[3];

            if (k != rhs_k) {
                throw std::runtime_error("Batched MatMul inner dimension mismatch");
            }

            DC_Tensor output(m, n, channels, lhs.m_mem_order);
            output.set_logical_shape({1, channels, m, n});

            for (int c = 0; c < channels; ++c) {
                for (int row = 0; row < m; ++row) {
                    for (int col = 0; col < n; ++col) {
                        float sum = 0.0f;
                        for (int inner = 0; inner < k; ++inner) {
                            const size_t lhs_idx =
                                static_cast<size_t>((row * k + inner) * channels + c);
                            const size_t rhs_idx =
                                static_cast<size_t>((inner * n + col) * channels + c);
                            sum += lhs.m_data[lhs_idx] * rhs.m_data[rhs_idx];
                            record_mac(stats);
                        }
                        output.m_data[static_cast<size_t>((row * n + col) * channels + c)] = sum;
                        stats.record_operation(OperationType::MEMORY_STORE, 1);
                    }
                }
            }

            populate_stats_matmul(channels, m, k, n, stats);
            stats.record_layer_configuration(
                lhs, output.m_height, output.m_width, output.m_channels,
                false, 0, 0, 0, false, ActivationType::NONE);
            return output;
        }

    } // namespace

    DC_CNNLayer_MatMul::DC_CNNLayer_MatMul(
        int relative_lhs_index,
        int relative_rhs_index,
        std::vector<int> lhs_shape,
        std::vector<int> rhs_shape)
        : m_relative_lhs_index(relative_lhs_index),
          m_relative_rhs_index(relative_rhs_index),
          m_lhs_shape(std::move(lhs_shape)),
          m_rhs_shape(std::move(rhs_shape)) {
        m_layer_type = Layer_Type::MATMUL;
        set_dump_enabled(true);
    }

    DC_Tensor DC_CNNLayer_MatMul::forward(const std::vector<DC_Tensor>& layer_outputs) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        const DC_Tensor& lhs = tensor_at_relative(layer_outputs, m_relative_lhs_index);
        const DC_Tensor& rhs = tensor_at_relative(layer_outputs, m_relative_rhs_index);

        DC_Tensor output = (lhs.m_mem_order == MEM_ORDER::HWC
                ? batched_matmul_hwc(lhs, rhs, m_lhs_shape, m_rhs_shape, stats)
                : batched_matmul_nchw(lhs, rhs, m_lhs_shape, m_rhs_shape, stats));

        dump_output_if_enabled(output, lhs.m_mem_order);
        return output;
    }

} // namespace DC_ConvNet
