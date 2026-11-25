// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS crypto core: registers and DMA helpers for the CTR and bypass (copy) modes,
// see units/crypto_core/docs/cryptoCore_documentation.md

#ifndef DIOWAS_CRYPTO_CORE_H
#define DIOWAS_CRYPTO_CORE_H

#include <stdint.h>
#include "memmap.h"

/**********************************************************************//**
 * @name Registers
 **************************************************************************/
/**@{*/
#define CRYPTO_CTRL       REG32(CRYPTO_BASE + 0x00U)
#define CRYPTO_STATUS     REG32(CRYPTO_BASE + 0x04U)
#define CRYPTO_CTR_IV0    REG32(CRYPTO_BASE + 0x40U) // IV[31:0]. Writing an IV word resets the counter.
#define CRYPTO_CTR_IV1    REG32(CRYPTO_BASE + 0x44U) // IV[63:32]
#define CRYPTO_CTR_IV2    REG32(CRYPTO_BASE + 0x48U) // IV[95:64]
#define CRYPTO_SRC_ADDR   REG32(CRYPTO_BASE + 0x50U)
#define CRYPTO_DST_ADDR   REG32(CRYPTO_BASE + 0x54U)
#define CRYPTO_DMA_BLOCKS REG32(CRYPTO_BASE + 0x58U) // length in 16 byte blocks
#define CRYPTO_GO         REG32(CRYPTO_BASE + 0x5CU)
#define CRYPTO_DMA_STATUS REG32(CRYPTO_BASE + 0x60U)
/**@}*/

// CTRL
#define CRYPTO_CTRL_KEY2     (1U << 0) // 0 = key1
#define CRYPTO_CTRL_BYPASS   (1U << 1) // plain DMA copy
#define CRYPTO_CTRL_MODE_CTR (0U << 2)

// STATUS
#define CRYPTO_STATUS_BOOT_DONE  (1U << 2)
#define CRYPTO_STATUS_KEY1_VALID (1U << 3)

// DMA_STATUS
#define CRYPTO_DMA_BUSY  (1U << 0)
#define CRYPTO_DMA_DONE  (1U << 1)
#define CRYPTO_DMA_ERROR (1U << 2)
#define CRYPTO_DMA_DONE_OK(status) (((status) & (CRYPTO_DMA_DONE | CRYPTO_DMA_ERROR)) == CRYPTO_DMA_DONE)
#define CRYPTO_DMA_RUNNING(status) (((status) & (CRYPTO_DMA_BUSY | CRYPTO_DMA_DONE)) == CRYPTO_DMA_BUSY)

#define CRYPTO_DMA_BLOCK_BYTES 16U

/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
void     crypto_dma_setup(uint32_t ctrl, uint32_t src, uint32_t dst, uint32_t blocks);
uint32_t crypto_dma_wait(uint32_t max_polls);
uint32_t crypto_dma_copy(uint32_t src, uint32_t dst, uint32_t bytes, uint32_t max_polls);
void     crypto_ctr_set_iv(uint32_t iv0, uint32_t iv1, uint32_t iv2);
/**@}*/

/**********************************************************************//**
 * Start the DMA configured by crypto_dma_setup().
 **************************************************************************/
static inline void crypto_dma_go(void) {
  CRYPTO_GO = 1U;
}

#endif // DIOWAS_CRYPTO_CORE_H
