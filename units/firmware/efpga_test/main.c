#include <core_complex.h>
#include <stdio.h>
#include "bitstreams.h"

// configuration
#define BAUD_RATE 19200

// helper macros
#define REG32(addr) (*(volatile uint32_t*)(addr))

// eFPGA
#define EFPGA_BASE 0xF0000000U
#define EFPGA_CFG  REG32(EFPGA_BASE + 0)
#define EFPGA_DATA REG32(EFPGA_BASE + 4)


// Main function
int main() {

  int i;

  // initialize the platform
  hal_cpu_init(BAUD_RATE);

  // say hello
  printf("DI-OWAS - basic eFPGA test\r\n\r\n");


  // program bitstream
  uint32_t readback;
  int errors = 0;
  printf("programming bitstream...\r\n");
  for (i=0; i<(sizeof(demo_bitstream)/4); i++) {
    EFPGA_CFG = demo_bitstream[i];
    readback = EFPGA_CFG;
    if (readback != demo_bitstream[i]) {
      errors++;
    }
  }
  if (errors) {
    printf("FAILED!\r\n");
    return -1;
  }
  else {
    printf("OK\r\n");
  }

  // wait?
  for (i=0; i<100; i++) {
    asm volatile ("nop");
  }

  // send dummy data
  EFPGA_DATA = 0x01020302;
  asm volatile ("nop");
  asm volatile ("nop");
  asm volatile ("nop");
  printf("Result: 0x%lx\r\n", EFPGA_DATA);
  

  return 0;
}

