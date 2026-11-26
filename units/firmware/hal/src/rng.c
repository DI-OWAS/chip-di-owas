// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS pseudo-random test data (xorshift32)

#include <rng.h>

static uint32_t rng_state = 1U;


/**********************************************************************//**
 * Restart the sequence. The same seed gives the same sequence again.
 *
 * @param[in] seed Start value, not 0 (xorshift32 stays at 0).
 **************************************************************************/
void rng_seed(uint32_t seed) {

  rng_state = seed;
}


/**********************************************************************//**
 * Next value of the sequence.
 **************************************************************************/
uint32_t rng_next(void) {

  rng_state ^= rng_state << 13;
  rng_state ^= rng_state >> 17;
  rng_state ^= rng_state << 5;
  return rng_state;
}
