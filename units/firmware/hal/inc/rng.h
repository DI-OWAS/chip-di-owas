// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// DI-OWAS pseudo-random test data (xorshift32)

#ifndef DIOWAS_RNG_H
#define DIOWAS_RNG_H

#include <stdint.h>

/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
void     rng_seed(uint32_t seed);
uint32_t rng_next(void);
/**@}*/

#endif // DIOWAS_RNG_H
