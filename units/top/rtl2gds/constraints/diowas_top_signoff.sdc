# pin definitions
set ext_clk_pin [get_ports clk_i_PAD]

set ext_rst_pin [get_ports rstn_i_PAD]

set cam_if_clk_pin [get_ports cam_pixel_clk_i_PAD]


# clock periods
set ext_clk_per 20.0
set dcv_clk_per 50.0

set ext_in_del_default 5.0
set ext_out_del_default 5.0

# Set a higher limits than in lib
set_max_fanout 16 [current_design]
#set_max_capacitance 0.5 [current_design]
set_max_transition 0.8 [current_design]
set_max_area 0

# clock definitions
create_clock -period $ext_clk_per $ext_clk_pin -name EXT_CLK
set_clock_uncertainty 0.1 [get_clocks EXT_CLK]
set_clock_transition 0.25 [get_clocks EXT_CLK]

create_clock -period $dcv_clk_per $cam_if_clk_pin -name DCV_CLK
set_clock_uncertainty 0.15 [get_clocks DCV_CLK]
set_clock_transition 0.25 [get_clocks DCV_CLK]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    set_ideal_network [all_clocks]
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}


# toplevel port timing
set_input_delay [expr 0.2 * $ext_clk_per] -clock [get_clocks {EXT_CLK}]  [get_ports {jtag_tdi_i_PAD jtag_tms_i_PAD jtag_tck_i_PAD}]
set_output_delay [expr 0.2 * $ext_clk_per] -clock [get_clocks {EXT_CLK}]  [get_ports jtag_tdo_o_PAD]

set_input_transition 0.5 [get_ports console_rxd_i_PAD]
# Bound the pad-to-synchronizer route (don't also add a false path on the same path)
set_max_delay [expr {1.0 * $ext_clk_per}] -from [get_ports console_rxd_i_PAD]
set_max_delay [expr {1.0 * $ext_clk_per}] -to   [get_ports console_txd_o_PAD]

# BH UAR
set_input_transition 0.5 [get_ports bhif_rxd_i_PAD[*]]
# Bound the pad-to-synchronizer route (don't also add a false path on the same path)
set_max_delay [expr {1.0 * $ext_clk_per}] -from [get_ports bhif_rxd_i_PAD[*]]
set_max_delay [expr {1.0 * $ext_clk_per}] -to   [get_ports bhif_cts_o_PAD]
    
# DCV interface
set_input_delay  [expr $ext_clk_per/4.0] -clock [get_clocks {DCV_CLK}]  [get_ports {cam_frame_valid_i_PAD cam_line_valid_i_PAD cam_pixel_data_i_PAD*}]
set_output_delay [expr $ext_clk_per/2.0] -clock [get_clocks {EXT_CLK}]  [get_ports {cam_doutif_valid_o_PAD cam_doutif_first_o_PAD cam_doutif_data_o_PAD*}]


# one-time O(N) index of flop instances
array set isff {}
foreach f [all_registers -edge_triggered -cells] {
    set isff([get_full_name $f]) 1
}

# SPI ram
# all outputs
foreach port [concat [get_ports spiram_csn_o_PAD[*]] [get_ports spiram_clk_o_PAD] [get_ports spiram_sdo_o_PAD] ] {
  set starts {}
  foreach c [get_fanin -to $port -flat -only_cells -startpoints_only] {
    if {[info exists isff([get_full_name $c])]} { lappend starts $c }
  }
  if {[llength $starts] == 0} {
    puts "WARNING: no flop startpoints found for [get_full_name $port]"
    continue
  }
  set_max_delay -ignore_clock_latency 7.5 -from $starts -to $port
}       
# input
set_input_delay  [expr 0.1 * $ext_clk_per] -clock [get_clocks {EXT_CLK}]  [get_ports spiram_sdi_i_PAD]


# SPI host
# all outputs
foreach port [concat [get_ports spi_csn_o_PAD[*]] [get_ports spi_sck_o_PAD] [get_ports spi_sdo_o_PAD] ] {
  set starts {}
  foreach c [get_fanin -to $port -flat -only_cells -startpoints_only] {
    if {[info exists isff([get_full_name $c])]} { lappend starts $c }
  }
  if {[llength $starts] == 0} {
    puts "WARNING: no flop startpoints found for [get_full_name $port]"
    continue
  }
  set_max_delay -ignore_clock_latency 7.5 -from $starts -to $port
}       
# input
set_input_delay  [expr 0.1 * $ext_clk_per] -clock [get_clocks {EXT_CLK}]  [get_ports spi_sdi_i_PAD]


# QSPI memory controller. Derived from FPGA I/O constraints for now.
source $::env(DESIGN_DIR)/../constraints/psram_interface.sdc


# timing exceptions
set_false_path -through $ext_rst_pin

set_false_path -through [get_pins IOPad_io_status_led/*]

set_clock_groups -asynchronous \
                 -group [get_clocks EXT_CLK] \
                 -group [get_clocks DCV_CLK]

