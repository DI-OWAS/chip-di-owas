// DI-OWAS Core-Complex HAL

#ifndef DIOWAS_CORE_COMPLEX_H
#define DIOWAS_CORE_COMPLEX_H

#include <stdint.h>
#include <neorv32.h>

/**********************************************************************//**
 * @name Prototypes
 **************************************************************************/
/**@{*/
void hal_cpu_init(int uart_baud);
void hal_cpu_delay_ms(uint32_t time_ms);
/**@}*/


#endif // DIOWAS_CORE_COMPLEX_H

