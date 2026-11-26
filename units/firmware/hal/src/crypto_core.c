// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS crypto core: DMA helpers

#include <crypto_core.h>


/**********************************************************************//**
 * Configure a DMA run without starting it (start with crypto_dma_go()).
 *
 * @param[in] ctrl CTRL value, e.g. CRYPTO_CTRL_BYPASS or CRYPTO_CTRL_MODE_CTR.
 * @param[in] src Source byte address.
 * @param[in] dst Destination byte address.
 * @param[in] blocks Length in 16 byte blocks.
 **************************************************************************/
void crypto_dma_setup(uint32_t ctrl, uint32_t src, uint32_t dst, uint32_t blocks) {

  CRYPTO_CTRL       = ctrl;
  CRYPTO_SRC_ADDR   = src;
  CRYPTO_DST_ADDR   = dst;
  CRYPTO_DMA_BLOCKS = blocks;
}


/**********************************************************************//**
 * Poll DMA_STATUS until the DMA is done, at most max_polls times.
 *
 * @param[in] max_polls Polls before giving up.
 * @return Last DMA_STATUS, check it with CRYPTO_DMA_DONE_OK();
 *         CRYPTO_DMA_DONE not set = the DMA did not end in time.
 **************************************************************************/
uint32_t crypto_dma_wait(uint32_t max_polls) {

  uint32_t status = 0;
  for (uint32_t poll = 0; poll < max_polls; poll++) {
    status = CRYPTO_DMA_STATUS;
    if (status & CRYPTO_DMA_DONE) {
      break;
    }
  }
  return status;
}


/**********************************************************************//**
 * Plain DMA copy (bypass mode), waits for the end.
 *
 * @param[in] src Source byte address.
 * @param[in] dst Destination byte address.
 * @param[in] bytes Length, a multiple of CRYPTO_DMA_BLOCK_BYTES.
 * @param[in] max_polls Polls before giving up.
 * @return Last DMA_STATUS, check it with CRYPTO_DMA_DONE_OK().
 **************************************************************************/
uint32_t crypto_dma_copy(uint32_t src, uint32_t dst, uint32_t bytes, uint32_t max_polls) {

  crypto_dma_setup(CRYPTO_CTRL_BYPASS, src, dst, bytes / CRYPTO_DMA_BLOCK_BYTES);
  crypto_dma_go();
  return crypto_dma_wait(max_polls);
}


/**********************************************************************//**
 * Set the CTR IV; this also resets the counter, so a second run with the
 * same IV decrypts.
 **************************************************************************/
void crypto_ctr_set_iv(uint32_t iv0, uint32_t iv1, uint32_t iv2) {

  CRYPTO_CTR_IV0 = iv0;
  CRYPTO_CTR_IV1 = iv1;
  CRYPTO_CTR_IV2 = iv2;
}
