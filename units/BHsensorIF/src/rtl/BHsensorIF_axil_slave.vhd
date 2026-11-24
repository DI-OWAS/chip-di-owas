--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: JSchmid
-- File			: BHsensorIF_axil_slave.vhd
-- Design Name 	: FPGA
-- Module Name 	: BHsensorIF_axil_slave
-- Project Name : DI-OWAS
-- Create Date 	: 6.2.2026
-- Last Change 	: $Id $
-- Description 	: 
-- Dependencies : n.a.
-- Revision 	: 0.1
-- Comments 	: 
--######################################################################
-- Copyright 2024-2026, B-Horizon GmbH, All Rights Reserved
--######################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.BHsensorIF_pkg.all;

entity BHsensorIF_axil_slave is
    port (
        -- Global
        i_clk      : in  std_logic;
        i_rstn     : in  std_logic;

        -- AXI-Lite Write Address
        i_awaddr   : in  std_logic_vector(31 downto 0);
        i_awvalid  : in  std_logic;
        o_awready  : out std_logic;

        -- AXI-Lite Write Data
        i_wdata    : in  std_logic_vector(31 downto 0);
        i_wstrb    : in  std_logic_vector(3 downto 0);
        i_wvalid   : in  std_logic;
        o_wready   : out std_logic;

        -- AXI-Lite Write Response
        o_bresp    : out std_logic_vector(1 downto 0);
        o_bvalid   : out std_logic;
        i_bready   : in  std_logic;

        -- AXI-Lite Read Address
        i_araddr   : in  std_logic_vector(31 downto 0);
        i_arvalid  : in  std_logic;
        o_arready  : out std_logic;

        -- AXI-Lite Read Data
        o_rdata    : out std_logic_vector(31 downto 0);
        o_rresp    : out std_logic_vector(1 downto 0);
        o_rvalid   : out std_logic;
        i_rready   : in  std_logic;

        -- User I/O
        i_ro_data  : in  std_logic_vector(63 downto 0);       -- 8×8b
        o_wo_data  : out std_logic_vector(6*32-1 downto 0)    -- 6×32b = 192b
    );
end entity;

	-- constant c_axi_bh_thres0 : unsigned(7 downto 0) := x"00";
	-- constant c_axi_bh_thres1 : unsigned(7 downto 0) := x"00";
	-- constant c_axi_bh_thres2 : unsigned(7 downto 0) := x"00";	

architecture rtl of BHsensorIF_axil_slave is

    -- Adress-Ausrichtung (AXI-Lite 32 Bit)
    constant C_ADDR_LSB : integer := 2;

    -- Basis (Word-Index = Byte-Adresse >> 2)		TBD
    -- constant C_RO_BASE  : integer := 16#4000# / 4;  -- 0x4000 >> 2
    -- constant C_WO_BASE  : integer := 16#8000# / 4;  -- 0x8000 >> 2

    --Default-Resetwerte der 6 WO-Register (anpassbar)
    constant C_WO0_RESET : std_logic_vector(31 downto 0) := x"0000_0000";	-- cts inactive
	--
    constant C_WO1_RESET : std_logic_vector(31 downto 0) := b"0000_0000" & 
															b"0000_0" & c_UART_CTRL_PRSC2 & 
															b"0000_00" &  c_UART_CTRL_BAUD9;    
	--
    constant C_WO2_RESET : std_logic_vector(31 downto 0) := x"0000_0000";
    constant C_WO3_RESET : std_logic_vector(31 downto 0) := x"0000_0000";

    -- Interne Register
    type t_reg8   is array (0 to 7) of std_logic_vector(7 downto 0);
    type t_reg32  is array (0 to 5) of std_logic_vector(31 downto 0);

    signal s_ro_reg   : t_reg8;
    signal s_wo_reg32 : t_reg32 := (
        0 => C_WO0_RESET,
        1 => C_WO1_RESET,
        2 => C_WO2_RESET,
        3 => C_WO3_RESET,
        4 => std_logic_vector(c_base_addr),
        5 => std_logic_vector(to_unsigned(c_store_frames,32))
    );

    -- AXI Steuerung
    signal s_awready     : std_logic := '0';
    signal s_wready      : std_logic := '0';
    signal s_bvalid      : std_logic := '0';
    signal s_aw_captured : std_logic := '0';
    signal s_w_captured  : std_logic := '0';

    signal s_saved_awaddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_saved_wdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_saved_wstrb  : std_logic_vector(3 downto 0)  := (others => '0');

    signal s_arready : std_logic := '0';
    signal s_rvalid  : std_logic := '0';
    signal s_rdata   : std_logic_vector(31 downto 0) := (others => '0');

begin
    -- AXI Outputs
    o_awready <= s_awready;
    o_wready  <= s_wready;
    o_bresp   <= "00";         -- OKAY
    o_bvalid  <= s_bvalid;

    o_arready <= s_arready;
    o_rresp   <= "00";         -- OKAY
    o_rvalid  <= s_rvalid;
    o_rdata   <= s_rdata;

    -- RO entpacken (Input → intern)
    gen_ro : for i in 0 to 7 generate
        s_ro_reg(i) <= i_ro_data((i+1)*8-1 downto i*8);
    end generate;

    -- WO bündeln (intern → Ausgang)
    gen_wo_pack : for i in 0 to 5 generate
        o_wo_data((i+1)*32-1 downto i*32) <= s_wo_reg32(i);
    end generate;

    --------------------------------------------------------------------
    -- AXI Hauptprozess
    --------------------------------------------------------------------
    process(i_clk, i_rstn)
        variable v_idx  : integer;
        variable v_wi   : integer;
        variable v_old  : std_logic_vector(31 downto 0);
        variable v_new  : std_logic_vector(31 downto 0);
    begin
            if i_rstn = '0' then
                -- Write
                s_awready      <= '0';
                s_wready       <= '0';
                s_bvalid       <= '0';
                s_aw_captured  <= '0';
                s_w_captured   <= '0';
                s_saved_awaddr <= (others => '0');
                s_saved_wdata  <= (others => '0');
                s_saved_wstrb  <= (others => '0');

                -- Read
                s_arready <= '0';
                s_rvalid  <= '0';
                s_rdata   <= (others => '0');

                -- WO Resetdefault
                s_wo_reg32(0) <= C_WO0_RESET;
                s_wo_reg32(1) <= C_WO1_RESET;
                s_wo_reg32(2) <= C_WO2_RESET;
                s_wo_reg32(3) <= C_WO3_RESET;
                s_wo_reg32(4) <= std_logic_vector(c_base_addr);
                s_wo_reg32(5) <= std_logic_vector(to_unsigned(c_store_frames,32));

			elsif rising_edge(i_clk) then
                
				s_wo_reg32(0) <= (others => '0');		-- one shot irq_clear

                ----------------------------------------------------------------
                -- WRITE ADDRESS (AW) erfassen
                ----------------------------------------------------------------
                if (s_aw_captured = '0') and (s_bvalid = '0') then
                    s_awready <= '1';
                else
                    s_awready <= '0';
                end if;

                if (s_awready = '1') and (i_awvalid = '1') then
                    s_saved_awaddr <= i_awaddr;
                    s_aw_captured  <= '1';
                end if;

                ----------------------------------------------------------------
                -- WRITE DATA (W) erfassen
                ----------------------------------------------------------------
                if (s_w_captured = '0') and (s_bvalid = '0') then
                    s_wready <= '1';
                else
                    s_wready <= '0';
                end if;

                if (s_wready = '1') and (i_wvalid = '1') then
                    s_saved_wdata <= i_wdata;
                    s_saved_wstrb <= i_wstrb;
                    s_w_captured  <= '1';
                end if;

                ----------------------------------------------------------------
                -- WRITE ausführen (wenn AW & W erfasst)
                ----------------------------------------------------------------
                if (s_aw_captured = '1') and (s_w_captured = '1') and (s_bvalid = '0') then
                    --v_idx := to_integer(unsigned(s_saved_awaddr(31 downto C_ADDR_LSB)));
                    v_idx := to_integer(unsigned(s_saved_awaddr(15 downto C_ADDR_LSB)));	-- debug Stephan, ignore MSB/BaseAdress

                    if (v_idx >= C_WO_BASE) and (v_idx < C_WO_BASE + 6) then
                        v_wi  := v_idx - C_WO_BASE;       -- Wortindex 0..5
                        v_old := s_wo_reg32(v_wi);
                        v_new := v_old;

                        for b in 0 to 3 loop
                            if s_saved_wstrb(b) = '1' then
                                v_new(8*b+7 downto 8*b) := s_saved_wdata(8*b+7 downto 8*b);
                            end if;
                        end loop;

                        s_wo_reg32(v_wi) <= v_new;
                    end if;

                    s_bvalid <= '1';
                end if;

                -- Write Response quittieren
                if (s_bvalid = '1') and (i_bready = '1') then
                    s_bvalid      <= '0';
                    s_aw_captured <= '0';
                    s_w_captured  <= '0';
                end if;

                ----------------------------------------------------------------
                -- READ CHANNEL
                ----------------------------------------------------------------
                if (s_rvalid = '0') then
                    s_arready <= '1';
                else
                    s_arready <= '0';
                end if;

                if (i_arvalid = '1') and (s_arready = '1') then
                    v_idx := to_integer(unsigned(i_araddr(31 downto C_ADDR_LSB)));

                    if v_idx = C_RO_BASE then
                        s_rdata <= s_ro_reg(3) & s_ro_reg(2) & s_ro_reg(1) & s_ro_reg(0);
                    elsif v_idx = C_RO_BASE + 1 then
                        s_rdata <= s_ro_reg(7) & s_ro_reg(6) & s_ro_reg(5) & s_ro_reg(4);
					
					-- add RO-Registers to read decoder (RW)
					elsif (v_idx >= C_WO_BASE) and (v_idx < C_WO_BASE + 6) then
						s_rdata <= s_wo_reg32(v_idx - C_WO_BASE);

                    else
                        s_rdata <= (others => '0');
                    end if;

                    s_rvalid <= '1';
                end if;

                if (s_rvalid = '1') and (i_rready = '1') then
                    s_rvalid <= '0';
                end if;

            end if;
        
    end process;

end architecture;
