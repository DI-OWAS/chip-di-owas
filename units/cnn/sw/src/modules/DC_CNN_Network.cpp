#include "DC_CNN_Network.h"
#include "DC_OWAS_TopLevel.h"
#include "DC_CNN_Accelerator_Const.h"
#include "DC_layer.h"

#include <algorithm>
namespace DC_ConvNet {

    void DC_CNN_Network::set_layers(std::vector<std::unique_ptr<DC_Layer>>&& layers) {
        m_layers = std::move(layers);
    }

    std::vector<DC_Tensor> DC_CNN_Network::execute_classification_task(
        DC_OWAS::DC_OWAS_TopLevel& owas_top_level,
        const DC_Tensor& input_image, 
        Layer_Type output_layer) {

        DC_HW_Params_Global global_params;
        
        global_params.m_mem_order_code = input_image.m_mem_order;
        global_params.m_number_of_rows_to_load = number_of_rows_to_load;

        owas_top_level.GetAccelerator().SetGlobalParams(global_params);

        std::vector<DC_Tensor> layer_outputs;
        std::vector<DC_Tensor> net_outputs;

        owas_top_level.GetAccelerator().ResetCommandFifo();

        owas_top_level.WriteInputToOffChip(input_image.m_data);

        DC_Tensor current = input_image;
        current.m_data.clear();
        current.m_input_mem_seeks = owas_top_level.m_outputs_mem_seeks[0];
        current.m_output_mem_seeks = current.m_input_mem_seeks + current.get_tensor_size();

        for (auto i = 0u; i < m_layers.size(); ++i) {

            current.m_weights_mem_seeks = owas_top_level.m_weights_mem_seeks[i];
            current.m_biases_mem_seeks = owas_top_level.m_biases_mem_seeks[i];

            const auto& layer = m_layers[i];

            std::list<std::unique_ptr<DC_CNN_HW_Command>> cmds;

            if (layer->get_layer_type() == Layer_Type::ROUTE || layer->get_layer_type() == Layer_Type::SHORTCUT) {
                auto layers_params = layer->build_layer_parameter_set(layer_outputs);
                
                for (auto& layer_params : layers_params)
                    layer_params.m_layer_id = owas_top_level.GetAccelerator().PushBackLayerParams(layer_params);

                cmds = layer->build_fifo_commands(current, layers_params);
            }
            else if (layer->get_layer_type() != output_layer) {
                auto layer_params = layer->build_layer_parameter_set(current);

                layer_params.m_layer_id = owas_top_level.GetAccelerator().PushBackLayerParams(layer_params);

                cmds = layer->build_fifo_commands(current, layer_params);
            }

            for (auto cmd_it = cmds.begin(); cmd_it != cmds.end(); ++cmd_it) {
                owas_top_level.GetAccelerator().PushBackCommand(std::move(*cmd_it));
            }

            layer_outputs.push_back(current);

            if (layer->get_layer_type() == output_layer)
            {
                net_outputs.push_back(current);

                current.m_output_mem_seeks = current.m_output_mem_seeks + current.get_tensor_size();

                continue;
            }

            current.m_input_mem_seeks = current.m_output_mem_seeks;
            current.m_output_mem_seeks = current.m_input_mem_seeks + current.get_tensor_size();
        }

		//ON AI ACCELERATOR PROCESSING
        owas_top_level.m_cnn_accelerator.ProcessCommandFifo();

		//ON CPU PROCESSING FOR FLATTEN, DENSE, SOFTMAX AND YOLO LAYERS
        auto flatten_layer = std::find_if(
            m_layers.begin(), m_layers.end(),
            [](const std::unique_ptr<DC_Layer>& layer) {
                return layer->get_layer_type() == Layer_Type::FLATTEN;
            });

        if (flatten_layer != m_layers.end())
        {
			auto flatten_layer_id = std::distance(m_layers.begin(), flatten_layer);

            layer_outputs[flatten_layer_id - 1].m_data =
                owas_top_level.ReadOutputsFromOffChipByAddr(
                    layer_outputs[flatten_layer_id - 1].m_output_mem_seeks
                    , layer_outputs[flatten_layer_id - 1].m_height * layer_outputs[flatten_layer_id - 1].m_width * layer_outputs[flatten_layer_id - 1].m_channels);

            for (size_t i = static_cast<size_t>(flatten_layer_id); i < m_layers.size(); ++i)
            {
                layer_outputs[i] = m_layers[i]->forward(layer_outputs[i - 1]);  

                if (m_layers[i]->get_layer_type() == output_layer)
                {
                    net_outputs[0] = layer_outputs[i];
				}
            }

            return net_outputs;
        }

        auto out_layer_id = 0u;

        for (auto& layer : m_layers)
        {
            if (layer->get_layer_type() != output_layer)
                continue;

            net_outputs[out_layer_id].m_data =
                owas_top_level.ReadOutputsFromOffChipByAddr(
                    net_outputs[out_layer_id].m_input_mem_seeks
                    , net_outputs[out_layer_id].m_height * net_outputs[out_layer_id].m_width * net_outputs[out_layer_id].m_channels);

            net_outputs[out_layer_id] = layer->forward(net_outputs[out_layer_id]);

            ++out_layer_id;
        }

        return net_outputs;
    }

    std::vector<DC_Tensor> DC_CNN_Network::execute_classification_task(
        const DC_Tensor& input_image, Layer_Type output_layer) {
        std::vector<DC_Tensor> layer_outputs;
        std::vector<DC_Tensor> net_outputs;

        DC_Tensor current = input_image;

/*         DC_CNN_LOG(
            "CNN infer: start %dx%dx%d HWC, %u layer(s), target=%s\r\n",
            input_image.m_height,
            input_image.m_width,
            input_image.m_channels,
            static_cast<unsigned>(m_layers.size()),
            layerTypeToString(output_layer).c_str()); */

        for (std::size_t layer_idx = 0U; layer_idx < m_layers.size(); ++layer_idx) {
            const auto& layer = m_layers[layer_idx];
            const auto layer_type = layer->get_layer_type();

/*             if ((layer_idx == 0U) || (layer_idx % 8U == 0U) || (layer_type == Layer_Type::CONV)
                || (layer_type == output_layer)) {
                DC_CNN_LOG(
                    "CNN infer: layer %u/%u %s\r\n",
                    static_cast<unsigned>(layer_idx + 1U),
                    static_cast<unsigned>(m_layers.size()),
                    layerTypeToString(layer_type).c_str());
            } */

            if (layer->requires_layer_outputs()) {
                current = layer->forward(layer_outputs);
            }
            else {
                current = layer->forward(current);
            }

            layer_outputs.push_back(current);

            if (layer_type == output_layer)
            {
                net_outputs.push_back(current);
            }
        }

/*         DC_CNN_LOG(
            "CNN infer: forward complete (%u output tensor(s))\r\n",
            static_cast<unsigned>(net_outputs.size())); */

        return net_outputs;
    }
} // namespace DC_ConvNet 