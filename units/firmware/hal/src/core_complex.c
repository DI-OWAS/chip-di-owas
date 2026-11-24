// DI-OWAS Core-Complex HAL

#include <core_complex.h>


/**********************************************************************//**
 * Setup processor platform.
 *
 * @PARAM[IN] uart_baud Baud rate fro serial console.
 **************************************************************************/
// Setup the processor
void hal_cpu_init(int uart_baud) {

  neorv32_rte_setup();
  neorv32_uart_setup(NEORV32_UART0, uart_baud, 0);
}


/**********************************************************************//**
 * Simple busy-wait function.
 *
 * @param[in] time_ms Time so wait in ms.
 **************************************************************************/
// Simple busy-wait delay function
void hal_cpu_delay_ms(uint32_t time_ms) {

  neorv32_aux_delay_ms(neorv32_sysinfo_get_clk(), time_ms);
}

