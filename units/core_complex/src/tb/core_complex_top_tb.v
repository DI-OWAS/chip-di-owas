// Copyright 2024 Fraunhofer Institute for Microelectronic Circuits and Systems (IMS), Duisburg, Germany.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// DI-OWAS Project
//
// File     : core_complex_top_tb.v
// Author   : S. Nolting
// Creation : 20.09.2023
// Abstract : cpu-complex testbench

`timescale 1 ns/100 ps // time-unit = 1 ns, precision = 100 ps

module core_complex_top_tb;

  reg clk, clk_en, rstn;
  wire uart0_rxd, uart0_txd, status_led;

  // ----------------------------------------------------------
  // Configuration
  // ----------------------------------------------------------
  parameter SYS_CLK_KHZ = 100000; // system clock in kHz
  parameter UART0_BAUD  = 19200; // default baud rate
  // ----------------------------------------------------------

  real sys_clk_t2 = 0.5 * (1.0/(SYS_CLK_KHZ * 1e3) * 1e9); // 50% duty cycle


  // ----------------------------------------------------------------------------
  // System clock generator
  // ----------------------------------------------------------------------------
  always @(posedge clk_en or negedge clk_en) begin
    if (clk_en == 1'b1) begin
      while (clk_en == 1'b1) begin
        #(sys_clk_t2) clk = 0;
        #(sys_clk_t2) clk = 1;
      end
    end else begin
      clk = 1'b0;
    end
  end


  // ----------------------------------------------------------------------------
  // Simulated system
  // ----------------------------------------------------------------------------
  core_complex_top core_complex_top_dut (
    // global control
    .clk_i         (clk),
    .rstn_i        (rstn),
    // axi4-lite-compatible host interface
    .m_axi_awaddr  (),
    .m_axi_awprot  (),
    .m_axi_awvalid (),
    .m_axi_awready (1'b0),
    .m_axi_wdata   (),
    .m_axi_wstrb   (),
    .m_axi_wvalid  (),
    .m_axi_wready  (1'b0),
    .m_axi_araddr  (),
    .m_axi_arprot  (),
    .m_axi_arvalid (),
    .m_axi_arready (1'b0),
    .m_axi_rdata   (32'h00000000),
    .m_axi_rresp   (2'b00),
    .m_axi_rvalid  (1'b0),
    .m_axi_rready  (),
    .m_axi_bresp   (2'b00),
    .m_axi_bvalid  (1'b0),
    .m_axi_bready  (),
    // jtag on-chip debugger interface
    .jtag_tck_i    (1'b0),
    .jtag_tdi_i    (1'b0),
    .jtag_tdo_o    (),
    .jtag_tms_i    (1'b0),
    // gpio
    .status_led_o  (status_led),
    // uart0
    .console_txd_o (uart0_txd),
    .console_rxd_i (uart0_rxd)
  );


  // ----------------------------------------------------------------------------
  // UART receiver
  // ----------------------------------------------------------------------------
  wire [7:0] char_data; // character detected by the UART receiver
  wire char_valid; // valid character

  uart_sim_receiver #(
    .CLOCK_FREQ (SYS_CLK_KHZ*1000),
    .BAUD_RATE  (UART0_BAUD)
  ) uart_sim_receiver_inst(
    .clk_i   (clk),
    .txd_i   (uart0_txd),
    .data_o  (char_data),
    .valid_o (char_valid)
  );

  // buffer the processor's UART data in a small FIFO-like queue
  reg [7:0] char_buffer [0:6];
  integer i;
  always @(posedge clk) begin
    // update "FIFO"
    if (char_valid == 1'b1) begin
      // top-to-bottom shift
      for (i=6; i>0; i=i-1) begin
        char_buffer[i-1] <= char_buffer[i];
      end
      char_buffer[6] <= char_data;
    end
    // check for bootloader intro string
    if ((char_buffer[0] == "N") &&
        (char_buffer[1] == "E") &&
        (char_buffer[2] == "O") &&
        (char_buffer[3] == "R") &&
        (char_buffer[4] == "V") &&
        (char_buffer[5] == "3") &&
        (char_buffer[6] == "2")) begin
      // simulation was successful
      $display (""); // force line break
      $display("[TB] Simulation successful!");
      $display (""); // force line break
      $finish; // terminate
    end
  end


  // ----------------------------------------------------------------------------
  // Stimulus
  // ----------------------------------------------------------------------------
  initial begin
    clk  = 0;
    rstn = 0;
    #10;
    clk_en = 1'b1;
    #10;

    rstn = 1'b0;
    #20; // active reset for 20 ns
    rstn = 1'b1;

    #500

    $display("[TB] DI-OWAS Core-Complex Testbench >>");
    $display("[TB] f_clk SYS: %0d kHz", SYS_CLK_KHZ);

    // work in progress

    #50_000_000
    $display ("[TB] WARNING! Simulation timeout!");
    $finish();
  end


endmodule
