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

  -- Uncomment the following library declaration if using
  -- arithmetic functions with Signed or Unsigned values
  --use IEEE.NUMERIC_STD.ALL;

  -- Uncomment the following library declaration if instantiating
  -- any Xilinx leaf cells in this code.
  --library UNISIM;
  --use UNISIM.VComponents.all;

entity dc_cfa_bayer_filter is
  --generic (
  --  g_swap_rb_color : boolean := true -- for sony sensor
  --);
  port (
    --basic IF
    i_clk          : in  std_logic; --interpolator clock
    i_rst_n        : in  std_logic; --interpolator reset
    i_pipeline_enable : in  std_logic;
    i_swap_rb_color : in std_logic;

    --filter IF
    i_green_pixel  : in  std_logic;
    i_red_row      : in  std_logic;
    i_matrix_valid : in  std_logic_vector(24 downto 0);
    i_matrix       : in  t_vec16(24 downto 0);
    --i_adc_bits     : in  std_logic_vector(3 downto 0);
    o_color_valid  : out std_logic;
    o_red          : out std_logic_vector(15 downto 0);
    o_green        : out std_logic_vector(15 downto 0);
    o_blue         : out std_logic_vector(15 downto 0);
    o_rgb          : out std_logic_vector(31 downto 0)
  );

end entity;

architecture Behavioral of dc_cfa_bayer_filter is


	-- ======================================================================================================
	-- Constants & functions
	-- ======================================================================================================

  --  type integer_matrix is array (0 to 24) of integer;

  --  
  --  constant R0 : integer_matrix := ( 0, 0, 0, 0, 0,
  --                                    0, 0, 0, 0, 0,
  --                                    0, 0,16, 0, 0, 
  --                                    0, 0, 0, 0, 0,
  --                                    0, 0, 0, 0, 0
  --                                   );
  --
  --  constant R1 : integer_matrix := ( 0, 0,-2, 0, 0,
  --                                    0, 0, 4, 0, 0,
  --                                   -2, 4, 8, 4,-2, 
  --                                    0, 0, 4, 0, 0,
  --                                    0, 0,-2, 0, 0
  --                                   );
  --
  --  constant R2 : integer_matrix := ( 0, 0, 1, 0, 0,
  --                                    0,-2, 0,-2, 0,
  --                                   -2, 8,10, 8,-2, 
  --                                    0,-2, 0,-2, 0,
  --                                    0, 0, 1, 0, 0
  --                                   );
  --                                   
  --  constant R3 : integer_matrix := ( 0, 0,-2, 0, 0,
  --                                    0,-2, 8,-2, 0,
  --                                    1, 0,10, 0, 1, 
  --                                    0,-2, 8,-2, 0,
  --                                    0, 0,-2, 0, 0
  --                                   );
  --                                   
  --  constant R4 : integer_matrix := ( 0, 0,-3, 0, 0,
  --                                    0, 4, 0, 4, 0,
  --                                   -3, 0,12, 0,-3, 
  --                                    0, 4, 0, 4, 0,
  --                                    0, 0,-3, 0, 0
  --                                   );
  function R0_func(input_matrix : t_vec18; valid : std_logic_vector(24 downto 0)) return std_logic_vector is

  begin
    return std_logic_vector(shift_left(unsigned(input_matrix(12)), 4));
  end function;

  function R1_func(input_matrix : t_vec18; valid : std_logic_vector(24 downto 0)) return t_vec18 is

    variable valid_2  : std_logic_vector(17 downto 0);
    variable valid_7  : std_logic_vector(17 downto 0);
    variable valid_10 : std_logic_vector(17 downto 0);
    variable valid_11 : std_logic_vector(17 downto 0);
    variable valid_12 : std_logic_vector(17 downto 0);
    variable valid_13 : std_logic_vector(17 downto 0);
    variable valid_14 : std_logic_vector(17 downto 0);
    variable valid_17 : std_logic_vector(17 downto 0);
    variable valid_22 : std_logic_vector(17 downto 0);

    variable result : t_vec18(3 downto 0);

  begin

    valid_2 := (others => valid(2));
    valid_7 := (others => valid(7));
    valid_10 := (others => valid(10));
    valid_11 := (others => valid(11));
    valid_12 := (others => valid(12));
    valid_13 := (others => valid(13));
    valid_14 := (others => valid(14));
    valid_17 := (others => valid(17));
    valid_22 := (others => valid(22));

    result(0) := std_logic_vector(- (shift_left(signed(input_matrix(2) and valid_2), 1)) - (shift_left(signed(input_matrix(10) and valid_10), 1)) - (shift_left(signed(input_matrix(14) and valid_14), 1)));

    result(1) := std_logic_vector(- (shift_left(signed(input_matrix(22) and valid_22), 1)) + (shift_left(signed(input_matrix(7) and valid_7), 2)));

    result(2) := std_logic_vector((shift_left(signed(input_matrix(11) and valid_11), 2)) + (shift_left(signed(input_matrix(13) and valid_13), 2)));

    result(3) := std_logic_vector((shift_left(signed(input_matrix(17) and valid_17), 2)) + (shift_left(signed(input_matrix(12) and valid_12), 3)));

    return result;
  end function;

  function R2_func(input_matrix : t_vec18; valid : std_logic_vector(24 downto 0)) return t_vec18 is

    variable valid_2  : std_logic_vector(17 downto 0);
    variable valid_6  : std_logic_vector(17 downto 0);
    variable valid_8  : std_logic_vector(17 downto 0);
    variable valid_10 : std_logic_vector(17 downto 0);
    variable valid_11 : std_logic_vector(17 downto 0);
    variable valid_12 : std_logic_vector(17 downto 0);
    variable valid_13 : std_logic_vector(17 downto 0);
    variable valid_14 : std_logic_vector(17 downto 0);
    variable valid_16 : std_logic_vector(17 downto 0);
    variable valid_18 : std_logic_vector(17 downto 0);
    variable valid_22 : std_logic_vector(17 downto 0);
    variable result   : t_vec18(3 downto 0);

  begin

    valid_2 := (others => valid(2));
    valid_6 := (others => valid(6));
    valid_8 := (others => valid(8));
    valid_10 := (others => valid(10));
    valid_11 := (others => valid(11));
    valid_12 := (others => valid(12));
    valid_13 := (others => valid(13));
    valid_14 := (others => valid(14));
    valid_16 := (others => valid(16));
    valid_18 := (others => valid(18));
    valid_22 := (others => valid(22));

    result(0) := std_logic_vector(signed(input_matrix(2) and valid_2) + signed(input_matrix(22) and valid_22) - (shift_left(signed(input_matrix(6) and valid_6), 1)));

    result(1) := std_logic_vector(
      - (shift_left(signed(input_matrix(8) and valid_8), 1)) - (shift_left(signed(input_matrix(10) and valid_10), 1)) - (shift_left(signed(input_matrix(14) and valid_14), 1)));

    result(2) := std_logic_vector(
      - (shift_left(signed(input_matrix(16) and valid_16), 1)) - (shift_left(signed(input_matrix(18) and valid_18), 1)) + (shift_left(signed(input_matrix(11) and valid_11), 3)));

    result(3) := std_logic_vector(
      (shift_left(signed(input_matrix(13) and valid_13), 3)) + (shift_left(signed(input_matrix(12) and valid_12), 3)) + (shift_left(signed(input_matrix(12) and valid_12), 1))
      );
    return result;
  end function;

  function R3_func(input_matrix : t_vec18; valid : std_logic_vector(24 downto 0)) return t_vec18 is

    variable valid_2  : std_logic_vector(17 downto 0);
    variable valid_6  : std_logic_vector(17 downto 0);
    variable valid_7  : std_logic_vector(17 downto 0);
    variable valid_8  : std_logic_vector(17 downto 0);
    variable valid_10 : std_logic_vector(17 downto 0);
    variable valid_11 : std_logic_vector(17 downto 0);
    variable valid_12 : std_logic_vector(17 downto 0);
    variable valid_13 : std_logic_vector(17 downto 0);
    variable valid_14 : std_logic_vector(17 downto 0);
    variable valid_16 : std_logic_vector(17 downto 0);
    variable valid_17 : std_logic_vector(17 downto 0);
    variable valid_18 : std_logic_vector(17 downto 0);
    variable valid_22 : std_logic_vector(17 downto 0);
    variable result   : t_vec18(3 downto 0);

  begin

    valid_2 := (others => valid(2));
    valid_6 := (others => valid(6));
    valid_7 := (others => valid(7));
    valid_8 := (others => valid(8));
    valid_10 := (others => valid(10));
    valid_11 := (others => valid(11));
    valid_12 := (others => valid(12));
    valid_13 := (others => valid(13));
    valid_14 := (others => valid(14));
    valid_16 := (others => valid(16));
    valid_17 := (others => valid(17));
    valid_18 := (others => valid(18));
    valid_22 := (others => valid(22));

    result(0) := std_logic_vector(signed(input_matrix(10) and valid_10) + signed(input_matrix(14) and valid_14) - shift_left(signed(input_matrix(2) and valid_2), 1));

    result(1) := std_logic_vector(
      - shift_left(signed(input_matrix(6) and valid_6), 1) - shift_left(signed(input_matrix(8) and valid_8), 1) - shift_left(signed(input_matrix(16) and valid_16), 1));

    result(2) := std_logic_vector(
      - shift_left(signed(input_matrix(18) and valid_18), 1) - shift_left(signed(input_matrix(22) and valid_22), 1) + shift_left(signed(input_matrix(7) and valid_7), 3));

    result(3) := std_logic_vector(
      shift_left(signed(input_matrix(17) and valid_17), 3) + shift_left(signed(input_matrix(12) and valid_12), 3) + shift_left(signed(input_matrix(12) and valid_12), 1));

    return result;
  end function;

  function R4_func(input_matrix : t_vec18; valid : std_logic_vector(24 downto 0)) return t_vec18 is

    variable valid_2  : std_logic_vector(17 downto 0);
    variable valid_6  : std_logic_vector(17 downto 0);
    variable valid_8  : std_logic_vector(17 downto 0);
    variable valid_10 : std_logic_vector(17 downto 0);
    variable valid_12 : std_logic_vector(17 downto 0);
    variable valid_14 : std_logic_vector(17 downto 0);
    variable valid_16 : std_logic_vector(17 downto 0);
    variable valid_18 : std_logic_vector(17 downto 0);
    variable valid_22 : std_logic_vector(17 downto 0);
    variable result   : t_vec18(3 downto 0);

  begin

    valid_2 := (others => valid(2));
    valid_6 := (others => valid(6));
    valid_8 := (others => valid(8));
    valid_10 := (others => valid(10));
    valid_12 := (others => valid(12));
    valid_14 := (others => valid(14));
    valid_16 := (others => valid(16));
    valid_18 := (others => valid(18));
    valid_22 := (others => valid(22));

    result(0) := std_logic_vector(- shift_left(signed(input_matrix(2) and valid_2), 1) - signed(input_matrix(2) and valid_2) - shift_left(signed(input_matrix(10) and valid_10), 1) - signed(input_matrix(10) and valid_10));
    result(1) := std_logic_vector(
      - shift_left(signed(input_matrix(14) and valid_14), 1) - signed(input_matrix(14) and valid_14) - shift_left(signed(input_matrix(22) and valid_22), 1) - signed(input_matrix(22) and valid_22));

    result(2) := std_logic_vector(
      shift_left(signed(input_matrix(6) and valid_6), 2) + shift_left(signed(input_matrix(8) and valid_8), 2) + shift_left(signed(input_matrix(16) and valid_16), 2));
    result(3) := std_logic_vector(
      shift_left(signed(input_matrix(18) and valid_18), 2) + shift_left(signed(input_matrix(12) and valid_12), 3) + shift_left(signed(input_matrix(12) and valid_12), 2)
      );
    return result;
  end function;

  function final_sum(val_in : t_vec18(3 downto 0)) return std_logic_vector is

  begin
    return std_logic_vector(signed(val_in(0)) + signed(val_in(1)) + signed(val_in(2)) + signed(val_in(3)));
  end function;


	-- ======================================================================================================
	-- Signal declarations
	-- ======================================================================================================

  signal output_valid : std_logic;

  signal red       : std_logic_vector(15 downto 0);
  signal green     : std_logic_vector(15 downto 0);
  signal blue      : std_logic_vector(15 downto 0);
  signal rgb_value : std_logic_vector(31 downto 0);

  --signal valid          : std_logic_vector(24 downto 0);
  signal valid_d1 : std_logic_vector(24 downto 0);
  signal valid_d2 : std_logic_vector(24 downto 0);
  signal valid_d3 : std_logic_vector(24 downto 0);

  signal matrix    : t_vec18(24 downto 0);
  signal matrix_d1 : t_vec18(24 downto 0);

  signal red_tmp   : std_logic_vector(17 downto 0);
  signal green_tmp : std_logic_vector(17 downto 0);
  signal blue_tmp  : std_logic_vector(17 downto 0);

  signal R0_tmp : std_logic_vector(17 downto 0);
  signal R1_tmp : t_vec18(3 downto 0);
  signal R2_tmp : t_vec18(3 downto 0);
  signal R3_tmp : t_vec18(3 downto 0);
  signal R4_tmp : t_vec18(3 downto 0);

  attribute use_dsp48          : string;
  attribute use_dsp48 of red   : signal is "no";
  attribute use_dsp48 of green : signal is "no";
  attribute use_dsp48 of blue  : signal is "no";


  signal matrix_valid : std_logic_vector(24 downto 0);

begin

	-- ======================================================================================================
	-- Assignements
	-- ======================================================================================================

  input0: for i in 24 downto 0 generate
    matrix(i)(15 downto 0)  <= i_matrix(i);
    matrix(i)(17 downto 16) <= "00";
  end generate;

  -- gen_rbg_orig: if g_swap_rb_color = false generate
  --   o_color_valid <= output_valid;
  --   o_red         <= red;
  --   o_green       <= green;
  --   o_blue        <= blue;
  --   o_rgb         <= rgb_value;

  --   rgb_value(31 downto 24) <= "00000000";
  --   rgb_value(23 downto 16) <= blue(7 downto 0);
  --   rgb_value(15 downto 8)  <= green(7 downto 0);
  --   rgb_value(7 downto 0)   <= red(7 downto 0);
  -- end generate;

  --gen_rbg_swap: if g_swap_rb_color = true generate

    rgb_value(31 downto 24) <= "00000000";
    rgb_value(23 downto 16) <= red(7 downto 0) when i_swap_rb_color = '1' else blue(7 downto 0);
    rgb_value(15 downto 8)  <= green(7 downto 0);
    rgb_value(7 downto 0)   <= blue(7 downto 0) when i_swap_rb_color = '1' else red(7 downto 0);

    o_color_valid <= output_valid;
    o_red         <= blue when i_swap_rb_color = '1' else red;
    o_green       <= green;
    o_blue        <= red when i_swap_rb_color = '1' else blue;
    o_rgb         <= rgb_value;

  --end generate;

  --  matrix_valid <= i_matrix_valid;
  matrix_valid <= (others => '1');


	-- ======================================================================================================
	-- Processes
	-- ======================================================================================================

  process(i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
        red <= (others => '0');
        green <= (others => '0');
        blue <= (others => '0');


        valid_d1 <= (others => '0');
        valid_d2 <= (others => '0');
        output_valid <= '0';
        --red_coeff <= R0;
        --green_coeff <= R0;
        --blue_coeff <= R0;
    elsif rising_edge(i_clk) then


      if (i_pipeline_enable = '1') then
        valid_d1 <= i_matrix_valid;
        valid_d2 <= valid_d1;
        valid_d3 <= valid_d2;

        matrix_d1 <= matrix;
        --matrix_d2 <= matrix_d1;

        -------------------------- takt 1      
        R0_tmp <= R0_func(matrix, matrix_valid);
        R1_tmp <= R1_func(matrix, matrix_valid);
        R2_tmp <= R2_func(matrix, matrix_valid);
        R3_tmp <= R3_func(matrix, matrix_valid);
        R4_tmp <= R4_func(matrix, matrix_valid);

        -------------------------- takt 2
        if (i_red_row = '0') then
          if (i_green_pixel = '0') then
            --blue row and blue pixel
            --red_coeff <= R4;
            --green_coeff <= R1;
            --blue_coeff <= R0;
            red_tmp <= final_sum(R4_tmp);
            green_tmp <= final_sum(R1_tmp);
            blue_tmp <= R0_tmp;
          else
            --blue row and green pixel
            --red_coeff <= R3;
            --green_coeff <= R0;
            --blue_coeff <= R2;
            red_tmp <= final_sum(R3_tmp);
            green_tmp <= R0_tmp;
            blue_tmp <= final_sum(R2_tmp);
          end if;
        else
          if (i_green_pixel = '0') then
            --red row and red pixel
            --red_coeff <= R0;
            --green_coeff <= R1;
            --blue_coeff <= R4;
            red_tmp <= R0_tmp;
            green_tmp <= final_sum(R1_tmp);
            blue_tmp <= final_sum(R4_tmp);
          else
            --red row and green pixel
            --red_coeff <= R2;
            --green_coeff <= R0;
            --blue_coeff <= R3;
            red_tmp <= final_sum(R2_tmp);
            green_tmp <= R0_tmp;
            blue_tmp <= final_sum(R3_tmp);
          end if;
        end if;
      end if;


        output_valid <= '0';
        if (i_pipeline_enable = '1') then

          --output_valid   <= input_valid;
          if (valid_d2 /= "0000000000000000000000000") then
            if (red_tmp(17 downto 16) /= "00") then
              red(7 downto 0) <= x"ff";
            else
              red(7 downto 0) <= red_tmp(15 downto 8);
            end if;

            if (green_tmp(17 downto 16) /= "00") then
              green(7 downto 0) <= x"ff";
            else
              green(7 downto 0) <= green_tmp(15 downto 8);
            end if;

            if (blue_tmp(17 downto 16) /= "00") then
              blue(7 downto 0) <= x"ff";
            else
              blue(7 downto 0) <= blue_tmp(15 downto 8);
            end if;

          end if;

          output_valid <= valid_d2(12);
        end if; 
    end if;
  end process;

end architecture;
