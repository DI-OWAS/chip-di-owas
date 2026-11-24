MAKEFILE_DIR := $(shell dirname $(shell readlink -f $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell readlink -f "$(MAKEFILE_DIR)/../../../../")

# all result data will be stored here:
RUNS_DIR := $(ROOT_DIR)/rundirs/librelane_top
# latest rundir:
LATEST_RUNS_DIR := $(shell find $(RUNS_DIR) -maxdepth 1 -type d | sort | tail -n 1)

OWAS_CONTAINER ?= /einc/containers/owas/stable/latest
#OWAS_CONTAINER ?= /einc/containers/owas/stable/2026-08-17_2.img

# PDK needs to be provided with the standard OpenLane/LibreLane dir structure and
# the file 'config.tcl' in subfolder $(PDK_ROOT)/$(PDK)/libs.tech/librelane/
#PDK_ROOT ?= /usr/local/share/pdk/IHP-Open-PDK
PDK_ROOT ?= $(ROOT_DIR)/vendor/IHP-Open-PDK
#PDK      ?= ihp-sg13g2
PDK      ?= ihp-sg13cmos5l

PDK_5L_URL    := https://github.com/IHP-GmbH/ihp-sg13cmos5l.git
PDK_5L_DIR    := $(PDK_ROOT)/ihp-sg13cmos5l
PDK_5L_BRANCH := main


# for standard run tagging
TSTAMP := $(shell /bin/date "+%Y-%m-%d_%H-%M-%S")

# from and to steps for the resp. target:
FROM_STEP := OpenROAD.CheckSDCFiles
TO_STEP   := OpenROAD.STAPostPNR

FROM_DIR := $(shell find $(LATEST_RUNS_DIR) -maxdepth 1 -type d -name *$(shell echo $(subst .,"-",$(FROM_STEP)) | tr A-Z a-z))
TO_DIR   := $(shell find $(LATEST_RUNS_DIR) -maxdepth 1 -type d -name *$(shell echo $(subst .,"-",$(TO_STEP)) | tr A-Z a-z))

# LibreLane command with potential env defs
LL_CMD := PYTHONPATH=$(MAKEFILE_DIR)/scripts:$$PYTHONPATH librelane


all: vhdl_to_verilog unzip_macro ll_synth_only

full_impl: vhdl_to_verilog unzip_macro LibreLane

vhdl_to_verilog:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf $(OWAS_CONTAINER) bash -c "make -C $(ROOT_DIR)/units/top vhdl_to_verilog -B" ;

unzip_macro:
	find $(ROOT_DIR)/vendor/MLFPGA_engine/final -type f -iname "*.zip" -execdir gunzip -f -k -S .zip {} \;

LibreLane:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf $(OWAS_CONTAINER) bash -c '$(LL_CMD) \
	  --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(RUNS_DIR)/RUN_$(TSTAMP)' ;

synth_explore:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf $(OWAS_CONTAINER) bash -c '$(LL_CMD) \
	  --flow SynthesisExploration --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(RUNS_DIR)/RUN_$(TSTAMP)' ;

ll_gui:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) $(OWAS_CONTAINER) bash -c "$(LL_CMD) --log-level VERBOSE \
	  --flow OpenInOpenROAD --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(LATEST_RUNS_DIR)" ;

ll_steps:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf $(OWAS_CONTAINER) bash -c '$(LL_CMD) \
	  --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) --from $(FROM_STEP) --to $(TO_STEP) --with-initial-state $(FROM_DIR)/state_in.json \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(LATEST_RUNS_DIR)' ;

ll_synth_only:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf $(OWAS_CONTAINER) bash -c '$(LL_CMD) \
	  --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) --to OpenROAD.STAPrePNR \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(RUNS_DIR)/RUN_$(TSTAMP)' ; \
	tar czf "$(RUNS_DIR)/RUN_$(TSTAMP)/synthesis_result.tar.gz" -C "$(RUNS_DIR)/RUN_$(TSTAMP)"/*yosys-synthesis* . ; \
	tar czf "$(RUNS_DIR)/RUN_$(TSTAMP)/sta_prepnr_reports.tar.gz" -C "$(RUNS_DIR)/RUN_$(TSTAMP)"/*openroad-staprepnr . ;

ll_klayout:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) $(OWAS_CONTAINER) bash -c "$(LL_CMD) --log-level VERBOSE \
	  --flow OpenInKLayout --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(LATEST_RUNS_DIR)" ;

ll_magic:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) --no-mount /etc/apptainer --no-mount /etc/apptainer/apptainer.conf -B $(ROOT_DIR) $(OWAS_CONTAINER) bash -c "$(LL_CMD) --log-level VERBOSE \
	  --flow OpenInMagic --manual-pdk --pdk-root $(PDK_ROOT) --pdk $(PDK) \
	  $(MAKEFILE_DIR)/config.yaml --design-dir $(MAKEFILE_DIR) --run-tag $(LATEST_RUNS_DIR)" ;

info:
	echo $(FROM_DIR)

ll_help:
	apptainer exec --writable-tmpfs -H $(ROOT_DIR) -B $(ROOT_DIR) $(OWAS_CONTAINER) bash -c "$(LL_CMD) --help";

.PHONY: LibreLane



ifeq ($(STDCELL_LIB),tulip)
include $(ROOT_DIR)/vendor/tulip/librelane.mk
endif
