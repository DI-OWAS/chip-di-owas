library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_BHsensorIF_axil_slave is
end;

architecture tb of tb_BHsensorIF_axil_slave is

  constant CLK_PERIOD : time := 10 ns;

  signal clk          : std_logic := '0';
  signal rstn         : std_logic := '0';

  -- AXI Write Address
  signal awaddr       : std_logic_vector(31 downto 0) := (others=>'0');
  signal awvalid      : std_logic := '0';
  signal awready      : std_logic;

  -- AXI Write Data
  signal wdata        : std_logic_vector(31 downto 0) := (others=>'0');
  signal wstrb        : std_logic_vector(3 downto 0) := (others=>'0');
  signal wvalid       : std_logic := '0';
  signal wready       : std_logic;

  -- AXI Write Response
  signal bresp        : std_logic_vector(1 downto 0);
  signal bvalid       : std_logic;
  signal bready       : std_logic := '0';

  -- AXI Read Address
  signal araddr       : std_logic_vector(31 downto 0) := (others=>'0');
  signal arvalid      : std_logic := '0';
  signal arready      : std_logic;

  -- AXI Read Data
  signal rdata        : std_logic_vector(31 downto 0);
  signal rresp        : std_logic_vector(1 downto 0);
  signal rvalid       : std_logic;
  signal rready       : std_logic := '0';

  -- User Data
  signal ro_data      : std_logic_vector(63 downto 0) := (others=>'0');
  signal wo_data      : std_logic_vector(63 downto 0);

begin

  ------------------------------------------------------------------
  -- Clock
  ------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  ------------------------------------------------------------------
  -- DUT
  ------------------------------------------------------------------
  dut : entity work.BHsensorIF_axil_slave
    port map (
      s_axil_aclk_i    => clk,
      s_axil_aresetn_i => rstn,

      s_axil_awaddr_i  => awaddr,
      s_axil_awvalid_i => awvalid,
      s_axil_awready_o => awready,

      s_axil_wdata_i   => wdata,
      s_axil_wstrb_i   => wstrb,
      s_axil_wvalid_i  => wvalid,
      s_axil_wready_o  => wready,

      s_axil_bresp_o   => bresp,
      s_axil_bvalid_o  => bvalid,
      s_axil_bready_i  => bready,

      s_axil_araddr_i  => araddr,
      s_axil_arvalid_i => arvalid,
      s_axil_arready_o => arready,

      s_axil_rdata_o   => rdata,
      s_axil_rresp_o   => rresp,
      s_axil_rvalid_o  => rvalid,
      s_axil_rready_i  => rready,

      ro_data_i        => ro_data,
      wo_data_o        => wo_data
    );

  ------------------------------------------------------------------
  -- SINGLE stimulus process
  ------------------------------------------------------------------
  stimulus : process
    variable read_tmp : std_logic_vector(31 downto 0);
  begin

    ------------------------------------------------------
    -- RESET
    ------------------------------------------------------
    rstn <= '0';
    wait for 50 ns;
    rstn <= '1';
    wait for 20 ns;

    ------------------------------------------------------
    -- Prepare RO registers
    ------------------------------------------------------
    ro_data <= x"0102030405060708";

    ------------------------------------------------------
    -- WRITE 1 : addr 0x00 -> WO0..3
    ------------------------------------------------------
    awaddr  <= x"00000000";
    awvalid <= '1';

    wdata   <= x"AABBCCDD";
    wstrb   <= "1111";
    wvalid  <= '1';

    bready  <= '1';

    wait until rising_edge(clk) and awready = '1' and wready = '1';

    awvalid <= '0';
    wvalid  <= '0';

    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

    ------------------------------------------------------
    -- WRITE 2 : addr 0x04 -> WO4..7
    ------------------------------------------------------
    awaddr  <= x"00000004";
    awvalid <= '1';

    wdata   <= x"11223344";
    wstrb   <= "1111";
    wvalid  <= '1';

    bready  <= '1';

    wait until rising_edge(clk) and awready = '1' and wready = '1';

    awvalid <= '0';
    wvalid  <= '0';

    wait until rising_edge(clk) and bvalid = '1';
    bready <= '0';

    ------------------------------------------------------
    -- READ 1 : addr 0x08
    ------------------------------------------------------
    araddr  <= x"00000008";
    arvalid <= '1';
    rready  <= '1';

    wait until rising_edge(clk) and arready = '1';
    arvalid <= '0';

    wait until rising_edge(clk) and rvalid = '1';
    read_tmp := rdata;
    report "Read @0x08 = " & to_hstring(read_tmp);
    rready <= '0';

    ------------------------------------------------------
    -- READ 2 : addr 0x0C
    ------------------------------------------------------
    araddr  <= x"0000000C";
    arvalid <= '1';
    rready  <= '1';

    wait until rising_edge(clk) and arready = '1';
    arvalid <= '0';

    wait until rising_edge(clk) and rvalid = '1';
    read_tmp := rdata;
    report "Read @0x0C = " & to_hstring(read_tmp);
    rready <= '0';

    ------------------------------------------------------
    report "Simulation finished.";
    wait;
  end process;

end architecture;