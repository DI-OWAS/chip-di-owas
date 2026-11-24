`timescale 1ns / 1ps
`default_nettype none

module tb_cryptoCore_dma;

    // --- parameters (match the DUT) ---
    localparam AXI_DATA_WIDTH = 32;
    localparam AXI_ADDR_WIDTH = 16;
    localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;
    localparam AXI_ID_WIDTH   = 8;
    localparam LEN_WIDTH      = 20;

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
    reg  [31:0]  rd_data;
    integer      timeout_ctr;
    integer      end_loop;
    integer      i;
    integer      pass_count;
    integer      fail_count;
    reg [127:0]  test_data [0:3];   // known source patterns / expected results

    reg [127:0] tag_rd;

    // DATA-IF request counters (cycles with arvalid/awvalid high)
    integer      ar_cnt = 0;
    integer      aw_cnt = 0;

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
    .LEN_WIDTH      (LEN_WIDTH)
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


// ----------------------------------------------------------------
    // Clock: 100 MHz (10 ns period)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // count DATA-IF requests (used to check that nothing happens on the bus after reset)
    always @(posedge clk) begin
        if (m_axi_arvalid) ar_cnt = ar_cnt + 1;
        if (m_axi_awvalid) aw_cnt = aw_cnt + 1;
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


        
        // Starting
        wait_cycles(4);
        @(negedge clk); rst = 1'b0;                 // release on falling edge to avoid race
        #1;                                         // small delta so outputs settle

        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[2] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data);   // STATUS[2] = boot_done
            timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[2]) begin check(0, "boot never completed"); $finish; end

        
        $display("PROBE t=%0t boot_active=%b boot_done=%b dc_go(GO)=%b",
        $time, dut.boot_active, dut.boot_done, dut.dc_go);

        // Test 1 - boot disabled (BOOT_ENABLE=0, default): no DATA-IF accesses, static keys loaded
        wait_cycles(200);
        check(ar_cnt == 0 && aw_cnt == 0, "T1: no DATA-IF access after reset (boot disabled)");
        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[3] === 1'b1 && rd_data[4] === 1'b1, "T1: static key1/key2 valid after reset");

        // Test 2 - encrypt 4 NIST block through DMA path

        // key1 = STATIC_KEY1 (NIST SP 800-38A key, loaded after reset because BOOT_ENABLE=0)


        axi4lite_rd_handshake(8'h04, rd_data);          // check status

        //sanity check if key1_valid
        if (!rd_data[3]) begin
            check(0, "T2: key1 load failed — aborting");
            $finish;
        end

        // write IV
        //write ctr_nonce over 3 32 bit axi4Lite writes
        axi4lite_wr_handshake(8'h40, 32'hf8f9fafb, 4'hf);
        axi4lite_wr_handshake(8'h44, 32'hf4f5f6f7, 4'hf);
        axi4lite_wr_handshake(8'h48, 32'hf0f1f2f3, 4'hf);

        // forcing ctr to NIST start (instead of starting with zero)
        force dut.u_axi4LiteRegister.ctr_count = 32'hfcfdfeff;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;


        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);


        // preload SRC with NIST plaintext
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);


        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf); // SRC_ADDR
        axi4lite_wr_handshake(8'h54, 32'h0000_1000, 4'hf); // DST_ADDR
        axi4lite_wr_handshake(8'h58, 32'h0000_0004, 4'hf); // DMA_BLOCKS
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO = 1



        timeout_ctr = 300;
        end_loop = 0;

        while (timeout_ctr !== 0 && !end_loop) begin
            
            axi4lite_rd_handshake(8'h60, rd_data); //read DMA_STATUS register
            
            //if busy wait one cycle and decrement timeout_ctr 
            if (!rd_data[1]) begin
                wait_cycles(1);
                timeout_ctr = timeout_ctr - 1;
            end
            else end_loop = 1;
        end

        if (timeout_ctr === 0) begin
            check(0, "timeout");
        end 

        else begin
            check(read_block(16'h1000 + 0*16) === 128'h874d6191b620e3261bef6864990db6ce, "T2: block 0");
            check(read_block(16'h1000 + 1*16) === 128'h9806f66b7970fdff8617187bb9fffdff, "T2: block 1");
            check(read_block(16'h1000 + 2*16) === 128'h5ae4df3edbd5d35e5b4f09020db03eab, "T2: block 2");
            check(read_block(16'h1000 + 3*16) === 128'h1e031dda2fbe03d1792170a0f3009cee, "T2: block 3");
        end



        // Test 3 - feeding ciphertext back through with the same key + IV and check if resulting plaintext is correct

        // write IV
        //write ctr_nonce over 3 32 bit axi4Lite writes
        axi4lite_wr_handshake(8'h40, 32'hf8f9fafb, 4'hf);
        axi4lite_wr_handshake(8'h44, 32'hf4f5f6f7, 4'hf);
        axi4lite_wr_handshake(8'h48, 32'hf0f1f2f3, 4'hf);

        // forcing ctr to NIST start (instead of starting with zero)
        force dut.u_axi4LiteRegister.ctr_count = 32'hfcfdfeff;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);

        axi4lite_wr_handshake(8'h50, 32'h0000_1000, 4'hf); // SRC_ADDR
        axi4lite_wr_handshake(8'h54, 32'h0000_2000, 4'hf); // DST_ADDR
        axi4lite_wr_handshake(8'h58, 32'h0000_0004, 4'hf); // DMA_BLOCKS
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO = 1

        timeout_ctr = 300;
        end_loop = 0;

        while (timeout_ctr !== 0 && !end_loop) begin
            
            axi4lite_rd_handshake(8'h60, rd_data); //read DMA_STATUS register
            
            //if busy wait one cycle and decrement timeout_ctr 
            if (!rd_data[1]) begin
                wait_cycles(1);
                timeout_ctr = timeout_ctr - 1;
            end
            else end_loop = 1;
        end

        if (timeout_ctr === 0) begin
            check(0, "timeout");
        end 

        // check if result is as expected the original plaintext
        else begin
            check(read_block(16'h2000 + 0*16) === 128'h6bc1bee22e409f96e93d7e117393172a, "T3: block 0");
            check(read_block(16'h2000 + 1*16) === 128'hae2d8a571e03ac9c9eb76fac45af8e51, "T3: block 1");
            check(read_block(16'h2000 + 2*16) === 128'h30c81c46a35ce411e5fbc1191a0a52ef, "T3: block 2");
            check(read_block(16'h2000 + 3*16) === 128'hf69f2445df4f9b17ad2b417be66c3710, "T3: block 3");

        end



        // Test 4: bypass via plain copy

        axi4lite_wr_handshake(8'h00, 32'h2, 4'hF);  //write bypass = 1 (CTRL[1]) into CTRL register

        // preload SRC with distinct per block pattern
        for (i = 0; i < 4; i = i + 1) begin
            preload_block(16'h0000 + i*16, {32'hDEAD_BEEF, 32'hCAFE_BABE, i[31:0], ~i[31:0]});
        end

        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf); // SRC_ADDR
        axi4lite_wr_handshake(8'h54, 32'h0000_1000, 4'hf); // DST_ADDR
        axi4lite_wr_handshake(8'h58, 32'h0000_0004, 4'hf); // DMA_BLOCKS
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO = 1

        timeout_ctr = 300;
        end_loop = 0;

        while (timeout_ctr !== 0 && !end_loop) begin
            
            axi4lite_rd_handshake(8'h60, rd_data); //read DMA_STATUS register
            
            //if busy wait one cycle and decrement timeout_ctr 
            if (!rd_data[1]) begin
                wait_cycles(1);
                timeout_ctr = timeout_ctr - 1;
            end
            else end_loop = 1;
        end

        if (timeout_ctr === 0) begin
            check(0, "timeout");
        end 

        // check if result is as expected the original plaintext
        else begin
            check(read_block(16'h1000 + 0*16) === {32'hDEAD_BEEF, 32'hCAFE_BABE, 32'd0, ~32'd0}, "T4: block 0");
            check(read_block(16'h1000 + 1*16) === {32'hDEAD_BEEF, 32'hCAFE_BABE, 32'd1, ~32'd1}, "T4: block 1");
            check(read_block(16'h1000 + 2*16) === {32'hDEAD_BEEF, 32'hCAFE_BABE, 32'd2, ~32'd2}, "T4: block 2");
            check(read_block(16'h1000 + 3*16) === {32'hDEAD_BEEF, 32'hCAFE_BABE, 32'd3, ~32'd3}, "T4: block 3");
        end


        // ================= T5: Phase B register read/write =================
        // --- config registers: write a pattern, read it back ---
        axi4lite_wr_handshake(8'h64, 32'h11223344, 4'hf);   // CCM_NONCE_0
        axi4lite_rd_handshake(8'h64, rd_data);
        check(rd_data === 32'h11223344, "T5: CCM_NONCE_0 rw");

        axi4lite_wr_handshake(8'h68, 32'h55667788, 4'hf);   // CCM_NONCE_1
        axi4lite_rd_handshake(8'h68, rd_data);
        check(rd_data === 32'h55667788, "T5: CCM_NONCE_1 rw");

        axi4lite_wr_handshake(8'h6C, 32'h99aabbcc, 4'hf);   // CCM_NONCE_2
        axi4lite_rd_handshake(8'h6C, rd_data);
        check(rd_data === 32'h99aabbcc, "T5: CCM_NONCE_2 rw");

        axi4lite_wr_handshake(8'h70, 32'h000000dd, 4'hf);   // CCM_NONCE_3 (top byte only)
        axi4lite_rd_handshake(8'h70, rd_data);
        check(rd_data === 32'h000000dd, "T5: CCM_NONCE_3 rw (8-bit)");

        axi4lite_wr_handshake(8'h74, 32'h00000028, 4'hf);   // PAYLOAD_LEN = 40
        axi4lite_rd_handshake(8'h74, rd_data);
        check(rd_data === 32'h00000028, "T5: PAYLOAD_LEN rw");

        axi4lite_wr_handshake(8'h80, 32'hdeadbeef, 4'hf);   // TAG_IN_0
        axi4lite_rd_handshake(8'h80, rd_data);
        check(rd_data === 32'hdeadbeef, "T5: TAG_IN_0 rw");

        axi4lite_wr_handshake(8'h8C, 32'hcafebabe, 4'hf);   // TAG_IN_3
        axi4lite_rd_handshake(8'h8C, rd_data);
        check(rd_data === 32'hcafebabe, "T5: TAG_IN_3 rw");

        // --- CTRL: mode=CCM(2), decrypt=1  → 5'b1_10_0_0 = 0x18 ---
        axi4lite_wr_handshake(8'h00, 32'h18, 4'hf);
        axi4lite_rd_handshake(8'h00, rd_data);
        check(rd_data[4:0] === 5'h18, "T5: CTRL mode/decrypt rw");

        // --- read-only paths: engines idle, so results read 0 (just prove the read decode) ---
        axi4lite_rd_handshake(8'h90, rd_data);              // TAG_OUT_0
        check(rd_data === 32'h0, "T5: TAG_OUT_0 reads 0 (idle)");

        axi4lite_rd_handshake(8'h04, rd_data);              // STATUS
        check(rd_data[7:6] === 2'b00, "T5: STATUS done/auth = 0 (idle)");


        // ===== T6: CMAC over the DMA path =====
        preload_block(16'h0000, 128'h6bc1bee2_2e409f96_e93d7e11_7393172a);   // the message
        axi4lite_wr_handshake(8'h40, 32'h0,        4'hf);  // clears ctr_count
        axi4lite_wr_handshake(8'h74, 32'h00000010, 4'hf);  // PAYLOAD_LEN = 16  (C3a: drives DMA len now)
        axi4lite_wr_handshake(8'h00, 32'h04,       4'hf);  // CTRL: mode=CMAC
        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf); // SRC_ADDR
        axi4lite_wr_handshake(8'h58, 32'h0000_0001, 4'hf); // DMA_BLOCKS = 1
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO


        // wait for the ENGINE to finish (STATUS[6]=engine_done) — not just dma_done!
        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data);
            timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T6: engine never done");

        // read the latched tag
        axi4lite_rd_handshake(8'h90, rd_data); tag_rd[31:0]   = rd_data;
        axi4lite_rd_handshake(8'h94, rd_data); tag_rd[63:32]  = rd_data;
        axi4lite_rd_handshake(8'h98, rd_data); tag_rd[95:64]  = rd_data;
        axi4lite_rd_handshake(8'h9C, rd_data); tag_rd[127:96] = rd_data;
        check(tag_rd === 128'h070a16b4_6b4d4144_f79bdd9d_d04a287c, "T6: CMAC-over-DMA tag");


        // ===== T7: CCM encrypt over DMA =====
        preload_block(16'h0000, 128'h20212223_24252627_28292a2b_2c2d2e2f);  // plaintext
        // CCM nonce 00112233445566778899aabbcc → register words (byte0 = MSB in the engine):
        axi4lite_wr_handshake(8'h64, 32'h99aabbcc, 4'hf);   // CCM_NONCE_0 = nonce[31:0]
        axi4lite_wr_handshake(8'h68, 32'h55667788, 4'hf);   // CCM_NONCE_1 = nonce[63:32]
        axi4lite_wr_handshake(8'h6C, 32'h11223344, 4'hf);   // CCM_NONCE_2 = nonce[95:64]
        axi4lite_wr_handshake(8'h70, 32'h00000000, 4'hf);   // CCM_NONCE_3 = nonce[103:96]=0x00
        axi4lite_wr_handshake(8'h74, 32'h00000010, 4'hf);   // PAYLOAD_LEN = 16
        axi4lite_wr_handshake(8'h40, 32'h0, 4'hf);          // clear ctr_count (avoid refuse)
        axi4lite_wr_handshake(8'h00, 32'h08, 4'hf);         // CTRL: mode=CCM(2), decrypt=0 → 5'b0_10_0_0=0x08
        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf);  // SRC
        axi4lite_wr_handshake(8'h54, 32'h0000_1000, 4'hf);  // DST
        axi4lite_wr_handshake(8'h58, 32'h0000_0001, 4'hf);  // DMA_BLOCKS = 1
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf);  // GO

        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data); timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T7: engine never done");
        check(read_block(16'h1000) === 128'h712ef053_5b0956aa_cab44659_6a4cf70a, "T7: CCM ciphertext");
        axi4lite_rd_handshake(8'h90, rd_data); tag_rd[31:0]   = rd_data;
        axi4lite_rd_handshake(8'h94, rd_data); tag_rd[63:32]  = rd_data;
        axi4lite_rd_handshake(8'h98, rd_data); tag_rd[95:64]  = rd_data;
        axi4lite_rd_handshake(8'h9C, rd_data); tag_rd[127:96] = rd_data;
        check(tag_rd === 128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e0, "T7: CCM tag U");

        // ===== T8: CCM decrypt+verify over DMA =====
        preload_block(16'h0000, 128'h712ef053_5b0956aa_cab44659_6a4cf70a);  // ciphertext
        // same nonce + payload_len as T7 (still set); load tag_in = U:
        axi4lite_wr_handshake(8'h80, 32'h28a9c6e0, 4'hf);   // TAG_IN_0 = U[31:0]
        axi4lite_wr_handshake(8'h84, 32'hd4a9e14a, 4'hf);   // TAG_IN_1 = U[63:32]
        axi4lite_wr_handshake(8'h88, 32'he37c7739, 4'hf);   // TAG_IN_2 = U[95:64]
        axi4lite_wr_handshake(8'h8C, 32'h4918ab9a, 4'hf);   // TAG_IN_3 = U[127:96]
        axi4lite_wr_handshake(8'h00, 32'h18, 4'hf);         // CTRL: mode=CCM(2), decrypt=1 → 0x18
        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf);  // SRC
        axi4lite_wr_handshake(8'h54, 32'h0000_2000, 4'hf);  // DST
        axi4lite_wr_handshake(8'h58, 32'h0000_0001, 4'hf);  // DMA_BLOCKS = 1
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf);  // GO

        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data); timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T8: engine never done");
        check(read_block(16'h2000) === 128'h20212223_24252627_28292a2b_2c2d2e2f, "T8: CCM plaintext");
        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[7] === 1'b1, "T8: CCM auth_ok");


        // ===== T9: CMAC over DMA, 20 bytes (partial last block, nbytes=4) =====
        preload_block(16'h0000, 128'h6bc1bee2_2e409f96_e93d7e11_7393172a); // block0 (value-conv)
        u_axi_ram.mem[4] = 32'hae2d8a57;                                   // tail word @ addr 0x10, byte-forward
        axi4lite_wr_handshake(8'h40, 32'h0,        4'hf);  // clear ctr_count
        axi4lite_wr_handshake(8'h74, 32'h00000014, 4'hf);  // PAYLOAD_LEN = 20
        axi4lite_wr_handshake(8'h00, 32'h04,       4'hf);  // CTRL: mode=CMAC
        axi4lite_wr_handshake(8'h50, 32'h0,        4'hf);  // SRC
        axi4lite_wr_handshake(8'h58, 32'h2,        4'hf);  // DMA_BLOCKS (refuse-check only; len uses payload_len)
        axi4lite_wr_handshake(8'h5C, 32'h1,        4'hf);  // GO

        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data); timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T9: engine never done");
        axi4lite_rd_handshake(8'h90, rd_data); tag_rd[31:0]   = rd_data;
        axi4lite_rd_handshake(8'h94, rd_data); tag_rd[63:32]  = rd_data;
        axi4lite_rd_handshake(8'h98, rd_data); tag_rd[95:64]  = rd_data;
        axi4lite_rd_handshake(8'h9C, rd_data); tag_rd[127:96] = rd_data;
        check(tag_rd === 128'h7d85449e_a6ea19c8_23a7bf78_837dfade, "T9: CMAC 20B (partial) tag");

        // ===== T10: CCM encrypt over DMA, 20 bytes (4-byte tail) =====
        preload_block(16'h0000, 128'h20212223_24252627_28292a2b_2c2d2e2f); // plaintext block0
        u_axi_ram.mem[(16'h0010)>>2] = 32'h30313233;                        // plaintext tail (byte-forward)
        axi4lite_wr_handshake(8'h64, 32'h99aabbcc, 4'hf);  // CCM_NONCE_0
        axi4lite_wr_handshake(8'h68, 32'h55667788, 4'hf);  // CCM_NONCE_1
        axi4lite_wr_handshake(8'h6C, 32'h11223344, 4'hf);  // CCM_NONCE_2
        axi4lite_wr_handshake(8'h70, 32'h00000000, 4'hf);  // CCM_NONCE_3
        axi4lite_wr_handshake(8'h74, 32'h00000014, 4'hf);  // PAYLOAD_LEN = 20
        axi4lite_wr_handshake(8'h40, 32'h0,        4'hf);  // clear ctr_count
        axi4lite_wr_handshake(8'h00, 32'h08,       4'hf);  // CTRL: mode=CCM, decrypt=0
        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf); // SRC
        axi4lite_wr_handshake(8'h54, 32'h0000_1000, 4'hf); // DST
        axi4lite_wr_handshake(8'h58, 32'h0000_0002, 4'hf); // DMA_BLOCKS (refuse-check only)
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO
        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data); timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T10: engine never done");
        check(read_block(16'h1000) === 128'h712ef053_5b0956aa_cab44659_6a4cf70a, "T10: CCM20 ct block0");
        check(u_axi_ram.mem[(16'h1010)>>2] === 32'h0cbe8409,                     "T10: CCM20 ct tail");
        axi4lite_rd_handshake(8'h90, rd_data); tag_rd[31:0]   = rd_data;
        axi4lite_rd_handshake(8'h94, rd_data); tag_rd[63:32]  = rd_data;
        axi4lite_rd_handshake(8'h98, rd_data); tag_rd[95:64]  = rd_data;
        axi4lite_rd_handshake(8'h9C, rd_data); tag_rd[127:96] = rd_data;
        check(tag_rd === 128'hd75e527f_55e83085_9597fee8_14fcfa9a,               "T10: CCM20 tag U");

        // ===== T11: CCM decrypt+verify over DMA, 20 bytes =====
        preload_block(16'h0000, 128'h712ef053_5b0956aa_cab44659_6a4cf70a); // ciphertext block0
        u_axi_ram.mem[(16'h0010)>>2] = 32'h0cbe8409;                        // ciphertext tail (byte-forward)
        axi4lite_wr_handshake(8'h80, 32'h14fcfa9a, 4'hf);  // TAG_IN_0 = U[31:0]
        axi4lite_wr_handshake(8'h84, 32'h9597fee8, 4'hf);  // TAG_IN_1
        axi4lite_wr_handshake(8'h88, 32'h55e83085, 4'hf);  // TAG_IN_2
        axi4lite_wr_handshake(8'h8C, 32'hd75e527f, 4'hf);  // TAG_IN_3 = U[127:96]
        axi4lite_wr_handshake(8'h74, 32'h00000014, 4'hf);  // PAYLOAD_LEN = 20 (nonce still set from T10)
        axi4lite_wr_handshake(8'h00, 32'h18,       4'hf);  // CTRL: mode=CCM, decrypt=1
        axi4lite_wr_handshake(8'h50, 32'h0000_0000, 4'hf); // SRC
        axi4lite_wr_handshake(8'h54, 32'h0000_2000, 4'hf); // DST
        axi4lite_wr_handshake(8'h58, 32'h0000_0002, 4'hf); // DMA_BLOCKS
        axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO
        timeout_ctr = 30000; rd_data = 0;
        while (!rd_data[6] && timeout_ctr != 0) begin
            axi4lite_rd_handshake(8'h04, rd_data); timeout_ctr = timeout_ctr - 1;
        end
        if (!rd_data[6]) check(0, "T11: engine never done");
        check(read_block(16'h2000) === 128'h20212223_24252627_28292a2b_2c2d2e2f, "T11: CCM20 pt block0");
        check(u_axi_ram.mem[(16'h2010)>>2] === 32'h30313233,                     "T11: CCM20 pt tail");
        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[7] === 1'b1,                                               "T11: CCM20 auth_ok");


        $display("-------------------------------");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $display("-------------------------------");
        $finish;
    end

endmodule

`default_nettype wire