--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH

--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--============================================================================================
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.std_logic_unsigned.all;

  use work.dc_base_type_pkg.all;

entity dc_cfa_window_mux is
  generic (
    g_use_two_imagers : boolean := false
  );
  port (
    --basic IF
    i_clk              :     std_logic;
    i_rst_n            :     std_logic;

    --MUX IF
    i_pixels_per_line  : in  t_vec12(1 downto 0);
    i_mux_data         : in  t_vec36(1 downto 0);
    i_mux_write_enable : in  std_logic_vector(1 downto 0);
    i_mux_read_address : in  std_logic_vector(10 downto 0);
    i_mux_read_channel : in  std_logic;
    o_mux_slice        : out t_vec16(4 downto 0);
    o_mux_line         : out t_vec12(1 downto 0);
    i_pipeline_enable : in  std_logic := '1'
  );
end entity;

architecture Behavioral of dc_cfa_window_mux is

  component dc_standard_sdp_ram is
    generic (
      g_data_width                : positive  := 24;
      g_addr_width                : positive  := 10;
      g_write_first               : boolean   := false;
      g_data_reg                  : boolean   := false;
      g_ram_style                 : string    := "block";
      g_max_fanout                : string    := "10000";
      g_bit_init                  : std_logic := '1';
      g_use_reset_output_value    : boolean   := true;
      g_use_non_pow2_num_elements : boolean   := false;
      g_non_pow2_num_elements     : integer   := 128
    );

    port (
      i_clk           : in  std_logic;
      i_rst_n         : in  std_logic;
      i_write_address : in  std_logic_vector(g_addr_width - 1 downto 0);
      i_write_data    : in  std_logic_vector(g_data_width - 1 downto 0);
      i_write_enable  : in  std_logic;
      i_read_address  : in  std_logic_vector(g_addr_width - 1 downto 0);
      o_read_data     : out std_logic_vector(g_data_width - 1 downto 0)
    );

  end component;

  -- ======================================================================================================
  -- Signal declarations
  -- ======================================================================================================
  signal data_in       : t_vec36(1 downto 0); --raw data input from FIFO
  signal data_in_w24       : t_vec24(1 downto 0);
  signal write_address : t_vec10(1 downto 0); --write address for current line buffer, generated locally
  signal buffer_select : t_vec6(1 downto 0);  --multiplexed external FIFO read enable
  signal data_valid    : t_vec6(1 downto 0);  --data valid signal

  signal left_data_out_w24  : t_vec24(5 downto 0);
  signal right_data_out_w24 : t_vec24(5 downto 0);

  signal left_data_out_w24_d  : t_vec24(5 downto 0);
  signal right_data_out_w24_d : t_vec24(5 downto 0);

  -- The RAM has no read enable. Preserve its pending result on the first
  -- stopped clock and replay it once when the downstream pipeline resumes.
  signal left_data_out_w24_hold  : t_vec24(5 downto 0);
  signal right_data_out_w24_hold : t_vec24(5 downto 0);
  signal pipeline_enable_d      : std_logic;


  signal left_data_out  : t_vec12(5 downto 0);
  signal right_data_out : t_vec12(5 downto 0);

  signal frame_start       : std_logic_vector(1 downto 0);
  signal frame_start_delay : std_logic_vector(1 downto 0);
  signal frame_start_pulse : std_logic_vector(1 downto 0);

  signal line_start       : std_logic_vector(1 downto 0);
  signal line_start_delay : std_logic_vector(1 downto 0);
  signal line_start_pulse : std_logic_vector(1 downto 0);

  signal line_stop       : std_logic_vector(1 downto 0);
  signal line_stop_delay : std_logic_vector(1 downto 0);
  signal line_stop_pulse : std_logic_vector(1 downto 0);

  signal mux_line    : t_vec12(1 downto 0);
  signal active_line : t_vec3(1 downto 0);

  --signal dummy_data_out          : std_logic_vector(35 downto 0);

begin

  -- ======================================================================================================
  -- Instances
  -- ======================================================================================================


  --transformation 36 => 2x18, frame start (32) and line start (33) bits are duplicated
--  data_in_gen: for i in 0 to 1 generate
--    data_in(i)(15 downto 0)  <= i_mux_data(i)(15 downto 0);
--    data_in(i)(17 downto 16) <= i_mux_data(i)(33 downto 32);
--    data_in(i)(35 downto 18) <= i_mux_data(i)(33 downto 16);
--  end generate;

  data_in <= i_mux_data;


  we_gen: for i in 5 downto 0 generate
    data_valid(0)(i) <= buffer_select(0)(i) and i_mux_write_enable(0);
    data_valid(1)(i) <= buffer_select(1)(i) and i_mux_write_enable(1);
  end generate;

  start_gen: for i in 0 to 1 generate
    frame_start(i) <= i_mux_data(i)(32);
    line_start(i)  <= i_mux_data(i)(33);
  end generate;



data_in_w24(0) <= data_in(0)(27 downto 16) & data_in(0)(11 downto 0);
data_in_w24(1) <= data_in(1)(27 downto 16) & data_in(1)(11 downto 0);

  left_line: for i in 5 downto 0 generate
    left_line_inst: dc_standard_sdp_ram
      port map (
        i_clk           => i_clk,
        i_rst_n         => i_rst_n,
        i_write_enable  => data_valid(0)(i),
        i_write_address => write_address(0),
        i_write_data    => data_in_w24(0),
        i_read_address  => i_mux_read_address(10 downto 1),
        o_read_data     => left_data_out_w24(i)
      );
    left_data_out(i) <= left_data_out_w24_d(i)(11 downto 0) when i_mux_read_address(0) = '0' else left_data_out_w24_d(i)(23 downto 12);
  end generate;

  gen_2nd_imager: if g_use_two_imagers = true generate
    right_line: for i in 5 downto 0 generate
      right_line_inst: dc_standard_sdp_ram

        port map (
          i_clk           => i_clk,
          i_rst_n         => i_rst_n,
          i_write_enable  => data_valid(1)(i),
          i_write_address => write_address(1),
          i_write_data    => data_in_w24(1),
          i_read_address  => i_mux_read_address(10 downto 1),
          o_read_data     => right_data_out_w24(i)
        );
      right_data_out(i) <= right_data_out_w24_d(i)(11 downto 0) when i_mux_read_address(0) = '0' else right_data_out_w24_d(i)(23 downto 12);
    end generate;
  end generate;



  -- ======================================================================================================
  -- Assignments
  -- ======================================================================================================
  o_mux_line <= mux_line;

  -- ======================================================================================================
  -- Processes

  -- ======================================================================================================
  process (i_clk, i_rst_n)
    variable stop_count : t_vec10(1 downto 0);
  begin
    if i_rst_n = '0' then
        for i in 0 to 1 loop
          mux_line(i) <= (others => '0');

          write_address(i) <= (others => '0');
          active_line(i) <= "000";

          frame_start_delay(i) <= '0';
          frame_start_pulse(i) <= '0';

          line_start_delay(i) <= '0';
          line_start_pulse(i) <= '0';

          line_stop(i) <= '0';
          line_stop_delay(i) <= '0';
          line_stop_pulse(i) <= '0';
        end loop;

        o_mux_slice <= (others => (others => '0'));
        pipeline_enable_d <= '1';
    elsif rising_edge(i_clk) then
        --creation of local start pulses from FIFO data bit 32 and 33
        frame_start_delay <= frame_start;
        line_start_delay <= line_start;
        line_stop_delay <= line_stop;

        pipeline_enable_d <= i_pipeline_enable;

        -- The free-running RAM overwrites its output during a pause. Save the
        -- result which the next enabled read stage would otherwise lose.
        if (i_pipeline_enable = '0') and (pipeline_enable_d = '1') then
          left_data_out_w24_hold <= left_data_out_w24;
          right_data_out_w24_hold <= right_data_out_w24;
        end if;

        -- Only the read pipeline pauses; pending input writes still complete.
        if i_pipeline_enable = '1' then
          if pipeline_enable_d = '0' then
            left_data_out_w24_d <= left_data_out_w24_hold;
            right_data_out_w24_d <= right_data_out_w24_hold;
          else
            left_data_out_w24_d <= left_data_out_w24;
            right_data_out_w24_d <= right_data_out_w24;
          end if;
        end if;

        for i in 0 to 1 loop
          if (i_mux_write_enable(i) = '1') then
            write_address(i) <= std_logic_vector(unsigned(write_address(i)) + 1);
          end if;

          stop_count(i) := std_logic_vector(signed(i_pixels_per_line(i)(10 downto 1)) - 1);

          if (unsigned(i_pixels_per_line(i)) > 0) and (write_address(i) = stop_count(0)) and (i_mux_write_enable(i) = '1') then
            line_stop(i) <= '1';
          end if;

          --switch to next line on left channel
          if (line_stop_pulse(i) = '1') then
            line_stop(i) <= '0';
            write_address(i) <= (others => '0');
            --increment mux_line for left channel
            mux_line(i) <= std_logic_vector(unsigned(mux_line(i) + 1));
            --increment active line modulo 6
            if (unsigned(active_line(i)) < 5) then
              active_line(i) <= std_logic_vector(unsigned(active_line(i)) + 1);
            else
              active_line(i) <= "000";
            end if;
          end if;

          --reset active line counter at new frame start
          if (frame_start_pulse(i) = '1') then
            active_line(i) <= "000"; --reset local line counters
            mux_line(i) <= (others => '0');
          end if;

          --generate frame_start_pulse from rising flank of frame_start
          frame_start_pulse(i) <= '0';
          if (frame_start_delay(i) = '0') and (frame_start(i) = '1') then
            frame_start_pulse(i) <= '1';
          end if;

          --generate line_start_pulse from rising flank of line_start
          line_start_pulse(i) <= '0';
          if (line_start_delay(i) = '0') and (line_start(i) = '1') then
            line_start_pulse(i) <= '1';
          end if;

          --generate line_stop_pulse from rising flank of line_stop
          line_stop_pulse(i) <= '0';
          if (line_stop_delay(i) = '0') and (line_stop(i) = '1') then
            line_stop_pulse(i) <= '1';
          end if;
        end loop;

        --heavy multiplexing ahead
        case (active_line(0)) is
          when "000" =>
            buffer_select(0) <= "000001";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out(i + 1)(11 downto 0);
              end loop;
            end if;
          when "001" =>
            buffer_select(0) <= "000010";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out((i + 2) mod 6)(11 downto 0);
              end loop;
            end if;
          when "010" =>
            buffer_select(0) <= "000100";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out((i + 3) mod 6)(11 downto 0);
              end loop;
            end if;
          when "011" =>
            buffer_select(0) <= "001000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out((i + 4) mod 6)(11 downto 0);
              end loop;
            end if;
          when "100" =>
            buffer_select(0) <= "010000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out((i + 5) mod 6)(11 downto 0);
              end loop;
            end if;
          when "101" =>
            buffer_select(0) <= "100000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '0') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= left_data_out(i)(11 downto 0);
              end loop;
            end if;
          when others =>
            buffer_select(0) <= "000000";
            if i_pipeline_enable = '1' then
              o_mux_slice(0) <= (others => '0');
              o_mux_slice(1) <= (others => '0');
              o_mux_slice(2) <= (others => '0');
              o_mux_slice(3) <= (others => '0');
              o_mux_slice(4) <= (others => '0');
            end if;
        end case;

        case (active_line(1)) is
          when "000" =>
            buffer_select(1) <= "000001";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out(i + 1)(11 downto 0);
              end loop;
            end if;
          when "001" =>
            buffer_select(1) <= "000010";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out((i + 2) mod 6)(11 downto 0);
              end loop;
            end if;
          when "010" =>
            buffer_select(1) <= "000100";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out((i + 3) mod 6)(11 downto 0);
              end loop;
            end if;
          when "011" =>
            buffer_select(1) <= "001000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out((i + 4) mod 6)(11 downto 0);
              end loop;
            end if;
          when "100" =>
            buffer_select(1) <= "010000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out((i + 5) mod 6)(11 downto 0);
              end loop;
            end if;
          when "101" =>
            buffer_select(1) <= "100000";
            if (i_pipeline_enable = '1') and (i_mux_read_channel = '1') then
              for i in 0 to 4 loop
                o_mux_slice(i)(11 downto 0) <= right_data_out(i)(11 downto 0);
              end loop;
            end if;
          when others =>
            buffer_select(1) <= "000000";
            if i_pipeline_enable = '1' then
              o_mux_slice(0) <= (others => '0');
              o_mux_slice(1) <= (others => '0');
              o_mux_slice(2) <= (others => '0');
              o_mux_slice(3) <= (others => '0');
              o_mux_slice(4) <= (others => '0');
            end if;
        end case;

    end if;
  end process;

end architecture;
