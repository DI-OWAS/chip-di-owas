--============================================================================================
-- Copyright: 
--   2026 DC Vision Systems GmbH
--============================================================================================
-- Description:
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh,
--   Andreas Gruebl
--============================================================================================


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dc_standard_sdp_ram is
	generic(
		g_data_width                : positive  := 8;
		g_addr_width                : positive  := 8;
		g_write_first               : boolean   := false;
		g_data_reg                  : boolean   := false;
		g_ram_style                 : string    := "block";
		g_max_fanout                : string    := "10000";
		g_bit_init                  : std_logic := '1';
		g_data_init                 : std_logic_vector(255 downto 0) := (others => '1'); --max
		g_use_reset_output_value : boolean := true;
		g_use_non_pow2_num_elements : boolean   := false;
		g_non_pow2_num_elements    : integer   := 128
	);

	port(
		i_clk           : in  std_logic;
		i_rst_n         : in  std_logic;
		i_write_address : in  std_logic_vector(g_addr_width - 1 downto 0);
		i_write_data    : in  std_logic_vector(g_data_width - 1 downto 0);
		i_write_enable  : in  std_logic;
		i_read_address  : in  std_logic_vector(g_addr_width - 1 downto 0);
		o_read_data     : out std_logic_vector(g_data_width - 1 downto 0)
	);

end dc_standard_sdp_ram;

architecture behavioral_ihp of dc_standard_sdp_ram is

	component RM_IHPSG13_1P_1024x32_c2_bm_bist is
    port (
        -- Port A
        A_CLK       : in  std_logic;
        A_MEN       : in  std_logic;
        A_WEN       : in  std_logic;
        A_REN       : in  std_logic;
        A_ADDR      : in  std_logic_vector(9 downto 0);
        A_DIN       : in  std_logic_vector(31 downto 0);
        A_DLY       : in  std_logic;
        A_DOUT      : out std_logic_vector(31 downto 0);
        A_BM        : in  std_logic_vector(31 downto 0);

        A_BIST_CLK  : in  std_logic;
        A_BIST_EN   : in  std_logic;
        A_BIST_MEN  : in  std_logic;
        A_BIST_WEN  : in  std_logic;
        A_BIST_REN  : in  std_logic;
        A_BIST_ADDR : in  std_logic_vector(9 downto 0);
        A_BIST_DIN  : in  std_logic_vector(31 downto 0);
        A_BIST_BM   : in  std_logic_vector(31 downto 0)
    );
	end component;

	signal write_data_local : std_logic_vector(31 downto 0);
	signal read_data_local  : std_logic_vector(31 downto 0);
    signal ram_address : std_logic_vector(g_addr_width - 1 downto 0);

begin
    -- Single-port RAM: read by default, write when enabled.
    ram_address <= i_write_address when i_write_enable = '1' else i_read_address;

	u_ram : RM_IHPSG13_1P_1024x32_c2_bm_bist
	port map (
	    -- Port A
	    A_CLK       => i_clk,
	    A_MEN       => '1',
	    A_WEN       => i_write_enable,
	    A_REN       => not i_write_enable,
	    A_ADDR      => ram_address,
	    A_DIN       => write_data_local,
	    A_DLY       => '1',
	    A_DOUT      => read_data_local,
	    A_BM        => (others => '1'),
	
	    -- Port A BIST (disabled)
	    A_BIST_CLK  => '0',
	    A_BIST_EN   => '0',
	    A_BIST_MEN  => '0',
	    A_BIST_WEN  => '0',
	    A_BIST_REN  => '0',
	    A_BIST_ADDR => (others => '0'),
	    A_BIST_DIN  => (others => '0'),
	    A_BIST_BM   => (others => '0')
	);

	write_data_local <= (23 downto 0 => i_write_data, others => '0');
    o_read_data      <= read_data_local(23 downto 0);

end behavioral_ihp;
