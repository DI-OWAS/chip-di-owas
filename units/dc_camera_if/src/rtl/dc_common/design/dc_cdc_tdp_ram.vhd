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

entity dc_cdc_tdp_ram is
	generic(
		g_data_width                : positive  := 8;
		g_addr_width                : positive  := 8;
		g_ram_style                 : string    := "block";
		g_max_fanout                : string    := "10000";
		g_bit_init                  : std_logic := '1';
		g_data_init                 : std_logic_vector(255 downto 0) := (others => '1'); --max
		g_use_reset_output_value : boolean := true;
		g_use_non_pow2_num_elements : boolean   := false;
		g_non_pow2_num_elements    : integer   := 128
	);

	port(
		i_clk_rd         : in  std_logic;
		i_clr_rd         : in  std_logic;
		i_clk_wr         : in  std_logic;
		i_write_address : in  std_logic_vector(g_addr_width - 1 downto 0);
		i_write_data    : in  std_logic_vector(g_data_width - 1 downto 0);
		i_write_enable  : in  std_logic;
		i_read_address  : in  std_logic_vector(g_addr_width - 1 downto 0);
		o_read_data     : out std_logic_vector(g_data_width - 1 downto 0)
	);

end dc_cdc_tdp_ram;

architecture behavioral of dc_cdc_tdp_ram is

	-- ======================================================================================================
	-- Functions
	-- ======================================================================================================

	function set_mem_depth(
			use_non_pow2          : boolean;
			address_width         : integer;
			non_pow2_num_elements : integer
		) return integer is
	begin
		if use_non_pow2 = true then
			return non_pow2_num_elements;
		else
			return 2 ** g_addr_width;
		end if;
	end function;


	-- ======================================================================================================
	-- Signal declarations
	-- ======================================================================================================

	constant RAM_depth : positive := set_mem_depth(g_use_non_pow2_num_elements, g_addr_width, g_non_pow2_num_elements);

	type RAM_memory is array (0 to RAM_depth - 1) of std_logic_vector(g_data_width - 1 downto 0);

    signal memory : RAM_memory := (others => g_data_init(g_data_width-1 downto 0));

	attribute ram_style : string;
	attribute ram_style of memory : signal is g_ram_style;

	-- altera
	attribute ramstyle : string;
	attribute ramstyle of memory : signal is g_ram_style;

begin

	-- ======================================================================================================
	-- Processes
	-- ======================================================================================================

	RAM_proc : process(i_clk_wr)
	begin
		if rising_edge(i_clk_wr) then

				if (i_write_enable = '1') then
					memory(to_integer(unsigned(i_write_address))) <= i_write_data;
				end if;
		end if;
	end process;

	-- model the output register of the block ram
	outreg_proc : process(i_clk_rd)
        variable tmp_rd_address : std_logic_vector(g_addr_width - 1 downto 0);
	begin
		if rising_edge(i_clk_rd) then
			if i_clr_rd = '1' then
				o_read_data <= (others => '0');
			else
			    tmp_rd_address := i_read_address;

                --pragma synthesis off
                if (to_integer(unsigned(i_read_address)) >= RAM_depth) then
                    tmp_rd_address := (others => 'X');
                end if;
                --pragma synthesis on


				o_read_data <= memory(to_integer(unsigned(tmp_rd_address)));
			end if;
		end if;
	end process;

end behavioral;
