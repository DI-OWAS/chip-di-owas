// Copyright 2025 Fraunhofer Institute for Microelectronic Circuits and Systems (IMS), Duisburg, Germany.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// DI-OWAS Project
//
// File     : spram_ihp130nm.v
// Author   : S. Nolting
// Creation : 06.11.2025
// Abstract : Single-port SRAM using IHP 130nm primitives and AXI4 wrapper


module spram_ihp130nm
#(
  // Width of data bus in bits
  parameter DATA_WIDTH = 32,
  // Width of address bus in bits
  parameter ADDR_WIDTH = 16,
  // Width of wstrb (width of data bus in words)
  parameter STRB_WIDTH = (DATA_WIDTH/8),
  // Width of ID signal
  parameter ID_WIDTH = 6,
  // Extra pipeline register on output
  parameter PIPELINE_OUTPUT = 0
)
(
  input  wire                   clk,
  input  wire                   rst,

  input  wire [ID_WIDTH-1:0]    s_axi_awid,
  input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
  input  wire [7:0]             s_axi_awlen,
  input  wire [2:0]             s_axi_awsize,
  input  wire [1:0]             s_axi_awburst,
  input  wire                   s_axi_awlock,
  input  wire [3:0]             s_axi_awcache,
  input  wire [2:0]             s_axi_awprot,
  input  wire                   s_axi_awvalid,
  output wire                   s_axi_awready,
  input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
  input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
  input  wire                   s_axi_wlast,
  input  wire                   s_axi_wvalid,
  output wire                   s_axi_wready,
  output wire [ID_WIDTH-1:0]    s_axi_bid,
  output wire [1:0]             s_axi_bresp,
  output wire                   s_axi_bvalid,
  input  wire                   s_axi_bready,
  input  wire [ID_WIDTH-1:0]    s_axi_arid,
  input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
  input  wire [7:0]             s_axi_arlen,
  input  wire [2:0]             s_axi_arsize,
  input  wire [1:0]             s_axi_arburst,
  input  wire                   s_axi_arlock,
  input  wire [3:0]             s_axi_arcache,
  input  wire [2:0]             s_axi_arprot,
  input  wire                   s_axi_arvalid,
  output wire                   s_axi_arready,
  output wire [ID_WIDTH-1:0]    s_axi_rid,
  output wire [DATA_WIDTH-1:0]  s_axi_rdata,
  output wire [1:0]             s_axi_rresp,
  output wire                   s_axi_rlast,
  output wire                   s_axi_rvalid,
  input  wire                   s_axi_rready
);

  // ----------------------------------------------------------
  // AXI adapter
  // ----------------------------------------------------------

  wire [ADDR_WIDTH-1:0] cmd_addr;
  wire [ID_WIDTH-1:0] cmd_id;
  wire cmd_ready, resp_ready;
  reg [ID_WIDTH-1:0] read_id_q;
  wire [DATA_WIDTH-1:0] cmd_wdata, cmd_rdata;
  wire [STRB_WIDTH-1:0] cmd_wstb;
  wire cmd_we, cmd_re, cmd_rvld, cmd_last, cmd_rlast;

  axi_ram_wr_rd_if #(
    .DATA_WIDTH      (DATA_WIDTH), // Width of data bus in bits
    .ADDR_WIDTH      (ADDR_WIDTH), // Width of address bus in bits
    .STRB_WIDTH      (STRB_WIDTH), // Width of wstrb (width of data bus in words)
    .ID_WIDTH        (ID_WIDTH),   // Width of ID signal
    .AWUSER_ENABLE   (0),          // Propagate awuser signal
    .AWUSER_WIDTH    (1),          // Width of awuser signal
    .WUSER_ENABLE    (0),          // Propagate wuser signal
    .WUSER_WIDTH     (1),          // Width of wuser signal
    .BUSER_ENABLE    (0),          // Propagate buser signal
    .BUSER_WIDTH     (1),          // Width of buser signal
    .ARUSER_ENABLE   (0),          // Propagate aruser signal
    .ARUSER_WIDTH    (1),          // Width of aruser signal
    .RUSER_ENABLE    (0),          // Propagate ruser signal
    .RUSER_WIDTH     (1),          // Width of ruser signal
    .AUSER_WIDTH     (1),          // Width of auser output
    .PIPELINE_OUTPUT (0),          // Extra pipeline register on output
    .INTERLEAVE      (0)           // Interleave read and write burst cycles
  ) axi_adapter (
    // global interface
    .clk (clk),
    .rst (rst),
    // AXI slave interface
    .s_axi_awid     (s_axi_awid),
    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awlen    (s_axi_awlen),
    .s_axi_awsize   (s_axi_awsize),
    .s_axi_awburst  (s_axi_awburst),
    .s_axi_awlock   (s_axi_awlock),
    .s_axi_awcache  (s_axi_awcache),
    .s_axi_awprot   (s_axi_awprot),
    .s_axi_awqos    (4'b0000),
    .s_axi_awregion (4'b0000),
    .s_axi_awuser   (1'b0),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awready  (s_axi_awready),
    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wlast    (s_axi_wlast),
    .s_axi_wuser    (1'b0),
    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wready   (s_axi_wready),
    .s_axi_bid      (s_axi_bid),
    .s_axi_bresp    (s_axi_bresp),
    .s_axi_buser    (),
    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bready   (s_axi_bready),
    .s_axi_arid     (s_axi_arid),
    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arlen    (s_axi_arlen),
    .s_axi_arsize   (s_axi_arsize),
    .s_axi_arburst  (s_axi_arburst),
    .s_axi_arlock   (s_axi_arlock),
    .s_axi_arcache  (s_axi_arcache),
    .s_axi_arprot   (s_axi_arprot),
    .s_axi_arqos    (4'b0000),
    .s_axi_arregion (4'b0000),
    .s_axi_aruser   (1'b0),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_arready  (s_axi_arready),
    .s_axi_rid      (s_axi_rid),
    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rlast    (s_axi_rlast),
    .s_axi_ruser    (),
    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rready   (s_axi_rready),
    // RAM interface
    .ram_cmd_id        (cmd_id),
    .ram_cmd_addr      (cmd_addr),
    .ram_cmd_lock      (), // unused
    .ram_cmd_cache     (), // unused
    .ram_cmd_prot      (), // unused
    .ram_cmd_qos       (), // unused
    .ram_cmd_region    (), // unused
    .ram_cmd_auser     (), // unused
    .ram_cmd_wr_data   (cmd_wdata),
    .ram_cmd_wr_strb   (cmd_wstb),
    .ram_cmd_wr_user   (), // unused
    .ram_cmd_wr_en     (cmd_we),
    .ram_cmd_rd_en     (cmd_re),
    .ram_cmd_last      (cmd_last),
    .ram_cmd_ready     (cmd_ready),
    .ram_rd_resp_id    (read_id_q),
    .ram_rd_resp_data  (cmd_rdata),
    .ram_rd_resp_last  (cmd_rlast),
    .ram_rd_resp_user  (1'b0),
    .ram_rd_resp_valid (cmd_rvld),
    .ram_rd_resp_ready (resp_ready)
  );


  // ----------------------------------------------------------
  // SRAM primitives
  // ----------------------------------------------------------

  genvar i;
  wire  [3:0] sram_we;
  wire [31:0] sram_rdata;

  assign sram_we[0] = ((cmd_we == 1'b1) && (cmd_wstb[0] == 1'b1)) ? 1'b1 : 1'b0;
  assign sram_we[1] = ((cmd_we == 1'b1) && (cmd_wstb[1] == 1'b1)) ? 1'b1 : 1'b0;
  assign sram_we[2] = ((cmd_we == 1'b1) && (cmd_wstb[2] == 1'b1)) ? 1'b1 : 1'b0;
  assign sram_we[3] = ((cmd_we == 1'b1) && (cmd_wstb[3] == 1'b1)) ? 1'b1 : 1'b0;

//  generate
//    for (i=0; i<4; i=i+1) begin: ihp_srams
      RM_IHPSG13_1P_4096x8_c3_bm_bist sram_b0 (
       .A_CLK      (clk),
       .A_MEN      (cmd_re | cmd_we),
       .A_WEN      (sram_we[0]),
       .A_REN      (cmd_re),
       .A_ADDR     (cmd_addr[13:2]),
       .A_DIN      (cmd_wdata[0*8+7:0*8+0]),
       .A_DLY      (1'b1), // tie high!
       .A_DOUT     (sram_rdata[0*8+7:0*8+0]),
       .A_BM       ({8{sram_we[0]}}),

       .A_BIST_EN      (1'b0),
       .A_BIST_CLK     (1'b0),
       .A_BIST_MEN     (1'b0),
       .A_BIST_WEN     (1'b0),
       .A_BIST_REN     (1'b0),
       .A_BIST_ADDR    (12'h000),
       .A_BIST_DIN     (8'h00),
       .A_BIST_BM      (8'h00)
     );
      RM_IHPSG13_1P_4096x8_c3_bm_bist sram_b1 (
       .A_CLK      (clk),
       .A_MEN      (cmd_re | cmd_we),
       .A_WEN      (sram_we[1]),
       .A_REN      (cmd_re),
       .A_ADDR     (cmd_addr[13:2]),
       .A_DIN      (cmd_wdata[1*8+7:1*8+0]),
       .A_DLY      (1'b1), // tie high!
       .A_DOUT     (sram_rdata[1*8+7:1*8+0]),
       .A_BM       ({8{sram_we[1]}}),

       .A_BIST_EN      (1'b0),
       .A_BIST_CLK     (1'b0),
       .A_BIST_MEN     (1'b0),
       .A_BIST_WEN     (1'b0),
       .A_BIST_REN     (1'b0),
       .A_BIST_ADDR    (12'h000),
       .A_BIST_DIN     (8'h00),
       .A_BIST_BM      (8'h00)
     );
      RM_IHPSG13_1P_4096x8_c3_bm_bist sram_b2 (
       .A_CLK      (clk),
       .A_MEN      (cmd_re | cmd_we),
       .A_WEN      (sram_we[2]),
       .A_REN      (cmd_re),
       .A_ADDR     (cmd_addr[13:2]),
       .A_DIN      (cmd_wdata[2*8+7:2*8+0]),
       .A_DLY      (1'b1), // tie high!
       .A_DOUT     (sram_rdata[2*8+7:2*8+0]),
       .A_BM       ({8{sram_we[2]}}),

       .A_BIST_EN      (1'b0),
       .A_BIST_CLK     (1'b0),
       .A_BIST_MEN     (1'b0),
       .A_BIST_WEN     (1'b0),
       .A_BIST_REN     (1'b0),
       .A_BIST_ADDR    (12'h000),
       .A_BIST_DIN     (8'h00),
       .A_BIST_BM      (8'h00)
     );
      RM_IHPSG13_1P_4096x8_c3_bm_bist sram_b3 (
       .A_CLK      (clk),
       .A_MEN      (cmd_re | cmd_we),
       .A_WEN      (sram_we[3]),
       .A_REN      (cmd_re),
       .A_ADDR     (cmd_addr[13:2]),
       .A_DIN      (cmd_wdata[3*8+7:3*8+0]),
       .A_DLY      (1'b1), // tie high!
       .A_DOUT     (sram_rdata[3*8+7:3*8+0]),
       .A_BM       ({8{sram_we[3]}}),

       .A_BIST_EN      (1'b0),
       .A_BIST_CLK     (1'b0),
       .A_BIST_MEN     (1'b0),
       .A_BIST_WEN     (1'b0),
       .A_BIST_REN     (1'b0),
       .A_BIST_ADDR    (12'h000),
       .A_BIST_DIN     (8'h00),
       .A_BIST_BM      (8'h00)
     );
//    end
//  endgenerate


  // read-back control
  reg valid_q, last_q;

  always @ (posedge clk) begin
    if (rst == 1'b1) begin
      valid_q <= 1'b0;
      last_q  <= 1'b0;
      read_id_q <= {ID_WIDTH{1'b0}};
    end else if (cmd_ready) begin
      valid_q <= cmd_re;
      if (cmd_re) begin
        last_q <= cmd_last;
        read_id_q <= cmd_id;
      end
    end
  end

  // Hold response ID, data and LAST until the AXI adapter accepts them.
  assign cmd_ready = !valid_q || resp_ready;
  assign cmd_rvld  = valid_q;
  assign cmd_rlast = last_q;
  assign cmd_rdata = (valid_q == 1'b1) ? sram_rdata : 32'h00000000;

endmodule


