/******************************************************************************
 * @file    DC_baremetal_log.h
 * @authors JiaWei Wang
 *          DC Vision Systems GmbH
 * @author j.wang@dc-vision.com
 * @brief   UART-friendly CNN progress logging on bare-metal (printf, no iostream)
 * @version 0.1.0
 * @date    2026-05-26
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

#include <cstdio>

#ifdef TARGET_OS_BAREMETAL

/* newlib nano often lacks %zu; use %u with unsigned casts in format strings. */
/**
 * @brief UART-friendly printf-based progress log (enabled on bare-metal builds)
 *
 * Expands to std::printf on TARGET_OS_BAREMETAL; no-op otherwise.
 */
#define DC_CNN_LOG(...) \
    do { \
        (void)std::printf(__VA_ARGS__); \
    } while (0)

#else

/**
 * @brief UART-friendly printf-based progress log (enabled on bare-metal builds)
 *
 * Expands to std::printf on TARGET_OS_BAREMETAL; no-op otherwise.
 */
#define DC_CNN_LOG(...) \
    do { \
    } while (0)

#endif /* TARGET_OS_BAREMETAL */
