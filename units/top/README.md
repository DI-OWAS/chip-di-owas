# DI-Owas Top

:construction work in progress :construction

### Current Modules

* Core Complex
* AXI4 interconnect
* Generic RAM_0
* Generic RAM_1
* System controller

### Address Map

* `0xC0000000` - RAM_0
* `0xD0000000` - RAM_1
* `0xF0000000` - system controller

### Octal PSRAM system simulation

`sim_octram.mk` runs `diowas_top_tb` with four APS12808L PSRAM models in
iverilog, as RTL or with gate-level netlists of single instances. Run it from
`units/top`. `make -f sim_octram.mk` lists the targets and options.

Needs iverilog 13, the VHDL to Verilog conversion of the top `Makefile`
(`make vhdl_to_verilog`, project container), the `riscv-none-elf-` GCC for the
test firmware (`../firmware/octram_test`, built automatically) and the
SG13CMOS5L PDK (`CMOS5L_PDK`, default: ciel install). `gl_inst` also needs
yosys and the verilog-axi patch (`make patch`).

```
make -f sim_octram.mk rtl_pads STOP_AFTER_DMA=1   # JTAG tests only
make -f sim_octram.mk rtl_pads                    # with the octram_test firmware (hours)
make -f sim_octram.mk gl_inst                     # AXI interconnect at gate level (hours)
```

A run passes with `[TB] Simulation successful!` in `build/sim_octram/<run>.log`.

The PSRAM model is not a vendor model: it was written with AI assistance from the
APS12808L datasheet (Rev. 1.5), see
`vendor/QSPI_Memory_Controller/test/sim_models/aps12808l_model.v` in the
controller repository.
