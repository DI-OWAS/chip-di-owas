#include <neorv32.h>

// UART baud rate
#define BAUD_RATE 19200
#define PSRAM_CTRL 0xF2000000
#define PSRAM_BASE 0x10000000
#define PSRAM_SIZE 2*1024*1024

// test data generator
volatile uint32_t x32;
uint32_t xorshift32()
{
    x32 ^= x32 << 13;
    x32 ^= x32 >> 17;
    x32 ^= x32 << 5;
    return x32;
}


// Main function
int main() {

  // initialize the platform
  neorv32_rte_setup();

  // setup UART at default baud rate, no interrupts
  neorv32_uart0_setup(BAUD_RATE, 0);

  int i;
  int errors = 0;
  uint32_t ref, res;
  uint8_t ref8, res8;

  neorv32_uart0_printf("PSRAM test\n");

  neorv32_cpu_store_unsigned_word(PSRAM_CTRL + 0, 0x00000000); // reset
  neorv32_cpu_store_unsigned_word(PSRAM_CTRL + 4, 0x35996600); // init sequence
  neorv32_cpu_store_unsigned_word(PSRAM_CTRL + 8, 0x000042b1); // PSRAM mode register
  neorv32_cpu_store_unsigned_word(PSRAM_CTRL + 0, 0x020b04a1); // control and status register

  // --------------------------------------------
  // Word-wise clear
  // --------------------------------------------

  neorv32_uart0_printf("clear... ");
  errors = 0;
  for (i=0; i<PSRAM_SIZE; i+=4) {
    neorv32_cpu_store_unsigned_word(PSRAM_BASE + i, 0);
  }

  for (i=0; i<PSRAM_SIZE; i+=4) {
    if (neorv32_cpu_load_unsigned_word(PSRAM_BASE + i) != 0) {
      errors++;
    }
  }
  neorv32_uart0_printf("errors: %u\n", errors);

  // --------------------------------------------
  // Word-wise write
  // --------------------------------------------

  neorv32_uart0_printf("word... ");
  x32 = 0xcafebabe;
  for (i=0; i<PSRAM_SIZE; i+=4) {
    ref = xorshift32();
    neorv32_cpu_store_unsigned_word(PSRAM_BASE + i, ref);
    res = neorv32_cpu_load_unsigned_word(PSRAM_BASE + i);
    //neorv32_uart0_printf("[%u] <0x%x> ref = 0x%x vs res = 0x%x\n", i, PSRAM_BASE + i, ref, res);
  }

  x32 = 0xcafebabe;
  for (i=0; i<PSRAM_SIZE; i+=4) {
    ref = xorshift32();
    res = neorv32_cpu_load_unsigned_word(PSRAM_BASE + i);
    if (ref != res) {
      neorv32_uart0_printf("[%u] <0x%x> ref = 0x%x vs res = 0x%x\n", i, PSRAM_BASE + i, ref, res);
      errors++;
    }
  }
  neorv32_uart0_printf("errors: %u\n", errors);

  // --------------------------------------------
  // Byte-wise write
  // --------------------------------------------

  neorv32_uart0_printf("byte... ");
  x32 = 314159265;
  for (i=0; i<PSRAM_SIZE; i++) {
    neorv32_cpu_store_unsigned_byte(PSRAM_BASE + i, (uint8_t)xorshift32());
  }

  x32 = 314159265;
  for (i=0; i<PSRAM_SIZE; i++) {
    ref8 = (uint8_t)xorshift32();
    res8 = neorv32_cpu_load_unsigned_byte(PSRAM_BASE + i);
    if (ref8 != res8) {
      neorv32_uart0_printf("[%u] <0x%x> ref = 0x%x vs res = 0x%x\n", i, PSRAM_BASE + i, ref8, res8);
      errors++;
    }
  }
  neorv32_uart0_printf("byte errors: %u\n", errors);


  if (errors) {
    neorv32_uart0_printf("\nTEST FAILED!\n");
    return -1;
  }
  else {
    neorv32_uart0_printf("\nTEST PASSED!\n");
    return 0;
  }
}

