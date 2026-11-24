#pragma once

#include "DC_tensor.h"
#include "DC_OnChipMemory.h"

namespace DC_ConvNet {

    struct LayerStats;
    struct DC_Tensor;

    /**
     * @brief Parameter structure for compute_kernel functions.
     * 
     * Wraps the commonly used parameters for kernel computation operations
     * to improve code readability and maintainability.
     */
    struct DC_ComputeKernelParams {
        /// Starting channel index in the input tensor.
        int input_channel_start_idx;
        /// Output channel index to be computed.
        int out_channel_idx;
        /// Output row index to be computed.
        int out_row_idx;
        /// Output column index to be computed.
        int out_col_idx;
        /// Height of the input tensor.
        int input_height;
        /// Width of the input tensor.
        int input_width;
        /// Spatial size of the kernel (assumed square).
        int kernel_size;
        /// Stride used during the kernel traversal.
        int stride;
        /// Padding applied to the input tensor.
        int padding;
        /// Number of input channels.
        int num_input_channels;
        /// Number of output channels.
        int num_output_channels;
        /// Capacity (in rows) of any local line buffer used by the kernel.
        int local_buffer_rows_capacity;

        /**
         * @brief Constructor for DC_ComputeKernelParams
         * 
         * @param input_channel_start_idx Starting channel index for input
         * @param out_channel_idx Output channel index
         * @param out_row_idx Output row index
         * @param out_col_idx Output column index
         * @param input_height Input tensor height
         * @param input_width Input tensor width
         * @param kernel_size Size of the kernel
         * @param stride Stride value
         * @param padding Padding value
         * @param num_input_channels Number of input channels
         * @param num_output_channels Number of output channels
         */
        DC_ComputeKernelParams(int input_channel_start_idx, int out_channel_idx, 
                              int out_row_idx, int out_col_idx,
                              int input_height, int input_width, int kernel_size,
                              int stride, int padding, int num_input_channels, 
                              int num_output_channels, int local_buffer_rows_capacity = 0)
            : input_channel_start_idx(input_channel_start_idx)
            , out_channel_idx(out_channel_idx)
            , out_row_idx(out_row_idx)
            , out_col_idx(out_col_idx)
            , input_height(input_height)
            , input_width(input_width)
            , kernel_size(kernel_size)
            , stride(stride)
            , padding(padding)
            , num_input_channels(num_input_channels)
            , num_output_channels(num_output_channels)
            , local_buffer_rows_capacity(local_buffer_rows_capacity) {}
    };

    /**
     * @class DC_ComputeKernel
     * @brief Abstract base class for kernel computation operations.
     *
     * Derived classes implement specific kernel operations (e.g., convolution,
     * pooling) either on raw host pointers or on an on-chip memory abstraction.
     */
    class DC_ComputeKernel {
    protected:

        virtual ~DC_ComputeKernel() = default;

        /**
         * @brief Pure virtual function for kernel computation operations
         * 
         * This function must be implemented by derived classes to perform
         * the specific kernel computation operation (convolution, pooling, etc.)
         * at a given spatial position and output channel.
         * 
         * @param input Input tensor containing feature maps
         * @param weights Pointer to weight vector (may be nullptr for operations without weights)
         * @param compute_params Pointer to DC_ComputeKernelParams structure containing all necessary parameters
         * @param stride_mode Stride mode (VALID, SAME, or MULTIPLY)
         * @param mem_order Memory order (HWC or CHW) for index calculation
         * @param stats Performance statistics recorder for operation counting
         * @return float Computed result for the specified output position and channel
         */
        virtual float compute_kernel(
            const float* const input,
            const float* const weights,
            const DC_ComputeKernelParams* const compute_params,
            StrideMode stride_mode,
            MEM_ORDER mem_order,
            LayerStats& stats
        ) const = 0;

        /**
         * @brief Optional overload of compute_kernel using `DC_OnChipMemory`.
         *
         * Implementations may override this variant when operating directly on
         * on-chip memory instead of raw host pointers. The default implementation
         * returns 0 and performs no computation.
         */
        virtual float compute_kernel(
            const DC_OnChipMemory& ,
            const DC_ComputeKernelParams& ,
            StrideMode ,
            MEM_ORDER ,
            LayerStats& 
        ) const { return 0.f; }
    };

} // namespace DC_ConvNet 
