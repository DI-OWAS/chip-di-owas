-- ======================================================================================================
-- Copyright:
--   2026 DC Vision Systems GmbH
-- ======================================================================================================
-- Description:
--   AXI4 read master with multiple command sources.
--
--   Command format (48 bit):
--     [47:32] : transfer length minus one, in AXI data words
--               x"0000" = 1 word, x"FFFF" = 65536 words
--     [31:0]  : byte address of the first word
--
--   Commands longer than one AXI burst are split into multiple INCR bursts.
--   o_read_first is asserted together with o_read_valid for the first accepted
--   data word of each command.
-- ======================================================================================================
-- Authors:
--   Frederik Lange, David Madlener, Maximilian Singh
-- ======================================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.dc_base_type_pkg.all;

entity dc_axi_reader is
  generic(
    g_num_read_ports     : natural := 1;
    C_M_AXI_BURST_LEN    : integer := 64;
    C_M_AXI_ID_WIDTH     : integer := 1;
    C_M_AXI_ADDR_WIDTH   : integer := 32;
    C_M_AXI_DATA_WIDTH   : integer := 64;
    C_M_AXI_ARUSER_WIDTH : integer := 0;
    C_M_AXI_RUSER_WIDTH  : integer := 0
  );

  port(
    -- external interface
    i_clk                 : in  std_logic;
    i_rst_n               : in  std_logic;
    o_error               : out std_logic;

    -- read command interface
    i_command             : in  t_vec48(g_num_read_ports - 1 downto 0);
    i_command_queue_empty : in  std_logic_vector(g_num_read_ports - 1 downto 0);
    o_command_read_enable : out std_logic_vector(g_num_read_ports - 1 downto 0);

    -- read data interface
    o_read_data           : out std_logic_vector(C_M_AXI_DATA_WIDTH - 1 downto 0);
    o_read_valid          : out std_logic_vector(g_num_read_ports - 1 downto 0);
    o_read_first          : out std_logic;
    o_read_last           : out std_logic;
    i_read_stop           : in  std_logic_vector(g_num_read_ports - 1 downto 0);

    -- AXI4 read address channel
    o_M_AXI_ARID          : out std_logic_vector(C_M_AXI_ID_WIDTH - 1 downto 0);
    o_M_AXI_ARADDR        : out std_logic_vector(C_M_AXI_ADDR_WIDTH - 1 downto 0);
    o_M_AXI_ARLEN         : out std_logic_vector(7 downto 0);
    o_M_AXI_ARSIZE        : out std_logic_vector(2 downto 0);
    o_M_AXI_ARBURST       : out std_logic_vector(1 downto 0);
    o_M_AXI_ARLOCK        : out std_logic;
    o_M_AXI_ARCACHE       : out std_logic_vector(3 downto 0);
    o_M_AXI_ARPROT        : out std_logic_vector(2 downto 0);
    o_M_AXI_ARQOS         : out std_logic_vector(3 downto 0);
    o_M_AXI_ARUSER        : out std_logic_vector(C_M_AXI_ARUSER_WIDTH - 1 downto 0);
    o_M_AXI_ARVALID       : out std_logic;
    i_M_AXI_ARREADY       : in  std_logic;

    -- AXI4 read data channel
    i_M_AXI_RID           : in  std_logic_vector(C_M_AXI_ID_WIDTH - 1 downto 0);
    i_M_AXI_RDATA         : in  std_logic_vector(C_M_AXI_DATA_WIDTH - 1 downto 0);
    i_M_AXI_RRESP         : in  std_logic_vector(1 downto 0);
    i_M_AXI_RLAST         : in  std_logic;
    i_M_AXI_RUSER         : in  std_logic_vector(C_M_AXI_RUSER_WIDTH - 1 downto 0);
    i_M_AXI_RVALID        : in  std_logic;
    o_M_AXI_RREADY        : out std_logic
  );
end dc_axi_reader;

architecture implementation of dc_axi_reader is

  -- ======================================================================================================
  -- Functions
  -- ======================================================================================================

  function f_log2(value : positive) return natural is
    variable v_value  : natural := value - 1;
    variable v_result : natural := 0;
  begin
    while v_value > 0 loop
      v_value  := v_value / 2;
      v_result := v_result + 1;
    end loop;
    return v_result;
  end function;

  function f_min(a : natural; b : natural) return natural is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  -- ======================================================================================================
  -- Constants and types
  -- ======================================================================================================

  constant C_BYTES_PER_WORD  : natural := C_M_AXI_DATA_WIDTH / 8;
  constant C_MAX_BURST_WORDS : natural := f_min(C_M_AXI_BURST_LEN, 256);

  type t_read_state is (
    idle,
    prepare_burst,
    send_address,
    receive_data
  );

  -- ======================================================================================================
  -- Internal signals
  -- ======================================================================================================

  signal read_state          : t_read_state;
  signal active_port         : natural range 0 to g_num_read_ports - 1;

  signal command_read_enable : std_logic_vector(g_num_read_ports - 1 downto 0);

  signal address_reg         : std_logic_vector(C_M_AXI_ADDR_WIDTH - 1 downto 0);
  signal remaining_words     : unsigned(16 downto 0);
  signal burst_words         : unsigned(8 downto 0);

  signal arvalid_reg         : std_logic;
  signal rready_int          : std_logic;
  signal first_word_pending  : std_logic;
  signal error_reg           : std_logic;

begin

  -- ======================================================================================================
  -- Parameter checks
  -- ======================================================================================================

  -- synthesis translate_off
  assert g_num_read_ports > 0 report "dc_axi_reader: g_num_read_ports must be greater than zero" severity failure;
  -- synthesis translate_on

  -- synthesis translate_off
  assert C_M_AXI_BURST_LEN >= 1 and C_M_AXI_BURST_LEN <= 256 report "dc_axi_reader: C_M_AXI_BURST_LEN must be in the range 1 to 256" severity failure;
  -- synthesis translate_on

  -- synthesis translate_off
  assert C_M_AXI_DATA_WIDTH = 32 or C_M_AXI_DATA_WIDTH = 64 report "dc_axi_reader: only 32-bit and 64-bit AXI data widths are supported" severity failure;
  -- synthesis translate_on

  -- ======================================================================================================
  -- Assignments
  -- ======================================================================================================

  o_error               <= error_reg;
  o_command_read_enable <= command_read_enable;

  o_M_AXI_ARID          <= (others => '0');
  o_M_AXI_ARADDR        <= address_reg;
  o_M_AXI_ARLEN         <= std_logic_vector(resize(burst_words - 1, o_M_AXI_ARLEN'length)) when burst_words /= 0 else
                           (others => '0');
  o_M_AXI_ARSIZE        <= std_logic_vector(to_unsigned(f_log2(C_BYTES_PER_WORD), o_M_AXI_ARSIZE'length));
  o_M_AXI_ARBURST       <= "01";
  o_M_AXI_ARLOCK        <= '0';
  o_M_AXI_ARCACHE       <= "0010";
  o_M_AXI_ARPROT        <= "000";
  o_M_AXI_ARQOS         <= (others => '0');
  o_M_AXI_ARUSER        <= (others => '0');
  o_M_AXI_ARVALID       <= arvalid_reg;
  o_M_AXI_RREADY        <= rready_int;

  -- ======================================================================================================
  -- Read data mapping
  -- ======================================================================================================

  gen64 : if C_M_AXI_DATA_WIDTH = 64 generate
    o_read_data(31 downto 0)  <= i_M_AXI_RDATA(63 downto 32);
    o_read_data(63 downto 32) <= i_M_AXI_RDATA(31 downto 0);
  end generate;

  gen32 : if C_M_AXI_DATA_WIDTH = 32 generate
    o_read_data <= i_M_AXI_RDATA;
  end generate;

  -- ======================================================================================================
  -- Read data handshake
  -- ======================================================================================================

  process(read_state, active_port, i_read_stop)
  begin
    rready_int <= '0';

    if read_state = receive_data then
      if i_read_stop(active_port) = '0' then
        rready_int <= '1';
      end if;
    end if;
  end process;

  process(active_port, i_M_AXI_RVALID, i_M_AXI_RLAST, rready_int, first_word_pending, remaining_words, burst_words)
  begin
    o_read_valid <= (others => '0');
    o_read_first <= '0';
    o_read_last  <= '0';

    if i_M_AXI_RVALID = '1' and rready_int = '1' then
      o_read_valid(active_port) <= '1';

      if first_word_pending = '1' then
        o_read_first <= '1';
      end if;

      if i_M_AXI_RLAST = '1' and remaining_words <= resize(burst_words, remaining_words'length) then
        o_read_last <= '1';
      end if;
    end if;
  end process;

  -- ======================================================================================================
  -- AXI read control
  -- ======================================================================================================

  process(i_clk, i_rst_n)
    variable v_length_words : unsigned(16 downto 0);
    variable v_burst_words  : natural;
    variable v_next_address : unsigned(C_M_AXI_ADDR_WIDTH - 1 downto 0);
  begin
    if i_rst_n = '0' then
      command_read_enable <= (others => '0');
        read_state          <= idle;
        active_port         <= 0;
        address_reg         <= (others => '0');
        remaining_words     <= (others => '0');
        burst_words         <= (others => '0');
        arvalid_reg         <= '0';
        first_word_pending  <= '0';
        error_reg           <= '0';

    elsif rising_edge(i_clk) then
      command_read_enable <= (others => '0');
        case read_state is

          when idle =>
            arvalid_reg <= '0';

            for i in 0 to g_num_read_ports - 1 loop
              if i_command_queue_empty(i) = '0' and i_read_stop(i) = '0' then
                active_port <= i;
                address_reg <= std_logic_vector(resize(unsigned(i_command(i)(31 downto 0)), C_M_AXI_ADDR_WIDTH));

                v_length_words := resize(unsigned(i_command(i)(47 downto 32)), 17) + 1;
                remaining_words <= v_length_words;

                command_read_enable(i) <= '1';
                first_word_pending     <= '1';
                read_state             <= prepare_burst;
                exit;
              end if;
            end loop;

          when prepare_burst =>
            if remaining_words > to_unsigned(C_MAX_BURST_WORDS, remaining_words'length) then
              v_burst_words := C_MAX_BURST_WORDS;
            else
              v_burst_words := to_integer(remaining_words);
            end if;

            burst_words <= to_unsigned(v_burst_words, burst_words'length);
            arvalid_reg <= '1';
            read_state  <= send_address;

          when send_address =>
            if arvalid_reg = '1' and i_M_AXI_ARREADY = '1' then
              arvalid_reg <= '0';
              read_state  <= receive_data;
            end if;

          when receive_data =>
            if i_M_AXI_RVALID = '1' and rready_int = '1' then
              if i_M_AXI_RRESP(1) = '1' then
                error_reg <= '1';
              end if;

              if first_word_pending = '1' then
                first_word_pending <= '0';
              end if;

              if i_M_AXI_RLAST = '1' then
                if remaining_words <= resize(burst_words, remaining_words'length) then
                  remaining_words <= (others => '0');
                  read_state      <= idle;
                else
                  remaining_words <= remaining_words - resize(burst_words, remaining_words'length);

                  v_next_address := unsigned(address_reg) +
                                    to_unsigned(to_integer(burst_words) * C_BYTES_PER_WORD,
                                                C_M_AXI_ADDR_WIDTH);
                  address_reg <= std_logic_vector(v_next_address);
                  read_state  <= prepare_burst;
                end if;
              end if;
            end if;

          when others =>
            read_state <= idle;

        end case;
    end if;
  end process;

end implementation;
