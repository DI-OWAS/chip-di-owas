--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: J.Schmid
-- File			: BHsensorIF_pkg.vhd
-- Design Name 	: FPGA
-- Module Name 	: BHsensorIF_pkg
-- Project Name : DI-OWAS
-- Create Date 	: 6.2.2025
-- Last Change 	: $Id: 6478188ec092523463371d15e200c06592aa5637 $
-- Description 	: 
-- Dependencies : n.a.
-- Revision 	: 0.1
-- Comments 	: 
--######################################################################
-- Copyright 2024-2025, B-Horizon GmbH, All Rights Reserved
--######################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package BHsensorIF_pkg is

-- TB constants
	constant CLOCK_FREQUENCY : natural := 100_000_000;
	constant c_period : time := (1 sec) / CLOCK_FREQUENCY;	-- 10 ns

-- RTL Constants

    -- Basis (Word-Index = Byte-Adresse >> 2)
    constant C_RO_BASE  : integer := 16#4000# / 4;  -- 0x4000 >> 2
    constant C_WO_BASE  : integer := 16#8000# / 4;  -- 0x8000 >> 2
	
	constant c_base_addr	 : unsigned(31 downto 0) := x"D000_0000";	-- RAM_1?
	
	constant c_store_frames  : integer := 16;

	constant c_channels  : integer := 4;	-- nr of channels

-- UART constants
	constant c_SIM_MODE_EN  : boolean := false		; 	--boolean; -- enable simulation-mode option
	constant c_SIM_LOG_FILE : string  := "uart.log"	; 	--string;  -- name of SIM mode log file
	constant c_UART_RX_FIFO : natural := 2**(4+3)	; 	--natural range 1 to 2**15; -- RX fifo depth, has to be a power of two, min 1	-- HW
	constant c_UART_TX_FIFO : natural := 1			;	--natural range 1 to 2**15  -- TX fifo depth, has to be a power of two, min 1	-- HW

	constant c_addr_ctrlreg : std_logic_vector(31 downto 0) := x"FFF5_0000"; -- access address UART
	constant c_addr_datareg : std_logic_vector(31 downto 0) := x"FFF5_0004"; -- access address UART

	--UART_CTRL_PRSCx			0b000	0b001	0b010	0b011	0b100	0b101	0b110	0b111
	--Resulting clock_prescaler	2		4		8		64		128		1024	2048	4096
	
	-- constant c_UART_CTRL_BAUD9  : std_logic_vector(9 downto 0) := b"00_0000_0100";-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
	-- constant c_UART_CTRL_PRSC2  : std_logic_vector(2 downto 0) := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
	-- constant c_baudrate : real := real(CLOCK_FREQUENCY / 2 / (4 + 1) )			;--										resulting 10Mbaud
	
	-- constant c_UART_CTRL_BAUD9  : std_logic_vector(9 downto 0) := b"00_0011_0001";-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x31 = d49
	-- constant c_UART_CTRL_PRSC2  : std_logic_vector(2 downto 0) := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
	-- constant c_baudrate : real := real(CLOCK_FREQUENCY / 2 / (49 + 1) )			;--										resulting 1Mbaud
	
	-- constant c_UART_CTRL_BAUD9  : std_logic_vector(9 downto 0) := b"00_0110_0011";-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x63 = d99
	-- constant c_UART_CTRL_PRSC2  : std_logic_vector(2 downto 0) := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
	-- constant c_baudrate : real := real(CLOCK_FREQUENCY / 2 / (99 + 1) )			;-- 									resulting 500kbaud
	
	constant c_UART_CTRL_BAUD9  : std_logic_vector(9 downto 0) := b"01_1111_0011"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x1F3 = d499
	constant c_UART_CTRL_PRSC2  : std_logic_vector(2 downto 0) := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
	constant c_baudrate : real := real(CLOCK_FREQUENCY / 2 / (499 + 1) )			;-- 									resulting 100kbaud


-- frame types and constants

	-- BHsensorIF_axi_burst4_writer
	-- 128 Byte = 1024 Bit
	subtype t_frame128B is std_logic_vector(1023 downto 0);

	-- 4 × 128-Byte Frames
	type t_frame128B_4ch is array (0 to 3) of t_frame128B;

	-- 4 × 6-bit Index (0..63)
	type t_u6_vec is array (0 to 3) of unsigned(5 downto 0);

	-- general types for uarts (4) and channels (8)
	type ty_ar4_sl is array (0 to 3) of std_logic;
	type ty_ar8_sl is array (0 to 7) of std_logic;
	type ty_ar8_slv8 is array (0 to 7) of std_logic_vector(7 downto 0);
	type ty_ar8_slv16 is array (0 to 7) of std_logic_vector(15 downto 0);
	type ty_ar8_slv32 is array (0 to 7) of std_logic_vector(31 downto 0);


	type ty_ar28_slv32 is array (0 to 28 -1) of std_logic_vector(31 downto 0);
	type ty_ar28_us32 is array (0 to 28 -1) of unsigned(31 downto 0);
	type ty_ar120_us8 is array (0 to 35+77+8 -1) of unsigned(7 downto 0);
	


	type t_array_col_seat is array (0 to 10) of std_logic_vector(7 downto 0);	-- coloums
	type t_array_seat is array (0 to 6) of t_array_col_seat;

	type t_array_col_backRest is array (0 to 4) of std_logic_vector(7 downto 0);	-- coloums
	type t_array_backRest is array (0 to 6) of t_array_col_backRest;
	
	type t_array_col_sensors is array (0 to 15) of std_logic_vector(7 downto 0);	-- coloums
	type t_array_sensors is array (0 to 6) of t_array_col_sensors;

	
	type t_array_col_frame is array (0 to 15) of std_logic_vector(7 downto 0);	-- coloums
	type t_array_frame is array (0 to 7) of t_array_col_frame;

	type t_arr_frames is array (0 to 63) of t_array_frame;	-- 64FPS
	--type t_arr15_sensors is array (0 to 14) of t_array_sensors;	-- 15FPS

	type t_states is (init, idle, read_header, read_payload, read_footer, check_frame, quantify_frame, store_frames);
	
	constant c_array_seat	: t_array_seat := (
		0		=> (5 => x"51", others => x"00"),
		1		=> (5 => x"52", others => x"00"),
		2		=> (5 => x"53", others => x"00"),
		3 		=> (x"04",x"14",x"24",x"34",x"44",x"54",x"64",x"74",x"84",x"94",x"A4"),
		4		=> (5 => x"55", others => x"00"),
		5		=> (5 => x"56", others => x"00"),
		6		=> (5 => x"57", others => x"00"),		
		others	=> (others => x"00")
	);

	constant c_array_backRest	: t_array_backRest := (
		0		=> (3 => x"E1", others => x"00"),
		1		=> (4 => x"F2", others => x"00"),
		2		=> (3 => x"E3", others => x"00"),
		3 		=> (2 => x"D4", others => x"00"),
		4		=> (1 => x"C5", others => x"00"),
		5		=> (0 => x"B6", others => x"00"),
		6		=> (1 => x"C7", others => x"00"),		
		others	=> (others => x"00")
	);	
	
	constant c_frame_sync : std_logic_vector(31 downto 0) := x"12_34_56_78";

	-- new Frame definitions
	
	constant c_start_Byte: unsigned(7 downto 0) := x"7B";
	constant c_end_Byte1 : unsigned(7 downto 0) := x"7D";
	constant c_end_Byte2 : unsigned(7 downto 0) := x"7E";
	
	constant c_streaming_message : unsigned(7 downto 0) := x"11";
	constant c_payload : unsigned(7 downto 0) := x"78";-- 120 = 112 +4TimeStamp +4cunter
	
	constant c_axil_thres0 : std_logic_vector(7 downto 0) := x"00";
	constant c_axil_thres1 : std_logic_vector(7 downto 0) := x"00";
	constant c_axil_thres2 : std_logic_vector(7 downto 0) := x"00";	
	
	--constant c_store_offset  : unsigned(31 downto 0) := to_unsigned(c_store_frames * 16#80#, 32);

	-- constant c_base_addr_ch0 : std_logic_vector(32-1 downto 0) := x"8000_0000";	-- base address
	-- constant c_base_addr_ch1 : std_logic_vector(32-1 downto 0) := x"8000_0800";
	-- constant c_base_addr_ch2 : std_logic_vector(32-1 downto 0) := x"8000_1000";
	-- constant c_base_addr_ch3 : std_logic_vector(32-1 downto 0) := x"8000_1800";
	
	-- constant c_base_addr_ch0 : unsigned(31 downto 0) := x"80000000";
	-- constant c_base_addr_ch1 : unsigned(31 downto 0) := c_base_addr_ch0 + c_store_offset;
	-- constant c_base_addr_ch2 : unsigned(31 downto 0) := c_base_addr_ch1 + c_store_offset;
	-- constant c_base_addr_ch3 : unsigned(31 downto 0) := c_base_addr_ch2 + c_store_offset;	

-- Components
	COMPONENT blk_mem_gen_1024x16
		PORT (
			clka 	: IN STD_ulogic;
			ena 	: IN STD_ulogic;
			wea 	: IN STD_ulogic_VECTOR(0 DOWNTO 0);
			addra 	: IN STD_ulogic_VECTOR(3 DOWNTO 0);
			dina 	: IN STD_ulogic_VECTOR(1023 DOWNTO 0);
			clkb 	: IN STD_ulogic;
			enb 	: IN STD_ulogic;
			addrb 	: IN STD_ulogic_VECTOR(3 DOWNTO 0);
			doutb 	: OUT STD_ulogic_VECTOR(1023 DOWNTO 0) 
		);
	END COMPONENT;
		
-- TB Functions/Procedures
	procedure p_strobe(signal s_strobe : inout std_logic);

end BHsensorIF_pkg;

package body BHsensorIF_pkg is

-- TB Functions/Procedures
	procedure p_strobe(signal s_strobe : inout std_logic) is
    begin
		s_strobe	<= '1';
		wait for 1*c_period;
		s_strobe	<= '0';
    end procedure;

end BHsensorIF_pkg;
