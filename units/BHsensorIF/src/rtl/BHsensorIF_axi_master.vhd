--#####################################################################
-- Company      : B-Horizon GmbH
-- Engineer     : JSchmid
-- File         : BHsensorIF_axi_master.vhd
-- Design Name  : FPGA
-- Module Name  : BHsensorIF_axi_master
-- Project Name : DI-OWAS
-- Create Date  : 2026-02-06
-- Description  : 4-Kanal AXI4-MM Burst Writer (32 beats x 32-bit = 128 Byte)
--                - Round-Robin Kanalwahl
--                - 64-Frame Ringbuffer-Index je Kanal
--                - Minimaler Descriptor-FSM (valid wird gehalten bis ready)
--                - Stream startet erst nach Descriptor-Annahme
--                - Frame + Adresse werden beim Kanal-Pick gesnapshottet
--#####################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.BHsensorIF_pkg.all;

entity BHsensorIF_axi_master is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;

	i_store_frames	: in std_logic_vector(2*8-1 downto 0);	--
	
    --------------------------------------------------------------------------
    -- Eingänge: 4 Kanäle, jeweils 128-Byte Frame + 1-Takt-Strobe
    --------------------------------------------------------------------------
    i_new_frame  : in std_logic_vector(3 downto 0);
    i_frame_data : in t_frame128B_4ch;

    --------------------------------------------------------------------------
    -- Basisadressen jedes Kanals (128-Byte aligned!)
    --------------------------------------------------------------------------
    i_base_addr_ch0 : in std_logic_vector(31 downto 0);
    i_base_addr_ch1 : in std_logic_vector(31 downto 0);
    i_base_addr_ch2 : in std_logic_vector(31 downto 0);
    i_base_addr_ch3 : in std_logic_vector(31 downto 0);

    --------------------------------------------------------------------------
    -- Write-Done je Kanal (1-Takt-Puls)
    --------------------------------------------------------------------------
    o_write_done : out std_logic_vector(3 downto 0);

    --------------------------------------------------------------------------
    -- AXI4-MM Master (32-bit)
    --------------------------------------------------------------------------
    m_axi_awaddr  : out std_logic_vector(31 downto 0);
    m_axi_awlen   : out std_logic_vector(7 downto 0);
    m_axi_awsize  : out std_logic_vector(2 downto 0);
    m_axi_awburst : out std_logic_vector(1 downto 0);
    m_axi_awvalid : out std_logic;
    m_axi_awready : in  std_logic;

    m_axi_wdata   : out std_logic_vector(31 downto 0);
    m_axi_wstrb   : out std_logic_vector(3 downto 0);
    m_axi_wlast   : out std_logic;
    m_axi_wvalid  : out std_logic;
    m_axi_wready  : in  std_logic;

    m_axi_bid     : in  std_logic;	-- new??
    m_axi_bresp   : in  std_logic_vector(1 downto 0);
    m_axi_bvalid  : in  std_logic;
    m_axi_bready  : out std_logic
  );
end entity;

architecture rtl of BHsensorIF_axi_master is

  -----------------------------------------------------------------------------
  -- Konstanten
  -----------------------------------------------------------------------------
  constant DATA_WIDTH      : integer := 32;
  constant ADDR_WIDTH      : integer := 32;
  constant STRB_WIDTH      : integer := DATA_WIDTH/8;
  constant FRAME_BYTES     : integer := 128;
  constant BEATS_PER_FRAME : integer := FRAME_BYTES / (DATA_WIDTH/8); -- 32 beats

  -----------------------------------------------------------------------------
  -- Zustandsmaschine (Haupt-FSM)
  -----------------------------------------------------------------------------
  type t_state is (S_IDLE, S_DESC, S_STREAM, S_WAIT_DONE);
  signal state : t_state := S_IDLE;

  -----------------------------------------------------------------------------
  -- Round-Robin & Kanalwahl
  -----------------------------------------------------------------------------
  signal rr_ptr     : unsigned(1 downto 0) := (others => '0');
  signal active_ch  : unsigned(1 downto 0) := (others => '0');

  -----------------------------------------------------------------------------
  -- Ringbuffer Index je Kanal
  -----------------------------------------------------------------------------
  type t_u6_vec is array (0 to 3) of unsigned(5 downto 0);
  signal wr_index : t_u6_vec := (others => (others => '0'));
  signal wr_index_snap : unsigned(5 downto 0) := (others => '0');

  -----------------------------------------------------------------------------
  -- Adresse
  -----------------------------------------------------------------------------
  signal base_addr     : unsigned(ADDR_WIDTH-1 downto 0);
  signal target_addr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal target_addr_r : std_logic_vector(ADDR_WIDTH-1 downto 0);

  -----------------------------------------------------------------------------
  -- Minimaler Descriptor-FSM
  -----------------------------------------------------------------------------
  signal desc_valid  : std_logic := '0';
  signal desc_ready  : std_logic;
  signal dma_complete: std_logic;

  signal desc_busy : std_logic := '0';
  signal desc_done : std_logic := '0';

  -----------------------------------------------------------------------------
  -- Frame Buffer
  -----------------------------------------------------------------------------
  signal frame_buf : std_logic_vector(FRAME_BYTES*8-1 downto 0);

  type t_word_array is array (0 to BEATS_PER_FRAME-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
  signal words : t_word_array;

  -----------------------------------------------------------------------------
  -- AXIS Stream Sequencer
  -----------------------------------------------------------------------------
  signal word_index : unsigned(5 downto 0) := (others => '0');
  signal tvalid     : std_logic := '0';
  signal tready     : std_logic;
  signal tlast      : std_logic := '0';
  signal tdata      : std_logic_vector(DATA_WIDTH-1 downto 0);

  -----------------------------------------------------------------------------
  -- Write-Done
  -----------------------------------------------------------------------------
  signal write_done_int : std_logic_vector(3 downto 0) := (others => '0');
  
	signal s_wdata_swapped : std_logic_vector(31 downto 0);
	signal m_axi_wdata_tmp : std_logic_vector(31 downto 0);

	signal s_store_frames : integer range 0 to 255;

begin

	s_wdata_swapped <= m_axi_wdata_tmp(7 downto 0) &
						m_axi_wdata_tmp(15 downto 8) &
						m_axi_wdata_tmp(23 downto 16) &
						m_axi_wdata_tmp(31 downto 24);

	m_axi_wdata <= s_wdata_swapped;


  o_write_done <= write_done_int;

  -----------------------------------------------------------------------------
  -- Basisadresse wählen
  -----------------------------------------------------------------------------
  process(active_ch, i_base_addr_ch0, i_base_addr_ch1, i_base_addr_ch2, i_base_addr_ch3)
  begin
    case active_ch is
      when "00" => base_addr <= unsigned(i_base_addr_ch0);
      when "01" => base_addr <= unsigned(i_base_addr_ch1);
      when "10" => base_addr <= unsigned(i_base_addr_ch2);
      when others => base_addr <= unsigned(i_base_addr_ch3);
    end case;
  end process;

  -----------------------------------------------------------------------------
  -- Zieladresse
  -----------------------------------------------------------------------------
  target_addr <= std_logic_vector(
    base_addr + shift_left(resize(wr_index_snap, ADDR_WIDTH), 7)
  );

  -----------------------------------------------------------------------------
  -- Adresse nur bei Descriptor-Annahme latchen
  -----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        --target_addr_r <= (others => '0');
        target_addr_r <= i_base_addr_ch0;
      elsif (state = S_DESC and desc_done = '1') then
        target_addr_r <= target_addr;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Frame puffern + Words generieren
  -----------------------------------------------------------------------------
  gen_words: for i in 0 to BEATS_PER_FRAME-1 generate
    words(i) <= frame_buf((i*DATA_WIDTH)+DATA_WIDTH-1 downto i*DATA_WIDTH);
  end generate;

  tdata <= words(to_integer(word_index));

  -----------------------------------------------------------------------------
  -- Minimaler Descriptor-FSM
  -----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      desc_done <= '0';

      if rst = '1' then
        desc_valid <= '0';
        desc_busy  <= '0';

      else

        -- Start descriptor when we ENTER S_DESC
        if (state = S_DESC and desc_busy = '0') then
          desc_valid <= '1';
          desc_busy  <= '1';
        end if;

        -- Handshake
        if desc_valid = '1' and desc_ready = '1' then
          desc_valid <= '0';
          desc_done  <= '1';
        end if;

        if desc_done = '1' then
          desc_busy <= '0';
        end if;

      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- TLAST für letztes Beat
  -----------------------------------------------------------------------------
  process(tvalid, word_index)
  begin
    if (tvalid = '1' and word_index = to_unsigned(BEATS_PER_FRAME-1, word_index'length)) then
      tlast <= '1';
    else
      tlast <= '0';
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Haupt-FSM: Round-Robin, Descriptor-Start, Streaming
  -----------------------------------------------------------------------------
  process(clk)
    variable cand_i : integer;
    variable picked : boolean;
  begin
    if rising_edge(clk) then

      write_done_int <= (others => '0');

      if rst = '1' then
        state         <= S_IDLE;
        rr_ptr        <= (others => '0');
        active_ch     <= (others => '0');
        wr_index_snap <= (others => '0');
        tvalid        <= '0';
        --tlast         <= '0';
        word_index    <= (others => '0');

      else

        case state is

          -------------------------------------------------------------------
          -- IDLE: nächsten Kanal finden
          -------------------------------------------------------------------
          when S_IDLE =>
            tvalid     <= '0';
            --tlast      <= '0';
            word_index <= (others => '0');

            picked := false;

            for k in 0 to 3 loop
              cand_i := (to_integer(rr_ptr) + 1 + k) mod 4;
              if i_new_frame(cand_i) = '1' then

                active_ch     <= to_unsigned(cand_i, 2);
                rr_ptr        <= to_unsigned(cand_i, 2);
                wr_index_snap <= wr_index(cand_i);

                frame_buf     <= i_frame_data(cand_i);

                state <= S_DESC;
                picked := true;
                exit;
              end if;
            end loop;

          -------------------------------------------------------------------
          -- S_DESC: warten, bis Descriptor angenommen wurde (desc_done)
          -------------------------------------------------------------------
          when S_DESC =>
            if desc_done = '1' then
              tvalid     <= '1';
              word_index <= (others => '0');
              state      <= S_STREAM;
            end if;

          -------------------------------------------------------------------
          -- AXIS Streaming
          -------------------------------------------------------------------
          when S_STREAM =>
            if tvalid = '1' and tready = '1' then
              if word_index = to_unsigned(BEATS_PER_FRAME-1, word_index'length) then
                tvalid <= '0';
                state  <= S_WAIT_DONE;
              else
                word_index <= word_index + 1;
              end if;
            end if;

          -------------------------------------------------------------------
          -- Auf DMA Done warten
          -------------------------------------------------------------------
          when S_WAIT_DONE =>
            if dma_complete = '1' then
              write_done_int(to_integer(active_ch)) <= '1';
              --wr_index(to_integer(active_ch)) <= wr_index(to_integer(active_ch)) + 1;
				wr_index(to_integer(active_ch)) 
					<= (wr_index(to_integer(active_ch)) + 1) mod s_store_frames;-- channel size (number of frames)
					--<= (wr_index(to_integer(active_ch)) + 1) mod 8;		-- channel size (number of frames)			
              state <= S_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;


	s_store_frames <= to_integer(unsigned(i_store_frames));

  -----------------------------------------------------------------------------
  -- DMA Instanz
  -----------------------------------------------------------------------------
  dma_i : entity work.BHsensorIF_axi_dma_wr_wrapper
    generic map (
      AXI_DATA_WIDTH    => DATA_WIDTH,
      AXI_ADDR_WIDTH    => ADDR_WIDTH,
      AXI_ID_WIDTH      => 1,			--8?
      AXI_MAX_BURST_LEN => BEATS_PER_FRAME,
      AXIS_DATA_WIDTH   => DATA_WIDTH,
      AXIS_KEEP_WIDTH   => STRB_WIDTH,
      AXIS_LAST_ENABLE  => 1,
      AXIS_ID_ENABLE    => 0,
      AXIS_DEST_ENABLE  => 0,
      AXIS_USER_ENABLE  => 1,
      AXIS_USER_WIDTH   => 1,
      LEN_WIDTH         => 20,
      TAG_WIDTH         => 8,
      ENABLE_SG         => 0,
      ENABLE_UNALIGNED  => 0
    )
    port map (
      clk => clk,
      rst => rst,

      --s_axis_write_desc_addr  => target_addr_r,
      s_axis_write_desc_addr  => target_addr,	-- fixed adress mismatch (_r to late)
	  
      s_axis_write_desc_len   => std_logic_vector(to_unsigned(FRAME_BYTES, 20)),
      s_axis_write_desc_tag   => (others => '0'),
      s_axis_write_desc_valid => desc_valid,
      s_axis_write_desc_ready => desc_ready,

      m_axis_write_desc_status_len   => open,
      m_axis_write_desc_status_tag   => open,
      m_axis_write_desc_status_id    => open,
      m_axis_write_desc_status_dest  => open,
      m_axis_write_desc_status_user  => open,
      m_axis_write_desc_status_error => open,
      m_axis_write_desc_status_valid => dma_complete,

      s_axis_write_data_tdata  => tdata,
      s_axis_write_data_tkeep  => (others => '1'),
      s_axis_write_data_tvalid => tvalid,
      s_axis_write_data_tready => tready,
      s_axis_write_data_tlast  => tlast,
      s_axis_write_data_tid    => (others => '0'),
      s_axis_write_data_tdest  => (others => '0'),
      s_axis_write_data_tuser  => "0",

      m_axi_awid    => open,
      m_axi_awaddr  => m_axi_awaddr,
      m_axi_awlen   => m_axi_awlen,
      m_axi_awsize  => m_axi_awsize,
      m_axi_awburst => m_axi_awburst,
      m_axi_awlock  => open,
      m_axi_awcache => open,
      m_axi_awprot  => open,
      m_axi_awvalid => m_axi_awvalid,
      m_axi_awready => m_axi_awready,

      m_axi_wdata   => m_axi_wdata_tmp,		-- swapping MSB/LSB
      m_axi_wstrb   => m_axi_wstrb,
      m_axi_wlast   => m_axi_wlast,
      m_axi_wvalid  => m_axi_wvalid,
      m_axi_wready  => m_axi_wready,

      --m_axi_bid     => (others => '0'),
      m_axi_bid     => m_axi_bid,		-- new??
      m_axi_bresp   => m_axi_bresp,
      m_axi_bvalid  => m_axi_bvalid,
      m_axi_bready  => m_axi_bready,

      enable => '1',
      abort  => '0'
    );

end architecture;