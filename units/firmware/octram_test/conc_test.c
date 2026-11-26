// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// CPU and DMA on the PSRAM at the same time: the DMA runs CONC_RUNS times while
// the CPU writes and reads back data in a moving window. conc_directed() proves
// the overlap with one access of each type while the DMA is busy.
#include "octram_test.h"

#ifdef OCTRAM_SIM
#define CONC_BLOCKS 64U   // 1 KB
#define CONC_RUNS   4U    // DMA runs per variant
#else
#define CONC_BLOCKS 1024U // 16 KB
#define CONC_RUNS   8U
#endif
#define CONC_SEC         NUM_BYTES_IN_WORD // bytes per section
#define CONC_STEP        0x34U             // CPU window step per round
#define CONC_WIN_MASK    0xFFFU            // CPU window moves within 4 KB
#define CONC_DELAY_STEP  37U               // CPU delay after a DMA start: (run * STEP) % MAX nops
#define CONC_DELAY_MAX   64U
#define SRAM_BUF_BLOCKS  (SRAM_BUF_BYTES / CRYPTO_DMA_BLOCK_BYTES)
#define CONC_SRAM_BLOCKS (CONC_BLOCKS < SRAM_BUF_BLOCKS ? CONC_BLOCKS : SRAM_BUF_BLOCKS)
#define CONC_MAX_ROUNDS  100000U           // hang detection
#define CONC_SEED_STEP   0x9e3779b9U       // seed step per CPU round (golden ratio, 32 bit)

uint32_t conc_rounds[NUM_CONC_VARS];
uint32_t conc_overlap_mask[NUM_CONC_VARS];

typedef struct { const char *name; uint32_t src, dst, blocks; } conc_var_t;

// CPU access types. The writes come first (see dir_end).
enum { ACCESS_WRITE_WORD, ACCESS_WRITE_HALF, ACCESS_WRITE_BYTE,
       ACCESS_READ_BYTE, ACCESS_READ_WORD, ACCESS_READ_HALF, NUM_ACCESS_TYPES };
static const char *const access_name[NUM_ACCESS_TYPES] = { "wrW", "wrH", "wrB", "rdB", "rdW", "rdH" };

static uint8_t conc_shadow[3U*CONC_SEC]; // expected CPU window content
static uint32_t conc_win;                // CPU window position

// state of the DMA runs while the CPU works on the PSRAM
static struct {
  const conc_var_t *var;
  uint32_t overlap_mask; // access types that overlapped the DMA
  uint32_t runs;
  uint32_t dma_errors;
  uint32_t active;
} conc;

// the varying delay spreads the CPU accesses over the DMA run
static void conc_dma_start(void) {
  uint32_t delay;
  crypto_dma_setup(CRYPTO_CTRL_BYPASS, conc.var->src, conc.var->dst, conc.var->blocks);
  crypto_dma_go();
  for (delay = (conc.runs * CONC_DELAY_STEP) % CONC_DELAY_MAX; delay > 0; delay--) __asm__ volatile ("nop");
}

// called after every CPU PSRAM access of the given type
static void conc_tick(uint32_t type) {
  uint32_t status;
  if (!conc.active) return;
  status = CRYPTO_DMA_STATUS;
  if (CRYPTO_DMA_RUNNING(status)) {
    conc.overlap_mask |= 1U << type;
  } else if (status & CRYPTO_DMA_DONE) {
    if (status & CRYPTO_DMA_ERROR) conc.dma_errors++;
    conc.runs++;
    if (conc.runs < CONC_RUNS) conc_dma_start(); else conc.active = 0;
  }
}

static void shadow_put(uint32_t off, uint32_t value, uint32_t bytes) {
  uint32_t k;
  for (k = 0; k < bytes; k++) conc_shadow[off + k] = (uint8_t)(value >> (BITS_PER_BYTE*k));
}

static uint32_t shadow_get(uint32_t off, uint32_t bytes) {
  uint32_t k, value = 0;
  for (k = 0; k < bytes; k++) value |= (uint32_t)conc_shadow[off + k] << (BITS_PER_BYTE*k);
  return value;
}

static uint32_t conc_cpu_round(uint32_t addr, uint32_t seed) {
  uint32_t offset, value, expected, actual, errors = 0;
  rng_seed(seed);
  for (offset = 0; offset < CONC_SEC; offset += sizeof(uint32_t)) { // words
    value = rng_next(); shadow_put(offset, value, sizeof(uint32_t));
    *(volatile uint32_t*)(addr + offset) = value;
    conc_tick(ACCESS_WRITE_WORD);
  }
  for (offset = CONC_SEC; offset < 2U*CONC_SEC; offset += sizeof(uint16_t)) { // half-words
    value = rng_next() & HALF_WORD_MASK; shadow_put(offset, value, sizeof(uint16_t));
    *(volatile uint16_t*)(addr + offset) = (uint16_t)value;
    conc_tick(ACCESS_WRITE_HALF);
  }
  for (offset = 2U*CONC_SEC; offset < 3U*CONC_SEC; offset++) { // bytes
    value = rng_next() & BYTE_MASK; shadow_put(offset, value, sizeof(uint8_t));
    *(volatile uint8_t*)(addr + offset) = (uint8_t)value;
    conc_tick(ACCESS_WRITE_BYTE);
  }
  for (offset = 0; offset < CONC_SEC; offset++) { // word section as bytes
    expected = shadow_get(offset, sizeof(uint8_t));
    actual   = *(volatile uint8_t*)(addr + offset);
    conc_tick(ACCESS_READ_BYTE);
    if (actual != expected) errors += report_mismatch("conc cpu b", addr + offset, expected, actual);
  }
  for (offset = CONC_SEC; offset < 2U*CONC_SEC; offset += sizeof(uint32_t)) { // half-word section as words
    expected = shadow_get(offset, sizeof(uint32_t));
    actual   = *(volatile uint32_t*)(addr + offset);
    conc_tick(ACCESS_READ_WORD);
    if (actual != expected) errors += report_mismatch("conc cpu w", addr + offset, expected, actual);
  }
  for (offset = 2U*CONC_SEC; offset < 3U*CONC_SEC; offset += sizeof(uint16_t)) { // byte section as half-words
    expected = shadow_get(offset, sizeof(uint16_t));
    actual   = *(volatile uint16_t*)(addr + offset);
    conc_tick(ACCESS_READ_HALF);
    if (actual != expected) errors += report_mismatch("conc cpu h", addr + offset, expected, actual);
  }
  return errors;
}

// Directed check: start the DMA, wait until a marker arrives at the destination,
// then one access and a DMA_STATUS read. Still busy = the access ran during the
// DMA (stores complete only with the AXI B response, so this holds for writes).
#define CONC_DIR        (CONC_CPU + 0x2000U) // outside the moving CPU window
#define CONC_MARK       0x600DF00DU
#define CONC_MARK_POLLS 100000U
#define DIR_PATTERN     0xA5C3F00FU
#define DIR_BEFORE(t)   (DIR_PATTERN ^ ((t) * 0x01010101U)) // CONC_DIR content before the access
// values the directed and latency accesses write
#define DIR_WORD_VALUE  0x5A5A0000U
#define DIR_HALF_VALUE  0xBEEFU // upper half-word (CONC_DIR + 2)
#define DIR_BYTE_VALUE  0xC3U   // byte 1 (CONC_DIR + 1)
static uint32_t conc_dir_print = 1U;   // first pass only
extern char __crt0_stack_top[];        // end of SRAM1 (linker script)

static uint32_t dir_blocks(const conc_var_t *cv) {
  if (cv->src == (uint32_t)sram_buf) return ((uint32_t)__crt0_stack_top - cv->src) / CRYPTO_DMA_BLOCK_BYTES;
  return cv->blocks;
}

static uint32_t dir_start(const conc_var_t *cv, uint32_t type) {
  volatile uint32_t *dst_first = (volatile uint32_t*)cv->dst;
  uint32_t polls = 0;
  *(volatile uint32_t*)CONC_DIR = DIR_BEFORE(type);
  *(volatile uint32_t*)cv->src  = CONC_MARK ^ type;
  *dst_first = 0;
  crypto_dma_setup(CRYPTO_CTRL_BYPASS, cv->src, cv->dst, dir_blocks(cv));
  crypto_dma_go();
  while ((*dst_first != (CONC_MARK ^ type)) && (++polls < CONC_MARK_POLLS));
  return polls;
}

static uint32_t dir_end(const conc_var_t *cv, uint32_t type, uint32_t marker_polls, uint32_t status,
                        uint32_t cycles, uint32_t expected, uint32_t actual) {
  uint32_t errors = 0;
  if (marker_polls >= CONC_MARK_POLLS) {
    neorv32_uart0_printf("conc %s: %s marker not seen\n", cv->name, access_name[type]);
    errors++;
  }
  if (!CRYPTO_DMA_RUNNING(status)) {
    neorv32_uart0_printf("conc %s: %s not overlapped (DMA status 0x%x after the access)\n", cv->name, access_name[type], status);
    errors++;
  }
  status = crypto_dma_wait(DMA_POLLS);
  if (!CRYPTO_DMA_DONE_OK(status)) {
    neorv32_uart0_printf("conc %s: %s dma status 0x%x\n", cv->name, access_name[type], status);
    errors++;
  }
  if (type <= ACCESS_WRITE_BYTE) actual = *(volatile uint32_t*)CONC_DIR; // writes: read back the word
  if (actual != expected) errors += report_mismatch("conc dir", CONC_DIR, expected, actual);
  if (conc_dir_print) neorv32_uart0_printf(" %s %u", access_name[type], cycles);
  return errors;
}

// Macros, not functions: the access must sit inline between the two MCYCLE
// reads. The empty asm keeps the expected value computation out of the timed part.
#define CONC_DIR_ACCESS(type, expected_expr, access) do {               \
    before = DIR_BEFORE(type); expected = (expected_expr); actual = 0;  \
    marker_polls = dir_start(cv, (type));                               \
    __asm__ volatile ("" : "+r" (expected));                            \
    start = neorv32_cpu_csr_read(CSR_MCYCLE);                           \
    access;                                                             \
    status = CRYPTO_DMA_STATUS;                                         \
    end = neorv32_cpu_csr_read(CSR_MCYCLE);                             \
    errors += dir_end(cv, (type), marker_polls, status, end - start, expected, actual); \
  } while (0)

static uint32_t conc_directed(const conc_var_t *cv) {
  volatile uint32_t *word  = (volatile uint32_t*)CONC_DIR;
  volatile uint16_t *half  = (volatile uint16_t*)(CONC_DIR + 2U);
  volatile uint8_t  *byte1 = (volatile uint8_t*)(CONC_DIR + 1U);
  volatile uint8_t  *byte3 = (volatile uint8_t*)(CONC_DIR + 3U);
  uint32_t before, expected, actual, marker_polls, status, start, end, errors = 0;
  if (conc_dir_print) neorv32_uart0_printf("conc dir %s cycles:", cv->name);
  CONC_DIR_ACCESS(ACCESS_WRITE_WORD, DIR_WORD_VALUE,                                 *word  = expected);
  CONC_DIR_ACCESS(ACCESS_WRITE_HALF, (before & 0x0000FFFFU) | (DIR_HALF_VALUE << 16), *half  = DIR_HALF_VALUE);
  CONC_DIR_ACCESS(ACCESS_WRITE_BYTE, (before & 0xFFFF00FFU) | (DIR_BYTE_VALUE << 8),  *byte1 = DIR_BYTE_VALUE);
  CONC_DIR_ACCESS(ACCESS_READ_BYTE,  before >> 24,                                    actual = *byte3);
  CONC_DIR_ACCESS(ACCESS_READ_WORD,  before,                                          actual = *word);
  CONC_DIR_ACCESS(ACCESS_READ_HALF,  before >> 16,                                    actual = *half);
  if (conc_dir_print) neorv32_uart0_printf("\n");
  return errors;
}

static uint32_t conc_one(const conc_var_t *cv, uint32_t seed, uint32_t *rounds_out, uint32_t *mask_out) {
  volatile uint32_t *src = (volatile uint32_t*)cv->src;
  volatile uint32_t *dst = (volatile uint32_t*)cv->dst;
  uint32_t i, words = cv->blocks * CRYPTO_DMA_BLOCK_BYTES / NUM_BYTES_IN_WORD;
  uint32_t expected, actual, rounds = 0, errors = 0;
  errors += conc_directed(cv);
  // CPU: random source, zero destination
  rng_seed(seed);
  for (i = 0; i < words; i++) {
    src[i] = rng_next();
    dst[i] = 0;
  }
  // start the DMA, CPU traffic on the PSRAM until CONC_RUNS runs are done
  conc.var = cv; conc.overlap_mask = 0; conc.runs = 0; conc.dma_errors = 0; conc.active = 1;
  conc_dma_start();
  while (conc.active && (rounds < CONC_MAX_ROUNDS)) {
    errors += conc_cpu_round(CONC_CPU + ((conc_win++ * CONC_STEP) & CONC_WIN_MASK),
                             seed ^ (CONC_SEED_STEP * (rounds + 1U)));
    rounds++;
  }

  *rounds_out = rounds;
  *mask_out   = conc.overlap_mask;
  if (conc.active) {
    neorv32_uart0_printf("conc %s: DMA hang, run %u status 0x%x after %u CPU rounds\n",
                         cv->name, conc.runs, CRYPTO_DMA_STATUS, rounds);
    conc.active = 0;
    return errors + 1;
  }
  if (conc.dma_errors) {
    neorv32_uart0_printf("conc %s: %u DMA runs ended with error\n", cv->name, conc.dma_errors);
    errors += conc.dma_errors;
  }
  // CPU: check the DMA copy
  rng_seed(seed);
  for (i = 0; i < words; i++) {
    expected = rng_next();
    actual   = dst[i];
    if (actual != expected) errors += report_mismatch("conc dst", (uint32_t)&dst[i], expected, actual);
  }
  if (errors) neorv32_uart0_printf("conc %s: %u errors\n", cv->name, errors);
  return errors;
}

uint32_t test_dma_concurrent(uint32_t seed) {
  const conc_var_t vars[NUM_CONC_VARS] = {
    { "PSRAM->PSRAM", CONC_SRC,            CONC_DST,            CONC_BLOCKS      },
    { "SRAM1->PSRAM", (uint32_t)sram_buf,  CONC_DST,            CONC_SRAM_BLOCKS },
    { "PSRAM->SRAM1", CONC_SRC,            (uint32_t)sram_buf,  CONC_SRAM_BLOCKS },
  };
  uint32_t v, errors = 0;
  for (v = 0; v < NUM_CONC_VARS; v++) {
    errors += conc_one(&vars[v], seed + 0x1000U*v, &conc_rounds[v], &conc_overlap_mask[v]);
  }
  conc_dir_print = 0;
  return errors;
}

#ifndef OCTRAM_SIM
// Board only: CPU access latency, idle and with the DMA running (wait 0..1200
// cycles after GO). b/d = DMA busy/done after the access. Macros for the same
// reason as CONC_DIR_ACCESS.
#define LAT_TIMED(access) do {                                   \
    __asm__ volatile ("" : "+r" (value));                        \
    start = neorv32_cpu_csr_read(CSR_MCYCLE);                    \
    access;                                                      \
    status = CRYPTO_DMA_STATUS;                                  \
    end = neorv32_cpu_csr_read(CSR_MCYCLE);                      \
  } while (0)

#define LAT_EACH(M)                                  \
  M(ACCESS_WRITE_WORD, *word  = value)               \
  M(ACCESS_WRITE_HALF, *half  = DIR_HALF_VALUE)      \
  M(ACCESS_WRITE_BYTE, *byte1 = DIR_BYTE_VALUE)      \
  M(ACCESS_READ_BYTE,  actual = *byte3)              \
  M(ACCESS_READ_WORD,  actual = *word)               \
  M(ACCESS_READ_HALF,  actual = *half)

#define LAT_IDLE(type, access)                                       \
  LAT_TIMED(access);                                                 \
  neorv32_uart0_printf(" %s %u", access_name[type], end - start);

#define LAT_DMA(type, access)                                        \
  crypto_dma_setup(CRYPTO_CTRL_BYPASS, cv->src, cv->dst, cv->blocks); \
  dma_cycles = neorv32_cpu_csr_read(CSR_MCYCLE);                     \
  crypto_dma_go();                                                   \
  while ((neorv32_cpu_csr_read(CSR_MCYCLE) - dma_cycles) < wait_cycles); \
  LAT_TIMED(access);                                                 \
  dma_status = crypto_dma_wait(DMA_POLLS_LONG);                      \
  dma_cycles = neorv32_cpu_csr_read(CSR_MCYCLE) - dma_cycles;        \
  if ((dma_status & CRYPTO_DMA_DONE) == 0) {                         \
    neorv32_uart0_printf(" %s: DMA hang, status 0x%x\n", access_name[type], dma_status); \
    return;                                                          \
  }                                                                  \
  neorv32_uart0_printf(" %s %u%c/dma%u", access_name[type], end - start, \
                       CRYPTO_DMA_RUNNING(status) ? 'b' : 'd', dma_cycles);

void measure_conc_latency(void) {
  const conc_var_t vars[NUM_CONC_VARS] = {
    { "PSRAM->PSRAM 16KB", CONC_SRC,           CONC_DST,           CONC_BLOCKS      },
    { "SRAM1->PSRAM 2KB",  (uint32_t)sram_buf, CONC_DST,           CONC_SRAM_BLOCKS },
    { "PSRAM->SRAM1 2KB",  CONC_SRC,           (uint32_t)sram_buf, CONC_SRAM_BLOCKS },
  };
  static const uint32_t lat_waits[] = { 0U, 300U, 800U, 1200U }; // cycles from GO to the access
  volatile uint32_t *word  = (volatile uint32_t*)CONC_DIR;
  volatile uint16_t *half  = (volatile uint16_t*)(CONC_DIR + 2U);
  volatile uint8_t  *byte1 = (volatile uint8_t*)(CONC_DIR + 1U);
  volatile uint8_t  *byte3 = (volatile uint8_t*)(CONC_DIR + 3U);
  const conc_var_t *cv;
  uint32_t v, wait_idx, wait_cycles, start, end, dma_cycles, status, dma_status;
  uint32_t value = DIR_WORD_VALUE, actual = 0;
  neorv32_uart0_printf("CPU PSRAM access latency (cycles incl. the DMA_STATUS read, b = DMA still busy after the access, d = done):\n");
  neorv32_uart0_printf("lat idle (no DMA):");
  LAT_EACH(LAT_IDLE)
  start  = neorv32_cpu_csr_read(CSR_MCYCLE);
  status = CRYPTO_DMA_STATUS;
  end    = neorv32_cpu_csr_read(CSR_MCYCLE);
  neorv32_uart0_printf(" status %u\n", end - start);
  for (v = 0; v < NUM_CONC_VARS; v++) {
    cv = &vars[v];
    for (wait_idx = 0; wait_idx < sizeof(lat_waits)/sizeof(lat_waits[0]); wait_idx++) {
      wait_cycles = lat_waits[wait_idx];
      neorv32_uart0_printf("lat %s wait %u:", cv->name, wait_cycles);
      LAT_EACH(LAT_DMA)
      neorv32_uart0_printf("\n");
    }
  }
  (void)status; (void)actual;
}
#endif // OCTRAM_SIM
