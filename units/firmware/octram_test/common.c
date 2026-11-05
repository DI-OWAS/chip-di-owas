// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// Error report, DMA helpers with the test's poll limits and AES-CTR IV, shared SRAM1 buffer
#include "octram_test.h"

// fixed AES-CTR test IV
#define AES_CTR_IV0 0xfcfdfeffU
#define AES_CTR_IV1 0xf8f9fafbU
#define AES_CTR_IV2 0xf4f5f6f7U

uint32_t sram_buf[SRAM_BUF_WORDS];

uint32_t report_mismatch(const char *name, uint32_t addr, uint32_t expected, uint32_t actual) {
  neorv32_uart0_printf("%s <0x%x> ref 0x%x res 0x%x\n", name, addr, expected, actual);
  return 1;
}

// plain DMA copy, 1 = error
uint32_t dma_copy_checked(uint32_t src, uint32_t dst, uint32_t bytes) {
  uint32_t status = crypto_dma_copy(src, dst, bytes, DMA_POLLS);
  if (!CRYPTO_DMA_DONE_OK(status)) {
    neorv32_uart0_printf("dma 0x%x -> 0x%x status 0x%x\n", src, dst, status);
    return 1;
  }
  return 0;
}

// AES-CTR with key1 (NIST test key after reset, cryptoCore STATIC_KEY1).
// Writing the IV resets the counter, so a second run with the same IV decrypts.
// Returns DMA_STATUS. cycles is the time from GO to done seen by the CPU.
uint32_t aes_ctr(uint32_t src, uint32_t dst, uint32_t bytes, uint32_t *cycles) {
  uint32_t start, status;
  crypto_ctr_set_iv(AES_CTR_IV0, AES_CTR_IV1, AES_CTR_IV2);
  crypto_dma_setup(CRYPTO_CTRL_MODE_CTR, src, dst, bytes / CRYPTO_DMA_BLOCK_BYTES); // key1
  start = neorv32_cpu_csr_read(CSR_MCYCLE);
  crypto_dma_go();
  status = crypto_dma_wait(DMA_POLLS_LONG);
  *cycles = neorv32_cpu_csr_read(CSR_MCYCLE) - start;
  return status;
}
