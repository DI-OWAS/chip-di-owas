# author: nolting; FhG IMS, Jan 2025

all: clean project bitstream

.DEFAULT_GOAL := help

# recreate vivado project file from tcl script
project:
	make -C ../../core_complex vhdl_to_verilog
	vivado -mode batch -notrace -source nexys_video.tcl

# open vivado project in GUI
gui:
	vivado work/nexys_video.xpr

# generate bitstream
bitstream:
	vivado -mode batch -notrace -source generate_bitstream.tcl

# remove ALL(!) Vivado and SRC artifacts
clean:
	rm -rf work/ .Xil/
	rm -f *.log *.jou *.str
	rm -f *_webtalk.html
	rm -f *_webtalk.xml

# help menu
help:
	@echo "-----------------------------------------------"
	@echo " DI-OWAS Top - FPGA Makefile "
	@echo "-----------------------------------------------"
	@echo " help      - show this text"
	@echo " clean     - remove all local build artifacts"
	@echo " project   - recreate Vivado project"
	@echo " gui       - open Vivado project in GUI mode"
	@echo " bitstream - generate bitstream in console mode"

