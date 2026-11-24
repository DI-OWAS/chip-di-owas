--============================================================================================
-- Copyright: 
--   2026 DC Vision Systems GmbH, all rights reserved
--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--============================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.dc_base_type_pkg.all;
  use work.dc_constants_pkg.all;
  use work.dc_cam_if_saxi_pkg.all;

  --entity declaration

entity dc_cam_if_top is
  port (
    -- ====================================================================================================================
    -- basic interface
    -- ====================================================================================================================
    i_rstn_core          : in  std_logic;
    i_clk_core          : in  std_logic;                     -- same as all AXI interfaces

    o_interrupt_flag    : out std_logic_vector(7 downto 0);
    i_interrupt_clear   : in  std_logic_vector(7 downto 0);

    -- ====================================================================================================================
    -- camera input interface
    -- ====================================================================================================================
    --camera module ports 
    i_cam_pixel_clk     : in  std_logic;                     --pixel clock
    i_cam_line_valid    : in  std_logic;                     --line valid
    i_cam_frame_valid   : in  std_logic;                     --frame valid
    i_cam_pixel_data    : in  std_logic_vector(11 downto 0); --pixel data bus

    o_cam_output_enable : out std_logic;                     --output enable (static at the moment!)
    o_cam_standby       : out std_logic;                     --standby       (static at the moment!)
    o_cam_reset         : out std_logic;                     --reset         (static at the moment!)


    -- ====================================================================================================================
    -- data output interface
    -- ====================================================================================================================
    o_doutif_data       : out std_logic_vector(15 downto 0);
    o_doutif_valid      : out std_logic;
    o_doutif_first      : out std_logic;
    o_doutif_clk        : out std_logic;

    -- ====================================================================================================================
    -- Ports of Axi Slave Bus Interface S00_AXI         
    -- ====================================================================================================================
    s00_axi_awaddr      : in  std_logic_vector(20 - 1 downto 0);
    s00_axi_awprot      : in  std_logic_vector(2 downto 0);
    s00_axi_awvalid     : in  std_logic;
    s00_axi_awready     : out std_logic;
    s00_axi_wdata       : in  std_logic_vector(32 - 1 downto 0);
    s00_axi_wstrb       : in  std_logic_vector((32 / 8) - 1 downto 0);
    s00_axi_wvalid      : in  std_logic;
    s00_axi_wready      : out std_logic;
    s00_axi_bresp       : out std_logic_vector(1 downto 0);
    s00_axi_bvalid      : out std_logic;
    s00_axi_bready      : in  std_logic;
    s00_axi_araddr      : in  std_logic_vector(20 - 1 downto 0);
    s00_axi_arprot      : in  std_logic_vector(2 downto 0);
    s00_axi_arvalid     : in  std_logic;
    s00_axi_arready     : out std_logic;
    s00_axi_rdata       : out std_logic_vector(32 - 1 downto 0);
    s00_axi_rresp       : out std_logic_vector(1 downto 0);
    s00_axi_rvalid      : out std_logic;
    s00_axi_rready      : in  std_logic;

    --===========================================================================================================================
    -- Ports of Axi Master Bus Interface M00_AXI
    -- ====================================================================================================================
    m00_axi_tx_done     : out std_logic;
    m00_axi_error       : out std_logic;
    m00_axi_aclk        : in  std_logic;
    m00_axi_aresetn     : in  std_logic;
    m00_axi_awid        : out std_logic_vector(1 - 1 downto 0);
    m00_axi_awaddr      : out std_logic_vector(32 - 1 downto 0);
    m00_axi_awlen       : out std_logic_vector(7 downto 0);
    m00_axi_awsize      : out std_logic_vector(2 downto 0);
    m00_axi_awburst     : out std_logic_vector(1 downto 0);
    m00_axi_awlock      : out std_logic;
    m00_axi_awcache     : out std_logic_vector(3 downto 0);
    m00_axi_awprot      : out std_logic_vector(2 downto 0);
    m00_axi_awqos       : out std_logic_vector(3 downto 0);
    --m00_axi_awuser      : out std_logic_vector(0 - 1 downto 0);
    m00_axi_awvalid     : out std_logic;
    m00_axi_awready     : in  std_logic;
    m00_axi_wdata       : out std_logic_vector(32 - 1 downto 0);
    m00_axi_wstrb       : out std_logic_vector(32 / 8 - 1 downto 0);
    m00_axi_wlast       : out std_logic;
    --m00_axi_wuser       : out std_logic_vector(0 - 1 downto 0);
    m00_axi_wvalid      : out std_logic;
    m00_axi_wready      : in  std_logic;
    m00_axi_bid         : in  std_logic_vector(1 - 1 downto 0);
    m00_axi_bresp       : in  std_logic_vector(1 downto 0);
    --m00_axi_buser       : in  std_logic_vector(0 - 1 downto 0);
    m00_axi_bvalid      : in  std_logic;
    m00_axi_bready      : out std_logic;
    m00_axi_arid        : out std_logic_vector(1 - 1 downto 0);
    m00_axi_araddr      : out std_logic_vector(32 - 1 downto 0);
    m00_axi_arlen       : out std_logic_vector(7 downto 0);
    m00_axi_arsize      : out std_logic_vector(2 downto 0);
    m00_axi_arburst     : out std_logic_vector(1 downto 0);
    m00_axi_arlock      : out std_logic;
    m00_axi_arcache     : out std_logic_vector(3 downto 0);
    m00_axi_arprot      : out std_logic_vector(2 downto 0);
    m00_axi_arqos       : out std_logic_vector(3 downto 0);
    --m00_axi_aruser      : out std_logic_vector(0 - 1 downto 0);
    m00_axi_arvalid     : out std_logic;
    m00_axi_arready     : in  std_logic;
    m00_axi_rid         : in  std_logic_vector(1 - 1 downto 0);
    m00_axi_rdata       : in  std_logic_vector(32 - 1 downto 0);
    m00_axi_rresp       : in  std_logic_vector(1 downto 0);
    m00_axi_rlast       : in  std_logic;
    --m00_axi_ruser       : in  std_logic_vector(0 - 1 downto 0);
    m00_axi_rvalid      : in  std_logic;
    m00_axi_rready      : out std_logic
  );
end entity;

--architecture implementation of entity dc_cam_if_topp 

architecture arch_imp of dc_cam_if_top is

  --===================================================================================================================================
  -- constants
  --===================================================================================================================================

  -- Parameters of Axi Slave Bus Interface S00_AXI
  constant C_S00_AXI_DATA_WIDTH : integer := 32;
  constant C_S00_AXI_ADDR_WIDTH : integer := 20;
  -- Parameters of Axi Master Bus Interface M00_AXI
  constant C_M00_AXI_BURST_LEN_WR    : integer := 16;
  constant C_M00_AXI_BURST_LEN_RD    : integer := 8;
  constant C_M00_AXI_ID_WIDTH     : integer := 1;
  constant C_M00_AXI_ADDR_WIDTH   : integer := 32;
  constant C_M00_AXI_DATA_WIDTH   : integer := 32;
  constant C_M00_AXI_AWUSER_WIDTH : integer := 0;
  constant C_M00_AXI_ARUSER_WIDTH : integer := 0;
  constant C_M00_AXI_WUSER_WIDTH  : integer := 0;
  constant C_M00_AXI_RUSER_WIDTH  : integer := 0;
  constant C_M00_AXI_BUSER_WIDTH  : integer := 0;

  constant c_num_write_ports_maxi0 : positive := 1;

  subtype t_maxi0_range is natural range (c_num_write_ports_maxi0 - 1) downto 0;

  constant c_raw_fifo_counter_width         : positive := 4;
  constant c_interp_fifo_counter_width      : positive := 6;
  constant c_output_cmd_fifo_counter_width  : positive := 4;

  --===================================================================================================================================
  -- component declarations
  --===================================================================================================================================

  --===================================================================================================================================
  -- signals
  --===================================================================================================================================   
  signal s_proc_maxi_write_address     : t_vec32(c_num_write_ports_maxi0 - 1 downto 0);
  signal s_proc_maxi_write_data        : t_vec128(c_num_write_ports_maxi0 - 1 downto 0) := (others => (others => '0'));
  signal s_proc_maxi_write_first       : std_logic_vector(c_num_write_ports_maxi0 - 1 downto 0);
  signal s_proc_maxi_write_count       : t_vec12(c_num_write_ports_maxi0 - 1 downto 0);
  signal s_proc_maxi_write_empty       : std_logic_vector(c_num_write_ports_maxi0 - 1 downto 0);
  signal s_proc_maxi_write_read_enable : std_logic_vector(c_num_write_ports_maxi0 - 1 downto 0);

  signal s_config_register : register_config_cam_if_r;
  signal s_status_register : status_cam_if_r;
  signal s_reset_saxi      : std_logic;
  signal s_rst_core_n      : std_logic;
  signal s_block_rst_n     : std_logic;

  signal s_interrupt_flags      : std_logic_vector(7 downto 0);
  signal s_frame_valid_d1       : std_logic;
  signal s_frame_valid_d2       : std_logic;
  signal s_input_frame_done     : std_logic;
  signal s_input_frame_counter  : unsigned(15 downto 0);
  signal s_clock_counter        : unsigned(31 downto 0);
  signal s_quad_buffer_next     : unsigned(1 downto 0);
  signal s_quad_buffer_index    : std_logic_vector(1 downto 0);
  signal s_quad_first_d         : std_logic;

  signal cam_lines_per_frame  : t_vec16(1 downto 0);
  signal cam_pixels_per_line  : t_vec12(1 downto 0);
  signal cam_pixels_per_frame : t_vec24(1 downto 0);
  signal mux_line             : t_vec12(1 downto 0);
  signal last_mux_line        : t_vec12(1 downto 0);

  signal cam_enable           : std_logic;
  signal cam_status_signals   : std_logic_vector(2 downto 0);
  signal cam_debug_pixel_data : std_logic_vector(11 downto 0);
  signal cam_frame_counter    : std_logic_vector(31 downto 0);

  signal histogram_address : std_logic_vector(c_pixel_histogram_bit_num - 1 downto 0);
  signal histogram_data    : std_logic_vector(c_pixel_histogram_bin_depth - 1 downto 0);

  signal frame_valid : std_logic;

  signal raw_fifo_data_in      : std_logic_vector(35 downto 0);
  signal raw_fifo_data_out     : std_logic_vector(35 downto 0);
  signal raw_fifo_count        : std_logic_vector(c_raw_fifo_counter_width downto 0);
  signal raw_fifo_stop         : std_logic;
  signal raw_fifo_valid        : std_logic;
  signal raw_fifo_read_enable0 : std_logic;
  signal raw_fifo_read_enable1 : std_logic;
  signal raw_fifo_empty        : std_logic;

  signal interp_fifo_data_in  : std_logic_vector(35 downto 0);
  signal interp_fifo_data_out : std_logic_vector(35 downto 0);
  signal interp_fifo_data_in1 : std_logic_vector(35 downto 0);
  signal interp_fifo_count    : std_logic_vector(c_interp_fifo_counter_width downto 0);
  signal interp_fifo_stop     : std_logic;
  signal interp_fifo_valid    : std_logic;
  signal interp_fifo_valid1   : std_logic;

  --signal interp_fifo_read_enable : std_logic;
  signal interp_fifo_empty : std_logic;

  signal bayer_interp_enable : std_logic;

  signal dbg_interp_channel : std_logic;
  signal dbg_filter_valid   : std_logic;
  signal dbg_mux_data_valid : std_logic;

  -- ======================================================================================================
  -- Output read path
  -- ======================================================================================================

  signal s_output_if_cmd              : std_logic_vector(47 downto 0);
  signal s_output_if_cmd_write_enable : std_logic;
  signal s_output_if_cmd_full         : std_logic;

  signal s_output_cmd_fifo_count      : std_logic_vector(c_output_cmd_fifo_counter_width downto 0);
  signal s_output_read_cmd            : t_vec48(0 downto 0);
  signal s_output_read_cmd_empty      : std_logic_vector(0 downto 0);
  signal s_output_read_cmd_read       : std_logic_vector(0 downto 0);

  signal s_output_read_data           : std_logic_vector(C_M00_AXI_DATA_WIDTH - 1 downto 0);
  signal s_output_read_valid          : std_logic_vector(0 downto 0);
  signal s_output_read_first          : std_logic;
  signal s_output_read_last           : std_logic;
  signal s_output_read_stop           : std_logic_vector(0 downto 0);

  signal s_output_reader_error        : std_logic;
  signal s_axi_writer_error           : std_logic;
  signal s_output_packet_count        : std_logic_vector(31 downto 0);
  signal s_output_word_count          : std_logic_vector(31 downto 0);
  signal s_output_packet_done         : std_logic;

  --===============================================================================================================================================
  -- attributes
  --===============================================================================================================================================

begin

  --===============================================================================================================================================
  -- assignments
  --===============================================================================================================================================
  s_rst_core_n   <= i_rstn_core;
  s_block_rst_n  <= s_rst_core_n and m00_axi_aresetn and (not s_reset_saxi);

  o_interrupt_flag <= s_interrupt_flags;
  m00_axi_error    <= s_axi_writer_error or s_output_reader_error;

  -- AXI read channel is driven by dc_axi_reader below.
  s_proc_maxi_write_empty(0)   <= interp_fifo_empty;
  s_proc_maxi_write_first(0)   <= interp_fifo_data_out(32);
  s_proc_maxi_write_address(0) <= s_config_register.ddr_mem_start_address(to_integer(s_quad_buffer_next));

  --s_proc_maxi_write_count(0)   <= interp_fifo_count(11 downto 0);
  s_proc_maxi_write_count(0) <= std_logic_vector(resize(unsigned(interp_fifo_count(c_interp_fifo_counter_width downto 0)), s_proc_maxi_write_count(0)'length));

  s_proc_maxi_write_data(0)(31 downto 0) <= interp_fifo_data_out(31 downto 0);
  s_proc_maxi_write_data(0)(127 downto 32) <= (others => '0'); -- [Nol] unused; tie to zero

  cam_enable          <= s_config_register.enable_imager;
  bayer_interp_enable <= '1';

  -- Output interface status.
  -- The existing status record currently provides these two software-readable fields.
  -- status             : number of output packets started
  -- num_skipped_frames : current 16-bit word index within the active/last packet
  s_status_register.status <= std_logic_vector(resize(unsigned(s_output_packet_count), s_status_register.status'length));
  s_status_register.num_skipped_frames <= std_logic_vector(resize(unsigned(s_output_word_count), s_status_register.num_skipped_frames'length));
  s_status_register.buffer_index  <= s_quad_buffer_index;
  s_status_register.pixel_count   <= std_logic_vector(resize(unsigned(cam_pixels_per_line(0)), s_status_register.pixel_count'length));
  s_status_register.line_count    <= cam_lines_per_frame(0);
  s_status_register.frame_counter <= std_logic_vector(s_input_frame_counter);
  s_status_register.clock_counter <= std_logic_vector(s_clock_counter);



  -- ======================================================================================================
  -- Status, quad-buffer control and interrupts
  -- ======================================================================================================

  process(i_clk_core, s_block_rst_n)
    variable v_interrupt_flags : std_logic_vector(7 downto 0);
  begin
    if s_block_rst_n = '0' then
      s_frame_valid_d1      <= '0';
      s_frame_valid_d2      <= '0';
      s_input_frame_done    <= '0';
      s_input_frame_counter <= (others => '0');
      s_clock_counter       <= (others => '0');
      s_interrupt_flags     <= (others => '0');
      s_status_register.buffer_status <= (others => '0');
    elsif rising_edge(i_clk_core) then

      s_status_register.buffer_status(0) <= i_cam_line_valid;
      s_status_register.buffer_status(1) <= i_cam_frame_valid;
      s_status_register.buffer_status(2) <= s_input_frame_done;
      s_status_register.buffer_status(3) <= raw_fifo_stop;
      s_status_register.buffer_status(4) <= raw_fifo_empty;
      s_status_register.buffer_status(5) <= interp_fifo_stop;
      s_status_register.buffer_status(6) <= interp_fifo_valid;
      s_status_register.buffer_status(7) <= interp_fifo_empty;
      s_status_register.buffer_status(8) <= bayer_interp_enable;
      s_status_register.buffer_status(9) <= s_output_if_cmd_full;
      s_status_register.buffer_status(10) <= s_output_read_cmd_empty(0);
      s_status_register.buffer_status(11) <= s_output_read_stop(0);
      s_status_register.buffer_status(12) <= s_output_reader_error;
      s_status_register.buffer_status(13) <= s_axi_writer_error;
      s_status_register.buffer_status(14) <= s_output_packet_done;
      s_status_register.buffer_status(15) <= i_interrupt_clear(0);
      s_status_register.buffer_status(16) <= s_axi_writer_error;
      s_status_register.buffer_status(17) <= bayer_interp_enable;


      s_frame_valid_d1   <= frame_valid;
      s_frame_valid_d2   <= s_frame_valid_d1;
      s_input_frame_done <= '0';
      s_clock_counter    <= s_clock_counter + 1;

      if s_frame_valid_d2 = '1' and s_frame_valid_d1 = '0' then
        s_input_frame_done    <= '1';
        s_input_frame_counter <= s_input_frame_counter + 1;
      end if;

      v_interrupt_flags := s_interrupt_flags and not i_interrupt_clear;
      if s_frame_valid_d2 = '1' and s_frame_valid_d1 = '0' then
        v_interrupt_flags(0) := '1';
      end if;
      if s_output_packet_done = '1' then
        v_interrupt_flags(1) := '1';
      end if;
      s_interrupt_flags <= v_interrupt_flags;
    end if;
  end process;

  process(i_clk_core, s_block_rst_n)
  begin
    if s_block_rst_n = '0' then
      s_quad_buffer_next  <= (others => '0');
      s_quad_buffer_index <= (others => '0');
      s_quad_first_d      <= '0';
    elsif rising_edge(i_clk_core) then
      s_quad_first_d <= (not interp_fifo_empty) and s_proc_maxi_write_first(0);

      if s_frame_valid_d1 = '0' and s_frame_valid_d2 = '1' then
      --if interp_fifo_empty = '0' and s_proc_maxi_write_first(0) = '1' and s_quad_first_d = '0' then
        s_quad_buffer_index <= std_logic_vector(s_quad_buffer_next);
        s_quad_buffer_next  <= s_quad_buffer_next + 1;
      end if;
    end if;
  end process;

  --===============================================================================================================================================
  --===============================================================================================================================================
  -- instances
  --===============================================================================================================================================
  --===============================================================================================================================================

  --Instantiation of camera interface
  cam_interface_inst: entity work.camera_interface
    generic map (
      g_pixel_histogram_bin_depth => c_pixel_histogram_bin_depth,
      g_pixel_histogram_bit_num   => c_pixel_histogram_bit_num,
      g_pixels_per_line           => c_dc_pixels_per_line,
      g_lines_per_frame           => c_dc_lines_per_frame,
      g_adc_bit_num               => c_dc_adc_bit_num
    )
    port map (
      i_rst_n                 => s_block_rst_n,
      i_axi_clk               => m00_axi_aclk,
      i_pixel_clk             => i_cam_pixel_clk,
      i_enable                => cam_enable,
      --inputs from adapter      
      i_line_valid            => i_cam_line_valid,
      i_frame_valid           => i_cam_frame_valid,
      i_pixel_data            => i_cam_pixel_data,
      o_frame_valid           => frame_valid,
      o_reset                 => o_cam_reset,
      o_output_enable         => o_cam_output_enable,
      o_standby               => o_cam_standby,
      o_lines_per_frame       => cam_lines_per_frame(0),
      o_pixels_per_line       => cam_pixels_per_line(0),
      o_pixels_per_frame      => cam_pixels_per_frame(0),
      o_frame_counter         => cam_frame_counter,
      o_control_signal        => cam_status_signals,
      o_debug_pixel_data      => cam_debug_pixel_data,
      i_histogram_address     => histogram_address,
      o_histogram_data        => histogram_data,
      o_debug_histogram_data  => open,
      o_debug_histogram_valid => open,
      -- output FIFO IF
      o_fifo_data             => raw_fifo_data_in,
      o_fifo_write_enable     => raw_fifo_valid,
      i_fifo_full             => raw_fifo_stop,
      i_fifo_almost_full      => raw_fifo_stop
    );
    cam_lines_per_frame(1)  <= (others => '0'); -- [Nol] unused, tie to zero
    cam_pixels_per_line(1)  <= (others => '0'); -- [Nol] unused, tie to zero
    cam_pixels_per_frame(1) <= (others => '0'); -- [Nol] unused, tie to zero

  raw_fifo: entity work.dc_fwft_fifo
    generic map (
      g_data_width    => 36,
      g_counter_width => c_raw_fifo_counter_width,
      g_prog_level    => 2 ** c_raw_fifo_counter_width - 3
    )
    port map (
      i_clk          => i_clk_core,
      i_rst_n        => s_block_rst_n,
      i_write_enable => raw_fifo_valid,
      i_data_in      => raw_fifo_data_in,
      i_read_enable  => raw_fifo_read_enable0,
      o_data_out     => raw_fifo_data_out,
      o_count        => raw_fifo_count,
      o_empty        => raw_fifo_empty,
      o_full         => open,
      o_prog_full    => raw_fifo_stop,
      o_overflow     => open
    );

  bayer_interpolator_inst: entity work.dc_bayer_interpolator
    port map (
      --basic IF
      i_clk                  => m00_axi_aclk,
      i_rst_n                => s_block_rst_n,
      i_enable(0)            => bayer_interp_enable,
      i_enable(1)            => '0',
      i_swap_rb_color => s_config_register.swap_rb_color,

      --FIFO RD ports
      i_fifo_raw_data(0)     => raw_fifo_data_out,
      i_fifo_raw_data(1)     => (others => '0'),
      o_fifo_raw_read_enable(0)  => raw_fifo_read_enable0,
      o_fifo_raw_read_enable(1)  => raw_fifo_read_enable1,
      i_fifo_raw_empty(0)        => raw_fifo_empty,
      i_fifo_raw_empty(1)        => '0',
      --FIFO WR ports
      o_fifo_interp_data(0)  => interp_fifo_data_in,
      o_fifo_interp_data(1)  => interp_fifo_data_in1,
      o_fifo_interp_write_enable(0) => interp_fifo_valid,
      o_fifo_interp_write_enable(1) => interp_fifo_valid1,
      i_fifo_interp_full(0)         => interp_fifo_stop,
      i_fifo_interp_full(1)         => '0',
      i_fifo_interp_almost_full(0)  => interp_fifo_stop,
      i_fifo_interp_almost_full(1)  => '0',
      --parameter inputs
      i_lines_per_frame(0)   => s_config_register.lines_per_frame,
      i_lines_per_frame(1)   => (others => '0'),

      i_pixels_per_line(0)   => s_config_register.pixels_per_line,
      i_pixels_per_line(1)   => (others => '0'),


      --i_adc_bits                 => adc_bits,
      --parameter outputs
      o_mux_line             => mux_line,
      o_last_mux_line        => last_mux_line,
      o_interp_channel       => dbg_interp_channel,
      o_filter_valid         => dbg_filter_valid,
      o_mux_data_valid       => dbg_mux_data_valid
    );

  interp_fifo: entity work.dc_fwft_fifo
    generic map (
      g_data_width    => 36,
      g_counter_width => c_interp_fifo_counter_width,
      g_prog_level    => 2 ** c_interp_fifo_counter_width - 10
    )

    port map (
      i_clk          => i_clk_core,
      i_rst_n        => s_block_rst_n,
      i_write_enable => interp_fifo_valid,
      i_data_in      => interp_fifo_data_in,
      i_read_enable  => s_proc_maxi_write_read_enable(0),
      o_data_out     => interp_fifo_data_out,
      o_count        => interp_fifo_count,
      o_empty        => interp_fifo_empty,
      o_full         => open,
      o_prog_full    => interp_fifo_stop,
      o_overflow     => open
    );

  -- ======================================================================================================
  -- Output command FIFO
  -- ======================================================================================================

  output_cmd_fifo_inst : entity work.dc_fwft_fifo
    generic map (
      g_data_width    => 48,
      g_counter_width => c_output_cmd_fifo_counter_width,
      g_prog_level    => 2 ** c_output_cmd_fifo_counter_width - 2
    )
    port map (
      i_clk          => i_clk_core,
      i_rst_n        => s_block_rst_n,
      i_write_enable => s_output_if_cmd_write_enable,
      i_data_in      => s_output_if_cmd,
      i_read_enable  => s_output_read_cmd_read(0),
      o_data_out     => s_output_read_cmd(0),
      o_count        => s_output_cmd_fifo_count,
      o_empty        => s_output_read_cmd_empty(0),
      o_full         => s_output_if_cmd_full,
      o_prog_full    => open,
      o_overflow     => open
    );



  -- ======================================================================================================
  -- Output interface
  -- ======================================================================================================

  output_reader_inst : entity work.dc_cam_if_output_reader
    generic map (
      g_data_width => C_M00_AXI_DATA_WIDTH
    )
    port map (
      i_clk                  => i_clk_core,
      i_rst_n                => s_block_rst_n,

      i_read_data            => s_output_read_data,
      i_read_valid           => s_output_read_valid(0),
      i_read_first           => s_output_read_first,
      i_read_last            => s_output_read_last,
      o_read_stop            => s_output_read_stop(0),

      o_doutif_data          => o_doutif_data,
      o_doutif_valid         => o_doutif_valid,
      o_doutif_first         => o_doutif_first,
      o_doutif_clk           => o_doutif_clk,

      o_output_packet_count  => s_output_packet_count,
      o_output_packet_done   => s_output_packet_done,
      o_output_word_count    => s_output_word_count
    );


  -- ======================================================================================================
  -- AXI reader
  -- ======================================================================================================

  axi_reader_inst : entity work.dc_axi_reader
    generic map (
      g_num_read_ports     => 1,
      C_M_AXI_BURST_LEN    => C_M00_AXI_BURST_LEN_RD,
      C_M_AXI_ID_WIDTH     => C_M00_AXI_ID_WIDTH,
      C_M_AXI_ADDR_WIDTH   => C_M00_AXI_ADDR_WIDTH,
      C_M_AXI_DATA_WIDTH   => C_M00_AXI_DATA_WIDTH,
      C_M_AXI_ARUSER_WIDTH => 0,
      C_M_AXI_RUSER_WIDTH  => 0
    )
    port map (
      i_clk                 => i_clk_core,
      i_rst_n               => s_block_rst_n,
      o_error               => s_output_reader_error,

      i_command             => s_output_read_cmd,
      i_command_queue_empty => s_output_read_cmd_empty,
      o_command_read_enable => s_output_read_cmd_read,

      o_read_data           => s_output_read_data,
      o_read_valid          => s_output_read_valid,
      o_read_first          => s_output_read_first,
      o_read_last           => s_output_read_last,
      i_read_stop           => s_output_read_stop,

      o_M_AXI_ARID          => m00_axi_arid,
      o_M_AXI_ARADDR        => m00_axi_araddr,
      o_M_AXI_ARLEN         => m00_axi_arlen,
      o_M_AXI_ARSIZE        => m00_axi_arsize,
      o_M_AXI_ARBURST       => m00_axi_arburst,
      o_M_AXI_ARLOCK        => m00_axi_arlock,
      o_M_AXI_ARCACHE       => m00_axi_arcache,
      o_M_AXI_ARPROT        => m00_axi_arprot,
      o_M_AXI_ARQOS         => m00_axi_arqos,
      o_M_AXI_ARUSER        => open,
      o_M_AXI_ARVALID       => m00_axi_arvalid,
      i_M_AXI_ARREADY       => m00_axi_arready,

      i_M_AXI_RID           => m00_axi_rid,
      i_M_AXI_RDATA         => m00_axi_rdata,
      i_M_AXI_RRESP         => m00_axi_rresp,
      i_M_AXI_RLAST         => m00_axi_rlast,
      i_M_AXI_RUSER         => (others => '0'),
      i_M_AXI_RVALID        => m00_axi_rvalid,
      o_M_AXI_RREADY        => m00_axi_rready
    );



  --=====================================================================================================
  -- AXI interfaces
  --=====================================================================================================
  axi_writer0_inst: entity work.dc_axi_writer
    generic map (
      g_num_write_ports    => c_num_write_ports_maxi0,
      C_M_AXI_BURST_LEN    => C_M00_AXI_BURST_LEN_WR,
      C_M_AXI_ID_WIDTH     => C_M00_AXI_ID_WIDTH,
      C_M_AXI_ADDR_WIDTH   => C_M00_AXI_ADDR_WIDTH,
      C_M_AXI_DATA_WIDTH   => C_M00_AXI_DATA_WIDTH,
      C_M_AXI_AWUSER_WIDTH => C_M00_AXI_AWUSER_WIDTH,
      C_M_AXI_ARUSER_WIDTH => C_M00_AXI_ARUSER_WIDTH,
      C_M_AXI_WUSER_WIDTH  => C_M00_AXI_WUSER_WIDTH,
      C_M_AXI_RUSER_WIDTH  => C_M00_AXI_RUSER_WIDTH,
      C_M_AXI_BUSER_WIDTH  => C_M00_AXI_BUSER_WIDTH
    )
    port map (
      -- AXI write IF       
      i_base_address(c_num_write_ports_maxi0 - 1 downto 0)    => s_proc_maxi_write_address(c_num_write_ports_maxi0 - 1 downto 0),
      i_buf_data(c_num_write_ports_maxi0 - 1 downto 0)        => s_proc_maxi_write_data(c_num_write_ports_maxi0 - 1 downto 0),
      i_buf_first(c_num_write_ports_maxi0 - 1 downto 0)       => s_proc_maxi_write_first(c_num_write_ports_maxi0 - 1 downto 0),
      i_buf_count(c_num_write_ports_maxi0 - 1 downto 0)       => s_proc_maxi_write_count(c_num_write_ports_maxi0 - 1 downto 0),
      i_buf_empty(c_num_write_ports_maxi0 - 1 downto 0)       => s_proc_maxi_write_empty(c_num_write_ports_maxi0 - 1 downto 0),
      o_buf_read_enable(c_num_write_ports_maxi0 - 1 downto 0) => s_proc_maxi_write_read_enable(c_num_write_ports_maxi0 - 1 downto 0),
      o_M_AXI_TX_DONE                                         => m00_axi_tx_done,
      o_error                                                 => s_axi_writer_error,
      i_force_address_offset_reset                            => (others => '0'),
      i_clk                                                   => i_clk_core,
      i_rst_n                                                 => s_block_rst_n,
      o_M_AXI_AWID                                            => m00_axi_awid,
      o_M_AXI_AWADDR                                          => m00_axi_awaddr,
      o_M_AXI_AWLEN                                           => m00_axi_awlen,
      o_M_AXI_AWSIZE                                          => m00_axi_awsize,
      o_M_AXI_AWBURST                                         => m00_axi_awburst,
      o_M_AXI_AWLOCK                                          => m00_axi_awlock,
      o_M_AXI_AWCACHE                                         => m00_axi_awcache,
      o_M_AXI_AWPROT                                          => m00_axi_awprot,
      o_M_AXI_AWQOS                                           => m00_axi_awqos,
      o_M_AXI_AWUSER                                          => open,            --m00_axi_awuser,
      o_M_AXI_AWVALID                                         => m00_axi_awvalid,
      i_M_AXI_AWREADY                                         => m00_axi_awready,
      o_M_AXI_WDATA                                           => m00_axi_wdata,
      o_M_AXI_WSTRB                                           => m00_axi_wstrb,
      o_M_AXI_WLAST                                           => m00_axi_wlast,
      o_M_AXI_WUSER                                           => open,            --m00_axi_wuser,
      o_M_AXI_WVALID                                          => m00_axi_wvalid,
      i_M_AXI_WREADY                                          => m00_axi_wready,
      i_M_AXI_BID                                             => m00_axi_bid,
      i_M_AXI_BRESP                                           => m00_axi_bresp,
      i_M_AXI_BUSER                                           => (others => '0'), --m00_axi_buser,
      i_M_AXI_BVALID                                          => m00_axi_bvalid,
      o_M_AXI_BREADY                                          => m00_axi_bready
    );

  --======================================================================================================================
  -- Instantiation of Axi Bus Interface S00_AXI
  --======================================================================================================================
  cam_if_rec_saxi_inst: entity work.dc_cam_if_rec_saxi
    generic map (
			g_pixel_histogram_bit_num   => c_pixel_histogram_bit_num,
			g_pixel_histogram_bin_depth => c_pixel_histogram_bin_depth,

      C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
      C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
    )
    port map (
      --======================================================================================================================
      -- basic interface
      --======================================================================================================================
      i_clk                    => i_clk_core,
      i_rst_n                  => s_rst_core_n,
			--======================================================================================================================
			-- intensizty histogram access
			--======================================================================================================================
			i_histogram_data                    => histogram_data,
			o_histogram_address                 => histogram_address,     

          -- =================================================================================================
    -- output data interface
    -- =================================================================================================
    o_output_if_cmd  => s_output_if_cmd,
    o_output_if_cmd_write_enable  => s_output_if_cmd_write_enable,
    i_output_if_cmd_full  => s_output_if_cmd_full,

      --======================================================================================================================
                  -- axi interface
      --======================================================================================================================
      s_axi_awaddr             => s00_axi_awaddr,
      s_axi_awprot             => s00_axi_awprot,
      s_axi_awvalid            => s00_axi_awvalid,
      s_axi_awready            => s00_axi_awready,
      s_axi_wdata              => s00_axi_wdata,
      s_axi_wstrb              => s00_axi_wstrb,
      s_axi_wvalid             => s00_axi_wvalid,
      s_axi_wready             => s00_axi_wready,
      s_axi_bresp              => s00_axi_bresp,
      s_axi_bvalid             => s00_axi_bvalid,
      s_axi_bready             => s00_axi_bready,
      s_axi_araddr             => s00_axi_araddr,
      s_axi_arprot             => s00_axi_arprot,
      s_axi_arvaid             => s00_axi_arvalid,
      s_axi_arready            => s00_axi_arready,
      s_axi_rdata              => s00_axi_rdata,
      s_axi_rreesp             => s00_axi_rresp,
      s_axi_rvalid             => s00_axi_rvalid,
      s_axi_rready             => s00_axi_rready,
      o_register_config_cam_if => s_config_register,
      i_status_cam_if => s_status_register,

      o_soft_reset             => s_reset_saxi
    );

end architecture;
