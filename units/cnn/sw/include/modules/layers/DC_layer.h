/******************************************************************************
 * @file    DC_layer.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Base layer class for neural network layers
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
#include "DC_CNN_HW_Command.h"
#include "DC_CNN_HW_Parameters.h"

#include <string>
#include <list>
#include <memory>

namespace DC_ConvNet {

    /**
     * @brief Identifies the concrete neural network layer kind
     */
    enum class Layer_Type
    {
          CONV            /**< 2D convolution */
        , DECONV2D        /**< 2D transposed convolution */
        , MAXPOOL         /**< Max pooling */
        , ROUTE           /**< Route / multi-input data movement */
        , UPSAMPLE        /**< Spatial upsampling */
        , YOLO            /**< YOLO detection head */
        , FLATTEN         /**< Flatten to 1D feature vector */
        , DENSE           /**< Fully connected / dense */
        , SOFTMAX         /**< Softmax over logits */
        , SOFTMAX_ND      /**< Softmax over an arbitrary axis */
        , SHORTCUT        /**< Residual shortcut add */
        , AVGPOOL         /**< Average pooling */
        , L2NORM          /**< L2 normalization */
        , RESHAPE         /**< Tensor reshape */
        , TRANSPOSE       /**< Axis permutation / transpose */
        , CONCAT          /**< Concatenation along an axis */
        , ADD             /**< Element-wise addition */
        , LAYERNORM       /**< Layer normalization */
        , SKIP_LAYERNORM  /**< Residual add + layer normalization */
        , GEMM            /**< General matrix multiply */
        , GATHER          /**< Index gather along an axis */
        , MUL             /**< Element-wise multiply */
        , MATMUL          /**< Matrix multiply of two tensors */
        , GELU            /**< GELU activation */
        , RELU            /**< ReLU activation */
        , SLICE           /**< Contiguous axis slice */
        , RESIZE          /**< Spatial bilinear resize */
        , UNKNOWN         /**< Unspecified / uninitialized layer type */
    };

    /**
     * @brief Helper function to convert Layer_Type to string
     * 
     * @param type Layer type enumeration
     * @return std::string String representation of the layer type
     */
    std::string layerTypeToString(Layer_Type type);

    /**
     * @brief Abstract base class for all neural network layers
     * 
     * Defines the interface that all layer implementations must adhere to.
     */
    class DC_Layer {
    public:
        virtual ~DC_Layer() = default;
        
		/**
         * @brief Build HW parameter descriptors for a single-input layer
         *
         * @param input Input tensor used to derive HW parameters
         * @return DC_HW_Params_Layer Parameter set for accelerator scheduling (default empty)
         */
		virtual DC_HW_Params_Layer build_layer_parameter_set(const DC_Tensor& /*input*/) const { return DC_HW_Params_Layer(); }

        /**
         * @brief Build HW parameter descriptors for a multi-input layer
         *
         * @param inputs Input tensors used to derive HW parameters
         * @return std::vector<DC_HW_Params_Layer> Parameter sets (default empty)
         */
        virtual std::vector<DC_HW_Params_Layer> build_layer_parameter_set(const std::vector<DC_Tensor>& /*inputs*/) const { return {}; }

        /**
         * @brief Perform forward pass through the layer
         * 
         * @param input Input tensor
         * @return DC_Tensor Output tensor after layer computation
         */
        virtual DC_Tensor forward(const DC_Tensor& input) const = 0;

        /**
         * @brief Perform forward pass through the layer
         *
         * @param input Input tensors
         * @return DC_Tensor Output tensor after layer computation
         */
        virtual DC_Tensor forward(const std::vector<DC_Tensor>& layer_outputs) const = 0;

        /**
         * @brief Whether forward() requires the full @p layer_outputs history.
         */
        virtual bool requires_layer_outputs() const { return false; }

        /**
         * @brief Emit accelerator FIFO commands for a single-parameter layer
         *
         * @param output Output tensor buffer (may be used for DMA destinations)
         * @param params HW parameter set for this layer
         * @return std::list<std::unique_ptr<DC_CNN_HW_Command>> Ordered HW commands (default empty)
         */
        virtual std::list<std::unique_ptr<DC_CNN_HW_Command>> build_fifo_commands(DC_Tensor& /*output*/, const DC_HW_Params_Layer& /*params*/) const { return {}; }

        /**
         * @brief Emit accelerator FIFO commands for a multi-parameter layer
         *
         * @param output Output tensor buffer (may be used for DMA destinations)
         * @param params Vector of HW parameter sets for this layer
         * @return std::list<std::unique_ptr<DC_CNN_HW_Command>> Ordered HW commands (default empty)
         */
        virtual std::list<std::unique_ptr<DC_CNN_HW_Command>> build_fifo_commands(DC_Tensor& /*output*/, const std::vector<DC_HW_Params_Layer>& /*params*/) const { return {}; }

        /**
         * @brief Get the layer type
         * 
         * @return Layer_Type The type of this layer
         */
        Layer_Type get_layer_type() const { return m_layer_type; }
        
        /**
         * @brief Set the layer name
         * 
         * @param name The name to set for this layer
         */
        void set_layer_name(const std::string& name) { m_layer_name = name; }
        
        /**
         * @brief Get the layer name
         * 
         * @return std::string The name of this layer
         */
        std::string get_layer_name() const { return m_layer_name; }    
        
		/**
         * @brief Set the unique numeric identifier of this layer in the network
         *
         * @param id Layer index / id assigned by the network builder
         */
		void set_layer_id(size_t id) { m_layer_id = id; }

        /**
         * @brief Get the unique numeric identifier of this layer
         *
         * @return size_t Layer index / id
         */
        size_t get_layer_id() const { return m_layer_id; }

        /**
         * @brief Store the logical shape of an optional constant operand
         *
         * @param shape Operand shape; also marks the layer as having an operand
         */
        void set_operand_shape(const std::vector<int>& shape) { m_operand_shape = shape; m_has_operand = true; }

        /**
         * @brief Whether this layer has an associated constant operand shape
         *
         * @return true If set_operand_shape() was called
         */
        bool has_operand() const { return m_has_operand; }

        /**
         * @brief Get the logical shape of the constant operand
         *
         * @return const std::vector<int>& Operand shape (empty if none)
         */
        const std::vector<int>& get_operand_shape() const { return m_operand_shape; }

        /**
         * @brief Set directory where output dumps will be written. Created if missing.
         */
        void set_dump_directory(const std::string& dir) { m_dump_directory = dir; }

        /**
         * @brief Enable or disable golden output dumping for this layer.
         */
        void set_dump_enabled(bool enabled) { m_dump_enabled = enabled; }

        /**
         * @brief If dumping is enabled, write the given output tensor to a text file.
         * The file name uses: [prefix_]layerName_[counter].txt inside dump directory.
         *
         * @param output The output tensor to dump
         * @param mem_order Memory layout order (CHW or HWC)
         */
        void dump_output_if_enabled(const DC_Tensor& output, MEM_ORDER mem_order) const;

    protected:

        Layer_Type m_layer_type = Layer_Type::UNKNOWN;
        std::string m_layer_name = "unnamed_layer";
		size_t m_layer_id = 0u;

        std::vector<int> m_operand_shape;
        bool m_has_operand = false;

    private:
        std::string m_dump_directory = "output_dumps";
        bool m_dump_enabled = false;
        mutable size_t m_dump_counter = 0;
    };

} // namespace DC_ConvNet
