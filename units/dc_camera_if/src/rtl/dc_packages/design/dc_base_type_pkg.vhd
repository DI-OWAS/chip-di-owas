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


package dc_base_type_pkg is

	function to_std_logic(input_val : boolean) return std_logic;

	type t_vec2   is array (natural range <>) of std_logic_vector(1   downto 0);
	type t_vec3   is array (natural range <>) of std_logic_vector(2   downto 0);
	type t_vec4   is array (natural range <>) of std_logic_vector(3   downto 0);
	type t_vec5   is array (natural range <>) of std_logic_vector(4   downto 0);
	type t_vec6   is array (natural range <>) of std_logic_vector(5   downto 0);
	type t_vec7   is array (natural range <>) of std_logic_vector(6   downto 0);
	type t_vec8   is array (natural range <>) of std_logic_vector(7   downto 0);
	type t_vec9   is array (natural range <>) of std_logic_vector(8   downto 0);
	type t_vec10  is array (natural range <>) of std_logic_vector(9   downto 0);
	type t_vec11  is array (natural range <>) of std_logic_vector(10  downto 0);
	type t_vec12  is array (natural range <>) of std_logic_vector(11  downto 0);
	type t_vec13  is array (natural range <>) of std_logic_vector(12  downto 0);
	type t_vec14  is array (natural range <>) of std_logic_vector(13  downto 0);
	type t_vec16  is array (natural range <>) of std_logic_vector(15  downto 0);
	type t_vec18  is array (natural range <>) of std_logic_vector(17  downto 0);
    type t_vec20  is array (natural range <>) of std_logic_vector(19  downto 0);
    type t_vec21  is array (natural range <>) of std_logic_vector(20  downto 0);
	type t_vec22  is array (natural range <>) of std_logic_vector(21  downto 0);
	type t_vec23  is array (natural range <>) of std_logic_vector(22  downto 0);
	type t_vec24  is array (natural range <>) of std_logic_vector(23  downto 0);
	type t_vec27  is array (natural range <>) of std_logic_vector(26  downto 0);
	type t_vec30  is array (natural range <>) of std_logic_vector(29  downto 0);
	type t_vec32  is array (natural range <>) of std_logic_vector(31  downto 0);
	type t_vec33  is array (natural range <>) of std_logic_vector(32  downto 0);
	type t_vec36  is array (natural range <>) of std_logic_vector(35  downto 0);
	type t_vec48  is array (natural range <>) of std_logic_vector(47  downto 0);
	type t_vec64  is array (natural range <>) of std_logic_vector(63  downto 0);
	type t_vec72  is array (natural range <>) of std_logic_vector(71  downto 0);
	type t_vec128 is array (natural range <>) of std_logic_vector(127 downto 0);



end dc_base_type_pkg;

package body dc_base_type_pkg is



	function to_std_logic(input_val : boolean) return std_logic is
	begin
		if input_val then
			return ('1');
		else
			return ('0');
		end if;
	end function to_std_logic;

end dc_base_type_pkg;
