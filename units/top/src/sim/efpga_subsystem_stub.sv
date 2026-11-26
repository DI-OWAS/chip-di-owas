// SPDX-FileCopyrightText: 2026 DI-OWAS team
// SPDX-License-Identifier: Apache-2.0
// Simulation stub for efpga_subsystem_top: same ports, no function.
// AXI-lite slaves always ready, reads return 0xdeadc0de, AXI master idle.

`timescale 1ns / 1ps

module efpga_subsystem_top #(
    // Only NUM_SLOTS and AXI_ID_WIDTH set port widths, the rest keep overrides compiling
    parameter int NUM_SLOTS        = 1,
    parameter int AXI_ID_WIDTH     = 8,
    parameter logic [31:0] HW_VERSION = 32'hFAB00001,
    parameter int WEIGHT_SPLIT      = 8,
    parameter int USE_LADDER_CLOCKS = 0
) (
    // Global Clock & eFPGA Subsystem Reset Domain Inputs (from Top-Level Reset Controller)
    input  logic                                clk_i,
    input  logic                                rst_efpga_connector_n_i, // Active-Low Reset for eFPGA AXI Connector (Manager, Decouplers, Watchdogs, Bridges)
    input  logic                                rst_efpga_connector_i,   // Active-High Reset for eFPGA AXI Register Slices (Forencich IP)
    input  logic                                rst_efpga_fabric_n_i,    // Active-Low Configuration FSM Reset for eFPGA Fabric
    input  logic [NUM_SLOTS-1:0][3:0]           rst_efpga_slot_n_i,      // Active-Low Soft Resets for eFPGA User Softlogic Slots (4 per slot)
    input  logic [NUM_SLOTS-1:0]                rst_efpga_npu_n_i,       // Active-Low Reset for Hardened NPU Complex

    // =========================================================================
    // AXI4-Lite Slave: Global Manager Interface
    // =========================================================================
    input  logic [31:0]                         s_axil_mgr_awaddr,
    input  logic [2:0]                          s_axil_mgr_awprot,
    input  logic                                s_axil_mgr_awvalid,
    output logic                                s_axil_mgr_awready,
    input  logic [31:0]                         s_axil_mgr_wdata,
    input  logic [3:0]                          s_axil_mgr_wstrb,
    input  logic                                s_axil_mgr_wvalid,
    output logic                                s_axil_mgr_wready,
    output logic [1:0]                          s_axil_mgr_bresp,
    output logic                                s_axil_mgr_bvalid,
    input  logic                                s_axil_mgr_bready,
    input  logic [31:0]                         s_axil_mgr_araddr,
    input  logic [2:0]                          s_axil_mgr_arprot,
    input  logic                                s_axil_mgr_arvalid,
    output logic                                s_axil_mgr_arready,
    output logic [31:0]                         s_axil_mgr_rdata,
    output logic [1:0]                          s_axil_mgr_rresp,
    output logic                                s_axil_mgr_rvalid,
    input  logic                                s_axil_mgr_rready,

    // =========================================================================
    // AXI4-Lite Slave: Slot Control Interface (Array)
    // =========================================================================
    input  logic [NUM_SLOTS*32-1:0]             s_axil_ctrl_awaddr,
    input  logic [NUM_SLOTS*3-1:0]              s_axil_ctrl_awprot,
    input  logic [NUM_SLOTS-1:0]                s_axil_ctrl_awvalid,
    output logic [NUM_SLOTS-1:0]                s_axil_ctrl_awready,
    input  logic [NUM_SLOTS*32-1:0]             s_axil_ctrl_wdata,
    input  logic [NUM_SLOTS*4-1:0]              s_axil_ctrl_wstrb,
    input  logic [NUM_SLOTS-1:0]                s_axil_ctrl_wvalid,
    output logic [NUM_SLOTS-1:0]                s_axil_ctrl_wready,
    output logic [NUM_SLOTS*2-1:0]              s_axil_ctrl_bresp,
    output logic [NUM_SLOTS-1:0]                s_axil_ctrl_bvalid,
    input  logic [NUM_SLOTS-1:0]                s_axil_ctrl_bready,
    input  logic [NUM_SLOTS*32-1:0]             s_axil_ctrl_araddr,
    input  logic [NUM_SLOTS*3-1:0]              s_axil_ctrl_arprot,
    input  logic [NUM_SLOTS-1:0]                s_axil_ctrl_arvalid,
    output logic [NUM_SLOTS-1:0]                s_axil_ctrl_arready,
    output logic [NUM_SLOTS*32-1:0]             s_axil_ctrl_rdata,
    output logic [NUM_SLOTS*2-1:0]              s_axil_ctrl_rresp,
    output logic [NUM_SLOTS-1:0]                s_axil_ctrl_rvalid,
    input  logic [NUM_SLOTS-1:0]                s_axil_ctrl_rready,

    // =========================================================================
    // AXI4 Full Master: Slot DMA Interface (Array)
    // =========================================================================
    output logic [NUM_SLOTS*AXI_ID_WIDTH-1:0]   m_axi_dma_awid,
    output logic [NUM_SLOTS*32-1:0]             m_axi_dma_awaddr,
    output logic [NUM_SLOTS*8-1:0]              m_axi_dma_awlen,
    output logic [NUM_SLOTS*3-1:0]              m_axi_dma_awsize,
    output logic [NUM_SLOTS*2-1:0]              m_axi_dma_awburst,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_awlock,
    output logic [NUM_SLOTS*4-1:0]              m_axi_dma_awcache,
    output logic [NUM_SLOTS*3-1:0]              m_axi_dma_awprot,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_awvalid,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_awready,
    output logic [NUM_SLOTS*32-1:0]             m_axi_dma_wdata,
    output logic [NUM_SLOTS*4-1:0]              m_axi_dma_wstrb,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_wlast,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_wvalid,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_wready,
    input  logic [NUM_SLOTS*AXI_ID_WIDTH-1:0]   m_axi_dma_bid,
    input  logic [NUM_SLOTS*2-1:0]              m_axi_dma_bresp,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_bvalid,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_bready,
    output logic [NUM_SLOTS*AXI_ID_WIDTH-1:0]   m_axi_dma_arid,
    output logic [NUM_SLOTS*32-1:0]             m_axi_dma_araddr,
    output logic [NUM_SLOTS*8-1:0]              m_axi_dma_arlen,
    output logic [NUM_SLOTS*3-1:0]              m_axi_dma_arsize,
    output logic [NUM_SLOTS*2-1:0]              m_axi_dma_arburst,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_arlock,
    output logic [NUM_SLOTS*4-1:0]              m_axi_dma_arcache,
    output logic [NUM_SLOTS*3-1:0]              m_axi_dma_arprot,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_arvalid,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_arready,
    input  logic [NUM_SLOTS*AXI_ID_WIDTH-1:0]   m_axi_dma_rid,
    input  logic [NUM_SLOTS*32-1:0]             m_axi_dma_rdata,
    input  logic [NUM_SLOTS*2-1:0]              m_axi_dma_rresp,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_rlast,
    input  logic [NUM_SLOTS-1:0]                m_axi_dma_rvalid,
    output logic [NUM_SLOTS-1:0]                m_axi_dma_rready,

    // =========================================================================
    // External Padring PMOD Interface
    // =========================================================================
    input  logic [7:0]                          pmod_io_i,
    output logic [7:0]                          pmod_io_o,
    output logic [7:0]                          pmod_io_oe_o,

    // =========================================================================
    // External BitBang Configuration Interface
    // =========================================================================
    input  logic                                efpga_cfg_sclk_i = 1'b0,
    input  logic                                efpga_cfg_sdata_i = 1'b0,

    // =========================================================================
    // Interrupt Lines to CPU and SoC Subsystems
    // =========================================================================
    output logic [3:0]                          efpga_usr_irq_o,
    output logic [NUM_SLOTS-1:0]                efpga_fault_irq_o
);

  assign s_axil_mgr_awready = 1'b1;
  assign s_axil_mgr_wready = 1'b1;
  assign s_axil_mgr_bresp = '0;
  assign s_axil_mgr_bvalid = 1'b1;
  assign s_axil_mgr_arready = 1'b1;
  assign s_axil_mgr_rdata = 32'hdeadc0de;
  assign s_axil_mgr_rresp = '0;
  assign s_axil_mgr_rvalid = 1'b1;
  assign s_axil_ctrl_awready = '1;
  assign s_axil_ctrl_wready = '1;
  assign s_axil_ctrl_bresp = '0;
  assign s_axil_ctrl_bvalid = '1;
  assign s_axil_ctrl_arready = '1;
  assign s_axil_ctrl_rdata = {NUM_SLOTS{32'hdeadc0de}};
  assign s_axil_ctrl_rresp = '0;
  assign s_axil_ctrl_rvalid = '1;
  assign m_axi_dma_awid = '0;
  assign m_axi_dma_awaddr = '0;
  assign m_axi_dma_awlen = '0;
  assign m_axi_dma_awsize = '0;
  assign m_axi_dma_awburst = '0;
  assign m_axi_dma_awlock = '0;
  assign m_axi_dma_awcache = '0;
  assign m_axi_dma_awprot = '0;
  assign m_axi_dma_awvalid = '0;
  assign m_axi_dma_wdata = '0;
  assign m_axi_dma_wstrb = '0;
  assign m_axi_dma_wlast = '0;
  assign m_axi_dma_wvalid = '0;
  assign m_axi_dma_bready = '0;
  assign m_axi_dma_arid = '0;
  assign m_axi_dma_araddr = '0;
  assign m_axi_dma_arlen = '0;
  assign m_axi_dma_arsize = '0;
  assign m_axi_dma_arburst = '0;
  assign m_axi_dma_arlock = '0;
  assign m_axi_dma_arcache = '0;
  assign m_axi_dma_arprot = '0;
  assign m_axi_dma_arvalid = '0;
  assign m_axi_dma_rready = '0;
  assign pmod_io_o = '0;
  assign pmod_io_oe_o = '0;
  assign efpga_usr_irq_o = '0;
  assign efpga_fault_irq_o = '0;

  initial $display("[SIM] efpga_subsystem_top: using simulation stub (no eFPGA)");

endmodule
