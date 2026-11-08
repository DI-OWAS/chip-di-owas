// DI-OWAS main testbench

`timescale 1 ns/100 ps // time-unit = 1 ns, precision = 100 ps

`define CORE_CLK_PERIOD 20  // CPU clock period
`define JTAG_CLK_PERIOD 200 // JTAG interface clock period

// Internal monitors need the RTL hierarchy: off for a gate-level netlist (-DGATE_LEVEL).
// The core is diowas_top_dut (TECH_FPGA) or diowas_top_i inside the pad ring.
`ifdef TECH_FPGA
`define DUT_CORE diowas_top_dut
`else
`define DUT_CORE diowas_top_pads_dut.diowas_top_i
`endif
`ifndef GATE_LEVEL
`define TB_MONITORS
`endif
// cryptoCore at gate level (sim_octram.mk gl_inst): only its ports and the kept dma_busy net
`ifdef GL_cryptoCore_inst
`define CRYPTO_DMA_BUSY `DUT_CORE.cryptoCore_inst.dma_busy
`else
`define CRYPTO_DMA_BUSY `DUT_CORE.cryptoCore_inst.u_cryptoDmaCtrl.dma_busy
`endif

module diowas_top_tb;

  integer i;
  integer octram_test_errors = 0;
  integer rst_wait_cycles; // reset test: clock cycles waited for a DMA burst

  // JTAG access
  reg  tck, tms, tdi;
  wire tdo, tck_wire, tms_wire, tdi_wire;
`include "jtag_tasks.vh"
  assign tck_wire = tck;
  assign tms_wire = tms;
  assign tdi_wire = tdi;

  // generators
  reg clk, rstn;
  reg bfm_imager_clk;
  localparam integer BFM_CLK_PERIOD = 80 * `CORE_CLK_PERIOD;

  // wiring
  wire clk_wire, rstn_wire, rst_wire;
  wire uart_txd, uart_rxd, spi_sck, spi_sdo, spi_sdi, spiram_sck, spiram_sdi, spiram_sdo;
  wire [1:0] spi_csn, spiram_csn;
  wire logic0;
  wire ts;

  // ---- octal PSRAM test ----
  // address map
  localparam [31:0]  SRAM0_BASE         = 32'h00000000;
  localparam [31:0]  OCTRAM_BASE        = 32'h20000000;
  localparam [31:0]  SRAM1_BASE         = 32'h80000000;
  localparam [31:0]  CRYPTO_BASE        = 32'hF5000000;
  localparam integer BYTES_PER_WORD     = 4;
  localparam integer OCTRAM_CHIPS       = 4;      // one APS12808L per byte lane

  // crypto core registers (DMA in bypass mode = plain copy)
  localparam [31:0]  CRYPTO_CTRL        = CRYPTO_BASE + 32'h00;
  localparam [31:0]  CRYPTO_SRC_ADDR    = CRYPTO_BASE + 32'h50;
  localparam [31:0]  CRYPTO_DST_ADDR    = CRYPTO_BASE + 32'h54;
  localparam [31:0]  CRYPTO_DMA_BLOCKS  = CRYPTO_BASE + 32'h58;
  localparam [31:0]  CRYPTO_GO          = CRYPTO_BASE + 32'h5C;
  localparam [31:0]  CRYPTO_DMA_STATUS  = CRYPTO_BASE + 32'h60;
  localparam [31:0]  CRYPTO_CTRL_BYPASS = 32'h2;
  localparam integer DMA_ST_BUSY = 0, DMA_ST_DONE = 1, DMA_ST_ERROR = 2;  // DMA_STATUS bits
  localparam integer DMA_BLOCK_WORDS    = 4;      // 16 bytes per DMA block

  // test buffers
  localparam [31:0]  SRAM0_BUF    = SRAM0_BASE  + 32'h200;
  localparam [31:0]  SRAM1_BUF    = SRAM1_BASE  + 32'h400;
  localparam [31:0]  OCT_DMA      = OCTRAM_BASE + 32'h1000;
  localparam [31:0]  OCT_P2P_SRC  = OCTRAM_BASE + 32'h200FC4;  // just below a 4 KB boundary
  localparam [31:0]  OCT_P2P_DST  = OCTRAM_BASE + 32'h300000;
  localparam [31:0]  OCT_CONC_SRC = OCTRAM_BASE + 32'h400000;
  localparam [31:0]  OCT_CONC_DST = OCTRAM_BASE + 32'h500000;
  localparam [31:0]  OCT_CONC_CPU = OCTRAM_BASE + 32'h600000;
  localparam [31:0]  OCT_RST_DST  = OCTRAM_BASE + 32'h700000;

  // test sizes and data
  localparam integer OCT_JTAG_WORDS     = 4;
  localparam integer DMA_TEST_BLOCKS    = 4;
  localparam integer DMA_TEST_WORDS     = DMA_TEST_BLOCKS*DMA_BLOCK_WORDS;
  localparam integer CONC_BLOCKS        = 256;    // 4 KB
  localparam integer CONC_CHECKS        = 16;     // checked words, one every CONC_CHECK_STRIDE bytes
  localparam integer CONC_CHECK_STRIDE  = 256;
  // octram_pattern() start index per test, so every test writes different data
  localparam integer PAT_JTAG = 0, PAT_DMA = 16, PAT_P2P = 32, PAT_CONC = 64, PAT_CONC_CPU = 96, PAT_RST = 112;

  // reset during DMA test
  localparam integer RST_AFTER_R_BEATS  = CONC_BLOCKS*DMA_BLOCK_WORDS/4;  // reset after a quarter of the copy
  localparam integer RST_DELAY          = 2000;   // without monitors: reset during the 4 KB copy (about 8000 cycles)
  localparam integer RST_WAIT_MAX       = 200000;
  localparam integer RST_CYCLES         = 20;

  // timeouts and limits
  localparam integer FW_TIMEOUT_NS      = 1_000_000_000; // firmware phase, 1 s. octram_test needs about 0.51 s.
  localparam integer DMA_POLLS          = 200;    // DMA_STATUS polls over JTAG
  localparam integer OCT_PWRUP_WAIT     = 2000;   // controller power-up reset + MR init
  localparam integer OCT_HANG_CYCLES    = 100000; // AXI hang detection
  localparam integer OCT_MAX_ERR_PRINT  = 10;

  // octal PSRAM
  wire   [OCTRAM_CHIPS-1:0] octram_bus_clk; // one bus clock per chip
  wire                      octram_resetn;
  wire   [OCTRAM_CHIPS-1:0] octram_csn, octram_dqs, octram_dqs_out, octram_dqs_oe, octram_dq_oe;
  wire [8*OCTRAM_CHIPS-1:0] octram_dq, octram_dq_out;

  // camera interface
  wire frame_valid, line_valid, pixel_clock;
  wire [11:0] pixel_data;

  // BH sensor interface
`include "sac2owas.vh"
  wire [1:0] bh_rxd;
  wire bh_cts;

  // *************************************************************************************
  // Generators
  // *************************************************************************************

  // main clock
  always begin
    #(`CORE_CLK_PERIOD/2) clk = !clk;
  end

  // Dedicated imager clock: 12.5 MHz for a 100 MHz core clock.
  always begin
    #(BFM_CLK_PERIOD/2) bfm_imager_clk = !bfm_imager_clk;
  end

  // testbench init
  initial begin
    clk  = 0;
    bfm_imager_clk = 0;
    rstn = 0;
    $display("\n[TB] DI-OWAS: default testbench");
`ifdef WAVEDUMP
    $dumpfile("diowas_tb.vcd");
    $dumpvars(0, diowas_top_tb);
    $display("\n[TB] INFO: dumping simulation data to: %s","diowas_tb.shm");
`endif
    #100;
    rstn = 1;
  end

  // *************************************************************************************
  // DUT
  // *************************************************************************************

  assign clk_wire = clk;
  assign rstn_wire = rstn;
  assign rst_wire = ~rstn;
  assign logic0 = 1'b0;
  assign ts = 1'bz;

`ifdef TECH_FPGA
  diowas_top diowas_top_dut (
    // Global control
    .clk_i              (clk_wire),
    .rstn_i             (rstn_wire),
    // Core complex: JTAG TAP
    .jtag_tck_i         (tck_wire),
    .jtag_tdi_i         (tdi_wire),
    .jtag_tdo_o         (tdo),
    .jtag_tms_i         (tms_wire),
    // Core complex: SPI host
    .spi_csn_o          (spi_csn),
    .spi_sck_o          (spi_sck),
    .spi_sdo_o          (spi_sdo),
    .spi_sdi_i          (spi_sdi),
    // Core complex: I2C host
    .twi_scl_o          (), // [Nol] TODO
    .twi_scl_i          (1'b1), // [Nol] TODO
    .twi_sda_o          (), // [Nol] TODO
    .twi_sda_i          (1'b1), // [Nol] TODO
    // Core complex: Heartbeat LED
    .status_led_o       (), // [Nol] TODO
    // Core complex: Serial console
    .console_txd_o      (uart_txd),
    .console_rxd_i      (uart_rxd),
    // SPI PSRAM
    .spiram_clk_o       (spiram_sck),
    .spiram_csn_o       (spiram_csn),
    .spiram_sdi_i       (spiram_sdi),
    .spiram_sdo_o       (spiram_sdo),
    // Octal PSRAM
    .octram_bus_clk_o   (octram_bus_clk),
    .octram_csn_o       (octram_csn),
    .octram_resetn_o    (octram_resetn),
    .octram_strobe_i    (octram_dqs),
    .octram_strobe_o    (octram_dqs_out),
    .octram_strobe_oe_o (octram_dqs_oe),
    .octram_data_i      (octram_dq),
    .octram_data_o      (octram_dq_out),
    .octram_data_oe_o   (octram_dq_oe),
    // camera Interface
    .cam_pixel_clk_i    (pixel_clock),
    .cam_line_valid_i   (line_valid),
    .cam_frame_valid_i  (frame_valid),
    .cam_pixel_data_i   (pixel_data),
    .cam_doutif_data_o  (),
    .cam_doutif_valid_o (),
    .cam_doutif_first_o (),
    .cam_doutif_clk_o   (),
    // BH Sensor IF UARTs
    .bhif_rxd_i         (bh_rxd),
    .bhif_cts_o         (bh_cts),
    // eFPGA user IOs
    .efpga_io_out_o     (),
    .efpga_io_oe_o      (),
    .efpga_io_in_i      (8'h00)
  );
`else
  diowas_top_pads diowas_top_pads_dut ( // [Nol] TODO
`ifdef USE_POWER_PINS
    .VDD(),
    .VSS(),
    .IOVDD(),
    .IOVSS(),
`endif
    // global control
    .clk_i_PAD              (clk_wire),
    .rstn_i_PAD             (rstn_wire),
    // jtag on-chip debugger interface
    .jtag_tck_i_PAD         (tck_wire),
    .jtag_tdi_i_PAD         (tdi_wire),
    .jtag_tdo_o_PAD         (tdo),
    .jtag_tms_i_PAD         (tms_wire),
    // I2C interface
    .twi_scl_PAD            (), // TODO
    .twi_sda_PAD            (), // TODO
    // SPI host
    .spi_csn_o_PAD          (spi_csn),
    .spi_sck_o_PAD          (spi_sck),
    .spi_sdo_o_PAD          (spi_sdo),
    .spi_sdi_i_PAD          (spi_sdi),
    // heartbeat LED
    .status_led_o_PAD       (), // TODO
    // uart0
    .console_txd_o_PAD      (uart_txd),
    .console_rxd_i_PAD      (uart_rxd),
    // SPI PSRAM
    .spiram_clk_o_PAD       (spiram_sck),
    .spiram_csn_o_PAD       (spiram_csn),
    .spiram_sdi_i_PAD       (spiram_sdi),
    .spiram_sdo_o_PAD       (spiram_sdo),
    // Octal PSRAM
    .qspiram_bus_clk_o_PAD  (octram_bus_clk),
    .qspiram_csn_o_PAD      (octram_csn),
    .qspiram_resetn_o_PAD   (octram_resetn),
    .qspiram_strobe_io_PAD  (octram_dqs),
    .qspiram_data_io_PAD    (octram_dq),
    // DCV Camera Interface
    .cam_pixel_clk_i_PAD    (pixel_clock),
    .cam_frame_valid_i_PAD  (frame_valid),
    .cam_line_valid_i_PAD   (line_valid),
    .cam_pixel_data_i_PAD   (pixel_data),
    .cam_doutif_data_o_PAD  (),
    .cam_doutif_valid_o_PAD (),
    .cam_doutif_first_o_PAD (),
    .cam_doutif_clk_o_PAD   (),
    // BH Interface UARTs
    .bhif_rxd_i_PAD         (bh_rxd),
    .bhif_cts_o_PAD         (bh_cts),
    // eFPGA user IOs
    .efpga_io_PAD           ()
  );
`endif

  // *************************************************************************************
  // SPI flash
  // *************************************************************************************

  // -DBOOT_IMAGE='"<file>"' replaces the default boot image, e.g. the octal PSRAM
  // test firmware: make -C ../firmware/octram_test sim_image, then
  // -DBOOT_IMAGE='"../firmware/octram_test/octram_boot_image.mem"' (path relative to units/top)
  spi_rom #(
`ifdef BOOT_IMAGE
    .INIT_FILE   (`BOOT_IMAGE),
`else
    .INIT_FILE   ("src/sim/boot_image.mem"),
`endif
    .SIZE_BYTES  (16*1024),
    .ADDR_OFFSET (32'd0),
    .ADDR_BYTES  (3)
  ) spi_rom_inst (
    .sck (spi_sck),
    .csn (spi_csn[0]),
    .sdi (spi_sdo),
    .sdo (spi_sdi)
  );

  pulldown(spi_sdi);

  // *************************************************************************************
  // SPI PSRAM
  // *************************************************************************************

  wire [3:0] spi_psram_sdio;

  pulldown(spi_psram_sdio[0]);
  pulldown(spi_psram_sdio[1]);
  pulldown(spi_psram_sdio[2]);
  pulldown(spi_psram_sdio[3]);

  assign spi_psram_sdio[0] = spiram_sdo;
  assign spiram_sdi = spi_psram_sdio[1];

  psram_model #(
    .MEM_BYTES (4096)
  ) spi_psram_inst (
    .sck  (spiram_sck),
    .cs_n (spiram_csn[0]),
    .sio  (spi_psram_sdio)
  );

  pulldown(spi_sdi);

  // *************************************************************************************
  // Octal PSRAM (4x APMemory APS12808L, one byte lane each)
  // *************************************************************************************

`ifndef OCTRAM_ADDR_BITS
`define OCTRAM_ADDR_BITS 24 // full 16 MB per chip
`endif

  // The controller holds RESET# low for 1_000_000 cycles (20 ms) after reset. Simulations
  // shorten it with -DOCTRAM_RESET_CYCLES=500 (for a gate-level netlist: set at synthesis).
`ifndef OCTRAM_RESET_CYCLES
  initial $display("[TB] WARNING: OCTRAM_RESET_CYCLES not set, the PSRAM power-up reset takes 20 ms");
`endif

  genvar octram_i;
  generate
    for (octram_i = 0; octram_i < OCTRAM_CHIPS; octram_i = octram_i + 1) begin : gen_octram
`ifdef TECH_FPGA // core outputs. The pad ring drives the PSRAM nets itself.
      assign #1 octram_dq[octram_i*8 +: 8] = octram_dq_oe[octram_i] ? octram_dq_out[octram_i*8 +: 8] : 8'bz;
      assign #1 octram_dqs[octram_i] = octram_dqs_oe[octram_i] ? octram_dqs_out[octram_i] : 1'bz;
`endif
      aps12808l_model #(
        .ADDR_BITS (`OCTRAM_ADDR_BITS),
        .SEED      (octram_i + 1),
        .T_PU      (1_000_000) // 1 us instead of 150 us
      ) octram_inst (
        .CE_n    (octram_csn[octram_i]),
        .CLK     (octram_bus_clk[octram_i]),
        .RESET_n (octram_resetn),
        .DQ      (octram_dq[octram_i*8 +: 8]),
        .DQS     (octram_dqs[octram_i])
      );
    end
  endgenerate

  // set by the monitors below, used by the tests (stay 0 without monitors)
  integer conc_cpu_hits = 0;
  integer oct_rst_viol  = 0;
  reg     oct_idle_expected = 1'b1;
  reg     oct_trace = 1'b0;

  // AXI monitor on the octal PSRAM slave port
`ifdef TB_MONITORS
  wire        oct_arvalid = `DUT_CORE.axi_octram_arvalid;
  wire        oct_arready = `DUT_CORE.axi_octram_arready;
  wire  [7:0] oct_arlen   = `DUT_CORE.axi_octram_arlen;
  wire        oct_awvalid = `DUT_CORE.axi_octram_awvalid;
  wire        oct_awready = `DUT_CORE.axi_octram_awready;
  wire  [7:0] oct_awlen   = `DUT_CORE.axi_octram_awlen;
  wire        oct_rvalid  = `DUT_CORE.axi_octram_rvalid;
  wire        oct_rready  = `DUT_CORE.axi_octram_rready;
  wire        oct_rlast   = `DUT_CORE.axi_octram_rlast;
  wire        oct_wvalid  = `DUT_CORE.axi_octram_wvalid;
  wire        oct_wready  = `DUT_CORE.axi_octram_wready;
  wire        oct_wlast   = `DUT_CORE.axi_octram_wlast;
  wire        oct_bvalid  = `DUT_CORE.axi_octram_bvalid;
  wire        oct_bready  = `DUT_CORE.axi_octram_bready;

  integer oct_ar_cnt, oct_aw_cnt, oct_ar_maxlen, oct_aw_maxlen;
  integer oct_r_beats0, oct_w_beats0;  // beat counters at the start of the reset-during-DMA test
  integer oct_rready_gaps, oct_wvalid_gaps, oct_r_beats, oct_w_beats;
  integer oct_busy_cycles, oct_max_busy;
  reg     oct_r_active, oct_w_active;
  integer oct_r_outstanding, oct_w_outstanding;

  // statistics survive the reset-during-traffic test, transaction state does not
  initial begin
    oct_ar_cnt = 0; oct_aw_cnt = 0; oct_ar_maxlen = 0; oct_aw_maxlen = 0;
    oct_rready_gaps = 0; oct_wvalid_gaps = 0; oct_r_beats = 0; oct_w_beats = 0;
    oct_max_busy = 0;
  end
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      oct_r_active <= 0; oct_w_active <= 0;
      oct_r_outstanding <= 0; oct_w_outstanding <= 0;
      oct_busy_cycles <= 0;
    end else begin
      if (oct_arvalid && oct_arready) begin
        oct_ar_cnt <= oct_ar_cnt + 1;
        if (oct_arlen > oct_ar_maxlen) oct_ar_maxlen <= oct_arlen;
        oct_r_active <= 1;
      end
      if (oct_awvalid && oct_awready) begin
        oct_aw_cnt <= oct_aw_cnt + 1;
        if (oct_awlen > oct_aw_maxlen) oct_aw_maxlen <= oct_awlen;
        oct_w_active <= 1;
      end
      // master side stalls in the middle of a burst
      if (oct_rvalid && !oct_rready) oct_rready_gaps <= oct_rready_gaps + 1;
      if (oct_w_active && !oct_wvalid && oct_wready) oct_wvalid_gaps <= oct_wvalid_gaps + 1;
      if (oct_rvalid && oct_rready) begin
        oct_r_beats <= oct_r_beats + 1;
        if (oct_rlast) oct_r_active <= 0;
      end
      if (oct_wvalid && oct_wready) begin
        oct_w_beats <= oct_w_beats + 1;
        if (oct_wlast) oct_w_active <= 0;
      end
      // outstanding transactions (hang detection)
      oct_r_outstanding <= oct_r_outstanding + ((oct_arvalid && oct_arready) ? 1 : 0) - ((oct_rvalid && oct_rready && oct_rlast) ? 1 : 0);
      oct_w_outstanding <= oct_w_outstanding + ((oct_awvalid && oct_awready) ? 1 : 0) - ((oct_bvalid && oct_bready) ? 1 : 0);
      if ((oct_r_outstanding != 0) || (oct_w_outstanding != 0) || oct_arvalid || oct_awvalid) begin
        oct_busy_cycles <= oct_busy_cycles + 1;
        if (oct_busy_cycles > oct_max_busy) oct_max_busy <= oct_busy_cycles;
        if (oct_busy_cycles == OCT_HANG_CYCLES) begin
          $display("[TB] ERROR! Octal PSRAM AXI hang (no completion for %0d cycles)", OCT_HANG_CYCLES);
          octram_report;
          $finish;
        end
      end else begin
        oct_busy_cycles <= 0;
      end
    end
  end


  // CPU (JTAG) accesses to the PSRAM while the crypto DMA is busy
  always @(posedge clk) begin
    if (`CRYPTO_DMA_BUSY &&
        ((`DUT_CORE.axi_cpu_arvalid && `DUT_CORE.axi_cpu_arready && (`DUT_CORE.axi_cpu_araddr[31:26] == OCTRAM_BASE[31:26])) ||
         (`DUT_CORE.axi_cpu_awvalid && `DUT_CORE.axi_cpu_awready && (`DUT_CORE.axi_cpu_awaddr[31:26] == OCTRAM_BASE[31:26]))))
      conc_cpu_hits = conc_cpu_hits + 1;
  end

  // reset behaviour of the octal PSRAM port:
  // - while the system reset is active, no VALID on any AXI channel and all
  //   PSRAM chip selects high
  // - while oct_idle_expected is set (from power-on until the first PSRAM
  //   access of the test, and after the reset-during-traffic test until the
  //   next intended access), no AXI request may reach the PSRAM port
  // The crossbar uses the synchronous reset, so its VALID outputs drop at the
  // first clock edge in reset: the first reset cycle is not checked (the
  // controller is already held in its asynchronous reset then).
  wire oct_any_valid = oct_arvalid | oct_awvalid | oct_wvalid | oct_rvalid | oct_bvalid;
  reg  oct_in_reset = 1'b0;
  always @(posedge clk) begin
    oct_in_reset <= (`DUT_CORE.resetn_async !== 1'b1);
    if ((`DUT_CORE.resetn_async !== 1'b1) && oct_in_reset) begin
      if ((oct_any_valid !== 1'b0) || (octram_csn !== {OCTRAM_CHIPS{1'b1}})) begin
        if (oct_rst_viol < OCT_MAX_ERR_PRINT)
          $display("[TB] ERROR! %0t: OCTRAM activity during reset (ar %b aw %b w %b r %b b %b, csn %b)",
                   $time, oct_arvalid, oct_awvalid, oct_wvalid, oct_rvalid, oct_bvalid, octram_csn);
        oct_rst_viol = oct_rst_viol + 1;
      end
    end else if ((`DUT_CORE.resetn_async === 1'b1) && oct_idle_expected && (oct_any_valid !== 1'b0)) begin
      if (oct_rst_viol < OCT_MAX_ERR_PRINT)
        $display("[TB] ERROR! %0t: OCTRAM AXI activity after reset without a request (ar %b aw %b w %b r %b b %b)",
                 $time, oct_arvalid, oct_awvalid, oct_wvalid, oct_rvalid, oct_bvalid);
      oct_rst_viol = oct_rst_viol + 1;
    end
  end

  // handshake trace on the octal PSRAM port (enabled around single tests)
  always @(posedge clk) begin
    if (oct_trace) begin
      if (oct_arvalid && oct_arready)
        $display("[OCT %0t] AR id %0d addr 0x%08h len %0d", $time, `DUT_CORE.axi_octram_arid, `DUT_CORE.axi_octram_araddr, oct_arlen + 1);
      if (oct_awvalid && oct_awready)
        $display("[OCT %0t] AW id %0d addr 0x%08h len %0d", $time, `DUT_CORE.axi_octram_awid, `DUT_CORE.axi_octram_awaddr, oct_awlen + 1);
      if (oct_rvalid && oct_rready)
        $display("[OCT %0t] R  id %0d data 0x%08h resp %0d last %0d", $time, `DUT_CORE.axi_octram_rid, `DUT_CORE.axi_octram_rdata, `DUT_CORE.axi_octram_rresp, oct_rlast);
      if (oct_wvalid && oct_wready)
        $display("[OCT %0t] W  data 0x%08h strb %h last %0d", $time, `DUT_CORE.axi_octram_wdata, `DUT_CORE.axi_octram_wstrb, oct_wlast);
      if (oct_bvalid && oct_bready)
        $display("[OCT %0t] B  id %0d resp %0d", $time, `DUT_CORE.axi_octram_bid, `DUT_CORE.axi_octram_bresp);
    end
  end

`endif

  task octram_report;
    integer err;
    begin
      err = gen_octram[0].octram_inst.error_count + gen_octram[1].octram_inst.error_count +
            gen_octram[2].octram_inst.error_count + gen_octram[3].octram_inst.error_count;
`ifdef TB_MONITORS
      $display("[TB] OCTRAM AXI: AR %0d (max len %0d), AW %0d (max len %0d), R beats %0d, W beats %0d",
               oct_ar_cnt, oct_ar_maxlen + 1, oct_aw_cnt, oct_aw_maxlen + 1, oct_r_beats, oct_w_beats);
      $display("[TB] OCTRAM AXI: RVALID&!RREADY cycles %0d, WVALID gaps in burst %0d, longest busy %0d cycles",
               oct_rready_gaps, oct_wvalid_gaps, oct_max_busy);
`endif
      $display("[TB] OCTRAM model: reads %0d writes %0d MR writes %0d unknown cmds %0d, errors %0d",
               gen_octram[0].octram_inst.read_count, gen_octram[0].octram_inst.write_count,
               gen_octram[0].octram_inst.mr_write_count, gen_octram[0].octram_inst.unknown_cmd_count, err);
      if (err != 0) begin
        $display("[TB] ERROR! Octal PSRAM model reported %0d protocol errors", err);
        octram_test_errors = octram_test_errors + err;
      end
    end
  endtask

  // *************************************************************************************
  // UART
  // *************************************************************************************

  wire [7:0] uart_txd_data;
  reg  [7:0] uart_rxd_data;
  wire uart_txd_valid, uart_rxd_busy;
  reg  uart_rxd_valid;

  // transmitter - testing CPU RXD
  uart_rtx_transmitter #(
    .CLOCK_FREQ (50000000),
    .BAUD_RATE  (19200)
  ) uart_rtx_transmitter_inst (
    .clk     (clk),
    .nrst    (rstn),
    .data_in (uart_rxd_data),
    .valid   (uart_rxd_valid),
    .tx      (uart_rxd),
    .busy    (uart_rxd_busy)
  );

  // receiver - testing CPU TXD
  uart_rtx_receiver #(
    .CLOCK_FREQ (50000000),
    .BAUD_RATE  (19200)
  ) uart_rtx_receiver_inst (
    .clk_i   (clk),
    .txd_i   (uart_txd),
    .data_o  (uart_txd_data),
    .valid_o (uart_txd_valid)
  );

  // UART RX char logging
  reg [7:0] uart_line_log [0:63];
  integer uart_line_pnt;

  always @(posedge clk or negedge rstn) begin
    if (rstn == 1'b0) begin
     uart_line_pnt <= 0;
    end else if (uart_txd_valid == 1'b1) begin
      if ((uart_txd_data >= 32) && (uart_txd_data <= 127)) begin // printable?
        if (uart_line_pnt == 63) begin
          uart_line_pnt <= 0;
        end
        uart_line_log[uart_line_pnt] <= uart_txd_data;
        uart_line_pnt <= uart_line_pnt + 1;
      end else if ((uart_txd_data == 10) || (uart_txd_data == 13)) begin // line ending?
        uart_line_pnt <= 0;
      end
    end
  end

  // *************************************************************************************
  // Camera model
  // *************************************************************************************
  bfm_imager #(
    .enable_test_pattern(1)
    //.test_image0("./stimulus/raw0.hex"),
    //.enable_test_pattern(0)    
  ) bfm_imager_inst (
	  .i_clk(bfm_imager_clk),
    .i_rst(~rstn),
    .o_cam_pixel_clock(pixel_clock),
    .o_cam_frame_valid(frame_valid),
    .o_cam_line_valid(line_valid),
    .o_cam_pixel_data(pixel_data)
  );

  // *************************************************************************************
  // BH sensor model
  // *************************************************************************************

  initial begin
    sac2owas_load();
  end

  wire bh_uart_busy, bh_uart_tx;
  reg [2:0] bh_sensor_fsm;
  reg [15:0] bh_sensor_idx;
  reg bh_uart_valid;
  reg bh_uart_done;

  always @(posedge clk or negedge rstn) begin
    if (rstn == 1'b0) begin
      bh_sensor_fsm <= 3'b000;
      bh_sensor_idx <= 16'b000;
      bh_uart_valid <= 1'b0;
      bh_uart_done  <= 1'b0;
    end else begin
      bh_uart_valid <= 1'b0;
      bh_uart_done  <= ~bh_uart_busy;
      case (bh_sensor_fsm)

        // wait for sensor interface to get ready
        3'b000: begin
          if (bh_cts == 1'b1) begin
            bh_sensor_fsm <= 3'b001;
          end
        end

        // trigger UART
        3'b001: begin
          bh_uart_valid <= 1'b1;
          bh_sensor_fsm <= 3'b010;
        end

        // dummy cycle
        3'b010: begin
          bh_sensor_fsm <= 3'b011;
        end

        // dummy cycle
        3'b011: begin
          bh_sensor_fsm <= 3'b100;
        end

        // wait for UART
        3'b100: begin
          if ((bh_uart_busy == 1'b0) && (bh_uart_done == 1'b1)) begin
            bh_sensor_fsm <= 3'b101;
          end
        end

        // all done?
        3'b101: begin
          if (bh_sensor_idx < SAC2OWAS_BYTE_COUNT) begin
            bh_sensor_idx <= bh_sensor_idx + 1;
            bh_sensor_fsm <= 3'b001;
          end else begin
            bh_sensor_fsm <= 3'b101;
          end
        end

      endcase
    end
  end

  uart_rtx_transmitter #(
    .CLOCK_FREQ (50000000),
    .BAUD_RATE  (100000)
  ) bh_sensor_tx (
    .clk     (clk),
    .nrst    (rstn),
    .data_in (sac2owas_bytes[bh_sensor_idx]),
    .valid   (bh_uart_valid),
    .tx      (bh_uart_tx),
    .busy    (bh_uart_busy)
  );

  assign bh_rxd = {bh_uart_tx, bh_uart_tx};

  // *************************************************************************************
  // Stimulus / testbench control
  // *************************************************************************************

  reg [31:0] jtag_rdata;
  reg [31:0] tmp_data[3:0];

  // octal PSRAM DMA test helpers

  function [31:0] octram_pattern;
    input [7:0] k;
    octram_pattern = {k ^ 8'hA5, k, 8'h5A ^ k, ~k};
  endfunction

  // start a plain copy (CTRL.BYPASS) of <blocks> x 16 bytes by the crypto core DMA, via JTAG
  task crypto_dma_start;
    input [31:0] src;
    input [31:0] dst;
    input [31:0] blocks;
  begin
    jtag_riscv_memory_wr(CRYPTO_CTRL,       CRYPTO_CTRL_BYPASS);
    jtag_riscv_memory_wr(CRYPTO_SRC_ADDR,   src);
    jtag_riscv_memory_wr(CRYPTO_DST_ADDR,   dst);
    jtag_riscv_memory_wr(CRYPTO_DMA_BLOCKS, blocks);
    jtag_riscv_memory_wr(CRYPTO_GO,         32'h1);
  end
  endtask

  // wait for the DMA started by crypto_dma_start (src/dst only for the messages).
  // Not done after DMA_POLLS polls or done with error counts as an error
  task crypto_dma_wait;
    input [31:0] src;
    input [31:0] dst;
    reg   [31:0] status;
    integer      polls;
  begin
    status = 32'h0;
    polls  = 0;
    while ((status[DMA_ST_DONE] == 1'b0) && (polls < DMA_POLLS)) begin
      jtag_riscv_memory_rd(CRYPTO_DMA_STATUS, status);
      polls = polls + 1;
    end
    if (status[DMA_ST_DONE] == 1'b0) begin
      $display("[TB] ERROR! Crypto DMA 0x%08h -> 0x%08h did not finish", src, dst);
`ifdef TB_MONITORS
`ifndef GL_cryptoCore_inst
      $display("[TB]   dmactrl state %0d, adapter state %0d, dma_rd axi %0d axis %0d, dma_wr state %0d",
               `DUT_CORE.cryptoCore_inst.u_cryptoDmaCtrl.state,
               `DUT_CORE.cryptoCore_inst.u_aesStreamAdapter.state,
               `DUT_CORE.cryptoCore_inst.u_axi_dma.axi_dma_rd_inst.axi_state_reg,
               `DUT_CORE.cryptoCore_inst.u_axi_dma.axi_dma_rd_inst.axis_state_reg,
               `DUT_CORE.cryptoCore_inst.u_axi_dma.axi_dma_wr_inst.state_reg);
`endif
      $display("[TB]   crypto AXI ar %b/%b r %b/%b aw %b/%b w %b/%b b %b/%b",
               `DUT_CORE.cryptoCore_inst.m_axi_arvalid, `DUT_CORE.cryptoCore_inst.m_axi_arready,
               `DUT_CORE.cryptoCore_inst.m_axi_rvalid,  `DUT_CORE.cryptoCore_inst.m_axi_rready,
               `DUT_CORE.cryptoCore_inst.m_axi_awvalid, `DUT_CORE.cryptoCore_inst.m_axi_awready,
               `DUT_CORE.cryptoCore_inst.m_axi_wvalid,  `DUT_CORE.cryptoCore_inst.m_axi_wready,
               `DUT_CORE.cryptoCore_inst.m_axi_bvalid,  `DUT_CORE.cryptoCore_inst.m_axi_bready);
`endif
      octram_test_errors = octram_test_errors + 1;
    end else if (status[DMA_ST_ERROR]) begin
      $display("[TB] ERROR! Crypto DMA 0x%08h -> 0x%08h reported an error", src, dst);
      octram_test_errors = octram_test_errors + 1;
    end
  end
  endtask

  task crypto_dma_copy;
    input [31:0] src;
    input [31:0] dst;
    input [31:0] blocks;
  begin
    crypto_dma_start(src, dst, blocks);
    crypto_dma_wait(src, dst);
  end
  endtask

  // read a word over JTAG and compare it, mismatches count as octal PSRAM test errors
  task octram_check;
    input [8*24-1:0] what; // memory name for the message
    input [31:0]     addr;
    input [31:0]     expected;
    reg   [31:0]     data;
  begin
    jtag_riscv_memory_rd(addr, data);
    if (data !== expected) begin
      $display("[TB] ERROR! %0s 0x%08h = 0x%08h, expected 0x%08h", what, addr, data, expected);
      octram_test_errors = octram_test_errors + 1;
    end
  end
  endtask

  // write octram_pattern(pat + k) to addr + k*stride, k = 0..count-1, over JTAG
  task octram_fill;
    input [31:0] addr;
    input integer count;
    input integer stride;
    input integer pat;
    integer k;
  begin
    for (k = 0; k < count; k = k + 1)
      jtag_riscv_memory_wr(addr + stride*k, octram_pattern(pat + k));
  end
  endtask

  // read back what octram_fill wrote with the same arguments and compare
  task octram_verify;
    input [8*24-1:0] what;
    input [31:0]     addr;
    input integer    count;
    input integer    stride;
    input integer    pat;
    integer k;
  begin
    for (k = 0; k < count; k = k + 1)
      octram_check(what, addr + stride*k, octram_pattern(pat + k));
  end
  endtask

  // reset the JTAG TAP and the core, then halt the CPU (debug mode)
  task jtag_reset_and_halt;
  begin
    jtag_tap_reset;
    #1000
    jtag_riscv_reset;
    #1000
    jtag_riscv_halt;
    #1000;
  end
  endtask

  initial begin
    tck <= 1'b0;
    tdi <= 1'b0;
    tms <= 1'b0;

    // -------------------------------------------------------
    // Core reset & halt (enter debug mode)
    // -------------------------------------------------------

    jtag_reset_and_halt;

    // -------------------------------------------------------
    // System reset controller
    // -------------------------------------------------------
  
    $display("[TB] JTAG RESET_CTRL access tests (reset whole system)...");
  
    jtag_riscv_memory_wr(32'hFFEB0000, 32'h0000FFFF);
    jtag_riscv_memory_rd(32'hFFEB0000, jtag_rdata);
    if (jtag_rdata != 32'h0000FFFF) begin
      $display("[TB] ERROR! RESET_CTRL access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    
    jtag_riscv_memory_wr(32'hFFEB0000, 32'h00000000);
    jtag_riscv_memory_rd(32'hFFEB0000, jtag_rdata);
    if (jtag_rdata != 32'h00000000) begin
      $display("[TB] ERROR! RESET_CTRL access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    #1000

    // -------------------------------------------------------
    // SRAM test via JTAG
    // -------------------------------------------------------

    $display("[TB] JTAG memory access tests (SRAM 0+1)...");

    // SRAM 0
    jtag_riscv_memory_wr(32'h00000000, 32'hFEEDCAFE);
    jtag_riscv_memory_wr(32'h00000004, 32'h11223344);
    jtag_riscv_memory_wr(32'h00000008, 32'h1234CAFE);
    jtag_riscv_memory_wr(32'h0000000C, 32'h01020304);

    // SRAM 1
    jtag_riscv_memory_wr(32'h80000000, 32'h55667788);
    jtag_riscv_memory_wr(32'h80000100, 32'hABCD5678);
    jtag_riscv_memory_wr(32'h80000200, 32'hA1B2C3D4);
    jtag_riscv_memory_wr(32'h80000300, 32'hEFEFEFEF);

    // SRAM 0
    jtag_riscv_memory_rd(32'h00000000, jtag_rdata);
    if (jtag_rdata != 32'hFEEDCAFE) begin
      $display("[TB] ERROR! SRAM0 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h00000004, jtag_rdata);
    if (jtag_rdata != 32'h11223344) begin
      $display("[TB] ERROR! SRAM0 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h00000008, jtag_rdata);
    if (jtag_rdata != 32'h1234CAFE) begin
      $display("[TB] ERROR! SRAM0 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h0000000C, jtag_rdata);
    if (jtag_rdata != 32'h01020304) begin
      $display("[TB] ERROR! SRAM0 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end

    // SRAM 1
    jtag_riscv_memory_rd(32'h80000000, jtag_rdata);
    if (jtag_rdata != 32'h55667788) begin
      $display("[TB] ERROR! SRAM1 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h80000100, jtag_rdata);
    if (jtag_rdata != 32'hABCD5678) begin
      $display("[TB] ERROR! SRAM1 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h80000200, jtag_rdata);
    if (jtag_rdata != 32'hA1B2C3D4) begin
      $display("[TB] ERROR! SRAM1 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    jtag_riscv_memory_rd(32'h80000300, jtag_rdata);
    if (jtag_rdata != 32'hEFEFEFEF) begin
      $display("[TB] ERROR! SRAM1 access test returned incorrect data (0x%08h)!", jtag_rdata);
    end
    #1000

    // -------------------------------------------------------
    // IMS SPI-RAM Controller
    // -------------------------------------------------------
    $display("[TB] SPIRAM: Setup...");
    jtag_riscv_memory_wr(32'hF2000000, 32'h02030203);
    jtag_riscv_memory_wr(32'hF2000004, 32'h00996600);
    jtag_rdata = 32'hffffffff;
    while (jtag_rdata[4] == 1'b0) begin // busy?
      jtag_riscv_memory_rd(32'hF2000000, jtag_rdata);
    end
    $display("[TB] SPIRAM: Access check...");
    jtag_riscv_memory_wr(32'h10000000, 32'h12345678);
    jtag_riscv_memory_wr(32'h10000004, 32'habed4567);
    jtag_riscv_memory_wr(32'h10000008, 32'h7289bfed);
    jtag_riscv_memory_wr(32'h1000000C, 32'h01bed765);
    jtag_riscv_memory_rd(32'h10000000, tmp_data[0]);
    jtag_riscv_memory_rd(32'h10000004, tmp_data[1]);
    jtag_riscv_memory_rd(32'h10000008, tmp_data[2]);
    jtag_riscv_memory_rd(32'h1000000C, tmp_data[3]);
    if ((tmp_data[0] != 32'h12345678) ||
        (tmp_data[1] != 32'habed4567) ||
        (tmp_data[2] != 32'h7289bfed) ||
        (tmp_data[3] != 32'h01bed765)) begin
      $display("[TB] SPIRAM: Data error!");
    end else begin
      $display("[TB] SPIRAM: Tests OK");
    end
    #1000



`ifndef TB_SKIP_DCV // sim_octram.mk skips the DCV test (20 ms wait) unless DCV=1
  //============================================================================================================================
   // -------------------------------------------------------
   // DC-Vision / Camera Interface Tests
   // -------------------------------------------------------
   $display("[TB] DCV: Starting imager...");
  jtag_riscv_memory_wr(32'hF4000000+20'h00004, 32'h00000001); // enable
  jtag_riscv_memory_wr(32'hF4000020, 32'h00000000); // Puffer 0
  jtag_riscv_memory_wr(32'hF4000024, 32'h00100000); // Puffer 1
  jtag_riscv_memory_wr(32'hF4000028, 32'h00200000); // Puffer 2
  jtag_riscv_memory_wr(32'hF400002C, 32'h00300000); // Puffer 3


   bfm_imager_inst.start_imager();


    // SRAM 0
    jtag_riscv_memory_wr(32'h00000000, 32'h01234567);
    jtag_riscv_memory_wr(32'h00000004, 32'h11223344);
    jtag_riscv_memory_wr(32'h00000008, 32'h55667788);
    jtag_riscv_memory_wr(32'h0000000C, 32'h99AABBCC);
    jtag_riscv_memory_wr(32'h00000010, 32'h11111111);
    jtag_riscv_memory_wr(32'h00000014, 32'h22222222);
    jtag_riscv_memory_wr(32'h00000018, 32'h22222223);
    jtag_riscv_memory_wr(32'h0000001C, 32'h22222224);
    jtag_riscv_memory_wr(32'h00000020, 32'h1a1a0021);
    jtag_riscv_memory_wr(32'h00000030, 32'h1a1a0031);
    jtag_riscv_memory_wr(32'h00000040, 32'h1a1a0041);
    jtag_riscv_memory_wr(32'h00000050, 32'h1a1a0051);
    jtag_riscv_memory_wr(32'h00000060, 32'h1a1a0061);
    jtag_riscv_memory_wr(32'h00000070, 32'h1a1a0071);
    jtag_riscv_memory_wr(32'h00000080, 32'h1a1a0081);


   #10000
//   $display("[TB] DCV: Starting read-out of image data...");
   jtag_riscv_memory_wr(32'hF4000000+20'h00030, 32'h00000000); // set read base address
   jtag_riscv_memory_wr(32'hF4000000+20'h00034, 32'd2048); // trigger read of 4096 words from read base address
   #20000000
  //============================================================================================================================
`endif


    // -------------------------------------------------------
    // RUB Crypto Core Tests
    // -------------------------------------------------------
    $display("[TB] Crypto: Setup dummy data...");
    jtag_riscv_memory_wr(32'h00000000, 32'h86429753);
    jtag_riscv_memory_wr(32'h00000004, 32'hacdcacdc);
    jtag_riscv_memory_wr(32'h00000008, 32'h11223344);
    jtag_riscv_memory_wr(32'h0000000c, 32'h56565656);
    $display("[TB] Crypto: Configuring DMA transfer...");
    crypto_dma_start(SRAM0_BASE, SRAM1_BASE, 1); // plain copy of 1 block (16 bytes)
    $display("[TB] Crypto: Waiting for DMA...");
    jtag_rdata = 32'h00000000;
    while (jtag_rdata[DMA_ST_DONE] == 1'b0) begin
      jtag_riscv_memory_rd(CRYPTO_DMA_STATUS, jtag_rdata);
    end
    if (jtag_rdata[DMA_ST_ERROR]) begin
      $display("[TB] ERROR! Crypto DMA reported an error (DMA_STATUS = 0x%08h)!", jtag_rdata);
    end
    $display("[TB] Crypto: DMA done. Checking destination...");
    jtag_riscv_memory_rd(32'h80000000, tmp_data[0]);
    jtag_riscv_memory_rd(32'h80000004, tmp_data[1]);
    jtag_riscv_memory_rd(32'h80000008, tmp_data[2]);
    jtag_riscv_memory_rd(32'h8000000C, tmp_data[3]);
    if ((tmp_data[0] != 32'h86429753) ||
        (tmp_data[1] != 32'hacdcacdc) ||
        (tmp_data[2] != 32'h11223344) ||
        (tmp_data[3] != 32'h56565656)) begin
      $display("[TB] ERROR! Crypto destination data incorrect!");
    end else begin
      $display("[TB] Crypto: Tests OK");
    end
    #1000

    // -------------------------------------------------------
    // Octal PSRAM: JTAG access + crypto DMA as second AXI master
    // (pin-level checks, the internal monitor checks need TB_MONITORS)
    // -------------------------------------------------------
`ifdef TB_MONITORS
    if (oct_rst_viol != 0) begin
      $display("[TB] ERROR! OCTRAM: %0d reset/idle violations before the first PSRAM access", oct_rst_viol);
      octram_test_errors = octram_test_errors + 1;
    end else
      $display("[TB] OCTRAM: no PSRAM port activity during and after power-on reset");
`endif
    oct_idle_expected = 1'b0;
    $display("[TB] OCTRAM: JTAG write/read...");
    octram_fill(OCTRAM_BASE, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_JTAG);
    octram_verify("OCTRAM", OCTRAM_BASE, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_JTAG);

    $display("[TB] OCTRAM DMA: SRAM0 -> OCTRAM (%0d blocks)...", DMA_TEST_BLOCKS);
    octram_fill(SRAM0_BUF, DMA_TEST_WORDS, BYTES_PER_WORD, PAT_DMA);
    crypto_dma_copy(SRAM0_BUF, OCT_DMA, DMA_TEST_BLOCKS);
    octram_verify("OCTRAM", OCT_DMA, DMA_TEST_WORDS, BYTES_PER_WORD, PAT_DMA);

    $display("[TB] OCTRAM DMA: OCTRAM -> SRAM1 (%0d blocks)...", DMA_TEST_BLOCKS);
    crypto_dma_copy(OCT_DMA, SRAM1_BUF, DMA_TEST_BLOCKS);
    octram_verify("SRAM1", SRAM1_BUF, DMA_TEST_WORDS, BYTES_PER_WORD, PAT_DMA);

    // OCTRAM -> OCTRAM: source just below a 4 KB boundary, so the DMA reads
    // a 15-beat and a 1-beat burst (hung on the Nexys board)
    $display("[TB] OCTRAM DMA: OCTRAM 0x%08h -> OCTRAM 0x%08h (%0d blocks)...", OCT_P2P_SRC, OCT_P2P_DST, DMA_TEST_BLOCKS);
    octram_fill(OCT_P2P_SRC, DMA_TEST_WORDS, BYTES_PER_WORD, PAT_P2P);
    oct_trace = 1'b1;
    crypto_dma_copy(OCT_P2P_SRC, OCT_P2P_DST, DMA_TEST_BLOCKS);
    oct_trace = 1'b0;
    octram_verify("OCTRAM", OCT_P2P_DST, DMA_TEST_WORDS, BYTES_PER_WORD, PAT_P2P);

    // Smoke test: JTAG PSRAM accesses during a 4 KB OCTRAM -> OCTRAM DMA (JTAG is slow,
    // usually only the first access overlaps). The full CPU + DMA concurrency coverage
    // is in the octram_test firmware.
    $display("[TB] OCTRAM DMA: OCTRAM -> OCTRAM (%0d blocks) with concurrent JTAG PSRAM accesses...", CONC_BLOCKS);
    octram_fill(OCT_CONC_SRC, CONC_CHECKS, CONC_CHECK_STRIDE, PAT_CONC);
    conc_cpu_hits = 0;
    crypto_dma_start(OCT_CONC_SRC, OCT_CONC_DST, CONC_BLOCKS);
    octram_fill(OCT_CONC_CPU, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_CONC_CPU);
    octram_verify("concurrent OCTRAM", OCT_CONC_CPU, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_CONC_CPU);
    crypto_dma_wait(OCT_CONC_SRC, OCT_CONC_DST);
`ifdef TB_MONITORS
    $display("[TB] OCTRAM DMA: %0d JTAG PSRAM accesses while the DMA was busy", conc_cpu_hits);
    if (conc_cpu_hits == 0) begin
      $display("[TB] ERROR! no JTAG PSRAM access overlapped the DMA");
      octram_test_errors = octram_test_errors + 1;
    end
`endif
    octram_verify("OCTRAM", OCT_CONC_DST, CONC_CHECKS, CONC_CHECK_STRIDE, PAT_CONC);

    // System reset in the middle of a 4 KB OCTRAM -> OCTRAM DMA (read and
    // write bursts in flight): during reset the PSRAM port must be quiet and
    // all chip selects high, after reset no AXI request may appear on its own,
    // then the PSRAM must work again (new power-up sequence of the controller).
    $display("[TB] OCTRAM: system reset during DMA bursts...");
    crypto_dma_start(OCT_CONC_SRC, OCT_RST_DST, CONC_BLOCKS);
`ifdef TB_MONITORS
    // the controller runs one burst at a time: reset after a quarter of the
    // copy, in the middle of a read or write burst of the DMA
    oct_r_beats0 = oct_r_beats;
    oct_w_beats0 = oct_w_beats;
    rst_wait_cycles = 0;
    while (!(`CRYPTO_DMA_BUSY && (oct_r_beats > oct_r_beats0 + RST_AFTER_R_BEATS) &&
             ((oct_r_active && oct_rvalid) || (oct_w_active && oct_wvalid))) && (rst_wait_cycles < RST_WAIT_MAX)) begin
      @(posedge clk);
      rst_wait_cycles = rst_wait_cycles + 1;
    end
    if (!`CRYPTO_DMA_BUSY || !(oct_r_active || oct_w_active)) begin
      $display("[TB] ERROR! reset test: DMA not in the middle of a burst");
      octram_test_errors = octram_test_errors + 1;
    end
    $display("[TB] OCTRAM: asserting reset at %0t (%0s burst open, DMA R beats %0d, W beats %0d)", $time,
             oct_r_active ? "read" : "write", oct_r_beats - oct_r_beats0, oct_w_beats - oct_w_beats0);
`else
    repeat (RST_DELAY) @(posedge clk);
    $display("[TB] OCTRAM: asserting reset at %0t", $time);
`endif
    @(negedge clk);
    rstn = 1'b0;
    oct_idle_expected = 1'b1;
    repeat (RST_CYCLES) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;
    repeat (OCT_PWRUP_WAIT) @(posedge clk);
    jtag_reset_and_halt;
    // done may be set: the crypto boot controller runs its own (non-PSRAM)
    // boot DMA after every reset
    jtag_riscv_memory_rd(CRYPTO_DMA_STATUS, jtag_rdata);
    if (jtag_rdata[DMA_ST_BUSY] !== 1'b0) begin
      $display("[TB] ERROR! DMA_STATUS after reset 0x%08h, expected not busy", jtag_rdata);
      octram_test_errors = octram_test_errors + 1;
    end
    if (oct_rst_viol != 0) begin // stays 0 without TB_MONITORS
      $display("[TB] ERROR! OCTRAM: %0d reset/idle violations around the reset", oct_rst_viol);
      octram_test_errors = octram_test_errors + 1;
    end
    oct_idle_expected = 1'b0;
    // PSRAM works again: new JTAG round trip, new DMA (source rewritten,
    // retention across RESET# is not specified)
    octram_fill(OCT_CONC_SRC, CONC_CHECKS, CONC_CHECK_STRIDE, PAT_CONC);
    octram_fill(OCTRAM_BASE, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_RST);
    octram_verify("after reset OCTRAM", OCTRAM_BASE, OCT_JTAG_WORDS, BYTES_PER_WORD, PAT_RST);
    crypto_dma_copy(OCT_CONC_SRC, OCT_RST_DST, CONC_BLOCKS);
    octram_verify("after reset DMA OCTRAM", OCT_RST_DST, CONC_CHECKS, CONC_CHECK_STRIDE, PAT_CONC);

    octram_report;
    if (octram_test_errors == 0)
      $display("[TB] OCTRAM DMA: Tests OK");
    else
      $display("[TB] ERROR! OCTRAM DMA: %0d errors", octram_test_errors);
`ifdef TB_STOP_AFTER_DMA
    if (octram_test_errors == 0) $display("\n[TB] Simulation successful!");
    else                         $display("\n[TB] Simulation failed!");
    $finish;
`endif
    #1000

    // -------------------------------------------------------
    // B-Horizon / Sensor Interface Tests
    // -------------------------------------------------------
    $display("[TB] BH: Register access test...");
    jtag_riscv_memory_wr(32'hF3000000+16'h8008, 32'h00000003); // enable lowest two channels
    #1000

    // -------------------------------------------------------
    // Uni Heidelberg eFPGA / AI Tests
    // -------------------------------------------------------
    $display("[TB] TODO: UHD - Add your tests here...");
    #1000


    // -------------------------------------------------------
    // Reset core and run normal bootloader boot
    // -------------------------------------------------------
    jtag_riscv_reset;
    #100000

    // wait for bootloader checker to complete
    $display("[TB] Running bootloader...");
    #FW_TIMEOUT_NS;
    octram_report;
    $display("\n[TB] Simulation terminated (time out)!");
    $finish;
  end

  // *************************************************************************************
  // UART console (process bootloader and app input/output)
  // *************************************************************************************

  reg [3:0] uart_checker_state;
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      uart_checker_state <= 4'h0;
      uart_rxd_data      <= 8'h00;
      uart_rxd_valid     <= 1'b0;
    end else begin
      uart_rxd_valid <= 1'b0;
      case (uart_checker_state)

        // wait for auto-boot notifier
        4'h0: begin
          if ((uart_line_log[0] == "A") &&
              (uart_line_log[1] == "u") &&
              (uart_line_log[2] == "t") &&
              (uart_line_log[3] == "o") &&
              (uart_line_log[4] == "-") &&
              (uart_line_log[5] == "b") &&
              (uart_line_log[6] == "o") &&
              (uart_line_log[7] == "o") &&
              (uart_line_log[8] == "t")) begin
            uart_checker_state <= 4'h1;
          end
        end

        // send "any" command to abort auto-boot
        4'h1: begin
          uart_rxd_data      <= 8'h6C; // "l"
          uart_rxd_valid     <= 1'b1;
          uart_checker_state <= 4'h2;
        end

        // wait for abort notifier
        4'h2: begin
          if ((uart_line_log[0] == "A") &&
              (uart_line_log[1] == "b") &&
              (uart_line_log[2] == "o") &&
              (uart_line_log[3] == "r") &&
              (uart_line_log[4] == "t") &&
              (uart_line_log[5] == "e") &&
              (uart_line_log[6] == "d")) begin
            uart_checker_state <= 4'h3;
          end
        end

        // send "load from SPI" command
        4'h3: begin
          uart_rxd_data      <= 8'h6C; // "l"
          uart_rxd_valid     <= 1'b1;
          uart_checker_state <= 4'h4;
        end

        // wait for loading to complete
        4'h4: begin
          if ((uart_line_log[0]  == "L") &&
              (uart_line_log[1]  == "o") &&
              (uart_line_log[2]  == "a") &&
              (uart_line_log[3]  == "d") &&
              (uart_line_log[4]  == "i") &&
              (uart_line_log[5]  == "n") &&
              (uart_line_log[6]  == "g") &&
              (uart_line_log[7]  == " ") &&
              (uart_line_log[8]  == "f") &&
              (uart_line_log[9]  == "r") &&
              (uart_line_log[10] == "o") &&
              (uart_line_log[11] == "m") &&
              (uart_line_log[12] == " ") &&
              (uart_line_log[13] == "S") &&
              (uart_line_log[14] == "P") &&
              (uart_line_log[15] == "I") &&
              (uart_line_log[16] == " ") &&
              (uart_line_log[17] == "f") &&
              (uart_line_log[18] == "l") &&
              (uart_line_log[19] == "a") &&
              (uart_line_log[20] == "s") &&
              (uart_line_log[21] == "h") &&
              (uart_line_log[22] == " ") &&
              (uart_line_log[23] == "@") &&
              (uart_line_log[24] == "0") &&
              (uart_line_log[25] == "x") &&
              (uart_line_log[26] == "0") &&
              (uart_line_log[27] == "0") &&
              (uart_line_log[28] == "0") &&
              (uart_line_log[29] == "0") &&
              (uart_line_log[30] == "0") &&
              (uart_line_log[31] == "0") &&
              (uart_line_log[32] == "0") &&
              (uart_line_log[33] == "0") &&
              (uart_line_log[34] == ".") &&
              (uart_line_log[35] == ".") &&
              (uart_line_log[36] == ".") &&
              (uart_line_log[37] == " ") &&
              (uart_line_log[38] == "O") &&
              (uart_line_log[39] == "K")) begin
            uart_checker_state <= 4'h5;
          end
        end

        // send "execute" command
        4'h5: begin
          uart_rxd_data      <= 8'h65; // "e"
          uart_rxd_valid     <= 1'b1;
          uart_checker_state <= 4'h6;
        end

        // wait for executed program to terminate
        4'h6: begin
          // app (hello_world) prints "TEST PASS" / "TEST FAIL"
          if ((uart_line_log[0] == "T") &&
              (uart_line_log[1] == "E") &&
              (uart_line_log[2] == "S") &&
              (uart_line_log[3] == "T") &&
              (uart_line_log[4] == " ") &&
              (uart_line_log[5] == "P") &&
              (uart_line_log[6] == "A") &&
              (uart_line_log[7] == "S") &&
              (uart_line_log[8] == "S")) begin
            octram_report;
            if (octram_test_errors == 0) $display("\n[TB] Simulation successful!");
            else                         $display("\n[TB] Simulation failed! (%0d octal PSRAM errors)", octram_test_errors);
            $finish;
          end
          if ((uart_line_log[0] == "T") &&
              (uart_line_log[1] == "E") &&
              (uart_line_log[2] == "S") &&
              (uart_line_log[3] == "T") &&
              (uart_line_log[4] == " ") &&
              (uart_line_log[5] == "F") &&
              (uart_line_log[6] == "A") &&
              (uart_line_log[7] == "I") &&
              (uart_line_log[8] == "L")) begin
            octram_report;
            $display("\n[TB] Simulation failed!");
            $finish;
          end
        end

      endcase
    end
  end

endmodule
