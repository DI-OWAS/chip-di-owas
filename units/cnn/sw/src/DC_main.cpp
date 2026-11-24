#include "DC_CNN.h"
#include "DC_OWAS_TopLevel.h"

#include <chrono>

using namespace DC_ConvNet;

auto verbose = true;

MEM_ORDER mem_order = MEM_ORDER::HWC;

void print_usage(const char* program_name) {
    std::cout << "Usage: " << program_name << " <config_file_path>" << std::endl;
}

void execute_core(const DC_JsonConfig& cnn_net_conf, const std::vector<DC_Tensor>& input_images)
{
    DC_OWAS::DC_OWAS_TopLevel OWAS_top_level;

#ifdef COMPUTE_IN_FIFO_QUEUE
    auto layers = DC_ConvNet::build_cnn_layers_from_config<DC_FifoCommandBuilder_CNNLayer_Conv2D
        , DC_FifoCommandBuilder_CNNLayer_MaxPool2D
        , DC_FifoCommandBuilder_CNNLayer_Route
        , DC_FifoCommandBuilder_CNNLayer_Upsample>(
            OWAS_top_level
            , cnn_net_conf.network_topology_file
            , cnn_net_conf.weights_file
            , cnn_net_conf.get_weights_format()
            , mem_order
            , verbose);
#endif // COMPUTE_IN_FIFO_QUEUE
#ifdef COMPUTE_IN_LAYERS
    auto layers = DC_ConvNet::build_cnn_layers_from_config<DC_CNNLayer_Conv2D
        , DC_CNNLayer_MaxPool2D
        , DC_CNNLayer_Route
        , DC_CNNLayer_Upsample>(
            OWAS_top_level
            , cnn_net_conf.network_topology_file
            , cnn_net_conf.weights_file
            , cnn_net_conf.get_weights_format()
            , mem_order
			, verbose);
#endif // COMPUTE_IN_LAYERS

    DC_CNN_Network cnn_net;
    cnn_net.set_layers(std::move(layers));

    for (const auto& input_image : input_images) {

        // Reset any existing performance statistics
        DC_PerformanceStats::getInstance().resetAllStats();

        const auto inference_start_time = std::chrono::high_resolution_clock::now();
#ifdef COMPUTE_IN_FIFO_QUEUE
        const auto net_outputs = cnn_net.execute_classification_task(OWAS_top_level, input_image, cnn_net_conf.get_output_layer());
#endif // COMPUTE_IN_FIFO_QUEUE
#ifdef COMPUTE_IN_LAYERS
		const auto net_outputs = cnn_net.execute_classification_task(input_image, cnn_net_conf.get_output_layer());
#endif // COMPUTE_IN_LAYERS
        const auto inference_elapsed_ms = std::chrono::duration<double, std::milli>(
            std::chrono::high_resolution_clock::now() - inference_start_time).count();

        if (verbose) {
            const auto input_id = static_cast<int>(std::distance(input_images.data(), &input_image));

            visualize_cnn_outputs(input_id, input_image, net_outputs, cnn_net_conf.get_weights_format(), cnn_net_conf.network_topology_file);

            std::cout << "\n===== CNN Inference Time =====\n"
                      << "Total execution time: " << inference_elapsed_ms / 1000 << " s\n" << std::endl;

            std::cout << "\n===== CNN Performance Statistics =====\n" << std::endl;
            std::string report = DC_PerformanceStats::getInstance().generateReport(true);
            std::cout << report << std::endl;
        }
    }
}

int main(int argc, char* argv[])
{
    // Check if config file path is provided
    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }

    const auto config = DC_ConvNet::parse_json_config(argv[1]);
    const auto inputs = DC_ImageUtils::get_images(config.image_inputs_dir, config.get_weights_format(), mem_order);
    execute_core(config, inputs);

    return 0;
}

