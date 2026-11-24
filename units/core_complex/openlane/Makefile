MAKEFILE_DIR := $(shell dirname $(shell readlink -f $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell readlink -f "$(MAKEFILE_DIR)/../../../")
RUNS_DIR := $(ROOT_DIR)/rundirs/openlane_test_top
OWAS_CONTAINER ?= /containers/manual/owas/latest

all: OpenLane

CMD_CONTAINER_OpenLane := singularity exec -H $(ROOT_DIR) -B $(ROOT_DIR) $(OWAS_CONTAINER)
OpenLane:
	$(CMD_CONTAINER_OpenLane) flow.tcl -design $(MAKEFILE_DIR) -run_path $(RUNS_DIR)

.PHONY: all OpenLane
