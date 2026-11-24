// ************************************************************
// The DI-OWAS Project
// Top module for the Digilent Nexys Video test setup
//
// (c) Copyright 2025 Fraunhofer IMS, Stephan Nolting
// ************************************************************

module nexys_video
(
  // global control
  input        clk_i,
  input        rstn_i,
  // jtag on-chip debugger interface
  input        jtag_tck_i,
  input        jtag_tdi_i,
  output       jtag_tdo_o,
  input        jtag_tms_i,
  // gpio
  output       status_led_o,
  // uart0
  output       console_txd_o,
  input        console_rxd_i,
  // QSPI PSRAM
  output       psram_clk_o,
  output       psram_csn_o,
  inout  [3:0] psram_data_io
);

  wire [3:0] psram_di, psram_do, psram_oe;

  diowas_top diowas_top_inst (
    // global control
    .clk_i              (clk_i),
    .rstn_i             (rstn_i),
    // jtag on-chip debugger interface
    .jtag_tck_i         (jtag_tck_i),
    .jtag_tdi_i         (jtag_tdi_i),
    .jtag_tdo_o         (jtag_tdo_o),
    .jtag_tms_i         (jtag_tms_i),
    // Core complex: SPI host
    .spi_csn_o          (), // [Nol] TODO
    .spi_sck_o          (), // [Nol] TODO
    .spi_sdo_o          (), // [Nol] TODO
    .spi_sdi_i          (1'b0), // [Nol] TODO
    // Core complex: I2C host
    .twi_scl_o          (), // [Nol] TODO
    .twi_scl_i          (1'b1), // [Nol] TODO
    .twi_sda_o          (), // [Nol] TODO
    .twi_sda_i          (1'b1), // [Nol] TODO
    // gpio
    .status_led_o       (status_led_o),
    // uart0
    .console_txd_o      (console_txd_o),
    .console_rxd_i      (console_rxd_i),
    // QSPI PSRAM
    .psram_clk_o        (psram_clk_o),
    .psram_csn_o        (psram_csn_o),
    .psram_di           (psram_di),
    .psram_do           (psram_do),
    .psram_oe           (psram_oe),
    // Octal PSRAM
    .octram_bus_clk_o   (), // [UHD] TODO
    .octram_csn_o       (), // [UHD] TODO
    .octram_resetn_o    (), // [UHD] TODO
    .octram_strobe_i    (4'h0), // [UHD] TODO
    .octram_strobe_o    (), // [UHD] TODO
    .octram_strobe_oe_o (), // [UHD] TODO
    .octram_data_i      (32'h00000000), // [UHD] TODO
    .octram_data_o      (), // [UHD] TODO
    .octram_data_oe_o   (), // [UHD] TODO
    // camera Interface
    .cam_pixel_clk_i    (1'b0),
    .cam_frame_valid_i  (1'b0),
    .cam_line_valid_i   (1'b0),
    .cam_pixel_data_i   (12'h000),
    .cam_doutif_data_o  (),
    .cam_doutif_valid_o (),
    .cam_doutif_first_o (),
    .cam_doutif_clk_o   (),
    // BH Sensor IF UARTs
    .bhif_rxd_i         (2'b00),
    .bhif_cts_o         (),
    // eFPGA user IOs
    .efpga_io_out_o     (),
    .efpga_io_oe_o      (),
    .efpga_io_in_i      (8'h00)
  );

  // PSRAM tri-state [Nol] work-in-progress
  assign psram_di = psram_data_io;
  assign psram_data_io[0] = (psram_oe[0] == 1'b1) ? psram_do[0] : 1'bZ;
  assign psram_data_io[1] = (psram_oe[1] == 1'b1) ? psram_do[1] : 1'bZ;
  assign psram_data_io[2] = (psram_oe[2] == 1'b1) ? psram_do[2] : 1'bZ;
  assign psram_data_io[3] = (psram_oe[3] == 1'b1) ? psram_do[3] : 1'bZ;

endmodule

