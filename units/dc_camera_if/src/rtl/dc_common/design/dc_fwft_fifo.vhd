--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH

--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--==========


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dc_fwft_fifo is
	generic(
		g_data_width    : positive := 8;
		g_counter_width : positive := 8;
		g_prog_level    : positive := 250
	);

	port(
		i_clk          : in  std_logic;
		i_rst_n        : in  std_logic;
		i_write_enable : in  std_logic;
		i_data_in      : in  std_logic_vector(g_data_width - 1 downto 0);
		i_read_enable  : in  std_logic;
		o_data_out     : out std_logic_vector(g_data_width - 1 downto 0);
		o_count        : out std_logic_vector(g_counter_width downto 0);
		o_empty        : out std_logic;
		o_full         : out std_logic;
		o_prog_full    : out std_logic;
		o_overflow     : out std_logic
	);
end dc_fwft_fifo;

architecture behavioral of dc_fwft_fifo is

	-- ======================================================================================================
	-- Constants & signals
	-- ======================================================================================================

	constant fifo_depth : positive := 2 ** g_counter_width;

	signal write_ptr : std_logic_vector(g_counter_width - 1 downto 0);
	signal read_ptr  : std_logic_vector(g_counter_width - 1 downto 0);

	-- one bit more to allow maximum count value
	signal count_reg       : std_logic_vector(g_counter_width downto 0);
	signal count_corrected : std_logic_vector(g_counter_width downto 0);

	signal count_is_zero : std_logic;

	signal write_enable_protected   : std_logic;
	signal write_enable_protected_d : std_logic;
	signal read_enable_protected    : std_logic;

	signal fifo_full      : std_logic;
	signal fifo_prog_full : std_logic;
	signal fifo_empty     : std_logic;

	signal read_enable_fwft         : std_logic;
	signal output_reg_fwft_empty    : std_logic;
	signal output_reg_fwft_empty_d1 : std_logic;

	type fifo_memory_type is array (0 to fifo_depth - 1) of std_logic_vector(g_data_width - 1 downto 0);

	-- inferring the RAM
	signal fifo_memory : fifo_memory_type;
	--shared variable fifo_memory   : fifo_memory_type;
	-- explicitely modeling the output register
	signal mem_out_val_before_reg : std_logic_vector(g_data_width - 1 downto 0);


begin

	-- synthesis translate_off
	assert (g_prog_level < 2**g_counter_width) report "fwft_fifo: prog_level is too high!!!" severity failure;
	-- synthesis translate_on
	--=================================================================================================================================================
	-- assignment of the output signals
	--=================================================================================================================================================
	o_full      <= fifo_full;
	o_prog_full <= fifo_prog_full;

	o_empty <= output_reg_fwft_empty;

	count_corrected <= count_reg when output_reg_fwft_empty = '1' else std_logic_vector(unsigned(count_reg) + 1);

	o_count <= count_corrected(g_counter_width downto 0) when (output_reg_fwft_empty = '0') else (others => '0');

	--=================================================================================================================================================
	-- combinatorial logic
	--=================================================================================================================================================

	-- protect read and write signal from over/underflow
	write_enable_protected <= i_write_enable;

	read_enable_fwft <= '1' when output_reg_fwft_empty = '1' and fifo_empty = '0' else '0';

	-- internal read from the memory to the output register
	read_enable_protected <= '1' when (i_read_enable = '1' and fifo_empty = '0') or read_enable_fwft = '1' else '0';
	--  read_enable_protected <= '1' when (i_read_enable='1' and fifo_empty='0') else '0';

	count_is_zero <= '1' when (to_integer(unsigned(count_reg)) = 0) else '0';

	--=================================================================================================================================================
	-- clocked
	--=================================================================================================================================================

	-- fifo_memory pointer process
	fifo_proc : process(i_clk, i_rst_n)
		variable var_read_ptr : std_logic_vector(g_counter_width - 1 downto 0);
	begin
		if i_rst_n = '0' then
			write_ptr <= (others => '0');
			read_ptr  <= (others => '0');
			count_reg <= (others => '0');
				-- handle as not usable on read and write side during reset
			fifo_empty     <= '1';
			fifo_full      <= '1';
			fifo_prog_full <= '1';
			output_reg_fwft_empty <= '1';
			output_reg_fwft_empty_d1 <= '1';
			write_enable_protected_d <= '0';
			o_overflow <= '0';
			o_data_out <= (others => '0');

		elsif rising_edge(i_clk) then
			output_reg_fwft_empty_d1 <= output_reg_fwft_empty;

				--	o_data_out <= (others =>'0');
			if (fifo_full = '1') and (i_write_enable = '1') then
				-- synthesis translate_off
				assert (false) report "fifo overflow!!!" severity failure;
				-- synthesis translate_on
				o_overflow <= '1';
			end if;

			write_enable_protected_d <= write_enable_protected;

			--===================================================================================================================
			-- counter and pointers to the memory
			-- observe the fill grade of the fifo
			-- update the counter only if either read enable or write enable is set
			-- if both have the same value, do nothing since the couter value will not change
			if (write_enable_protected_d = '1') and (read_enable_protected = '0') then
				count_reg <= std_logic_vector(unsigned(count_reg) + 1);
			elsif (write_enable_protected_d = '0') and (read_enable_protected = '1') then
				count_reg <= std_logic_vector(unsigned(count_reg) - 1);
			end if;

				-- increment the write pointer when a write enable is set
			if write_enable_protected = '1' then
				write_ptr <= std_logic_vector(unsigned(write_ptr) + 1);
			-- write the data to the fifo if a write enable is set and allowed
				fifo_memory(to_integer(unsigned(write_ptr))) <= i_data_in;
			end if;

			var_read_ptr := read_ptr;
				-- increment the read pointer when a read enable is set
			if read_enable_protected = '1' then
				var_read_ptr := std_logic_vector(unsigned(var_read_ptr) + 1);
			end if;
			read_ptr <= var_read_ptr;

			mem_out_val_before_reg <= fifo_memory(to_integer(unsigned(var_read_ptr)));

			if read_enable_protected = '1' then
				o_data_out <= mem_out_val_before_reg;
				--===================================================================================================================
				-- copy the data to the output register if an internal read has happened
					-- an internal copy has happened to the output register, therfore it is not empty
				-- an internal copy has happened to the output register, therfore it is not empty
				output_reg_fwft_empty <= '0';
			end if;

			if output_reg_fwft_empty = '1' and fifo_empty = '0' then
				output_reg_fwft_empty <= '0';
			end if;

				-- no internal but an external read --> the output reg is definetly empty
			if fifo_empty = '1' and i_read_enable = '1' then
				output_reg_fwft_empty <= '1';
			end if;

			--===================================================================================================================
			-- flags
			-- check if the fifo is already empty or will be empty in the next cycle
			-- look ahead the empty for the next cycle to improve timing
			fifo_empty <= '0';
			if (count_is_zero = '1') or
			   (to_integer(unsigned(count_reg)) = 1 and read_enable_protected = '1' and write_enable_protected_d = '0') then
				fifo_empty <= '1';
			end if;

			-- check if the fifo is already full or will be full in the next cycle
			-- look ahead the full for the next cycle to improve timing
			fifo_full <= '0';
			if (to_integer(unsigned(count_reg)) >= fifo_depth - 1) or
			   (to_integer(unsigned(count_reg)) = fifo_depth - 2 and write_enable_protected_d = '1' and read_enable_protected = '0') then
				fifo_full <= '1';
			end if;

			-- simple check for the programmable full level
			fifo_prog_full <= '0';
			if to_integer(unsigned(count_reg)) >= g_prog_level then
				fifo_prog_full <= '1';
			end if;
		end if;
	end process;

end behavioral;
