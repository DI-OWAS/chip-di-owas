--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: J.Schmid
-- File			: TB_OWAS_BH_IF.vhd
-- Design Name 	: UART
-- Module Name 	: TB_OWAS_BH_IF
-- Project Name : DI-OWAS Project
-- Create Date 	: 6.2.2025
-- Last Change 	: $Id: 8632601961ef8490ca91e4bd07d9d071bfb32c43 $
-- Description 	: 
-- Dependencies : na
-- Revision 	: 1.0
-- Comments 	: 
--######################################################################
-- Copyright 2024-2025, B-Horizon GmbH, All Rights Reserved
--######################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.stop;
use std.textio.all;
use ieee.std_logic_textio.all;
				
--library neorv32;
--use neorv32.neorv32_package.all;

use work.BHsensorIF_pkg.all;

entity TB_OWAS_BH_IF is
end TB_OWAS_BH_IF;

architecture bhv of TB_OWAS_BH_IF is

	signal s_clk_i      : std_logic:='0'; -- global clock line
	signal s_rstn_i     : std_logic; -- global reset line, low-active, async

	signal s_dut_rxd_i 	: std_logic_vector(3 downto 0); -- serial RX line
	--signal s_dut_cts_i	: std_logic_vector(3 downto 0); -- UART.TX allowed to transmit, HIGH-active, optional
	signal s_dut_rts_o	: std_logic_vector(3 downto 0); -- UART.RX ready to receive ("RTR"), HIGH-active, optional
	--signal s_dut_txd_o 	: std_logic_vector(3 downto 0); -- serial TX line
	
	signal s_sac_rxd_i 	: std_logic; -- serial RX line
	signal s_sac_cts_i	: std_logic := '0'; -- UART.TX allowed to transmit, HIGH-active, optional
	signal s_sac_rts_o	: std_logic; -- UART.RX ready to receive ("RTR"), HIGH-active, optional
	signal s_sac_txd_o 	: std_logic; -- serial TX line
	signal s_sac_irq_tx_o  : std_logic; -- TX interrupt
		
	signal s_sac_ctrl1_data0_i	: std_logic; 					-- select CTRLreg (1) or DATAreg(0)
	signal s_sac_stb_i			: std_logic:='0'; 				-- request strobe, single-shot
	signal s_sac_r0w1_i			: std_logic; 					
	signal s_sac_data_tx_i		: std_logic_vector(7 downto 0);--TX data byte

	signal s_arr_frames_sac	: t_arr_frames;

	file 		f_frames_sac_out	: text;
	constant 	cf_frames_sac_out 	: string := "..\..\..\..\..\..\GIT\owas-intern\src_tb\sac2owas.dat"; 

	file 		f_ram_out		: text;
	constant 	cf_ram_out 		: string := "..\..\..\..\..\..\GIT\owas-intern\src_tb\out.dat"; 

	signal s_bram_frames_o	: std_logic_VECTOR(1023 DOWNTO 0);
	signal s_array_frame	: t_array_frame;	-- row/FIFO

	signal s_axil_awaddr_i  	: std_logic_vector(32-1 downto 0);
	signal s_axil_awvalid_i 	: std_logic;
							 
	signal s_axil_wdata_i   	: std_logic_vector(31 downto 0);
	signal s_axil_wstrb_i   	: std_logic_vector(3 downto 0);
	signal s_axil_wvalid_i  	: std_logic;
							
	signal s_axil_bready_i	: std_logic;
							
	signal s_axil_araddr_i  	: std_logic_vector(32-1 downto 0);
	signal s_axil_arvalid_i 	: std_logic;
	signal s_axil_rready_i	: std_logic;

	signal s_axil_awready_o	: std_logic;
	signal s_axil_wready_o  : std_logic;
	signal s_axil_bvalid_o  : std_logic;


	signal m_axi_awready_i 	: std_logic:='1';
	signal m_axi_wready_i  	: std_logic:='1';		

	signal m_axi_bid_i  	: std_logic:='1';
	signal m_axi_bresp_i   	: std_logic_vector(1 downto 0):=b"11";
	signal m_axi_bvalid_i  	: std_logic:='1';

	signal m_axi_awaddr_o	: std_logic_vector(32-1 downto 0);
	signal m_axi_awvalid_o	: std_logic;
	signal m_axi_wdata_o	: std_logic_vector(32-1 downto 0);
	signal m_axi_wvalid_o	: std_logic;
	signal m_axi_bready_o	: std_logic;

	signal s_irq_state_o	: std_logic;

begin
	
	s_clk_i 	<= not s_clk_i 	after c_period/2;
	s_rstn_i 	<= '0', '1'	 	after 10*c_period;

	s_sac_rxd_i <= '0';	-- not used
	
	s_sac_cts_i <= '0';	--in  std_logic; -- UART.TX allowed to transmit, HIGH-active, optional

	s_dut_rxd_i	<= s_sac_txd_o & s_sac_txd_o & s_sac_txd_o & s_sac_txd_o;-- sac connected to all channels

	--s_dut_cts_i	<= b"0000";		-- disable tx (cts high active), TX/DTU not used


------------------------------------------------------
-- SAC Source
------------------------------------------------------
	u_sac_uart : entity work.BHsensorIF_UartWrapper
		generic map (
			g_UART_RX_FIFO => 2**(3+4),	--: natural range 1 to 2**15 := c_UART_RX_FIFO :; -- RX fifo depth, has to be a power of two, min 1
			g_UART_TX_FIFO => 2**(3+4)	--: natural range 1 to 2**15 := c_UART_TX_FIFO :  -- TX fifo depth, has to be a power of two, min 1
		)
		port map (
			i_clk       	=> s_clk_i      	,	--in  std_logic; -- global clock line
			i_rstn      	=> s_rstn_i     	,	--in  std_logic; -- global reset line, low-active, async
			--bus_req_i   	=> s_bus_req_i  	,	--in  bus_req_t;  -- bus request
			i_ctrl1_data0	=> s_sac_ctrl1_data0_i	,	--in  std_logic; -- select CTRLreg (1) or DATAreg(0)
			i_stb			=> s_sac_stb_i		,	--in  std_logic; -- request strobe, single-shot
			i_r0w1			=> s_sac_r0w1_i		,	--in  std_logic; 
			i_data_tx		=> unsigned(s_sac_data_tx_i)	,	--in  std_logic_vector(7 downto 0); 	--TX data byte
			o_data_rx		=> open				,	--out  std_logic_vector(7 downto 0); 	--RX data byte
			--bus_rsp_o  	=> s_bus_rsp_o  	,	--out bus_rsp_t;  -- bus response
			--clkgen_en_o 	=> open				,	--out std_logic; -- enable clock generator -> external input at clkgen_i(x) port
			--clkgen_i    	=> s_clkgen_i   	,	--in  std_logic_vector(7 downto 0);
			o_txd		  	=> s_sac_txd_o 		,	--out std_logic; -- serial TX line
			i_rxd		  	=> s_sac_rxd_i 		,	--in  std_logic; -- serial RX line
			o_rts		  	=> s_sac_rts_o 		,	--out std_logic; -- UART.RX ready to receive ("RTR"), HIGH-active, optional
			i_cts		  	=> s_sac_cts_i 		,	--in  std_logic; -- UART.TX allowed to transmit, HIGH-active, optional
			o_irq_rx    	=> open   			,	--out std_logic; -- RX interrupt
			o_irq_tx    	=> s_sac_irq_tx_o  	,	--out std_logic  -- TX interrupt
			--
			o_UART_CTRL_RX_NEMPTY		=> open	,	--out	std_logic;	-- s_ctrlreg_data(16)	<= '0';	-- 	r/-	RX FIFO not empty		
			o_UART_CTRL_RX_HALF			=> open	,	--out	std_logic;	-- s_ctrlreg_data(17)	<= '0';	-- 	r/-	RX FIFO at least half-full		
			o_UART_CTRL_RX_FULL			=> open	,	--out	std_logic;	-- s_ctrlreg_data(18)	<= '0';	-- 	r/-	RX FIFO full		
			o_UART_CTRL_TX_EMPTY		=> open	,	--out	std_logic;	-- s_ctrlreg_data(19)	<= '0';	-- 	r/-	TX FIFO empty		
			o_UART_CTRL_TX_NHALF		=> open	,	--out	std_logic;	-- s_ctrlreg_data(20)	<= '0';	-- 	r/-	TX FIFO not at least half-full		
			o_UART_CTRL_TX_FULL			=> open	,	--out	std_logic;	-- s_ctrlreg_data(21)	<= '0';	-- 	r/-	TX FIFO full		
			o_UART_CTRL_IRQ_RX_NEMPTY	=> open	,	--out	std_logic;	-- s_ctrlreg_data(22)	<= '0';	-- 	r/w	fire IRQ if RX FIFO not empty		
			o_UART_CTRL_IRQ_RX_HALF		=> open	,	--out	std_logic;	-- s_ctrlreg_data(23)	<= '0';	-- 	r/w	fire IRQ if RX FIFO at least half-full		
			o_UART_CTRL_IRQ_RX_FULL		=> open	,	--out	std_logic;	-- s_ctrlreg_data(24)	<= '0';	-- 	r/w	fire IRQ if RX FIFO full		
			o_UART_CTRL_IRQ_TX_EMPTY	=> open	,	--out	std_logic;	-- s_ctrlreg_data(25)	<= '0';	-- 	r/w	fire IRQ if TX FIFO empty		
			o_UART_CTRL_IRQ_TX_NHALF	=> open	,	--out	std_logic;	-- s_ctrlreg_data(26)	<= '0';	-- 	r/w	fire IRQ if TX not at least half full		
			--o_-						=> open	,	--out	std_logic;	-- s_ctrlreg_data(27)	<= '0';	-- 	r/-	reserved read as zero		
			o_UART_CTRL_RX_CLR			=> open	,	--out	std_logic;	-- s_ctrlreg_data(28)	<= '0';	-- 	r/w	Clear RX FIFO, flag auto-clears		
			o_UART_CTRL_TX_CLR			=> open	,	--out	std_logic;	-- s_ctrlreg_data(29)	<= '0';	-- 	r/w	Clear TX FIFO, flag auto-clears		
			o_UART_CTRL_RX_OVER			=> open	,	--out	std_logic;	-- s_ctrlreg_data(30)	<= '0';	-- 	r/-	RX FIFO overflow; cleared by disabling the module		
			o_UART_CTRL_TX_BUSY			=> open		--out	std_logic	-- s_ctrlreg_data(31)	<= '0';	-- 	r/-	TX busy or TX FIFO not empty		
		);

------------------------------------------------------
-- read sac frames from file
------------------------------------------------------
	p_frames_read : process
		variable fstatus	: file_open_status;
		variable file_line  : line;
		variable v_slv  	: std_logic_vector(7 downto 0);
		variable x			: integer := 0;
	begin
		file_open(fstatus, f_frames_sac_out, cf_frames_sac_out, read_mode);
		while not endfile(f_frames_sac_out) loop
			for r in 0 to 7 loop
				readline(f_frames_sac_out, file_line);
				for c in 0 to 15 loop
				hread(file_line, v_slv);
				s_arr_frames_sac(x)(r)(c) <= std_logic_vector(v_slv);				
				end loop;	
			end loop;	
			x := x + 1;
		end loop;
		file_close(f_frames_sac_out);
		wait;
	end process p_frames_read;

------------------------------------------------------
-- apply sac-frames to UART/TX
------------------------------------------------------
	p_sac: process
		variable v_sac_timestamp : std_logic_vector(31 downto 0);	
	begin
		
		wait until s_dut_rts_o /= "0000";
		s_sac_cts_i	<= '1';			-- enable tx (cts high active), start streaming
		
		wait for 20*c_period;
		
		-- CTRLreg/read
		s_sac_ctrl1_data0_i <= '1';	
		s_sac_r0w1_i		<= '0';	
		p_strobe(s_sac_stb_i);
		wait for 19*c_period;
		
		-- 	enable/init UART (CTRL 0xfff50000)
		s_sac_ctrl1_data0_i <= '1';	
		s_sac_r0w1_i		<= '1';	
		p_strobe(s_sac_stb_i);
		wait for 19*c_period;

		-- CTRLreg/read
		s_sac_ctrl1_data0_i <= '1';	
		s_sac_r0w1_i		<= '0';	
		p_strobe(s_sac_stb_i);
		wait for 19*c_period;
				
		wait for 200*c_period;
		
		-- DATAreg access
		s_sac_ctrl1_data0_i <= '0';	
		for x in 0 to 63 loop	-- 64 FPS
			-- write
			s_sac_r0w1_i		<= '1';	
			for r in 0 to 0 loop		-- control row
				for c in 0 to 3 loop
					s_sac_data_tx_i <= s_arr_frames_sac(x)(r)(c);	-- write SAC to uart/tx		
					p_strobe(s_sac_stb_i);
					wait for 9*c_period;
				end loop;
				
				v_sac_timestamp := std_logic_vector(to_unsigned(integer(real(now / 1 us)), 32));	-- Factor tbd
				
				for c in 4 to 7 loop	-- time stamp
				--for i in 0 to 3 loop	-- time stamp
					--s_sac_data_tx_i <= v_sac_timestamp(32-1 -8*i downto 32-8 -8*i);	 							
					s_sac_data_tx_i <= s_arr_frames_sac(x)(r)(c);	-- write SAC to uart/tx		--debug	
					
					p_strobe(s_sac_stb_i);
					wait for 9*c_period;
				end loop;
				
				for c in 8 to 8 loop	-- frame counter 32bit LSB=count
					s_sac_data_tx_i <= std_logic_vector(to_unsigned(x, 8));	-- write SAC to uart/tx
					p_strobe(s_sac_stb_i);
					wait for 9*c_period;
				end loop;
				
				for c in 9 to 11 loop	-- frame counter 32bit
					s_sac_data_tx_i <= s_arr_frames_sac(x)(r)(c);	-- write SAC to uart/tx		
					p_strobe(s_sac_stb_i);
					wait for 9*c_period;
				end loop;
			end loop;
			
			for r in 1 to 7 loop		-- data rows
				for c in 0 to 15 loop
					s_sac_data_tx_i <= s_arr_frames_sac(x)(r)(c);	-- write SAC to uart/tx		
					p_strobe(s_sac_stb_i);
					wait for 9*c_period;
				end loop;
			end loop;	

			-- finalize with crc16 and end bytes (from row 0)
			for c in 12 to 15 loop	-- 2x crc16, 2x End bytes
				s_sac_data_tx_i <= s_arr_frames_sac(x)(0)(c);	-- write SAC to uart/tx		
				p_strobe(s_sac_stb_i);
				wait for 9*c_period;
			end loop;
				
			--wait for 128*(8+3)*10*c_period;	-- time per frame, bits @ baudrate
			wait until 	s_sac_irq_tx_o = '1';
			wait for 100 us;	-- safety margin
			
		end loop;

		wait for 17000*c_period;
		stop;
		WAIT;
		
	end process p_sac;

------------------------------------------------------
-- enable SAC-TX-Streaming, WRITE CTS Register (output Pin)
------------------------------------------------------
	stimulus_cts : process
		variable read_tmp : std_logic_vector(31 downto 0);
	begin

		wait for 1 ms;
		s_axil_awaddr_i  <= x"0000_8000";	-- cts
		s_axil_awvalid_i <= '1';

		s_axil_wdata_i   <= x"0000_0008";	-- channel 3
		s_axil_wstrb_i   <= "1111";
		s_axil_wvalid_i  <= '1';

		s_axil_bready_i  <= '1';

		wait until rising_edge(s_clk_i) and s_axil_awready_o = '1' and s_axil_wready_o = '1';

		s_axil_awvalid_i <= '0';
		s_axil_wvalid_i  <= '0';

		wait until rising_edge(s_clk_i) and s_axil_bvalid_o = '1';
		s_axil_bready_i <= '0';

		wait;
	end process stimulus_cts;

------------------------------------------------------
-- collect data from Bus (local memory dump)
------------------------------------------------------
	p_ram : process(s_clk_i, s_rstn_i) is
		variable v_addr : std_logic_vector(31 downto 0):=(others=>'0');
		variable v_data : std_logic_vector(31 downto 0):=(others=>'0');
		variable fstatus	: file_open_status;
		variable file_line  : line;
	begin
	
		if s_rstn_i = '0' then	-- clear file

			file_open(fstatus, f_ram_out, cf_ram_out, write_mode);
			file_close(f_ram_out);
	
		elsif rising_edge(s_clk_i) then
			if m_axi_awvalid_o = '1' then
				v_addr := m_axi_awaddr_o;
				
				file_open(fstatus, f_ram_out, cf_ram_out, append_mode);

			end if;
			
			if m_axi_wvalid_o = '1' then
			
				v_data := m_axi_wdata_o;		-- read valid data
				
				hwrite(file_line, v_addr, right, 8);
				write(file_line, character'VAL(9));  	-- TAB
				hwrite(file_line, v_data, right, 8);
				writeline(f_ram_out, file_line);			
					
				v_addr := std_logic_vector(unsigned(v_addr) + 4);	-- byte addressing
				
			end if;
			
			if m_axi_bready_o = '1' then
				--write(file_line, character'VAL(13));	-- CR
				writeline(f_ram_out, file_line);			
				file_close(f_ram_out);
			end if;
			
		end if;
	end process;

end bhv;


