-- ================================================================================ --
-- AXI4-Lite to Wishbone Converter                                                  --
-- -------------------------------------------------------------------------------- --
-- Copyright (c) 2025 Stephan Nolting. All rights reserved.                         --
-- Licensed under the BSD-3-Clause license.                                         --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axilite2wishbone is
  port (
    -- global control --
    resetn        : in  std_ulogic;
    clk           : in  std_ulogic;
    -- AXI4-lite interface device port --
    s_axi_awaddr  : in  std_ulogic_vector(31 downto 0);
    s_axi_awprot  : in  std_ulogic_vector(2 downto 0);
    s_axi_awvalid : in  std_ulogic;
    s_axi_awready : out std_ulogic;
    s_axi_wdata   : in  std_ulogic_vector(31 downto 0);
    s_axi_wstrb   : in  std_ulogic_vector(3 downto 0);
    s_axi_wvalid  : in  std_ulogic;
    s_axi_wready  : out std_ulogic;
    s_axi_araddr  : in  std_ulogic_vector(31 downto 0);
    s_axi_arprot  : in  std_ulogic_vector(2 downto 0);
    s_axi_arvalid : in  std_ulogic;
    s_axi_arready : out std_ulogic;
    s_axi_rdata   : out std_ulogic_vector(31 downto 0);
    s_axi_rresp   : out std_ulogic_vector(1 downto 0);
    s_axi_rvalid  : out std_ulogic;
    s_axi_rready  : in  std_ulogic;
    s_axi_bresp   : out std_ulogic_vector(1 downto 0);
    s_axi_bvalid  : out std_ulogic;
    s_axi_bready  : in  std_ulogic;
    -- Wishbone host port --
    wb_cyc_o      : out std_ulogic;
    wb_stb_o      : out std_ulogic;
    wb_rw_o       : out std_ulogic;
    wb_prot_o     : out std_ulogic_vector(2 downto 0);
    wb_ben_o      : out std_ulogic_vector(3 downto 0);
    wb_addr_o     : out std_ulogic_vector(31 downto 0);
    wb_data_o     : out std_ulogic_vector(31 downto 0);
    wb_data_i     : in  std_ulogic_vector(31 downto 0);
    wb_ack_i      : in  std_ulogic;
    wb_err_i      : in  std_ulogic
  );
end axilite2wishbone;

architecture axilite2wishbone_rtl of axilite2wishbone is

  -- AXI handshake arbiter --
  type state_t is (S_IDLE, S_RPND, S_RRESP, S_WPND, S_WRESP);
  type arbiter_t is record
    state : state_t;
    ctrl  : std_ulogic_vector(2 downto 0);
    stb   : std_ulogic;
    rw    : std_ulogic;
    addr  : std_ulogic_vector(31 downto 0);
    rdata : std_ulogic_vector(31 downto 0);
    wdata : std_ulogic_vector(31 downto 0);
    ben   : std_ulogic_vector(3 downto 0);
    prot  : std_ulogic_vector(2 downto 0);
    err   : std_ulogic;
  end record;
  signal arbiter : arbiter_t;

begin

  -- AXI Handshake Arbiter ------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  axi_arbiter: process(resetn, clk)
  begin
    if (resetn = '0') then
      arbiter.state <= S_IDLE;
      arbiter.ctrl  <= (others => '0');
      arbiter.stb   <= '0';
      arbiter.rw    <= '0';
      arbiter.addr  <= (others => '0');
      arbiter.rdata <= (others => '0');
      arbiter.wdata <= (others => '0');
      arbiter.ben   <= (others => '0');
      arbiter.prot  <= (others => '0');
      arbiter.err   <= '0';
    elsif rising_edge(clk) then
      arbiter.stb <= '0';
      case arbiter.state is

        when S_IDLE => -- waiting for host request
          if (s_axi_awvalid = '1') then
            arbiter.addr    <= s_axi_awaddr;
            arbiter.prot    <= s_axi_awprot;
            arbiter.rw      <= '1';
            arbiter.ctrl(1) <= '1';
          elsif (s_axi_arvalid = '1') then
            arbiter.addr    <= s_axi_araddr;
            arbiter.prot    <= s_axi_arprot;
            arbiter.rw      <= '0';
            arbiter.ctrl(0) <= '1';
          end if;
          if (s_axi_wvalid = '1') then
            arbiter.wdata   <= s_axi_wdata;
            arbiter.ben     <= s_axi_wstrb;
            arbiter.ctrl(2) <= '1';
          end if;
          --
          if (arbiter.ctrl(2) = '1') and (arbiter.ctrl(1) = '1') then
            arbiter.stb   <= '1';
            arbiter.state <= S_WPND;
          elsif (arbiter.ctrl(0) = '1') then
            arbiter.stb   <= '1';
            arbiter.state <= S_RPND;
          end if;

        when S_RPND => -- pending read operation
          arbiter.ctrl  <= (others => '0');
          arbiter.rdata <= wb_data_i;
          arbiter.err   <= wb_err_i;
          if (wb_ack_i = '1') or (wb_err_i = '1') then
            arbiter.state <= S_RRESP;
          end if;

        when S_RRESP => -- read response
          if (s_axi_rready = '1') then
            arbiter.state <= S_IDLE;
          end if;

        when S_WPND => -- pending write operation
          arbiter.ctrl <= (others => '0');
          arbiter.err  <= wb_err_i;
          if (wb_ack_i = '1') or (wb_err_i = '1') then
            arbiter.state <= S_WRESP;
          end if;

        when S_WRESP => -- write response
          if (s_axi_bready = '1') then
            arbiter.state <= S_IDLE;
          end if;

        when others => -- undefined
          arbiter.state <= S_IDLE;

      end case;
    end if;
  end process axi_arbiter;


  -- AXI request channels --
  s_axi_awready <= '1' when (arbiter.state = S_IDLE) else '0';
  s_axi_arready <= '1' when (arbiter.state = S_IDLE) else '0';
  s_axi_wready  <= '1' when (arbiter.state = S_IDLE) else '0';

  -- AXI write response channel --
  s_axi_bresp  <= (arbiter.err & '0') when (arbiter.state = S_WRESP) else "00";
  s_axi_bvalid <= '1' when (arbiter.state = S_WRESP) else '0';

  -- AXI read response channel --
  s_axi_rdata  <= arbiter.rdata when (arbiter.state = S_RRESP) else (others => '0');
  s_axi_rresp  <= (arbiter.err & '0') when (arbiter.state = S_RRESP) else "00";
  s_axi_rvalid <= '1' when (arbiter.state = S_RRESP) else '0';

  -- register interface --
  wb_cyc_o  <= '0' when (arbiter.state = S_IDLE) else '1';
  wb_stb_o  <= arbiter.stb;
  wb_rw_o   <= arbiter.rw;
  wb_prot_o <= arbiter.prot;
  wb_addr_o <= arbiter.addr;
  wb_data_o <= arbiter.wdata;
  wb_ben_o  <= arbiter.ben;

end axilite2wishbone_rtl;
