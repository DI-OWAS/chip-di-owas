#pragma once

#include "DC_layer.h"
#include "DC_CNNComputeKernel.h"

#include <stdexcept>
#include <vector>

namespace DC_ConvNet {

    struct LayerStats;
    struct DC_Tensor;

    /**
     * @brief General matrix multiply (GEMM) layer: Y = X W^T (+ bias).
     *
     * Follows the same compute-kernel architecture as Conv2D / Dense:
     * DC_ComputeKernelParams, compute_kernel, optional bias, store_result.
     */
    class DC_CNNLayer_Gemm final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a GEMM layer computing Y = X W^T (+ bias)
         *
         * @param in_features Number of input features (columns of X)
         * @param out_features Number of output features (rows of W)
         * @param use_bias Whether to add a bias vector after the matmul (default true)
         */
        DC_CNNLayer_Gemm(int in_features, int out_features, bool use_bias = true);

        /** @brief Whether weight matrix has been loaded. */
        bool weights_loaded() const { return !m_weights.empty(); }
        /** @brief Whether bias vector has been loaded. */
        bool bias_loaded() const { return !m_bias.empty(); }
        /**
         * @brief Load weight matrix
         * @param weights Flat weight buffer in the active memory-order layout
         */
        void load_weights(const std::vector<float>& weights) { m_weights = weights; }
        /**
         * @brief Load bias vector
         * @param bias Bias terms (one per output feature)
         */
        void load_bias(const std::vector<float>& bias) { m_bias = bias; }

        /** @brief Number of input features. */
        int get_in_features() const { return m_in_features; }
        /** @brief Number of output features. */
        int get_out_features() const { return m_out_features; }
        /** @brief Whether bias is enabled for this layer. */
        bool get_use_bias() const { return m_use_bias; }

        /**
         * @brief Forward pass: general matrix multiply
         *
         * @param input Input tensor X
         * @return DC_Tensor Output Y = X W^T (+ bias)
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         *
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error("Use forward(input) instead.");
        }

    private:
        float compute_kernel(
            const float* const,
            const float* const,
            const DC_ComputeKernelParams* const,
            StrideMode,
            MEM_ORDER,
            LayerStats&
        ) const override {
            return 0.f; // Not used in this layer
        }

        /**
         * @brief Dot product of one input row with one output-feature weight vector.
         *
         * Same indexing pattern as Conv2D: calculate_weight_array_index +
         * calculate_input_array_index, both driven by mem_order. Weights are
         * stored in the active mem_order (OI / CHW 1x1, or HWIO for HWC).
         * Bias is applied in forward after this call.
         */
        float compute_kernel(
            const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats
        ) const;

        int m_in_features;
        int m_out_features;
        bool m_use_bias;
        std::vector<float> m_weights;
        std::vector<float> m_bias;
    };

} // namespace DC_ConvNet
