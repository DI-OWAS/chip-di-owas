# Core Complex

The core complex ist based on the Fraunhofer IMS AIRISC family
of RISC-V cores for deeply-embedded applications. The core itself is published
unter the permissivee BSD-3-clause license.

## TODOs

* [ ] specify actual clock frequnecy
* [ ] add multi-UART module
* [ ] port openlane flow
* [ ] add AMD FPGA flow (which board?)
* [ ] add openlane flow to core complex makefile
* [ ] add FPGA flow to core complex makefile
* ...

## Folders

:warning: The folder layout may change to comply with other parts of the the DI-OWAS project.

* `asic`: 22nm proprietary ASIC implementation artifacts
* `fpga`: FPGA implementation scripts and artifacts
* `openlane`: 130nm open-source ASIC implementation sripts and artifacts
* `sim`: unit tests artifacts
* `src`: HDL sources and scripts

## Architecture

The core compley features a single RISC-V-compliant 32-bit CPU core.

:construction: **Under Construction** :construction:

### CPU Configuration

RISC-V ISA configuration:

* `I` - base integer ISA
* `Zicsr` - control and status registers (privileged architecture)
* `Zifencei` - instruction stream synchronization
* **T.B.A.**

### Processor Configuration

:construction: **Under Construction** :construction:

### CPU / Processor Documentation

* Data sheet: https://stnolting.github.io/neorv32/
* User guide: https://stnolting.github.io/neorv32/ug/
* Software reference: https://stnolting.github.io/neorv32/sw/files.html

### DI-OWAS-Specific Modules

:construction: **Under Construction** :construction:

