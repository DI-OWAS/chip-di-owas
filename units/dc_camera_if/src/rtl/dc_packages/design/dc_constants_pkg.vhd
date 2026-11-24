--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH
--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   David Madlener, Frederik Lange
--============================================================================================


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

--use work.dc_library_selection_pkg.all;
--use work.camera_interface_type_pkg.all;

package dc_constants_pkg is


  constant c_pixel_histogram_bit_num   : integer := 8;
  constant c_pixel_histogram_bin_depth : integer := 16;
  constant c_dc_pixels_per_line        : integer := 1280;
  constant c_dc_lines_per_frame        : integer := 32;
  constant c_dc_adc_bit_num            : integer := 12;

  constant c_default_base_address_image_write_0 : std_logic_vector(31 downto 0) := x"00000000";
  constant c_default_base_address_image_write_1 : std_logic_vector(31 downto 0) := x"00001000";
  constant c_default_base_address_image_write_2 : std_logic_vector(31 downto 0) := x"00002000";
  constant c_default_base_address_image_write_3 : std_logic_vector(31 downto 0) := x"00003000";


end dc_constants_pkg;



package body dc_constants_pkg is


end dc_constants_pkg;
