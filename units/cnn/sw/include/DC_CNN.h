/******************************************************************************
 * @file    DC_CNN.h
 * @authors Oleksandr Karpenko, Frederik Lange, Maximilian Singh
 *          DC Vision Systems GmbH
 * @brief   Main include file for DC Vision CNN library
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

/**
 * @defgroup dc_cnn_api DC Vision CNN Library
 * @brief Umbrella include for network execution, builders, layers, stats, and FIFO command builders.
 *
 * Include this header to pull in the primary public CNN API surfaces used by host
 * and embedded applications.
 */

#include "DC_image_utils.h"
#include "DC_network_builder.h"
#include "DC_print_utils.h"
#include "DC_CNN_Network.h"
#include "DC_PerformanceStats.h"

#include "DC_FifoCommandBuilder_CNNLayer_Conv2D.h"
#include "DC_FifoCommandBuilder_CNNLayer_MaxPool2D.h"
#include "DC_FifoCommandBuilder_CNNLayer_Route.h"
#include "DC_FifoCommandBuilder_CNNLayer_Upsample.h"
#include "DC_CNNLayer_Conv2D.h"
#include "DC_CNNLayer_MaxPool2D.h"
#include "DC_CNNLayer_Route.h"
#include "DC_CNNLayer_Upsample.h"

#include <iostream>