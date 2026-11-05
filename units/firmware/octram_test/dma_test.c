// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// Crypto DMA copies to, from and within the PSRAM, AES-CTR round trip
#include "octram_test.h"

#define DMA_WORDS 64U // 256 bytes = 16 blocks
static uint32_t sram_src[DMA_WORDS], sram_dst[DMA_WORDS];

// SRAM1 -> OCTRAM -> SRAM1, CPU checks both copies
uint32_t test_dma(uint32_t seed) {
  volatile uint32_t *octram = (volatile uint32_t*)DMA_OCTRAM;
  volatile uint32_t *dst    = sram_dst;
  uint32_t i, actual, errors = 0;
  rng_seed(seed);
  for (i = 0; i < DMA_WORDS; i++) {
    sram_src[i] = rng_next();
    sram_dst[i] = 0;
    octram[i]   = 0;
  }
  errors += dma_copy_checked((uint32_t)sram_src, DMA_OCTRAM, sizeof(sram_src));
  for (i = 0; i < DMA_WORDS; i++) {
    actual = octram[i];
    if (actual != sram_src[i]) errors += report_mismatch("dma->oct", (uint32_t)&octram[i], sram_src[i], actual);
  }
  errors += dma_copy_checked(DMA_OCTRAM, (uint32_t)sram_dst, sizeof(sram_dst));
  for (i = 0; i < DMA_WORDS; i++) {
    actual = dst[i];
    if (actual != sram_src[i]) errors += report_mismatch("oct->dma", (uint32_t)&dst[i], sram_src[i], actual);
  }
  return errors;
}

// OCTRAM -> OCTRAM DMA copy with guard words around the destination. The
// variants cover burst lengths, word (not block) alignment and 4 KB crossings.
#define P2P_GUARD 16U // guard words before and after the destination

typedef struct { uint32_t blocks, src_off, dst_off; } p2p_var_t;
static const p2p_var_t p2p_vars[] = {
  {   1, 0x000, 0x000 }, // one 4-beat burst
  {   2, 0x000, 0x000 }, // 8-beat burst
  {   4, 0x000, 0x000 }, // exactly one 16-beat burst
  {   5, 0x000, 0x000 }, // 16 + 4 beats
  {  17, 0x000, 0x000 }, // several full bursts + remainder
  {   3, 0x004, 0x008 }, // word aligned, not block aligned
  {  33, 0x00C, 0x004 },
  {   2, 0xFF0, 0x000 }, // source crosses a 4 KB boundary
  {   2, 0x000, 0xFF8 }, // destination crosses a 4 KB boundary
  { 300, 0xFC4, 0x7F8 }, // long, both cross, different offsets
#ifndef OCTRAM_SIM
  {1024, 0x000, 0x000 }, // 16 KB
#endif
};
#define NUM_P2P_VARS (sizeof(p2p_vars)/sizeof(p2p_vars[0]))

uint32_t test_dma_p2p(uint32_t seed) {
  volatile uint32_t *src, *dst, *guard_pre, *guard_post;
  uint32_t v, i, words, expected, actual, errors = 0, errors_before;
  for (v = 0; v < NUM_P2P_VARS; v++) {
    errors_before = errors;
    words      = p2p_vars[v].blocks * CRYPTO_DMA_BLOCK_BYTES / NUM_BYTES_IN_WORD;
    src        = (volatile uint32_t*)(P2P_SRC + p2p_vars[v].src_off);
    dst        = (volatile uint32_t*)(P2P_DST + p2p_vars[v].dst_off);
    guard_pre  = dst - P2P_GUARD;
    guard_post = dst + words;
    // CPU: zero destination incl. guards, random source
    for (i = 0; i < words + 2U*P2P_GUARD; i++) {
      guard_pre[i] = 0;
    }
    rng_seed(seed + v);
    for (i = 0; i < words; i++) {
      src[i] = rng_next();
    }
    if (dma_copy_checked((uint32_t)src, (uint32_t)dst, CRYPTO_DMA_BLOCK_BYTES*p2p_vars[v].blocks)) {
      errors++;
      continue;
    }
    // CPU: destination equals source, source unchanged, guards still zero
    rng_seed(seed + v);
    for (i = 0; i < words; i++) {
      expected = rng_next();
      actual   = src[i];
      if (actual != expected) errors += report_mismatch("p2p src", (uint32_t)&src[i], expected, actual);
      actual   = dst[i];
      if (actual != expected) errors += report_mismatch("p2p dst", (uint32_t)&dst[i], expected, actual);
    }
    for (i = 0; i < P2P_GUARD; i++) {
      actual = guard_pre[i];
      if (actual != 0) errors += report_mismatch("p2p pre", (uint32_t)&guard_pre[i], 0, actual);
      actual = guard_post[i];
      if (actual != 0) errors += report_mismatch("p2p post", (uint32_t)&guard_post[i], 0, actual);
    }
    if (errors != errors_before) neorv32_uart0_printf("p2p variant %u (%u blocks): %u errors\n", v, p2p_vars[v].blocks, errors - errors_before);
  }
  return errors;
}

// AES-CTR: encrypt random data, decrypt it again, compare (all in the PSRAM)
#define AES_BYTES        2048U
#define AES_WORDS        (AES_BYTES / NUM_BYTES_IN_WORD)
#define AES_SAME_MAX     4U // ciphertext words allowed to equal the plaintext

uint32_t test_aes_ctr(uint32_t seed) {
  volatile uint32_t *plain     = (volatile uint32_t*)AES_PLAIN;
  volatile uint32_t *cipher    = (volatile uint32_t*)AES_CIPHER;
  volatile uint32_t *decrypted = (volatile uint32_t*)AES_DECRYPTED;
  uint32_t i, expected, actual, cycles, status, same = 0, errors = 0;
  if ((CRYPTO_STATUS & CRYPTO_STATUS_KEY1_VALID) == 0) {
    neorv32_uart0_printf("aes: key1 not valid (STATUS 0x%x), skipped\n", CRYPTO_STATUS);
    return 1;
  }
  rng_seed(seed);
  for (i = 0; i < AES_WORDS; i++) {
    plain[i]     = rng_next();
    cipher[i]    = 0;
    decrypted[i] = 0;
  }
  status = aes_ctr(AES_PLAIN, AES_CIPHER, AES_BYTES, &cycles);
  if (!CRYPTO_DMA_DONE_OK(status)) { neorv32_uart0_printf("aes enc status 0x%x\n", status); return errors + 1; }
  status = aes_ctr(AES_CIPHER, AES_DECRYPTED, AES_BYTES, &cycles);
  if (!CRYPTO_DMA_DONE_OK(status)) { neorv32_uart0_printf("aes dec status 0x%x\n", status); return errors + 1; }
  rng_seed(seed);
  for (i = 0; i < AES_WORDS; i++) {
    expected = rng_next();
    if (cipher[i] == expected) same++;
    actual = decrypted[i];
    if (actual != expected) errors += report_mismatch("aes dec", (uint32_t)&decrypted[i], expected, actual);
  }
  if (same > AES_SAME_MAX) {
    neorv32_uart0_printf("aes: %u ciphertext words equal the plaintext\n", same);
    errors++;
  }
  return errors;
}
