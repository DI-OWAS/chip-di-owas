module cryptoCore #
(
    // Parameters for the axi_dma module
    // Width of AXI data bus in bits
    parameter AXI_DATA_WIDTH = 32,
    // Width of AXI address bus in bits
    parameter AXI_ADDR_WIDTH = 16,
    // Width of AXI wstrb (width of data bus in words)
    parameter AXI_STRB_WIDTH = (AXI_DATA_WIDTH/8),
    // Width of AXI ID signal
    parameter AXI_ID_WIDTH = 8,

    parameter LEN_WIDTH = 20,


    // hardcoded key for bitstream decryption
    parameter [127:0] KEK = 128'hf00ff209847506cc080c0a0b00110eaf,
    // address where encrypted bitstream sits
    parameter [31:0] BOOT_SRC_ADDR = 32'h0000_0000,
    // address where decrypted bitstream needs to be written to
    parameter [31:0] BOOT_DST_ADDR = 32'h0000_1000, 
    // 1IV block + body blocks + 2 key blocks
    parameter integer BOOT_N_BLOCKS = 8,

    // 1 = run the bitstream boot after reset, 0 = no boot (no DATA-IF accesses after reset)
    parameter BOOT_ENABLE = 0,
    // fixed keys loaded once after reset when BOOT_ENABLE = 0
    // public test keys (NIST SP 800-38A / FIPS-197 C.1), NOT secret
    parameter [127:0] STATIC_KEY1 = 128'h2b7e151628aed2a6abf7158809cf4f3c,
    parameter [127:0] STATIC_KEY2 = 128'h000102030405060708090a0b0c0d0e0f
)
(
    input  wire             clk,
    input  wire             rst,

    //ports for AXI4-Lite slave 
    input  wire [7:0]       s_axil_awaddr,
    input  wire [2:0]       s_axil_awprot,
    input  wire             s_axil_awvalid,
    output wire             s_axil_awready,
    input  wire [31:0]      s_axil_wdata,
    input  wire [3:0]       s_axil_wstrb,
    input  wire             s_axil_wvalid,
    output wire             s_axil_wready,
    output wire [1:0]       s_axil_bresp,
    output wire             s_axil_bvalid,
    input  wire             s_axil_bready,
    input  wire [7:0]       s_axil_araddr,
    input  wire [2:0]       s_axil_arprot,
    input  wire             s_axil_arvalid,
    output wire             s_axil_arready,
    output wire [31:0]      s_axil_rdata,
    output wire [1:0]       s_axil_rresp,
    output wire             s_axil_rvalid,
    input  wire             s_axil_rready,

    // --- DATA-IF: AXI4 master (to crossbar) ---
    // Write address channel
    output wire [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                m_axi_awlen,
    output wire [2:0]                m_axi_awsize,
    output wire [1:0]                m_axi_awburst,
    output wire                      m_axi_awlock,
    output wire [3:0]                m_axi_awcache,
    output wire [2:0]                m_axi_awprot,
    output wire                      m_axi_awvalid,
    input  wire                      m_axi_awready,
    // Write data channel
    output wire [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [AXI_STRB_WIDTH-1:0] m_axi_wstrb,
    output wire                      m_axi_wlast,
    output wire                      m_axi_wvalid,
    input  wire                      m_axi_wready,
    // Write response channel
    input  wire [AXI_ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]                m_axi_bresp,
    input  wire                      m_axi_bvalid,
    output wire                      m_axi_bready,
    // Read address channel
    output wire [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]                m_axi_arlen,
    output wire [2:0]                m_axi_arsize,
    output wire [1:0]                m_axi_arburst,
    output wire                      m_axi_arlock,
    output wire [3:0]                m_axi_arcache,
    output wire [2:0]                m_axi_arprot,
    output wire                      m_axi_arvalid,
    input  wire                      m_axi_arready,
    // Read data channel
    input  wire [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]                m_axi_rresp,
    input  wire                      m_axi_rlast,
    input  wire                      m_axi_rvalid,
    output wire                      m_axi_rready
);
    
    // boot wires (declared first: boot_active is used in eff_mode below)
    wire boot_active;
    wire boot_done;
    wire boot_go;
    wire [31:0] boot_src, boot_dst, boot_blocks;
    wire        boot_bypass;
    wire        boot_iv_load;
    wire [95:0] boot_iv_data;

    // --- AXI register outputs ---
    wire [4:0]   CTRL;
    wire [1:0]   mode = CTRL[3:2];
    wire         decrypt = CTRL[4];
    wire [127:0] ctr_nonce;
    wire         ctr_overflow;
    wire [1:0]   eff_mode = boot_active ? 2'd0 : mode;

    // --- CTRL decode ---
    wire         ctrl_key_sel;
    wire         ctrl_bypass;

    // --- STATUS assembly ---
    wire [7:0]   STATUS;

    // --- FSM → AES ---
    wire [127:0] io_key;
    wire [127:0] io_dataIn;
    wire         fsm_enable;

    // --- FSM → keyStorage ---
    wire         key_sel;
    wire         key1_wr_en;
    wire [127:0] key1_wr_data;
    wire         key2_wr_en;
    wire [127:0] key2_wr_data;

    // --- FSM → AXI register ---
    wire         status_busy;
    wire         status_done;
    wire [127:0] cipher_out;
    wire         ctr_count_inc;

    // --- AES outputs ---
    wire [127:0] io_dataOut;
    wire         fsm_ready;
    wire         fsm_valid;

    // --- keyStorage outputs ---
    wire [127:0] key_out;
    wire         key1_valid;
    wire         key2_valid;


    // DMA control wires
    wire [31:0]               SRC_ADDR, DST_ADDR, DMA_BLOCKS, ctr_count_val;
    wire                      GO, dma_go_clr, dma_busy, dma_done, dma_error;
    wire [AXI_ADDR_WIDTH-1:0] rd_desc_addr, wr_desc_addr;
    wire [LEN_WIDTH-1:0]      rd_desc_len,  wr_desc_len;
    wire                      rd_desc_valid, rd_desc_ready;
    wire                      wr_desc_valid, wr_desc_ready;

    // AXIS read-data stream  (axi_dma  → loopback/AES)
    wire [AXI_DATA_WIDTH-1:0]   m_axis_read_data_tdata;
    wire [AXI_DATA_WIDTH/8-1:0] m_axis_read_data_tkeep;
    wire                        m_axis_read_data_tvalid;
    wire                        m_axis_read_data_tready;
    wire                        m_axis_read_data_tlast;

    // AXIS write-data stream (loopback/AES → axi_dma)
    wire [AXI_DATA_WIDTH-1:0]   s_axis_write_data_tdata;
    wire [AXI_DATA_WIDTH/8-1:0] s_axis_write_data_tkeep;
    wire                        s_axis_write_data_tvalid;
    wire                        s_axis_write_data_tready;
    wire                        s_axis_write_data_tlast;
    wire                        s_axis_write_data_tuser;

    // descriptor completion (axi_dma → cryptoDmaCtrl)
    wire                        wr_status_valid;

    // wires for aesStreamAdapter
    wire [127:0]                adapter_cipher_in;
    wire                        adapter_start;
    wire [127:0]                fsm_cipher_in;
    wire                        fsm_ctrl_start;


    // descriptor muxes (switches between boot and normal addresses etc.)
    wire        dc_go     = boot_active ? boot_go     : GO;
    wire [31:0] dc_src    = boot_active ? boot_src    : SRC_ADDR;
    wire [31:0] dc_dst    = boot_active ? boot_dst    : DST_ADDR;
    wire [31:0] dc_blocks = boot_active ? boot_blocks : DMA_BLOCKS;
    wire        dc_bypass = boot_active ? boot_bypass : ctrl_bypass;

    wire        read_only, boot_discard;
    wire        boot_key1_wr_en, boot_key2_wr_en;
    wire [127:0] boot_key_wr_data;

    // one-cycle pulse after reset: loads STATIC_KEY1/2 when the boot path is disabled
    reg static_key_load;
    always @(posedge clk or posedge rst)
        if (rst) static_key_load <= (BOOT_ENABLE == 0); else static_key_load <= 1'b0;

    wire         ks_key1_wr_en   = boot_active ? boot_key1_wr_en  : (key1_wr_en | static_key_load);
    wire [127:0] ks_key1_wr_data = boot_active ? boot_key_wr_data : (static_key_load ? STATIC_KEY1 : key1_wr_data);
    wire         ks_key2_wr_en   = boot_active ? boot_key2_wr_en  : (key2_wr_en | static_key_load);
    wire [127:0] ks_key2_wr_data = boot_active ? boot_key_wr_data : (static_key_load ? STATIC_KEY2 : key2_wr_data);

    wire [127:0] ctr_io_key, ctr_io_dataIn;   wire ctr_fsm_enable;
    wire [127:0] cmac_io_key, cmac_io_dataIn;  wire cmac_fsm_enable;
    wire [127:0] ccm_io_key,  ccm_io_dataIn;   wire ccm_fsm_enable;


    // --- Phase B: config from reg file → engines ---
    wire [103:0] ccm_nonce;
    wire [15:0]  payload_len;
    wire [127:0] tag_in;

    // --- Phase B: engine results → latch → reg file ---
    wire [127:0] cmac_tag,  ccm_tag_out;
    wire         cm_tag_valid, cc_tag_valid, cc_auth_ok;
    reg  [127:0] tag_out_reg;
    reg          auth_ok_reg, engine_done_reg;


    wire [127:0] cc_out_data;
    wire         cc_out_valid;
    wire [4:0]   cc_out_nbytes;
    wire         cc_out_ready;



    assign s_axis_write_data_tkeep = {AXI_STRB_WIDTH{1'b1}};    // full 128 bit block
    assign s_axis_write_data_tuser = 1'b0;


    // cipher input via DMA path
    assign fsm_cipher_in  = adapter_cipher_in;
    assign fsm_ctrl_start = adapter_start;


    // --- Continuous assignments ---

    assign ctrl_key_sel     = CTRL[0];
    assign ctrl_bypass      = CTRL[1];
    assign STATUS = {auth_ok_reg, engine_done_reg,          // [7],[6]
                 ctr_overflow, key2_valid, key1_valid,  // [5],[4],[3]
                 boot_done, status_done, status_busy};  // [2],[1],[0]

    // select the active engine's result
    wire         eng_tvalid = (eff_mode==2'd2) ? cc_tag_valid :
                            (eff_mode==2'd1) ? cm_tag_valid : 1'b0;
    wire [127:0] eng_tag    = (mode==2'd2) ? ccm_tag_out : cmac_tag;


    reg dma_busy_d;
    always @(posedge clk or posedge rst)
        if (rst) dma_busy_d <= 1'b0; else dma_busy_d <= dma_busy;

    wire eng_start = dma_busy & ~dma_busy_d & (eff_mode != 2'd0);  // rising edge of dma_busy in engine modes
    wire cmac_start = eng_start & (eff_mode == 2'd1);
    wire cc_start   = eng_start & (eff_mode == 2'd2);

    wire read_only_eff = read_only | (eff_mode == 2'd1);   // CMAC has no ciphertext output

    wire [127:0] eng_block_in;
    wire         eng_block_valid, eng_block_last;
    wire [4:0]   eng_block_nbytes;
    wire         cm_block_ready, cc_block_ready;
    wire block_ready_sel = (eff_mode == 2'd2) ? cc_block_ready : cm_block_ready;


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tag_out_reg     <= 128'd0;
            auth_ok_reg     <= 1'b0;
            engine_done_reg <= 1'b0;
        end else begin
            if (eng_start) engine_done_reg <= 1'b0;   // new message clears done
            if (eng_tvalid) begin
                tag_out_reg     <= eng_tag;
                auth_ok_reg     <= cc_auth_ok;   // meaningful for CCM decrypt
                engine_done_reg <= 1'b1;
            end
        end
    end


    //Instantiate all modules of the crypto core
    aesArbiter u_aesArbiter (
        .mode(mode), .boot_active(boot_active),
        .ctr_key (ctr_io_key),  .ctr_din (ctr_io_dataIn),  .ctr_en (ctr_fsm_enable),
        .cmac_key(cmac_io_key), .cmac_din(cmac_io_dataIn), .cmac_en(cmac_fsm_enable),
        .ccm_key (ccm_io_key),  .ccm_din (ccm_io_dataIn),  .ccm_en (ccm_fsm_enable),
        .aes_key(io_key), .aes_din(io_dataIn), .aes_en(fsm_enable)
    );

    AES128_Sec_0_Area_0 u_AES128_Sec_0_Area_0 (
        .control_clk    (clk),
        .control_reset  (rst),
        .io_key         (io_key),
        .io_dataIn      (io_dataIn),
        .io_dataOut     (io_dataOut),
        .fsm_enable     (fsm_enable),
        .fsm_ready      (fsm_ready),
        .fsm_valid      (fsm_valid)
    );


    keyStorage u_keyStorage (
        .clk            (clk),
        .rst            (rst),
        .key1_wr_en     (ks_key1_wr_en),
        .key1_wr_data   (ks_key1_wr_data),
        .key2_wr_en     (ks_key2_wr_en),
        .key2_wr_data   (ks_key2_wr_data),
        .key_sel        (key_sel),
        .key_out        (key_out),
        .key1_valid     (key1_valid),
        .key2_valid     (key2_valid)
    );


    cryptoCoreFSM u_cryptoCoreFSM (
        .clk            (clk),
        .rst            (rst),
        .ctrl_start     (fsm_ctrl_start),
        .ctrl_key_sel   (ctrl_key_sel),
        .boot_active    (boot_active),
        .boot_kek       (KEK),
        .cipher_in      (fsm_cipher_in),
        .ctr_nonce      (ctr_nonce),
        .key_out        (key_out),
        .key1_valid     (key1_valid),
        .key2_valid     (key2_valid),
        .fsm_ready      (fsm_ready),
        .fsm_valid      (fsm_valid),
        .io_dataOut     (io_dataOut),
        .status_busy    (status_busy),
        .status_done    (status_done),
        .cipher_out     (cipher_out),
        .io_key         (ctr_io_key),
        .io_dataIn      (ctr_io_dataIn),
        .fsm_enable     (ctr_fsm_enable),
        .key_sel        (key_sel),
        .key1_wr_en     (key1_wr_en),
        .key1_wr_data   (key1_wr_data),
        .key2_wr_en     (key2_wr_en),
        .key2_wr_data   (key2_wr_data),
        .ctr_count_inc  (ctr_count_inc),
        .ctr_overflow   (ctr_overflow),
        .boot_done      (boot_done)
    );


    cmacEngine u_cmacEngine (
        .clk(clk), .rst(rst),
        .start(cmac_start), .key(key_out),
        .block_in(eng_block_in), .block_valid(eng_block_valid),
        .block_last(eng_block_last), .block_nbytes(eng_block_nbytes),
        .block_ready(cm_block_ready), .tag(cmac_tag), .tag_valid(cm_tag_valid), .busy(),
        .io_key(cmac_io_key), .io_dataIn(cmac_io_dataIn), .fsm_enable(cmac_fsm_enable),
        .io_dataOut(io_dataOut), .fsm_ready(fsm_ready), .fsm_valid(fsm_valid)
    );

    ccmEngine #(.Q(2)) u_ccmEngine (
        .clk(clk), .rst(rst),
        .start(cc_start), .decrypt(decrypt), .key(key_out),
        .nonce(ccm_nonce), .payload_len(payload_len), .tag_in(tag_in),
        .block_in(eng_block_in), .block_valid(eng_block_valid),
        .block_last(eng_block_last), .block_nbytes(eng_block_nbytes),
        .block_ready(cc_block_ready),
        .out_data(cc_out_data), .out_valid(cc_out_valid),
        .out_nbytes(cc_out_nbytes), .out_ready(cc_out_ready),
        .tag_out(ccm_tag_out), .tag_valid(cc_tag_valid), .auth_ok(cc_auth_ok), .busy(),
        .io_key(ccm_io_key), .io_dataIn(ccm_io_dataIn), .fsm_enable(ccm_fsm_enable),
        .io_dataOut(io_dataOut), .fsm_ready(fsm_ready), .fsm_valid(fsm_valid)

    );


    axi4LiteRegister u_axi4LiteRegister (
        .clk            (clk),
        .rst            (rst),
        .CTRL           (CTRL),
        .STATUS         (STATUS),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awprot  (s_axil_awprot),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arprot  (s_axil_arprot),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        .ctr_nonce      (ctr_nonce),
        .ctr_count_inc  (ctr_count_inc),
        .ctr_overflow   (ctr_overflow),
        .ctr_count_val  (ctr_count_val),
        .SRC_ADDR       (SRC_ADDR),
        .DST_ADDR       (DST_ADDR),
        .DMA_BLOCKS     (DMA_BLOCKS),
        .GO             (GO),
        .dma_go_clr     (dma_go_clr),
        .dma_busy       (dma_busy),
        .dma_done       (dma_done),
        .dma_error      (dma_error),
        .boot_iv_load   (boot_iv_load),
        .boot_iv_data   (boot_iv_data),
        .boot_active    (boot_active),
        .ccm_nonce   (ccm_nonce),
        .payload_len (payload_len),
        .tag_in      (tag_in),
        .tag_out     (tag_out_reg)
    );



    axi_dma #(
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH),
    .AXIS_DATA_WIDTH(AXI_DATA_WIDTH),
    .LEN_WIDTH      (LEN_WIDTH)
) u_axi_dma (
    .clk(clk),
    .rst(rst),

    // --- read descriptor in (from cryptoDmaCtrl) ---
    .s_axis_read_desc_addr  (rd_desc_addr),
    .s_axis_read_desc_len   (rd_desc_len),
    .s_axis_read_desc_tag   (8'd0),
    .s_axis_read_desc_id    (8'd0),
    .s_axis_read_desc_dest  (8'd0),
    .s_axis_read_desc_user  (1'b0),
    .s_axis_read_desc_valid (rd_desc_valid),
    .s_axis_read_desc_ready (rd_desc_ready),

    // --- read descriptor status out (unused) ---
    .m_axis_read_desc_status_tag   (),
    .m_axis_read_desc_status_error (),
    .m_axis_read_desc_status_valid (),

    // --- read data stream out ---
    .m_axis_read_data_tdata  (m_axis_read_data_tdata),
    .m_axis_read_data_tkeep  (m_axis_read_data_tkeep),
    .m_axis_read_data_tvalid (m_axis_read_data_tvalid),
    .m_axis_read_data_tready (m_axis_read_data_tready),
    .m_axis_read_data_tlast  (m_axis_read_data_tlast),
    .m_axis_read_data_tid    (),
    .m_axis_read_data_tdest  (),
    .m_axis_read_data_tuser  (),

    // --- write descriptor in (from cryptoDmaCtrl) ---
    .s_axis_write_desc_addr  (wr_desc_addr),
    .s_axis_write_desc_len   (wr_desc_len),
    .s_axis_write_desc_tag   (8'd0),
    .s_axis_write_desc_valid (wr_desc_valid),
    .s_axis_write_desc_ready (wr_desc_ready),

    // --- write descriptor status out (only valid used) ---
    .m_axis_write_desc_status_len   (),
    .m_axis_write_desc_status_tag   (),
    .m_axis_write_desc_status_id    (),
    .m_axis_write_desc_status_dest  (),
    .m_axis_write_desc_status_user  (),
    .m_axis_write_desc_status_error (),
    .m_axis_write_desc_status_valid (wr_status_valid),

    // --- write data stream in ---
    .s_axis_write_data_tdata  (s_axis_write_data_tdata),
    .s_axis_write_data_tkeep  (s_axis_write_data_tkeep),
    .s_axis_write_data_tvalid (s_axis_write_data_tvalid),
    .s_axis_write_data_tready (s_axis_write_data_tready),
    .s_axis_write_data_tlast  (s_axis_write_data_tlast),
    .s_axis_write_data_tid    (8'd0),
    .s_axis_write_data_tdest  (8'd0),
    .s_axis_write_data_tuser  (s_axis_write_data_tuser),

    // --- AXI master (passthrough to top-level ports) ---
    .m_axi_awid    (m_axi_awid),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awlock  (m_axi_awlock),
    .m_axi_awcache (m_axi_awcache),
    .m_axi_awprot  (m_axi_awprot),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bid     (m_axi_bid),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready),
    .m_axi_arid    (m_axi_arid),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arlock  (m_axi_arlock),
    .m_axi_arcache (m_axi_arcache),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rid     (m_axi_rid),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),

    // --- config ---
    .read_enable  (1'b1),
    .write_enable (1'b1),
    .write_abort  (1'b0)
);


cryptoDmaCtrl #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .LEN_WIDTH      (LEN_WIDTH)
) u_cryptoDmaCtrl (
    .clk(clk),
    .rst(rst),
    .GO(dc_go),
    .SRC_ADDR(dc_src),
    .DST_ADDR(dc_dst),
    .DMA_BLOCKS(dc_blocks),
    .boot_active(boot_active),
    .rd_desc_ready(rd_desc_ready),
    .wr_desc_ready(wr_desc_ready),
    .wr_status_valid(wr_status_valid),
    .rd_desc_addr(rd_desc_addr),
    .rd_desc_len(rd_desc_len),
    .rd_desc_valid(rd_desc_valid),
    .wr_desc_addr(wr_desc_addr),
    .wr_desc_len(wr_desc_len),
    .wr_desc_valid(wr_desc_valid),
    .dma_go_clr(dma_go_clr),
    .dma_busy(dma_busy),
    .dma_done(dma_done),
    .dma_error(dma_error),
    .ctr_count(ctr_count_val),
    .ctr_overflow(ctr_overflow),
    .ctrl_key_sel(ctrl_key_sel),
    .ctrl_bypass(dc_bypass),
    .key1_valid(key1_valid),
    .key2_valid(key2_valid),
    .read_only(read_only_eff),
    .engine_mode (eff_mode != 2'd0),
    .payload_len (payload_len)
);


aesStreamAdapter u_aesStreamAdapter (
    .clk(clk),
    .rst(rst),
    .in_tdata(m_axis_read_data_tdata),
    .in_tvalid(m_axis_read_data_tvalid),
    .in_tready(m_axis_read_data_tready),
    .in_tlast(m_axis_read_data_tlast),
    .out_tdata(s_axis_write_data_tdata),
    .out_tvalid(s_axis_write_data_tvalid),
    .out_tready(s_axis_write_data_tready),
    .out_tlast(s_axis_write_data_tlast),
    .cipher_in(adapter_cipher_in),
    .start(adapter_start),
    .cipher_out(cipher_out),
    .status_busy(status_busy),
    .status_done(status_done),
    .bypass(dc_bypass),
    .discard_output(boot_discard),
    // --- C1: engine block feed ---
    .mode         (eff_mode),
    .block_in     (eng_block_in),
    .block_valid  (eng_block_valid),
    .block_last   (eng_block_last),
    .block_nbytes (eng_block_nbytes),
    .block_ready  (block_ready_sel),
    .eng_out_data   (cc_out_data),
    .eng_out_valid  (cc_out_valid),
    .eng_out_nbytes (cc_out_nbytes),
    .eng_out_ready  (cc_out_ready)

);



bootCtrl #(
    .BOOT_SRC_ADDR(BOOT_SRC_ADDR),
    .BOOT_DST_ADDR(BOOT_DST_ADDR),
    .BOOT_N_BLOCKS(BOOT_N_BLOCKS),
    .BOOT_ENABLE(BOOT_ENABLE)
) u_bootCtrl (
    .clk(clk), 
    .rst(rst),
    .boot_active(boot_active), 
    .boot_done(boot_done),
    .boot_go(boot_go), 
    .boot_src(boot_src), 
    .boot_dst(boot_dst), 
    .boot_blocks(boot_blocks),
    .dma_busy(dma_busy), 
    .dma_done(dma_done), 
    .dma_error(dma_error),
    .rd_tdata   (m_axis_read_data_tdata),
    .rd_tvalid  (m_axis_read_data_tvalid),
    .rd_tready  (m_axis_read_data_tready),
    .boot_bypass(boot_bypass),
    .boot_iv_load(boot_iv_load),
    .boot_iv_data(boot_iv_data),
    .status_done(status_done), 
    .cipher_out(cipher_out), 
    .read_only(read_only), 
    .boot_discard(boot_discard), 
    .boot_key1_wr_en(boot_key1_wr_en), 
    .boot_key2_wr_en(boot_key2_wr_en), 
    .boot_key_wr_data(boot_key_wr_data)
);


endmodule