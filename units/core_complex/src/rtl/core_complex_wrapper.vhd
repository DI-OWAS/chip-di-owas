-- Copyright 2026 Fraunhofer Institute for Microelectronic Circuits and Systems (IMS), Duisburg, Germany.
-- SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
--
-- DI-OWAS Project
--
-- File     : core_complex_wrapper.vhd
-- Author   : S. Nolting
-- Creation : 19.09.2023
-- Abstract : processor wrapper for configuring the generics & AXI4-lite bridging

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity core_complex_wrapper is
  port (
    -- ------------------------------------------------------------
    -- Global Control
    -- ------------------------------------------------------------
    clk_i         : in  std_ulogic;
    rstn_i        : in  std_ulogic; -- low-active, async
    -- ------------------------------------------------------------
    -- AXI4-Lite-Compatible Host Interface
    -- ------------------------------------------------------------
    -- Write Address Channel --
    m_axi_awaddr  : out std_logic_vector(31 downto 0);
    m_axi_awlen   : out std_logic_vector(7 downto 0);
    m_axi_awsize  : out std_logic_vector(2 downto 0);
    m_axi_awburst : out std_logic_vector(1 downto 0);
    m_axi_awcache : out std_logic_vector(3 downto 0);
    m_axi_awprot  : out std_logic_vector(2 downto 0);
    m_axi_awvalid : out std_logic;
    m_axi_awready : in  std_logic;
    -- Write Data Channel --
    m_axi_wdata   : out std_logic_vector(31 downto 0);
    m_axi_wstrb   : out std_logic_vector(3 downto 0);
    m_axi_wlast   : out std_logic;
    m_axi_wvalid  : out std_logic;
    m_axi_wready  : in  std_logic;
    -- Read Address Channel --
    m_axi_araddr  : out std_logic_vector(31 downto 0);
    m_axi_arlen   : out std_logic_vector(7 downto 0);
    m_axi_arsize  : out std_logic_vector(2 downto 0);
    m_axi_arburst : out std_logic_vector(1 downto 0);
    m_axi_arcache : out std_logic_vector(3 downto 0);
    m_axi_arprot  : out std_logic_vector(2 downto 0);
    m_axi_arvalid : out std_logic;
    m_axi_arready : in  std_logic;
    -- Read Data Channel --
    m_axi_rdata   : in  std_logic_vector(31 downto 0);
    m_axi_rresp   : in  std_logic_vector(1 downto 0);
    m_axi_rlast   : in  std_logic;
    m_axi_rvalid  : in  std_logic;
    m_axi_rready  : out std_logic;
    -- Write Response Channel --
    m_axi_bresp   : in  std_logic_vector(1 downto 0);
    m_axi_bvalid  : in  std_logic;
    m_axi_bready  : out std_logic;
    -- ------------------------------------------------------------
    -- JTAG on-chip debugger interface
    -- ------------------------------------------------------------
    jtag_tck_i    : in  std_ulogic;
    jtag_tdi_i    : in  std_ulogic;
    jtag_tdo_o    : out std_ulogic;
    jtag_tms_i    : in  std_ulogic;
    -- ------------------------------------------------------------
    -- IO
    -- ------------------------------------------------------------
    -- SPI host --
    spi_csn_o     : out std_ulogic_vector(1 downto 0);
    spi_sck_o     : out std_ulogic;
    spi_sdo_o     : out std_ulogic;
    spi_sdi_i     : in  std_ulogic;
    -- I2C host --
    twi_scl_o     : out std_ulogic;
    twi_scl_i     : in  std_ulogic;
    twi_sda_o     : out std_ulogic;
    twi_sda_i     : in  std_ulogic;
    -- GPIO --
    status_led_o  : out std_ulogic;
    -- UART0 --
    console_txd_o : out std_ulogic;
    console_rxd_i : in  std_ulogic;
    -- ------------------------------------------------------------
    -- System reset control (low-active)
    -- ------------------------------------------------------------
    sys_resetn_o  : out std_ulogic_vector(15 downto 0);
    -- ------------------------------------------------------------
    -- Interrupts (via GPIO controller)
    -- ------------------------------------------------------------
    irq_i         : in  std_ulogic_vector(15 downto 0)
  );
end entity;

architecture core_complex_wrapper_rtl of core_complex_wrapper is

  -- internal configuration --
  constant cache_line_size_c : natural := 32; -- in bytes, has to be a power of two

  -- internal xbus --
  signal xbus_req : xbus_req_t;
  signal xbus_rsp : xbus_rsp_t;

  -- IO connection --
  signal gpio_o_con, gpio_i_con : std_ulogic_vector(31 downto 0);
  signal spi_csn : std_ulogic_vector(7 downto 0);
  signal cfs_out : std_ulogic_vector(255 downto 0);

begin

  -- The Core Of The Problem ----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    -- Processor Clocking --
    CLOCK_FREQUENCY     => 50_000_000, -- clockspeed of clk_i in Hz
    -- Boot Configuration --
    BOOT_MODE_SELECT    => 0, -- boot via built-in bootloader
    BOOT_ADDR_CUSTOM    => x"00000000",
    -- On-Chip Debugger --
    OCD_EN              => true,
    OCD_NUM_HW_TRIGGERS => 1,
    OCD_JEDEC_ID        => "11101000010",
    -- RISC-V CPU Extensions --
    RISCV_ISA_C         => true,
    RISCV_ISA_E         => true,
    RISCV_ISA_M         => true,
    RISCV_ISA_Zicntr    => true,
    -- Extension Options --
    CPU_FAST_SHIFT_EN   => false,
    CPU_RF_ARCH_SEL     => 1, -- use REGs with async read for register file
    -- CPU Caches --
    ICACHE_EN           => false,
    ICACHE_NUM_BLOCKS   => 16,
    DCACHE_EN           => false,
    DCACHE_NUM_BLOCKS   => 16,
    CACHE_BLOCK_SIZE    => cache_line_size_c,
    -- External bus interface --
    XBUS_EN             => true,
    XBUS_TIMEOUT        => 4096,
    XBUS_REGSTAGE_EN    => true,
    -- Processor peripherals --
    IO_GPIO_NUM         => 16,
    IO_CLINT_EN         => true,
    IO_UART0_EN         => true,
    IO_TWI_EN           => true,
    IO_TWI_FIFO         => 1,
    IO_SPI_EN           => true,
    IO_CFS_EN           => true
  )
  port map (
    -- Global control --
    clk_i       => clk_i,
    rstn_i      => rstn_i,
    -- JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) --
    jtag_tck_i  => jtag_tck_i,
    jtag_tdi_i  => jtag_tdi_i,
    jtag_tdo_o  => jtag_tdo_o,
    jtag_tms_i  => jtag_tms_i,
    -- External bus interface (available if XBUS_EN = true) --
    xbus_adr_o  => xbus_req.addr,
    xbus_dat_o  => xbus_req.data,
    xbus_cti_o  => xbus_req.cti,
    xbus_tag_o  => xbus_req.tag,
    xbus_we_o   => xbus_req.we,
    xbus_sel_o  => xbus_req.sel,
    xbus_stb_o  => xbus_req.stb,
    xbus_cyc_o  => xbus_req.cyc,
    xbus_dat_i  => xbus_rsp.data,
    xbus_ack_i  => xbus_rsp.ack,
    xbus_err_i  => xbus_rsp.err,
    -- GPIO (available if IO_GPIO_NUM > 0) --
    gpio_o      => gpio_o_con,
    gpio_i      => gpio_i_con,
    -- primary UART0 (available if IO_UART0_EN = true) --
    uart0_txd_o => console_txd_o,
    uart0_rxd_i => console_rxd_i,
    -- SPI (available if IO_SPI_EN = true) --
    spi_clk_o   => spi_sck_o,
    spi_dat_o   => spi_sdo_o,
    spi_dat_i   => spi_sdi_i,
    spi_csn_o   => spi_csn,
    -- TWI (available if IO_TWI_EN = true) --
    twi_sda_i   => twi_sda_i,
    twi_sda_o   => twi_sda_o,
    twi_scl_i   => twi_scl_i,
    twi_scl_o   => twi_scl_o,
    -- Custom functions subsystem IO (available if IO_CFS_EN = true) --
    cfs_in_i    => (others => '0'),
    cfs_out_o   => cfs_out
  );

  spi_csn_o <= spi_csn(1 downto 0);

  -- IO Wiring ------------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------

  -- CPU status LED --
  status_led_o <= gpio_o_con(0);

  -- system resets --
  sys_resetn_o <= cfs_out(15 downto 0);

  -- interrupts --
  gpio_i_con <= x"0000" & irq_i;

  -- Wishbone-to-AXI4-Lite Bridge -----------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  axi4_bridge_inst: entity neorv32.xbus2axi4_bridge
  generic map (
    BURST_EN  => false,
    BURST_LEN => cache_line_size_c
  )
  port map (
    -- Global control --
    clk           => clk_i,
    resetn        => rstn_i,
    -- XBUS device interface --
    xbus_req_i    => xbus_req,
    xbus_rsp_o    => xbus_rsp,
    -- AXI4 host write address channel --
    m_axi_awaddr  => m_axi_awaddr,
    m_axi_awlen   => m_axi_awlen ,
    m_axi_awsize  => m_axi_awsize,
    m_axi_awburst => m_axi_awburst,
    m_axi_awcache => m_axi_awcache,
    m_axi_awprot  => m_axi_awprot,
    m_axi_awvalid => m_axi_awvalid,
    m_axi_awready => m_axi_awready,
    -- AXI4 host write data channel --
    m_axi_wdata   => m_axi_wdata,
    m_axi_wstrb   => m_axi_wstrb,
    m_axi_wlast   => m_axi_wlast,
    m_axi_wvalid  => m_axi_wvalid,
    m_axi_wready  => m_axi_wready,
    -- AXI4 host read address channel --
    m_axi_araddr  => m_axi_araddr,
    m_axi_arlen   => m_axi_arlen,
    m_axi_arsize  => m_axi_arsize,
    m_axi_arburst => m_axi_arburst,
    m_axi_arcache => m_axi_arcache,
    m_axi_arprot  => m_axi_arprot,
    m_axi_arvalid => m_axi_arvalid,
    m_axi_arready => m_axi_arready,
    -- AXI4 host read data channel --
    m_axi_rdata   => m_axi_rdata,
    m_axi_rresp   => m_axi_rresp,
    m_axi_rlast   => m_axi_rlast,
    m_axi_rvalid  => m_axi_rvalid,
    m_axi_rready  => m_axi_rready,
    -- AXI4 host write response channel --
    m_axi_bresp   => m_axi_bresp,
    m_axi_bvalid  => m_axi_bvalid,
    m_axi_bready  => m_axi_bready
  );

end architecture;

