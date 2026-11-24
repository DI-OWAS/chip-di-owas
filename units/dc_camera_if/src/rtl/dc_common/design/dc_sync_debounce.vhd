--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH
--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--============================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity dc_sync_debounce is
  generic (
    g_sync_length     : integer := 3;
    g_debounce_length : integer := 16
  );

  port (
    i_rst_n : in  std_logic;
    i_clk  : in  std_logic;
    i_data : in  std_logic;
    o_data : out std_logic
  );
end entity;

architecture behavioral of dc_sync_debounce is

  --===================================================================================================================================
  -- signals
  --===================================================================================================================================

  -- input signal
  signal s_data_in : std_logic;

  -- shift register for synchronization and debouncing
  signal s_data_shift : std_logic_vector(g_sync_length + g_debounce_length downto 0);

  -- output signal
  signal s_data_out : std_logic;

begin

  --==================================================================================================================
  -- assignments
  --==================================================================================================================
  s_data_in <= i_data;
  o_data    <= s_data_out;

  --==================================================================================================================
  -- processes
  --==================================================================================================================

  -- process to synchronize and debounce data signal
  sync_debounce_proc: process (i_clk, i_rst_n) is

    constant all_zeros : std_logic_vector(g_debounce_length downto 0) := (others => '0');
    constant all_ones  : std_logic_vector(g_debounce_length downto 0) := (others => '1');

  begin
    if i_rst_n = '0' then
      s_data_shift <= (others => '0');
      s_data_out <= '0';
    elsif rising_edge(i_clk) then
      --if i_rst = '1' then
      --    s_data_shift <= (others => '0');
      --    s_data_out <= '0';
      --else
      s_data_shift <= s_data_shift(s_data_shift'high - 1 downto 0) & s_data_in;

      if (s_data_shift(s_data_shift'high downto g_sync_length) = all_zeros) then
        s_data_out <= '0';
      elsif (s_data_shift(s_data_shift'high downto g_sync_length) = all_ones) then
        s_data_out <= '1';
      end if;
      --end if;
    end if;
  end process;

end architecture;
