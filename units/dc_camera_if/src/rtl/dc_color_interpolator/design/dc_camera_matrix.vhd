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
use ieee.std_logic_unsigned.all;
use work.dc_base_type_pkg.all;


entity dc_cfa_camera_matrix is
  port(
    --basic IF
    i_clk             : in std_logic;  --interpolator clock
    i_rst_n           : in std_logic;  --interpolator reset
    i_pipeline_enable : in std_logic;

    --matrix IF
    i_slice        : in t_vec16(4 downto 0);
    i_shift        : in std_logic;
    i_first_column : in std_logic;
    i_last_column  : in std_logic;

    o_valid        : out std_logic_vector(24 downto 0);
    o_matrix       : out t_vec16(24 downto 0)
  );

end dc_cfa_camera_matrix;


architecture Behavioral of dc_cfa_camera_matrix is

  signal shift_d1       : std_logic;
  signal shift_d2       : std_logic;


  signal buffer_matrix  : t_vec16(24 downto 0);          --matrix mapped to linear vector A_ij = A(i*5+j)
  signal data_valid     : std_logic_vector(24 downto 0); --valid matrix entries

  attribute max_fanout : integer;
  attribute max_fanout of data_valid : signal is 15;

begin

  o_valid <= data_valid;

  inner0 : for j in 24 downto 0 generate
    o_matrix(j) <= buffer_matrix(j);
  end generate;

  process(i_clk, i_rst_n)

  begin
    if i_rst_n = '0' then
        data_valid <= (others => '0');
        shift_d1   <= '0';
        shift_d2   <= '0';

        outer1 : for i in 4 downto 0 loop
          inner1 : for j in 4 downto 0 loop
            buffer_matrix(i*5+j) <= (others => '0');
          end loop;
        end loop;
    elsif rising_edge(i_clk) then
      if i_pipeline_enable = '1' then
        if (i_first_column = '1') then
          buffer_clear_loop : for i in 24 downto 0 loop
            buffer_matrix(i) <= (others => '0');
          end loop;
        end if;

        valid_loop : for i in 24 downto 0 loop
          data_valid(i) <= shift_d2;  --generate local delay
        end loop;
        shift_d2  <= shift_d1;
        shift_d1  <= i_shift;

        if (i_shift = '1') or (shift_d2 = '1') then
          outer2 : for i in 4 downto 0 loop
            buffer_matrix(i*5+4) <= i_slice(i);
            buffer_matrix(i*5+3) <= buffer_matrix(i*5+4);
            buffer_matrix(i*5+2) <= buffer_matrix(i*5+3);
            buffer_matrix(i*5+1) <= buffer_matrix(i*5+2);
            buffer_matrix(i*5)   <= buffer_matrix(i*5+1);

            data_valid(i*5+4) <= i_shift;
            data_valid(i*5+3) <= data_valid(i*5+4);
            data_valid(i*5+2) <= data_valid(i*5+3);
            data_valid(i*5+1) <= data_valid(i*5+2);
            data_valid(i*5)   <= data_valid(i*5+1);
          end loop;
        end if;
      end if;

    end if;
  end process;

end Behavioral;
