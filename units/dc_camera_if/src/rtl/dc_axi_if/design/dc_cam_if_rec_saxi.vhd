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

  use work.dc_base_type_pkg.all;
  use work.dc_cam_if_saxi_pkg.all;
  use work.dc_constants_pkg.all;
  
entity dc_cam_if_rec_saxi is
  generic (
    g_pixel_histogram_bin_depth : integer := 16;
    g_pixel_histogram_bit_num   : integer;
    -- Do not modify the parameters beyond this line
    -- Width of S_AXI data bus
    C_S_AXI_DATA_WIDTH : integer := 32;
    -- Width of S_AXI address bus
    C_S_AXI_ADDR_WIDTH : integer := 18
  );
  port (
    -- =================================================================================================
    -- global control
    -- =================================================================================================
    o_soft_reset             : out std_logic;
    -- =================================================================================================
    -- register configuration records
    -- =================================================================================================
    o_register_config_cam_if : out register_config_cam_if_r;
    i_status_cam_if          : in  status_cam_if_r;

    -- =================================================================================================
    -- output data interface
    -- =================================================================================================
    o_output_if_cmd : out std_logic_vector(47 downto 0);
    o_output_if_cmd_write_enable : out std_logic;
    i_output_if_cmd_full : in std_logic;


    -- =================================================================================================
    -- intensity histogram
    -- =================================================================================================
    o_histogram_address     : out  std_logic_vector(g_pixel_histogram_bit_num - 1 downto 0);   --pixel histogram read address
    i_histogram_data        : in std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0); --histogram bin value

    -- =================================================================================================
    i_clk                    : in  std_logic;
    i_rst_n                  : in  std_logic;
    s_axi_awaddr             : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    s_axi_awprot             : in  std_logic_vector(2 downto 0);
    s_axi_awvalid            : in  std_logic;
    s_axi_awready            : out std_logic;
    s_axi_wdata              : in  std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    s_axi_wstrb              : in  std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
    s_axi_wvalid             : in  std_logic;
    s_axi_wready             : out std_logic;
    s_axi_bresp              : out std_logic_vector(1 downto 0);
    s_axi_bvalid             : out std_logic;
    s_axi_bready             : in  std_logic;
    s_axi_araddr             : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    s_axi_arprot             : in  std_logic_vector(2 downto 0);
    s_axi_arvaid             : in  std_logic;
    s_axi_arready            : out std_logic;
    s_axi_rdata              : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    s_axi_rreesp             : out std_logic_vector(1 downto 0);
    s_axi_rvalid             : out std_logic;
    s_axi_rready             : in  std_logic
  );
end entity;

architecture arch_imp of dc_cam_if_rec_saxi is

  --=====================================================================================================
  -- constants
  --=====================================================================================================
  constant c_internal_address_msb : integer := C_S_AXI_ADDR_WIDTH;

  constant c_msb_memory_addresses : integer := 30;
  constant c_lsb_memory_addresses : integer := 0;

  --=====================================================================================================
  -- signals
  --=====================================================================================================
  signal axi_awaddr    : std_logic_vector(c_internal_address_msb - 1 downto 0);
  signal axi_awaddr_d1 : std_logic_vector(c_internal_address_msb - 1 downto 0);
  signal axi_wdata_d1  : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
  signal axi_awready   : std_logic;
  signal axi_wready    : std_logic;
  signal axi_bresp     : std_logic_vector(1 downto 0);
  signal axi_bvalid    : std_logic;
  signal axi_araddr    : std_logic_vector(c_internal_address_msb - 1 downto 0);
  signal axi_arready   : std_logic;
  signal axi_rdata     : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
  signal axi_rresp     : std_logic_vector(1 downto 0);
  signal axi_rvalid    : std_logic;

  ---- internal registers
  signal s_cam_if_rec_control : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);

  signal s_reg_data_out : std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);

  signal s_reg_wren    : std_logic;
  signal s_reg_wren_d1 : std_logic;

  signal s_reg_rden : std_logic;

  signal s_register_config_cam_if    : register_config_cam_if_r;
  signal s_register_config_cam_if_d1 : register_config_cam_if_r;


  signal s_soft_reset      : std_logic;


	-- signals for histogram 
	signal pixel_histogram_data    : std_logic_vector(g_pixel_histogram_bin_depth - 1 downto 0);
	signal pixel_histogram_address : std_logic_vector(g_pixel_histogram_bit_num - 1 downto 0);


  signal s_output_if_cmd : std_logic_vector(47 downto 0);
  signal s_output_if_cmd_write_enable : std_logic;



begin

  --=====================================================================================================
  -- output assignments
  --=====================================================================================================
  o_register_config_cam_if <= s_register_config_cam_if_d1;
  o_soft_reset <= s_soft_reset;

  	o_histogram_address <= pixel_histogram_address;



  o_output_if_cmd <= s_output_if_cmd;
  o_output_if_cmd_write_enable <= s_output_if_cmd_write_enable;

  -- I/O Connections assignments
  s_axi_awready <= axi_awready;
  s_axi_wready  <= axi_wready;
  s_axi_bresp   <= axi_bresp;
  s_axi_bvalid  <= axi_bvalid;
  s_axi_arready <= axi_arready;
  s_axi_rdata   <= axi_rdata;
  s_axi_rreesp  <= axi_rresp;
  s_axi_rvalid  <= axi_rvalid;

  axi_rdata <= s_reg_data_out; -- register read data


	pixel_histogram_address <= axi_araddr(g_pixel_histogram_bit_num - 1 + 2 downto 2);
	pixel_histogram_data <= i_histogram_data;


  --=====================================================================================================
  -- internal assignments & combinatorial
  --=====================================================================================================
  axi_awaddr_d1(1 downto 0) <= "00"; -- [AG] fix unassigned bits

  s_reg_wren <= axi_wready and s_axi_wvalid and axi_awready and s_axi_awvalid;
  --=====================================================================================================
  -- processes
  --=====================================================================================================

  --register write process
  process (i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      s_reg_wren_d1 <= '0';
      axi_awaddr_d1(axi_awaddr_d1'length - 1 downto 2) <= (others => '0');
      axi_wdata_d1 <= (others => '0');
      s_soft_reset <= '0';
      s_output_if_cmd <= (others => '0');
      s_output_if_cmd_write_enable <= '0';
        --===============================================================================
        -- recording
        --===============================================================================
      s_cam_if_rec_control <= (others => '0');
      s_cam_if_rec_control(0) <= '1';
      s_register_config_cam_if.ddr_mem_start_address(0) <= c_default_base_address_image_write_0;
      s_register_config_cam_if.ddr_mem_start_address(1) <= c_default_base_address_image_write_1;
      s_register_config_cam_if.ddr_mem_start_address(2) <= c_default_base_address_image_write_2;
      s_register_config_cam_if.ddr_mem_start_address(3) <= c_default_base_address_image_write_3;
      s_register_config_cam_if.enable_imager <= '0';
      s_register_config_cam_if.swap_rb_color <= '1';
      s_register_config_cam_if.bypass_debayering <= '0';
      s_register_config_cam_if.lines_per_frame <= std_logic_vector(to_unsigned(c_dc_lines_per_frame, 16));
      s_register_config_cam_if.pixels_per_line <= std_logic_vector(to_unsigned(c_dc_pixels_per_line, 12));


      s_register_config_cam_if_d1.ddr_mem_start_address(0) <= c_default_base_address_image_write_0;
      s_register_config_cam_if_d1.ddr_mem_start_address(1) <= c_default_base_address_image_write_1;
      s_register_config_cam_if_d1.ddr_mem_start_address(2) <= c_default_base_address_image_write_2;
      s_register_config_cam_if_d1.ddr_mem_start_address(3) <= c_default_base_address_image_write_3;
      s_register_config_cam_if_d1.enable_imager <= '0';
      s_register_config_cam_if_d1.swap_rb_color <= '1';
      s_register_config_cam_if_d1.bypass_debayering <= '0';
      s_register_config_cam_if_d1.lines_per_frame <= std_logic_vector(to_unsigned(c_dc_lines_per_frame, 16));
      s_register_config_cam_if_d1.pixels_per_line <= std_logic_vector(to_unsigned(c_dc_pixels_per_line, 12));

      
    elsif rising_edge(i_clk) then
      --update changes made in previous clock cycle
      s_reg_wren_d1 <= s_reg_wren;
      axi_awaddr_d1(axi_awaddr_d1'length - 1 downto 2) <= axi_awaddr(axi_awaddr_d1'length - 1 downto 2);
      axi_wdata_d1 <= s_axi_wdata;

      s_register_config_cam_if_d1 <= s_register_config_cam_if;
      s_soft_reset <= '0';
      s_output_if_cmd_write_enable <= '0';

      if (s_reg_wren_d1 = '1') then
        case to_integer(unsigned(axi_awaddr_d1(c_internal_address_msb - 1 downto 0))) is
            --===============================================================================
            -- recording
            --===============================================================================
          when reg_addr_control =>
            s_cam_if_rec_control <= axi_wdata_d1;
            s_register_config_cam_if.enable_imager <= axi_wdata_d1(0);
            s_register_config_cam_if.bypass_debayering <= axi_wdata_d1(1);
            s_register_config_cam_if.swap_rb_color <= axi_wdata_d1(2);

          when reg_addr_soft_reset =>
            if axi_wdata_d1(0) = '1' then
              s_soft_reset <= '1';
            end if;

          when reg_cam_if_image_geometry =>
            s_register_config_cam_if.lines_per_frame <= axi_wdata_d1(15 downto 0);
            s_register_config_cam_if.pixels_per_line <= axi_wdata_d1(27 downto 16);

          when reg_cam_if_ddr_mem_start_address_0 =>
            s_register_config_cam_if.ddr_mem_start_address(0) <= axi_wdata_d1;

          when reg_cam_if_ddr_mem_start_address_1 =>
            s_register_config_cam_if.ddr_mem_start_address(1) <= axi_wdata_d1;

          when reg_cam_if_ddr_mem_start_address_2 =>
            s_register_config_cam_if.ddr_mem_start_address(2) <= axi_wdata_d1;

          when reg_cam_if_ddr_mem_start_address_3 =>
            s_register_config_cam_if.ddr_mem_start_address(3) <= axi_wdata_d1;

            -- =======================================================
          when reg_cam_if_out_if_mem_rd_address =>
            s_output_if_cmd(31 downto 0) <= axi_wdata_d1;

          when reg_cam_if_out_if_data_len_and_trigger_address =>
            s_output_if_cmd(47 downto 32) <= axi_wdata_d1(15 downto 0);
            s_output_if_cmd_write_enable <= '1';

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  process (i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      s_reg_data_out <= (others => '0');
    elsif rising_edge(i_clk) then
        if (s_reg_rden = '1') then
          s_reg_data_out <= (others => '0');

          case to_integer(unsigned(axi_araddr(c_internal_address_msb - 1 downto 0))) is

            when reg_addr_version_id =>
              s_reg_data_out <= x"0100001a";

            when reg_addr_control =>
              s_reg_data_out <= s_cam_if_rec_control;

            when reg_addr_status =>
              s_reg_data_out <= i_status_cam_if.status;

            when reg_addr_soft_reset =>
              s_reg_data_out <= (others => '0');

            when reg_cam_if_buffer_index =>
              s_reg_data_out(1 downto 0) <= i_status_cam_if.buffer_index;

            when reg_cam_if_pixel_count =>
              s_reg_data_out(15 downto 0) <= i_status_cam_if.pixel_count;

            when reg_cam_if_line_count =>
              s_reg_data_out(15 downto 0) <= i_status_cam_if.line_count;

            when reg_cam_if_frame_counter =>
              s_reg_data_out(15 downto 0) <= i_status_cam_if.frame_counter;

            when reg_cam_if_buffer_status =>
              s_reg_data_out(31 downto 0) <= i_status_cam_if.buffer_status;

            --===============================================================================
            when reg_cam_if_ddr_mem_start_address_0 =>
              s_reg_data_out <= s_register_config_cam_if.ddr_mem_start_address(0);

            when reg_cam_if_ddr_mem_start_address_1 =>
              s_reg_data_out <= s_register_config_cam_if.ddr_mem_start_address(1);

            when reg_cam_if_ddr_mem_start_address_2 =>
              s_reg_data_out <= s_register_config_cam_if.ddr_mem_start_address(2);

            when reg_cam_if_ddr_mem_start_address_3 =>
              s_reg_data_out <= s_register_config_cam_if.ddr_mem_start_address(3);



            -- =======================================================
            when reg_cam_if_out_if_mem_rd_address =>
              s_reg_data_out <= s_output_if_cmd(31 downto 0);

            when reg_cam_if_out_if_data_len_and_trigger_address =>
              s_reg_data_out <= i_output_if_cmd_full & b"000000000000000" & s_output_if_cmd(47 downto 32);

            when reg_cam_if_clock_counter =>
              s_reg_data_out <= i_status_cam_if.clock_counter;

            when reg_cam_if_image_geometry =>
              s_reg_data_out(15 downto 0) <= s_register_config_cam_if.lines_per_frame;
              s_reg_data_out(27 downto 16) <= s_register_config_cam_if.pixels_per_line;
              


            --===============================================================================
						-- Address decoding for reading histogram registers
						when reg_cam_histogram_base_address + 1023 downto reg_cam_histogram_base_address =>
							s_reg_data_out(g_pixel_histogram_bin_depth - 1 downto 0) <= pixel_histogram_data;


            when others =>
              s_reg_data_out <= (others => '0');

          end case;
          --=========================================================================================================
        end if;
    end if;
  end process;

  --=====================================================================================================
  -- AXI logic
  --=====================================================================================================

  -- A register read is started when a read address is accepted and no previous
  -- read response is pending.
  s_reg_rden <= axi_arready and s_axi_arvaid and (not axi_rvalid);

  process (i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
        axi_awready <= '0';
        axi_awaddr  <= (others => '0');
        axi_wready  <= '0';
        axi_bvalid  <= '0';
        axi_bresp   <= "00";

        axi_arready <= '0';
        axi_araddr  <= (others => '1');
        axi_rvalid  <= '0';
        axi_rresp   <= "00";

    elsif rising_edge(i_clk) then
        -- Default values for the one-cycle address/data acceptance strobes.
        axi_awready <= '0';
        axi_wready  <= '0';
        axi_arready <= '0';

        -- Write address and data are accepted together. The address is aligned
        -- to the 32-bit register boundary before it is stored internally.
        if (axi_awready = '0' and axi_wready = '0' and
            s_axi_awvalid = '1' and s_axi_wvalid = '1') then
          axi_awready <= '1';
          axi_wready  <= '1';
          axi_awaddr  <= s_axi_awaddr(c_internal_address_msb - 1 downto 2) & "00";
        end if;

        -- Generate the write response after a write transfer has been accepted.
        if (axi_awready = '1' and s_axi_awvalid = '1' and
            axi_wready = '1' and s_axi_wvalid = '1' and
            axi_bvalid = '0') then
          axi_bvalid <= '1';
          axi_bresp  <= "00";
        elsif (axi_bvalid = '1' and s_axi_bready = '1') then
          axi_bvalid <= '0';
        end if;

        -- Accept a new read address only while no address handshake is active.
        if (axi_arready = '0' and s_axi_arvaid = '1') then
          axi_arready <= '1';
          axi_araddr  <= s_axi_araddr(c_internal_address_msb - 1 downto 2) & "00";
        end if;

        -- Hold the read response valid until it has been accepted by the master.
        if (axi_arready = '1' and s_axi_arvaid = '1' and axi_rvalid = '0') then
          axi_rvalid <= '1';
          axi_rresp  <= "00";
        elsif (axi_rvalid = '1' and s_axi_rready = '1') then
          axi_rvalid <= '0';
        end if;
    end if;
  end process;


end architecture;
