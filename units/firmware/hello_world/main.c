#include <core_complex.h>
#include <stdio.h>

// UART baud rate
#define BAUD_RATE 19200

// Main function
int main() {

  // initialize the platform
  hal_cpu_init(BAUD_RATE);

  // say hello
  neorv32_uart0_printf("Hello OWAS!\r\n\r\n");
  neorv32_uart0_printf("TEST PASS\r\n");

  return 0;
}

