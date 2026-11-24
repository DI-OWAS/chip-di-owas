`timescale 1ns / 1ps
`default_nettype none

module tb_cryptoCore_boot;

    // --- parameters (match the DUT) ---
    localparam AXI_DATA_WIDTH = 32;
    localparam AXI_ADDR_WIDTH = 16;
    localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;
    localparam AXI_ID_WIDTH   = 8;
    localparam LEN_WIDTH      = 20;


    // boot geometry / key — must match what the DUT is parameterized with
    localparam [127:0] KEK        = 128'hf00ff209847506cc080c0a0b00110eaf;
    localparam [95:0]  IV_NONCE   = 96'h112233445566778899aabbcc;
    localparam integer N_BLOCKS   = 8;
    localparam integer BODY       = N_BLOCKS - 3;      // 5 body blocks
    localparam [15:0]  BOOT_SRC   = 16'h0000;
    localparam [15:0]  BOOT_DST   = 16'h1000;
    localparam [127:0] KEY1_VAL   = 128'h0f0e0d0c0b0a09080706050403020100;
    localparam [127:0] KEY2_VAL   = 128'hf0e0d0c0b0a090807060504030201000;
    localparam [95:0]  RT_NONCE   = 96'hAABBCCDDEEFF00112233_4455;      // (24 hex digits)



    localparam ADDR_CTRL=8'h00, ADDR_STATUS=8'h04,
           ADDR_N1=8'h40, ADDR_N2=8'h44, ADDR_N3=8'h48,
           ADDR_SRC=8'h50, ADDR_DST=8'h54, ADDR_BLKS=8'h58,
           ADDR_GO=8'h5C, ADDR_DMASTAT=8'h60;


    // reference AES (keystream oracle) — its OWN reset
    reg          aes_rst;
    reg  [127:0] io_key, io_dataIn;
    reg          fsm_enable;
    wire [127:0] io_dataOut;
    wire         fsm_ready, fsm_valid;

    reg  [127:0] plaintext [0:BODY-1];
    reg  [127:0] ks;


    // --- clock / reset ---
    reg clk;
    reg rst;

    // --- AXI4-Lite slave (TB drives inputs = reg; DUT outputs = wire) ---
    reg  [7:0]  s_axil_awaddr;
    reg  [2:0]  s_axil_awprot;
    reg         s_axil_awvalid;
    wire        s_axil_awready;
    reg  [31:0] s_axil_wdata;
    reg  [3:0]  s_axil_wstrb;
    reg         s_axil_wvalid;
    wire        s_axil_wready;
    wire [1:0]  s_axil_bresp;
    wire        s_axil_bvalid;
    reg         s_axil_bready;
    reg  [7:0]  s_axil_araddr;
    reg  [2:0]  s_axil_arprot;
    reg         s_axil_arvalid;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;
    wire        s_axil_rvalid;
    reg         s_axil_rready;

    // --- AXI4 master bus: DUT (master) <-> axi_ram (slave) ---
    wire [AXI_ID_WIDTH-1:0]   m_axi_awid;
    wire [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [7:0]                m_axi_awlen;
    wire [2:0]                m_axi_awsize;
    wire [1:0]                m_axi_awburst;
    wire                      m_axi_awlock;
    wire [3:0]                m_axi_awcache;
    wire [2:0]                m_axi_awprot;
    wire                      m_axi_awvalid;
    wire                      m_axi_awready;
    wire [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    wire [AXI_STRB_WIDTH-1:0] m_axi_wstrb;
    wire                      m_axi_wlast;
    wire                      m_axi_wvalid;
    wire                      m_axi_wready;
    wire [AXI_ID_WIDTH-1:0]   m_axi_bid;
    wire [1:0]                m_axi_bresp;
    wire                      m_axi_bvalid;
    wire                      m_axi_bready;
    wire [AXI_ID_WIDTH-1:0]   m_axi_arid;
    wire [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [7:0]                m_axi_arlen;
    wire [2:0]                m_axi_arsize;
    wire [1:0]                m_axi_arburst;
    wire                      m_axi_arlock;
    wire [3:0]                m_axi_arcache;
    wire [2:0]                m_axi_arprot;
    wire                      m_axi_arvalid;
    wire                      m_axi_arready;
    wire [AXI_ID_WIDTH-1:0]   m_axi_rid;
    wire [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    wire [1:0]                m_axi_rresp;
    wire                      m_axi_rlast;
    wire                      m_axi_rvalid;
    wire                      m_axi_rready;

    // --- testbench helper variables ---
    reg  [31:0]             rd_data;
    integer                 timeout_ctr;
    integer                 end_loop;
    integer                 i;
    integer                 pass_count;
    integer                 fail_count;
    reg [127:0]             test_data [0:3];   // known source patterns / expected results

    reg [127:0]             saved_key1, saved_key2;

    reg [127:0] PT0, PT1;

// Instantiation of axi_ram 
// it is our AXI4 slave for testing, this "plays" the axi crossbar + memory for testing purposes, as this is not implemented here 
axi_ram #(
    .DATA_WIDTH (32),
    .ADDR_WIDTH (16),     // match cryptoCore AXI_ADDR_WIDTH
    .ID_WIDTH   (8)
) u_axi_ram (
    .clk(clk),
    .rst(rst),
    // write address/data/resp  ← from DUT master
    .s_axi_awid(m_axi_awid),   .s_axi_awaddr(m_axi_awaddr), .s_axi_awlen(m_axi_awlen),
    .s_axi_awsize(m_axi_awsize),.s_axi_awburst(m_axi_awburst),.s_axi_awlock(m_axi_awlock),
    .s_axi_awcache(m_axi_awcache),.s_axi_awprot(m_axi_awprot),.s_axi_awvalid(m_axi_awvalid),
    .s_axi_awready(m_axi_awready),
    .s_axi_wdata(m_axi_wdata),  .s_axi_wstrb(m_axi_wstrb),   .s_axi_wlast(m_axi_wlast),
    .s_axi_wvalid(m_axi_wvalid),.s_axi_wready(m_axi_wready),
    .s_axi_bid(m_axi_bid),      .s_axi_bresp(m_axi_bresp),   .s_axi_bvalid(m_axi_bvalid),
    .s_axi_bready(m_axi_bready),
    // read address/data        ← from DUT master
    .s_axi_arid(m_axi_arid),    .s_axi_araddr(m_axi_araddr), .s_axi_arlen(m_axi_arlen),
    .s_axi_arsize(m_axi_arsize),.s_axi_arburst(m_axi_arburst),.s_axi_arlock(m_axi_arlock),
    .s_axi_arcache(m_axi_arcache),.s_axi_arprot(m_axi_arprot),.s_axi_arvalid(m_axi_arvalid),
    .s_axi_arready(m_axi_arready),
    .s_axi_rid(m_axi_rid),      .s_axi_rdata(m_axi_rdata),   .s_axi_rresp(m_axi_rresp),
    .s_axi_rlast(m_axi_rlast),  .s_axi_rvalid(m_axi_rvalid), .s_axi_rready(m_axi_rready)
);


cryptoCore #(
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH),
    .LEN_WIDTH      (LEN_WIDTH),
    .KEK(KEK), 
    .BOOT_SRC_ADDR({16'd0, BOOT_SRC}), 
    .BOOT_DST_ADDR({16'd0, BOOT_DST}), 
    .BOOT_N_BLOCKS(N_BLOCKS),
    .BOOT_ENABLE(1)             // this TB tests the boot path itself
) dut (
    .clk(clk),
    .rst(rst),
    // AXI4-Lite slave
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awprot(s_axil_awprot), .s_axil_awvalid(s_axil_awvalid), .s_axil_awready(s_axil_awready),
    .s_axil_wdata(s_axil_wdata),   .s_axil_wstrb(s_axil_wstrb),   .s_axil_wvalid(s_axil_wvalid),   .s_axil_wready(s_axil_wready),
    .s_axil_bresp(s_axil_bresp),   .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready),
    .s_axil_araddr(s_axil_araddr), .s_axil_arprot(s_axil_arprot), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata),   .s_axil_rresp(s_axil_rresp),   .s_axil_rvalid(s_axil_rvalid),   .s_axil_rready(s_axil_rready),
    // AXI4 master → axi_ram
    .m_axi_awid(m_axi_awid),       .m_axi_awaddr(m_axi_awaddr),   .m_axi_awlen(m_axi_awlen),     .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst), .m_axi_awlock(m_axi_awlock),   .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),     .m_axi_wstrb(m_axi_wstrb),     .m_axi_wlast(m_axi_wlast),     .m_axi_wvalid(m_axi_wvalid),    .m_axi_wready(m_axi_wready),
    .m_axi_bid(m_axi_bid),         .m_axi_bresp(m_axi_bresp),     .m_axi_bvalid(m_axi_bvalid),   .m_axi_bready(m_axi_bready),
    .m_axi_arid(m_axi_arid),       .m_axi_araddr(m_axi_araddr),   .m_axi_arlen(m_axi_arlen),     .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst), .m_axi_arlock(m_axi_arlock),   .m_axi_arcache(m_axi_arcache), .m_axi_arprot(m_axi_arprot),
    .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),         .m_axi_rdata(m_axi_rdata),     .m_axi_rresp(m_axi_rresp),     .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),   .m_axi_rready(m_axi_rready)
);

    AES128_Sec_0_Area_0 u_AES128_Sec_0_Area_0 (
        .control_clk    (clk),
        .control_reset  (aes_rst),
        .io_key         (io_key),
        .io_dataIn      (io_dataIn),
        .io_dataOut     (io_dataOut),
        .fsm_enable     (fsm_enable),
        .fsm_ready      (fsm_ready),
        .fsm_valid      (fsm_valid)
    );


    // ----------------------------------------------------------------
    // Clock: 100 MHz (10 ns period)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;


    // Probe: log each block the FSM finishes during boot
    always @(posedge clk) begin
        if (dut.boot_active && dut.u_cryptoCoreFSM.state == 3'd3) begin  // RUNTIME_DONE
            $display("BOOT-DEC t=%0t  nonce=%h  cin=%h  ksout=%h",
                    $time,
                    dut.u_cryptoCoreFSM.ctr_nonce,
                    dut.u_cryptoCoreFSM.cipher_in,
                    dut.u_cryptoCoreFSM.io_dataOut);
        end
    end

    always @(posedge clk) begin
    if (!dut.boot_active && dut.u_cryptoCoreFSM.state == 3'd3) begin  // RUNTIME_DONE, post-boot
        $display("RUN-ENC t=%0t nonce=%h key=%h cin=%h ksout=%h cout=%h",
            $time,
            dut.u_cryptoCoreFSM.ctr_nonce,
            dut.u_cryptoCoreFSM.io_key,
            dut.u_cryptoCoreFSM.cipher_in,
            dut.u_cryptoCoreFSM.io_dataOut,
            dut.u_cryptoCoreFSM.cipher_out);
        end
    end

    always @(posedge clk) begin
        if (!dut.boot_active && m_axi_wvalid && m_axi_wready)
            $display("RUN-WRITE t=%0t wdata=%h wlast=%b", $time, m_axi_wdata, m_axi_wlast); 
    end

    // ----------------------------------------------------------------
    // Helper task: wait N rising edges
    // ----------------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask



    task check;
        input        condition;
        input [1023:0] test_name;
        begin
            if (condition) begin
                $display("PASS: %s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %s  (sim time=%0t)", test_name, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask


    
    task axi4lite_wr_handshake;
        input [7:0]  addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(negedge clk);
            s_axil_awvalid = 1'b1;
            s_axil_awaddr = addr; 
            s_axil_wvalid = 1'b1;
            s_axil_wdata = data; 
            s_axil_wstrb = strb;

            while (! (s_axil_awready && s_axil_wready) ) begin
                @(posedge clk); #1;
            end

            @(negedge clk);
            s_axil_awvalid = 1'b0;
            s_axil_wvalid = 1'b0;
            s_axil_bready = 1'b1;

            while (!s_axil_bvalid) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1; //wait another clock cycle so that bvalid actually deasserts in time
            
            @(negedge clk);
            s_axil_bready = 1'b0;
        end
    endtask



    task axi4lite_rd_handshake;
        input [7:0] addr;
        output [31:0] rdata_out;
        begin
            // Address Phase
            @(negedge clk);
            s_axil_araddr = addr;
            s_axil_arvalid = 1'b1;
            s_axil_rready = 1'b1;

            while (!s_axil_arready) begin
                @(posedge clk); #1;
            end

            @(negedge clk);
            s_axil_arvalid = 1'b0;

            // Data Phase
            while (!s_axil_rvalid) begin
                @(posedge clk); #1;
            end
            #1;

            rdata_out = s_axil_rdata;
            @(negedge clk);
            s_axil_rready = 1'b0;
        end
    endtask


    task load_key_1;
        input [127:0] key_value;
        
        begin
            //as we do not have the boot part implemented yet we use simulation-only force/release to write the key
            force dut.u_keyStorage.key1_wr_en = 1'b1; 
            force dut.u_keyStorage.key1_wr_data = key_value;

            @(posedge clk); #1;
            release dut.u_keyStorage.key1_wr_en; 
            release dut.u_keyStorage.key1_wr_data;
        end
    endtask

    task preload_block(input [15:0] byte_addr, input [127:0] val);
        integer w; begin
            w = byte_addr >> 2;
            u_axi_ram.mem[w+0] = val[31:0];    // low word first — matches adapter lane 0
            u_axi_ram.mem[w+1] = val[63:32];
            u_axi_ram.mem[w+2] = val[95:64];
            u_axi_ram.mem[w+3] = val[127:96];
        end
    endtask

    function [127:0] read_block(input [15:0] byte_addr);
        integer w; begin
            w = byte_addr >> 2;
            read_block = {u_axi_ram.mem[w+3], u_axi_ram.mem[w+2],
                        u_axi_ram.mem[w+1], u_axi_ram.mem[w+0]};
        end
    endfunction


    task gen_keystream(input [127:0] key, input [127:0] ctr_block, output [127:0] ks_out);
        begin
            @(negedge clk);
            while (!fsm_ready) @(negedge clk);   // engine idle & ready
            io_key     = key;
            io_dataIn  = ctr_block;
            @(negedge clk);                       // <-- let io_key/io_dataIn settle before enable
            fsm_enable = 1'b1;
            @(negedge clk);
            fsm_enable = 1'b0;
            while (!fsm_valid) @(negedge clk);
            ks_out = io_dataOut;
        end
    endtask



    task run_host_dma(input [95:0] nonce, input key_sel,
                  input [15:0] src, input [15:0] dst, input [31:0] nblk);
        begin
            axi4lite_wr_handshake(ADDR_N1, nonce[31:0],  4'hF);   // nonce write also resets the counter to 0
            axi4lite_wr_handshake(ADDR_N2, nonce[63:32], 4'hF);
            axi4lite_wr_handshake(ADDR_N3, nonce[95:64], 4'hF);
            axi4lite_wr_handshake(ADDR_CTRL, {31'b0, key_sel}, 4'hF);  // bypass=0, key_sel picks key1/key2
            axi4lite_wr_handshake(ADDR_SRC,  {16'b0, src}, 4'hF);
            axi4lite_wr_handshake(ADDR_DST,  {16'b0, dst}, 4'hF);
            axi4lite_wr_handshake(ADDR_BLKS, nblk, 4'hF);
            axi4lite_wr_handshake(ADDR_GO, 32'h1, 4'hF);
            rd_data = 0;
            while (!rd_data[0]) axi4lite_rd_handshake(ADDR_DMASTAT, rd_data);  // wait until BUSY (bit 0) — transfer started
            rd_data = 0;
            while (!rd_data[1]) axi4lite_rd_handshake(ADDR_DMASTAT, rd_data);  // then wait for DONE (bit 1)
        end
    endtask



    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        
        // Initialise all TB-driven inputs to safe defaults
        rst            = 1'b1;

        s_axil_awaddr  = 8'b0;
        s_axil_awprot  = 3'b0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata   = 32'b0;
        s_axil_wstrb   = 4'b0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = 8'b0;
        s_axil_arprot  = 3'b0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        pass_count     = 0;
        fail_count     = 0;
        timeout_ctr    = 0;
        end_loop       = 0;

        aes_rst    = 1'b1;
        io_key     = KEK;     
        io_dataIn  = 128'b0;
        fsm_enable = 1'b0;


        
        // let the clock settle, release ONLY the reference AES (DUT still in reset)
        wait_cycles(4);
        @(negedge clk); aes_rst = 1'b0;
        wait_cycles(2);



        preload_block((BOOT_SRC + 16'd0), {IV_NONCE, 32'h0} /* logic[127:0] */);

         // body blocks: bitstream position p = i+1 uses CTR counter (p-1) = i
        for (i = 0; i < BODY; i = i + 1) begin
            plaintext[i] = {96'hCAFEF00D_00000000_00000000 + i, 32'd0} ^ (128'h1111_2222_3333_4444_5555_6666_7777_8888 + i);
            gen_keystream(KEK, {IV_NONCE, i[31:0]}, ks);   // M3: {nonce, i}
            preload_block(BOOT_SRC + (i+1)*16, plaintext[i] ^ ks);
            $display("GEN  blk %0d: ctr=%0d  ks=%h  plain=%h  ct=%h",
                 i, i, ks, plaintext[i], plaintext[i] ^ ks);
        end

        // key blocks (bitstream positions N-2, N-1): counter continues past the body
        i = BODY;
        gen_keystream(KEK, {IV_NONCE, i[31:0]}, ks);
        preload_block(BOOT_SRC + (N_BLOCKS-2)*16, KEY1_VAL ^ ks);

        i = BODY + 1;
        gen_keystream(KEK, {IV_NONCE, i[31:0]}, ks);
        preload_block(BOOT_SRC + (N_BLOCKS-1)*16, KEY2_VAL ^ ks);

        // --- release the DUT: boot runs automatically ---
        @(negedge clk); rst = 1'b0;


        // M5-A: mid-boot host nonce write must be ignored (gate = ~boot_active)
        while (dut.u_axi4LiteRegister.ctr_count < 32'd2) @(posedge clk);   // boot now in the body phase
        axi4lite_wr_handshake(8'h40, 32'hDEADBEEF, 4'hF); // clobber attempt on CTR_NONCE_1 (0x40)


        // wait for boot to finish
        timeout_ctr = 0;
        while (!dut.boot_done && timeout_ctr < 50000) begin
            @(posedge clk); timeout_ctr = timeout_ctr + 1;
        end
        check(dut.boot_done, "boot_done asserted");

        // --- verify the decrypted body landed at BOOT_DST ---
        for (i = 0; i < BODY; i = i + 1) begin
            check(read_block(BOOT_DST + i*16) == plaintext[i], "body block decrypted correctly");
        end

        check(dut.u_axi4LiteRegister.ctr_iv    == IV_NONCE,       "nonce loaded from IV block");
        check(dut.u_axi4LiteRegister.ctr_count == (N_BLOCKS - 1), "counter = 5 body + 2 keys = 7");

        // --- key extraction ---
        check(dut.u_keyStorage.key1 == KEY1_VAL, "key1 extracted into keyStorage");
        check(dut.u_keyStorage.key2 == KEY2_VAL, "key2 extracted into keyStorage");
        check(dut.u_keyStorage.key1_valid && dut.u_keyStorage.key2_valid, "both keys marked valid");

        // --- security: keys must never appear in memory ---
        check(read_block(BOOT_SRC + (N_BLOCKS-2)*16) !== KEY1_VAL, "key1 plaintext not left in source");
        check(read_block(BOOT_DST + BODY*16)         !== KEY1_VAL, "no key written past body at DST");



        // M5-B: post-boot host register activity must not affect the keys
        saved_key1 = dut.u_keyStorage.key1;
        saved_key2 = dut.u_keyStorage.key2;
        axi4lite_wr_handshake(8'h40, 32'h11223344, 4'hF);  // nonce write — now allowed (boot done)
        axi4lite_wr_handshake(8'h00, 32'h00000001, 4'hF);  // CTRL write (key_sel etc.)
        check(dut.u_keyStorage.key1 == saved_key1 &&
        dut.u_keyStorage.key2 == saved_key2, "keys unchanged by post-boot host writes");



        PT0 = 128'h00112233445566778899aabbccddeeff;
        PT1 = 128'hffeeddccbbaa99887766554433221100;
        preload_block(16'h2000, PT0);
        preload_block(16'h2010, PT1);

        run_host_dma(RT_NONCE, 1'b0 /*key1*/, 16'h2000, 16'h3000, 32'd2);
        $display("POST-RUN: boot_state=%0d read_only=%b discard=%b dma_state=%0d",
                 dut.u_bootCtrl.state, dut.read_only, dut.boot_discard,
                 dut.u_cryptoDmaCtrl.state);


        // re-prime the reference AES with KEY1_VAL stable from reset (avoids the key-switch latch)
        io_key = KEY1_VAL;
        @(negedge clk); aes_rst = 1'b1;
        wait_cycles(3);
        @(negedge clk); aes_rst = 1'b0;
        wait_cycles(2);

        gen_keystream(KEY1_VAL, {RT_NONCE, 32'd0}, ks);
        check(read_block(16'h3000) == (PT0 ^ ks), "runtime block0 encrypted with extracted key1");
        gen_keystream(KEY1_VAL, {RT_NONCE, 32'd1}, ks);
        check(read_block(16'h3010) == (PT1 ^ ks), "runtime block1 encrypted with extracted key1");


        $display("-------------------------------");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $display("-------------------------------");
        $finish;
    end

endmodule

`default_nettype wire