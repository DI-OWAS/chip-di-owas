// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS memory map (see units/top/src/rtl/diowas_top.v) and register access

#ifndef DIOWAS_MEMMAP_H
#define DIOWAS_MEMMAP_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t*)(addr))

#define OCTRAM_BASE 0x20000000U // octal PSRAM, 64 MB window (4x APS12808L)
#define CRYPTO_BASE 0xF5000000U // crypto core registers

#endif // DIOWAS_MEMMAP_H
