// Copyright 2026 Fraunhofer Institute for Microelectronic Circuits and Systems (IMS), Duisburg, Germany.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// DI-OWAS Project
//
// File     : core_complex_top.v
// Author   : S. Nolting
// Creation : 17.08.2026
// Abstract : RISC-V core complex top module

module core_complex_top (
  // global control
  input         clk_i,
  input         rstn_i,
  // axi4-lite-compatible host interface
  output [31:0] m_axi_awaddr,
  output  [7:0] m_axi_awlen,
  output  [2:0] m_axi_awsize,
  output  [1:0] m_axi_awburst,
  output  [3:0] m_axi_awcache,
  output  [2:0] m_axi_awprot,
  output        m_axi_awvalid,
  input         m_axi_awready,
  //
  output [31:0] m_axi_wdata,
  output  [3:0] m_axi_wstrb,
  output        m_axi_wlast,
  output        m_axi_wvalid,
  input         m_axi_wready,
  //
  output [31:0] m_axi_araddr,
  output  [7:0] m_axi_arlen,
  output  [2:0] m_axi_arsize,
  output  [1:0] m_axi_arburst,
  output  [3:0] m_axi_arcache,
  output  [2:0] m_axi_arprot,
  output        m_axi_arvalid,
  input         m_axi_arready,
  //
  input  [31:0] m_axi_rdata,
  input   [1:0] m_axi_rresp,
  input         m_axi_rlast,
  input         m_axi_rvalid,
  output        m_axi_rready,
  //
  input   [1:0] m_axi_bresp,
  input         m_axi_bvalid,
  output        m_axi_bready,
  // jtag on-chip debugger interface
  input         jtag_tck_i,
  input         jtag_tdi_i,
  output        jtag_tdo_o,
  input         jtag_tms_i,
  // spi
  output  [1:0] spi_csn_o,
  output        spi_sck_o,
  output        spi_sdo_o,
  input         spi_sdi_i,
  // I2C host
  output        twi_scl_o,
  input         twi_scl_i,
  output        twi_sda_o,
  input         twi_sda_i,
  // gpio
  output        status_led_o,
  // uart0
  output        console_txd_o,
  input         console_rxd_i,
  // system reset control
  output [15:0] sys_resetn_o,
  // internal interrupts
  input  [15:0] irq_i
);

  core_complex_wrapper core_complex_wrapper_inst (
    // global control
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),
    // axi4-lite-compatible host interface
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awcache (m_axi_awcache),
    .m_axi_awprot  (m_axi_awprot),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    //
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    //
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arcache (m_axi_arcache),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    //
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),
    //
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready),
    // jtag on-chip debugger interface
    .jtag_tck_i    (jtag_tck_i),
    .jtag_tdi_i    (jtag_tdi_i),
    .jtag_tdo_o    (jtag_tdo_o),
    .jtag_tms_i    (jtag_tms_i),
    // spi host
    .spi_csn_o     (spi_csn_o),
    .spi_sck_o     (spi_sck_o),
    .spi_sdo_o     (spi_sdo_o),
    .spi_sdi_i     (spi_sdi_i),
    // I2C host
    .twi_scl_o     (twi_scl_o),
    .twi_scl_i     (twi_scl_i),
    .twi_sda_o     (twi_sda_o),
    .twi_sda_i     (twi_sda_i),
    // gpio
    .status_led_o  (status_led_o),
    // uart0
    .console_txd_o (console_txd_o),
    .console_rxd_i (console_rxd_i),
    // system reset control
    .sys_resetn_o  (sys_resetn_o),
    // interrupts
    .irq_i         (irq_i)
  );

endmodule

