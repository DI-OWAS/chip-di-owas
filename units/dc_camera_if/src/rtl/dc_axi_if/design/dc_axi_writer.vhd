--============================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH
--============================================================================================
-- Description:
--   AXI4 write master for multiple buffered input streams.
--============================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh
--============================================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.dc_base_type_pkg.all;

entity dc_axi_writer is
  generic (
    g_num_write_ports          : positive                      := 6;
    g_max_write_address_offset : std_logic_vector(31 downto 0) := (others => '1');
    C_M_AXI_BURST_LEN          : integer                       := 8;
    C_M_AXI_ID_WIDTH           : integer                       := 1;
    C_M_AXI_ADDR_WIDTH         : integer                       := 32;
    C_M_AXI_DATA_WIDTH         : integer                       := 64;
    C_M_AXI_AWUSER_WIDTH       : integer                       := 0;
    C_M_AXI_ARUSER_WIDTH       : integer                       := 0;
    C_M_AXI_WUSER_WIDTH        : integer                       := 0;
    C_M_AXI_RUSER_WIDTH        : integer                       := 0;
    C_M_AXI_BUSER_WIDTH        : integer                       := 0
  );

  port (
    -- ====================================================================
    -- Basie IF
    -- ====================================================================
    i_clk                        : in  std_logic;
    i_rst_n                      : in  std_logic;
    o_error                      : out std_logic;
    -- ====================================================================
    -- Buffer IF
    -- ====================================================================
    i_force_address_offset_reset : in  std_logic_vector(g_num_write_ports - 1 downto 0);
    i_base_address               : in  t_vec32(g_num_write_ports - 1 downto 0);
    i_buf_data                   : in  t_vec128(g_num_write_ports - 1 downto 0);
    i_buf_first                  : in  std_logic_vector(g_num_write_ports - 1 downto 0);
    i_buf_count                  : in  t_vec12(g_num_write_ports - 1 downto 0);
    i_buf_empty                  : in  std_logic_vector(g_num_write_ports - 1 downto 0);
    o_buf_read_enable            : out std_logic_vector(g_num_write_ports - 1 downto 0);
    -- ====================================================================
    -- AXI IF
    -- ====================================================================
    o_M_AXI_TX_DONE              : out std_logic;
    o_M_AXI_AWID                 : out std_logic_vector(C_M_AXI_ID_WIDTH - 1 downto 0);
    o_M_AXI_AWADDR               : out std_logic_vector(C_M_AXI_ADDR_WIDTH - 1 downto 0);
    o_M_AXI_AWLEN                : out std_logic_vector(7 downto 0);
    o_M_AXI_AWSIZE               : out std_logic_vector(2 downto 0);
    o_M_AXI_AWBURST              : out std_logic_vector(1 downto 0);
    o_M_AXI_AWLOCK               : out std_logic;
    o_M_AXI_AWCACHE              : out std_logic_vector(3 downto 0);
    o_M_AXI_AWPROT               : out std_logic_vector(2 downto 0);
    o_M_AXI_AWQOS                : out std_logic_vector(3 downto 0);
    o_M_AXI_AWUSER               : out std_logic_vector(C_M_AXI_AWUSER_WIDTH - 1 downto 0);
    o_M_AXI_AWVALID              : out std_logic;
    i_M_AXI_AWREADY              : in  std_logic;
    o_M_AXI_WDATA                : out std_logic_vector(C_M_AXI_DATA_WIDTH - 1 downto 0);
    o_M_AXI_WSTRB                : out std_logic_vector(C_M_AXI_DATA_WIDTH / 8 - 1 downto 0);
    o_M_AXI_WLAST                : out std_logic;
    o_M_AXI_WUSER                : out std_logic_vector(C_M_AXI_WUSER_WIDTH - 1 downto 0);
    o_M_AXI_WVALID               : out std_logic;
    i_M_AXI_WREADY               : in  std_logic;
    i_M_AXI_BID                  : in  std_logic_vector(C_M_AXI_ID_WIDTH - 1 downto 0);
    i_M_AXI_BRESP                : in  std_logic_vector(1 downto 0);
    i_M_AXI_BUSER                : in  std_logic_vector(C_M_AXI_BUSER_WIDTH - 1 downto 0);
    i_M_AXI_BVALID               : in  std_logic;
    o_M_AXI_BREADY               : out std_logic
  );
end entity;

architecture rtl of dc_axi_writer is

  function log2_ceil(value : positive) return natural is
    variable n : natural := value - 1;
    variable r : natural := 0;
  begin
    while n > 0 loop
      n := n / 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  constant C_BYTES_PER_BEAT  : positive := C_M_AXI_DATA_WIDTH / 8;
  constant C_BYTES_PER_BURST : positive := C_M_AXI_BURST_LEN * C_BYTES_PER_BEAT;

  type t_writer_state is (WAIT_FOR_DATA, TRANSFER_BURST);
  signal state : t_writer_state := WAIT_FOR_DATA;

  signal active_port         : natural range 0 to g_num_write_ports - 1         := 0;
  signal address_offset      : t_vec32(g_num_write_ports - 1 downto 0)          := (others => (others => '0'));
  signal address_base        : t_vec32(g_num_write_ports - 1 downto 0)          := (others => (others => '0'));
  signal pending_frame_reset : std_logic_vector(g_num_write_ports - 1 downto 0) := (others => '0');
  signal first_d             : std_logic_vector(g_num_write_ports - 1 downto 0) := (others => '0');

  signal aw_valid_reg : std_logic                                := '0';
  signal w_valid_reg  : std_logic                                := '0';
  signal b_ready_reg  : std_logic                                := '0';
  signal beat_index   : natural range 0 to C_M_AXI_BURST_LEN - 1 := 0;

  signal address_phase_done : std_logic := '0';
  signal data_phase_done    : std_logic := '0';

  signal selected_address : std_logic_vector(C_M_AXI_ADDR_WIDTH - 1 downto 0);
  signal selected_data    : std_logic_vector(C_M_AXI_DATA_WIDTH - 1 downto 0);
  signal read_enable_int  : std_logic_vector(g_num_write_ports - 1 downto 0);

begin

  assert C_M_AXI_BURST_LEN >= 1 and C_M_AXI_BURST_LEN <= 256
    report "C_M_AXI_BURST_LEN must be in the AXI4 range 1..256"
    severity failure;

  assert C_M_AXI_DATA_WIDTH mod 8 = 0
    report "C_M_AXI_DATA_WIDTH must be byte aligned"
    severity failure;

  -- Static AXI attributes.
  o_M_AXI_AWID    <= (others => '0');
  o_M_AXI_AWLEN   <= std_logic_vector(to_unsigned(C_M_AXI_BURST_LEN - 1, 8));
  o_M_AXI_AWSIZE  <= std_logic_vector(to_unsigned(log2_ceil(C_BYTES_PER_BEAT), 3));
  o_M_AXI_AWBURST <= "01";
  o_M_AXI_AWLOCK  <= '0';
  o_M_AXI_AWCACHE <= "0011";
  o_M_AXI_AWPROT  <= "000";
  o_M_AXI_AWQOS   <= (others => '0');
  o_M_AXI_AWUSER  <= (others => '1');
  o_M_AXI_WSTRB   <= (others => '1');
  o_M_AXI_WUSER   <= (others => '0');

  -- Registered channel controls.
  o_M_AXI_AWVALID <= aw_valid_reg;
  o_M_AXI_WVALID  <= w_valid_reg;
  o_M_AXI_BREADY  <= b_ready_reg;
  -- These outputs were inactive in the previous implementation and are kept compatible.
  o_M_AXI_TX_DONE <= '0';
  o_error         <= '0';

  -- Current stream is sampled through active_port for the complete burst.
  selected_address <= std_logic_vector(
    unsigned(address_base(active_port)(selected_address'range)) +
    unsigned(address_offset(active_port)(selected_address'range))
    );
  selected_data <= i_buf_data(active_port)(selected_data'range);

  o_M_AXI_AWADDR <= selected_address;
  o_M_AXI_WDATA  <= selected_data;
  o_M_AXI_WLAST  <= '1' when beat_index = C_M_AXI_BURST_LEN - 1 else '0';

  -- Pop exactly one FIFO word for each accepted AXI write-data beat.
  process (w_valid_reg, i_M_AXI_WREADY, active_port)
  begin
    read_enable_int <= (others => '0');
    if w_valid_reg = '1' and i_M_AXI_WREADY = '1' then
      read_enable_int(active_port) <= '1';
    end if;
  end process;
  o_buf_read_enable <= read_enable_int;

  -- Response channel. BREADY is pulsed for one clock after BVALID is observed.
  process (i_clk, i_rst_n)
  begin
    if i_rst_n = '0' then
      b_ready_reg <= '0';
    elsif rising_edge(i_clk) then
        if i_M_AXI_BVALID = '1' and b_ready_reg = '0' then
          b_ready_reg <= '1';
        else
          b_ready_reg <= '0';
        end if;
    end if;
  end process;

  -- Address-offset maintenance. A new frame resets the corresponding stream offset. If the
  -- frame marker appears while another burst is active, the reset is remembered and applied

  -- after that burst has finished.
  process (i_clk, i_rst_n)
    variable frame_rise : std_logic;
  begin
    if i_rst_n = '0' then
        address_offset <= (others => (others => '0'));
        address_base <= (others => (others => '0'));

        pending_frame_reset <= (others => '0');
        first_d <= (others => '0');
    elsif rising_edge(i_clk) then
        for p in 0 to g_num_write_ports - 1 loop
          frame_rise := '0';
          if i_buf_empty(p) = '0' and i_buf_first(p) = '1' and first_d(p) = '0' then
            frame_rise := '1';
          end if;

          first_d(p) <= (not i_buf_empty(p)) and i_buf_first(p);

          if i_force_address_offset_reset(p) = '1' then
            address_offset(p) <= (others => '0');
            address_base(p) <= i_base_address(p);
            pending_frame_reset(p) <= '0';
          elsif frame_rise = '1' then
            if state = WAIT_FOR_DATA then
              address_offset(p) <= (others => '0');
              address_base(p) <= i_base_address(p);
            else
              pending_frame_reset(p) <= '1';
            end if;
          elsif state = WAIT_FOR_DATA and pending_frame_reset(p) = '1' then
            address_offset(p) <= (others => '0');
            address_base(p) <= i_base_address(p);
            pending_frame_reset(p) <= '0';
          elsif data_phase_done = '1' and active_port = p then
            if unsigned(address_offset(p)) < unsigned(g_max_write_address_offset) then
              address_offset(p) <= std_logic_vector(unsigned(address_offset(p)) + to_unsigned(C_BYTES_PER_BURST, address_offset(p)'length));
            end if;
          end if;
        end loop;
    end if;
  end process;

  -- Main transfer controller. Address and data channels are started together, but each channel

  -- independently keeps VALID asserted until its own READY handshake occurs.
  process (i_clk, i_rst_n)
    variable selected : boolean;
  begin
    if i_rst_n = '0' then
        state <= WAIT_FOR_DATA;
        active_port <= 0;
        aw_valid_reg <= '0';
        w_valid_reg <= '0';
        beat_index <= 0;
        address_phase_done <= '0';
        data_phase_done <= '0';
    elsif rising_edge(i_clk) then
        data_phase_done <= '0';

        case state is
          when WAIT_FOR_DATA =>
            aw_valid_reg <= '0';
            w_valid_reg <= '0';
            beat_index <= 0;
            address_phase_done <= '0';
            selected := false;

            -- Pfixed-priority source selection: lowest ready port wins.
            for p in 0 to g_num_write_ports - 1 loop
              if not selected and to_integer(unsigned(i_buf_count(p))) >= C_M_AXI_BURST_LEN then
                active_port <= p;
                aw_valid_reg <= '1';
                w_valid_reg <= '1';
                state <= TRANSFER_BURST;
                selected := true;
              end if;
            end loop;

          when TRANSFER_BURST =>
            if aw_valid_reg = '1' and i_M_AXI_AWREADY = '1' then
              aw_valid_reg <= '0';
              address_phase_done <= '1';
            end if;

            if w_valid_reg = '1' and i_M_AXI_WREADY = '1' then
              if beat_index = C_M_AXI_BURST_LEN - 1 then
                w_valid_reg <= '0';
                data_phase_done <= '1';
              else
                beat_index <= beat_index + 1;
              end if;
            end if;

            -- the controller may accept a new source after the
            -- complete write-data burst. The AXI B response is handled independently.
            if data_phase_done = '1' then
              state <= WAIT_FOR_DATA;
            end if;
        end case;
    end if;
  end process;

end architecture;
