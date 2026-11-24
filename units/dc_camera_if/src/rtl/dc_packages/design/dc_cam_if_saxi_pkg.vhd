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
  --use work.camera_interface_type_pkg.all;
  use work.dc_base_type_pkg.all;

package dc_cam_if_saxi_pkg is

  -- ======================================================================================================================
  -- base 0x00
  constant c_prefix_block_base_system : std_logic_vector := x"00";

  constant reg_addr_version_id      : integer := 16#0000#;
  constant reg_addr_control         : integer := 16#0004#;
  constant reg_addr_status          : integer := 16#0008#;
  constant reg_addr_soft_reset      : integer := 16#000C#;
  constant reg_cam_if_buffer_index  : integer := 16#0010#;
  constant reg_cam_if_pixel_count   : integer := 16#0014#;
  constant reg_cam_if_line_count    : integer := 16#0018#;
  constant reg_cam_if_frame_counter : integer := 16#001C#;
  constant reg_cam_if_buffer_status : integer := 16#0040#;

  constant reg_cam_if_ddr_mem_start_address_0 : integer := 16#0020#;
  constant reg_cam_if_ddr_mem_start_address_1 : integer := 16#0024#;
  constant reg_cam_if_ddr_mem_start_address_2 : integer := 16#0028#;
  constant reg_cam_if_ddr_mem_start_address_3 : integer := 16#002C#;

  constant reg_cam_if_out_if_mem_rd_address               : integer := 16#0030#;
  constant reg_cam_if_out_if_data_len_and_trigger_address : integer := 16#0034#;
  constant reg_cam_if_clock_counter                       : integer := 16#0038#;
  constant reg_cam_if_image_geometry                      : integer := 16#003C#;

  constant reg_cam_histogram_base_address : integer := 16#400#; --1024

  type register_config_cam_if_r is record
    ddr_mem_start_address : t_vec32(3 downto 0); -- quad buffer to write buffers
    enable_imager         : std_logic;
    swap_rb_color         : std_logic;
    bypass_debayering     : std_logic;           -- copy input to output, no RGB conversion
    lines_per_frame       : std_logic_vector(15 downto 0);
    pixels_per_line       : std_logic_vector(11 downto 0);

  end record;

  type status_cam_if_r is record

    status             : std_logic_vector(31 downto 0);
    num_skipped_frames : std_logic_vector(15 downto 0);
    buffer_index       : std_logic_vector(1 downto 0);
    pixel_count        : std_logic_vector(15 downto 0);
    line_count         : std_logic_vector(15 downto 0);
    frame_counter      : std_logic_vector(15 downto 0);
    clock_counter      : std_logic_vector(31 downto 0);
    buffer_status      : std_logic_vector(31 downto 0);

  end record;

end package;

package body dc_cam_if_saxi_pkg is

end package body;
