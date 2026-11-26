# SPDX-FileCopyrightText: 2026 DI-OWAS team
# SPDX-License-Identifier: Apache-2.0

MARCH = rv32emc_zicsr_zifencei
MABI = ilp32e

RISCV_PREFIX ?= riscv-none-elf-

EFFORT = -Os

APP_SRC += \
$(wildcard ./*.c) \
$(wildcard ../hal/src/*.c)

APP_INC += \
-I . \
-I ../hal/inc

# PSRAM chip size in MB: 16 (APS12808L, default) or 8 (64 Mbit chips)
OCTRAM_CHIP_MB ?= 16
OCTRAM_BASE    := 0x20000000
# exec_image: code in the last 4 MB of the PSRAM window, outside the test areas
EXEC_BASE := $(shell printf '0x%08X' $$(($(OCTRAM_BASE) + (4 * $(OCTRAM_CHIP_MB) - 4) * 0x100000)))
EXEC_SIZE := 1024k

# Code in SRAM0 (exec_image: in the PSRAM), data and stack in SRAM1
ROM_BASE ?= 0x00000000
ROM_SIZE ?= 16k
RAM_BASE := 0x80000000
RAM_SIZE := 8k

USER_FLAGS += \
-Wl,--defsym,__neorv32_rom_size=$(ROM_SIZE) \
-Wl,--defsym,__neorv32_rom_base=$(ROM_BASE) \
-Wl,--defsym,__neorv32_ram_size=$(RAM_SIZE) \
-Wl,--defsym,__neorv32_ram_base=$(RAM_BASE) \
-ggdb -gdwarf-3 \
-DOCTRAM_CHIP_MB=$(OCTRAM_CHIP_MB)U \
$(OCTRAM_FLAGS)

NEORV32_HOME ?= ../../../vendor/neorv32
include $(NEORV32_HOME)/sw/common/common.mk

# System TB image octram_boot_image.mem (SPI flash content): small regions, one pass
sim_image:
	$(MAKE) clean_all
	$(MAKE) OCTRAM_FLAGS=-DOCTRAM_SIM exe
	xxd -p -c 4 neorv32_exe.bin > octram_boot_image.mem

# Board image that runs from the PSRAM (link address EXEC_BASE)
exec_image:
	$(MAKE) clean_all
	$(MAKE) ROM_BASE=$(EXEC_BASE) ROM_SIZE=$(EXEC_SIZE) exe
