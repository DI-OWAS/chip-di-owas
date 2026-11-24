// ***********************************************************
// The DI-OWAS Project
//
// Top module for the openlane ASIC flow
//
// (c) Copyright 2024 - 2025 DI-OWAS team
// (c) Copyright 2025 Uni Heidelberg (agruebl, UH2)
// ***********************************************************

`ifdef IHP_CMOS5L
  `define IHP_PREFIX sg13cmos5l
`else
  // the regular 7m process would be standard
  `define IHP_PREFIX sg13g2
`endif

module diowas_top_pads
(
`ifdef USE_POWER_PINS
  inout wire VDD,
  inout wire VSS,
  inout wire IOVDD,
  inout wire IOVSS,
`endif

  // global control
  inout wire clk_i_PAD,
  inout wire rstn_i_PAD,
 
  // jtag on-chip debugger interface
  inout wire jtag_tck_i_PAD,
  inout wire jtag_tdi_i_PAD,
  inout wire jtag_tdo_o_PAD,
  inout wire jtag_tms_i_PAD,

  // I2C interface
  inout wire twi_scl_PAD,
  inout wire twi_sda_PAD,
 
  // SPI host
  inout wire [1:0] spi_csn_o_PAD,
  inout wire       spi_sck_o_PAD,
  inout wire       spi_sdo_o_PAD,
  inout wire       spi_sdi_i_PAD,
  
  // heartbeat LED
  inout wire status_led_o_PAD,
 
  // uart0
  inout wire console_txd_o_PAD,
  inout wire console_rxd_i_PAD,
 
  // SPI PSRAM
  output        spiram_clk_o_PAD,
  output  [1:0] spiram_csn_o_PAD,
  input         spiram_sdi_i_PAD,
  output        spiram_sdo_o_PAD,

  // Octal PSRAM
  inout wire  [3:0] qspiram_bus_clk_o_PAD,
  inout wire  [3:0] qspiram_csn_o_PAD,
  inout wire        qspiram_resetn_o_PAD,
  inout wire  [3:0] qspiram_strobe_io_PAD,
  inout wire [31:0] qspiram_data_io_PAD,

  // DCV Camera Interface
  inout wire        cam_pixel_clk_i_PAD,
  inout wire        cam_frame_valid_i_PAD,
  inout wire        cam_line_valid_i_PAD,
  inout wire [11:0] cam_pixel_data_i_PAD,
  inout wire [15:0] cam_doutif_data_o_PAD,
  inout wire        cam_doutif_valid_o_PAD,
  inout wire        cam_doutif_first_o_PAD,
  inout wire        cam_doutif_clk_o_PAD,

  // BH Interface UARTs
  inout wire [1:0] bhif_rxd_i_PAD,
  inout wire       bhif_cts_o_PAD,
  
  // eFPGA user IOs
  inout wire [7:0] efpga_io_PAD,
  inout wire       efpga_sclk_i_PAD,
  inout wire       efpga_sdata_i_PAD
);

  wire clk_i_p2c;           // Pad to Core
  wire rstn_i_p2c;          // Pad to Core

  wire jtag_tck_i_p2c;      // Pad to Core
  wire jtag_tdi_i_p2c;      // Pad to Core
  wire jtag_tdo_o_c2p;      // Core to Pad
  wire jtag_tms_i_p2c;      // Pad to Core

  wire twi_scl_o_c2p;
  wire twi_scl_i_p2c;
  wire twi_sda_o_c2p;
  wire twi_sda_i_p2c;

  wire [1:0] spi_csn_o_c2p; // Core to Pad
  wire       spi_sck_o_c2p;
  wire       spi_sdo_o_c2p;
  wire       spi_sdi_i_p2c; // Pad to Core

  wire status_led_o_c2p;    // Core to Pad

  wire console_txd_o_c2p;   // Core to Pad
  wire console_rxd_i_p2c;   // Pad to Core

  // SPI PSRAM
  wire       spiram_clk_o_c2p;
  wire [1:0] spiram_csn_o_c2p;
  wire       spiram_sdi_i_p2c;
  wire       spiram_sdo_o_c2p;

  // Octal PSRAM
  wire  [3:0] qspiram_bus_clk_o_c2p;
  wire  [3:0] qspiram_csn_o_c2p;
  wire        qspiram_resetn_o_c2p;
  wire  [3:0] qspiram_strobe_i_p2c;
  wire  [3:0] qspiram_strobe_o_c2p;
  wire  [3:0] qspiram_strobe_oe_c2p; // 0 input, 1 output
  wire [31:0] qspiram_data_i_p2c;
  wire [31:0] qspiram_data_o_c2p;
  wire  [3:0] qspiram_data_oe_c2p; // 0 input, 1 output

  wire        cam_pixel_clk_i_p2c;     // Pad to Core
  wire        cam_frame_valid_i_p2c;
  wire        cam_line_valid_i_p2c;
  wire [11:0] cam_pixel_data_i_p2c;
  wire [15:0] cam_doutif_data_o_c2p;   // Core to Pad
  wire        cam_doutif_valid_o_c2p;
  wire        cam_doutif_first_o_c2p;
  wire        cam_doutif_clk_o_c2p;

  wire [1:0] bhif_rxd_i_p2c; // Pad to Core
  wire       bhif_cts_o_c2p; // Core to Pad

  wire [7:0] efpga_io_out_o_c2p;
  wire [7:0] efpga_io_oe_o_c2p;
  wire [7:0] efpga_io_in_i_p2c;

  wire       efpga_sclk_i_p2c;
  wire       efpga_sdata_i_p2c;


// macros for pad instances
`define VDD_PAD(base) base``_IOPadVdd
`define VSS_PAD(base) base``_IOPadVss
`define VDDIO_PAD(base) base``_IOPadIOVdd
`define VSSIO_PAD(base) base``_IOPadIOVss

`define IN_PAD(base) base``_IOPadIn
`define OUT_PAD16(base) base``_IOPadOut16mA
`define OUT_PAD30(base) base``_IOPadOut30mA
`define INOUT_PAD16(base) base``_IOPadInOut16mA
`define INOUT_PAD30(base) base``_IOPadInOut30mA

//////////   Power/Ground Supply Pads 	//////////
	////////// EAST
	(* keep *)
	`VDD_PAD(`IHP_PREFIX) IOPadVdd_east[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );
	(* keep *)

	(* keep *)
	`VSS_PAD(`IHP_PREFIX) IOPadVss_east[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VSSIO_PAD(`IHP_PREFIX) IOPadIOVss_east[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );
	(* keep *)

	(* keep *)
	`VDDIO_PAD(`IHP_PREFIX) IOPadIOVdd_east[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );


	////////// SOUTH
	(* keep *)
	`VDD_PAD(`IHP_PREFIX) IOPadVdd_south[3:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VSS_PAD(`IHP_PREFIX) IOPadVss_south[3:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VSSIO_PAD(`IHP_PREFIX) IOPadIOVss_south[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VDDIO_PAD(`IHP_PREFIX) IOPadIOVdd_south[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );


	////////// NORTH
	(* keep *)
	`VDD_PAD(`IHP_PREFIX) IOPadVdd_north[4:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );
	(* keep *)

	(* keep *)
	`VSS_PAD(`IHP_PREFIX) IOPadVss_north[4:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VSSIO_PAD(`IHP_PREFIX) IOPadIOVss_north[4:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VDDIO_PAD(`IHP_PREFIX) IOPadIOVdd_north[4:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );


	////////// WEST
	(* keep *)
	`VDD_PAD(`IHP_PREFIX) IOPadVdd_west[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );
	(* keep *)
	`VSS_PAD(`IHP_PREFIX) IOPadVss_west[5:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VSSIO_PAD(`IHP_PREFIX) IOPadIOVss_west[6:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );

	(* keep *)
	`VDDIO_PAD(`IHP_PREFIX) IOPadIOVdd_west[6:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD)
        `endif
    );


//////////   Signal I/O Pads 	//////////
  // jtag on-chip debugger interface
	`IN_PAD(`IHP_PREFIX) IOPad_io_tck (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (jtag_tck_i_p2c),
		.pad (jtag_tck_i_PAD)
	);

	`IN_PAD(`IHP_PREFIX) IOPad_io_tdi (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (jtag_tdi_i_p2c),
		.pad (jtag_tdi_i_PAD)
	);

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_tdo (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (jtag_tdo_o_c2p),
        .pad (jtag_tdo_o_PAD)
    );

	`IN_PAD(`IHP_PREFIX) IOPad_io_tms (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (jtag_tms_i_p2c),
		.pad (jtag_tms_i_PAD)
	);

  // I2C host
  	`INOUT_PAD16(`IHP_PREFIX) IOPad_io_twi_scl (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(twi_scl_PAD),
		.c2p(1'b0),
		.c2p_en(~twi_scl_o_c2p),
		.p2c(twi_scl_i_p2c)
	);

  	`INOUT_PAD16(`IHP_PREFIX) IOPad_io_twi_sda (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(twi_sda_PAD),
		.c2p(1'b0),
		.c2p_en(~twi_sda_o_c2p),
		.p2c(twi_sda_i_p2c)
	);


  // Core complex SPI host
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spi_csn[1:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (spi_csn_o_c2p),
        .pad (spi_csn_o_PAD)
    );

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spi_sck (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (spi_sck_o_c2p),
        .pad (spi_sck_o_PAD)
    );

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spi_sdo (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (spi_sdo_o_c2p),
        .pad (spi_sdo_o_PAD)
    );

	`IN_PAD(`IHP_PREFIX) IOPad_io_spi_sdi (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (spi_sdi_i_p2c),
		.pad (spi_sdi_i_PAD)
	);

  // gpio
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_status_led (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (status_led_o_c2p),
        .pad (status_led_o_PAD)
    );

  // uart0
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_console_txd (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
        .c2p (console_txd_o_c2p),
        .pad (console_txd_o_PAD)
    );

	`IN_PAD(`IHP_PREFIX) IOPad_io_console_rxd (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (console_rxd_i_p2c),
		.pad (console_rxd_i_PAD)
	);

  // SPI RAM
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spiram_clk (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (spiram_clk_o_c2p),
		.pad (spiram_clk_o_PAD)
	);

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spiram_sdo (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (spiram_sdo_o_c2p),
		.pad (spiram_sdo_o_PAD)
	);

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_spiram_csn[1:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (spiram_csn_o_c2p),
		.pad (spiram_csn_o_PAD)
	);

	`IN_PAD(`IHP_PREFIX) IOPad_io_spiram_sdi (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(spiram_sdi_i_PAD),
		.p2c(spiram_sdi_i_p2c)
	);
    
  // QSPI PSRAM
	`OUT_PAD30(`IHP_PREFIX) IOPad_o_qspiram_bus_clk[3:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (qspiram_bus_clk_o_c2p),
		.pad (qspiram_bus_clk_o_PAD)
	);

	`OUT_PAD30(`IHP_PREFIX) IOPad_o_qspiram_csn[3:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (qspiram_csn_o_c2p),
		.pad (qspiram_csn_o_PAD)
	);

	`OUT_PAD30(`IHP_PREFIX) IOPad_o_qspiram_resetn (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (qspiram_resetn_o_c2p),
		.pad (qspiram_resetn_o_PAD)
	);

	`INOUT_PAD30(`IHP_PREFIX) IOPad_io_qspiram_strobe[3:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(qspiram_strobe_io_PAD),
		.c2p(qspiram_strobe_o_c2p),
		.c2p_en(qspiram_strobe_oe_c2p),
		.p2c(qspiram_strobe_i_p2c)
	);

	`INOUT_PAD30(`IHP_PREFIX) IOPad_io_qspiram_data[31:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(qspiram_data_io_PAD),
		.c2p(qspiram_data_o_c2p),
		.c2p_en({ {8{qspiram_data_oe_c2p[3]}}, {8{qspiram_data_oe_c2p[2]}}, {8{qspiram_data_oe_c2p[1]}}, {8{qspiram_data_oe_c2p[0]}} }),
		.p2c(qspiram_data_i_p2c)
	);

    
    // BH Interface UARTs
	`IN_PAD(`IHP_PREFIX) IOPad_io_bhif_rxd[1:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (bhif_rxd_i_p2c),
		.pad (bhif_rxd_i_PAD)
	);

	`OUT_PAD16(`IHP_PREFIX) IOPad_io_bhif_cts (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (bhif_cts_o_c2p),
		.pad (bhif_cts_o_PAD)
	);

	// DCV Camera Interface
	`IN_PAD(`IHP_PREFIX) IOPad_io_cam_pixel_clk (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (cam_pixel_clk_i_p2c),
		.pad (cam_pixel_clk_i_PAD)
	);
	
	`IN_PAD(`IHP_PREFIX) IOPad_io_cam_line_valid (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (cam_line_valid_i_p2c),
		.pad (cam_line_valid_i_PAD)
	);
	
	`IN_PAD(`IHP_PREFIX) IOPad_io_cam_frame_valid (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (cam_frame_valid_i_p2c),
		.pad (cam_frame_valid_i_PAD)
	);
	
	`IN_PAD(`IHP_PREFIX) IOPad_io_cam_pixel_data[11:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (cam_pixel_data_i_p2c),
		.pad (cam_pixel_data_i_PAD)
	);
	
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_cam_doutif_data[15:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (cam_doutif_data_o_c2p),
		.pad (cam_doutif_data_o_PAD)
	);
	
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_cam_doutif_valid (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (cam_doutif_valid_o_c2p),
		.pad (cam_doutif_valid_o_PAD)
	);
	
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_cam_doutif_first (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (cam_doutif_first_o_c2p),
		.pad (cam_doutif_first_o_PAD)
	);
	
	`OUT_PAD16(`IHP_PREFIX) IOPad_io_cam_doutif_clk (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.c2p (cam_doutif_clk_o_c2p),
		.pad (cam_doutif_clk_o_PAD)
	);
	
	// eFPGA user IOs
 	`INOUT_PAD16(`IHP_PREFIX) IOPad_io_efpga[7:0] (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(efpga_io_PAD),
		.c2p(efpga_io_out_o_c2p),
		.c2p_en(efpga_io_oe_o_c2p),
		.p2c(efpga_io_in_i_p2c)
	);

 	`IN_PAD(`IHP_PREFIX) IOPad_io_efpga_sclk (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(efpga_sclk_i_PAD),
		.p2c(efpga_sclk_i_p2c)
	);

 	`IN_PAD(`IHP_PREFIX) IOPad_io_efpga_sdata (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.pad(efpga_sdata_i_PAD),
		.p2c(efpga_sdata_i_p2c)
	);

	// global control
	`IN_PAD(`IHP_PREFIX) IOPad_io_clock (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (clk_i_p2c),
		.pad (clk_i_PAD)
	);

	`IN_PAD(`IHP_PREFIX) IOPad_io_reset (
        `ifdef USE_POWER_PINS
        .vss(VSS), .vdd(VDD), .iovss(IOVSS), .iovdd(IOVDD),
        `endif
		.p2c (rstn_i_p2c),
		.pad (rstn_i_PAD)
	);
    

//////////   RTL top-level 	//////////
	diowas_top diowas_top_i (
		.clk_i(clk_i_p2c),
		.rstn_i(rstn_i_p2c),

		.jtag_tck_i(jtag_tck_i_p2c),
		.jtag_tdi_i(jtag_tdi_i_p2c),
		.jtag_tdo_o(jtag_tdo_o_c2p),
		.jtag_tms_i(jtag_tms_i_p2c),
		
		.spi_csn_o(spi_csn_o_c2p),
		.spi_sck_o(spi_sck_o_c2p),
		.spi_sdo_o(spi_sdo_o_c2p),
		.spi_sdi_i(spi_sdi_i_p2c),

		// Core complex: I2C host
		.twi_scl_o(twi_scl_o_c2p), // 0 = pull SCL low, 1 = leave SCL floating
		.twi_scl_i(twi_scl_i_p2c),
		.twi_sda_o(twi_sda_o_c2p), // 0 = pull SDA low, 1 = leave SDA floating
		.twi_sda_i(twi_sda_i_p2c),
		
		.status_led_o(status_led_o_c2p),

		.console_txd_o(console_txd_o_c2p),
		.console_rxd_i(console_rxd_i_p2c),

		// SPI PSRAM
		.spiram_clk_o(spiram_clk_o_c2p),
		.spiram_csn_o(spiram_csn_o_c2p),
		.spiram_sdi_i(spiram_sdi_i_p2c),
		.spiram_sdo_o(spiram_sdo_o_c2p),

		// Octal PSRAM
		.octram_bus_clk_o(qspiram_bus_clk_o_c2p),
		.octram_csn_o(qspiram_csn_o_c2p),
		.octram_resetn_o(qspiram_resetn_o_c2p),
		.octram_strobe_i(qspiram_strobe_i_p2c),
		.octram_strobe_o(qspiram_strobe_o_c2p),
		.octram_strobe_oe_o(qspiram_strobe_oe_c2p), // 0 input, 1 output
		.octram_data_i(qspiram_data_i_p2c),
		.octram_data_o(qspiram_data_o_c2p),
		.octram_data_oe_o(qspiram_data_oe_c2p), // 0 input, 1 output

		// DCV Camera Interface
		.cam_pixel_clk_i(cam_pixel_clk_i_p2c),
		.cam_frame_valid_i(cam_frame_valid_i_p2c),
		.cam_line_valid_i(cam_line_valid_i_p2c),
		.cam_pixel_data_i(cam_pixel_data_i_p2c),
		.cam_doutif_data_o(cam_doutif_data_o_c2p),
		.cam_doutif_valid_o(cam_doutif_valid_o_c2p),
		.cam_doutif_first_o(cam_doutif_first_o_c2p),
		.cam_doutif_clk_o(cam_doutif_clk_o_c2p),

		// BH Sensor IF UARTs
		.bhif_rxd_i(bhif_rxd_i_p2c),
		.bhif_cts_o(bhif_cts_o_c2p),

		// eFPGA user IOs
		.efpga_io_out_o(efpga_io_out_o_c2p),
		.efpga_io_oe_o(efpga_io_oe_o_c2p),
		.efpga_io_in_i(efpga_io_in_i_p2c),
		
		.efpga_cfg_sclk_i(efpga_sclk_i_p2c),
		.efpga_cfg_sdata_i(efpga_sdata_i_p2c)
	);
	
endmodule
