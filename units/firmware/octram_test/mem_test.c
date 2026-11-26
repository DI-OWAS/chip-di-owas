// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// CPU accesses to the PSRAM
#include "octram_test.h"

#define REGION_WORDS  (REGION_SIZE / NUM_BYTES_IN_WORD)

// test_lanes: word pattern, then one byte / half-word written over it
#define LANE_WORD8   0x11223344U
#define LANE_BYTE    0xA5U
#define LANE_WORD16  0x55667788U
#define LANE_HALF    0xBEEFU

// word-wise zero fill
uint32_t test_zero(uint32_t base) {
  volatile uint32_t *words = (volatile uint32_t*)base;
  uint32_t i, actual, errors = 0;
  for (i = 0; i < REGION_WORDS; i++) {
    words[i] = 0;
  }
  for (i = 0; i < REGION_WORDS; i++) {
    actual = words[i];
    if (actual != 0) errors += report_mismatch("zero", (uint32_t)&words[i], 0, actual);
  }
  return errors;
}

// PSRAM access with the given size in bytes
static void write_sized(uint32_t addr, uint32_t size, uint32_t value) {
  switch (size) {
    case sizeof(uint8_t):  *(volatile uint8_t*)addr  = (uint8_t)value;  break;
    case sizeof(uint16_t): *(volatile uint16_t*)addr = (uint16_t)value; break;
    default:               *(volatile uint32_t*)addr = value;           break;
  }
}

static uint32_t read_sized(uint32_t addr, uint32_t size) {
  switch (size) {
    case sizeof(uint8_t):  return *(volatile uint8_t*)addr;
    case sizeof(uint16_t): return *(volatile uint16_t*)addr;
    default:               return *(volatile uint32_t*)addr;
  }
}

// pseudo-random data at base + [first, end) with accesses of <size> bytes, read back
static uint32_t random_fill_check(const char *name, uint32_t base, uint32_t seed,
                                  uint32_t size, uint32_t first, uint32_t end) {
  uint32_t offset, expected, actual, errors = 0;
  uint32_t mask = (size == sizeof(uint32_t)) ? 0xFFFFFFFFU : (1U << (BITS_PER_BYTE*size)) - 1U;
  rng_seed(seed);
  for (offset = first; offset < end; offset += size) {
    write_sized(base + offset, size, rng_next());
  }
  rng_seed(seed);
  for (offset = first; offset < end; offset += size) {
    expected = rng_next() & mask;
    actual   = read_sized(base + offset, size);
    if (expected != actual) errors += report_mismatch(name, base + offset, expected, actual);
  }
  return errors;
}

// word-wise pseudo-random data
uint32_t test_word(uint32_t base, uint32_t seed) {
  return random_fill_check("word", base, seed, sizeof(uint32_t), 0, REGION_SIZE);
}

// half-word pseudo-random data, starting at an unaligned (word) offset
uint32_t test_half(uint32_t base, uint32_t seed) {
  return random_fill_check("half", base, seed, sizeof(uint16_t),
                           sizeof(uint16_t), REGION_SIZE - sizeof(uint16_t));
}

// byte-wise pseudo-random data, starting at an odd address
uint32_t test_byte(uint32_t base, uint32_t seed) {
  return random_fill_check("byte", base, seed, sizeof(uint8_t), 1U, REGION_SIZE - 1U);
}

// byte lane isolation (WSTRB): overwrite single bytes / half-words of a word
// and check that the other chips keep their data
uint32_t test_lanes(uint32_t base) {
  volatile uint32_t *word = (volatile uint32_t*)base;
  uint32_t lane, shift, expected, actual, errors = 0;
  for (lane = 0; lane < NUM_CHIPS; lane++) {
    shift = BITS_PER_BYTE*lane;
    *word = LANE_WORD8;
    *(volatile uint8_t*)(base + lane) = LANE_BYTE;
    expected = (LANE_WORD8 & ~(BYTE_MASK << shift)) | (LANE_BYTE << shift);
    actual   = *word;
    if (expected != actual) errors += report_mismatch("lane8", base, expected, actual);
  }
  for (lane = 0; lane < NUM_CHIPS; lane += sizeof(uint16_t)) {
    shift = BITS_PER_BYTE*lane;
    *word = LANE_WORD16;
    *(volatile uint16_t*)(base + lane) = LANE_HALF;
    expected = (LANE_WORD16 & ~(HALF_WORD_MASK << shift)) | (LANE_HALF << shift);
    actual   = *word;
    if (expected != actual) errors += report_mismatch("lane16", base, expected, actual);
  }
  return errors;
}
