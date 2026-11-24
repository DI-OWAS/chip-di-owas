--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH

--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--============================================================================================
--
----------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.std_logic_unsigned.all;

  --library fifo_generator_v12_0;
  --use fifo_generator_v12_0.fifo_generator_v12_0;

entity camera_interface is
  generic (
    g_pixels_per_line           : integer := 1280;
    g_lines_per_frame           : integer := 128;
    g_pixel_histogram_bin_depth : integer := 16;
    g_pixel_histogram_bit_num   : integer;
    g_adc_bit_num               : integer
  );

  port (
    i_rst_n                 : in  std_logic;
    i_axi_clk               : in  std_logic;
    -- ====================================================================
    --camera module ports
    -- ====================================================================
    i_pixel_clk             : in  std_logic;
    i_enable                : in  std_logic;
    i_line_valid            : in  std_logic;                                                  --line valid
    i_frame_valid           : in  std_logic;                                                  --frame valid
    i_pixel_data            : in  std_logic_vector(11 downto 0);                              --pixel data bus
    o_output_enable         : out std_logic;                                                  --output enable
    o_standby               : out std_logic;                                                  --standby
    o_reset                 : out std_logic;
    -- ====================================================================
    --register status data
    -- ====================================================================
    o_lines_per_frame       : out std_logic_vector(15 downto 0);                              --line count per frame
    o_pixels_per_line       : out std_logic_vector(11 downto 0);                              --pixel count per line
    o_pixels_per_frame      : out std_logic_vector(23 downto 0);                              --pixel count per frame
    o_control_signal        : out std_logic_vector(2 downto 0);                               --current control signal vector (PIXEL_CLK, LINE_VALID, FRAME_VALID)
    o_debug_pixel_data      : out std_logic_vector(11 downto 0);                              --current pixel data for debug purposes
    o_frame_counter         : out std_logic_vector(31 downto 0);                              --current frame counter

    -- ====================================================================
    -- histogram memory access
    -- ====================================================================
    i_histogram_address     : in  std_logic_vector(g_pixel_histogram_bit_num - 1 downto 0);   --pixel histogram read address
    o_histogram_data        : out std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0); --histogram bin value

    o_frame_valid           : out std_logic;
    --histogram debug ports
    o_debug_histogram_data  : out std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0); --histogram debug bin value
    o_debug_histogram_valid : out std_logic;                                                  --histogram debug valid indicator

    -- ====================================================================
    --FIFO ports
    -- ====================================================================
    o_fifo_data             : out std_logic_vector(35 downto 0);
    o_fifo_write_enable     : out std_logic;
    i_fifo_full             : in  std_logic;
    i_fifo_almost_full      : in  std_logic
  );
end entity;

architecture interface_behav of camera_interface is

  -- ==========================================================================================================
  --constant declarations
  -- ==========================================================================================================
  constant c_pixel_histogram_bin_num : integer := 2 ** g_pixel_histogram_bit_num;

  --if set 8 bit wide data port with two clocks per pixel else 12 bit wide port with one clock per pixel
  constant c_is_input_data_width_8bit : std_logic := '0';

  -- ==========================================================================================================
  --type declarations
  -- ==========================================================================================================
  type camera_adapter_state_type is (idle, receiving_frame, processing_end_of_frame); --state names for FSM
  type pixel_histogram_type is array (c_pixel_histogram_bin_num - 1 downto 0) of std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0); --pixel histogram array

  -- ==========================================================================================================
  -- signal declarations
  -- ==========================================================================================================

  signal camera_enable_clkpix      : std_logic;
  signal camera_enable_clkpix_sync : std_logic;
  signal frame_valid       : std_logic;
  signal frame_valid_gated : std_logic;
  signal frame_valid_d1    : std_logic;
  signal frame_valid_d2    : std_logic;
  signal line_valid_d1     : std_logic;
  signal line_valid_d2     : std_logic;

  signal pixel_data_d1 : std_logic_vector(11 downto 0);

  signal lines_per_frame_count   : std_logic_vector(15 downto 0);
  signal pixels_per_line_count   : std_logic_vector(11 downto 0);
  signal pixels_per_frame_count  : std_logic_vector(23 downto 0);
  signal lines_per_frame_shadow  : std_logic_vector(15 downto 0);
  signal pixels_per_line_shadow  : std_logic_vector(11 downto 0);
  signal pixels_per_frame_shadow : std_logic_vector(23 downto 0);

  signal odd_pixel_data         : std_logic;
  signal fused_pixel_data       : std_logic_vector(35 downto 0);
  signal two_pixel_complete     : std_logic;
  signal pixel_histogram        : pixel_histogram_type;-- := (others => (others => '0'));
  signal pixel_histogram_shadow : pixel_histogram_type;-- := (others => (others => '0'));
  signal read_histogram_data    : std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0);
  signal current_state    : camera_adapter_state_type;
  signal frame_counter    : std_logic_vector(31 downto 0);

  signal bin_index         : integer;
  signal frame_start_pulse : std_logic;
  signal line_start_pulse  : std_logic;
  signal line_stop_pulse   : std_logic;

  -- CDC
  signal two_pixel_complete_d1 : std_logic;
  signal two_pixel_complete_d2 : std_logic;
  signal two_pixel_complete_d3 : std_logic;
  signal fused_pixel_data_d1   : std_logic_vector(35 downto 0);
  signal fused_pixel_data_d2   : std_logic_vector(35 downto 0);
  signal fused_pixel_data_d3   : std_logic_vector(35 downto 0);

begin

  -- ==========================================================================================================
  -- output assignments
  -- ==========================================================================================================

  o_reset         <= '1'; --static at the moment!
  o_output_enable <= '0'; --static at the moment!
  o_standby       <= '0'; --static at the moment!
  o_debug_pixel_data(11 downto 0) <= pixel_data_d1(11 downto 0);

  o_control_signal(0) <= i_pixel_clk; --map camera control vector
  o_control_signal(1) <= line_valid_d1;
  o_control_signal(2) <= frame_valid_d1;

  o_frame_valid      <= frame_valid_gated;
  o_lines_per_frame  <= lines_per_frame_shadow;
  o_pixels_per_line  <= pixels_per_line_shadow;
  o_pixels_per_frame <= pixels_per_frame_shadow;
  o_frame_counter    <= frame_counter;
  o_histogram_data   <= read_histogram_data;


  -- ==========================================================================================================
  -- assignments
  -- ==========================================================================================================
  frame_valid        <= i_frame_valid; -- and camera_enable_clk54;
  --fifo_almost_full <= i_fifo_almost_full;
  --fifo_full        <= i_fifo_full;

  -- ==========================================================================================================
  -- processes
  -- ==========================================================================================================
  saxi_read: process (i_axi_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      read_histogram_data <= (others => '0');
    elsif rising_edge(i_axi_clk) then
      read_histogram_data <= pixel_histogram_shadow(to_integer(unsigned(i_histogram_address)));
    end if;
  end process;

  camera_state_machine: process (i_pixel_clk, i_rst_n)
    variable index      : integer;
    variable even_pixel : boolean;
  begin
    if i_rst_n = '0' then -- asynchronous reset (active low)
      --reset internal signals
      lines_per_frame_count <= (others => '0'); --lines per frame counter
      pixels_per_line_count <= (others => '0'); --pixels per line counter
      pixels_per_frame_count <= (others => '0'); --pixels per frame counter

      lines_per_frame_shadow <= std_logic_vector(to_unsigned(g_lines_per_frame, 16)); --lines per frame shadow
      pixels_per_line_shadow <= std_logic_vector(to_unsigned(g_pixels_per_line, 12)); --pixels per line shadow
      pixels_per_frame_shadow <= std_logic_vector(to_unsigned(g_lines_per_frame * g_pixels_per_line, 24)); --pixels per frame shadow

      frame_counter <= (others => '1'); --frame counter
      fused_pixel_data <= (others => '0'); --reset pixel data
      odd_pixel_data <= '0'; --even/odd indicator
      bin_index <= 0; --histogram bin index
      o_debug_histogram_data(15 downto 0) <= (others => '0'); --debug histogram bin value
      o_debug_histogram_valid <= '0'; --debug histogram valid indicator
      current_state <= idle; --FSM starts in 'idle'
      camera_enable_clkpix <= '0'; --synchronised camera enable from S_AXI interface
      two_pixel_complete <= '0';
      frame_start_pulse <= '0';
      line_start_pulse <= '0';
      line_stop_pulse <= '0';
      frame_valid_gated <= '0';
      frame_valid_d1 <= '0';
      frame_valid_d2 <= '0';
      line_valid_d1 <= '0';
      line_valid_d2 <= '0';
      pixel_data_d1 <= (others => '0');
      camera_enable_clkpix_sync <= '0';

    elsif rising_edge(i_pixel_clk) then -- rising clock edge

      pixel_data_d1 <= i_pixel_data;

      camera_enable_clkpix_sync <= i_enable;

      if (two_pixel_complete = '1') then

        fused_pixel_data_d1 <= fused_pixel_data; --============================================= CDC

        fused_pixel_data(32) <= '0'; --reset frame start indicator
        fused_pixel_data(33) <= '0'; --reset line start indicator
      end if;

      if (c_is_input_data_width_8bit = '1') and (odd_pixel_data = '1') then
        pixels_per_line_count <= pixels_per_line_count + 1; --increment line pixel counter
      end if;

      two_pixel_complete <= '0';
      frame_start_pulse <= '0';
      frame_valid_d1 <= frame_valid;
      frame_valid_d2 <= frame_valid_d1;
      line_valid_d1 <= i_line_valid;
      line_valid_d2 <= line_valid_d1;

      --update external enable signal
      camera_enable_clkpix <= camera_enable_clkpix_sync;

      --FSM [idle,receiving_frame,processing_frame]
      case current_state is

        when idle =>
          --if frame start detected and enabled
          if (frame_valid_d2 = '0') and (frame_valid_d1 = '1') then
            lines_per_frame_count <= (others => '0'); --reset counter for lines per frame
            pixels_per_line_count <= (others => '0'); --reset counter for pixels per line
            pixels_per_frame_count <= (others => '0'); --reset counter for pixels per frame

            frame_start_pulse <= '1'; --generate frame start pulse
            fused_pixel_data(32) <= '1'; --set pixel bit 32 to write frame start pulse to raw FIFO
            frame_counter <= frame_counter + 1;

            if (line_valid_d1 = '0') then --if upper part of pixel data not valid
              odd_pixel_data <= '0'; --set odd/even indicator to even
            end if;

            if camera_enable_clkpix = '1' then
              current_state <= receiving_frame; --switch to receiving frame if interface enabled
              frame_valid_gated <= '1';

            end if;
          end if;

        when receiving_frame =>

          line_start_pulse <= '0';
          --detect line start at raising edge of line_valid_d1
          if (line_valid_d2 = '0') and (line_valid_d1 = '1') then
            line_start_pulse <= '1'; --generate line start pulse
            fused_pixel_data(33) <= '1'; --set pixel bit 33 to write line start pulse to raw FIFO
          end if;

          line_stop_pulse <= '0';
          --detect line stop at falling edge of line_valid_d1
          if (line_valid_d2 = '1') and (line_valid_d1 = '0') then
            line_stop_pulse <= '1'; --generate line start pulse
            pixels_per_line_shadow <= pixels_per_line_count; --copy pixel count in current line to output register
            pixels_per_line_count <= (others => '0'); --reset line pixel counter
          end if;

          if (line_valid_d1 = '1') then --if inside line transmission
            --check if pixel is even
            if pixels_per_frame_count(0) = '0' then
              even_pixel := true;
            else
              even_pixel := false;
            end if;

            pixels_per_frame_count <= std_logic_vector(unsigned(pixels_per_frame_count) + 1);
            pixels_per_line_count <= std_logic_vector(unsigned(pixels_per_line_count) + 1); --increment line pixel counter

            index := to_integer(unsigned(pixel_data_d1(g_adc_bit_num - 1 downto g_adc_bit_num - g_pixel_histogram_bit_num))); --calculate bin index for histogram from pixel value

            -- avoid the maximum value
            if (index >= c_pixel_histogram_bin_num - 3) then
              index := c_pixel_histogram_bin_num - 3;
            end if;

            if unsigned(pixel_histogram(index)) <= to_unsigned(2 ** g_pixel_histogram_bin_depth - 3, g_pixel_histogram_bin_depth) then
              pixel_histogram(index) <= std_logic_vector(unsigned(pixel_histogram(index)) + 1); --increment corresponding bin count
            end if;

            if even_pixel then
              fused_pixel_data(11 downto 0) <= pixel_data_d1(11 downto 0);
            else
              fused_pixel_data(27 downto 16) <= pixel_data_d1(11 downto 0);
              two_pixel_complete <= '1';
            end if;

          else
            odd_pixel_data <= '0';
          end if;

          --detect end of frame at falling edge of frame_valid
          if (frame_valid_d2 = '1') and (frame_valid_d1 = '0') then --if frame end detected

            --reset histogram index for processing loop
            bin_index <= 0;
            --store pixel count results
            pixels_per_frame_shadow <= pixels_per_frame_count;
            lines_per_frame_shadow <= lines_per_frame_count;
            --switch to frame processing
            current_state <= processing_end_of_frame;

            frame_valid_gated <= '0';

            --if no frame end detected then check for
          elsif (line_valid_d2 = '0') and (line_valid_d1 = '1') then --if rising line start detected
            lines_per_frame_count <= lines_per_frame_count + 1; --increment lines per frame counter
          end if;

        when processing_end_of_frame =>

          o_debug_histogram_data <= pixel_histogram(bin_index); --output histogram data on debug port
          o_debug_histogram_valid <= '1'; --set valid line

          pixel_histogram_shadow(bin_index) <= pixel_histogram(bin_index); --copy histogram entry to shadow register
          pixel_histogram(bin_index) <= (others => '0'); --and clear it for next frame
          bin_index <= bin_index + 1; --proceed to next bin

          if bin_index = 2 ** g_pixel_histogram_bit_num - 1 then --if end of histogram array reached
            o_debug_histogram_valid <= '0';
            current_state <= idle;
          end if;

      end case;
    end if;

  end process;

  process (i_axi_clk, i_rst_n)
  begin
    if (i_rst_n = '0') then
      o_fifo_write_enable <= '0';

      two_pixel_complete_d1 <= '0';
      two_pixel_complete_d2 <= '0';
      two_pixel_complete_d3 <= '0';

    elsif rising_edge(i_axi_clk) then

      --===============================================================================
      -- CDC
      two_pixel_complete_d1 <= two_pixel_complete;
      two_pixel_complete_d2 <= two_pixel_complete_d1;
      two_pixel_complete_d3 <= two_pixel_complete_d2;

      fused_pixel_data_d2 <= fused_pixel_data_d1;
      fused_pixel_data_d3 <= fused_pixel_data_d2;
      --===============================================================================
      o_fifo_write_enable <= '0';

      if (two_pixel_complete_d3 = '1') and (two_pixel_complete_d2 = '0') then
        if (i_fifo_full = '0') then
          o_fifo_data <= fused_pixel_data_d2;
          o_fifo_write_enable <= '1'; -- and camera_enable_clk54;
        end if;
      end if;

    end if;
  end process;

  end architecture;
