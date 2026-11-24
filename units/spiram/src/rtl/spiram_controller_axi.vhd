-- ================================================================================ --
-- Simple SPI RAM Controller with AXI4-Lite Interfaces                               --
-- -------------------------------------------------------------------------------- --
-- Copyright (c) 2026 DI-OWAS Project, S. Nolting, Fraunhofer IMS.                  --
-- SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1                                 --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity spiram_controller_axi is
  port (
    -- global control --
    resetn         : in  std_ulogic;
    clk            : in  std_ulogic;
    -- AXI4-lite configuration port --
    s0_axi_awaddr  : in  std_ulogic_vector(31 downto 0);
    s0_axi_awprot  : in  std_ulogic_vector(2 downto 0);
    s0_axi_awvalid : in  std_ulogic;
    s0_axi_awready : out std_ulogic;
    s0_axi_wdata   : in  std_ulogic_vector(31 downto 0);
    s0_axi_wstrb   : in  std_ulogic_vector(3 downto 0);
    s0_axi_wvalid  : in  std_ulogic;
    s0_axi_wready  : out std_ulogic;
    s0_axi_araddr  : in  std_ulogic_vector(31 downto 0);
    s0_axi_arprot  : in  std_ulogic_vector(2 downto 0);
    s0_axi_arvalid : in  std_ulogic;
    s0_axi_arready : out std_ulogic;
    s0_axi_rdata   : out std_ulogic_vector(31 downto 0);
    s0_axi_rresp   : out std_ulogic_vector(1 downto 0);
    s0_axi_rvalid  : out std_ulogic;
    s0_axi_rready  : in  std_ulogic;
    s0_axi_bresp   : out std_ulogic_vector(1 downto 0);
    s0_axi_bvalid  : out std_ulogic;
    s0_axi_bready  : in  std_ulogic;
    -- AXI4-lite data port --
    s1_axi_awaddr  : in  std_ulogic_vector(31 downto 0);
    s1_axi_awprot  : in  std_ulogic_vector(2 downto 0);
    s1_axi_awvalid : in  std_ulogic;
    s1_axi_awready : out std_ulogic;
    s1_axi_wdata   : in  std_ulogic_vector(31 downto 0);
    s1_axi_wstrb   : in  std_ulogic_vector(3 downto 0);
    s1_axi_wvalid  : in  std_ulogic;
    s1_axi_wready  : out std_ulogic;
    s1_axi_araddr  : in  std_ulogic_vector(31 downto 0);
    s1_axi_arprot  : in  std_ulogic_vector(2 downto 0);
    s1_axi_arvalid : in  std_ulogic;
    s1_axi_arready : out std_ulogic;
    s1_axi_rdata   : out std_ulogic_vector(31 downto 0);
    s1_axi_rresp   : out std_ulogic_vector(1 downto 0);
    s1_axi_rvalid  : out std_ulogic;
    s1_axi_rready  : in  std_ulogic;
    s1_axi_bresp   : out std_ulogic_vector(1 downto 0);
    s1_axi_bvalid  : out std_ulogic;
    s1_axi_bready  : in  std_ulogic;
    -- SPI RAM --
    spi_clk_o     : out std_ulogic;
    spi_csn_o     : out std_ulogic_vector(1 downto 0);
    spi_di_i      : in  std_ulogic;
    spi_do_o      : out std_ulogic
  );
end;

architecture spiram_controller_axi_rtl of spiram_controller_axi is

  component axilite2wishbone
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
  end component;

  component neorv32_smc
  generic (
    BURST_EN   : boolean;                       -- enable burst support
    BURST_SIZE : natural range 4 to 1024;       -- burst size in bytes, has to be a power of 2
    MEM_BASE   : std_ulogic_vector(31 downto 0) -- serial memory base address (256MB-aligned)
  );
  port (
    -- global control --
    clk_i      : in  std_ulogic;                    -- global clock line
    rstn_i     : in  std_ulogic;                    -- global reset line, low-active, async
    -- control and status register interface --
    ctrl_req_i : in  bus_req_t;                     -- bus request
    ctrl_rsp_o : out bus_rsp_t;                     -- bus response
    -- data interface --
    data_req_i : in  bus_req_t;                     -- bus request
    data_rsp_o : out bus_rsp_t;                     -- bus response
    -- serial memory interface --
    smc_ioen_o : out std_ulogic;                    -- SMC pin enable, can be used for IO multiplexing
    smc_sck_o  : out std_ulogic;                    -- clock
    smc_csn_o  : out std_ulogic_vector(1 downto 0); -- bank/chip select, low-active
    smc_sdo_o  : out std_ulogic;                    -- serial data output
    smc_sdi_i  : in  std_ulogic                     -- serial data input
  );
  end component;

  signal neo_ctrl_req, neo_data_req : bus_req_t;
  signal neo_ctrl_rsp, neo_data_rsp : bus_rsp_t;

begin

  -- Control and Status Register Interface --------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  axilite2wishbone_ctrl_inst: axilite2wishbone
  port map (
    -- global control --
    resetn        => resetn,
    clk           => clk,
    -- AXI4-lite interface device port --
    s_axi_awaddr  => s0_axi_awaddr,
    s_axi_awprot  => s0_axi_awprot,
    s_axi_awvalid => s0_axi_awvalid,
    s_axi_awready => s0_axi_awready,
    s_axi_wdata   => s0_axi_wdata,
    s_axi_wstrb   => s0_axi_wstrb,
    s_axi_wvalid  => s0_axi_wvalid,
    s_axi_wready  => s0_axi_wready,
    s_axi_araddr  => s0_axi_araddr,
    s_axi_arprot  => s0_axi_arprot,
    s_axi_arvalid => s0_axi_arvalid,
    s_axi_arready => s0_axi_arready,
    s_axi_rdata   => s0_axi_rdata,
    s_axi_rresp   => s0_axi_rresp,
    s_axi_rvalid  => s0_axi_rvalid,
    s_axi_rready  => s0_axi_rready,
    s_axi_bresp   => s0_axi_bresp,
    s_axi_bvalid  => s0_axi_bvalid,
    s_axi_bready  => s0_axi_bready,
    -- Wishbone host port --
    wb_cyc_o      => open,
    wb_stb_o      => neo_ctrl_req.stb,
    wb_rw_o       => neo_ctrl_req.rw,
    wb_prot_o     => open,
    wb_ben_o      => neo_ctrl_req.ben,
    wb_addr_o     => neo_ctrl_req.addr,
    wb_data_o     => neo_ctrl_req.data,
    wb_data_i     => neo_ctrl_rsp.data,
    wb_ack_i      => neo_ctrl_rsp.ack,
    wb_err_i      => '0'
  );

  neo_ctrl_req.meta  <= (others => '0');
  neo_ctrl_req.amo   <= '0';
  neo_ctrl_req.amoop <= (others => '0');
  neo_ctrl_req.burst <= '0';
  neo_ctrl_req.lock  <= '0';
  

  -- PSRAM Data Interface -------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  axilite2wishbone_data_inst: axilite2wishbone
  port map (
    -- global control --
    resetn        => resetn,
    clk           => clk,
    -- AXI4-lite interface device port --
    s_axi_awaddr  => s1_axi_awaddr,
    s_axi_awprot  => s1_axi_awprot,
    s_axi_awvalid => s1_axi_awvalid,
    s_axi_awready => s1_axi_awready,
    s_axi_wdata   => s1_axi_wdata,
    s_axi_wstrb   => s1_axi_wstrb,
    s_axi_wvalid  => s1_axi_wvalid,
    s_axi_wready  => s1_axi_wready,
    s_axi_araddr  => s1_axi_araddr,
    s_axi_arprot  => s1_axi_arprot,
    s_axi_arvalid => s1_axi_arvalid,
    s_axi_arready => s1_axi_arready,
    s_axi_rdata   => s1_axi_rdata,
    s_axi_rresp   => s1_axi_rresp,
    s_axi_rvalid  => s1_axi_rvalid,
    s_axi_rready  => s1_axi_rready,
    s_axi_bresp   => s1_axi_bresp,
    s_axi_bvalid  => s1_axi_bvalid,
    s_axi_bready  => s1_axi_bready,
    -- Wishbone host port --
    wb_cyc_o      => open,
    wb_stb_o      => neo_data_req.stb,
    wb_rw_o       => neo_data_req.rw,
    wb_prot_o     => open,
    wb_ben_o      => neo_data_req.ben,
    wb_addr_o     => neo_data_req.addr,
    wb_data_o     => neo_data_req.data,
    wb_data_i     => neo_data_rsp.data,
    wb_ack_i      => neo_data_rsp.ack,
    wb_err_i      => '0'
  );

  neo_data_req.meta  <= (others => '0');
  neo_data_req.amo   <= '0';
  neo_data_req.amoop <= (others => '0');
  neo_data_req.burst <= '0';
  neo_data_req.lock  <= '0';

  -- SPI-RAM Controller ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  spi_controller_inst: neorv32_smc
  generic map (
    BURST_EN   => false,
    BURST_SIZE => 4,
    MEM_BASE   => x"00000000"
  )
  port map (
    -- global control --
    clk_i      => clk,                 
    rstn_i     => resetn,                 
    -- control and status register interface --
    ctrl_req_i => neo_ctrl_req,                  
    ctrl_rsp_o => neo_ctrl_rsp,                  
    -- data interface --
    data_req_i => neo_data_req,                  
    data_rsp_o => neo_data_rsp,                  
    -- serial memory interface --
    smc_ioen_o => open,
    smc_sck_o  => spi_clk_o,
    smc_csn_o  => spi_csn_o,
    smc_sdo_o  => spi_do_o,
    smc_sdi_i  => spi_di_i
  );

end;
