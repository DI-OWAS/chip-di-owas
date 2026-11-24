`timescale 1ns / 1ps
`default_nettype none

module tb_axi4LiteRegs; 

    reg                 clk;
    reg                 rst;

    wire [1:0]          CTRL;
    reg [4:0]           STATUS;

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

    wire [127:0]        ctr_nonce;

    // register to capture result of read task
    reg [31:0]          rd_data;

    axi4LiteRegister dut (
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
        .ctr_count_inc  (1'b0),
        .dma_go_clr     (1'b0),
        .dma_busy       (1'b0),
        .dma_done       (1'b0),
        .dma_error      (1'b0)
    );
    
    // ----------------------------------------------------------------
    // Clock: 100 MHz (10 ns period)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;   

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

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
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
        STATUS          = 4'd0;
        pass_count      = 1'b0;
        fail_count      = 1'b0;
        
            


        // ---- Test 1: Reset clears all outputs ---------------------------
        wait_cycles(4);
        @(negedge clk); rst = 1'b0;   // release on falling edge to avoid race
        #1;                            // small delta so outputs settle

        check(CTRL === 2'b0, "T1: CTRL was resetted correctly");
        check(ctr_nonce === 128'b0, "T1: ctr_nonce was resetted correctly");

        

        // ---- Test 2: Write CTRL ------------------------------------------
        axi4lite_wr_handshake(8'h00, 32'h3, 4'hF);
        check(CTRL === 2'h3, "T2: Write to CTRL working correctly");



        // ---- Test 3: STATUS readable -------------------------------------
        STATUS = 5'b10101;
        axi4lite_rd_handshake(8'h04, rd_data);
        check(rd_data[4:0] === 5'b10101, "T3: Status is readable after write handshake");



        // ---- Test 4: Write CTR_NONCE -------------------------------------
        axi4lite_wr_handshake(8'h40, 32'hDEAD_BEEF, 4'hf);
        axi4lite_wr_handshake(8'h44, 32'hBADE_AFFE, 4'hf);
        axi4lite_wr_handshake(8'h48, 32'hCAFE_BABE, 4'hf);
        check(ctr_nonce === 128'hCAFE_BABE_BADE_AFFE_DEAD_BEEF_0000_0000, "T4: Write to ctr_nonce works correctly.");



        $display("-------------------------------");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $display("-------------------------------");
        $finish;

    end

endmodule

`default_nettype wire