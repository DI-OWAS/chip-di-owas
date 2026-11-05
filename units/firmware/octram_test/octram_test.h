// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS octal PSRAM test: configuration, PSRAM test areas, test functions
#ifndef OCTRAM_TEST_H
#define OCTRAM_TEST_H

#include <core_complex.h>
#include <crypto_core.h>
#include <memmap.h>
#include <rng.h>

#define NUM_BYTES_IN_WORD      4U
#define NUM_BYTES_IN_HALF_WORD 2U
#define BITS_PER_BYTE          8U
#define BYTE_MASK              0xFFU
#define HALF_WORD_MASK         0xFFFFU

// Byte address A of the window maps to chip A%4, chip address A/4.
#define NUM_CHIPS 4U // one chip per byte lane
#ifndef OCTRAM_CHIP_MB
#define OCTRAM_CHIP_MB 16U
#endif
#define OCTRAM_SIZE (NUM_CHIPS*OCTRAM_CHIP_MB*1024U*1024U)
// Never access outside the 64 MB window: the crossbar answers DECERR and
// blocks that master's port until reset.

#ifdef OCTRAM_SIM
#define REGION_SIZE 64U
#define PASSES      1
#else
#define REGION_SIZE (64U*1024U)
#define PASSES      0 // 0 = endless
#endif

// PSRAM areas of the DMA tests
#define DMA_OCTRAM    (OCTRAM_BASE + 0x00100000U) // test_dma
#define P2P_SRC       (OCTRAM_BASE + 0x00200000U) // test_dma_p2p
#define P2P_DST       (OCTRAM_BASE + 0x00300000U)
#define CONC_SRC      (OCTRAM_BASE + 0x00400000U) // concurrency test, throughput
#define CONC_DST      (OCTRAM_BASE + 0x00500000U)
#define CONC_CPU      (OCTRAM_BASE + 0x00600000U)
#define AES_PLAIN     (OCTRAM_BASE + 0x00700000U) // AES-CTR plaintext
#define AES_CIPHER    (OCTRAM_BASE + 0x00780000U) // ciphertext
#define AES_DECRYPTED (OCTRAM_BASE + 0x007C0000U) // decrypted again

// 2 KB SRAM1 buffer for the SRAM1 <-> PSRAM DMA runs
#define SRAM_BUF_WORDS 512U
#define SRAM_BUF_BYTES (NUM_BYTES_IN_WORD*SRAM_BUF_WORDS)
extern uint32_t sram_buf[SRAM_BUF_WORDS];

#define LONG_DMA_BYTES (16U*1024U) // longest DMA run (board measurements)

#define DMA_POLLS      1000000U  // polls before a DMA counts as hung
#define DMA_POLLS_LONG 10000000U // measurement runs (up to LONG_DMA_BYTES)

// concurrency test results of the last pass
#define NUM_CONC_VARS 3U
extern uint32_t conc_rounds[NUM_CONC_VARS];       // CPU rounds
extern uint32_t conc_overlap_mask[NUM_CONC_VARS]; // access types that overlapped the DMA (info)

// common.c
uint32_t report_mismatch(const char *name, uint32_t addr, uint32_t expected, uint32_t actual);
uint32_t dma_copy_checked(uint32_t src, uint32_t dst, uint32_t bytes);
uint32_t aes_ctr(uint32_t src, uint32_t dst, uint32_t bytes, uint32_t *cycles);

// mem_test.c (tests return the number of errors)
uint32_t test_zero(uint32_t base);
uint32_t test_word(uint32_t base, uint32_t seed);
uint32_t test_half(uint32_t base, uint32_t seed);
uint32_t test_byte(uint32_t base, uint32_t seed);
uint32_t test_lanes(uint32_t base);

// dma_test.c
uint32_t test_dma(uint32_t seed);
uint32_t test_dma_p2p(uint32_t seed);
uint32_t test_aes_ctr(uint32_t seed);

// conc_test.c
uint32_t test_dma_concurrent(uint32_t seed);
void     measure_conc_latency(void); // board only

// perf.c
void     measure_throughput(void);   // board only

#endif // OCTRAM_TEST_H
