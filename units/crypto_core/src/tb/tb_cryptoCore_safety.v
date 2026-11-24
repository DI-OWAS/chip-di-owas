`timescale 1ns / 1ps
`default_nettype none

module tb_cryptoCore_safety; 

    reg                 clk;
    reg                 rst;

    localparam AXI_DATA_WIDTH = 32;
    localparam AXI_ADDR_WIDTH = 16;
    localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;
    localparam AXI_ID_WIDTH   = 8;
    localparam LEN_WIDTH      = 20;

    //ports for axil_reg_if module
    reg [7:0]           s_axil_awaddr;
    reg [2:0]           s_axil_awprot;
    reg                 s_axil_awvalid;
    wire                s_axil_awready;
    reg [31:0]          s_axil_wdata;
    reg [3:0]           s_axil_wstrb;
    reg                 s_axil_wvalid;
    wire                s_axil_wready;
    wire [1:0]          s_axil_bresp;
    wire                s_axil_bvalid;
    reg                 s_axil_bready;
    reg [7:0]           s_axil_araddr;
    reg [2:0]           s_axil_arprot;
    reg                 s_axil_arvalid;
    wire                s_axil_arready;
    wire [31:0]         s_axil_rdata;
    wire [1:0]          s_axil_rresp;
    wire                s_axil_rvalid;
    reg                 s_axil_rready;


    // register to capture result of read task
    reg [31:0]          rd_data;
    
    reg [127:0] DST1, DST2;

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
        .BOOT_ENABLE    (1)     // no static keys: T3/T4 need empty key slots after reset (boot is forced done below)
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

    integer timeout_ctr;
    integer end_loop;
    

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

    // ----------------------------------------------------------------
    // Pass/fail counter
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;

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

    task load_key_2;
        input [127:0] key_value;
        
        begin
            //as we do not have the boot part implemented yet we use simulation-only force/release to write the key
            force dut.u_keyStorage.key2_wr_en = 1'b1; 
            force dut.u_keyStorage.key2_wr_data = key_value;

            @(posedge clk); #1;
            release dut.u_keyStorage.key2_wr_en; 
            release dut.u_keyStorage.key2_wr_data;
        end
    endtask

    task do_reset;
        begin
            rst = 1;
            wait_cycles(4);
            @(negedge clk); rst = 1'b0;
            #1;
        end
    endtask

    task write_iv;
        input [95:0] iv;
        begin
            //write ctr_nonce over 3 32 bit axi4Lite writes
            axi4lite_wr_handshake(8'h40, iv[31:0], 4'hf);
            axi4lite_wr_handshake(8'h44, iv[63:32], 4'hf);
            axi4lite_wr_handshake(8'h48, iv[95:64], 4'hf);
        end
    endtask

    task program_and_go;
        input [31:0] src;
        input [31:0] dst;
        input [31:0] blocks;
        begin
            axi4lite_wr_handshake(8'h50, src, 4'hf); // SRC_ADDR
            axi4lite_wr_handshake(8'h54, dst, 4'hf); // DST_ADDR
            axi4lite_wr_handshake(8'h58, blocks, 4'hf); // DMA_BLOCKS
            axi4lite_wr_handshake(8'h5C, 32'h0000_0001, 4'hf); // GO = 1
        end
    endtask

    task poll_done;
        begin
           // poll until done is set
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
        // Skip the boot sequence for the runtime safety suite — boot is covered by tb_cryptoCore_boot.
        // Forcing the state survives resets, so do_reset() never re-triggers boot.
        force dut.u_bootCtrl.state = 4'd7;   // 4'd7 = BOOT_DONE (per bootCtrl localparams)


        // Initialise all inputs to safe defaults
        rst             = 1'b1;
        s_axil_awvalid  = 1'b0;
        s_axil_wvalid   = 1'b0;
        s_axil_arvalid  = 1'b0;
        s_axil_bready   = 1'b0;
        s_axil_rready   = 1'b0;
        s_axil_awaddr   = 1'b0;
        s_axil_araddr   = 1'b0;
        s_axil_wdata    = 1'b0;
        s_axil_wstrb    = 1'b0;
        s_axil_awprot   = 3'b0;
        s_axil_arprot   = 3'd0;

        pass_count      = 1'b0;
        fail_count      = 1'b0;
        

        
        // Test 1 --- Overflow protection

        do_reset;

        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);

        axi4lite_rd_handshake(8'h04, rd_data);          // check status

        //sanity check if key1_valid
        if (!rd_data[3]) begin
            check(0, "T1: key1 load failed — aborting");
            $finish;
        end

        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);
        
        // force ctr to overflow
        force dut.u_axi4LiteRegister.ctr_count = 32'hFFFFFFFE;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;


        // preload SRC with NIST plaintext
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);

        
        program_and_go(0, 16'h1000, 4);
        
        poll_done;

        
        check(rd_data[2] === 1, "T1: dma_error set on overflow");
        check(read_block(16'h1000 + 0*16) === 128'h0, "T1: block 0 untouched");
        check(read_block(16'h1000 + 1*16) === 128'h0, "T1: block 1 untouched");
        check(read_block(16'h1000 + 2*16) === 128'h0, "T1: block 2 untouched");
        check(read_block(16'h1000 + 3*16) === 128'h0, "T1: block 3 untouched");

    

        // write different IV --> resets ctr_overflow
        write_iv(96'hfffffffff4f5f6f7f8f9fafb);

        // try another encryption 
        program_and_go(0, 16'h1000, 4);

        poll_done;

        check(rd_data[2] === 0, "T1: dma_error not set after new IV");
        check(read_block(16'h1000 + 0*16) !== 128'h0, "T1: block 0 working again");
        check(read_block(16'h1000 + 1*16) !== 128'h0, "T1: block 1 working again");
        check(read_block(16'h1000 + 2*16) !== 128'h0, "T1: block 2 working again");
        check(read_block(16'h1000 + 3*16) !== 128'h0, "T1: block 3 working again");





        // Test 2 --- Key isolation

        do_reset;
        
        // load two different keys
        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);
        load_key_2(128'hAAAAAAAABBBBBBBBCCCCCCCCDDDDDDDD);


        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);
        
        // force ctr
        force dut.u_axi4LiteRegister.ctr_count = 32'hfcfdfeff;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;


        // preload SRC with NIST plaintext
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);


        
        program_and_go(0, 16'h2000, 1);

        poll_done;
        
        DST1 = read_block(16'h2000);


        // write different IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);
        
        // CTRL = key_sel=1 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h1, 4'hf);

        // force ctr
        force dut.u_axi4LiteRegister.ctr_count = 32'hfcfdfeff;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;

        // try another encryption, different key should lead to differnt result
        program_and_go(0, 16'h3000, 1);

        poll_done;

        DST2 = read_block(16'h3000);

        // check that key selection switches end to end
        check(DST1 !== DST2, "T2: key_sel switches end-to-end");
        check(DST1 === 128'h874d6191b620e3261bef6864990db6ce, "T2: key1 path is correct");




        // Test 3 --- reset during operation
        do_reset;
        
        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);

        axi4lite_rd_handshake(8'h04, rd_data);          // check status

        //sanity check if key1_valid
        if (!rd_data[3]) begin
            check(0, "T3: key1 load failed — aborting");
            $finish;
        end

        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);
        

        // preload SRC with NIST plaintext
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);

        
        program_and_go(0, 16'h4000, 4);

        wait_cycles(50);
        
        do_reset;

        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[0] === 0 && rd_data[1] === 0 && rd_data[3] === 0, "T3: key1 zeroized by async reset");
        axi4lite_rd_handshake(8'h60, rd_data);
        check(rd_data[0] === 0 && rd_data[1] === 0, "T3: all bits clear");
        
        // recovery
        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);

        axi4lite_rd_handshake(8'h04, rd_data);          // check status

        //sanity check if key1_valid
        if (!rd_data[3]) begin
            check(0, "T3: key1 load failed — aborting");
            $finish;
        end

        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);
        
        // preload 1 block in src
        preload_block(16'h0000, 128'h6bc1bee22e409f96e93d7e117393172a);
        
        program_and_go(0, 16'h4400, 1);

        poll_done;

        check(read_block(16'h4400) !== 128'h0, "T3: pipeline recovers after reset in midst of operation");




        // Test 4 --- no-key -> refusal + counter readback

        do_reset;
        
        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);

        // CTRL = key_sel=0 (key1), bypass=0 (encrypt)
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);
        // here key1 is selected but no key is loaded --> should lead to crypto not starting

        // preload 1 block in src
        preload_block(16'h0000, 128'h6bc1bee22e409f96e93d7e117393172a);
        
        program_and_go(0, 16'h5000, 1);

        poll_done;

        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[2] === 1, "T4: crypto did not start");
        check(read_block(16'h5000) === 128'h0, "T4: mem[0x500] untouched");

        

        // ctr check
        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);

        axi4lite_rd_handshake(8'h04, rd_data);          // check status

        //sanity check if key1_valid
        if (!rd_data[3]) begin
            check(0, "T3: key1 load failed — aborting");
            $finish;
        end

        // write IV
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);
        check(dut.u_axi4LiteRegister.ctr_count === 32'h0, "T4: ctr starts at 0 again");

        // preload 4 blocks in src
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);

        program_and_go(0, 16'h5800, 4); 
        
        poll_done;

        check(dut.u_axi4LiteRegister.ctr_count === 32'd4, "T4: ctr incremented correctly");




        // Test 5 --- Overflow BOUNDARY (off-by-one edge)
        // Pins the exact point where nonce reuse would begin.

        // ---- 5a: transfer that ENDS exactly at 0xFFFFFFFF must be ALLOWED ----
        // ctr_count = 0xFFFFFFFC, 4 blocks -> uses FFFFFFFC,FFFFFFFD,FFFFFFFE,FFFFFFFF
        // (four distinct counters, no reuse) -> gate must NOT refuse.
        do_reset;

        load_key_1(128'h2b7e151628aed2a6abf7158809cf4f3c);
        axi4lite_rd_handshake(8'h04, rd_data);
        if (!rd_data[3]) begin
            check(0, "T5: key1 load failed — aborting");
            $finish;
        end

        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);   // resets ctr_count=0, clears overflow
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);  // CTRL: key1, encrypt

        // force the counter to the exact edge (after the IV write that would reset it)
        force dut.u_axi4LiteRegister.ctr_count = 32'hFFFFFFFC;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;

        // preload 4 source blocks
        preload_block(16'h0000 + 0*16, 128'h6bc1bee22e409f96e93d7e117393172a);
        preload_block(16'h0000 + 1*16, 128'hae2d8a571e03ac9c9eb76fac45af8e51);
        preload_block(16'h0000 + 2*16, 128'h30c81c46a35ce411e5fbc1191a0a52ef);
        preload_block(16'h0000 + 3*16, 128'hf69f2445df4f9b17ad2b417be66c3710);

        program_and_go(0, 16'h6000, 4);
        poll_done;

        check(rd_data[2] === 0,                              "T5a: edge transfer (ends at 0xFFFFFFFF) is allowed");
        check(read_block(16'h6000) !== 128'h0, "T5a: DST written (transfer ran)");


        // ---- 5b: one block further would REUSE 0xFFFFFFFF -> must be REFUSED ----
        // ctr_count = 0xFFFFFFFD, 4 blocks -> 4th block would reuse FFFFFFFF.
        // (5a left ctr_overflow set; the IV write clears it and resets the counter.)
        write_iv(96'hf0f1f2f3f4f5f6f7f8f9fafb);
        axi4lite_wr_handshake(8'h0, 32'h0, 4'hf);  // CTRL: key1, encrypt

        force dut.u_axi4LiteRegister.ctr_count = 32'hFFFFFFFD;
        @(posedge clk); #1;
        release dut.u_axi4LiteRegister.ctr_count;

        program_and_go(0, 16'h7000, 4);
        poll_done;

        check(rd_data[2] === 1,                              "T5b: over-edge transfer (would reuse 0xFFFFFFFF) is refused");
        check(read_block(16'h7000) === 128'h0, "T5b: DST untouched on refusal");



        $display("-------------------------------");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $display("-------------------------------");
        $finish;

    end

endmodule

`default_nettype wire