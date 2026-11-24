/******************************************************************************
 * @file    utils/DC_embedded_yolo.h
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

#pragma once

#include "DC_CNN_Network.h"
#include "DC_config_parser.h"

#include <cstddef>
#include <cstdint>

namespace DC_ConvNet {

/**
 * @brief ROM-resident YOLOv4-tiny cfg and Darknet weights (no filesystem).
 */
struct DC_EmbeddedYoloAssets {
    const std::uint8_t* cfg_data = nullptr;
    std::size_t cfg_size = 0U;
    const std::uint8_t* weights_data = nullptr;
    std::size_t weights_size = 0U;
};

/**
 * @brief Parse embedded cfg, build layers, load weights from ROM, attach to @p net.
 *
 * Uses COMPUTE_IN_LAYERS (CPU) Conv/Pool/Route/Upsample templates and HWC layout.
 *
 * @return true on success; false on exception (logged when @p verbose).
 */
bool init_yolov4_tiny_from_rom(
    DC_CNN_Network& net,
    const DC_EmbeddedYoloAssets& assets,
    bool verbose = false,
    DC_NetConfig* out_net_config = nullptr);

} /* namespace DC_ConvNet */
