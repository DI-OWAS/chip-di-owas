--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: J.Schmid
-- File			: BHsensorIF_UartWrapper.vhd
-- Design Name 	: UartWrapper
-- Module Name 	: BHsensorIF_UartWrapper
-- Project Name : DI-OWAS
-- Create Date 	: 6.2.2025
-- Last Change 	: $Id: c3225bcdf2c8b30d0b6d036cc7c9e4500494ac66 $
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

-- pragma translate_off
-- RTL_SYNTHESIS OFF
use std.textio.all;
-- RTL_SYNTHESIS ON
-- pragma translate_on

--library neorv32;
use work.BHsensorIF_neorv32_package.bus_req_t;
use work.BHsensorIF_neorv32_package.bus_rsp_t;

use work.BHsensorIF_pkg.all;

entity BHsensorIF_UartWrapper is
	generic (
		g_UART_RX_FIFO : natural range 1 to 2**15 := c_UART_RX_FIFO; -- RX fifo depth, has to be a power of two, min 1
		g_UART_TX_FIFO : natural range 1 to 2**15 := c_UART_TX_FIFO  -- TX fifo depth, has to be a power of two, min 1
	);
	port (
		i_clk       	: in  std_logic; -- global clock line
		i_rstn      	: in  std_logic; -- global reset line, low-active, async
		--bus_req_i  	: in  bus_req_t;  -- bus request
		i_ctrl1_data0	: in  std_logic; -- select CTRLreg (1) or DATAreg(0)
		i_stb			: in  std_logic; -- request strobe, single-shot
		i_r0w1			: in  std_logic; -- 0 = read, 1 = write
		i_data_tx		: in  unsigned(7 downto 0); 	--TX data byte
		o_data_rx		: out unsigned(7 downto 0); 	--RX data byte
		o_txd  			: out std_logic; -- serial TX line
		i_rxd  			: in  std_logic; -- serial RX line
		o_rts 			: out std_logic; -- UART.RX ready to receive ("RTR"), high-active, optional
		i_cts 			: in  std_logic; -- UART.TX allowed to transmit, high-active, optional
		o_irq_rx   		: out std_logic; -- RX interrupt
		o_irq_tx   		: out std_logic;  -- TX interrupt
		--
		-- Baudrate from AXI-L/Regmap
		i_UART_CTRL_BAUD9  : in std_logic_vector(9 downto 0);	-- := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	x4
		i_UART_CTRL_PRSC2  : in std_logic_vector(2 downto 0);	-- := b"000"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	d2
		--
		o_UART_CTRL_RX_NEMPTY		: out	std_logic;	-- s_ctrlreg_data(16)	<= '0';	-- 	r/-	RX FIFO not empty		
		o_UART_CTRL_RX_HALF			: out	std_logic;	-- s_ctrlreg_data(17)	<= '0';	-- 	r/-	RX FIFO at least half-full		
		o_UART_CTRL_RX_FULL			: out	std_logic;	-- s_ctrlreg_data(18)	<= '0';	-- 	r/-	RX FIFO full		
		o_UART_CTRL_TX_EMPTY		: out	std_logic;	-- s_ctrlreg_data(19)	<= '0';	-- 	r/-	TX FIFO empty		
		o_UART_CTRL_TX_NHALF		: out	std_logic;	-- s_ctrlreg_data(20)	<= '0';	-- 	r/-	TX FIFO not at least half-full		
		o_UART_CTRL_TX_FULL			: out	std_logic;	-- s_ctrlreg_data(21)	<= '0';	-- 	r/-	TX FIFO full		
		o_UART_CTRL_IRQ_RX_NEMPTY	: out	std_logic;	-- s_ctrlreg_data(22)	<= '0';	-- 	r/w	fire IRQ if RX FIFO not empty		
		o_UART_CTRL_IRQ_RX_HALF		: out	std_logic;	-- s_ctrlreg_data(23)	<= '0';	-- 	r/w	fire IRQ if RX FIFO at least half-full		
		o_UART_CTRL_IRQ_RX_FULL		: out	std_logic;	-- s_ctrlreg_data(24)	<= '0';	-- 	r/w	fire IRQ if RX FIFO full		
		o_UART_CTRL_IRQ_TX_EMPTY	: out	std_logic;	-- s_ctrlreg_data(25)	<= '0';	-- 	r/w	fire IRQ if TX FIFO empty		
		o_UART_CTRL_IRQ_TX_NHALF	: out	std_logic;	-- s_ctrlreg_data(26)	<= '0';	-- 	r/w	fire IRQ if TX not at least half full		
		--o_-						: out	std_logic;	-- s_ctrlreg_data(27)	<= '0';	-- 	r/-	reserved read as zero		
		o_UART_CTRL_RX_CLR			: out	std_logic;	-- s_ctrlreg_data(28)	<= '0';	-- 	r/w	Clear RX FIFO, flag auto-clears		
		o_UART_CTRL_TX_CLR			: out	std_logic;	-- s_ctrlreg_data(29)	<= '0';	-- 	r/w	Clear TX FIFO, flag auto-clears		
		o_UART_CTRL_RX_OVER			: out	std_logic;	-- s_ctrlreg_data(30)	<= '0';	-- 	r/-	RX FIFO overflow; cleared by disabling the module		
		o_UART_CTRL_TX_BUSY			: out	std_logic	-- s_ctrlreg_data(31)	<= '0';	-- 	r/-	TX busy or TX FIFO not empty		
	);
end BHsensorIF_UartWrapper;

architecture rtl of BHsensorIF_UartWrapper is

	signal s_bus_req 		: bus_req_t;  					  -- bus request
	signal s_addr 			: std_logic_vector(31 downto 0); -- access address
	signal s_data 			: std_logic_vector(31 downto 0); -- access data
	signal s_ctrlreg_data 	: std_logic_vector(31 downto 0); -- access data
	signal s_datareg_data 	: std_logic_vector(31 downto 0); -- access data

	-- constant c_SIM_MODE_EN  : boolean := false		; 	--boolean; -- enable simulation-mode option
	-- constant c_SIM_LOG_FILE : string  := "uart.log"	; 	--string;  -- name of SIM mode log file
	-- constant c_UART_RX_FIFO : natural := 16			; 	--natural range 1 to 2**15; -- RX fifo depth, has to be a power of two, min 1	-- HW
	-- constant c_UART_TX_FIFO : natural := 16			;	--natural range 1 to 2**15  -- TX fifo depth, has to be a power of two, min 1	-- HW

	-- constant c_UART_DATA_TX_FIFO_SIZE : std_logic(3 downto 0) := x"2";	-- UART_DATA_TX_FIFO_SIZE (log2, SW/application)
	-- constant c_UART_DATA_RX_FIFO_SIZE : std_logic(3 downto 0) := x"2";	-- UART_DATA_RX_FIFO_SIZE (log2, SW/application)
	
	-- constant c_addr_ctrlreg : std_logic(31 downto 0) := x"FFF5_0000"; -- access address
	-- constant c_addr_datareg : std_logic(31 downto 0) := x"FFF5_0004"; -- access address

	-- constant c_UART_CTRL_BAUD9  : std_logic(9 downto 0) := b"00_0000_0100"	;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	r/w	12-bit Baud value configuration value
	-- constant c_UART_CTRL_PRSC2  : std_logic(2 downto 0) := b"111"			;-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	r/w	12-bit Baud value configuration value

	signal s_prsc_count	: std_logic_vector(12-1 downto 0);
	signal s_clk_2		: std_logic;
	signal s_clk_4		: std_logic;
	signal s_clk_8		: std_logic;
	signal s_clk_64		: std_logic;
	signal s_clk_128	: std_logic;
	signal s_clk_1024	: std_logic;
	signal s_clk_2048	: std_logic;
	signal s_clk_4096	: std_logic;
	signal s_clkgen		: std_logic_vector(8-1 downto 0);

    signal s_bus_rsp  	: bus_rsp_t;  -- bus response

	signal s_uart_rtsn	: std_logic; -- UART.RX ready to receive ("RTR"), low-active, optional
	signal s_uart_ctsn	: std_logic; -- UART.TX allowed to transmit, low-active, optional

begin

	-- prescaler clock generator 
	p_prsc_count: process(i_rstn, i_clk)
	
			variable v_count : integer range 0 to 2**12 - 1; 	-- 4096
			
	begin
	
		if (i_rstn = '0') then
			v_count := 0;
		elsif rising_edge(i_clk) then
			if v_count = 2**12 - 1 then
				v_count := 0;
			else
				v_count := v_count + 1;
			end if;
		end if;
		
		s_prsc_count <= std_logic_vector(to_unsigned(v_count,12));
		
	end process p_prsc_count;

	s_clk_2 	<= s_prsc_count(0);
	s_clk_4 	<= s_prsc_count(1);
	s_clk_8 	<= s_prsc_count(2);
	s_clk_64	<= s_prsc_count(5);
	s_clk_128	<= s_prsc_count(6);
	s_clk_1024	<= s_prsc_count(9);
	s_clk_2048	<= s_prsc_count(10);
	s_clk_4096	<= s_prsc_count(11);
	
	-- s_UART_CTRL_BAUD9	<= b"00_0000_0100"		;	-- UART_CTRL_BAUD9 : UART_CTRL_BAUD0	r/w	12-bit Baud value configuration value		
	-- s_UART_CTRL_PRSC2	<= b"111"				;	-- UART_CTRL_PRSC2 : UART_CTRL_PRSC0	r/w	Baud rate clock prescaler select		
	--s_clkgen				<= s_clk_2 & b"000_0000"	;	-- prescaler bit 7 (s_uart_ctrl(5 downto 3)	<= b"111")

	s_clkgen(0)	<= s_clk_2 		;
	s_clkgen(1)	<= s_clk_4 	   	;
	s_clkgen(2)	<= s_clk_8 	   	;
	s_clkgen(3)	<= s_clk_64	   	;
	s_clkgen(4)	<= s_clk_128	;
	s_clkgen(5)	<= s_clk_1024	;
	s_clkgen(6)	<= s_clk_2048	;
	s_clkgen(7)	<= s_clk_4096	;
	
	-- MUXes
	s_addr <= c_addr_ctrlreg 	when i_ctrl1_data0 = '1' else c_addr_datareg; --when i_ctrl1_data0 = '0'; -- [nolting] fix latch
	s_data <= s_ctrlreg_data 	when i_ctrl1_data0 = '1' else s_datareg_data; --when i_ctrl1_data0 = '0'; -- [nolting] fix latch
	
	-- CTRLs
	s_bus_req.addr  	<= std_ulogic_vector(s_addr)		;	-- std_ulogic_vector(31 downto 0); -- access address
	s_bus_req.data  	<= std_ulogic_vector(s_data)		;	-- std_ulogic_vector(31 downto 0); -- write data
	s_bus_req.ben   	<= x"F"			;	-- std_ulogic_vector(3 downto 0); -- byte enable
	s_bus_req.stb   	<= i_stb		; 	-- std_ulogic; -- request strobe, single-shot
	s_bus_req.rw    	<= i_r0w1		;	-- std_ulogic; -- 0 = read, 1 = write
	s_bus_req.src   	<= '0'			;	-- std_ulogic; -- 0 = data access, 1 = instruction fetch
	s_bus_req.priv  	<= '0'			;	-- std_ulogic; -- set if privileged (machine-mode) access
	s_bus_req.debug 	<= '0'			;	-- std_ulogic; -- set if debug mode access
	s_bus_req.amo   	<= '0'			;	-- std_ulogic; -- set if atomic memory operation
	s_bus_req.amoop 	<= x"0"			;	-- std_ulogic_vector(3 downto 0); -- type of atomic memory operation
	s_bus_req.fence 	<= '0'			;	-- std_ulogic; -- set if fence(.i) operation, single-shot

	-- CTRLreg/Data
	s_ctrlreg_data(0)		<= '1';			--	UART_CTRL_EN						r/w	UART enable		
	s_ctrlreg_data(1)		<= '0';			--	UART_CTRL_SIM_MODE					r/w	enable simulation mode		
	s_ctrlreg_data(2)		<= '1';			--	UART_CTRL_HWFC_EN					r/w	enable RTS/CTS hardware flow-control		
	-- s_ctrlreg_data(5 downto 3) <= c_UART_CTRL_PRSC2;	-- 	UART_CTRL_PRSC2 : UART_CTRL_PRSC0	r/w	Baud rate clock prescaler select		
	-- s_ctrlreg_data(15 downto 6)<= c_UART_CTRL_BAUD9;	-- 	UART_CTRL_BAUD9 : UART_CTRL_BAUD0	r/w	12-bit Baud value configuration value		
	s_ctrlreg_data(5 downto 3) <= i_UART_CTRL_PRSC2;	-- 	UART_CTRL_PRSC2 : UART_CTRL_PRSC0	r/w	Baud rate clock prescaler select		
	s_ctrlreg_data(15 downto 6)<= i_UART_CTRL_BAUD9;	-- 	UART_CTRL_BAUD9 : UART_CTRL_BAUD0	r/w	12-bit Baud value configuration value		
	--
	s_ctrlreg_data(16)		<= '0';			-- 	UART_CTRL_RX_NEMPTY					r/-	RX FIFO not empty		
	s_ctrlreg_data(17)		<= '0';			-- 	UART_CTRL_RX_HALF					r/-	RX FIFO at least half-full		
	s_ctrlreg_data(18)		<= '0';			-- 	UART_CTRL_RX_FULL					r/-	RX FIFO full		
	s_ctrlreg_data(19)		<= '0';			-- 	UART_CTRL_TX_EMPTY					r/-	TX FIFO empty		
	s_ctrlreg_data(20)		<= '0';			-- 	UART_CTRL_TX_NHALF					r/-	TX FIFO not at least half-full		
	s_ctrlreg_data(21)		<= '0';			-- 	UART_CTRL_TX_FULL					r/-	TX FIFO full		
	s_ctrlreg_data(22)		<= '0';			-- 	UART_CTRL_IRQ_RX_NEMPTY				r/w	fire IRQ if RX FIFO not empty		
	s_ctrlreg_data(23)		<= '0';			-- 	UART_CTRL_IRQ_RX_HALF				r/w	fire IRQ if RX FIFO at least half-full		
	s_ctrlreg_data(24)		<= '1';			-- 	UART_CTRL_IRQ_RX_FULL				r/w	fire IRQ if RX FIFO full		
	s_ctrlreg_data(25)		<= '1';			-- 	UART_CTRL_IRQ_TX_EMPTY				r/w	fire IRQ if TX FIFO empty		
	s_ctrlreg_data(26)		<= '0';			-- 	UART_CTRL_IRQ_TX_NHALF				r/w	fire IRQ if TX not at least half full		
	s_ctrlreg_data(27)		<= '0';			-- 	-									r/-	reserved read as zero		
	s_ctrlreg_data(28)		<= '0';			-- 	UART_CTRL_RX_CLR					r/w	Clear RX FIFO, flag auto-clears		
	s_ctrlreg_data(29)		<= '0';			-- 	UART_CTRL_TX_CLR					r/w	Clear TX FIFO, flag auto-clears		
	s_ctrlreg_data(30)		<= '0';			-- 	UART_CTRL_RX_OVER					r/-	RX FIFO overflow; cleared by disabling the module		
	s_ctrlreg_data(31)		<= '0';			-- 	UART_CTRL_TX_BUSY					r/-	TX busy or TX FIFO not empty		
	
	-- DATAreg/Data
	s_datareg_data(31 downto 16) <= (others => '0');	-- reserved
	
	--s_datareg_data(15 downto 12) <= c_UART_DATA_TX_FIFO_SIZE;	-- UART_DATA_TX_FIFO_SIZE (log2, SW/application)
	--s_datareg_data(11 downto 8)  <= c_UART_DATA_RX_FIFO_SIZE;	-- UART_DATA_RX_FIFO_SIZE (log2, SW/application)
	s_datareg_data(15 downto 8) <= (others => '0');		-- read only
	
	s_datareg_data(7 downto 0)   <= std_logic_vector(i_data_tx);			-- data_tx

	o_rts  	<= NOT s_uart_rtsn;	--out std_ulogic; -- UART.RX ready to receive ("RTR"), low-active, optional
	s_uart_ctsn 	<= NOT i_cts;		--in  std_ulogic; -- UART.TX allowed to transmit, low-active, optional

	u_neorv32_uart : entity work.BHsensorIF_neorv32_uart
		generic map (
			SIM_MODE_EN  => c_SIM_MODE_EN , --boolean; -- enable simulation-mode option
			SIM_LOG_FILE => c_SIM_LOG_FILE,	--string;  -- name of SIM mode log file
			UART_RX_FIFO => g_UART_RX_FIFO,	--natural range 1 to 2**15; -- RX fifo depth, has to be a power of two, min 1
			UART_TX_FIFO => g_UART_TX_FIFO 	--natural range 1 to 2**15  -- TX fifo depth, has to be a power of two, min 1
		)
		port map (
			clk_i       => i_clk      	,	--in  std_ulogic; -- global clock line
			rstn_i      => i_rstn     	,	--in  std_ulogic; -- global reset line, low-active, async
			bus_req_i   => s_bus_req  	,	--in  bus_req_t;  -- bus request
			bus_rsp_o   => s_bus_rsp	,	--out bus_rsp_t;  -- bus response
			clkgen_en_o => open			,	--out std_ulogic; -- enable clock generator
			clkgen_i    => std_ulogic_vector(s_clkgen),	--in  std_ulogic_vector(7 downto 0);
			uart_txd_o  => o_txd 		,	--out std_ulogic; -- serial TX line
			uart_rxd_i  => i_rxd		,	--in  std_ulogic; -- serial RX line
			uart_rts_o  => s_uart_rtsn	,	--out std_ulogic; -- UART.RX ready to receive ("RTR"), low-active, optional
			uart_cts_i  => s_uart_ctsn	,	--in  std_ulogic; -- UART.TX allowed to transmit, low-active, optional
			irq_rx_o    => o_irq_rx   	,	--out std_ulogic; -- RX interrupt
			irq_tx_o    => o_irq_tx   		--out std_ulogic  -- TX interrupt
		);

	-- bus_rsp_o data/control registered signals
	p_data_rx: process(i_rstn, i_clk)
	begin
		if (i_rstn = '0') then
			o_data_rx <= (others => '0');
		elsif rising_edge(i_clk) then
		
			if i_ctrl1_data0 = '0' and s_bus_rsp.ack = '1' then
				o_data_rx <= unsigned(s_bus_rsp.data(7 downto 0));
			end if;
			
			if i_ctrl1_data0 = '1' and s_bus_rsp.ack = '1' then
				o_UART_CTRL_RX_NEMPTY		<= s_bus_rsp.data(16);	-- s_ctrlreg_data(16)	<= '0';	-- 	r/-	RX FIFO not empty		
				o_UART_CTRL_RX_HALF			<= s_bus_rsp.data(17);	-- s_ctrlreg_data(17)	<= '0';	-- 	r/-	RX FIFO at least half-full		
				o_UART_CTRL_RX_FULL			<= s_bus_rsp.data(18);	-- s_ctrlreg_data(18)	<= '0';	-- 	r/-	RX FIFO full		
				o_UART_CTRL_TX_EMPTY		<= s_bus_rsp.data(19);	-- s_ctrlreg_data(19)	<= '0';	-- 	r/-	TX FIFO empty		
				o_UART_CTRL_TX_NHALF		<= s_bus_rsp.data(20);	-- s_ctrlreg_data(20)	<= '0';	-- 	r/-	TX FIFO not at least half-full		
				o_UART_CTRL_TX_FULL			<= s_bus_rsp.data(21);	-- s_ctrlreg_data(21)	<= '0';	-- 	r/-	TX FIFO full		
				o_UART_CTRL_IRQ_RX_NEMPTY	<= s_bus_rsp.data(22);	-- s_ctrlreg_data(22)	<= '0';	-- 	r/w	fire IRQ if RX FIFO not empty		
				o_UART_CTRL_IRQ_RX_HALF		<= s_bus_rsp.data(23);	-- s_ctrlreg_data(23)	<= '0';	-- 	r/w	fire IRQ if RX FIFO at least half-full		
				o_UART_CTRL_IRQ_RX_FULL		<= s_bus_rsp.data(24);	-- s_ctrlreg_data(24)	<= '0';	-- 	r/w	fire IRQ if RX FIFO full		
				o_UART_CTRL_IRQ_TX_EMPTY	<= s_bus_rsp.data(25);	-- s_ctrlreg_data(25)	<= '0';	-- 	r/w	fire IRQ if TX FIFO empty		
				o_UART_CTRL_IRQ_TX_NHALF	<= s_bus_rsp.data(26);	-- s_ctrlreg_data(26)	<= '0';	-- 	r/w	fire IRQ if TX not at least half full		
				--o_-						<= s_bus_rsp.data(27);	-- s_ctrlreg_data(27)	<= '0';	-- 	r/-	reserved read as zero		
				o_UART_CTRL_RX_CLR			<= s_bus_rsp.data(28);	-- s_ctrlreg_data(28)	<= '0';	-- 	r/w	Clear RX FIFO, flag auto-clears		
				o_UART_CTRL_TX_CLR			<= s_bus_rsp.data(29);	-- s_ctrlreg_data(29)	<= '0';	-- 	r/w	Clear TX FIFO, flag auto-clears		
				o_UART_CTRL_RX_OVER			<= s_bus_rsp.data(30);	-- s_ctrlreg_data(30)	<= '0';	-- 	r/-	RX FIFO overflow; cleared by disabling the module		
				o_UART_CTRL_TX_BUSY			<= s_bus_rsp.data(31);	-- s_ctrlreg_data(31)	<= '0';	-- 	r/-	TX busy or TX FIFO not empty		
			end if;
			
		end if;
	end process p_data_rx;

end rtl;
