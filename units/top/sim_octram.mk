# Octal PSRAM system simulation (iverilog). Run from units/top:
#   make -f sim_octram.mk <target> [options]
#
#   rtl_core  RTL of diowas_top (TECH_FPGA path)
#   rtl_pads  RTL with the pad ring (diowas_top_pads)
#   gl_pads   netlist of diowas_top_pads (GL_NETLIST)
#
# Options:
#   GL_NETLIST=<file>     gl_pads: gate-level netlist of diowas_top_pads
#   BOOT_IMAGE=<file>     SPI flash image (default: octram_test)
#   STOP_AFTER_DMA=1      end after the JTAG tests
#   WAVEDUMP=1            write a VCD
#   CMOS5L_PDK=<dir>      SG13CMOS5L PDK (default: PDK_ROOT, else the ciel install)
#   DCV=1                 also run the DC-Vision test of the TB (20 ms simulated wait)
#   OCTRAM_RESET_CYCLES   PSRAM RESET# low time in clocks (default 500, chip 20 ms).
#                         For gl_pads it is set at synthesis of the sim netlist, never for the chip.
#
# The eFPGA is a stub (src/sim/efpga_subsystem_stub.sv).

# SPDX-FileCopyrightText: 2026 DI-OWAS team
# SPDX-License-Identifier: Apache-2.0

include Makefile
.DEFAULT_GOAL := help_octram

BUILD := build/sim_octram

OCTRAM_RESET_CYCLES ?= 500
FW_IMAGE   := ../firmware/octram_test/octram_boot_image.mem
BOOT_IMAGE ?= $(FW_IMAGE)
GL_NETLIST ?=
DCV        ?= 0

IVERILOG_FLAGS = -g2012 -s diowas_top_tb -I $(INC_SIM) -DIHP_CMOS5L \
  -DOCTRAM_RESET_CYCLES=$(OCTRAM_RESET_CYCLES) '-DBOOT_IMAGE="$(BOOT_IMAGE)"' \
  $(if $(STOP_AFTER_DMA),-DTB_STOP_AFTER_DMA) $(if $(WAVEDUMP),-DWAVEDUMP) \
  $(if $(filter 1,$(DCV)),,-DTB_SKIP_DCV)

# --- simulation-only sources ---
CMOS5L_PDK   ?= $(firstword $(wildcard $(PDK_ROOT)/ihp-sg13cmos5l $(HOME)/.ciel/ihp-sg13/ihp-sg13cmos5l))
$(if $(wildcard $(CMOS5L_PDK)/libs.ref),,$(error SG13CMOS5L PDK not found (CMOS5L_PDK=$(CMOS5L_PDK)), set CMOS5L_PDK to the ihp-sg13cmos5l directory))
MODEL_PSRAM  := ../../vendor/QSPI_Memory_Controller/test/sim_models/aps12808l_model.v
MODELS_SRAM  := $(CMOS5L_PDK)/libs.ref/sg13cmos5l_sram/verilog/*.v
MODELS_IO    := $(CMOS5L_PDK)/libs.ref/sg13cmos5l_io/verilog/*.v
CELLS_SIM    := $(CMOS5L_PDK)/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_stdcell.v
MODELS_CELLS := $(CMOS5L_PDK)/libs.ref/sg13cmos5l_stdcell/verilog/sg13cmos5l_udp.v $(CELLS_SIM)
STUB_EFPGA   := src/sim/efpga_subsystem_stub.sv

# verilog-axi needs the Verilog-2005 time-0 run of "always @*". With -g2012 the
# crossbar state stays X after reset. The copies use always_comb.
SIM_AXI_DIR := $(BUILD)/verilog_axi
RTL_AXI_SIM := $(addprefix $(SIM_AXI_DIR)/,$(notdir $(wildcard $(RTL_AXI))))
$(SIM_AXI_DIR)/%.v: ../../vendor/verilog-axi/rtl/%.v
	@mkdir -p $(SIM_AXI_DIR)
	@sed -E 's/always @ ?(\*|\(\*\))/always_comb/' $< > $@

RTL_SIM := $(filter-out $(RTL_AXI) $(RTL_EFPGA),$(FILES_RTL)) $(RTL_AXI_SIM) $(STUB_EFPGA)

FILES_RTL_CORE := $(FILES_SIM) $(MODEL_PSRAM) $(RTL_SIM) $(MODELS_SRAM)
FILES_RTL_PADS := $(FILES_SIM) $(MODEL_PSRAM) $(RTL_SIM) $(RTL_TOP_ASIC) $(MODELS_IO) $(MODELS_SRAM)
FILES_GL_PADS  := $(FILES_SIM) $(MODEL_PSRAM) $(GL_NETLIST) $(STUB_EFPGA) $(MODELS_CELLS) $(MODELS_IO) $(MODELS_SRAM)

# --- targets ---
.PHONY: help_octram rtl_core rtl_pads gl_pads fw_image clean_octram

fw_image $(FW_IMAGE):
	$(MAKE) -C ../firmware/octram_test sim_image

# $(1) = run name, $(2) = files, $(3) = extra iverilog flags
define octram_run
	@mkdir -p $(BUILD)
	@echo "Compiling $(1) (iverilog) ..."
	iverilog $(IVERILOG_FLAGS) $(3) -o $(BUILD)/$(1).sim $(2)
	@echo "Running $(1), log: $(BUILD)/$(1).log ..."
	vvp -n -l $(BUILD)/$(1).log $(BUILD)/$(1).sim > /dev/null
	@grep -q '\[TB\] Simulation successful!' $(BUILD)/$(1).log && echo "$(1): PASS" || (echo "$(1): FAIL, see $(BUILD)/$(1).log"; exit 1)
endef

rtl_core: vhdl_to_verilog $(RTL_AXI_SIM) $(BOOT_IMAGE)
	$(call octram_run,rtl_core,$(FILES_RTL_CORE),-DTECH_FPGA=1)

rtl_pads: vhdl_to_verilog $(RTL_AXI_SIM) $(BOOT_IMAGE)
	$(call octram_run,rtl_pads,$(FILES_RTL_PADS))

gl_pads: $(BOOT_IMAGE) $(CELLS_SIM)
	@test -n "$(GL_NETLIST)" || (echo "set GL_NETLIST=<gate-level netlist of diowas_top_pads>"; exit 1)
	$(call octram_run,gl_pads,$(FILES_GL_PADS),-DGATE_LEVEL -DFUNCTIONAL)

clean_octram:
	rm -rf $(BUILD)

help_octram:
	@sed -n '/^#/!q;2,$$s/^# \{0,1\}//p' sim_octram.mk
