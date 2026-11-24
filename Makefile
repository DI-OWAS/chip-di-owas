CHIP_ROOT_DIR := $(dir $(shell readlink -f $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash

all: impl_librelane FABulous

impl_librelane:
	$(MAKE) -C units/top/rtl2gds/librelane

OWAS_CONTAINER ?= /containers/manual/owas/latest
CMD_CONTAINER_FABULOUS := singularity exec -H $(CHIP_ROOT_DIR) $(OWAS_CONTAINER)
FABulous: export FAB_ROOT=$(CHIP_ROOT_DIR)vendor/FABulous
FABulous:
	$(CMD_CONTAINER_FABULOUS) bash -c "python3 -m venv venv_fabulous"
	$(CMD_CONTAINER_FABULOUS) bash -c "source venv_fabulous/bin/activate && pip install docker numpy fasm"
	$(CMD_CONTAINER_FABULOUS) bash -c "source venv_fabulous/bin/activate && cd ${FAB_ROOT} && python3 FABulous.py -c test"
	echo -e "load_fabric\ngen_all_tile\ngen_fabric\nexit" > ${FAB_ROOT}/test.script
	$(CMD_CONTAINER_FABULOUS) bash -c "source venv_fabulous/bin/activate && cd ${FAB_ROOT} && python3 FABulous.py -s test.script test"

.PHONY: all tb impl_librelane FABulous
