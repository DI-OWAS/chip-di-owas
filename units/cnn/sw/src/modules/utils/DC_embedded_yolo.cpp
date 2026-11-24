/******************************************************************************
 * @file    utils/DC_embedded_yolo.cpp
 * @authors JiaWei Wang
 *          DC Vision Systems GmbH
 * @author j.wang@dc-vision.com
 * @brief   Build YOLOv4-tiny from ROM-embedded .cfg / .weights buffers
 * @version 0.1.0
 * @date    2026-05-22
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (c) 2026 DC Vision Systems GmbH
 ******************************************************************************/

#include "DC_embedded_yolo.h"

#include "DC_baremetal_log.h"
#include "DC_config_parser.h"
#include "DC_network_builder.h"
#include "DC_CNNLayer_Conv2D.h"
#include "DC_CNNLayer_MaxPool2D.h"
#include "DC_CNNLayer_Route.h"
#include "DC_CNNLayer_Upsample.h"

#include <string>

namespace DC_ConvNet {

bool init_yolov4_tiny_from_rom(
    DC_CNN_Network& net,
    const DC_EmbeddedYoloAssets& assets,
    bool verbose,
    DC_NetConfig* out_net_config)
{
    if (assets.cfg_data == nullptr || assets.cfg_size == 0U
        || assets.weights_data == nullptr || assets.weights_size == 0U) {
        if (verbose) {
            (void)std::printf("init_yolov4_tiny_from_rom: invalid embedded asset pointers\r\n");
        }
        return false;
    }

    try {
        DC_CNN_LOG(
            "CNN ROM: cfg %u bytes, weights %u bytes\r\n",
            static_cast<unsigned>(assets.cfg_size),
            static_cast<unsigned>(assets.weights_size));

        DC_CNN_LOG("CNN: parsing yolov4-tiny.cfg from ROM...\r\n");
        const auto net_conf = parse_network_config_from_memory(
            reinterpret_cast<const char*>(assets.cfg_data),
            assets.cfg_size);
        if (out_net_config != nullptr) {
            *out_net_config = net_conf;
        }
        DC_CNN_LOG(
            "CNN: cfg OK — input %dx%dx%d, %u layer entries\r\n",
            net_conf.width,
            net_conf.height,
            net_conf.channels,
            static_cast<unsigned>(net_conf.layers.size()));

        DC_CNN_LOG("CNN: building layer graph (CPU, no OWAS)...\r\n");
        auto layers = build_cnn_layers_from_net_config_cpu<
            DC_CNNLayer_Conv2D,
            DC_CNNLayer_MaxPool2D,
            DC_CNNLayer_Route,
            DC_CNNLayer_Upsample>(
            net_conf,
            assets.weights_data,
            assets.weights_size,
            WeightsFormat::YOLO,
            MEM_ORDER::HWC,
            false,
            std::string("embedded/yolov4-tiny.cfg"));

        net.set_layers(std::move(layers));

        DC_CNN_LOG("CNN: init complete — network ready for inference\r\n");

        if (verbose) {
            (void)std::printf(
                "init_yolov4_tiny_from_rom: network ready (cfg %u bytes, weights %u bytes)\r\n",
                static_cast<unsigned>(assets.cfg_size),
                static_cast<unsigned>(assets.weights_size));
        }

        return true;
    }
    catch (const std::exception& ex) {
        DC_CNN_LOG("init_yolov4_tiny_from_rom failed: %s\r\n", ex.what());
        (void)verbose;
        return false;
    }
}

} /* namespace DC_ConvNet */
