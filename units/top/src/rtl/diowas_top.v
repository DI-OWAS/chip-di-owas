// ***********************************************************
// The DI-OWAS Project
// Top module
// (c) Copyright 2024 - 2026 DI-OWAS team
// ***********************************************************

module diowas_top (
  // Global control
  input         clk_i,
  input         rstn_i,
  // Core complex: JTAG TAP
  input         jtag_tck_i,
  input         jtag_tdi_i,
  output        jtag_tdo_o,
  input         jtag_tms_i,
  // Core complex: SPI host
  output  [1:0] spi_csn_o,
  output        spi_sck_o,
  output        spi_sdo_o,
  input         spi_sdi_i,
  // Core complex: I2C host
  output        twi_scl_o, // 0 = pull SCL low, 1 = leave SCL floating
  input         twi_scl_i,
  output        twi_sda_o, // 0 = pull SDA low, 1 = leave SDA floating
  input         twi_sda_i,
  // Core complex: Heartbeat LED
  output        status_led_o,
  // Core complex: Serial console
  output        console_txd_o,
  input         console_rxd_i,
  // SPI PSRAM
  output        spiram_clk_o,
  output  [1:0] spiram_csn_o,
  input         spiram_sdi_i,
  output        spiram_sdo_o,
  // Octal PSRAM
  output  [3:0] octram_bus_clk_o,
  output  [3:0] octram_csn_o,
  output        octram_resetn_o,
  input   [3:0] octram_strobe_i,
  output  [3:0] octram_strobe_o,
  output  [3:0] octram_strobe_oe_o, // 0 input, 1 output
  input  [31:0] octram_data_i,
  output [31:0] octram_data_o,
  output  [3:0] octram_data_oe_o, // 0 input, 1 output
  // camera Interface
  input         cam_pixel_clk_i,
  input         cam_frame_valid_i,
  input         cam_line_valid_i,
  input  [11:0] cam_pixel_data_i,
  output [15:0] cam_doutif_data_o,
  output        cam_doutif_valid_o,
  output        cam_doutif_first_o,
  output        cam_doutif_clk_o,
  // BH Sensor IF UARTs
  input   [1:0] bhif_rxd_i,
  output        bhif_cts_o,
  // eFPGA user IOs
  output  [7:0] efpga_io_out_o,
  output  [7:0] efpga_io_oe_o,
  input   [7:0] efpga_io_in_i,
  // eFGPA Bitbang config adapter
  input         efpga_cfg_sclk_i,
  input         efpga_cfg_sdata_i
);

  // --------------------------------------------
  // AXI address map
  // --------------------------------------------
  // axi-full devices
  localparam [31:0] SRAM0_BASE  = 32'h00000000; localparam [31:0] SRAM0_AWIDTH  = 32'd14;
  localparam [31:0] SPIRAM_BASE = 32'h10000000; localparam [31:0] SPIRAM_AWIDTH = 32'd28;
  localparam [31:0] OCTRAM_BASE = 32'h20000000; localparam [31:0] OCTRAM_AWIDTH = 32'd26; // 4x APS12808L (16 MB each) = 64 MB
  localparam [31:0] SRAM1_BASE  = 32'h80000000; localparam [31:0] SRAM1_AWIDTH  = 32'd14;
  localparam [31:0] MMIO_BASE   = 32'hF0000000; localparam [31:0] MMIO_AWIDTH   = 32'd28;
  // axi-lite devices (MMIO)
  localparam [31:0] EFPGA_CFG_BASE       = 32'hF0000000;
  localparam [31:0] EFPGA_SLOT_BASE      = 32'hF1000000;
  localparam [31:0] SPIRAM_CFG_BASE      = 32'hF2000000;
  localparam [31:0] BHSENSORIF_CFG_BASE  = 32'hF3000000;
  localparam [31:0] DCCAMIF_CFG_BASE     = 32'hF4000000;
  localparam [31:0] CRYPTO_CFG_BASE      = 32'hF5000000;

  // AXI4-full interfaces
  wire [31:0] axi_cpu_awaddr,  axi_mmio_awaddr,  axi_bhsensorif_awaddr,  axi_dccamif_awaddr,  axi_crypto_awaddr,  axi_efpga_awaddr,  axi_sram0_awaddr,  axi_sram1_awaddr,  axi_spiram_data_awaddr,  axi_octram_awaddr  ;
  wire  [7:0] axi_cpu_awlen,   axi_mmio_awlen,   axi_bhsensorif_awlen,   axi_dccamif_awlen,   axi_crypto_awlen,   axi_efpga_awlen,   axi_sram0_awlen,   axi_sram1_awlen,   axi_spiram_data_awlen,   axi_octram_awlen   ;
  wire  [2:0] axi_cpu_awsize,  axi_mmio_awsize,  axi_bhsensorif_awsize,  axi_dccamif_awsize,  axi_crypto_awsize,  axi_efpga_awsize,  axi_sram0_awsize,  axi_sram1_awsize,  axi_spiram_data_awsize,  axi_octram_awsize  ;
  wire  [1:0] axi_cpu_awburst, axi_mmio_awburst, axi_bhsensorif_awburst, axi_dccamif_awburst, axi_crypto_awburst, axi_efpga_awburst, axi_sram0_awburst, axi_sram1_awburst, axi_spiram_data_awburst, axi_octram_awburst ;
  wire        axi_cpu_awlock,  axi_mmio_awlock,  axi_bhsensorif_awlock,  axi_dccamif_awlock,  axi_crypto_awlock,  axi_efpga_awlock,  axi_sram0_awlock,  axi_sram1_awlock,  axi_spiram_data_awlock,  axi_octram_awlock  ;
  wire  [3:0] axi_cpu_awcache, axi_mmio_awcache, axi_bhsensorif_awcache, axi_dccamif_awcache, axi_crypto_awcache, axi_efpga_awcache, axi_sram0_awcache, axi_sram1_awcache, axi_spiram_data_awcache, axi_octram_awcache ;
  wire  [2:0] axi_cpu_awprot,  axi_mmio_awprot,  axi_bhsensorif_awprot,  axi_dccamif_awprot,  axi_crypto_awprot,  axi_efpga_awprot,  axi_sram0_awprot,  axi_sram1_awprot,  axi_spiram_data_awprot,  axi_octram_awprot  ;
  wire        axi_cpu_awvalid, axi_mmio_awvalid, axi_bhsensorif_awvalid, axi_dccamif_awvalid, axi_crypto_awvalid, axi_efpga_awvalid, axi_sram0_awvalid, axi_sram1_awvalid, axi_spiram_data_awvalid, axi_octram_awvalid ;
  wire        axi_cpu_awready, axi_mmio_awready, axi_bhsensorif_awready, axi_dccamif_awready, axi_crypto_awready, axi_efpga_awready, axi_sram0_awready, axi_sram1_awready, axi_spiram_data_awready, axi_octram_awready ;
  wire [31:0] axi_cpu_wdata,   axi_mmio_wdata,   axi_bhsensorif_wdata,   axi_dccamif_wdata,   axi_crypto_wdata,   axi_efpga_wdata,   axi_sram0_wdata,   axi_sram1_wdata,   axi_spiram_data_wdata,   axi_octram_wdata   ;
  wire  [3:0] axi_cpu_wstrb,   axi_mmio_wstrb,   axi_bhsensorif_wstrb,   axi_dccamif_wstrb,   axi_crypto_wstrb,   axi_efpga_wstrb,   axi_sram0_wstrb,   axi_sram1_wstrb,   axi_spiram_data_wstrb,   axi_octram_wstrb   ;
  wire        axi_cpu_wlast,   axi_mmio_wlast,   axi_bhsensorif_wlast,   axi_dccamif_wlast,   axi_crypto_wlast,   axi_efpga_wlast,   axi_sram0_wlast,   axi_sram1_wlast,   axi_spiram_data_wlast,   axi_octram_wlast   ;
  wire        axi_cpu_wvalid,  axi_mmio_wvalid,  axi_bhsensorif_wvalid,  axi_dccamif_wvalid,  axi_crypto_wvalid,  axi_efpga_wvalid,  axi_sram0_wvalid,  axi_sram1_wvalid,  axi_spiram_data_wvalid,  axi_octram_wvalid  ;
  wire        axi_cpu_wready,  axi_mmio_wready,  axi_bhsensorif_wready,  axi_dccamif_wready,  axi_crypto_wready,  axi_efpga_wready,  axi_sram0_wready,  axi_sram1_wready,  axi_spiram_data_wready,  axi_octram_wready  ;
  wire  [1:0] axi_cpu_bresp,   axi_mmio_bresp,   axi_bhsensorif_bresp,   axi_dccamif_bresp,   axi_crypto_bresp,   axi_efpga_bresp,   axi_sram0_bresp,   axi_sram1_bresp,   axi_spiram_data_bresp,   axi_octram_bresp   ;
  wire        axi_cpu_bvalid,  axi_mmio_bvalid,  axi_bhsensorif_bvalid,  axi_dccamif_bvalid,  axi_crypto_bvalid,  axi_efpga_bvalid,  axi_sram0_bvalid,  axi_sram1_bvalid,  axi_spiram_data_bvalid,  axi_octram_bvalid  ;
  wire        axi_cpu_bready,  axi_mmio_bready,  axi_bhsensorif_bready,  axi_dccamif_bready,  axi_crypto_bready,  axi_efpga_bready,  axi_sram0_bready,  axi_sram1_bready,  axi_spiram_data_bready,  axi_octram_bready  ;
  wire [31:0] axi_cpu_araddr,  axi_mmio_araddr,  axi_bhsensorif_araddr,  axi_dccamif_araddr,  axi_crypto_araddr,  axi_efpga_araddr,  axi_sram0_araddr,  axi_sram1_araddr,  axi_spiram_data_araddr,  axi_octram_araddr  ;
  wire  [7:0] axi_cpu_arlen,   axi_mmio_arlen,   axi_bhsensorif_arlen,   axi_dccamif_arlen,   axi_crypto_arlen,   axi_efpga_arlen,   axi_sram0_arlen,   axi_sram1_arlen,   axi_spiram_data_arlen,   axi_octram_arlen   ;
  wire  [2:0] axi_cpu_arsize,  axi_mmio_arsize,  axi_bhsensorif_arsize,  axi_dccamif_arsize,  axi_crypto_arsize,  axi_efpga_arsize,  axi_sram0_arsize,  axi_sram1_arsize,  axi_spiram_data_arsize,  axi_octram_arsize  ;
  wire  [1:0] axi_cpu_arburst, axi_mmio_arburst, axi_bhsensorif_arburst, axi_dccamif_arburst, axi_crypto_arburst, axi_efpga_arburst, axi_sram0_arburst, axi_sram1_arburst, axi_spiram_data_arburst, axi_octram_arburst ;
  wire        axi_cpu_arlock,  axi_mmio_arlock,  axi_bhsensorif_arlock,  axi_dccamif_arlock,  axi_crypto_arlock,  axi_efpga_arlock,  axi_sram0_arlock,  axi_sram1_arlock,  axi_spiram_data_arlock,  axi_octram_arlock  ;
  wire  [3:0] axi_cpu_arcache, axi_mmio_arcache, axi_bhsensorif_arcache, axi_dccamif_arcache, axi_crypto_arcache, axi_efpga_arcache, axi_sram0_arcache, axi_sram1_arcache, axi_spiram_data_arcache, axi_octram_arcache ;
  wire  [2:0] axi_cpu_arprot,  axi_mmio_arprot,  axi_bhsensorif_arprot,  axi_dccamif_arprot,  axi_crypto_arprot,  axi_efpga_arprot,  axi_sram0_arprot,  axi_sram1_arprot,  axi_spiram_data_arprot,  axi_octram_arprot  ;
  wire        axi_cpu_arvalid, axi_mmio_arvalid, axi_bhsensorif_arvalid, axi_dccamif_arvalid, axi_crypto_arvalid, axi_efpga_arvalid, axi_sram0_arvalid, axi_sram1_arvalid, axi_spiram_data_arvalid, axi_octram_arvalid ;
  wire        axi_cpu_arready, axi_mmio_arready, axi_bhsensorif_arready, axi_dccamif_arready, axi_crypto_arready, axi_efpga_arready, axi_sram0_arready, axi_sram1_arready, axi_spiram_data_arready, axi_octram_arready ;
  wire [31:0] axi_cpu_rdata,   axi_mmio_rdata,   axi_bhsensorif_rdata,   axi_dccamif_rdata,   axi_crypto_rdata,   axi_efpga_rdata,   axi_sram0_rdata,   axi_sram1_rdata,   axi_spiram_data_rdata,   axi_octram_rdata   ;
  wire  [1:0] axi_cpu_rresp,   axi_mmio_rresp,   axi_bhsensorif_rresp,   axi_dccamif_rresp,   axi_crypto_rresp,   axi_efpga_rresp,   axi_sram0_rresp,   axi_sram1_rresp,   axi_spiram_data_rresp,   axi_octram_rresp   ;
  wire        axi_cpu_rlast,   axi_mmio_rlast,   axi_bhsensorif_rlast,   axi_dccamif_rlast,   axi_crypto_rlast,   axi_efpga_rlast,   axi_sram0_rlast,   axi_sram1_rlast,   axi_spiram_data_rlast,   axi_octram_rlast   ;
  wire        axi_cpu_rvalid,  axi_mmio_rvalid,  axi_bhsensorif_rvalid,  axi_dccamif_rvalid,  axi_crypto_rvalid,  axi_efpga_rvalid,  axi_sram0_rvalid,  axi_sram1_rvalid,  axi_spiram_data_rvalid,  axi_octram_rvalid  ;
  wire        axi_cpu_rready,  axi_mmio_rready,  axi_bhsensorif_rready,  axi_dccamif_rready,  axi_crypto_rready,  axi_efpga_rready,  axi_sram0_rready,  axi_sram1_rready,  axi_spiram_data_rready,  axi_octram_rready  ;

  // AXI4-full IDs
  wire [7:0] axi_sram0_awid, axi_sram0_bid, axi_sram0_arid, axi_sram0_rid;
  wire [7:0] axi_sram1_awid, axi_sram1_bid, axi_sram1_arid, axi_sram1_rid;
  wire [7:0] axi_spiram_data_awid, axi_spiram_data_bid, axi_spiram_data_arid, axi_spiram_data_rid;
  wire [7:0] axi_octram_awid, axi_octram_bid, axi_octram_arid, axi_octram_rid;
  wire [7:0] axi_mmio_awid, axi_mmio_bid, axi_mmio_arid, axi_mmio_rid;

  // AXI4-lite interfaces
  wire [31:0] axil_main_awaddr,  axil_bhsensorif_cfg_awaddr,  axil_dccamif_cfg_awaddr,  axil_efpga_cfg_awaddr,  axil_efpga_slot_awaddr,  axil_crypto_cfg_awaddr,  axil_spiram_data_awaddr,  axil_spiram_cfg_awaddr  ;
  wire  [2:0] axil_main_awprot,  axil_bhsensorif_cfg_awprot,  axil_dccamif_cfg_awprot,  axil_efpga_cfg_awprot,  axil_efpga_slot_awprot,  axil_crypto_cfg_awprot,  axil_spiram_data_awprot,  axil_spiram_cfg_awprot  ;
  wire        axil_main_awvalid, axil_bhsensorif_cfg_awvalid, axil_dccamif_cfg_awvalid, axil_efpga_cfg_awvalid, axil_efpga_slot_awvalid, axil_crypto_cfg_awvalid, axil_spiram_data_awvalid, axil_spiram_cfg_awvalid ;
  wire        axil_main_awready, axil_bhsensorif_cfg_awready, axil_dccamif_cfg_awready, axil_efpga_cfg_awready, axil_efpga_slot_awready, axil_crypto_cfg_awready, axil_spiram_data_awready, axil_spiram_cfg_awready ;
  wire [31:0] axil_main_wdata,   axil_bhsensorif_cfg_wdata,   axil_dccamif_cfg_wdata,   axil_efpga_cfg_wdata,   axil_efpga_slot_wdata,   axil_crypto_cfg_wdata,   axil_spiram_data_wdata,   axil_spiram_cfg_wdata   ;
  wire  [3:0] axil_main_wstrb,   axil_bhsensorif_cfg_wstrb,   axil_dccamif_cfg_wstrb,   axil_efpga_cfg_wstrb,   axil_efpga_slot_wstrb,   axil_crypto_cfg_wstrb,   axil_spiram_data_wstrb,   axil_spiram_cfg_wstrb   ;
  wire        axil_main_wvalid,  axil_bhsensorif_cfg_wvalid,  axil_dccamif_cfg_wvalid,  axil_efpga_cfg_wvalid,  axil_efpga_slot_wvalid,  axil_crypto_cfg_wvalid,  axil_spiram_data_wvalid,  axil_spiram_cfg_wvalid  ;
  wire        axil_main_wready,  axil_bhsensorif_cfg_wready,  axil_dccamif_cfg_wready,  axil_efpga_cfg_wready,  axil_efpga_slot_wready,  axil_crypto_cfg_wready,  axil_spiram_data_wready,  axil_spiram_cfg_wready  ;
  wire  [1:0] axil_main_bresp,   axil_bhsensorif_cfg_bresp,   axil_dccamif_cfg_bresp,   axil_efpga_cfg_bresp,   axil_efpga_slot_bresp,   axil_crypto_cfg_bresp,   axil_spiram_data_bresp,   axil_spiram_cfg_bresp   ;
  wire        axil_main_bvalid,  axil_bhsensorif_cfg_bvalid,  axil_dccamif_cfg_bvalid,  axil_efpga_cfg_bvalid,  axil_efpga_slot_bvalid,  axil_crypto_cfg_bvalid,  axil_spiram_data_bvalid,  axil_spiram_cfg_bvalid  ;
  wire        axil_main_bready,  axil_bhsensorif_cfg_bready,  axil_dccamif_cfg_bready,  axil_efpga_cfg_bready,  axil_efpga_slot_bready,  axil_crypto_cfg_bready,  axil_spiram_data_bready,  axil_spiram_cfg_bready  ;
  wire [31:0] axil_main_araddr,  axil_bhsensorif_cfg_araddr,  axil_dccamif_cfg_araddr,  axil_efpga_cfg_araddr,  axil_efpga_slot_araddr,  axil_crypto_cfg_araddr,  axil_spiram_data_araddr,  axil_spiram_cfg_araddr  ;
  wire  [2:0] axil_main_arprot,  axil_bhsensorif_cfg_arprot,  axil_dccamif_cfg_arprot,  axil_efpga_cfg_arprot,  axil_efpga_slot_arprot,  axil_crypto_cfg_arprot,  axil_spiram_data_arprot,  axil_spiram_cfg_arprot  ;
  wire        axil_main_arvalid, axil_bhsensorif_cfg_arvalid, axil_dccamif_cfg_arvalid, axil_efpga_cfg_arvalid, axil_efpga_slot_arvalid, axil_crypto_cfg_arvalid, axil_spiram_data_arvalid, axil_spiram_cfg_arvalid ;
  wire        axil_main_arready, axil_bhsensorif_cfg_arready, axil_dccamif_cfg_arready, axil_efpga_cfg_arready, axil_efpga_slot_arready, axil_crypto_cfg_arready, axil_spiram_data_arready, axil_spiram_cfg_arready ;
  wire [31:0] axil_main_rdata,   axil_bhsensorif_cfg_rdata,   axil_dccamif_cfg_rdata,   axil_efpga_cfg_rdata,   axil_efpga_slot_rdata,   axil_crypto_cfg_rdata,   axil_spiram_data_rdata,   axil_spiram_cfg_rdata   ;
  wire  [1:0] axil_main_rresp,   axil_bhsensorif_cfg_rresp,   axil_dccamif_cfg_rresp,   axil_efpga_cfg_rresp,   axil_efpga_slot_rresp,   axil_crypto_cfg_rresp,   axil_spiram_data_rresp,   axil_spiram_cfg_rresp   ;
  wire        axil_main_rvalid,  axil_bhsensorif_cfg_rvalid,  axil_dccamif_cfg_rvalid,  axil_efpga_cfg_rvalid,  axil_efpga_slot_rvalid,  axil_crypto_cfg_rvalid,  axil_spiram_data_rvalid,  axil_spiram_cfg_rvalid  ;
  wire        axil_main_rready,  axil_bhsensorif_cfg_rready,  axil_dccamif_cfg_rready,  axil_efpga_cfg_rready,  axil_efpga_slot_rready,  axil_crypto_cfg_rready,  axil_spiram_data_rready,  axil_spiram_cfg_rready  ;

  // *************************************************************************************
  // Reset synchronizer
  // *************************************************************************************
  reg [1:0] resetn_sync_gen_q;
  wire resetn_async;

  // for synchronous resets
  always @(posedge clk_i or negedge rstn_i)
  begin
    if (rstn_i == 1'b0) begin // asynchronous set
      resetn_sync_gen_q <= 2'b00;
    end else begin // synchronous release
      resetn_sync_gen_q <= {resetn_sync_gen_q[0], 1'b1};
    end
  end

  assign resetn_async =  resetn_sync_gen_q[1]; // low-active asynchronous reset

  // *************************************************************************************
  // RISC-V Core Complex (FhG-IMS)
  // *************************************************************************************

  // global resets
  wire [15:0] system_resetn;
  localparam integer RESET_AXI        = 0;
  localparam integer RESET_AXIL       = 1;
  localparam integer RESET_SRAM       = 2;
  localparam integer RESET_BH         = 3;
  localparam integer RESET_DCV        = 4;
  localparam integer RESET_CRYPTO     = 5;
  localparam integer RESET_SPIRAM     = 6;
  localparam integer RESET_OCTRAM     = 7;
  localparam integer RESET_EFPGA_CON0 = 8;
  localparam integer RESET_EFPGA_CON1 = 9;
  localparam integer RESET_EFPGA_FAB  = 10;
  localparam integer RESET_EFPGA_SLOT = 11;
  localparam integer RESET_EFPGA_NPU  = 12;

  // CPU interrupts
  wire       irq_bhsensorif;
  wire [7:0] irq_dccamif;
  wire [3:0] efpga_usr_irq_o; // TODO: connect to interrupt controller
  wire       efpga_fault_irq_o; // TODO: connect to interrupt controller
  //
  wire [15:0] irq_cpu = {
    2'b00,            // 15:14 - reserved
    irq_dccamif,      // 13:6
    irq_bhsensorif,   // 5
    efpga_usr_irq_o,  // 4:1
    efpga_fault_irq_o // 0
  };

  // the core of the problem
  core_complex_wrapper core_complex_top_inst (
    // global control
    .clk_i         (clk_i),
    .rstn_i        (resetn_async),
    // AXI4 Write Address Channel
    .m_axi_awaddr  (axi_cpu_awaddr),
    .m_axi_awlen   (axi_cpu_awlen),
    .m_axi_awsize  (axi_cpu_awsize),
    .m_axi_awburst (axi_cpu_awburst),
    .m_axi_awcache (axi_cpu_awcache),
    .m_axi_awprot  (axi_cpu_awprot),
    .m_axi_awvalid (axi_cpu_awvalid),
    .m_axi_awready (axi_cpu_awready),
    // AXI4 Write Data Channel
    .m_axi_wdata   (axi_cpu_wdata),
    .m_axi_wstrb   (axi_cpu_wstrb),
    .m_axi_wlast   (axi_cpu_wlast),
    .m_axi_wvalid  (axi_cpu_wvalid),
    .m_axi_wready  (axi_cpu_wready),
    // AXI4 Read Address Channel
    .m_axi_araddr  (axi_cpu_araddr),
    .m_axi_arlen   (axi_cpu_arlen),
    .m_axi_arsize  (axi_cpu_arsize),
    .m_axi_arburst (axi_cpu_arburst),
    .m_axi_arcache (axi_cpu_arcache),
    .m_axi_arprot  (axi_cpu_arprot),
    .m_axi_arvalid (axi_cpu_arvalid),
    .m_axi_arready (axi_cpu_arready),
    // AXI4 Read Data Channel --
    .m_axi_rdata   (axi_cpu_rdata),
    .m_axi_rresp   (axi_cpu_rresp),
    .m_axi_rlast   (axi_cpu_rlast),
    .m_axi_rvalid  (axi_cpu_rvalid),
    .m_axi_rready  (axi_cpu_rready),
    // AXI4 Write Response Channel
    .m_axi_bresp   (axi_cpu_bresp),
    .m_axi_bvalid  (axi_cpu_bvalid),
    .m_axi_bready  (axi_cpu_bready),
    // jtag on-chip debugger interface
    .jtag_tck_i    (jtag_tck_i),
    .jtag_tdi_i    (jtag_tdi_i),
    .jtag_tdo_o    (jtag_tdo_o),
    .jtag_tms_i    (jtag_tms_i),
    // SPI host controller
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
    .sys_resetn_o  (system_resetn),
    // system interrupts
    .irq_i         (irq_cpu)
  );

  // static AXI signals
  assign axi_cpu_awlock = 1'b0;
  assign axi_cpu_arlock = 1'b0;

  // *************************************************************************************
  // AXI4-full high-bandwidth crossbar
  // *************************************************************************************
  axi_crossbar #(
    .S_COUNT         (5),  // Number of AXI inputs (slave interfaces)
    .M_COUNT         (5),  // Number of AXI outputs (master interfaces)
    .DATA_WIDTH      (32), // Width of data bus in bits
    .ADDR_WIDTH      (32), // Width of address bus in bits
    .STRB_WIDTH      (4),  // Width of wstrb (width of data bus in words)
    .S_ID_WIDTH      (4),  // Input ID field width (from AXI masters)
    .M_ID_WIDTH      (8),  // Output ID field width (towards AXI slaves)
    .AWUSER_ENABLE   (0),  // Propagate awuser signal
    .AWUSER_WIDTH    (1),  // Width of awuser signal
    .WUSER_ENABLE    (0),  // Propagate wuser signal
    .WUSER_WIDTH     (1),  // Width of wuser signal
    .BUSER_ENABLE    (0),  // Propagate buser signal
    .BUSER_WIDTH     (1),  // Width of buser signal
    .ARUSER_ENABLE   (0),  // Propagate aruser signal
    .ARUSER_WIDTH    (1),  // Width of aruser signal
    .RUSER_ENABLE    (0),  // Propagate ruser signal
    .RUSER_WIDTH     (1),  // Width of ruser signal
    .S_THREADS       ({32'd1, 32'd1, 32'd1, 32'd1, 32'd1}), // Number of concurrent unique IDs for each slave interface, S_COUNT concatenated fields of 32 bits
    .S_ACCEPT        ({32'd1, 32'd1, 32'd1, 32'd1, 32'd1}), // Number of concurrent operations for each slave interface, S_COUNT concatenated fields of 32 bits
    .M_REGIONS       (1), // Number of regions per master interface
    .M_BASE_ADDR     ({SRAM0_BASE,   SRAM1_BASE,   SPIRAM_BASE,   OCTRAM_BASE,   MMIO_BASE  }), // Master interface base addresses, M_COUNT concatenated fields of M_REGIONS concatenated fields of ADDR_WIDTH bits
    .M_ADDR_WIDTH    ({SRAM0_AWIDTH, SRAM1_AWIDTH, SPIRAM_AWIDTH, OCTRAM_AWIDTH, MMIO_AWIDTH}), // Master interface address widths, M_COUNT concatenated fields of M_REGIONS concatenated fields of 32 bits
    .M_CONNECT_READ  ({5'b11111,     5'b11111,     5'b11111,      5'b11111,      5'b11111   }), // Read connections between interfaces, M_COUNT concatenated fields of S_COUNT bits
    .M_CONNECT_WRITE ({5'b11111,     5'b11111,     5'b11111,      5'b11111,      5'b11111   }), // Write connections between interfaces, M_COUNT concatenated fields of S_COUNT bits
    .M_ISSUE         ({32'd1,        32'd1,        32'd1,         32'd1,         32'd1      }), // Number of concurrent operations for each master interface, M_COUNT concatenated fields of 32 bits
    .M_SECURE        (5'b00000), // Secure master (fail operations based on awprot/arprot), M_COUNT bits
    .S_AW_REG_TYPE   ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Slave interface AW channel register type (input), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .S_W_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Slave interface W channel register type (input), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .S_B_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Slave interface B channel register type (output), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .S_AR_REG_TYPE   ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Slave interface AR channel register type (input), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .S_R_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Slave interface R channel register type (output), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .M_AW_REG_TYPE   ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Master interface AW channel register type (output), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .M_W_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Master interface W channel register type (output), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .M_B_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Master interface B channel register type (input), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .M_AR_REG_TYPE   ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0}), // Master interface AR channel register type (output), 0 to bypass, 1 for simple buffer, 2 for skid buffer
    .M_R_REG_TYPE    ({2'd0, 2'd0, 2'd0, 2'd0, 2'd0})  // Master interface R channel register type (input), 0 to bypass, 1 for simple buffer, 2 for skid buffer
  ) axi_crossbar_inst (
    .clk           (clk_i),
    .rst           (~system_resetn[RESET_AXI]),
    /****** AXI slave interfaces ******/
    .s_axi_awid    ({4'h3,            4'h2,                   4'h1,                4'h1,              4'h0}),
    .s_axi_awaddr  ({axi_cpu_awaddr,  axi_bhsensorif_awaddr,  axi_dccamif_awaddr,  axi_efpga_awaddr,  axi_crypto_awaddr}),
    .s_axi_awlen   ({axi_cpu_awlen,   axi_bhsensorif_awlen,   axi_dccamif_awlen,   axi_efpga_awlen,   axi_crypto_awlen}),
    .s_axi_awsize  ({axi_cpu_awsize,  axi_bhsensorif_awsize,  axi_dccamif_awsize,  axi_efpga_awsize,  axi_crypto_awsize}),
    .s_axi_awburst ({axi_cpu_awburst, axi_bhsensorif_awburst, axi_dccamif_awburst, axi_efpga_awburst, axi_crypto_awburst}),
    .s_axi_awlock  ({axi_cpu_awlock,  axi_bhsensorif_awlock,  axi_dccamif_awlock,  axi_efpga_awlock,  axi_crypto_awlock}),
    .s_axi_awcache ({axi_cpu_awcache, axi_bhsensorif_awcache, axi_dccamif_awcache, axi_efpga_awcache, axi_crypto_awcache}),
    .s_axi_awprot  ({axi_cpu_awprot,  axi_bhsensorif_awprot,  axi_dccamif_awprot,  axi_efpga_awprot,  axi_crypto_awprot}),
    .s_axi_awqos   ({4'h0,            4'h0,                   4'h0,                4'h0,              4'h0}),
    .s_axi_awuser  ({1'b0,            1'b0,                   1'b0,                1'b0,              1'b0}),
    .s_axi_awvalid ({axi_cpu_awvalid, axi_bhsensorif_awvalid, axi_dccamif_awvalid, axi_efpga_awvalid, axi_crypto_awvalid}),
    .s_axi_awready ({axi_cpu_awready, axi_bhsensorif_awready, axi_dccamif_awready, axi_efpga_awready, axi_crypto_awready}),
    .s_axi_wdata   ({axi_cpu_wdata,   axi_bhsensorif_wdata,   axi_dccamif_wdata,   axi_efpga_wdata,   axi_crypto_wdata}),
    .s_axi_wstrb   ({axi_cpu_wstrb,   axi_bhsensorif_wstrb,   axi_dccamif_wstrb,   axi_efpga_wstrb,   axi_crypto_wstrb}),
    .s_axi_wlast   ({axi_cpu_wlast,   axi_bhsensorif_wlast,   axi_dccamif_wlast,   axi_efpga_wlast,   axi_crypto_wlast}),
    .s_axi_wuser   ({1'b0,            1'b0,                   1'b0,                1'b0,              1'b0}),
    .s_axi_wvalid  ({axi_cpu_wvalid,  axi_bhsensorif_wvalid,  axi_dccamif_wvalid,  axi_efpga_wvalid,  axi_crypto_wvalid}),
    .s_axi_wready  ({axi_cpu_wready,  axi_bhsensorif_wready,  axi_dccamif_wready,  axi_efpga_wready,  axi_crypto_wready}),
    .s_axi_bid     (),
    .s_axi_bresp   ({axi_cpu_bresp,   axi_bhsensorif_bresp,   axi_dccamif_bresp,   axi_efpga_bresp,   axi_crypto_bresp}),
    .s_axi_buser   (),
    .s_axi_bvalid  ({axi_cpu_bvalid,  axi_bhsensorif_bvalid,  axi_dccamif_bvalid,  axi_efpga_bvalid,  axi_crypto_bvalid}),
    .s_axi_bready  ({axi_cpu_bready,  axi_bhsensorif_bready,  axi_dccamif_bready,  axi_efpga_bready,  axi_crypto_bready}),
    .s_axi_arid    ({4'h3,            4'h2,                   4'h1,                4'h1,              4'h0}),
    .s_axi_araddr  ({axi_cpu_araddr,  axi_bhsensorif_araddr,  axi_dccamif_araddr,  axi_efpga_araddr,  axi_crypto_araddr}),
    .s_axi_arlen   ({axi_cpu_arlen,   axi_bhsensorif_arlen,   axi_dccamif_arlen,   axi_efpga_arlen,   axi_crypto_arlen}),
    .s_axi_arsize  ({axi_cpu_arsize,  axi_bhsensorif_arsize,  axi_dccamif_arsize,  axi_efpga_arsize,  axi_crypto_arsize}),
    .s_axi_arburst ({axi_cpu_arburst, axi_bhsensorif_arburst, axi_dccamif_arburst, axi_efpga_arburst, axi_crypto_arburst}),
    .s_axi_arlock  ({axi_cpu_arlock,  axi_bhsensorif_arlock,  axi_dccamif_arlock,  axi_efpga_arlock,  axi_crypto_arlock}),
    .s_axi_arcache ({axi_cpu_arcache, axi_bhsensorif_arcache, axi_dccamif_arcache, axi_efpga_arcache, axi_crypto_arcache}),
    .s_axi_arprot  ({axi_cpu_arprot,  axi_bhsensorif_arprot,  axi_dccamif_arprot,  axi_efpga_arprot,  axi_crypto_arprot}),
    .s_axi_arqos   ({4'h0,            4'h0,                   4'h0,                4'h0,              4'h0}),
    .s_axi_aruser  ({1'b0,            1'b0,                   1'b0,                1'b0,              1'b0}),
    .s_axi_arvalid ({axi_cpu_arvalid, axi_bhsensorif_arvalid, axi_dccamif_arvalid, axi_efpga_arvalid, axi_crypto_arvalid}),
    .s_axi_arready ({axi_cpu_arready, axi_bhsensorif_arready, axi_dccamif_arready, axi_efpga_arready, axi_crypto_arready}),
    .s_axi_rid     (),
    .s_axi_rdata   ({axi_cpu_rdata,   axi_bhsensorif_rdata,   axi_dccamif_rdata,   axi_efpga_rdata,   axi_crypto_rdata}),
    .s_axi_rresp   ({axi_cpu_rresp,   axi_bhsensorif_rresp,   axi_dccamif_rresp,   axi_efpga_rresp,   axi_crypto_rresp}),
    .s_axi_rlast   ({axi_cpu_rlast,   axi_bhsensorif_rlast,   axi_dccamif_rlast,   axi_efpga_rlast,   axi_crypto_rlast}),
    .s_axi_ruser   (),
    .s_axi_rvalid  ({axi_cpu_rvalid,  axi_bhsensorif_rvalid,  axi_dccamif_rvalid,  axi_efpga_rvalid,  axi_crypto_rvalid}),
    .s_axi_rready  ({axi_cpu_rready,  axi_bhsensorif_rready,  axi_dccamif_rready,  axi_efpga_rready,  axi_crypto_rready}),
    /****** AXI master interfaces ******/
    .m_axi_awid     ({axi_sram0_awid,    axi_sram1_awid,    axi_spiram_data_awid,    axi_octram_awid,    axi_mmio_awid   }),
    .m_axi_awaddr   ({axi_sram0_awaddr,  axi_sram1_awaddr,  axi_spiram_data_awaddr,  axi_octram_awaddr,  axi_mmio_awaddr }),
    .m_axi_awlen    ({axi_sram0_awlen,   axi_sram1_awlen,   axi_spiram_data_awlen,   axi_octram_awlen,   axi_mmio_awlen  }),
    .m_axi_awsize   ({axi_sram0_awsize,  axi_sram1_awsize,  axi_spiram_data_awsize,  axi_octram_awsize,  axi_mmio_awsize }),
    .m_axi_awburst  ({axi_sram0_awburst, axi_sram1_awburst, axi_spiram_data_awburst, axi_octram_awburst, axi_mmio_awburst}),
    .m_axi_awlock   ({axi_sram0_awlock,  axi_sram1_awlock,  axi_spiram_data_awlock,  axi_octram_awlock,  axi_mmio_awlock }),
    .m_axi_awcache  ({axi_sram0_awcache, axi_sram1_awcache, axi_spiram_data_awcache, axi_octram_awcache, axi_mmio_awcache}),
    .m_axi_awprot   ({axi_sram0_awprot,  axi_sram1_awprot,  axi_spiram_data_awprot,  axi_octram_awprot,  axi_mmio_awprot }),
    .m_axi_awqos    (),
    .m_axi_awregion (),
    .m_axi_awuser   (),
    .m_axi_awvalid  ({axi_sram0_awvalid, axi_sram1_awvalid, axi_spiram_data_awvalid, axi_octram_awvalid, axi_mmio_awvalid}),
    .m_axi_awready  ({axi_sram0_awready, axi_sram1_awready, axi_spiram_data_awready, axi_octram_awready, axi_mmio_awready}),
    .m_axi_wdata    ({axi_sram0_wdata,   axi_sram1_wdata,   axi_spiram_data_wdata,   axi_octram_wdata,   axi_mmio_wdata  }),
    .m_axi_wstrb    ({axi_sram0_wstrb,   axi_sram1_wstrb,   axi_spiram_data_wstrb,   axi_octram_wstrb,   axi_mmio_wstrb  }),
    .m_axi_wlast    ({axi_sram0_wlast,   axi_sram1_wlast,   axi_spiram_data_wlast,   axi_octram_wlast,   axi_mmio_wlast  }),
    .m_axi_wuser    (),
    .m_axi_wvalid   ({axi_sram0_wvalid,  axi_sram1_wvalid,  axi_spiram_data_wvalid,  axi_octram_wvalid,  axi_mmio_wvalid }),
    .m_axi_wready   ({axi_sram0_wready,  axi_sram1_wready,  axi_spiram_data_wready,  axi_octram_wready,  axi_mmio_wready }),
    .m_axi_bid      ({axi_sram0_bid,     axi_sram1_bid,     axi_spiram_data_bid,     axi_octram_bid,     axi_mmio_bid    }),
    .m_axi_bresp    ({axi_sram0_bresp,   axi_sram1_bresp,   axi_spiram_data_bresp,   axi_octram_bresp,   axi_mmio_bresp  }),
    .m_axi_buser    ({1'b0,              1'b0,              1'b0,                    1'b0,              1'b0            }),
    .m_axi_bvalid   ({axi_sram0_bvalid,  axi_sram1_bvalid,  axi_spiram_data_bvalid,  axi_octram_bvalid,  axi_mmio_bvalid }),
    .m_axi_bready   ({axi_sram0_bready,  axi_sram1_bready,  axi_spiram_data_bready,  axi_octram_bready,  axi_mmio_bready }),
    .m_axi_arid     ({axi_sram0_arid,    axi_sram1_arid,    axi_spiram_data_arid,    axi_octram_arid,    axi_mmio_arid   }),
    .m_axi_araddr   ({axi_sram0_araddr,  axi_sram1_araddr,  axi_spiram_data_araddr,  axi_octram_araddr,  axi_mmio_araddr }),
    .m_axi_arlen    ({axi_sram0_arlen,   axi_sram1_arlen,   axi_spiram_data_arlen,   axi_octram_arlen,   axi_mmio_arlen  }),
    .m_axi_arsize   ({axi_sram0_arsize,  axi_sram1_arsize,  axi_spiram_data_arsize,  axi_octram_arsize,  axi_mmio_arsize }),
    .m_axi_arburst  ({axi_sram0_arburst, axi_sram1_arburst, axi_spiram_data_arburst, axi_octram_arburst, axi_mmio_arburst}),
    .m_axi_arlock   ({axi_sram0_arlock,  axi_sram1_arlock,  axi_spiram_data_arlock,  axi_octram_arlock,  axi_mmio_arlock }),
    .m_axi_arcache  ({axi_sram0_arcache, axi_sram1_arcache, axi_spiram_data_arcache, axi_octram_arcache, axi_mmio_arcache}),
    .m_axi_arprot   ({axi_sram0_arprot,  axi_sram1_arprot,  axi_spiram_data_arprot,  axi_octram_arprot,  axi_mmio_arprot }),
    .m_axi_arqos    (),
    .m_axi_arregion (),
    .m_axi_aruser   (),
    .m_axi_arvalid  ({axi_sram0_arvalid, axi_sram1_arvalid, axi_spiram_data_arvalid, axi_octram_arvalid, axi_mmio_arvalid}),
    .m_axi_arready  ({axi_sram0_arready, axi_sram1_arready, axi_spiram_data_arready, axi_octram_arready, axi_mmio_arready}),
    .m_axi_rid      ({axi_sram0_rid,     axi_sram1_rid,     axi_spiram_data_rid,     axi_octram_rid,     axi_mmio_rid    }),
    .m_axi_rdata    ({axi_sram0_rdata,   axi_sram1_rdata,   axi_spiram_data_rdata,   axi_octram_rdata,   axi_mmio_rdata  }),
    .m_axi_rresp    ({axi_sram0_rresp,   axi_sram1_rresp,   axi_spiram_data_rresp,   axi_octram_rresp,   axi_mmio_rresp  }),
    .m_axi_rlast    ({axi_sram0_rlast,   axi_sram1_rlast,   axi_spiram_data_rlast,   axi_octram_rlast,   axi_mmio_rlast  }),
    .m_axi_ruser    ({1'b0,              1'b0,              1'b0,                    1'b0,               1'b0            }),
    .m_axi_rvalid   ({axi_sram0_rvalid,  axi_sram1_rvalid,  axi_spiram_data_rvalid,  axi_octram_rvalid,  axi_mmio_rvalid }),
    .m_axi_rready   ({axi_sram0_rready,  axi_sram1_rready,  axi_spiram_data_rready,  axi_octram_rready,  axi_mmio_rready })
  );

  // *************************************************************************************
  // AXI4-lite low-bandwidth interconnect
  // *************************************************************************************

  // AXI-full to AXI-lite converter
  axi_axil_adapter #(
    .ADDR_WIDTH           (32),
    .AXI_DATA_WIDTH       (32),
    .AXI_STRB_WIDTH       (4),
    .AXI_ID_WIDTH         (8),
    .AXIL_DATA_WIDTH      (32),
    .AXIL_STRB_WIDTH      (4),
    .CONVERT_BURST        (0),
    .CONVERT_NARROW_BURST (0)
  ) axi_lite_bridge (
    .clk            (clk_i),
    .rst            (~system_resetn[RESET_AXIL]),
    /* AXI slave interface */
    .s_axi_awid     (axi_mmio_awid),
    .s_axi_awaddr   (axi_mmio_awaddr),
    .s_axi_awlen    (axi_mmio_awlen),
    .s_axi_awsize   (axi_mmio_awsize),
    .s_axi_awburst  (axi_mmio_awburst),
    .s_axi_awlock   (axi_mmio_awlock),
    .s_axi_awcache  (axi_mmio_awcache),
    .s_axi_awprot   (axi_mmio_awprot),
    .s_axi_awvalid  (axi_mmio_awvalid),
    .s_axi_awready  (axi_mmio_awready),
    .s_axi_wdata    (axi_mmio_wdata),
    .s_axi_wstrb    (axi_mmio_wstrb),
    .s_axi_wlast    (axi_mmio_wlast),
    .s_axi_wvalid   (axi_mmio_wvalid),
    .s_axi_wready   (axi_mmio_wready),
    .s_axi_bid      (axi_mmio_bid),
    .s_axi_bresp    (axi_mmio_bresp),
    .s_axi_bvalid   (axi_mmio_bvalid),
    .s_axi_bready   (axi_mmio_bready),
    .s_axi_arid     (axi_mmio_arid),
    .s_axi_araddr   (axi_mmio_araddr),
    .s_axi_arlen    (axi_mmio_arlen),
    .s_axi_arsize   (axi_mmio_arsize),
    .s_axi_arburst  (axi_mmio_arburst),
    .s_axi_arlock   (axi_mmio_arlock),
    .s_axi_arcache  (axi_mmio_arcache),
    .s_axi_arprot   (axi_mmio_arprot),
    .s_axi_arvalid  (axi_mmio_arvalid),
    .s_axi_arready  (axi_mmio_arready),
    .s_axi_rid      (axi_mmio_rid),
    .s_axi_rdata    (axi_mmio_rdata),
    .s_axi_rresp    (axi_mmio_rresp),
    .s_axi_rlast    (axi_mmio_rlast),
    .s_axi_rvalid   (axi_mmio_rvalid),
    .s_axi_rready   (axi_mmio_rready),
    /* AXI lite master interface */
    .m_axil_awaddr  (axil_main_awaddr),
    .m_axil_awprot  (axil_main_awprot),
    .m_axil_awvalid (axil_main_awvalid),
    .m_axil_awready (axil_main_awready),
    .m_axil_wdata   (axil_main_wdata),
    .m_axil_wstrb   (axil_main_wstrb),
    .m_axil_wvalid  (axil_main_wvalid),
    .m_axil_wready  (axil_main_wready),
    .m_axil_bresp   (axil_main_bresp),
    .m_axil_bvalid  (axil_main_bvalid),
    .m_axil_bready  (axil_main_bready),
    .m_axil_araddr  (axil_main_araddr),
    .m_axil_arprot  (axil_main_arprot),
    .m_axil_arvalid (axil_main_arvalid),
    .m_axil_arready (axil_main_arready),
    .m_axil_rdata   (axil_main_rdata),
    .m_axil_rresp   (axil_main_rresp),
    .m_axil_rvalid  (axil_main_rvalid),
    .m_axil_rready  (axil_main_rready)
  );

  // interconnect
  axil_interconnect #(
    .S_COUNT         (1),                                                // Number of AXI inputs (slave interfaces)
    .M_COUNT         (6),                                                // Number of AXI outputs (master interfaces)
    .DATA_WIDTH      (32),                                               // Width of data bus in bits
    .ADDR_WIDTH      (32),                                               // Width of address bus in bits
    .STRB_WIDTH      (4),                                                // Width of wstrb (width of data bus in words)
    .M_REGIONS       (1),                                                // Number of regions per master interface
    .M_BASE_ADDR     ({BHSENSORIF_CFG_BASE, DCCAMIF_CFG_BASE, EFPGA_CFG_BASE, EFPGA_SLOT_BASE, CRYPTO_CFG_BASE, SPIRAM_CFG_BASE}),  // Master interface base addresses
    .M_ADDR_WIDTH    ({32'd24, 32'd24, 32'd24, 32'd24, 32'd24, 32'd24}), // Master interface address widths
    .M_CONNECT_READ  ({1'b1,   1'b1,   1'b1,   1'b1,   1'b1,   1'b1}),   // Read connections between interfaces; M_COUNT concatenated fields of S_COUNT bits
    .M_CONNECT_WRITE ({1'b1,   1'b1,   1'b1,   1'b1,   1'b1,   1'b1}),   // Write connections between interfaces, M_COUNT concatenated fields of S_COUNT bits
    .M_SECURE        ({1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0})    // Secure master (fail operations based on awprot/arprot), M_COUNT bits
  ) axil_interconnect_inst (
    .clk            (clk_i),
    .rst            (~system_resetn[RESET_AXIL]),
    /* AXI lite slave interfaces */
    .s_axil_awaddr  (axil_main_awaddr),
    .s_axil_awprot  (axil_main_awprot),
    .s_axil_awvalid (axil_main_awvalid),
    .s_axil_awready (axil_main_awready),
    .s_axil_wdata   (axil_main_wdata),
    .s_axil_wstrb   (axil_main_wstrb),
    .s_axil_wvalid  (axil_main_wvalid),
    .s_axil_wready  (axil_main_wready),
    .s_axil_bresp   (axil_main_bresp),
    .s_axil_bvalid  (axil_main_bvalid),
    .s_axil_bready  (axil_main_bready),
    .s_axil_araddr  (axil_main_araddr),
    .s_axil_arprot  (axil_main_arprot),
    .s_axil_arvalid (axil_main_arvalid),
    .s_axil_arready (axil_main_arready),
    .s_axil_rdata   (axil_main_rdata),
    .s_axil_rresp   (axil_main_rresp),
    .s_axil_rvalid  (axil_main_rvalid),
    .s_axil_rready  (axil_main_rready),
    /* AXI lite master interfaces*/
    .m_axil_awaddr  ({axil_bhsensorif_cfg_awaddr,  axil_dccamif_cfg_awaddr,  axil_efpga_cfg_awaddr,  axil_efpga_slot_awaddr,  axil_crypto_cfg_awaddr,  axil_spiram_cfg_awaddr }),
    .m_axil_awprot  ({axil_bhsensorif_cfg_awprot,  axil_dccamif_cfg_awprot,  axil_efpga_cfg_awprot,  axil_efpga_slot_awprot,  axil_crypto_cfg_awprot,  axil_spiram_cfg_awprot }),
    .m_axil_awvalid ({axil_bhsensorif_cfg_awvalid, axil_dccamif_cfg_awvalid, axil_efpga_cfg_awvalid, axil_efpga_slot_awvalid, axil_crypto_cfg_awvalid, axil_spiram_cfg_awvalid}),
    .m_axil_awready ({axil_bhsensorif_cfg_awready, axil_dccamif_cfg_awready, axil_efpga_cfg_awready, axil_efpga_slot_awready, axil_crypto_cfg_awready, axil_spiram_cfg_awready}),
    .m_axil_wdata   ({axil_bhsensorif_cfg_wdata,   axil_dccamif_cfg_wdata,   axil_efpga_cfg_wdata,   axil_efpga_slot_wdata,   axil_crypto_cfg_wdata,   axil_spiram_cfg_wdata  }),
    .m_axil_wstrb   ({axil_bhsensorif_cfg_wstrb,   axil_dccamif_cfg_wstrb,   axil_efpga_cfg_wstrb,   axil_efpga_slot_wstrb,   axil_crypto_cfg_wstrb,   axil_spiram_cfg_wstrb  }),
    .m_axil_wvalid  ({axil_bhsensorif_cfg_wvalid,  axil_dccamif_cfg_wvalid,  axil_efpga_cfg_wvalid,  axil_efpga_slot_wvalid,  axil_crypto_cfg_wvalid,  axil_spiram_cfg_wvalid }),
    .m_axil_wready  ({axil_bhsensorif_cfg_wready,  axil_dccamif_cfg_wready,  axil_efpga_cfg_wready,  axil_efpga_slot_wready,  axil_crypto_cfg_wready,  axil_spiram_cfg_wready }),
    .m_axil_bresp   ({axil_bhsensorif_cfg_bresp,   axil_dccamif_cfg_bresp,   axil_efpga_cfg_bresp,   axil_efpga_slot_bresp,   axil_crypto_cfg_bresp,   axil_spiram_cfg_bresp  }),
    .m_axil_bvalid  ({axil_bhsensorif_cfg_bvalid,  axil_dccamif_cfg_bvalid,  axil_efpga_cfg_bvalid,  axil_efpga_slot_bvalid,  axil_crypto_cfg_bvalid,  axil_spiram_cfg_bvalid }),
    .m_axil_bready  ({axil_bhsensorif_cfg_bready,  axil_dccamif_cfg_bready,  axil_efpga_cfg_bready,  axil_efpga_slot_bready,  axil_crypto_cfg_bready,  axil_spiram_cfg_bready }),
    .m_axil_araddr  ({axil_bhsensorif_cfg_araddr,  axil_dccamif_cfg_araddr,  axil_efpga_cfg_araddr,  axil_efpga_slot_araddr,  axil_crypto_cfg_araddr,  axil_spiram_cfg_araddr }),
    .m_axil_arprot  ({axil_bhsensorif_cfg_arprot,  axil_dccamif_cfg_arprot,  axil_efpga_cfg_arprot,  axil_efpga_slot_arprot,  axil_crypto_cfg_arprot,  axil_spiram_cfg_arprot }),
    .m_axil_arvalid ({axil_bhsensorif_cfg_arvalid, axil_dccamif_cfg_arvalid, axil_efpga_cfg_arvalid, axil_efpga_slot_arvalid, axil_crypto_cfg_arvalid, axil_spiram_cfg_arvalid}),
    .m_axil_arready ({axil_bhsensorif_cfg_arready, axil_dccamif_cfg_arready, axil_efpga_cfg_arready, axil_efpga_slot_arready, axil_crypto_cfg_arready, axil_spiram_cfg_arready}),
    .m_axil_rdata   ({axil_bhsensorif_cfg_rdata,   axil_dccamif_cfg_rdata,   axil_efpga_cfg_rdata,   axil_efpga_slot_rdata,   axil_crypto_cfg_rdata,   axil_spiram_cfg_rdata  }),
    .m_axil_rresp   ({axil_bhsensorif_cfg_rresp,   axil_dccamif_cfg_rresp,   axil_efpga_cfg_rresp,   axil_efpga_slot_rresp,   axil_crypto_cfg_rresp,   axil_spiram_cfg_rresp  }),
    .m_axil_rvalid  ({axil_bhsensorif_cfg_rvalid,  axil_dccamif_cfg_rvalid,  axil_efpga_cfg_rvalid,  axil_efpga_slot_rvalid,  axil_crypto_cfg_rvalid,  axil_spiram_cfg_rvalid }),
    .m_axil_rready  ({axil_bhsensorif_cfg_rready,  axil_dccamif_cfg_rready,  axil_efpga_cfg_rready,  axil_efpga_slot_rready,  axil_crypto_cfg_rready,  axil_spiram_cfg_rready })
  );

  // *************************************************************************************
  // On-Chip SRAM
  // *************************************************************************************

  // SRAM bank 0
`ifdef TECH_FPGA
  axi_ram #(
`else
  spram_ihp130nm #(
`endif
    .DATA_WIDTH      (32),           // Width of data bus in bits
    .ADDR_WIDTH      (SRAM0_AWIDTH), // Effectve width of address bus in bits
    .STRB_WIDTH      (4),            // Width of wstrb (width of data bus in words)
    .ID_WIDTH        (8),            // Width of ID signal
    .PIPELINE_OUTPUT (1)             // Extra pipeline register on output
  ) axi_sram0_inst (
    .clk           (clk_i),
    .rst           (~system_resetn[RESET_SRAM]),
    .s_axi_awid    (axi_sram0_awid),
    .s_axi_awaddr  (axi_sram0_awaddr[SRAM0_AWIDTH-1:0]),
    .s_axi_awlen   (axi_sram0_awlen),
    .s_axi_awsize  (axi_sram0_awsize),
    .s_axi_awburst (axi_sram0_awburst),
    .s_axi_awlock  (axi_sram0_awlock),
    .s_axi_awcache (axi_sram0_awcache),
    .s_axi_awprot  (axi_sram0_awprot),
    .s_axi_awvalid (axi_sram0_awvalid),
    .s_axi_awready (axi_sram0_awready),
    .s_axi_wdata   (axi_sram0_wdata),
    .s_axi_wstrb   (axi_sram0_wstrb),
    .s_axi_wlast   (axi_sram0_wlast),
    .s_axi_wvalid  (axi_sram0_wvalid),
    .s_axi_wready  (axi_sram0_wready),
    .s_axi_bid     (axi_sram0_bid),
    .s_axi_bresp   (axi_sram0_bresp),
    .s_axi_bvalid  (axi_sram0_bvalid),
    .s_axi_bready  (axi_sram0_bready),
    .s_axi_arid    (axi_sram0_arid),
    .s_axi_araddr  (axi_sram0_araddr[SRAM0_AWIDTH-1:0]),
    .s_axi_arlen   (axi_sram0_arlen),
    .s_axi_arsize  (axi_sram0_arsize),
    .s_axi_arburst (axi_sram0_arburst),
    .s_axi_arlock  (axi_sram0_arlock),
    .s_axi_arcache (axi_sram0_arcache),
    .s_axi_arprot  (axi_sram0_arprot),
    .s_axi_arvalid (axi_sram0_arvalid),
    .s_axi_arready (axi_sram0_arready),
    .s_axi_rid     (axi_sram0_rid),
    .s_axi_rdata   (axi_sram0_rdata),
    .s_axi_rresp   (axi_sram0_rresp),
    .s_axi_rlast   (axi_sram0_rlast),
    .s_axi_rvalid  (axi_sram0_rvalid),
    .s_axi_rready  (axi_sram0_rready)
  );

  // SRAM bank 0
`ifdef TECH_FPGA
  axi_ram #(
`else
  spram_ihp130nm #(
`endif
    .DATA_WIDTH      (32),           // Width of data bus in bits
    .ADDR_WIDTH      (SRAM1_AWIDTH), // Effective width of address bus in bits
    .STRB_WIDTH      (4),            // Width of wstrb (width of data bus in words)
    .ID_WIDTH        (8),            // Width of ID signal
    .PIPELINE_OUTPUT (1)             // Extra pipeline register on output
  ) axi_sram1_inst (
    .clk           (clk_i),
    .rst           (~system_resetn[RESET_SRAM]),
    .s_axi_awid    (axi_sram1_awid),
    .s_axi_awaddr  (axi_sram1_awaddr[SRAM1_AWIDTH-1:0]),
    .s_axi_awlen   (axi_sram1_awlen),
    .s_axi_awsize  (axi_sram1_awsize),
    .s_axi_awburst (axi_sram1_awburst),
    .s_axi_awlock  (axi_sram1_awlock),
    .s_axi_awcache (axi_sram1_awcache),
    .s_axi_awprot  (axi_sram1_awprot),
    .s_axi_awvalid (axi_sram1_awvalid),
    .s_axi_awready (axi_sram1_awready),
    .s_axi_wdata   (axi_sram1_wdata),
    .s_axi_wstrb   (axi_sram1_wstrb),
    .s_axi_wlast   (axi_sram1_wlast),
    .s_axi_wvalid  (axi_sram1_wvalid),
    .s_axi_wready  (axi_sram1_wready),
    .s_axi_bid     (axi_sram1_bid),
    .s_axi_bresp   (axi_sram1_bresp),
    .s_axi_bvalid  (axi_sram1_bvalid),
    .s_axi_bready  (axi_sram1_bready),
    .s_axi_arid    (axi_sram1_arid),
    .s_axi_araddr  (axi_sram1_araddr[SRAM1_AWIDTH-1:0]),
    .s_axi_arlen   (axi_sram1_arlen),
    .s_axi_arsize  (axi_sram1_arsize),
    .s_axi_arburst (axi_sram1_arburst),
    .s_axi_arlock  (axi_sram1_arlock),
    .s_axi_arcache (axi_sram1_arcache),
    .s_axi_arprot  (axi_sram1_arprot),
    .s_axi_arvalid (axi_sram1_arvalid),
    .s_axi_arready (axi_sram1_arready),
    .s_axi_rid     (axi_sram1_rid),
    .s_axi_rdata   (axi_sram1_rdata),
    .s_axi_rresp   (axi_sram1_rresp),
    .s_axi_rlast   (axi_sram1_rlast),
    .s_axi_rvalid  (axi_sram1_rvalid),
    .s_axi_rready  (axi_sram1_rready)
  );

  // *************************************************************************************
  // UHD Embedded FPGA
  // *************************************************************************************
`ifdef TECH_FPGA // exclude module for FPGA emulation
  assign axil_efpga_cfg_awready = 1'b1;
  assign axil_efpga_cfg_wready  = 1'b1;
  assign axil_efpga_cfg_bresp   = 2'b00;
  assign axil_efpga_cfg_bvalid  = 1'b1;
  assign axil_efpga_cfg_arready = 1'b1;
  assign axil_efpga_cfg_rdata   = 32'hdeadc0de;
  assign axil_efpga_cfg_rresp   = 2'b00;
  assign axil_efpga_cfg_rvalid  = 1'b1;
  //
  assign axil_efpga_slot_awready = 1'b1;
  assign axil_efpga_slot_wready  = 1'b1;
  assign axil_efpga_slot_bresp   = 2'b00;
  assign axil_efpga_slot_bvalid  = 1'b1;
  assign axil_efpga_slot_arready = 1'b1;
  assign axil_efpga_slot_rdata   = 32'hdeadc0de;
  assign axil_efpga_slot_rresp   = 2'b00;
  assign axil_efpga_slot_rvalid  = 1'b1;
  //
  assign axi_efpga_awaddr  = 32'h00000000;
  assign axi_efpga_awlen   = 8'h00;
  assign axi_efpga_awsize  = 4'h0;
  assign axi_efpga_awburst = 2'b00;
  assign axi_efpga_awlock  = 1'b0;
  assign axi_efpga_awcache = 4'h0;
  assign axi_efpga_awprot  = 3'b000;
  assign axi_efpga_awvalid = 1'b0;
  assign axi_efpga_wdata   = 32'h00000000;
  assign axi_efpga_wstrb   = 4'h0;
  assign axi_efpga_wlast   = 1'b0;
  assign axi_efpga_wvalid  = 1'b0;
  assign axi_efpga_bready  = 1'b0;
  assign axi_efpga_araddr  = 32'h00000000;
  assign axi_efpga_arlen   = 8'h00;
  assign axi_efpga_arsize  = 4'h0;
  assign axi_efpga_arburst = 2'b00;
  assign axi_efpga_arlock  = 1'b0;
  assign axi_efpga_arcache = 4'h0;
  assign axi_efpga_arprot  = 3'b000;
  assign axi_efpga_arvalid = 1'b0;
  assign axi_efpga_rready  = 1'b0;
  assign efpga_io_out_o  = 8'b0;
  assign efpga_io_oe_o  = 8'b0;
  assign efpga_usr_irq_o = 4'b0;
  assign efpga_fault_irq_o = 1'b0;
`else
  efpga_subsystem_top #(
`ifdef __ICARUS__ // TODO: Question from UH1: why are these parameters only set for the iverilog flow (We did not do/intend that)?
    .AXI_ID_WIDTH (8),
    .HW_VERSION   (32'hFAB00001)
`endif
  ) efpga_subsystem_top_inst (
    // Global Clock & Synchronized System Resets
    .clk_i               (clk_i),
    .rst_efpga_connector_n_i ( system_resetn[RESET_EFPGA_CON0]), // Active-Low Reset for eFPGA AXI Connector (Manager, Decouplers, Watchdogs, Bridges)
    .rst_efpga_connector_i   (~system_resetn[RESET_EFPGA_CON1]), // Active-High Reset for eFPGA AXI Register Slices (Forencich IP)
    .rst_efpga_fabric_n_i    ( system_resetn[RESET_EFPGA_FAB]),  // Active-Low Configuration FSM Reset for eFPGA Fabric
    .rst_efpga_slot_n_i      ( system_resetn[RESET_EFPGA_SLOT]), // Active-Low Soft Resets for eFPGA User Softlogic Slots (4 bit vector)
    .rst_efpga_npu_n_i       ( system_resetn[RESET_EFPGA_NPU]),  // Active-Low Reset for Hardened NPU Complex
     // 1. AXI4-Lite Slave: Global Manager Interface
    .s_axil_mgr_awaddr   (axil_efpga_cfg_awaddr),
    .s_axil_mgr_awprot   (axil_efpga_cfg_awprot),
    .s_axil_mgr_awvalid  (axil_efpga_cfg_awvalid),
    .s_axil_mgr_awready  (axil_efpga_cfg_awready),
    .s_axil_mgr_wdata    (axil_efpga_cfg_wdata),
    .s_axil_mgr_wstrb    (axil_efpga_cfg_wstrb),
    .s_axil_mgr_wvalid   (axil_efpga_cfg_wvalid),
    .s_axil_mgr_wready   (axil_efpga_cfg_wready),
    .s_axil_mgr_bresp    (axil_efpga_cfg_bresp),
    .s_axil_mgr_bvalid   (axil_efpga_cfg_bvalid),
    .s_axil_mgr_bready   (axil_efpga_cfg_bready),
    .s_axil_mgr_araddr   (axil_efpga_cfg_araddr),
    .s_axil_mgr_arprot   (axil_efpga_cfg_arprot),
    .s_axil_mgr_arvalid  (axil_efpga_cfg_arvalid),
    .s_axil_mgr_arready  (axil_efpga_cfg_arready),
    .s_axil_mgr_rdata    (axil_efpga_cfg_rdata),
    .s_axil_mgr_rresp    (axil_efpga_cfg_rresp),
    .s_axil_mgr_rvalid   (axil_efpga_cfg_rvalid),
    .s_axil_mgr_rready   (axil_efpga_cfg_rready),
    // 2. AXI4-Lite Slave: Slot Control Interface (Array)
    .s_axil_ctrl_awaddr  (axil_efpga_slot_awaddr),
    .s_axil_ctrl_awprot  (axil_efpga_slot_awprot),
    .s_axil_ctrl_awvalid (axil_efpga_slot_awvalid),
    .s_axil_ctrl_awready (axil_efpga_slot_awready),
    .s_axil_ctrl_wdata   (axil_efpga_slot_wdata),
    .s_axil_ctrl_wstrb   (axil_efpga_slot_wstrb),
    .s_axil_ctrl_wvalid  (axil_efpga_slot_wvalid),
    .s_axil_ctrl_wready  (axil_efpga_slot_wready),
    .s_axil_ctrl_bresp   (axil_efpga_slot_bresp),
    .s_axil_ctrl_bvalid  (axil_efpga_slot_bvalid),
    .s_axil_ctrl_bready  (axil_efpga_slot_bready),
    .s_axil_ctrl_araddr  (axil_efpga_slot_araddr),
    .s_axil_ctrl_arprot  (axil_efpga_slot_arprot),
    .s_axil_ctrl_arvalid (axil_efpga_slot_arvalid),
    .s_axil_ctrl_arready (axil_efpga_slot_arready),
    .s_axil_ctrl_rdata   (axil_efpga_slot_rdata),
    .s_axil_ctrl_rresp   (axil_efpga_slot_rresp),
    .s_axil_ctrl_rvalid  (axil_efpga_slot_rvalid),
    .s_axil_ctrl_rready  (axil_efpga_slot_rready),
    // 3. AXI4 Full Master: Slot DMA Interface (Array)
    .m_axi_dma_awid      (),
    .m_axi_dma_awaddr    (axi_efpga_awaddr),
    .m_axi_dma_awlen     (axi_efpga_awlen),
    .m_axi_dma_awsize    (axi_efpga_awsize),
    .m_axi_dma_awburst   (axi_efpga_awburst),
    .m_axi_dma_awlock    (axi_efpga_awlock),
    .m_axi_dma_awcache   (axi_efpga_awcache),
    .m_axi_dma_awprot    (axi_efpga_awprot),
    .m_axi_dma_awvalid   (axi_efpga_awvalid),
    .m_axi_dma_awready   (axi_efpga_awready),
    .m_axi_dma_wdata     (axi_efpga_wdata),
    .m_axi_dma_wstrb     (axi_efpga_wstrb),
    .m_axi_dma_wlast     (axi_efpga_wlast),
    .m_axi_dma_wvalid    (axi_efpga_wvalid),
    .m_axi_dma_wready    (axi_efpga_wready),
    .m_axi_dma_bid       (8'h00),
    .m_axi_dma_bresp     (axi_efpga_bresp),
    .m_axi_dma_bvalid    (axi_efpga_bvalid),
    .m_axi_dma_bready    (axi_efpga_bready),
    .m_axi_dma_arid      (),
    .m_axi_dma_araddr    (axi_efpga_araddr),
    .m_axi_dma_arlen     (axi_efpga_arlen),
    .m_axi_dma_arsize    (axi_efpga_arsize),
    .m_axi_dma_arburst   (axi_efpga_arburst),
    .m_axi_dma_arlock    (axi_efpga_arlock),
    .m_axi_dma_arcache   (axi_efpga_arcache),
    .m_axi_dma_arprot    (axi_efpga_arprot),
    .m_axi_dma_arvalid   (axi_efpga_arvalid),
    .m_axi_dma_arready   (axi_efpga_arready),
    .m_axi_dma_rid       (8'h00),
    .m_axi_dma_rdata     (axi_efpga_rdata),
    .m_axi_dma_rresp     (axi_efpga_rresp),
    .m_axi_dma_rlast     (axi_efpga_rlast),
    .m_axi_dma_rvalid    (axi_efpga_rvalid),
    .m_axi_dma_rready    (axi_efpga_rready),
    // top IOs
    .pmod_io_i           (efpga_io_in_i),
    .pmod_io_o           (efpga_io_out_o),
    .pmod_io_oe_o        (efpga_io_oe_o),
    // Bitbang configuration adapter
    .efpga_cfg_sclk_i    (efpga_cfg_sclk_i),
    .efpga_cfg_sdata_i   (efpga_cfg_sdata_i),
    // user interrupt
    .efpga_usr_irq_o     (efpga_usr_irq_o), // 4 bit vector
    .efpga_fault_irq_o   (efpga_fault_irq_o) // single bit connection
  );
`endif

  // *************************************************************************************
  // B-Horizon Sensor Interface
  // *************************************************************************************
  BHsensorIF_top BHsensorIF_top_inst (
    // global control
    .i_clk            (clk_i),
    .i_rst_n          (system_resetn[RESET_BH]),
    // sensor interface
    .i_rxd            (bhif_rxd_i),
    .o_cts            (bhif_cts_o),
    .o_irq_state      (irq_bhsensorif),
    .i_irq_clr        (1'b0), // IRQs can be cleared by software
    // axil device
    .s_axil_awaddr_i  (axil_bhsensorif_cfg_awaddr),
    .s_axil_awvalid_i (axil_bhsensorif_cfg_awvalid),
    .s_axil_awready_o (axil_bhsensorif_cfg_awready),
    .s_axil_wdata_i   (axil_bhsensorif_cfg_wdata),
    .s_axil_wstrb_i   (axil_bhsensorif_cfg_wstrb),
    .s_axil_wvalid_i  (axil_bhsensorif_cfg_wvalid),
    .s_axil_wready_o  (axil_bhsensorif_cfg_wready),
    .s_axil_bresp_o   (axil_bhsensorif_cfg_bresp),
    .s_axil_bvalid_o  (axil_bhsensorif_cfg_bvalid),
    .s_axil_bready_i  (axil_bhsensorif_cfg_bready),
    .s_axil_araddr_i  (axil_bhsensorif_cfg_araddr),
    .s_axil_arvalid_i (axil_bhsensorif_cfg_arvalid),
    .s_axil_arready_o (axil_bhsensorif_cfg_arready),
    .s_axil_rdata_o   (axil_bhsensorif_cfg_rdata),
    .s_axil_rresp_o   (axil_bhsensorif_cfg_rresp),
    .s_axil_rvalid_o  (axil_bhsensorif_cfg_rvalid),
    .s_axil_rready_i  (axil_bhsensorif_cfg_rready),
    // axi host
    .m_axi_awaddr_o   (axi_bhsensorif_awaddr),
    .m_axi_awlen_o    (axi_bhsensorif_awlen),
    .m_axi_awsize_o   (axi_bhsensorif_awsize),
    .m_axi_awburst_o  (axi_bhsensorif_awburst),
    .m_axi_awvalid_o  (axi_bhsensorif_awvalid),
    .m_axi_awready_i  (axi_bhsensorif_awready),
    .m_axi_wdata_o    (axi_bhsensorif_wdata),
    .m_axi_wstrb_o    (axi_bhsensorif_wstrb),
    .m_axi_wlast_o    (axi_bhsensorif_wlast),
    .m_axi_wvalid_o   (axi_bhsensorif_wvalid),
    .m_axi_wready_i   (axi_bhsensorif_wready),
    .m_axi_bid_i      (1'b0),
    .m_axi_bresp_i    (axi_bhsensorif_bresp),
    .m_axi_bvalid_i   (axi_bhsensorif_bvalid),
    .m_axi_bready_o   (axi_bhsensorif_bready)
  );

  // unused
  assign axi_bhsensorif_awlock  = 1'b0;
  assign axi_bhsensorif_awcache = 4'b0000;
  assign axi_bhsensorif_awprot  = 3'b000;
  assign axi_bhsensorif_araddr  = 32'h00000000;
  assign axi_bhsensorif_arlen   = 8'h00;
  assign axi_bhsensorif_arsize  = 3'b000;
  assign axi_bhsensorif_arburst = 2'b00;
  assign axi_bhsensorif_arlock  = 1'b0;
  assign axi_bhsensorif_arcache = 4'b0000;
  assign axi_bhsensorif_arprot  = 3'b000;
  assign axi_bhsensorif_arvalid = 1'b0;
  assign axi_bhsensorif_rready  = 1'b0;

  // *************************************************************************************
  // DC-Vision Camera Interface
  // *************************************************************************************
  dc_cam_if_top dc_cam_if_top_inst (
    // basic interface
    .i_rstn_core        (system_resetn[RESET_DCV]),
    .i_clk_core        (clk_i),
    .o_interrupt_flag  (irq_dccamif),
    .i_interrupt_clear (8'b00000000),
    // camera input interface
    .i_cam_pixel_clk     (cam_pixel_clk_i),
    .i_cam_line_valid    (cam_line_valid_i),
    .i_cam_frame_valid   (cam_frame_valid_i),
    .i_cam_pixel_data    (cam_pixel_data_i),
    .o_cam_output_enable (), // TODO
    .o_cam_standby       (), // TODO
    .o_cam_reset         (), // TODO
    // data output interface
    .o_doutif_data   (cam_doutif_data_o),
    .o_doutif_valid  (cam_doutif_valid_o),
    .o_doutif_first  (cam_doutif_first_o),
    .o_doutif_clk    (cam_doutif_clk_o),
    // axil device
    .s00_axi_awaddr  (axil_dccamif_cfg_awaddr[19:0]),
    .s00_axi_awprot  (axil_dccamif_cfg_awprot),
    .s00_axi_awvalid (axil_dccamif_cfg_awvalid),
    .s00_axi_awready (axil_dccamif_cfg_awready),
    .s00_axi_wdata   (axil_dccamif_cfg_wdata),
    .s00_axi_wstrb   (axil_dccamif_cfg_wstrb),
    .s00_axi_wvalid  (axil_dccamif_cfg_wvalid),
    .s00_axi_wready  (axil_dccamif_cfg_wready),
    .s00_axi_bresp   (axil_dccamif_cfg_bresp),
    .s00_axi_bvalid  (axil_dccamif_cfg_bvalid),
    .s00_axi_bready  (axil_dccamif_cfg_bready),
    .s00_axi_araddr  (axil_dccamif_cfg_araddr[19:0]),
    .s00_axi_arprot  (axil_dccamif_cfg_arprot),
    .s00_axi_arvalid (axil_dccamif_cfg_arvalid),
    .s00_axi_arready (axil_dccamif_cfg_arready),
    .s00_axi_rdata   (axil_dccamif_cfg_rdata),
    .s00_axi_rresp   (axil_dccamif_cfg_rresp),
    .s00_axi_rvalid  (axil_dccamif_cfg_rvalid),
    .s00_axi_rready  (axil_dccamif_cfg_rready),
    // axi host
    .m00_axi_tx_done (), // TODO
    .m00_axi_error   (), // TODO
    .m00_axi_aclk    (clk_i),
    .m00_axi_aresetn (system_resetn[RESET_DCV]),
    .m00_axi_awid    (),
    .m00_axi_awaddr  (axi_dccamif_awaddr),
    .m00_axi_awlen   (axi_dccamif_awlen),
    .m00_axi_awsize  (axi_dccamif_awsize),
    .m00_axi_awburst (axi_dccamif_awburst),
    .m00_axi_awlock  (axi_dccamif_awlock),
    .m00_axi_awcache (axi_dccamif_awcache),
    .m00_axi_awprot  (axi_dccamif_awprot),
    .m00_axi_awqos   (),

    .m00_axi_awvalid (axi_dccamif_awvalid),
    .m00_axi_awready (axi_dccamif_awready),
    .m00_axi_wdata   (axi_dccamif_wdata),
    .m00_axi_wstrb   (axi_dccamif_wstrb),
    .m00_axi_wlast   (axi_dccamif_wlast),

    .m00_axi_wvalid  (axi_dccamif_wvalid),
    .m00_axi_wready  (axi_dccamif_wready),
    .m00_axi_bid     (1'b0),
    .m00_axi_bresp   (axi_dccamif_bresp),

    .m00_axi_bvalid  (axi_dccamif_bvalid),
    .m00_axi_bready  (axi_dccamif_bready),
    .m00_axi_arid    (),
    .m00_axi_araddr  (axi_dccamif_araddr),
    .m00_axi_arlen   (axi_dccamif_arlen),
    .m00_axi_arsize  (axi_dccamif_arsize),
    .m00_axi_arburst (axi_dccamif_arburst),
    .m00_axi_arlock  (axi_dccamif_arlock),
    .m00_axi_arcache (axi_dccamif_arcache),
    .m00_axi_arprot  (axi_dccamif_arprot),
    .m00_axi_arqos   (),

    .m00_axi_arvalid (axi_dccamif_arvalid),
    .m00_axi_arready (axi_dccamif_arready),
    .m00_axi_rid     (1'b0),
    .m00_axi_rdata   (axi_dccamif_rdata),
    .m00_axi_rresp   (axi_dccamif_rresp),
    .m00_axi_rlast   (axi_dccamif_rlast),

    .m00_axi_rvalid  (axi_dccamif_rvalid),
    .m00_axi_rready  (axi_dccamif_rready)
  );

  // *************************************************************************************
  // RUB Crypto Core
  // *************************************************************************************
  cryptoCore #(
    .AXI_DATA_WIDTH (32),
    .AXI_ADDR_WIDTH (32),
    .AXI_STRB_WIDTH (4),
    .AXI_ID_WIDTH   (8),
    .LEN_WIDTH      (20)
  ) cryptoCore_inst (
    // global control
    .clk            (clk_i),
    .rst            (~system_resetn[RESET_CRYPTO]),
    // axil device
    .s_axil_awaddr  (axil_crypto_cfg_awaddr[7:0]),
    .s_axil_awprot  (axil_crypto_cfg_awprot),
    .s_axil_awvalid (axil_crypto_cfg_awvalid),
    .s_axil_awready (axil_crypto_cfg_awready),
    .s_axil_wdata   (axil_crypto_cfg_wdata),
    .s_axil_wstrb   (axil_crypto_cfg_wstrb),
    .s_axil_wvalid  (axil_crypto_cfg_wvalid),
    .s_axil_wready  (axil_crypto_cfg_wready),
    .s_axil_bresp   (axil_crypto_cfg_bresp),
    .s_axil_bvalid  (axil_crypto_cfg_bvalid),
    .s_axil_bready  (axil_crypto_cfg_bready),
    .s_axil_araddr  (axil_crypto_cfg_araddr[7:0]),
    .s_axil_arprot  (axil_crypto_cfg_arprot),
    .s_axil_arvalid (axil_crypto_cfg_arvalid),
    .s_axil_arready (axil_crypto_cfg_arready),
    .s_axil_rdata   (axil_crypto_cfg_rdata),
    .s_axil_rresp   (axil_crypto_cfg_rresp),
    .s_axil_rvalid  (axil_crypto_cfg_rvalid),
    .s_axil_rready  (axil_crypto_cfg_rready),
    // axi host --
    .m_axi_awid     (),
    .m_axi_awaddr   (axi_crypto_awaddr),
    .m_axi_awlen    (axi_crypto_awlen),
    .m_axi_awsize   (axi_crypto_awsize),
    .m_axi_awburst  (axi_crypto_awburst),
    .m_axi_awlock   (axi_crypto_awlock),
    .m_axi_awcache  (axi_crypto_awcache),
    .m_axi_awprot   (axi_crypto_awprot),
    .m_axi_awvalid  (axi_crypto_awvalid),
    .m_axi_awready  (axi_crypto_awready),
    .m_axi_wdata    (axi_crypto_wdata),
    .m_axi_wstrb    (axi_crypto_wstrb),
    .m_axi_wlast    (axi_crypto_wlast),
    .m_axi_wvalid   (axi_crypto_wvalid),
    .m_axi_wready   (axi_crypto_wready),
    .m_axi_bid      (8'h00),
    .m_axi_bresp    (axi_crypto_bresp),
    .m_axi_bvalid   (axi_crypto_bvalid),
    .m_axi_bready   (axi_crypto_bready),
    .m_axi_arid     (),
    .m_axi_araddr   (axi_crypto_araddr),
    .m_axi_arlen    (axi_crypto_arlen),
    .m_axi_arsize   (axi_crypto_arsize),
    .m_axi_arburst  (axi_crypto_arburst),
    .m_axi_arlock   (axi_crypto_arlock),
    .m_axi_arcache  (axi_crypto_arcache),
    .m_axi_arprot   (axi_crypto_arprot),
    .m_axi_arvalid  (axi_crypto_arvalid),
    .m_axi_arready  (axi_crypto_arready),
    .m_axi_rid      (8'h00),
    .m_axi_rdata    (axi_crypto_rdata),
    .m_axi_rresp    (axi_crypto_rresp),
    .m_axi_rlast    (axi_crypto_rlast),
    .m_axi_rvalid   (axi_crypto_rvalid),
    .m_axi_rready   (axi_crypto_rready)
  );

  // *************************************************************************************
  // IMS SPI PSRAM Controller
  // *************************************************************************************

  // AXI-full to AXI-lite converter
  axi_axil_adapter #(
    .ADDR_WIDTH           (32),
    .AXI_DATA_WIDTH       (32),
    .AXI_STRB_WIDTH       (4),
    .AXI_ID_WIDTH         (8),
    .AXIL_DATA_WIDTH      (32),
    .AXIL_STRB_WIDTH      (4),
    .CONVERT_BURST        (0),
    .CONVERT_NARROW_BURST (0)
  ) axi_lite_bridge_spiram (
    .clk           (clk_i),
    .rst           (~system_resetn[RESET_SPIRAM]),
    // AXI slave interface
    .s_axi_awid    (axi_spiram_data_awid),
    .s_axi_awaddr  (axi_spiram_data_awaddr),
    .s_axi_awlen   (axi_spiram_data_awlen),
    .s_axi_awsize  (axi_spiram_data_awsize),
    .s_axi_awburst (axi_spiram_data_awburst),
    .s_axi_awlock  (axi_spiram_data_awlock),
    .s_axi_awcache (axi_spiram_data_awcache),
    .s_axi_awprot  (axi_spiram_data_awprot),
    .s_axi_awvalid (axi_spiram_data_awvalid),
    .s_axi_awready (axi_spiram_data_awready),
    .s_axi_wdata   (axi_spiram_data_wdata),
    .s_axi_wstrb   (axi_spiram_data_wstrb),
    .s_axi_wlast   (axi_spiram_data_wlast),
    .s_axi_wvalid  (axi_spiram_data_wvalid),
    .s_axi_wready  (axi_spiram_data_wready),
    .s_axi_bid     (axi_spiram_data_bid),
    .s_axi_bresp   (axi_spiram_data_bresp),
    .s_axi_bvalid  (axi_spiram_data_bvalid),
    .s_axi_bready  (axi_spiram_data_bready),
    .s_axi_arid    (axi_spiram_data_arid),
    .s_axi_araddr  (axi_spiram_data_araddr),
    .s_axi_arlen   (axi_spiram_data_arlen),
    .s_axi_arsize  (axi_spiram_data_arsize),
    .s_axi_arburst (axi_spiram_data_arburst),
    .s_axi_arlock  (axi_spiram_data_arlock),
    .s_axi_arcache (axi_spiram_data_arcache),
    .s_axi_arprot  (axi_spiram_data_arprot),
    .s_axi_arvalid (axi_spiram_data_arvalid),
    .s_axi_arready (axi_spiram_data_arready),
    .s_axi_rid     (axi_spiram_data_rid),
    .s_axi_rdata   (axi_spiram_data_rdata),
    .s_axi_rresp   (axi_spiram_data_rresp),
    .s_axi_rlast   (axi_spiram_data_rlast),
    .s_axi_rvalid  (axi_spiram_data_rvalid),
    .s_axi_rready  (axi_spiram_data_rready),
    // AXI lite master interface
    .m_axil_awaddr  (axil_spiram_data_awaddr),
    .m_axil_awprot  (axil_spiram_data_awprot),
    .m_axil_awvalid (axil_spiram_data_awvalid),
    .m_axil_awready (axil_spiram_data_awready),
    .m_axil_wdata   (axil_spiram_data_wdata),
    .m_axil_wstrb   (axil_spiram_data_wstrb),
    .m_axil_wvalid  (axil_spiram_data_wvalid),
    .m_axil_wready  (axil_spiram_data_wready),
    .m_axil_bresp   (axil_spiram_data_bresp),
    .m_axil_bvalid  (axil_spiram_data_bvalid),
    .m_axil_bready  (axil_spiram_data_bready),
    .m_axil_araddr  (axil_spiram_data_araddr),
    .m_axil_arprot  (axil_spiram_data_arprot),
    .m_axil_arvalid (axil_spiram_data_arvalid),
    .m_axil_arready (axil_spiram_data_arready),
    .m_axil_rdata   (axil_spiram_data_rdata),
    .m_axil_rresp   (axil_spiram_data_rresp),
    .m_axil_rvalid  (axil_spiram_data_rvalid),
    .m_axil_rready  (axil_spiram_data_rready)
  );

  // SPI RAM controller
  spiram_controller_axi spiram_controller_axi_inst (
    // global control
    .resetn         (system_resetn[RESET_SPIRAM]),
    .clk            (clk_i),
    // configuration interface
    .s0_axi_awaddr  (axil_spiram_cfg_awaddr),
    .s0_axi_awprot  (axil_spiram_cfg_awprot),
    .s0_axi_awvalid (axil_spiram_cfg_awvalid),
    .s0_axi_awready (axil_spiram_cfg_awready),
    .s0_axi_wdata   (axil_spiram_cfg_wdata),
    .s0_axi_wstrb   (axil_spiram_cfg_wstrb),
    .s0_axi_wvalid  (axil_spiram_cfg_wvalid),
    .s0_axi_wready  (axil_spiram_cfg_wready),
    .s0_axi_araddr  (axil_spiram_cfg_araddr),
    .s0_axi_arprot  (axil_spiram_cfg_arprot),
    .s0_axi_arvalid (axil_spiram_cfg_arvalid),
    .s0_axi_arready (axil_spiram_cfg_arready),
    .s0_axi_rdata   (axil_spiram_cfg_rdata),
    .s0_axi_rresp   (axil_spiram_cfg_rresp),
    .s0_axi_rvalid  (axil_spiram_cfg_rvalid),
    .s0_axi_rready  (axil_spiram_cfg_rready),
    .s0_axi_bresp   (axil_spiram_cfg_bresp),
    .s0_axi_bvalid  (axil_spiram_cfg_bvalid),
    .s0_axi_bready  (axil_spiram_cfg_bready),
    // data interface
    .s1_axi_awaddr  (axil_spiram_data_awaddr),
    .s1_axi_awprot  (axil_spiram_data_awprot),
    .s1_axi_awvalid (axil_spiram_data_awvalid),
    .s1_axi_awready (axil_spiram_data_awready),
    .s1_axi_wdata   (axil_spiram_data_wdata),
    .s1_axi_wstrb   (axil_spiram_data_wstrb),
    .s1_axi_wvalid  (axil_spiram_data_wvalid),
    .s1_axi_wready  (axil_spiram_data_wready),
    .s1_axi_araddr  (axil_spiram_data_araddr),
    .s1_axi_arprot  (axil_spiram_data_arprot),
    .s1_axi_arvalid (axil_spiram_data_arvalid),
    .s1_axi_arready (axil_spiram_data_arready),
    .s1_axi_rdata   (axil_spiram_data_rdata),
    .s1_axi_rresp   (axil_spiram_data_rresp),
    .s1_axi_rvalid  (axil_spiram_data_rvalid),
    .s1_axi_rready  (axil_spiram_data_rready),
    .s1_axi_bresp   (axil_spiram_data_bresp),
    .s1_axi_bvalid  (axil_spiram_data_bvalid),
    .s1_axi_bready  (axil_spiram_data_bready),
    // psram interface
    .spi_clk_o     (spiram_clk_o),
    .spi_csn_o     (spiram_csn_o),
    .spi_di_i      (spiram_sdi_i),
    .spi_do_o      (spiram_sdo_o)
  );

  // *************************************************************************************
  // UHD Octal PSRAM Controller
  // *************************************************************************************

  // The crossbar forwards the full system address. The controller sends AXI address / 4 to each chip, and the
  // chips require the upper address byte (A[31:24]) to be zero, so only pass the offset inside the OCTRAM window.
  localparam [31:0] OCTRAM_OFFSET_MASK = ~(32'hFFFFFFFF << OCTRAM_AWIDTH);
  wire [31:0] axi_octram_awaddr_offset = axi_octram_awaddr & OCTRAM_OFFSET_MASK;
  wire [31:0] axi_octram_araddr_offset = axi_octram_araddr & OCTRAM_OFFSET_MASK;

  OctalMemoryController_quad #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .STRB_WIDTH (4),
    .ID_WIDTH   (8),
    .CHIP_TYPE  (2), // must be 2 (APMemory APS12808L)
    .CLK_FREQ_HZ(50_000_000) // clk_i, the PSRAM reset / tCEM timings are derived from it
  ) OctalMemoryController_quad_inst (
    .clk   (clk_i),
    .rstn  (system_resetn[RESET_OCTRAM]),
    // memory
    .o_spi_bus_clock             (octram_bus_clk_o),
    // o_spi_bus_clock_neg not connected: the APMemory chips have no CK# input
    .o_spi_chip_select_neg       (octram_csn_o),
    .o_spi_reset_neg             (octram_resetn_o),
    .i_data_strobe               (octram_strobe_i),
    .o_data_strobe               (octram_strobe_o),
    .o_data_strobe_output_enable (octram_strobe_oe_o),
    .i_data                      (octram_data_i),
    .o_data                      (octram_data_o),
    .o_data_output_enable        (octram_data_oe_o),
    // AXI
    .s_axi_awid    (axi_octram_awid),
    .s_axi_awaddr  (axi_octram_awaddr_offset),
    .s_axi_awlen   (axi_octram_awlen),
    .s_axi_awsize  (axi_octram_awsize),
    .s_axi_awburst (axi_octram_awburst),
    .s_axi_awlock  (axi_octram_awlock),
    .s_axi_awcache (axi_octram_awcache),
    .s_axi_awprot  (axi_octram_awprot),
    .s_axi_awvalid (axi_octram_awvalid),
    .s_axi_awready (axi_octram_awready),
    .s_axi_wdata   (axi_octram_wdata),
    .s_axi_wstrb   (axi_octram_wstrb),
    .s_axi_wlast   (axi_octram_wlast),
    .s_axi_wvalid  (axi_octram_wvalid),
    .s_axi_wready  (axi_octram_wready),
    .s_axi_bid     (axi_octram_bid),
    .s_axi_bresp   (axi_octram_bresp),
    .s_axi_bvalid  (axi_octram_bvalid),
    .s_axi_bready  (axi_octram_bready),
    .s_axi_arid    (axi_octram_arid),
    .s_axi_araddr  (axi_octram_araddr_offset),
    .s_axi_arlen   (axi_octram_arlen),
    .s_axi_arsize  (axi_octram_arsize),
    .s_axi_arburst (axi_octram_arburst),
    .s_axi_arlock  (axi_octram_arlock),
    .s_axi_arcache (axi_octram_arcache),
    .s_axi_arprot  (axi_octram_arprot),
    .s_axi_arvalid (axi_octram_arvalid),
    .s_axi_arready (axi_octram_arready),
    .s_axi_rid     (axi_octram_rid),
    .s_axi_rdata   (axi_octram_rdata),
    .s_axi_rresp   (axi_octram_rresp),
    .s_axi_rlast   (axi_octram_rlast),
    .s_axi_rvalid  (axi_octram_rvalid),
    .s_axi_rready  (axi_octram_rready)
);

endmodule
