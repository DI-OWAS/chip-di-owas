`timescale 1ns / 1ps
`default_nettype none

module tb_cryptoCoreFSM; 
    reg              clk;
    reg              rst;
    //inputs from axi4LiteRegs module
    reg              ctrl_start;
    reg              ctrl_key_sel;
    reg [127:0]      cipher_in;
    reg [127:0]      ctr_nonce;
    //inputs from key_storage
    reg [127:0]      key_out;
    reg              key1_valid;
    reg              key2_valid;
    //inputs from AES engine
    reg              fsm_ready;
    reg              fsm_valid;
    reg [127:0]      io_dataOut;
    //outputs from axi4LiteRegs module
    wire              status_busy;
    wire              status_done;
    wire [127:0]      cipher_out;
    //outputs to AES engine
    wire [127:0]      io_key;
    wire [127:0]      io_dataIn;
    wire              fsm_enable;
    //output to keyStorage
    wire              key_sel;
    wire              key1_wr_en;
    wire [127:0]      key1_wr_data;
    wire              key2_wr_en;
    wire [127:0]      key2_wr_data;
    reg               ctr_overflow;
    wire              ctr_count_inc;

    cryptoCoreFSM dut(
        .clk            (clk),
        .rst            (rst),
        .ctrl_start     (ctrl_start),
        .ctrl_key_sel   (ctrl_key_sel),
        .cipher_in      (cipher_in),
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
        .io_key         (io_key),
        .io_dataIn      (io_dataIn),
        .fsm_enable     (fsm_enable),
        .key_sel        (key_sel),
        .key1_wr_en     (key1_wr_en),
        .key1_wr_data   (key1_wr_data),
        .key2_wr_en     (key2_wr_en),
        .key2_wr_data   (key2_wr_data),
        .ctr_overflow   (ctr_overflow),
        .ctr_count_inc  (ctr_count_inc)
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

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        // Initialise all inputs to safe defaults
        rst             = 1'b1;
        ctrl_start      = 1'b0;
        ctrl_key_sel    = 1'b0;
        cipher_in       = 128'd0;
        ctr_nonce       = 128'd0;
        key_out         = 128'd0;
        key1_valid      = 1'b0;
        key2_valid      = 1'b0;
        fsm_ready       = 1'b0;
        fsm_valid       = 1'b0;
        io_dataOut      = 128'b0;
        pass_count      = 0;
        fail_count      = 0;
        ctr_overflow    = 1'b0;
    


    // ---- Test 1: Reset clears all outputs -----------------------
    rst = 1'b1;
    wait_cycles(4);
    @(negedge clk); rst = 1'b0;   // release on falling edge to avoid race
    #1;                            // small delta so outputs settle

    check(status_busy  === 1'b0,  "T1: status_busy=0 after reset");
    check(status_done === 1'b0,  "T1: status_done=0 after reset");
    check(fsm_enable === 1'b0, "T1: fsm_enable=0 after reset");
    


    // ---- Test 2: ctrl_start with no valid key stays in IDLE -----------------------
    fsm_ready = 1'b1;
    ctrl_start = 1'b1;
    @(posedge clk); #1;
    
    check(fsm_enable === 1'b0, "T2: FSM did not leave IDLE");
    


    // ---- Test 3: Full run: IDLE → ENABLE → WAIT → DONE → IDLE -----------------------
    cipher_in  = 128'hAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA;
    io_dataOut = 128'hBBBBBBBB_BBBBBBBB_BBBBBBBB_BBBBBBBB;

    key1_valid = 1; ctrl_key_sel = 0; ctrl_start = 1;

    @(posedge clk); #1;
    check(fsm_enable === 1'b1 && status_busy === 1'b1, "T3: ENABLE state is reached after one clk cycle");
    @(negedge clk); ctrl_start = 1'b0;

    @(posedge clk); #1;
    check(status_busy === 1'b1 && fsm_enable === 1'b0, "T3: WAIT state is reached correctly");
    fsm_valid = 1'b1;

    @(posedge clk); #1;
    check(status_done === 1'b1 && cipher_out === io_dataOut ^ cipher_in, "T3: DONE state is reached correctly");
    fsm_valid = 1'b0;

    check(status_done === 1'b1, "T3: DONE state");
    @(posedge clk); #1;
    check(status_done === 1'b0 && status_busy === 1'b0, "T3: back to IDLE");
    check(cipher_out === (io_dataOut ^ cipher_in), "T3: cipher_out correct");


    // ---- Test 4: key_sel=1 with key2_valid=0 stays in IDLE -----------------------
    ctrl_key_sel = 1'b1; 
    key2_valid = 1'b0; 
    key1_valid = 1'b1;
    ctrl_start = 1'b1;
    fsm_ready = 1'b1;
    @(posedge clk); #1;
    check(fsm_enable === 1'b0, "T4: selecting invalid key leads to idle state");
    


    // ---- Test 5: key_sel=1 with key2_valid=1 runs successfully -----------------------#
    cipher_in  = 128'hAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA;
    io_dataOut = 128'hBBBBBBBB_BBBBBBBB_BBBBBBBB_BBBBBBBB;

    key2_valid = 1; ctrl_key_sel = 1; ctrl_start = 1;

    @(posedge clk); #1;
    check(fsm_enable === 1'b1 && status_busy === 1'b1, "T5: ENABLE state is reached after one clk cycle");
    



    $display("-------------------------------");
    $display("Results: %0d passed, %0d failed", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED");
    else                 $display("SOME TESTS FAILED");
    $display("-------------------------------");
    $finish;

    end

endmodule

`default_nettype wire