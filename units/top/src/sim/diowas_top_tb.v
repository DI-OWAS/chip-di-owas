// DI-OWAS main testbench

`timescale 1 ns/100 ps // time-unit = 1 ns, precision = 100 ps

`define CORE_CLK_PERIOD 20  // CPU clock period
`define JTAG_CLK_PERIOD 200 // JTAG interface clock period

module diowas_top_tb;

  integer i;

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

  spi_rom #(
    .INIT_FILE   ("src/sim/boot_image.mem"),
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
  // Octal PSRAM
  // *************************************************************************************

  // [UHD] TODO

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

  wire bh_uart_busy, bh_uart_tx;
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

  initial begin
    tck <= 1'b0;
    tdi <= 1'b0;
    tms <= 1'b0;

    // -------------------------------------------------------
    // Core reset & halt (enter debug mode)
    // -------------------------------------------------------

    // reset JTAG tap controller
    jtag_tap_reset;
    #1000

    // reset core
    jtag_riscv_reset;
    #1000

    // halt CPU core
    jtag_riscv_halt;
    #1000

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


    // -------------------------------------------------------
    // RUB Crypto Core Tests
    // -------------------------------------------------------
    $display("[TB] Crypto: Setup dummy data...");
    jtag_riscv_memory_wr(32'h00000000, 32'h86429753);
    jtag_riscv_memory_wr(32'h00000004, 32'hacdcacdc);
    jtag_riscv_memory_wr(32'h00000008, 32'h11223344);
    jtag_riscv_memory_wr(32'h0000000c, 32'h56565656);
    $display("[TB] Crypto: Configuring DMA transfer...");
    jtag_riscv_memory_wr(32'hF5000000+8'h00, 32'h00000002); // CTRL: plain transfer
    jtag_riscv_memory_wr(32'hF5000000+8'h50, 32'h00000000); // SRC
    jtag_riscv_memory_wr(32'hF5000000+8'h54, 32'h80000000); // DST
    jtag_riscv_memory_wr(32'hF5000000+8'h58, 32'h80000001); // DAM_BLOCKS 1
    jtag_riscv_memory_wr(32'hF5000000+8'h5C, 32'h80000001); // start operation
    $display("[TB] Crypto: Waiting for DMA...");
    jtag_rdata = 32'h00000000;
    while (jtag_rdata[1] == 1'b0) begin // DMA not done?
      jtag_riscv_memory_rd(32'h80000300, jtag_rdata);
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
    #500_000_000;
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
          if ((uart_line_log[0]  == "P") &&
              (uart_line_log[1]  == "A") &&
              (uart_line_log[2]  == "S") &&
              (uart_line_log[3]  == "S")) begin
            $display("\n[TB] Simulation successful!");
            $finish;
          end
          if ((uart_line_log[0]  == "F") &&
              (uart_line_log[1]  == "A") &&
              (uart_line_log[2]  == "I") &&
              (uart_line_log[3]  == "L")) begin
            $display("\n[TB] Simulation failed!");
            $finish;
          end
        end

      endcase
    end
  end

endmodule
