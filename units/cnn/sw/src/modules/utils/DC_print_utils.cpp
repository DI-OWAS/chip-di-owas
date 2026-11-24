#include "DC_print_utils.h"
#include "DC_yolo_utils.h"
#include "DC_depth_utils.h"

#include <iostream>
#include <numeric>
#include <algorithm>
#include <iomanip>

/**
 * @brief Visualizes the output of a TensorFlow model by displaying the top 5 class predictions.
 */
void DC_ConvNet::visualize_tensorflow_output(const std::vector<DC_ConvNet::DC_Tensor>& outputs)
{
    const auto probs = outputs[0];

    // Create indices for sorting
    std::vector<size_t> indices(probs.m_data.size());
    std::iota(indices.begin(), indices.end(), 0);

    // Sort indices based on probabilities (descending order)
    std::sort(indices.begin(), indices.end(), [&probs](size_t i1, size_t i2) {
        return probs.m_data[i1] > probs.m_data[i2];
        });

    // Define class names for CIFAR-10
    std::vector<std::string> class_names = {
        "airplane", "automobile", "bird", "cat", "deer",
        "dog", "frog", "horse", "ship", "truck"
    };

    // Display top 5 predictions
    std::cout << "\nTOP 5 PREDICTIONS:" << std::endl;
    std::cout << "--------------------------------------------------" << std::endl;
    std::cout << "Rank  Class               Probability" << std::endl;
    std::cout << "--------------------------------------------------" << std::endl;
    for (size_t i = 0; i < std::min(size_t(5), indices.size()); ++i) {
        size_t idx = indices[i];
        std::cout << std::left << i + 1 << "     " << std::setw(20) << class_names[idx] << " ";
        std::cout << std::right << std::fixed << std::setprecision(6) << probs.m_data[idx] << std::endl;
    }
    std::cout << "--------------------------------------------------" << std::endl;
}

/**
 * @brief Visualizes the output of a CNN model by displaying the top 5 class predictions.
 */
void DC_ConvNet::visualize_cnn_outputs(int input_id, const DC_Tensor& input_image
    , const std::vector<DC_Tensor>& net_outputs
    , WeightsFormat weights_format
    , const std::string& config_file) {

    switch (weights_format)
    {
    case WeightsFormat::YOLO:
        DC_YoloUtils::visualize_yolo_output(input_id, input_image, net_outputs, parse_network_config(config_file));
        break;
    case WeightsFormat::TENSORFLOW:
        visualize_tensorflow_output(net_outputs);
        break;
    case WeightsFormat::DEPTH_ANYTHING:
        DC_DepthUtils::visualize_depth_output(input_id, input_image, net_outputs, parse_network_config(config_file));
        break;
    default:
        break;
    }
}