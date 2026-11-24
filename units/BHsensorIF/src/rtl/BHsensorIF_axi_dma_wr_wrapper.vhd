--#####################################################################
-- Company 		: B-Horizon GmbH
-- Engineer 	: JSchmid
-- File			: BHsensorIF_axi_dma_wr_wrapper.vhd
-- Design Name 	: FPGA
-- Module Name 	: BHsensorIF_axi_dma_wr_wrapper
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

--library axi4;

entity BHsensorIF_axi_dma_wr_wrapper is
    generic (
        AXI_DATA_WIDTH        : integer := 32;
        AXI_ADDR_WIDTH        : integer := 32;
        AXI_STRB_WIDTH        : integer := 32/8;
        AXI_ID_WIDTH          : integer := 8;
        AXI_MAX_BURST_LEN     : integer := 16;
        AXIS_DATA_WIDTH       : integer := 32;
        --AXIS_KEEP_ENABLE      : integer := (32 > 8);
        AXIS_KEEP_ENABLE      : integer := 1;
        AXIS_KEEP_WIDTH       : integer := 32/8;
        AXIS_LAST_ENABLE      : integer := 1;
        AXIS_ID_ENABLE        : integer := 0;
        AXIS_ID_WIDTH         : integer := 8;
        AXIS_DEST_ENABLE      : integer := 0;
        AXIS_DEST_WIDTH       : integer := 8;
        AXIS_USER_ENABLE      : integer := 1;
        AXIS_USER_WIDTH       : integer := 1;
        LEN_WIDTH             : integer := 20;
        TAG_WIDTH             : integer := 8;
        ENABLE_SG             : integer := 0;
        ENABLE_UNALIGNED      : integer := 0
    );
    port (

        clk   : in  std_logic;
        rst   : in  std_logic;

        -- descriptor input
        s_axis_write_desc_addr  : in  std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        s_axis_write_desc_len   : in  std_logic_vector(LEN_WIDTH-1 downto 0);
        s_axis_write_desc_tag   : in  std_logic_vector(TAG_WIDTH-1 downto 0);
        s_axis_write_desc_valid : in  std_logic;
        s_axis_write_desc_ready : out std_logic;

        -- descriptor status output
        m_axis_write_desc_status_len   : out std_logic_vector(LEN_WIDTH-1 downto 0);
        m_axis_write_desc_status_tag   : out std_logic_vector(TAG_WIDTH-1 downto 0);
        m_axis_write_desc_status_id    : out std_logic_vector(AXIS_ID_WIDTH-1 downto 0);
        m_axis_write_desc_status_dest  : out std_logic_vector(AXIS_DEST_WIDTH-1 downto 0);
        m_axis_write_desc_status_user  : out std_logic_vector(AXIS_USER_WIDTH-1 downto 0);
        m_axis_write_desc_status_error : out std_logic_vector(3 downto 0);
        m_axis_write_desc_status_valid : out std_logic;

        -- AXIS stream write input
        s_axis_write_data_tdata  : in  std_logic_vector(AXIS_DATA_WIDTH-1 downto 0);
        s_axis_write_data_tkeep  : in  std_logic_vector(AXIS_KEEP_WIDTH-1 downto 0);
        s_axis_write_data_tvalid : in  std_logic;
        s_axis_write_data_tready : out std_logic;
        s_axis_write_data_tlast  : in  std_logic;
        s_axis_write_data_tid    : in  std_logic_vector(AXIS_ID_WIDTH-1 downto 0);
        s_axis_write_data_tdest  : in  std_logic_vector(AXIS_DEST_WIDTH-1 downto 0);
        s_axis_write_data_tuser  : in  std_logic_vector(AXIS_USER_WIDTH-1 downto 0);

        -- AXI master interface
        m_axi_awid    : out std_logic_vector(AXI_ID_WIDTH-1 downto 0);
        m_axi_awaddr  : out std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        m_axi_awlen   : out std_logic_vector(7 downto 0);
        m_axi_awsize  : out std_logic_vector(2 downto 0);
        m_axi_awburst : out std_logic_vector(1 downto 0);
        m_axi_awlock  : out std_logic;
        m_axi_awcache : out std_logic_vector(3 downto 0);
        m_axi_awprot  : out std_logic_vector(2 downto 0);
        m_axi_awvalid : out std_logic;
        m_axi_awready : in  std_logic;

        m_axi_wdata   : out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);
        m_axi_wstrb   : out std_logic_vector(AXI_STRB_WIDTH-1 downto 0);
        m_axi_wlast   : out std_logic;
        m_axi_wvalid  : out std_logic;
        m_axi_wready  : in  std_logic;

        m_axi_bid     : in  std_logic;
        m_axi_bresp   : in  std_logic_vector(1 downto 0);
        m_axi_bvalid  : in  std_logic;
        m_axi_bready  : out std_logic;

        -- configuration
        enable : in std_logic;
        abort  : in std_logic
    );
end entity BHsensorIF_axi_dma_wr_wrapper;


-----------------------------------------------------------------------
-- Architecture: Instantiates Verilog module
-----------------------------------------------------------------------
architecture rtl of BHsensorIF_axi_dma_wr_wrapper is

component BHsensorIF_axi_dma_wr
  generic (
    AXI_DATA_WIDTH    : integer;
    AXI_ADDR_WIDTH    : integer;
    AXI_STRB_WIDTH    : integer;
    AXI_ID_WIDTH      : integer;
    AXI_MAX_BURST_LEN : integer;
    AXIS_DATA_WIDTH   : integer;
    AXIS_KEEP_ENABLE  : integer;
    AXIS_KEEP_WIDTH   : integer;
    AXIS_LAST_ENABLE  : integer;
    AXIS_ID_ENABLE    : integer;
    AXIS_ID_WIDTH     : integer;
    AXIS_DEST_ENABLE  : integer;
    AXIS_DEST_WIDTH   : integer;
    AXIS_USER_ENABLE  : integer;
    AXIS_USER_WIDTH   : integer;
    LEN_WIDTH         : integer;
    TAG_WIDTH         : integer;
    ENABLE_SG         : integer;
    ENABLE_UNALIGNED  : integer
  );
  port (
    clk : in std_logic;
    rst : in std_logic;

    s_axis_write_desc_addr  : in  std_logic_Vector(AXI_DATA_WIDTH-1 downto 0);
    s_axis_write_desc_len   : in  std_logic_vector(LEN_WIDTH-1 downto 0);
    s_axis_write_desc_tag   : in  std_logic_vector(TAG_WIDTH-1 downto 0);
    s_axis_write_desc_valid : in  std_logic;
    s_axis_write_desc_ready : out std_logic;

    m_axis_write_desc_status_len   : out std_logic_vector(LEN_WIDTH-1 downto 0);
    m_axis_write_desc_status_tag   : out std_logic_vector(TAG_WIDTH-1 downto 0);
    m_axis_write_desc_status_id    : out std_logic_vector(AXIS_ID_WIDTH-1 downto 0);
    m_axis_write_desc_status_dest  : out std_logic_vector(AXIS_DEST_WIDTH-1 downto 0);
    m_axis_write_desc_status_user  : out std_logic_vector(AXIS_USER_WIDTH-1 downto 0);
    m_axis_write_desc_status_error : out std_logic_vector(3 downto 0);
    m_axis_write_desc_status_valid : out std_logic;

    s_axis_write_data_tdata  : in  std_logic_vector(AXIS_DATA_WIDTH-1 downto 0);
    s_axis_write_data_tkeep  : in  std_logic_vector(AXIS_KEEP_WIDTH-1 downto 0);
    s_axis_write_data_tvalid : in  std_logic;
    s_axis_write_data_tready : out std_logic;
    s_axis_write_data_tlast  : in  std_logic;
    s_axis_write_data_tid    : in  std_logic_vector(AXIS_ID_WIDTH-1 downto 0);
    s_axis_write_data_tdest  : in  std_logic_vector(AXIS_DEST_WIDTH-1 downto 0);
    s_axis_write_data_tuser  : in  std_logic_vector(AXIS_USER_WIDTH-1 downto 0);

    m_axi_awid    : out std_logic_vector(AXI_ID_WIDTH-1 downto 0);
    m_axi_awaddr  : out std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
    m_axi_awlen   : out std_logic_vector(7 downto 0);
    m_axi_awsize  : out std_logic_vector(2 downto 0);
    m_axi_awburst : out std_logic_vector(1 downto 0);
    m_axi_awlock  : out std_logic;
    m_axi_awcache : out std_logic_vector(3 downto 0);
    m_axi_awprot  : out std_logic_vector(2 downto 0);
    m_axi_awvalid : out std_logic;
    m_axi_awready : in  std_logic;

    m_axi_wdata  : out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);
    m_axi_wstrb  : out std_logic_vector(AXI_STRB_WIDTH-1 downto 0);
    m_axi_wlast  : out std_logic;
    m_axi_wvalid : out std_logic;
    m_axi_wready : in  std_logic;

    m_axi_bid    : in  std_logic_vector(AXI_ID_WIDTH-1 downto 0);
    m_axi_bresp  : in  std_logic_vector(1 downto 0);
    m_axi_bvalid : in  std_logic;
    m_axi_bready : out std_logic;

    enable : in std_logic;
    abort  : in std_logic
  );
  end component;


    signal s_m_axi_awaddr  : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);	--fix

begin

    --m_axi_awaddr  <= '0' & s_m_axi_awaddr(30 downto 0);	-- fix?
    m_axi_awaddr  <= s_m_axi_awaddr(31 downto 0);

    axi_dma_wr_inst : BHsensorIF_axi_dma_wr
        generic map (
            AXI_DATA_WIDTH    => AXI_DATA_WIDTH,
            AXI_ADDR_WIDTH    => AXI_ADDR_WIDTH,
            AXI_STRB_WIDTH    => AXI_STRB_WIDTH,
            AXI_ID_WIDTH      => AXI_ID_WIDTH,
            AXI_MAX_BURST_LEN => AXI_MAX_BURST_LEN,
            AXIS_DATA_WIDTH   => AXIS_DATA_WIDTH,
            AXIS_KEEP_ENABLE  => AXIS_KEEP_ENABLE,
            AXIS_KEEP_WIDTH   => AXIS_KEEP_WIDTH,
            AXIS_LAST_ENABLE  => AXIS_LAST_ENABLE,
            AXIS_ID_ENABLE    => AXIS_ID_ENABLE,
            AXIS_ID_WIDTH     => AXIS_ID_WIDTH,
            AXIS_DEST_ENABLE  => AXIS_DEST_ENABLE,
            AXIS_DEST_WIDTH   => AXIS_DEST_WIDTH,
            AXIS_USER_ENABLE  => AXIS_USER_ENABLE,
            AXIS_USER_WIDTH   => AXIS_USER_WIDTH,
            LEN_WIDTH         => LEN_WIDTH,
            TAG_WIDTH         => TAG_WIDTH,
            ENABLE_SG         => ENABLE_SG,
            ENABLE_UNALIGNED  => ENABLE_UNALIGNED
        )
        port map (
            clk => clk,
            rst => rst,

            s_axis_write_desc_addr  => s_axis_write_desc_addr,
            s_axis_write_desc_len   => s_axis_write_desc_len,
            s_axis_write_desc_tag   => s_axis_write_desc_tag,
            s_axis_write_desc_valid => s_axis_write_desc_valid,
            s_axis_write_desc_ready => s_axis_write_desc_ready,

            m_axis_write_desc_status_len   => m_axis_write_desc_status_len,
            m_axis_write_desc_status_tag   => m_axis_write_desc_status_tag,
            m_axis_write_desc_status_id    => m_axis_write_desc_status_id,
            m_axis_write_desc_status_dest  => m_axis_write_desc_status_dest,
            m_axis_write_desc_status_user  => m_axis_write_desc_status_user,
            m_axis_write_desc_status_error => m_axis_write_desc_status_error,
            m_axis_write_desc_status_valid => m_axis_write_desc_status_valid,

            s_axis_write_data_tdata  => s_axis_write_data_tdata,
            s_axis_write_data_tkeep  => s_axis_write_data_tkeep,
            s_axis_write_data_tvalid => s_axis_write_data_tvalid,
            s_axis_write_data_tready => s_axis_write_data_tready,
            s_axis_write_data_tlast  => s_axis_write_data_tlast,
            s_axis_write_data_tid    => s_axis_write_data_tid,
            s_axis_write_data_tdest  => s_axis_write_data_tdest,
            s_axis_write_data_tuser  => s_axis_write_data_tuser,

            m_axi_awid    => m_axi_awid,
            m_axi_awaddr  => s_m_axi_awaddr,
            m_axi_awlen   => m_axi_awlen,
            m_axi_awsize  => m_axi_awsize,
            m_axi_awburst => m_axi_awburst,
            m_axi_awlock  => m_axi_awlock,
            m_axi_awcache => m_axi_awcache,
            m_axi_awprot  => m_axi_awprot,
            m_axi_awvalid => m_axi_awvalid,
            m_axi_awready => m_axi_awready,

            m_axi_wdata  => m_axi_wdata,
            m_axi_wstrb  => m_axi_wstrb,
            m_axi_wlast  => m_axi_wlast,
            m_axi_wvalid => m_axi_wvalid,
            m_axi_wready => m_axi_wready,

            m_axi_bid    => (others => m_axi_bid),
            m_axi_bresp  => m_axi_bresp,
            m_axi_bvalid => m_axi_bvalid,
            m_axi_bready => m_axi_bready,

            enable => enable,
            abort  => abort
        );

end architecture rtl;
