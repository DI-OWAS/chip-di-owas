-- ======================================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH
-- ======================================================================================================
-- Description:
--   Output interface for data read by the AXI reader in dc_cam_if_top.
--
--   The module buffers 32-bit read data together with the first-word marker and converts each 32-bit
--   input word into two 16-bit output words. The lower 16 bits are output first, followed by the upper
--   16 bits.
--
--   The read-data FIFO is located in this module. Backpressure towards dc_axi_reader is generated from
--   the FIFO programmable-full flag.
--
--   o_doutif_first is asserted together with the first 16-bit word of a new command transfer.
-- ======================================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh
-- ======================================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity dc_cam_if_output_reader is
  generic (
    g_data_width : positive := 32
  );
  port (
    -- ==================================================================================================
    -- Basic interface
    -- ==================================================================================================
    i_clk                   : in  std_logic;
    i_rst_n                 : in  std_logic;

    -- ==================================================================================================
    -- Read data interface from dc_axi_reader
    -- ==================================================================================================
    i_read_data             : in  std_logic_vector(g_data_width - 1 downto 0);
    i_read_valid            : in  std_logic;
    i_read_first            : in  std_logic;
    i_read_last             : in  std_logic;
    o_read_stop             : out std_logic;

    -- ==================================================================================================
    -- 16-bit data output interface
    -- ==================================================================================================
    o_doutif_data           : out std_logic_vector(15 downto 0);
    o_doutif_valid          : out std_logic;
    o_doutif_first          : out std_logic;
    o_doutif_clk            : out std_logic;

    -- ==================================================================================================
    -- Status
    -- ==================================================================================================
    o_output_packet_count   : out std_logic_vector(31 downto 0);
    o_output_packet_done    : out std_logic;
    o_output_word_count     : out std_logic_vector(31 downto 0)
  );
end entity dc_cam_if_output_reader;

architecture rtl of dc_cam_if_output_reader is

  -- ======================================================================================================
  -- Constants
  -- ======================================================================================================

  constant c_data_fifo_counter_width : positive := 6;

  -- ======================================================================================================
  -- Signals: read data FIFO
  -- ======================================================================================================

  signal s_data_fifo_data_in     : std_logic_vector(g_data_width + 1 downto 0);
  signal s_data_fifo_data_out    : std_logic_vector(g_data_width + 1 downto 0);
  signal s_data_fifo_count       : std_logic_vector(c_data_fifo_counter_width downto 0);
  signal s_data_fifo_empty       : std_logic;
  signal s_data_fifo_prog_full   : std_logic;
  signal s_data_fifo_read_enable : std_logic;

  -- ======================================================================================================
  -- Signals: output converter
  -- ======================================================================================================

  signal s_upper_half   : std_logic;
  signal s_doutif_valid : std_logic;
  signal s_doutif_first : std_logic;

  -- ======================================================================================================
  -- Signals: status
  -- ======================================================================================================

  signal s_output_packet_count : unsigned(31 downto 0);
  signal s_output_word_count   : unsigned(31 downto 0);
  signal s_output_packet_done  : std_logic;

begin

  -- ======================================================================================================
  -- Parameter checks
  -- ======================================================================================================

  assert g_data_width = 32
    report "dc_cam_if_output_reader: g_data_width must be 32"
    severity failure;

  -- ======================================================================================================
  -- Assignments
  -- ======================================================================================================

  o_doutif_clk          <= i_clk;
  o_doutif_valid        <= s_doutif_valid;
  o_doutif_first        <= s_doutif_first;
  o_read_stop           <= s_data_fifo_prog_full;
  o_output_packet_count <= std_logic_vector(s_output_packet_count);
  o_output_word_count   <= std_logic_vector(s_output_word_count);
  o_output_packet_done  <= s_output_packet_done;

  s_data_fifo_data_in(g_data_width + 1)          <= i_read_last;
  s_data_fifo_data_in(g_data_width)              <= i_read_first;
  s_data_fifo_data_in(g_data_width - 1 downto 0) <= i_read_data;

  -- ======================================================================================================
  -- 32-to-16 bit output converter
  -- ======================================================================================================

  process(s_data_fifo_empty, s_upper_half, s_data_fifo_data_out)
  begin
    o_doutif_data           <= (others => '0');
    s_doutif_valid          <= '0';
    s_doutif_first          <= '0';
    s_data_fifo_read_enable <= '0';

    if s_data_fifo_empty = '0' then
      s_doutif_valid <= '1';

      if s_upper_half = '0' then
        o_doutif_data  <= s_data_fifo_data_out(15 downto 0);
        s_doutif_first <= s_data_fifo_data_out(g_data_width);
      else
        o_doutif_data           <= s_data_fifo_data_out(31 downto 16);
        s_data_fifo_read_enable <= '1';
      end if;
    end if;
  end process;

  -- ======================================================================================================
  -- Output half-word state
  -- ======================================================================================================

  process(i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      s_upper_half <= '0';
    elsif rising_edge(i_clk) then
      if s_doutif_valid = '1' then
        if s_upper_half = '0' then
          s_upper_half <= '1';
        else
          s_upper_half <= '0';
        end if;
      end if;
    end if;
  end process;

  -- ======================================================================================================
  -- Output status counters
  -- ======================================================================================================

  process(i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      s_output_packet_count <= (others => '0');
      s_output_word_count   <= (others => '0');
      s_output_packet_done  <= '0';
    elsif rising_edge(i_clk) then
      s_output_packet_done <= '0';
      if s_doutif_valid = '1' then
        if s_doutif_first = '1' then
          s_output_packet_count <= s_output_packet_count + 1;
          s_output_word_count   <= (others => '0');
        else
          s_output_word_count <= s_output_word_count + 1;
        end if;

        if s_upper_half = '1' and s_data_fifo_data_out(g_data_width + 1) = '1' then
          s_output_packet_done <= '1';
        end if;
      end if;
    end if;
  end process;

  -- ======================================================================================================
  -- Read data FIFO
  -- ======================================================================================================

  data_fifo_inst : entity work.dc_fwft_fifo
    generic map (
      g_data_width    => g_data_width + 2,
      g_counter_width => c_data_fifo_counter_width,
      g_prog_level    => 2 ** c_data_fifo_counter_width - 8
    )
    port map (
      i_clk          => i_clk,
      i_rst_n        => i_rst_n,
      i_write_enable => i_read_valid,
      i_data_in      => s_data_fifo_data_in,
      i_read_enable  => s_data_fifo_read_enable,
      o_data_out     => s_data_fifo_data_out,
      o_count        => s_data_fifo_count,
      o_empty        => s_data_fifo_empty,
      o_full         => open,
      o_prog_full    => s_data_fifo_prog_full,
      o_overflow     => open
    );

end architecture rtl;
