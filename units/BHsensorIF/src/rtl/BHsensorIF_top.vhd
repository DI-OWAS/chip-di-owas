--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: JSchmid
-- File			: BHsensorIF_top.vhd
-- Design Name 	: FPGA
-- Module Name 	: BHsensorIF_top
-- Project Name : DI-OWAS
-- Create Date 	: 6.2.2025
-- Last Change 	: $Id $
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
				
use work.BHsensorIF_pkg.all;

entity BHsensorIF_top is

	port (
		i_clk       	: in  std_logic; 
		i_rst_n      	: in  std_logic;		-- low active
		--i_enable		: in  std_logic;
							
		-- uart IF (4x rx only)   	      
		--o_txd  			: out std_logic_vector(3 downto 0); 
		--i_rxd  			: in  std_logic_vector(c_channels-1 downto 0); 
		i_rxd  			: in  std_logic_vector(1 downto 0); 	-- 2 channels only
		--o_rts	 		: out std_logic_vector(c_channels-1 downto 0); 	-- high active, enable SAC/TX via AXI-L
		o_cts	 		: out std_logic; 	-- high active, enable SAC/TX via AXI-L, rename to fit to demoboard
		--i_cts	 		: in  std_logic_vector(3 downto 0);		-- high active, redundant, no local TX, not connected
		
		o_irq_state		: out std_logic;
		i_irq_clr		: in  std_logic;
		
		-----------------------------------------------------------------------------
		-- BHsensorIF_s_axil	
		-----------------------------------------------------------------------------
		-- AXI-Lite Write Address
		s_axil_awaddr_i  : in  std_logic_vector(32-1 downto 0);
		s_axil_awvalid_i : in  std_logic;
		s_axil_awready_o : out std_logic;

		-- AXI-Lite Write Data
		s_axil_wdata_i   : in  std_logic_vector(31 downto 0);
		s_axil_wstrb_i   : in  std_logic_vector(c_channels-1 downto 0);
		s_axil_wvalid_i  : in  std_logic;
		s_axil_wready_o  : out std_logic;

		-- AXI-Lite Write Response
		s_axil_bresp_o   : out std_logic_vector(1 downto 0);
		s_axil_bvalid_o  : out std_logic;
		s_axil_bready_i  : in  std_logic;

		-- AXI-Lite Read Address
		s_axil_araddr_i  : in  std_logic_vector(32-1 downto 0);
		s_axil_arvalid_i : in  std_logic;
		s_axil_arready_o : out std_logic;

		-- AXI-Lite Read Data
		s_axil_rdata_o   : out std_logic_vector(31 downto 0);
		s_axil_rresp_o   : out std_logic_vector(1 downto 0);
		s_axil_rvalid_o  : out std_logic;
		s_axil_rready_i  : in  std_logic;

		-----------------------------------------------------------------------------
		-- BHsensorIF_axi_burst4_writer	
		-- using AXI DMA Writer Component (axi_dma_wr.v)
		-- only write channel used (only bursts, 32x4Bytes)
		-----------------------------------------------------------------------------
		m_axi_awaddr_o  : out std_logic_vector(32-1 downto 0);
		m_axi_awlen_o   : out std_logic_vector(7 downto 0);
		m_axi_awsize_o  : out std_logic_vector(2 downto 0);
		m_axi_awburst_o : out std_logic_vector(1 downto 0);
		m_axi_awvalid_o : out std_logic;
		m_axi_awready_i : in  std_logic;
						
		m_axi_wdata_o   : out std_logic_vector(32-1 downto 0);
		m_axi_wstrb_o   : out std_logic_vector(c_channels-1 downto 0);
		m_axi_wlast_o   : out std_logic;
		m_axi_wvalid_o  : out std_logic;
		m_axi_wready_i  : in  std_logic;
						
		m_axi_bid_i  	: in  std_logic;	--new
		m_axi_bresp_i   : in  std_logic_vector(1 downto 0);
		m_axi_bvalid_i  : in  std_logic;
		m_axi_bready_o  : out std_logic
	
	);
end BHsensorIF_top;

architecture rtl of BHsensorIF_top is

	signal s_irq_flags		: std_logic_vector(c_channels-1 downto 0); -- out std_logic;
	
	type ty_ar4_slv32 is array (0 to 3) of std_logic_vector(31 downto 0);
	signal s_time_stamp		: ty_ar4_slv32;
	signal s_frame_counter	: ty_ar4_slv32;

	signal s_axil_thres	: ty_ar4_slv32;
	
	-- signal s_axil_ch0_thres	: std_logic_vector(32-1 downto 0);
	-- signal s_axil_ch1_thres	: std_logic_vector(32-1 downto 0);
	-- signal s_axil_ch2_thres	: std_logic_vector(32-1 downto 0);
	-- signal s_axil_ch3_thres	: std_logic_vector(32-1 downto 0);
	
	--type ty_ar4_slv896 is array (0 to 3) of std_logic_vector(28*4*8 -1 downto 0);
	--signal s_frame_sensors_slv	: ty_ar4_slv896;	-- out ty_ar28_us32
	
	type ty_ar4_ar28_us32 is array (0 to 3) of ty_ar28_us32;
	signal s_frame_sensors	: ty_ar4_ar28_us32;	-- out ty_ar28_us32

	signal s_new_frame  : std_logic_vector(3 downto 0);
	signal s_frame_data : t_frame128B_4ch;

	signal s_write_done	: std_logic_vector(3 downto 0);

	signal s_frame_sensors_slv_0 : t_frame128B;
	signal s_frame_sensors_slv_1 : t_frame128B;
	signal s_frame_sensors_slv_2 : t_frame128B;
	signal s_frame_sensors_slv_3 : t_frame128B;

	function to_slv(a : ty_ar28_us32) return std_logic_vector is
		variable tmp : std_logic_vector(28*32 - 1 downto 0);
	begin
		for i in 0 to 27 loop
			tmp((i+1)*32 - 1 downto i*32) := std_logic_vector(a(i));
		end loop;
		return tmp;
	end function;


	function sensors_to_frame128B(a : ty_ar28_us32) return t_frame128B is
		variable slv896 : std_logic_vector(895 downto 0);
		variable frame  : t_frame128B := (others => '0');
	begin
		slv896 := to_slv(a);

		-- put sensors in lower 896 bits
		frame(895 downto 0) := slv896;

		-- upper 128 bits remain zero (or add your own fields here)

		return frame;
	end function;

	signal s_ro_data_i : std_logic_vector(2*32-1 downto 0);   -- 2×32b
	signal s_wo_data_o : std_logic_vector(6*32-1 downto 0);    -- 6×32b = 192b
	signal s_irq_valid : std_logic_vector(c_channels-1 downto 0);

	signal s_base_addr_ch0 : std_logic_vector(32-1 downto 0);
	signal s_base_addr_ch1 : std_logic_vector(32-1 downto 0);
	signal s_base_addr_ch2 : std_logic_vector(32-1 downto 0);
	signal s_base_addr_ch3 : std_logic_vector(32-1 downto 0);

	signal s_base_addr : std_logic_vector(32-1 downto 0);
	signal s_store_frames : std_logic_vector(8+8-1 downto 0);	-- single byte

	signal s_rst : std_logic;
	
	signal s_rts	: std_logic_vector(c_channels-1 downto 0); 	-- high active
	signal s_fix0 	: std_logic;

	signal s_irq_state    : std_logic_vector(c_channels-1 downto 0);
	signal s_irq_set      : std_logic_vector(c_channels-1 downto 0);
	signal s_irq_clr_sw   : std_logic_vector(c_channels-1 downto 0);
	signal s_irq_clr_hw   : std_logic;
	-- edge detection _d delayed
	signal s_irq_set_d      : std_logic_vector(c_channels-1 downto 0);
	signal s_irq_clr_sw_d   : std_logic_vector(c_channels-1 downto 0);
	signal s_irq_clr_hw_d   : std_logic;

	signal s_UART_CTRL_BAUD9  : std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
	signal s_UART_CTRL_PRSC2  : std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2

	signal s_rxd :  std_logic_vector(c_channels-1 downto 0); 

begin

	s_fix0 <= '0';
	
	--g_rxd : for i in 0 to c_channels-1 generate
	g_rxd : for i in 0 to 1 generate	-- 2 ch
	begin
		s_rxd(i) <= i_rxd(i) when s_rts(i) = '1' else '1';	-- RX idle when disable
	end generate g_rxd;

	s_rxd(2) <= s_fix0;
	s_rxd(3) <= s_fix0;
	
	--o_irq <= s_irq_flags;	-- std_logic_vector(3 downto 0)

	--g_generate: for x in 0 to c_channels-1 generate
	g_generate: for x in 0 to 1 generate	-- 2 channels only
		u_BHsensorIF_channel : entity work.BHsensorIF_channel(rtl)
			port map (
				i_clk   => i_clk	, -- in  std_logic; -- global clock line
				i_rstn  => i_rst_n	, -- in  std_logic; -- global reset line, low-active, async
				--o_txd 	=> open  	, -- out std_logic; -- serial TX line
				--i_rxd 	=> i_rxd(x)  	, -- in  std_logic; -- serial RX line
				i_rxd 	=> s_rxd(x)  	, -- in  std_logic; -- serial RX line
				--o_rts	=> open			, -- out std_logic; -- UART.RX ready to receive ("RTR"), high-active, optional
				i_rts	=> s_rts(x)		, -- out std_logic;	-- SW-flag, start TX-transfer, needed in channel to init baudrate
				--i_cts	=> s_fix0		, -- in  std_logic; -- UART.TX allowed to transmit, high-active, optional
				--             				
				i_axil_thres 	=> s_axil_thres(x)	,		--std_logic_vector(32-1 downto 0);
				--
				i_UART_CTRL_BAUD9  => s_UART_CTRL_BAUD9,	-- std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
				i_UART_CTRL_PRSC2  => s_UART_CTRL_PRSC2,	-- std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
				--
				o_IRQ_flag  	=> s_irq_flags(x)  			, -- out std_logic;
				o_time_stamp	=> s_time_stamp(x)			, -- out std_logic_vector(31 downto 0);
				o_frame_counter	=> s_frame_counter(x)		, -- out std_logic_vector(31 downto 0);
				--o_frame_sensors	=> s_frame_sensors(x)		  -- out std_logic_vector(28*4*8 -1 downto 0)
				o_frame_sensors	=> s_frame_sensors(x)		  -- out ty_ar28_us32
			);	
	end generate g_generate;

	g_generate_nc: for x in 2 to 3 generate	-- clamp not connected outputs
		s_irq_flags(x)  	<= '0';				-- out std_logic;
		s_time_stamp(x)		<= (others => '0');	-- out std_logic_vector(31 downto 0);
		s_frame_counter(x)	<= (others => '0');	-- out std_logic_vector(31 downto 0);
		s_frame_sensors(x)	<= (others => (others =>'0'));	-- out ty_ar28_us32
	end generate g_generate_nc;


	p_irq_valid : process (i_clk, i_rst_n)
	begin
		if i_rst_n = '0' then
			s_irq_valid <= (others => '0');
			
		elsif rising_edge(i_clk) then
		
			for i in 0 to c_channels-1 loop
				if s_irq_flags(i) = '1' then
					s_irq_valid(i) <= '1' after i*100 ns;
				end if;
				if s_write_done(i) = '1' then
					s_irq_valid(i) <= '0';
				end if;
			end loop;
			
		end if;
	end process;

	--s_new_frame <= s_irq_flags(3) & s_irq_flags(2) & s_irq_flags(1) & s_irq_flags(0);
	--s_new_frame <= b"00" & s_irq_valid(1) & '0' ;	-- ch1 only
	--s_new_frame <=  s_irq_valid(3) and not s_write_done(3) & 
	--				s_irq_valid(2) and not s_write_done(2) &
	--				s_irq_valid(1) and not s_write_done(1) &
	--				s_irq_valid(0) and not s_write_done(0);
					
	p_comp : process(s_irq_valid, s_write_done)
	begin
		for i in 0 to c_channels-1 loop
			--if s_irq_valid(i) = '1' and s_write_done(i) = '0' then
			--	s_new_frame(i) <= '1'; 
			--end if;
			s_new_frame(i) <= s_irq_valid(i) and not s_write_done(i);
		end loop;
	end process;

	s_frame_sensors_slv_0 <= sensors_to_frame128B(s_frame_sensors(0));
	s_frame_sensors_slv_1 <= sensors_to_frame128B(s_frame_sensors(1));
	s_frame_sensors_slv_2 <= sensors_to_frame128B(s_frame_sensors(2));
	s_frame_sensors_slv_3 <= sensors_to_frame128B(s_frame_sensors(3));
	
	--subtype t_frame128B is std_logic_vector(1023 downto 0);-- 128 Byte = 1024 Bit
	--type t_frame128B_4ch is array (0 to 3) of t_frame128B;-- 4 × 128-Byte Frames
	--s_frame_data(0) <= s_frame_counter(0) & s_time_stamp(0) & s_frame_sensors_slv_0(895 downto 0) & x"0000_0000_0000_0000";
	--s_frame_data(1) <= s_frame_counter(1) & s_time_stamp(1) & s_frame_sensors_slv_1(895 downto 0) & x"0000_0000_0000_0000";
	--s_frame_data(2) <= s_frame_counter(2) & s_time_stamp(2) & s_frame_sensors_slv_2(895 downto 0) & x"0000_0000_0000_0000";
	--s_frame_data(3) <= s_frame_counter(3) & s_time_stamp(3) & s_frame_sensors_slv_3(895 downto 0) & x"0000_0000_0000_0000";
	
	s_frame_data(0) <= x"0000_0000_0000_0000" & s_frame_sensors_slv_0(895 downto 0) & s_time_stamp(0) & s_frame_counter(0);
	s_frame_data(1) <= x"0000_0000_0000_0000" & s_frame_sensors_slv_1(895 downto 0) & s_time_stamp(1) & s_frame_counter(1);
	s_frame_data(2) <= x"0000_0000_0000_0000" & s_frame_sensors_slv_2(895 downto 0) & s_time_stamp(2) & s_frame_counter(2);
	s_frame_data(3) <= x"0000_0000_0000_0000" & s_frame_sensors_slv_3(895 downto 0) & s_time_stamp(3) & s_frame_counter(3);

	s_rst <= not i_rst_n;
	
	u_BHsensorIF_axi_master : entity work.BHsensorIF_axi_master(rtl)
		port map(
			clk   => i_clk	, -- in  std_logic;
			rst   => s_rst	, -- in  std_logic;

			i_store_frames	=>	s_store_frames,	--in std_logic_vector(2*8-1 downto 0);	--
			
			--------------------------------------------------------------------------
			-- 4 Kanäle Eingänge: 128-Byte Frame + Strobe
			--------------------------------------------------------------------------
			i_new_frame  	=> s_new_frame  , --in std_logic_vector(3 downto 0);
			i_frame_data 	=> s_frame_data , --in t_frame128B_4ch;

			--------------------------------------------------------------------------
			-- Basisadressen jedes Kanals
			--------------------------------------------------------------------------
			-- i_base_addr_ch0	=> std_logic_vector(c_base_addr_ch0), --in std_logic_vector(32-1 downto 0);
			-- i_base_addr_ch1	=> std_logic_vector(c_base_addr_ch1), --in std_logic_vector(32-1 downto 0);
			-- i_base_addr_ch2	=> std_logic_vector(c_base_addr_ch2), --in std_logic_vector(32-1 downto 0);
			-- i_base_addr_ch3	=> std_logic_vector(c_base_addr_ch3), --in std_logic_vector(32-1 downto 0);

			i_base_addr_ch0	=> s_base_addr_ch0, --in std_logic_vector(32-1 downto 0);
			i_base_addr_ch1	=> s_base_addr_ch1, --in std_logic_vector(32-1 downto 0);
			i_base_addr_ch2	=> s_base_addr_ch2, --in std_logic_vector(32-1 downto 0);
			i_base_addr_ch3	=> s_base_addr_ch3, --in std_logic_vector(32-1 downto 0);

			--------------------------------------------------------------------------
			-- Write-Done je Kanal
			--------------------------------------------------------------------------
			o_write_done 	=> s_write_done		, --out std_logic_vector(3 downto 0);

			--------------------------------------------------------------------------
			-- AXI4-MM Master
			--------------------------------------------------------------------------
			m_axi_awaddr  	=> m_axi_awaddr_o  	, --out std_logic_vector(32-1 downto 0);
			m_axi_awlen   	=> m_axi_awlen_o   	, --out std_logic_vector(7 downto 0);
			m_axi_awsize  	=> m_axi_awsize_o  	, --out std_logic_vector(2 downto 0);
			m_axi_awburst 	=> m_axi_awburst_o 	, --out std_logic_vector(1 downto 0);
			m_axi_awvalid 	=> m_axi_awvalid_o 	, --out std_logic;
			m_axi_awready 	=> m_axi_awready_i 	, --in  std_logic;

			m_axi_wdata   	=> m_axi_wdata_o   	, --out std_logic_vector(32-1 downto 0);
			m_axi_wstrb   	=> m_axi_wstrb_o   	, --out std_logic_vector(3 downto 0);
			m_axi_wlast   	=> m_axi_wlast_o   	, --out std_logic;
			m_axi_wvalid  	=> m_axi_wvalid_o  	, --out std_logic;
			m_axi_wready  	=> m_axi_wready_i  	, --in  std_logic;

			m_axi_bid     	=> m_axi_bid_i		, --in  std_logic;		-- new??
			m_axi_bresp   	=> m_axi_bresp_i   	, --in  std_logic_vector(1 downto 0);
			m_axi_bvalid  	=> m_axi_bvalid_i  	, --in  std_logic;
			m_axi_bready  	=> m_axi_bready_o  	  --out std_logic
	);

	u_BHsensorIF_axil_slave : entity work.BHsensorIF_axil_slave(rtl)
		port map(
			-- Global
			i_clk    	=> i_clk    	, --in  std_logic;
			i_rstn	 	=> i_rst_n 		, --in  std_logic;

			-- AXI-Lite Write Address
			i_awaddr  	=> s_axil_awaddr_i  , --in  std_logic_vector(32-1 downto 0);
			i_awvalid 	=> s_axil_awvalid_i , --in  std_logic;
			o_awready 	=> s_axil_awready_o , --out std_logic;

			-- AXI-Lite Write Data
			i_wdata   	=> s_axil_wdata_i   , --in  std_logic_vector(31 downto 0);
			i_wstrb   	=> s_axil_wstrb_i   , --in  std_logic_vector(3 downto 0);
			i_wvalid  	=> s_axil_wvalid_i  , --in  std_logic;
			o_wready  	=> s_axil_wready_o  , --out std_logic;

			-- AXI-Lite Write Response
			o_bresp   	=> s_axil_bresp_o   , --out std_logic_vector(1 downto 0);
			o_bvalid  	=> s_axil_bvalid_o  , --out std_logic;
			i_bready  	=> s_axil_bready_i  , --in  std_logic;

			-- AXI-Lite Read Address
			i_araddr  	=> s_axil_araddr_i  , --in  std_logic_vector(32-1 downto 0);
			i_arvalid 	=> s_axil_arvalid_i , --in  std_logic;
			o_arready 	=> s_axil_arready_o , --out std_logic;

			-- AXI-Lite Read Data
			o_rdata   	=> s_axil_rdata_o   , --out std_logic_vector(31 downto 0);
			o_rresp   	=> s_axil_rresp_o   , --out std_logic_vector(1 downto 0);
			o_rvalid  	=> s_axil_rvalid_o  , --out std_logic;
			i_rready  	=> s_axil_rready_i  , --in  std_logic;

			-- User-Signale
			i_ro_data   => s_ro_data_i,	--in  std_logic_vector(2*32-1 downto 0);	-- 2×32b
			o_wo_data   => s_wo_data_o  --out std_logic_vector(6*32-1 downto 0)	-- 6×32b = 192b
		);

	s_ro_data_i(2*32-1 downto c_channels) 	<= (others => '0');	-- unused
	
	--s_ro_data_i(0*32+c_channels-1 downto 0*32+0) 		<= s_irq_flags;		-- 4 channels
	s_ro_data_i(0*32+c_channels-1 downto 0*32+0) 		<= s_irq_state;		-- 4 channels

	--s_rts	<= s_wo_data_o(c_channels-1 downto 0) ;	-- high active
	--s_UART_CTRL_BAUD9 <= s_wo_data_o(1*32+9 	downto 1*32+0);		--std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
	s_rts	<= s_wo_data_o(2*32+c_channels-1 	downto 2*32+0) ;	-- high active

	--o_rts	<= s_rts;
	o_cts	<= '1' when s_rts /= "0000" else '0';	-- single port, rename to fit to demoboard

	-- s_axil_ch0_thres	<=  s_wo_data_o(1*32-1 downto 0*32) ;
	-- s_axil_ch1_thres	<=  s_wo_data_o(2*32-1 downto 1*32) ;
	-- s_axil_ch2_thres	<=  s_wo_data_o(3*32-1 downto 2*32) ;
	-- s_axil_ch3_thres	<=  s_wo_data_o(4*32-1 downto 3*32) ;

	s_axil_thres <= (others => (others => '0'));	-- unused
	-- s_axil_thres(0) <= x"00" & s_axil_ch0_thres(24-1 downto 0);
	-- s_axil_thres(1) <= x"00" & s_axil_ch1_thres(24-1 downto 0);
	-- s_axil_thres(2) <= x"00" & s_axil_ch2_thres(24-1 downto 0);
	-- s_axil_thres(3) <= x"00" & s_axil_ch3_thres(24-1 downto 0);
	
	s_base_addr 	<= s_wo_data_o(5*32-1 downto 4*32);
	s_store_frames 	<= s_wo_data_o(5*32+8+8-1 downto 5*32);	-- 2 Bytes

	s_UART_CTRL_BAUD9 <= s_wo_data_o(1*32+9 	downto 1*32+0);		--std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
	s_UART_CTRL_PRSC2 <= s_wo_data_o(1*32+16+2  downto 1*32+16);	--std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
	
	--p_addr : process (s_base_addr, s_store_frames, s_base_addr_ch0, s_base_addr_ch1, s_base_addr_ch2)
	-- p_addr : process (i_clk, s_base_addr, s_store_frames)
	-- begin
	
		-- s_base_addr_ch0 <= s_base_addr;
		-- s_base_addr_ch1 <= std_logic_vector(unsigned(s_base_addr_ch0) + to_unsigned(16#80#,32) * unsigned(s_store_frames));
		-- s_base_addr_ch2 <= std_logic_vector(unsigned(s_base_addr_ch1) + to_unsigned(16#80#,32) * unsigned(s_store_frames));
		-- s_base_addr_ch3 <= std_logic_vector(unsigned(s_base_addr_ch2) + to_unsigned(16#80#,32) * unsigned(s_store_frames));
		
	-- end process;

	p_addr : process (i_clk)
		variable frames_u : unsigned(8+8-1 downto 0);	-- 2bytes wg. sll
		variable step     : unsigned(31 downto 0);
		variable b0, b1, b2, b3 : unsigned(31 downto 0);
	begin
		if rising_edge(i_clk) then

			-- 32-bit sauber übernehmen
			frames_u := unsigned(s_store_frames);

			-- Schrittweite = frames * 128  (2^7)
			step := resize(frames_u sll 7, 32);
			-- Adressen berechnen
			b0 := unsigned(s_base_addr);
			b1 := b0 + step;
			b2 := b1 + step;
			b3 := b2 + step;

			-- Ausgänge
			s_base_addr_ch0 <= std_logic_vector(b0);
			s_base_addr_ch1 <= std_logic_vector(b1);
			s_base_addr_ch2 <= std_logic_vector(b2);
			s_base_addr_ch3 <= std_logic_vector(b3);

		end if;
	end process;

	------------------------------------------------------------------
	-- Global IRQ Handling
	------------------------------------------------------------------
	
	--s_irq_set <= '1' when s_irq_flags /= "0000" else '0';-- irq when a channel is active
	s_irq_set <= s_irq_flags;	-- irq per channel
	
	s_irq_clr_hw <= i_irq_clr;
	--s_irq_clr_sw <= '0';	-- TBD
	s_irq_clr_sw	<= s_wo_data_o(0*32+c_channels-1 	downto 0*32+0) ;	-- high active

	--o_irq_state <= s_irq_state;
	o_irq_state <= '1' when s_irq_state /= "0000" else '0';-- irq when a channel is active
	
	process(i_clk, i_rst_n)
	begin
		if i_rst_n = '0' then
			s_irq_state     <= (others => '0');
			s_irq_set_d     <= (others => '0');
			s_irq_clr_sw_d  <= (others => '0');
			s_irq_clr_hw_d  <= '0';		-- single port

		elsif rising_edge(i_clk) then
			for i in 0 to c_channels-1 loop
				-- Clear has priority over set
				if ((s_irq_clr_sw(i) and not s_irq_clr_sw_d(i)) = '1') or
				   ((s_irq_clr_hw and not s_irq_clr_hw_d) = '1') then

					s_irq_state(i) <= '0';

				elsif (s_irq_set(i) and not s_irq_set_d(i)) = '1' then

					s_irq_state(i) <= '1';

				end if;

				-- Register previous values for edge detection			
				s_irq_set_d(i)     <= s_irq_set(i);
				s_irq_clr_sw_d(i)  <= s_irq_clr_sw(i);
			end loop;
			s_irq_clr_hw_d  <= s_irq_clr_hw;
		end if;
	end process;

end rtl;