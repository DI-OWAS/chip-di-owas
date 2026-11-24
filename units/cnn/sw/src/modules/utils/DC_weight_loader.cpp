#include "DC_weight_loader.h"
#include "DC_baremetal_log.h"
#include "DC_FifoCommandBuilder_CNNLayer_Conv2D.h"
#include "DC_CNNLayer_Conv2D.h"
#include "DC_CNNLayer_Concat.h"
#include "DC_CNNLayer_Add.h"
#include "DC_CNNLayer_Mul.h"
#include "DC_CNNLayer_Dense.h"
#include "DC_CNNLayer_DeConv2D.h"
#include "DC_CNNLayer_Gemm.h"
#include "DC_CNNLayer_LayerNorm.h"
#include "DC_OWAS_TopLevel.h"

#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <unordered_map>

namespace DC_ConvNet {

    namespace {

        constexpr char kDepthAnythingMagic[4] = {'D', 'C', 'W', 'A'};
        constexpr uint32_t kDepthAnythingVersion = 1;

        enum class DC_DepthAnythingWeightDtype : uint32_t {
            FLOAT32 = 1,
            INT64 = 7,
        };

        struct DC_DepthAnythingTensor {
            std::string name;
            DC_DepthAnythingWeightDtype dtype = DC_DepthAnythingWeightDtype::FLOAT32;
            std::vector<uint32_t> shape;
            std::vector<uint8_t> raw_data;
        };

        class DC_DepthAnythingWeightStore {
        public:
            static DC_DepthAnythingWeightStore load(const std::filesystem::path& bin_path) {
                std::ifstream file(bin_path, std::ios::binary);
                if (!file) {
                    throw std::runtime_error("Failed to open DEPTH_ANYTHING weights file: " + bin_path.string());
                }

                char magic[4] = {};
                file.read(magic, sizeof(magic));
                if (std::string(magic, sizeof(magic)) != std::string(kDepthAnythingMagic, sizeof(kDepthAnythingMagic))) {
                    throw std::runtime_error("Invalid DEPTH_ANYTHING magic header in: " + bin_path.string());
                }

                uint32_t version = 0;
                uint32_t num_tensors = 0;
                file.read(reinterpret_cast<char*>(&version), sizeof(version));
                file.read(reinterpret_cast<char*>(&num_tensors), sizeof(num_tensors));
                if (version != kDepthAnythingVersion) {
                    throw std::runtime_error("Unsupported DEPTH_ANYTHING version: " + std::to_string(version));
                }

                DC_DepthAnythingWeightStore store;
                store.tensors_.reserve(num_tensors);

                for (uint32_t tensor_index = 0; tensor_index < num_tensors; ++tensor_index) {
                    DC_DepthAnythingTensor tensor;

                    uint32_t name_length = 0;
                    file.read(reinterpret_cast<char*>(&name_length), sizeof(name_length));
                    if (name_length == 0) {
                        throw std::runtime_error("Empty tensor name at index " + std::to_string(tensor_index));
                    }

                    tensor.name.resize(name_length);
                    file.read(tensor.name.data(), static_cast<std::streamsize>(name_length));

                    uint32_t dtype_code = 0;
                    file.read(reinterpret_cast<char*>(&dtype_code), sizeof(dtype_code));
                    if (dtype_code != static_cast<uint32_t>(DC_DepthAnythingWeightDtype::FLOAT32)
                        && dtype_code != static_cast<uint32_t>(DC_DepthAnythingWeightDtype::INT64)) {
                        throw std::runtime_error("Unsupported dtype code " + std::to_string(dtype_code)
                            + " for tensor " + tensor.name);
                    }
                    tensor.dtype = static_cast<DC_DepthAnythingWeightDtype>(dtype_code);

                    uint32_t num_dims = 0;
                    file.read(reinterpret_cast<char*>(&num_dims), sizeof(num_dims));
                    tensor.shape.resize(num_dims);
                    for (uint32_t dim_index = 0; dim_index < num_dims; ++dim_index) {
                        file.read(reinterpret_cast<char*>(&tensor.shape[dim_index]), sizeof(uint32_t));
                    }

                    uint64_t byte_size = 0;
                    file.read(reinterpret_cast<char*>(&byte_size), sizeof(byte_size));
                    tensor.raw_data.resize(static_cast<size_t>(byte_size));
                    if (byte_size > 0) {
                        file.read(reinterpret_cast<char*>(tensor.raw_data.data()),
                            static_cast<std::streamsize>(byte_size));
                    }

                    if (!file) {
                        throw std::runtime_error("Unexpected EOF while reading tensor " + tensor.name);
                    }

                    store.name_to_index_[tensor.name] = store.tensors_.size();
                    store.tensors_.push_back(std::move(tensor));
                }

                return store;
            }

            size_t size() const { return tensors_.size(); }

            const DC_DepthAnythingTensor* find(const std::string& name) const {
                const auto it = name_to_index_.find(name);
                if (it == name_to_index_.end()) {
                    return nullptr;
                }
                return &tensors_.at(it->second);
            }

            std::vector<float> get_float32(const std::string& name) const {
                const DC_DepthAnythingTensor* tensor = find(name);
                if (tensor == nullptr) {
                    throw std::runtime_error("DEPTH_ANYTHING tensor not found: " + name);
                }
                if (tensor->dtype != DC_DepthAnythingWeightDtype::FLOAT32) {
                    throw std::runtime_error("DEPTH_ANYTHING tensor is not float32: " + name);
                }
                if (tensor->raw_data.size() % sizeof(float) != 0) {
                    throw std::runtime_error("Invalid float32 byte size for tensor: " + name);
                }

                std::vector<float> values(tensor->raw_data.size() / sizeof(float));
                std::memcpy(values.data(), tensor->raw_data.data(), tensor->raw_data.size());
                return values;
            }

        private:
            std::vector<DC_DepthAnythingTensor> tensors_;
            std::unordered_map<std::string, size_t> name_to_index_;
        };

        std::vector<float> transpose_onnx_gemm_weights(
            const std::vector<float>& onnx_weights,
            int in_features,
            int out_features) {
            if (static_cast<size_t>(in_features * out_features) != onnx_weights.size()) {
                throw std::runtime_error("Gemm weight size does not match in_features/out_features");
            }

            std::vector<float> transposed(onnx_weights.size());
            for (int out_col = 0; out_col < out_features; ++out_col) {
                for (int in_col = 0; in_col < in_features; ++in_col) {
                    transposed[static_cast<size_t>(out_col * in_features + in_col)] =
                        onnx_weights[static_cast<size_t>(in_col * out_features + out_col)];
                }
            }
            return transposed;
        }

        std::vector<float> convert_conv_oihw_for_mem_order(
            const std::vector<float>& oihw_weights,
            int kernel_size,
            int in_channels,
            int out_channels,
            MEM_ORDER mem_order) {
            if (mem_order == MEM_ORDER::HWC) {
                return convert_weights_to_HWC(oihw_weights, kernel_size, in_channels, out_channels);
            }
            return oihw_weights;
        }


        class YoloWeightStream {
        public:
            virtual ~YoloWeightStream() = default;
            virtual void read_raw(void* dst, std::size_t nbytes) = 0;
        };

        class YoloWeightFileStream final : public YoloWeightStream {
        public:
            explicit YoloWeightFileStream(std::ifstream& file) : m_file(file) {}

            void read_raw(void* dst, std::size_t nbytes) override {
                m_file.read(reinterpret_cast<char*>(dst), static_cast<std::streamsize>(nbytes));
                if (!m_file) {
                    throw std::runtime_error("YOLO weights read failed (file)");
                }
            }

        private:
            std::ifstream& m_file;
        };

        class YoloWeightMemoryStream final : public YoloWeightStream {
        public:
            YoloWeightMemoryStream(const std::uint8_t* data, std::size_t size)
                : m_data(data), m_size(size) {}

            void read_raw(void* dst, std::size_t nbytes) override {
                if (m_data == nullptr || m_pos + nbytes > m_size) {
                    throw std::runtime_error("YOLO weights read past end (memory)");
                }
                std::memcpy(dst, m_data + m_pos, nbytes);
                m_pos += nbytes;
            }

        private:
            const std::uint8_t* m_data;
            std::size_t m_size;
            std::size_t m_pos = 0U;
        };

    } // namespace

    /**
     * @brief Loads weights from a file and assigns them to the network layers.
     */
    template<typename ConvT>
    void load_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        bool verbose) {

        if (weights_format == WeightsFormat::YOLO)
        {
            load_yolo_weights<ConvT>(owas_top_level, weights_file, layers, mem_order, verbose);
        }
        else if (weights_format == WeightsFormat::TENSORFLOW)
        {
            load_convnet_weights<ConvT>(owas_top_level, output_tensor_per_layer, weights_file, layers, mem_order);
        }
        else if (weights_format == WeightsFormat::DEPTH_ANYTHING)
        {
            load_depth_anything_weights<ConvT>(owas_top_level, weights_file, layers, mem_order, verbose);
        }
    }

    template<typename ConvT>
    void load_weights_from_memory(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        WeightsFormat weights_format,
        MEM_ORDER mem_order,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        bool verbose) {

        if (weights_format == WeightsFormat::YOLO) {
            load_yolo_weights_from_memory<ConvT>(
                owas_top_level, weights_data, weights_size, layers, mem_order, verbose);
        }
        else if (weights_format == WeightsFormat::TENSORFLOW) {
            (void)output_tensor_per_layer;
            (void)weights_data;
            (void)weights_size;
            throw std::runtime_error("TensorFlow weights from memory are not supported yet");
        }
        else if (weights_format == WeightsFormat::DEPTH_ANYTHING) {
            (void)output_tensor_per_layer;
            (void)weights_data;
            (void)weights_size;
            throw std::runtime_error("DEPTH_ANYTHING weights from memory are not supported yet");
        }
    }

    /**
     * @brief Converts convolutional layer weights from CHW to HWC format.
     */
    std::vector<float> convert_weights_to_CHW(
        const std::vector<float>& original_weights,
        int kernel_size,
        int in_channels,
        int out_channels
    ) {
        // Create new weights array with same total size
        std::vector<float> new_weights(original_weights.size());

        // Iterate through all dimensions
        for (int kh = 0; kh < kernel_size; ++kh) {
            for (int kw = 0; kw < kernel_size; ++kw) {
                for (int ic = 0; ic < in_channels; ++ic) {
                    for (int oc = 0; oc < out_channels; ++oc) {
                        // Calculate index in original format [kh, kw, ic, oc]
                        int original_idx = ((kh * kernel_size + kw) * in_channels + ic) * out_channels + oc;

                        // Calculate index in new format [oc, ic, kh, kw]
                        int new_idx = ((oc * in_channels + ic) * kernel_size + kh) * kernel_size + kw;

                        // Copy value to new position
                        new_weights[new_idx] = original_weights[original_idx];
                    }
                }
            }
        }

        return new_weights;
    }

    /**
     * @brief Converts convolutional layer weights from CHW to HWC format.
     */
    std::vector<float> convert_weights_to_HWC(
        const std::vector<float>& original_weights,
        int kernel_size,
        int in_channels,
        int out_channels
    ) {
        // Convert from CHW format [out_channels, in_channels, kh, kw]
        // to HWC format [kh, kw, in_channels, out_channels]
        std::vector<float> new_weights(original_weights.size());

        for (int kh = 0; kh < kernel_size; ++kh) {
            for (int kw = 0; kw < kernel_size; ++kw) {
                for (int ic = 0; ic < in_channels; ++ic) {
                    for (int oc = 0; oc < out_channels; ++oc) {
                        // Index in CHW (OIHW): ((oc * in_channels + ic) * kernel_size + kh) * kernel_size + kw
                        int chw_index = ((oc * in_channels + ic) * kernel_size + kh) * kernel_size + kw;

                        // Index in HWC (HWIO): kh * (kernel_size * in_channels * out_channels)
                        //   + kw * (in_channels * out_channels)
                        //   + ic * out_channels + oc
                        int hwc_index = kh * (kernel_size * in_channels * out_channels)
                            + kw * (in_channels * out_channels)
                            + ic * out_channels + oc;

                        new_weights[hwc_index] = original_weights[chw_index];
                    }
                }
            }
        }

        return new_weights;
    }

    template<typename ConvT>
    static void load_yolo_weights_stream_body(
        YoloWeightStream& stream,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose)
    {
        if (layers.empty()) {
            throw std::runtime_error("Network must be built before loading weights.");
        }

        if (verbose) {
            std::cout << "\nExpected Layer Shapes from Config:\n";
            std::cout << "----------------------------------------\n";
        }

        int32_t major = 0;
        int32_t minor = 0;
        int32_t revision = 0;
        stream.read_raw(&major, sizeof(major));
        stream.read_raw(&minor, sizeof(minor));
        stream.read_raw(&revision, sizeof(revision));

        DC_CNN_LOG(
            "CNN weights: Darknet header v%d.%d.%d\r\n",
            static_cast<int>(major),
            static_cast<int>(minor),
            static_cast<int>(revision));

        if (verbose) {
            std::cout << "Loading weights version: " << major << "." << minor << "." << revision << "\n";
        }
        if ((major * 10 + minor) >= 2) {
            uint64_t iseen = 0;
            stream.read_raw(&iseen, sizeof(uint64_t));
        }
        else {
            uint32_t iseen = 0;
            stream.read_raw(&iseen, sizeof(uint32_t));
        }

        size_t conv_layer_idx = 0;
        size_t total_params = 0;

        // Process each layer
        for (size_t i = 0; i < layers.size(); ++i)
        {
            if (layers[i]->get_layer_type() == Layer_Type::CONV) {
                auto conv = dynamic_cast<ConvT*>(layers[i].get());
                const int filters = conv->get_out_channels();
                const int channels = conv->get_in_channels();
                const int kernel_size = conv->get_kernel_size();
                const bool is_output_layer = !conv->uses_batch_norm();

                size_t weights_count;
                if (kernel_size == 1) {
                    weights_count = filters * channels;
                }
                else {
                    weights_count = filters * channels * kernel_size * kernel_size;
                }

                try {
                    // 1. Load biases first (for all layers)
                    std::vector<float> bias(filters);
                    stream.read_raw(bias.data(), filters * sizeof(float));

                    conv->load_bias(bias);

                    // 2. Load batch normalization parameters if present
                    if (!is_output_layer) {
                        std::vector<float> gamma(filters);
                        stream.read_raw(gamma.data(), filters * sizeof(float));

                        std::vector<float> mean(filters);
                        stream.read_raw(mean.data(), filters * sizeof(float));

                        std::vector<float> var(filters);
                        stream.read_raw(var.data(), filters * sizeof(float));

                        std::vector<float> beta(filters, 0.f);
                        conv->set_batch_norm_params(gamma, beta, mean, var);
                    }

                    // 3. Finally load weights
                    std::vector<float> weights(weights_count);
                    stream.read_raw(weights.data(), weights_count * sizeof(float));
                    if (mem_order == MEM_ORDER::HWC) {
                        weights = convert_weights_to_HWC(weights, kernel_size, channels, filters);
                    }

                    conv->load_weights(weights);

                    total_params += weights_count;
                    conv_layer_idx++;

                    if ((conv_layer_idx == 1U) || (conv_layer_idx % 5U == 0U)) {
                        DC_CNN_LOG(
                            "CNN weights: conv %u loaded (%u floats, layer idx %u)\r\n",
                            static_cast<unsigned>(conv_layer_idx),
                            static_cast<unsigned>(weights_count),
                            static_cast<unsigned>(i));
                    }

                    if (verbose) {
                        std::cout << "Successfully loaded " << weights_count << " weights";
                        if (!is_output_layer) {
                            std::cout << " and batch norm parameters";
                        }

                        std::cout << " for layer " << i << std::endl;
                    }
                }
                catch (const std::exception& e) {
                    throw std::runtime_error("Error loading weights for layer " + std::to_string(i) + ": " + e.what());
                }
            }
        }

        DC_CNN_LOG(
            "CNN weights: loaded %u conv layer(s), %u weight coeffs\r\n",
            static_cast<unsigned>(conv_layer_idx),
            static_cast<unsigned>(total_params));

        if (verbose) {
            std::cout << "\nSuccessfully loaded " << total_params << " parameters for "
                << conv_layer_idx << " convolutional layers" << std::endl;
        }
    }

    template<typename ConvT>
    static void load_yolo_weights_stream(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        YoloWeightStream& stream,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose)
    {
        load_yolo_weights_stream_body<ConvT>(stream, layers, mem_order, verbose);

        DC_CNN_LOG("CNN weights: fusing batch-norm into conv (off-chip)...\r\n");
        fuse_conv_batchnorm<ConvT>(owas_top_level, layers, mem_order);
        DC_CNN_LOG("CNN weights: load + fuse complete\r\n");

        if (verbose) {
            std::cout << "\nFusing batch normalization layers into convolutional layers..." << std::endl;
            std::cout << "Batch normalization fusion complete." << std::endl;
        }
    }

    /**
     * @brief Loads YOLO weights from a binary file and assigns them to the network layers.
     */
    template<typename ConvT>
    void load_yolo_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose)
    {
        std::ifstream file(weights_file, std::ios::binary);
        if (!file) {
            throw std::runtime_error("Could not open weights file: " + weights_file);
        }

        if (verbose) {
            file.seekg(0, std::ios::end);
            const auto file_size = file.tellg();
            file.seekg(0, std::ios::beg);
            std::cout << "Weights file size: " << file_size << " bytes\n";
        }

        YoloWeightFileStream stream(file);
        load_yolo_weights_stream<ConvT>(owas_top_level, stream, layers, mem_order, verbose);
    }

    template<typename ConvT>
    void load_yolo_weights_from_memory(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose)
    {
        DC_CNN_LOG(
            "CNN weights: ROM stream %u bytes\r\n",
            static_cast<unsigned>(weights_size));

        if (verbose) {
            std::cout << "Weights ROM size: " << weights_size << " bytes\n";
        }

        YoloWeightMemoryStream stream(weights_data, weights_size);
        load_yolo_weights_stream<ConvT>(owas_top_level, stream, layers, mem_order, verbose);
    }

    /**
     * @brief Fuses batch normalization into convolutional layers.
     */
    template<typename ConvT>
    void fuse_conv_batchnorm(DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        std::vector<std::unique_ptr<DC_Layer>>& layers, MEM_ORDER mem_order) {

        for (size_t i = 0; i < layers.size(); ++i) {
            auto conv_layer = dynamic_cast<ConvT*>(layers[i].get());
            if (!conv_layer) {
                continue;
            }

            conv_layer->enable_bias(true);

            if (!conv_layer->uses_batch_norm())
            {
                owas_top_level.WriteWeightsToOffChip(i, conv_layer->get_weights());
                owas_top_level.WriteBiasToOffChip(i, conv_layer->get_biases());

                continue;
            }
            // Get batch normalization parameters
            const auto& bn_scale = conv_layer->get_bn_gamma();
            const auto& bn_bias = conv_layer->get_bn_beta();
            const auto& bn_mean = conv_layer->get_bn_mean();
            const auto& bn_var = conv_layer->get_bn_var();
            const float bn_eps = conv_layer->get_bn_epsilon(); // Use the layer's epsilon value

            // Get original conv weights and biases
            auto& conv_weights = conv_layer->get_weights();
            auto& conv_biases = conv_layer->get_biases();

            const int out_channels = conv_layer->get_out_channels();
            const int in_channels = conv_layer->get_in_channels();
            const int kernel = conv_layer->get_kernel_size();
            const int num_filters = out_channels;
            const int filter_size = in_channels * kernel * kernel;

            // Ensure conv_biases has the right size (create if not exists)
            if (conv_biases.empty()) {
                conv_biases.resize(num_filters, 0.0f);
            }

            // Fuse batch norm into conv weights and biases
            // For each filter:
            // new_weight = weight * scale / sqrt(var + eps)
            // new_bias = (bias - mean) * scale / sqrt(var + eps) + beta
            for (int f = 0; f < num_filters; ++f) {
                const float scale = bn_scale[f] / std::sqrt(bn_var[f] + bn_eps);

                // Update weights for this filter depending on layout
                if (mem_order == MEM_ORDER::CHW) {
                    // OIHW contiguous per output channel
                    const int start = f * filter_size;
                    for (int j = 0; j < filter_size; ++j) {
                        conv_weights[start + j] *= scale;
                    }
                } else {
                    // HWIO layout: out_channels is innermost, stride across blocks
                    const int blocks = kernel * kernel * in_channels;
                    int idx = f; // first occurrence at offset f
                    for (int b = 0; b < blocks; ++b) {
                        conv_weights[idx] *= scale;
                        idx += num_filters; // jump to next (kh,kw,ic) block
                    }
                }

                // Update bias for this filter
                conv_biases[f] -= bn_mean[f] * scale + bn_bias[f];
            }

            owas_top_level.WriteWeightsToOffChip(i, conv_weights);
			owas_top_level.WriteBiasToOffChip(i, conv_biases);

            // Disable batch normalization since it's now fused
            conv_layer->disable_batch_norm();

            std::cout << "Fused batch normalization into convolutional layer " << i << std::endl;
        }
    }

    template<typename ConvT>
    void fuse_conv_batchnorm_inplace(
        std::vector<std::unique_ptr<DC_Layer>>& layers, MEM_ORDER mem_order) {

        for (size_t i = 0; i < layers.size(); ++i) {
            auto conv_layer = dynamic_cast<ConvT*>(layers[i].get());
            if (!conv_layer) {
                continue;
            }

            conv_layer->enable_bias(true);

            if (!conv_layer->uses_batch_norm()) {
                continue;
            }

            const auto& bn_scale = conv_layer->get_bn_gamma();
            const auto& bn_bias = conv_layer->get_bn_beta();
            const auto& bn_mean = conv_layer->get_bn_mean();
            const auto& bn_var = conv_layer->get_bn_var();
            const float bn_eps = conv_layer->get_bn_epsilon();

            auto& conv_weights = conv_layer->get_weights();
            auto& conv_biases = conv_layer->get_biases();

            const int out_channels = conv_layer->get_out_channels();
            const int in_channels = conv_layer->get_in_channels();
            const int kernel = conv_layer->get_kernel_size();
            const int num_filters = out_channels;
            const int filter_size = in_channels * kernel * kernel;

            if (conv_biases.empty()) {
                conv_biases.resize(static_cast<size_t>(num_filters), 0.0f);
            }

            for (int f = 0; f < num_filters; ++f) {
                const float scale = bn_scale[static_cast<size_t>(f)]
                    / std::sqrt(bn_var[static_cast<size_t>(f)] + bn_eps);

                if (mem_order == MEM_ORDER::CHW) {
                    const int start = f * filter_size;
                    for (int j = 0; j < filter_size; ++j) {
                        conv_weights[static_cast<size_t>(start + j)] *= scale;
                    }
                }
                else {
                    const int blocks = kernel * kernel * in_channels;
                    int idx = f;
                    for (int b = 0; b < blocks; ++b) {
                        conv_weights[static_cast<size_t>(idx)] *= scale;
                        idx += num_filters;
                    }
                }

                conv_biases[static_cast<size_t>(f)] -= bn_mean[static_cast<size_t>(f)] * scale
                    + bn_bias[static_cast<size_t>(f)];
            }

            conv_layer->disable_batch_norm();
        }
    }

    template<typename ConvT>
    void load_yolo_weights_from_memory_cpu(
        const std::uint8_t* weights_data,
        std::size_t weights_size,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose)
    {
        DC_CNN_LOG(
            "CNN weights: ROM stream %u bytes (CPU path)\r\n",
            static_cast<unsigned>(weights_size));

        YoloWeightMemoryStream stream(weights_data, weights_size);
        load_yolo_weights_stream_body<ConvT>(stream, layers, mem_order, verbose);

        DC_CNN_LOG("CNN weights: fusing batch-norm in-place...\r\n");
        fuse_conv_batchnorm_inplace<ConvT>(layers, mem_order);
        DC_CNN_LOG("CNN weights: CPU load + fuse complete\r\n");
    }

    /**
     * @brief Loads weights from a ConvNet weights file and assigns them to the network layers.
     */
    template<typename ConvT>
    void load_convnet_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::vector<DC_Tensor>& output_tensor_per_layer,
        const std::string& filename,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order) {
        std::ifstream file(filename, std::ios::binary);
        if (!file.is_open()) {
            throw std::runtime_error("Failed to open weights file: " + filename);
        }

        std::cout << "Opening weights file: " << filename << std::endl;

        // Read number of weight arrays
        uint32_t num_weights;
        file.read(reinterpret_cast<char*>(&num_weights), sizeof(uint32_t));
        std::cout << "Number of weight arrays: " << num_weights << std::endl;

        // Collect Conv2D and Dense layers
        std::vector<ConvT*> conv_layers;
        std::vector<std::pair<DC_CNNLayer_Dense*, DC_Tensor>> dense_layers;
        std::vector<int> conv_idx_tracker;

        for (auto i = 0u; i < layers.size(); ++i) {
            if (layers[i]->get_layer_type() == Layer_Type::CONV) {
                auto conv = dynamic_cast<ConvT*>(layers[i].get());
                conv_layers.push_back(conv);
				conv_idx_tracker.push_back(i);
            }
            else if (layers[i]->get_layer_type() == Layer_Type::DENSE) {
                auto dense = dynamic_cast<DC_CNNLayer_Dense*>(layers[i].get());
                dense_layers.push_back({ dense,  output_tensor_per_layer[i] });
            }
        }

        size_t conv_idx = 0;
        size_t dense_idx = 0;
        size_t total_weight_params = 0;
        size_t total_bias_params = 0;

        // Read each weight array
        for (uint32_t i = 0; i < num_weights; ++i) {
            // Read number of dimensions
            uint32_t num_dims;
            file.read(reinterpret_cast<char*>(&num_dims), sizeof(uint32_t));

            // Read shape dimensions
            std::vector<uint32_t> shape(num_dims);
            for (uint32_t j = 0; j < num_dims; ++j) {
                file.read(reinterpret_cast<char*>(&shape[j]), sizeof(uint32_t));
            }

            // Read weight data size
            uint64_t data_size;
            file.read(reinterpret_cast<char*>(&data_size), sizeof(uint64_t));

            // Read weight data
            std::vector<float> weight_data(data_size / sizeof(float));
            file.read(reinterpret_cast<char*>(weight_data.data()), data_size);

            // Print shape for debugging
            std::cout << "Weight array " << i << " shape: [";
            for (size_t j = 0; j < shape.size(); ++j) {
                std::cout << shape[j];
                if (j < shape.size() - 1) std::cout << ", ";
            }
            std::cout << "]" << std::endl;

            bool matched = false;
            const size_t param_count = weight_data.size();

            // First 6 arrays are Conv2D weights and biases (3 pairs)
            if (i < 6) {
                if (i % 2 == 0) {  // Conv2D weights
                    if (conv_idx < conv_layers.size()) {
                        auto conv = conv_layers[conv_idx];
                        if (shape.size() == 4 &&
                            shape[0] == 3 && shape[1] == 3 &&  // kernel size
                            shape[2] == static_cast<uint32_t>(conv->get_in_channels()) &&
                            shape[3] == static_cast<uint32_t>(conv->get_out_channels())) {
                            std::cout << "Loading Conv2D weights for layer " << conv_idx << std::endl;
                            conv->load_weights((mem_order == MEM_ORDER::CHW)
                                ? convert_weights_to_CHW(weight_data, shape[0], shape[2], shape[3])
                                : weight_data);
                            owas_top_level.WriteWeightsToOffChip(conv_idx_tracker[conv_idx], conv->get_weights());
                            matched = true;
                            total_weight_params += param_count;
                        }
                    }
                }
                else {  // Conv2D bias
                    if (conv_idx < conv_layers.size()) {
                        auto conv = conv_layers[conv_idx];
                        if (shape.size() == 1 && shape[0] == static_cast<uint32_t>(conv->get_out_channels())) {
                            std::cout << "Loading Conv2D bias for layer " << conv_idx << std::endl;
                            conv->load_bias(weight_data);
                            owas_top_level.WriteBiasToOffChip(conv_idx_tracker[conv_idx], conv->get_biases());
                            matched = true;
                            conv_idx++;  // Move to next Conv2D layer after loading bias
                            total_bias_params += param_count;
                        }
                    }
                }
            }
            // Last 4 arrays are Dense weights and biases (2 pairs)
            else {
                if ((i - 6) % 2 == 0) {  // Dense weights
                    if (dense_idx < dense_layers.size()) {
                        auto dense = dense_layers[dense_idx].first;
                        // Convert weights based on memory order
                        const auto& input_tensor = dense_layers[dense_idx].second;
                        const auto converted_weights = (mem_order == MEM_ORDER::CHW) 
                            ? convert_weights_to_CHW(weight_data, input_tensor.m_height, input_tensor.m_channels, shape[1])
                            : weight_data;

                        dense->load_weights(converted_weights);
                        matched = true;
                        total_weight_params += param_count;
                    }
                }
                else {  // Dense bias
                    if (dense_idx < dense_layers.size()) {
                        auto dense = dense_layers[dense_idx].first;
                        std::cout << "Loading Dense bias for layer " << dense_idx << std::endl;
                        dense->load_bias(weight_data);
                        matched = true;
                        dense_idx++;  // Move to next Dense layer after loading bias
                        total_bias_params += param_count;
                    }
                }
            }

            if (!matched) {
                std::cout << "Warning: Could not find matching layer for weight array " << i
                    << " with shape [";
                for (size_t j = 0; j < shape.size(); ++j) {
                    std::cout << shape[j];
                    if (j < shape.size() - 1) std::cout << ", ";
                }
                std::cout << "]" << std::endl;
            }
        }

        // Verify all layers received their weights
        bool all_loaded = true;
        for (size_t i = 0; i < conv_layers.size(); ++i) {
            if (!conv_layers[i]->weights_loaded() || !conv_layers[i]->bias_loaded()) {
                std::cout << "Warning: Conv2D layer " << i << " missing weights or bias" << std::endl;
                all_loaded = false;
            }
        }
        for (size_t i = 0; i < dense_layers.size(); ++i) {
            if (!dense_layers[i].first->weights_loaded() || !dense_layers[i].first->bias_loaded()) {
                std::cout << "Warning: Dense layer " << i << " missing weights or bias" << std::endl;
                all_loaded = false;
            }
        }

        if (all_loaded) {
            std::cout << "All layers loaded successfully" << std::endl;
        }

        const size_t total_params = total_weight_params + total_bias_params;

        std::cout << "Total ConvNet weight parameters: " << total_weight_params << std::endl;
        std::cout << "Total ConvNet bias parameters: " << total_bias_params << std::endl;
        std::cout << "Total ConvNet parameters (weights + biases): " << total_params << std::endl;

        file.close();
    }

    template<typename ConvT>
    void load_depth_anything_weights(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const std::string& weights_file,
        std::vector<std::unique_ptr<DC_Layer>>& layers,
        MEM_ORDER mem_order,
        bool verbose) {
        if (layers.empty()) {
            throw std::runtime_error("Network must be built before loading DEPTH_ANYTHING weights.");
        }

        const std::filesystem::path bin_path(weights_file);

        if (verbose) {
            std::cout << "Loading sequential weights from: " << bin_path << std::endl;
        }

        std::ifstream file(weights_file, std::ios::binary);
        if (!file.is_open()) {
            throw std::runtime_error("Failed to open weights file: " + weights_file);
        }

        // Skip YOLO-style header
        int32_t major = 0, minor = 0, revision = 0;
        uint64_t iseen = 0;
        file.read(reinterpret_cast<char*>(&major), sizeof(major));
        file.read(reinterpret_cast<char*>(&minor), sizeof(minor));
        file.read(reinterpret_cast<char*>(&revision), sizeof(revision));
        file.read(reinterpret_cast<char*>(&iseen), sizeof(iseen));

        size_t loaded_conv_blocks = 0;
        size_t loaded_gemm_blocks = 0;
        size_t loaded_norm_blocks = 0;
        size_t loaded_operand_blocks = 0;
        size_t loaded_dense_blocks = 0;
        size_t total_float_params = 0;

        auto read_floats = [&](size_t count) -> std::vector<float> {
            if (count == 0) return {};
            std::vector<float> data(count);
            file.read(reinterpret_cast<char*>(data.data()), count * sizeof(float));
            if (!file) {
                throw std::runtime_error("Unexpected end of file while reading weights!");
            }
            total_float_params += count;
            return data;
        };

        for (size_t i = 0; i < layers.size(); ++i) {
            auto& layer = layers[i];
            const auto type = layer->get_layer_type();

            if (type == Layer_Type::CONV) {
                auto conv = dynamic_cast<ConvT*>(layer.get());
                if (!conv) {
                    throw std::runtime_error("Layer type mismatch at index " + std::to_string(i));
                }

                const int out_channels = conv->get_out_channels();
                const int in_channels = conv->get_in_channels();
                const int kernel_h = conv->get_kernel_size();
                const int kernel_w = conv->get_kernel_size();
                
                auto weight_data = read_floats(out_channels * in_channels * kernel_h * kernel_w);
                auto conv_weights = convert_conv_oihw_for_mem_order(
                    weight_data,
                    kernel_h,
                    in_channels,
                    out_channels,
                    mem_order);
                conv->load_weights(conv_weights);

                if (conv->get_use_bias()) {
                    auto bias_data = read_floats(out_channels);
                    conv->load_bias(bias_data);
                    owas_top_level.WriteBiasToOffChip(i, conv->get_biases());
                }
                owas_top_level.WriteWeightsToOffChip(i, conv->get_weights());

                ++loaded_conv_blocks;
                if (verbose) {
                    std::cout << "Loaded Conv weights sequentially for layer " << i << std::endl;
                }
            }
            else if (type == Layer_Type::DECONV2D) {
                auto deconv = dynamic_cast<DC_CNNLayer_DeConv2D*>(layer.get());
                if (!deconv) {
                    throw std::runtime_error("Layer type mismatch at index " + std::to_string(i));
                }

                const int out_channels = deconv->get_out_channels();
                const int in_channels = deconv->get_in_channels();
                const int kernel_h = deconv->get_kernel_size();
                const int kernel_w = deconv->get_kernel_size();
                
                auto weight_data = read_floats(in_channels * out_channels * kernel_h * kernel_w);
                // ConvTranspose weights are IOHW [in, out, kh, kw]. Keep that layout for both
                // CHW and HWC activation tensors — the DeConv2D kernel indexes weights as IOHW.
                deconv->load_weights(weight_data);

                if (deconv->get_use_bias()) {
                    auto bias_data = read_floats(out_channels);
                    deconv->load_bias(bias_data);
                }

                ++loaded_conv_blocks;
                if (verbose) {
                    std::cout << "Loaded DeConv2D weights sequentially for layer " << i << std::endl;
                }
            }
            else if (type == Layer_Type::GEMM) {
                auto gemm = dynamic_cast<DC_CNNLayer_Gemm*>(layer.get());
                if (!gemm) {
                    throw std::runtime_error("Layer type mismatch at index " + std::to_string(i));
                }

                const int in_features = gemm->get_in_features();
                const int out_features = gemm->get_out_features();

                if (gemm->get_use_bias()) {
                    auto bias_data = read_floats(out_features);
                    gemm->load_bias(bias_data);
                }

                auto weight_data = read_floats(in_features * out_features);
                // ONNX Gemm -> OI (CHW 1x1), then convert to HWC when required
                auto gemm_weights = convert_conv_oihw_for_mem_order(
                    transpose_onnx_gemm_weights(weight_data, in_features, out_features),
                    1, // kernel_size
                    in_features,
                    out_features,
                    mem_order);
                gemm->load_weights(gemm_weights);
                
                ++loaded_gemm_blocks;
                if (verbose) {
                    std::cout << "Loaded Gemm weights sequentially for layer " << i << std::endl;
                }
            }
            else if (type == Layer_Type::LAYERNORM) {
                auto layernorm = dynamic_cast<DC_CNNLayer_LayerNorm*>(layer.get());
                if (!layernorm) {
                    throw std::runtime_error("Layer type mismatch at index " + std::to_string(i));
                }

                const size_t norm_size = layernorm->get_normalized_size();
                layernorm->load_gamma(read_floats(norm_size));
                layernorm->load_beta(read_floats(norm_size));
                
                ++loaded_norm_blocks;
                if (verbose) {
                    std::cout << "Loaded LayerNormalization weights sequentially for layer " << i << std::endl;
                }
            }
            
            // Check for operands in Add, Mul, Concat
            if (layer->has_operand()) {
                const auto& shape = layer->get_operand_shape();
                size_t num_elements = 1;
                for (int dim : shape) {
                    num_elements *= dim;
                }
                
                auto operand_values = read_floats(num_elements);

                if (type == Layer_Type::CONCAT) {
                    auto concat = dynamic_cast<DC_CNNLayer_Concat*>(layer.get());
                    concat->load_constant_operand(operand_values, shape);
                }
                else if (type == Layer_Type::ADD) {
                    auto add = dynamic_cast<DC_CNNLayer_Add*>(layer.get());
                    add->load_operand(operand_values);
                }
                else if (type == Layer_Type::MUL) {
                    auto mul = dynamic_cast<DC_CNNLayer_Mul*>(layer.get());
                    mul->load_operand(operand_values);
                }

                ++loaded_operand_blocks;
                if (verbose) {
                    std::cout << "Loaded operand sequentially for layer " << i << " (size: " << num_elements << ")" << std::endl;
                }
            }
        }

        if (verbose) {
            std::cout << "Sequential weight loading complete." << std::endl;
            std::cout << "  Conv / ConvTranspose blocks: " << loaded_conv_blocks << std::endl;
            std::cout << "  Gemm blocks: " << loaded_gemm_blocks << std::endl;
            std::cout << "  Normalization blocks: " << loaded_norm_blocks << std::endl;
            std::cout << "  Operand blocks: " << loaded_operand_blocks << std::endl;
            std::cout << "  Total float parameters assigned: " << total_float_params << std::endl;
        }
    }

} // namespace DC_ConvNet 

// Explicit template instantiations
// NOTE: The template definition lives in this .cpp, so we must explicitly instantiate the
// combinations that are used from other translation units (e.g., src/modules/utils/DC_network_builder.cpp).
template void DC_ConvNet::load_weights<DC_ConvNet::DC_FifoCommandBuilder_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::vector<DC_Tensor>& output_tensor_per_layer,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    const std::string& weights_file,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    bool verbose);

template void DC_ConvNet::load_weights<DC_ConvNet::DC_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::vector<DC_Tensor>& output_tensor_per_layer,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    const std::string& weights_file,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    bool verbose);

template void DC_ConvNet::load_weights_from_memory<DC_ConvNet::DC_FifoCommandBuilder_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::vector<DC_Tensor>& output_tensor_per_layer,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    bool verbose);

template void DC_ConvNet::load_weights_from_memory<DC_ConvNet::DC_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::vector<DC_Tensor>& output_tensor_per_layer,
    WeightsFormat weights_format,
    MEM_ORDER mem_order,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    bool verbose);

template void DC_ConvNet::load_yolo_weights_from_memory<DC_ConvNet::DC_FifoCommandBuilder_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order,
    bool verbose);

template void DC_ConvNet::load_yolo_weights_from_memory<DC_ConvNet::DC_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order,
    bool verbose);

template void DC_ConvNet::fuse_conv_batchnorm_inplace<DC_ConvNet::DC_CNNLayer_Conv2D>(
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order);

template void DC_ConvNet::load_yolo_weights_from_memory_cpu<DC_ConvNet::DC_CNNLayer_Conv2D>(
    const std::uint8_t* weights_data,
    std::size_t weights_size,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order,
    bool verbose);

template void DC_ConvNet::load_depth_anything_weights<DC_ConvNet::DC_FifoCommandBuilder_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::string& weights_file,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order,
    bool verbose);

template void DC_ConvNet::load_depth_anything_weights<DC_ConvNet::DC_CNNLayer_Conv2D>(
    DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
    const std::string& weights_file,
    std::vector<std::unique_ptr<DC_Layer>>& layers,
    MEM_ORDER mem_order,
    bool verbose);