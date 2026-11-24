set ext_clk_pin [get_ports clk_i]
set jtag_clk_pin [get_ports jtag_tck_i]

set ext_rst_pin [get_ports rstn_i]

set ext_clk_per 10.0
set jtag_clk_per 20.0

set ext_in_del_default 5.0
set ext_out_del_default 5.0

# clock definitions
create_clock -period $ext_clk_per $ext_clk_pin -name EXT_CLK

create_clock -period $jtag_clk_per $jtag_clk_pin -name JTAG_CLK


# interface timing
set_input_delay [expr $ext_clk_per/2.0] -clock [get_clocks {EXT_CLK}]  [get_ports {m_axi_awready m_axi_wready m_axi_arready m_axi_rdata* m_axi_rresp* m_axi_rvalid m_axi_bresp* m_axi_bvalid}]
set_output_delay 0.0 -clock [get_clocks {EXT_CLK}]  [get_ports {m_axi_awaddr* m_axi_awprot* m_axi_awvalid m_axi_wdata* m_axi_wstrb* m_axi_wvalid m_axi_araddr* m_axi_arprot* m_axi_arvalid m_axi_rready m_axi_bready}]

set_input_delay [expr $jtag_clk_per/2.0] -clock [get_clocks {JTAG_CLK}]  [get_ports {jtag_tdi_i jtag_tms_i}]
set_output_delay 0.0 -clock [get_clocks {JTAG_CLK}]  [get_ports {jtag_tdo_o}]


# timing exceptions
set_false_path -through $ext_rst_pin

set_false_path -to [get_ports status_led_o]

set_false_path -from EXT_CLK -to JTAG_CLK
set_false_path -from JTAG_CLK -to EXT_CLK

