// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS octal PSRAM test: CPU accesses, crypto DMA, CPU + DMA concurrency, AES-CTR.
// Board build: endless loop. OCTRAM_SIM: small regions, one pass.
#include "octram_test.h"

#define BAUD_RATE 19200

// CPU test regions: start, middle (high address bits), end of the window
#define OCTRAM_MID_OFF 0x01234560U
static const uint32_t regions[] = {
  OCTRAM_BASE,
  OCTRAM_BASE + OCTRAM_MID_OFF,
  OCTRAM_BASE + OCTRAM_SIZE - REGION_SIZE
};
#define NUM_REGIONS (sizeof(regions)/sizeof(regions[0]))

// Seeds of the pseudo-random test data. Pass and region vary them per run.
#define SEED_WORD      0xcafebabeU
#define SEED_HALF      0x13579bdfU
#define SEED_BYTE      314159265U
#define SEED_DMA       0x0bad5eedU
#define SEED_P2P       0x5eed0000U
#define SEED_P2P_PASS  0x100U // test_dma_p2p adds the variant index to the seed
#define SEED_CONC      0xc0c0a000U
#define SEED_AES       0xae5c7700U

int main() {

  uint32_t region, pass = 0, errors, total = 0;

  hal_cpu_init(BAUD_RATE);
  neorv32_uart0_printf("OCTRAM test, code at 0x%x\n", (uint32_t)&main);
#ifndef OCTRAM_SIM
  neorv32_uart0_printf("PSRAM %ux %u MB, tests up to 0x%x\n", NUM_CHIPS, OCTRAM_CHIP_MB, OCTRAM_BASE + OCTRAM_SIZE - 1U);
  measure_throughput();
  measure_conc_latency();
#endif

  while (1) {
    errors = 0;
    for (region = 0; region < NUM_REGIONS; region++) {
      errors += test_zero(regions[region]);
      errors += test_word(regions[region], SEED_WORD + pass + region);
      errors += test_half(regions[region], SEED_HALF + pass + region);
      errors += test_byte(regions[region], SEED_BYTE + pass + region);
      errors += test_lanes(regions[region]);
    }
    errors += test_dma(SEED_DMA + pass);
    errors += test_dma_p2p(SEED_P2P + SEED_P2P_PASS*pass);
    errors += test_dma_concurrent(SEED_CONC + pass);
    errors += test_aes_ctr(SEED_AES + pass);
    total += errors;
    pass++;
    neorv32_uart0_printf("pass %u errors %u total %u conc_rounds %u/%u/%u mask %x/%x/%x\n", pass, errors, total,
                         conc_rounds[0], conc_rounds[1], conc_rounds[2],
                         conc_overlap_mask[0], conc_overlap_mask[1], conc_overlap_mask[2]);
#if PASSES != 0
    if (pass >= PASSES) break;
#endif
  }

  if (total) {
    neorv32_uart0_printf("TEST FAIL\n");
    return -1;
  }
  neorv32_uart0_printf("TEST PASS\n");
  return 0;
}
