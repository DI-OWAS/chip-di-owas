# Use this makefile to configure all relevant CPU / compiler options
# as these cannot be set by Eclipse (since this is a makefile-based project).

# Override the default CPU ISA
MARCH = rv32imc_zicsr_zifencei

# Override the default RISC-V GCC prefix
RISCV_PREFIX ?= riscv-none-elf-

# Override default optimization goal
EFFORT = -Os

# Additional sources
APP_SRC += \
$(wildcard ./*.c) \
$(wildcard ../hal/src/*.c)

APP_INC += \
-I . \
-I ../hal/inc

# Adjust processor memory base/size and heap
USER_FLAGS += \
-Wl,--defsym,__neorv32_rom_size=4k \
-Wl,--defsym,__neorv32_rom_base=0x00000000 \
-Wl,--defsym,__neorv32_ram_size=4k \
-Wl,--defsym,__neorv32_ram_base=0x80000000 \
-ggdb -gdwarf-3

# Set path to NEORV32 root directory
NEORV32_HOME ?= ../../../vendor/neorv32
include $(NEORV32_HOME)/sw/common/common.mk
