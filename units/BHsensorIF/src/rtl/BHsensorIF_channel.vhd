--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: J.Schmid
-- File			: BHsensorIF_channel.vhd
-- Design Name 	: FPGA
-- Module Name 	: BHsensorIF_channel
-- Project Name : DI-OWAS
-- Create Date 	: 6.2.2025
-- Last Change 	: $Id $
-- Description 	: 
-- Dependencies : n.a.
-- Revision 	: 1.0
-- Comments 	: 
--######################################################################
-- Copyright 2024-2025, B-Horizon GmbH, All Rights Reserved
--######################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--use ieee.std_logic_textio.all;

use work.BHsensorIF_pkg.all;

entity BHsensorIF_channel is
	-- generic (
		-- g_v130nm : boolean := true		-- default v130nm
	-- );
	port (
		i_clk   : in  std_logic; -- global clock line
		i_rstn  : in  std_logic; -- global reset line, low-active, async
		--o_txd 	: out std_logic; -- serial TX line
		i_rxd  	: in  std_logic; -- serial RX line
		--o_rts 	: out std_logic; -- UART.RX ready to receive ("RTR"), high-active, optional
		i_rts	: in  std_logic;	-- SW-flag, start TX-transfer, needed in channel to init baudrate
		--i_cts 	: in  std_logic; -- UART.TX allowed to transmit, high-active, optional
		--
		i_axil_thres : in std_logic_vector(32-1 downto 0);
		--
		i_UART_CTRL_BAUD9  : in std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
		i_UART_CTRL_PRSC2  : in std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
		--
		o_IRQ_flag  : out std_logic;
		o_time_stamp: out std_logic_vector(31 downto 0);
		o_frame_counter: out std_logic_vector(31 downto 0);
		o_frame_sensors: out ty_ar28_us32
		--o_frame_sensors: out std_logic_vector(28*4*8 -1 downto 0)
	);
end BHsensorIF_channel;

architecture rtl of BHsensorIF_channel is

	signal s_irq_rx  		: std_logic; -- RX interrupt
	signal s_ctrl1_data0	: std_logic; 					-- select CTRLreg (1) or DATAreg(0)
	--signal s_stb			: std_logic:='0'; 				-- request strobe, single-shot
	signal s_r0w1			: std_logic; 					
	signal s_data_tx		: unsigned(7 downto 0);--TX data byte
	signal s_data_rx		: unsigned(7 downto 0);--RX data byte
	
	-- signal s_array_seat 	: t_array_seat;
	-- signal s_array_backRest : t_array_backRest;
	
    signal s_state : t_states;	
	
	signal s_strobe : std_logic;
	signal s_stb_DatRd : std_logic;
	
	signal s_go2idle 			: std_logic;
	signal s_go2read_payload 	: std_logic;
	signal s_go2read_footer 	: std_logic;
	signal s_go2quantify_frame 	: std_logic;
	signal s_go2check_frame 	: std_logic;
	
	signal s_ack : std_logic;
	
	type ty_ar4_us8 is array (0 to 3) of unsigned(7 downto 0);
	signal s_header	: ty_ar4_us8;
	signal s_footer	: ty_ar4_us8;
	
	signal s_adr : unsigned(7 downto 0);
	signal s_payload : unsigned(7 downto 0);
	
	signal s_crc16 : unsigned(15 downto 0);

	signal s_array_payload : ty_ar120_us8;

	signal s_frame_sensors : ty_ar28_us32;
	signal s_time_stamp : unsigned(31 downto 0); 
	signal s_frame_counter : unsigned(31 downto 0); 
	
	signal s_DatRead_enable : std_logic;
	signal s_fifo_valid : std_logic;
	
	signal s_frame_count : unsigned(7 downto 0);	-- 255 counter

	signal s_axil_thres0 : unsigned(7 downto 0);
	signal s_axil_thres1 : unsigned(7 downto 0);
	signal s_axil_thres2 : unsigned(7 downto 0);
	
	signal s_fix0 : std_logic;	

	signal s_rts_edge 	: std_logic;
	signal s_rts_d  	: std_logic;

begin	

	s_axil_thres0 <= unsigned(i_axil_thres(7 downto 0));
	s_axil_thres1 <= unsigned(i_axil_thres(15 downto 8));
	s_axil_thres2 <= unsigned(i_axil_thres(23 downto 16));
	
	s_data_tx <= (others => '0');	-- TX not used; 
	
	s_fix0 <= '0';
	
	--o_txd <= s_fix0;	-- TX not used; output pin fixed to 0
	
	u_BHsensorIF_UartWrapper : entity work.BHsensorIF_UartWrapper
		generic map (
			--g_UART_RX_FIFO => 2**(3+4),	--: natural range 1 to 2**15 := c_UART_RX_FIFO :; -- RX fifo depth, has to be a power of two, min 1
			--g_UART_TX_FIFO => 2**(3+4)	--: natural range 1 to 2**15 := c_UART_TX_FIFO :  -- TX fifo depth, has to be a power of two, min 1
			g_UART_RX_FIFO => c_UART_RX_FIFO, -- RX fifo depth, has to be a power of two, min 1
			--g_UART_TX_FIFO => c_UART_TX_FIFO  -- TX fifo depth, has to be a power of two, min 1
			g_UART_TX_FIFO => 1  -- TX fifo depth, has to be a power of two, min 1
		)
		port map (
			i_clk       	=> i_clk      	,	--in  std_logic; -- global clock line
			i_rstn      	=> i_rstn     	,	--in  std_logic; -- global reset line, low-active, async
			--bus_req   	=> s_bus_req  	,	--in  bus_req_t;  -- bus request
			i_ctrl1_data0	=> s_ctrl1_data0,	--in  std_logic; -- select CTRLreg (1) or DATAreg(0)
			i_stb			=> s_stb_DatRd	,	--in  std_logic; -- request strobe, single-shot
			i_r0w1			=> s_r0w1		,	--in  std_logic; 
			i_data_tx		=> s_data_tx	,	--in  std_logic_vector(7 downto 0); 	--TX data byte
			o_data_rx		=> s_data_rx	,	--out std_logic_vector(7 downto 0); 	--RX data byte
			--bus_rsp  	=> s_bus_rsp  		,	--out bus_rsp_t;  -- bus response
			--clkgen_en 	=> open			,	--out std_logic; -- enable clock generator -> external input at clkgen(x) port
			--clkgen    	=> s_clkgen   	,	--in  std_logic_vector(7 downto 0);
			--o_txd  			=> o_txd 		,	--out std_logic; -- serial TX line
			o_txd  			=> open 		,	--out std_logic; -- serial TX line
			i_rxd  			=> i_rxd 		,	--in  std_logic; -- serial RX line
			o_rts  			=> open 		,	--out std_logic; -- UART.RX ready to receive ("RTR"), HIGH-active, optional
			--i_cts  			=> i_cts 		,	--in  std_logic; -- UART.TX allowed to transmit, HIGH-active, optional
			i_cts  			=> s_fix0 		,	--in  std_logic; -- UART.TX allowed to transmit, HIGH-active, optional
			o_irq_rx    	=> s_irq_rx   	,	--out std_logic; -- RX interrupt
			o_irq_tx    	=> open   		,	--out std_logic  -- TX interrupt
			--
			i_UART_CTRL_BAUD9  => i_UART_CTRL_BAUD9,	-- std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
			i_UART_CTRL_PRSC2  => i_UART_CTRL_PRSC2,	-- std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
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

	--s_stb_DatRd <= s_strobe AND (s_read_header or s_read_payload or s_read_footer or s_init);	-- init!!
	s_stb_DatRd <= s_strobe AND s_DatRead_enable;

	p_sync_frame : process (i_clk, i_rstn)
		variable L : integer;
		
	begin
	
		if i_rstn = '0' then
			s_frame_count <= (others => '0');
			s_go2read_payload		<= '0';
			s_ack <= '0';
			--s_shift_row_data <= (others => (others => '0'));
			
		elsif rising_edge(i_clk) then
			if s_strobe = '1' then
				s_fifo_valid <= s_DatRead_enable;
			end if;
			
			--if s_stb_DatRd = '1' then
			if s_strobe = '1' and s_fifo_valid = '1' then
				--if s_read_header = '1' OR s_read_payload = '1' then
				s_go2idle <= '0';
				s_go2read_payload <= '0';
				s_go2read_footer <= '0';
				s_go2quantify_frame <= '0';
				s_go2check_frame <= '0';
				--s_ack <= '0';		-- data valid until next frame (starting read header)
				
				if s_state = read_header then
					
					s_ack <= '0';	-- data valid until next frame (starting read header)
			
					--if s_frame_count <= to_unsigned(3, s_frame_count'length) then
					if s_frame_count <= 3 then
						s_header(0 to 2) <= s_header(1 to 3);
						s_header(3) <= s_data_rx; 
					end if;
					
					if s_frame_count = 2 then
						if s_header(2) /= c_start_Byte then
							s_go2idle <= '1';
						elsif s_header(3) = c_streaming_message then
							s_go2read_payload <= '1';
						else
							s_go2idle <= '1';
						end if;
					end if;
					
					if s_frame_count = 3 then
						s_adr <= s_header(3);
						s_payload <= s_data_rx;
					end if;
					
					s_frame_count <= s_frame_count + 1;
					
				end if;
				
				if s_state = read_payload then

					L := to_integer(s_payload);

					if s_frame_count <= L + 3 then
						
						-- Shift mit festen Loop-Grenzen
						for i in 0 to s_array_payload'high - 1 loop
							if i < L - 1 then
								s_array_payload(i) <= s_array_payload(i + 1);
							end if;
						end loop;

						-- neues Byte ans Ende
						if L >= 1 then
							s_array_payload(L - 1) <= s_data_rx;
						end if;

					end if;

					if s_frame_count = L + 2 then  -- "+3 - 1"
						s_go2read_footer <= '1';
					end if;

					s_frame_count <= s_frame_count + 1;

				end if;
				
				if s_state = read_footer then
				
					if s_frame_count <= s_payload +4 +4 -1 then	-- +header +footer
						s_footer <= s_footer(1 to 3) & s_data_rx; 
					end if;
					
					if s_frame_count = s_payload +4 +4 -1 then	-- +header +footer
						s_frame_count <= (others => '0');	
					else
						s_frame_count <= s_frame_count + 1;
					end if;
					
					if s_frame_count = s_payload +4 +4 -1 -1 then	-- +header +footer
						s_crc16(15 downto 8) <= s_footer(2);	-- tbd
						s_crc16(7 downto 0) <= s_footer(3);	-- tbd
						s_go2check_frame <= '1';
					end if;
					
				end if;
				
				if s_state = check_frame then	-- check crc16 tbd
				
					if s_footer(2) /= c_end_Byte1 or s_footer(3) /= c_end_Byte2 then
						s_ack <= '0';
						s_go2idle <= '1';	-- skip frame, dont store
					else
						s_ack <= '1';
						s_go2quantify_frame <= '1';
					end if;
				
				end if;
			
			end if;
			
			if s_strobe = '1' and s_fifo_valid = '0' then
				s_go2quantify_frame <= '0';			
			end if;
			
		end if;
	
	end process p_sync_frame;


	p_rts_ed: process(i_clk, i_rstn)
	begin
		if i_rstn = '0' then
			s_rts_edge	<= '0';
			s_rts_d     <= '0';

		elsif rising_edge(i_clk) then

			if s_strobe = '1' then

				if (i_rts and not s_rts_d) = '1' then
					s_rts_edge <= '1';
				else
					s_rts_edge <= '0';
				end if;

				s_rts_d <= i_rts;	-- for edge detection
				
			end if;

		end if;
	end process p_rts_ed;

	
	p_state_machine : process(i_clk, i_rstn) is
	begin
		if i_rstn = '0' then
			s_state <= init;
			s_ctrl1_data0 <= '1';	
			s_r0w1		<= '1';	
			s_DatRead_enable <= '0';
			
		elsif rising_edge(i_clk) then
			if s_strobe = '1' then
				s_ctrl1_data0 <= '0';	
				s_r0w1		<= '0';	
				--s_DatRead_enable <= '0';
				
				case s_state is
					when init =>				-- init uart (write to control register, strobe needed)
						s_DatRead_enable <= '1';		--?? Baudrate changes?
						s_ctrl1_data0 <= '1';	
						s_r0w1		<= '1';	
						s_state <= idle;
					when idle =>
						s_DatRead_enable <= '0';
						
						if s_rts_edge = '1' then	-- initial baudrate setting by SW after reset and rts edge
							s_state <= init;
						
						elsif s_irq_rx = '1' then
							s_state <= read_header;
							s_DatRead_enable <= '1';
						end if;
					when read_header =>
						s_DatRead_enable <= '1';
						if s_go2read_payload = '1' then
							s_state <= read_payload;
							s_DatRead_enable <= '1';
						elsif s_go2idle = '1' then
							-- s_state <= idle;
							s_state <= init;			-- init Baudrate from Regmap
							s_DatRead_enable <= '0';
						end if;
					when read_payload =>
						s_DatRead_enable <= '1';
						if s_go2read_footer = '1' then
							s_state <= read_footer;
							s_DatRead_enable <= '1';
						end if;
					when read_footer =>
						s_DatRead_enable <= '1';
						
						if s_go2check_frame = '1' then
							s_state <= check_frame;
							s_DatRead_enable <= '0';
						end if;
						
					when check_frame =>
						if s_go2quantify_frame = '1' then
							s_state <= quantify_frame;
							s_DatRead_enable <= '0';
							--s_go2quantify_frame <= '0';
						elsif s_go2idle = '1' then
							-- s_state <= idle;
							s_state <= init;			-- init Baudrate from Regmap
							s_DatRead_enable <= '0';
						end if;

					when quantify_frame =>
						s_state <= store_frames;
						s_DatRead_enable <= '0';
					when store_frames =>
						-- s_state <= idle;
						s_state <= init;			-- init Baudrate from Regmap
						s_DatRead_enable <= '0';
					when others =>
						-- s_state <= idle;
						s_state <= init;			-- init Baudrate from Regmap
						s_DatRead_enable <= '0';
				end case;
			end if;
		end if;
	end process p_state_machine;

	p_strobe : process (i_clk, i_rstn) is
		variable v_count : integer range 0 to 9;
	begin
		if i_rstn = '0' then
			v_count := 0;
			s_strobe <= '0';
		elsif rising_edge(i_clk) then
			--if v_count = 9 then
			if v_count = 3 then
				v_count := 0;
				s_strobe <= '1';
			else
				s_strobe <= '0';
				v_count := v_count + 1;
			end if;
		end if;
	end process p_strobe;
	
	p_irq : process (i_clk, i_rstn) is
	begin
		if i_rstn = '0' then
			--NULL;
			o_IRQ_flag <= '0';
			
		elsif rising_edge(i_clk) then
			if s_strobe = '1' then
				--if s_state = quantify_frame then
				--	s_time_stamp(31 downto 0) <= s_array_payload(0)&s_array_payload(1)&s_array_payload(2)&s_array_payload(3);
				--	--s_frame_counter <= s_array_payload(4 to 7);
				--	for i in 0 to 3 loop
				--		s_frame_counter((3-i)*8+7 downto (3-i)*8) <= s_array_payload(i+4);
				--	end loop;	
				--	
				--	if g_v130nm = true then		-- the else pathes are not synthezided at all, bypass FRAME_Quantify
				--		for i in 0 to 28 -1 loop
				--			s_frame_sensors(i) <= 	s_array_payload(4*i+8+0) &
				--									s_array_payload(4*i+8+1) &
				--									s_array_payload(4*i+8+2) &
				--									s_array_payload(4*i+8+3);
				--		end loop;													
				--
				--	elsif s_axil_thres0 = x"00" AND 
				--		s_axil_thres1 = x"00" AND 
				--		s_axil_thres2 = x"00" then
				--		
				--		for i in 0 to 28 -1 loop
				--			s_frame_sensors(i) <= 	s_array_payload(4*i+8+0) &
				--									s_array_payload(4*i+8+1) &
				--									s_array_payload(4*i+8+2) &
				--									s_array_payload(4*i+8+3);
				--		end loop;									
				--	else
				--		for i in 0 to 28 -1 loop
				--			for j in 0 to 3 loop
				--				if s_array_payload(4*i +8 +j) < s_axil_thres0 then
				--					s_frame_sensors(i)((3-j)*8+7 downto (3-j)*8) <= x"10";	
				--					
				--				elsif (s_array_payload(4*i +8 +j) >= s_axil_thres0) AND (s_array_payload(4*i +8 +j) < s_axil_thres1) then
				--					s_frame_sensors(i)((3-j)*8+7 downto (3-j)*8) <= x"30";	
				--					
				--				elsif (s_array_payload(4*i +8 +j) >= s_axil_thres1) AND (s_array_payload(4*i +8 +j) < s_axil_thres2) then
				--					s_frame_sensors(i)((3-j)*8+7 downto (3-j)*8) <= x"50";	
				--					
				--				elsif s_array_payload(4*i +8 +j) >= s_axil_thres2 then
				--					s_frame_sensors(i)((3-j)*8+7 downto (3-j)*8) <= x"70";	
				--				else	
				--					s_frame_sensors(i)((3-j)*8+7 downto (3-j)*8) <= x"FF";	-- error					
				--				end if;	
				--			end loop;
				--		end loop;
				--	end if;
				--end if;
				
				if s_state = store_frames then
					o_IRQ_flag <= '1';
				else
					o_IRQ_flag <= '0';
				end if;

			end if;
		end if;
	end process p_irq;
	
	-- quantify frame and reformat to 32bit/4Bytes databus format
	p_quantify_frame_comb : process (s_ack, s_array_payload) is
	begin
		s_time_stamp <= (others => '0');
		s_frame_counter <= (others => '0');
		s_frame_sensors <= (others => (others => '0'));

		if s_ack = '1' then
			s_time_stamp(31 downto 0) <= s_array_payload(0)&s_array_payload(1)&s_array_payload(2)&s_array_payload(3);
			--s_frame_counter <= s_array_payload(4 to 7);
			for i in 0 to 3 loop
				s_frame_counter((3-i)*8+7 downto (3-i)*8) <= s_array_payload(i+4);
			end loop;	
		
			for i in 0 to 28 -1 loop
				s_frame_sensors(i) <= 	s_array_payload(4*i+8+0) &
										s_array_payload(4*i+8+1) &
										s_array_payload(4*i+8+2) &
										s_array_payload(4*i+8+3);
			end loop;												
		end if;	
	end process p_quantify_frame_comb;
	
	o_time_stamp 	<= std_logic_vector(s_time_stamp);
	o_frame_counter <= std_logic_vector(s_frame_counter);	
	o_frame_sensors <= s_frame_sensors;
	--o_frame_sensors <= to_slv(s_frame_sensors);	
	
end rtl;




