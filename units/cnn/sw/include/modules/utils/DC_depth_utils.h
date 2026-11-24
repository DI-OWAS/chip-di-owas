/******************************************************************************
 * @file    DC_depth_utils.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Utility functions for Depth Anything depth-map post-processing
 * @version 1.0.0
 * @date    2025-07-02
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
#include "DC_config_parser.h"

#include <vector>

namespace DC_ConvNet {

/**
 * @brief Utility class for Depth Anything inference post-processing.
 */
class DC_DepthUtils final {
public:
    /**
     * @brief Converts raw network depth output into a displayable depth image.
     *
     * Resizes the predicted depth map to the input image size, applies per-image
     * min-max normalization, and saves an 8-bit grayscale PNG.
     */
    static void visualize_depth_output(int input_id, const DC_Tensor& input_image,
        const std::vector<DC_Tensor>& outputs, const DC_NetConfig& net_conf);
};

} // namespace DC_ConvNet
