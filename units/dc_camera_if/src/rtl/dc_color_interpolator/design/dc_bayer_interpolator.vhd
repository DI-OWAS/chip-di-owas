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

entity dc_bayer_interpolator is
	generic(
		g_use_two_imagers : boolean := false
		--g_swap_rb_color : boolean := true -- for sony sensor
	);
	port(
		i_clk               : in  std_logic; --interpolator clock
		i_rst_n             : in  std_logic; --interpolator reset
		i_enable            : in  std_logic_vector(1 downto 0);
		i_swap_rb_color : in std_logic;

		--FIFO raw data read ports
		i_fifo_raw_data     : in  t_vec36(1 downto 0);
		i_fifo_raw_empty        : in  std_logic_vector(1 downto 0);
		o_fifo_raw_read_enable  : out std_logic_vector(1 downto 0);

		--FIFO interp data write ports
		o_fifo_interp_write_enable : out std_logic_vector(1 downto 0);
		o_fifo_interp_data  : out t_vec36(1 downto 0);
		i_fifo_interp_full         : in  std_logic_vector(1 downto 0);
		i_fifo_interp_almost_full  : in  std_logic_vector(1 downto 0);

		--parameter inputs
		--i_adc_bits          : in  std_logic_vector(3 downto 0);
		i_lines_per_frame   : in  t_vec16(1 downto 0);
		i_pixels_per_line   : in  t_vec12(1 downto 0);

		--debug outputs
		o_mux_line          : out t_vec12(1 downto 0); --output current multiplexer row
		o_last_mux_line     : out t_vec12(1 downto 0); --output last multiplexer row
		o_interp_channel    : out std_logic;
		o_filter_valid      : out std_logic;
		o_mux_data_valid    : out std_logic
	);

end dc_bayer_interpolator;

architecture Behavioral of dc_bayer_interpolator is
	type interp_state_type is (idle, waiting, interpolating); --state names for FSM

	signal interp_state      : interp_state_type;
	signal interp_enable     : std_logic_vector(1 downto 0);

	signal fifo_read_enable  : std_logic_vector(1 downto 0);
	signal fifo_write_enable : std_logic_vector(1 downto 0);

	signal frame_start       : std_logic_vector(1 downto 0);
	signal frame_start_delay : std_logic_vector(1 downto 0);

	signal stop_count_dbg    : t_vec16(1 downto 0);

	signal mux_slice         : t_vec16(4 downto 0); --output of multiplexer fed through to shifting matrix
	signal mux_line          : t_vec12(1 downto 0); --current multiplexer row
	signal last_mux_line     : t_vec12(1 downto 0); --last multiplexer row

	signal read_address      : std_logic_vector(10 downto 0);
	signal read_address_d1   : std_logic_vector(10 downto 0);
	signal read_address_d2   : std_logic_vector(10 downto 0);

	signal interp_column     : std_logic_vector(10 downto 0); --current pixel column
	signal interp_row        : t_vec12(1 downto 0); --current pixel row
	signal interp_channel    : std_logic; --current interpolation channel (0 = left, 1 = right)
	signal interp_channel_d1 : std_logic; --delayed signals
	signal interp_channel_d2 : std_logic;
	signal interp_channel_d3 : std_logic;
	signal interp_channel_d4 : std_logic;
	signal interp_channel_d5 : std_logic;
	signal interp_channel_d6 : std_logic;

	signal matrix_valid      : std_logic_vector(24 downto 0); --mask indicating which matrix entries are valid
	signal matrix            : t_vec16(24 downto 0); --matrix fed to filter
	signal first_column      : std_logic;
	signal last_column       : std_logic;

	signal mux_data_valid    : std_logic; --indicates that current mux_slice is valid
	signal mux_data_valid_d1 : std_logic; --delay 1
	signal mux_data_valid_d2 : std_logic; --delay 2
	signal mux_data_valid_d3 : std_logic; --delay 3

	signal green_pixel       : std_logic;
	signal green_pixel_d1    : std_logic;
	signal green_pixel_d2    : std_logic;

	signal red_row     : std_logic;
	signal line_ready  : std_logic_vector(1 downto 0);
	signal frame_ready : std_logic_vector(1 downto 0);

	signal filter_valid : std_logic;
	--signal filter_red   : std_logic_vector(15 downto 0);
	--signal filter_green : std_logic_vector(15 downto 0);
	--signal filter_blue  : std_logic_vector(15 downto 0);
	signal filter_rgb   : std_logic_vector(35 downto 0);


	signal s_mux_write_enable : std_logic_vector(1 downto 0);

	signal s_enable_pipeline_from_output_buffer : std_logic;

	signal s_cfg_bypass_color_interpolation : std_logic;

begin

	-- ======================================================================================================
	-- Instances
	-- ======================================================================================================

	mux_inst : entity work.dc_cfa_window_mux
		generic map(
			g_use_two_imagers => g_use_two_imagers
		)		port map(
			i_clk              => i_clk,
			i_rst_n            => i_rst_n,
			i_pipeline_enable  => s_enable_pipeline_from_output_buffer,

			--MUX interface
			i_pixels_per_line  => i_pixels_per_line,
			i_mux_data         => i_fifo_raw_data,
			i_mux_write_enable => s_mux_write_enable,
			i_mux_read_address => read_address,
			i_mux_read_channel => interp_channel_d2,
			o_mux_slice        => mux_slice,
			o_mux_line         => mux_line

		--o_mux_debug        => mux_debug
		);

	matrix_inst : entity work.dc_cfa_camera_matrix
		port map(
			-- basic IF
			i_clk             => i_clk,
			i_rst_n           => i_rst_n,
			i_pipeline_enable => s_enable_pipeline_from_output_buffer,

			-- matrix IF
			i_slice        => mux_slice,
			i_shift        => mux_data_valid_d2,
			i_first_column => first_column,
			i_last_column  => last_column,
			o_valid        => matrix_valid,
			o_matrix       => matrix
		);

	filter_inst : entity work.dc_cfa_bayer_filter
		--generic map(
		--	g_swap_rb_color => g_swap_rb_color
		--)
		port map(
			--basic IF
			i_clk          => i_clk,
			i_rst_n        => i_rst_n,
			i_pipeline_enable => s_enable_pipeline_from_output_buffer,
			i_swap_rb_color => i_swap_rb_color,

			--filter IF
			i_matrix_valid => matrix_valid,
			i_green_pixel  => green_pixel_d2,
			i_red_row      => red_row,
			i_matrix       => matrix,
			--i_adc_bits     => i_adc_bits,
			o_color_valid  => filter_valid,
			o_red          => open,
			o_green        => open,
			o_blue         => open,
			o_rgb          => filter_rgb(31 downto 0)
		);


	-- ======================================================================================================
	-- Assignments
	-- ======================================================================================================


	o_fifo_interp_data(0) <= filter_rgb;
	o_fifo_interp_data(1) <= filter_rgb;
	o_fifo_raw_read_enable    <= fifo_read_enable and (not i_fifo_raw_empty);
	o_fifo_interp_write_enable  <= fifo_write_enable;
	o_mux_line       <= mux_line;
	o_last_mux_line  <= last_mux_line;
	o_interp_channel <= interp_channel;
	o_filter_valid   <= filter_valid;
	o_mux_data_valid <= mux_data_valid;

	s_mux_write_enable <= interp_enable and fifo_read_enable and (not i_fifo_raw_empty);

	frame_start(0) <= i_fifo_raw_data(0)(32);
	frame_start(1) <= i_fifo_raw_data(1)(32);

	fifo_write_enable(0) <= filter_valid and (not interp_channel_d6);
	fifo_write_enable(1) <= filter_valid and interp_channel_d6;

	filter_rgb(35 downto 34) <= "00";   --two upper bits not used at the moment

	-- ======================================================================================================
	-- Processes
	-- ======================================================================================================


	process(i_clk, i_rst_n)
		variable delay_count0 : integer := 0;
		variable delay_count1 : integer := 0;

	begin
		if i_rst_n = '0' then
				delay_count0 := 0;
				delay_count1 := 0;
		elsif rising_edge(i_clk) then
				if (interp_enable(0) = '1') and (i_fifo_raw_empty(0) = '0') then
					delay_count0 := delay_count0 + 1;
				end if;

				if (interp_enable(1) = '1') and (i_fifo_raw_empty(1) = '0') then
					delay_count1 := delay_count1 + 1;
				end if;

				fifo_read_enable <= "00";

				if (interp_enable(0) = '1') and (i_fifo_raw_empty(0) = '0') and (delay_count0 > 2) and (i_fifo_interp_almost_full(0) = '0')  then
					fifo_read_enable(0) <= '1';
				elsif (interp_enable(1) = '1') and (i_fifo_raw_empty(1) = '0') and (delay_count1 > 2)  and (i_fifo_interp_almost_full(1) = '0') then
					fifo_read_enable(1) <= '1';
				end if;

				if (i_fifo_raw_empty(0) = '1') then
					delay_count0 := 0;
				end if;

				if (i_fifo_raw_empty(1) = '1') then
					delay_count1 := 0;
				end if;

		end if;
	end process;

	-- halt processing dependent on output buffer fill grade
	s_enable_pipeline_from_output_buffer <= not i_fifo_interp_almost_full(0) when interp_channel = '0' else
	                                        not i_fifo_interp_almost_full(1);

	process(i_clk, i_rst_n)
		variable stop_count   : t_vec16(1 downto 0);
		variable interp_index : integer range 0 to 1;
		variable logic_index  : std_logic;

	begin
		if i_rst_n = '0' then
				interp_state     <= idle;

				interp_enable <= (others => '0');

				interp_column   <= (others => '0');
				read_address    <= (others => '0');
				read_address_d1 <= (others => '0');
				read_address_d2 <= (others => '0');
				interp_column   <= (others => '0');

				interp_row(0) <= (others => '0');
				interp_row(1) <= (others => '0');

				last_mux_line(0) <= (others => '0');
				last_mux_line(1) <= (others => '0');

				frame_start_delay(0) <= '0';
				frame_start_delay(1) <= '0';

				line_ready(0) <= '0';
				line_ready(1) <= '0';

				frame_ready(0) <= '0';
				frame_ready(1) <= '0';

				green_pixel    <= '0';
				green_pixel_d1 <= '0';
				green_pixel_d2 <= '0';

				mux_data_valid    <= '0';
				mux_data_valid_d1 <= '0';
				mux_data_valid_d2 <= '0';
				mux_data_valid_d3 <= '0';
				first_column     <= '0';
				filter_rgb(33 downto 32) <= "00";

				interp_channel    <= '0';
				interp_channel_d1 <= '0';
				interp_channel_d2 <= '0';
				interp_channel_d3 <= '0';
				interp_channel_d4 <= '0';
				interp_channel_d5 <= '0';
				interp_channel_d6 <= '0';

		elsif rising_edge(i_clk) then


			-- ======================================================================================================
			-- pipelining
			if s_enable_pipeline_from_output_buffer ='1' then
				--generate delayed signals
				green_pixel_d2 <= green_pixel_d1;
				green_pixel_d1 <= green_pixel;

				mux_data_valid_d3 <= mux_data_valid_d2;
				mux_data_valid_d2 <= mux_data_valid_d1;
				mux_data_valid_d1 <= mux_data_valid;

				interp_channel_d6 <= interp_channel_d5;
				interp_channel_d5 <= interp_channel_d4;
				interp_channel_d4 <= interp_channel_d3;
				interp_channel_d3 <= interp_channel_d2;
				interp_channel_d2 <= interp_channel_d1;
				interp_channel_d1 <= interp_channel;

				interp_column   <= read_address_d2;
				read_address_d2 <= read_address_d1;
				read_address_d1 <= read_address;

				--synchronise enable input with frame start
				for i in 0 to 1 loop
					if (frame_start(i) = '1') and (frame_start_delay(i) = '0') then
						interp_enable(i) <= i_enable(i);
					end if;
				end loop;

				frame_start_delay <= frame_start;

				if red_row = '0' then
					green_pixel <= interp_column(0);
				else
					green_pixel <= not interp_column(0);
				end if;
			end if;
			-- ======================================================================================================

			if s_enable_pipeline_from_output_buffer = '1' then
				if (mux_data_valid_d2 = '1') and (mux_data_valid_d3 = '0') then
					first_column <= '1';
				else
					first_column <= '0';
				end if;

				case (interp_state) is
					when idle =>
						--wait for either camera interface to count lines per frame
						for i in 0 to 1 loop
								if (i = 0) then
									logic_index := '0';
								else
									logic_index := '1';
								end if;

							if (unsigned(i_lines_per_frame(i)) > 0) and (unsigned(mux_line(i)) = 5) then
								mux_data_valid    <= '0'; --multiplexer output not valid yet
								mux_data_valid_d1 <= '0'; --reset delayed signals
								mux_data_valid_d2 <= '0';
								mux_data_valid_d3 <= '0';
								last_column       <= '0';
								interp_state      <= interpolating; --then start interpolation process
								interp_channel    <= logic_index; --with left camera channel
								last_mux_line(i)  <= "000000000100"; -- "remember" fourth line
								line_ready(i)     <= '0'; --starting a new line
							end if;
						end loop;

					when waiting =>
						mux_data_valid <= '0';

						if filter_valid = '0' then --wait for filter pipeline to finish line
							for i in 0 to 1 loop
								if (i = 0) then
									logic_index := '0';
								else
									logic_index := '1';
								end if;

								if (line_ready(i) = '1') then
									if (unsigned(mux_line(i)) > unsigned(last_mux_line(i))) then
										interp_channel   <= logic_index;
										interp_state     <= interpolating;
										line_ready(i)    <= '0';
									end if;
								else
									if (unsigned(mux_line(i)) = 5) then
										interp_channel   <= logic_index; --start left camera channel
										last_mux_line(i) <= "000000000100"; -- "remember" fourth line
										frame_ready(i)   <= '0';
										interp_state     <= interpolating;
									end if;
								end if;

								stop_count(i) := std_logic_vector(signed(i_lines_per_frame(i)) - 1);

								if unsigned(i_lines_per_frame(i)) > 0 then
									if (last_mux_line(i) = stop_count(i)) then
										frame_ready(i)    <= '1';
										line_ready(i)     <= '0';
										interp_row(i)     <= (others => '0');
										last_mux_line(i)  <= (others => '0');
										mux_data_valid    <= '0'; --multiplexer output not valid yet
										mux_data_valid_d1 <= '0'; --reset delayed signals
										mux_data_valid_d2 <= '0';
										mux_data_valid_d3 <= '0';
									end if;
								end if;
							end loop;

							stop_count_dbg <= stop_count;

							if (frame_ready = "11") then
								frame_ready      <= "00";
								line_ready       <= "00";
								interp_state     <= idle;
							end if;
						end if;

					when interpolating =>

						-- ======================================================================================================
						-- pipelining
						if s_enable_pipeline_from_output_buffer ='1' then

							last_column <= '0';

							if (unsigned(read_address) = 0) then
								mux_data_valid <= '1'; --multiplexer output will be valid in three cycles
							end if;

							if first_column = '1' then
								filter_rgb(33) <= '1'; --set bit 33 to mark line start in FIFO data stream
								if (interp_channel = '0') and (interp_row(0) = "000000000000") then
									filter_rgb(32) <= '1'; --set bit 32 to mark frame start in FIFO data stream
								end if;
								if (interp_channel = '1') and (interp_row(1) = "000000000000") then
									filter_rgb(32) <= '1'; --set bit 32 to mark frame start in FIFO data stream
								end if;
							end if;

							read_address <= std_logic_vector(unsigned(read_address) + 1);

							if interp_channel = '0' then
								interp_index := 0;
							else
								interp_index := 1;
							end if;

							red_row <= interp_row(interp_index)(0);

							--check if all pixels in a line have been processed
							if (unsigned(read_address) = (unsigned(i_pixels_per_line(interp_index))-1) ) then
								read_address                <= (others => '0'); --reset read address and
								interp_row(interp_index)    <= std_logic_vector(unsigned(interp_row(interp_index)) + 1); --switch to next row
								last_mux_line(interp_index) <= mux_line(interp_index);
								line_ready(interp_index)    <= '1'; --finished a line
								interp_state                <= waiting;
							end if;
						end if;
						-- ======================================================================================================

				end case;
			end if;

			-- The output valid is a pulse: the FIFO also accepts the last result
			-- on the first stopped cycle. Clear its markers even while stalled.
			if filter_valid = '1' then
				filter_rgb(33 downto 32) <= "00";
			end if;
		end if;
	end process;

end Behavioral;
