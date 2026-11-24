#pragma once

#include "DC_layer.h"
#include "DC_CNN_activation_types.h"
#include "DC_CNNComputeKernel.h"

#include <stdexcept>
#include <vector>

namespace DC_ConvNet {

    struct LayerStats;
    struct DC_Tensor;

    /**
     * @brief 2D transposed convolution (DeConv2D) layer.
     *
     * Follows the same compute-kernel architecture as Conv2D: output-centric
     * loops, shared indexing helpers, fused bias + activation, and stats hooks.
     */
    class DC_CNNLayer_DeConv2D final : public DC_Layer, public DC_ComputeKernel {
    public:
        /**
         * @brief Constructs a 2D transposed convolution layer
         *
         * @param in_channels Number of input channels
         * @param out_channels Number of output channels
         * @param kernel_size Spatial kernel size
         * @param stride Stride of the transposed convolution (default 1)
         * @param padding Padding size (default 0)
         * @param use_bias Whether to add bias after convolution (default false)
         * @param activation Activation applied after the convolution (default NONE)
         */
        DC_CNNLayer_DeConv2D(
            int in_channels,
            int out_channels,
            int kernel_size,
            int stride = 1,
            int padding = 0,
            bool use_bias = false,
            ActivationType activation = ActivationType::NONE);

        /** @brief Whether convolution weights have been loaded. */
        bool weights_loaded() const { return !m_weights.empty(); }
        /** @brief Whether bias terms have been loaded. */
        bool bias_loaded() const { return !m_bias.empty(); }
        /**
         * @brief Load convolution weight tensor
         * @param weights Flat weight buffer in ConvTranspose layout
         */
        void load_weights(const std::vector<float>& weights) { m_weights = weights; }
        /**
         * @brief Load bias vector
         * @param bias Bias terms (one per output channel)
         */
        void load_bias(const std::vector<float>& bias) { m_bias = bias; }

        /** @brief Number of input channels. */
        int get_in_channels() const { return m_in_channels; }
        /** @brief Number of output channels. */
        int get_out_channels() const { return m_out_channels; }
        /** @brief Spatial kernel size. */
        int get_kernel_size() const { return m_kernel_size; }
        /** @brief Whether bias is enabled for this layer. */
        bool get_use_bias() const { return m_use_bias; }

        /**
         * @brief Forward pass: 2D transposed convolution
         *
         * @param input Input tensor
         * @return DC_Tensor Upsampled / deconvolved output
         */
        DC_Tensor forward(const DC_Tensor& input) const override;

        /**
         * @brief Forward propagation with multiple inputs (not supported)
         *
         * @return DC_Tensor (never returns, throws exception)
         * @throws std::logic_error Always throws as this method is not supported
         */
        DC_Tensor forward(const std::vector<DC_Tensor>&) const override {
            throw std::logic_error(m_layer_name + R"(: Use forward(input) instead.)");
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
         * @brief Computes transposed-convolution MAC at one output position/channel.
         *
         * Weights are stored in ConvTranspose layout [in, out, kh, kw] (IOHW for CHW,
         * converted HWIO for HWC), so channel roles are swapped when calling
         * calculate_weight_array_index.
         */
        float compute_kernel(
            const DC_Tensor* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats
        ) const;

        int m_in_channels;
        int m_out_channels;
        int m_kernel_size;
        int m_stride;
        int m_padding;
        bool m_use_bias;
        ActivationType m_activation;
        float m_leaky_alpha;
        std::vector<float> m_weights;
        std::vector<float> m_bias;
    };

} // namespace DC_ConvNet
