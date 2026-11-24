# QSPI PSRAM Controller

Responsible: Fraunhofer IMS, S. Nolting

A generic QSPI PSRAM controller that provides two host ports (Wishbone; accessible
via AXI wrappers): one for the module's control and status registers and another
one for transparently accessing the PSRAM memory.

Tested with: apmemory APS1604M-3SQR QSPI/QPI PSRAM

## Folders

* `src`: HDL sources and scripts

## TODOs

* add PSRAM burst supports
* add full AXI4 interface for memory access
* (add simple r/w cache; direct-mapped)

