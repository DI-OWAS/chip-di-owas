// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// Board only: DMA throughput from GO to done, no other PSRAM traffic
#include "octram_test.h"

#ifndef OCTRAM_SIM

// MB/s x10 = bytes / (cycles / f_clk) / 1e6 * 10 = bytes * f_clk / (cycles * 1e5)
#define BYTES_PER_MB_DIV_10 100000U

static void print_throughput(const char *name, uint32_t bytes, uint32_t cycles, uint32_t status) {
  uint32_t mb_per_s_x10 = (uint32_t)(((uint64_t)bytes * neorv32_sysinfo_get_clk()) /
                                     ((uint64_t)cycles * BYTES_PER_MB_DIV_10));
  neorv32_uart0_printf("tput %s: %u bytes, %u cycles, %u.%u MB/s, status 0x%x\n",
                       name, bytes, cycles, mb_per_s_x10 / 10U, mb_per_s_x10 % 10U, status);
}

static void throughput_copy(const char *name, uint32_t src, uint32_t dst, uint32_t bytes) {
  uint32_t start, status;
  crypto_dma_setup(CRYPTO_CTRL_BYPASS, src, dst, bytes / CRYPTO_DMA_BLOCK_BYTES);
  start = neorv32_cpu_csr_read(CSR_MCYCLE);
  crypto_dma_go();
  status = crypto_dma_wait(DMA_POLLS_LONG);
  print_throughput(name, bytes, neorv32_cpu_csr_read(CSR_MCYCLE) - start, status);
}

static void throughput_aes(const char *name, uint32_t src, uint32_t dst, uint32_t bytes) {
  uint32_t cycles, status;
  status = aes_ctr(src, dst, bytes, &cycles);
  print_throughput(name, bytes, cycles, status);
}

void measure_throughput(void) {
  neorv32_uart0_printf("DMA plain-copy throughput (%u MHz, GO to done seen by CPU):\n",
                       neorv32_sysinfo_get_clk() / 1000000U);
  throughput_copy("SRAM->PSRAM 2KB",   (uint32_t)sram_buf, CONC_SRC, SRAM_BUF_BYTES);
  throughput_copy("PSRAM->SRAM 2KB",   CONC_SRC, (uint32_t)sram_buf, SRAM_BUF_BYTES);
  throughput_copy("PSRAM->PSRAM 2KB",  CONC_SRC, CONC_DST, SRAM_BUF_BYTES);
  throughput_copy("PSRAM->PSRAM 16KB", CONC_SRC, CONC_DST, LONG_DMA_BYTES);
  neorv32_uart0_printf("crypto STATUS 0x%x (bit 3 = key1 valid)\n", CRYPTO_STATUS);
  throughput_aes("AES-CTR SRAM->PSRAM 2KB",   (uint32_t)sram_buf, CONC_DST, SRAM_BUF_BYTES);
  throughput_aes("AES-CTR PSRAM->PSRAM 2KB",  CONC_SRC, CONC_DST, SRAM_BUF_BYTES);
  throughput_aes("AES-CTR PSRAM->PSRAM 16KB", CONC_SRC, CONC_DST, LONG_DMA_BYTES);
}

#endif // OCTRAM_SIM
