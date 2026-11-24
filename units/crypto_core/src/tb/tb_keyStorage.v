`timescale 1ns / 1ps
`default_nettype none

module tb_keyStorage;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg          clk;
    reg          rst;

    reg          key1_wr_en;
    reg  [127:0] key1_wr_data;
    reg          key2_wr_en;
    reg  [127:0] key2_wr_data;

    reg          key_sel;
    wire [127:0] key_out;
    wire         key1_valid;
    wire         key2_valid;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    keyStorage dut (
        .clk         (clk),
        .rst         (rst),
        .key1_wr_en  (key1_wr_en),
        .key1_wr_data(key1_wr_data),
        .key2_wr_en  (key2_wr_en),
        .key2_wr_data(key2_wr_data),
        .key_sel     (key_sel),
        .key_out     (key_out),
        .key1_valid  (key1_valid),
        .key2_valid  (key2_valid)
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
        input [255:0] test_name;
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
        rst          = 1'b1;
        key1_wr_en   = 1'b0;
        key1_wr_data = 128'b0;
        key2_wr_en   = 1'b0;
        key2_wr_data = 128'b0;
        key_sel      = 1'b0;
        pass_count   = 0;
        fail_count   = 0;

        // ---- Test 1: Reset clears everything -----------------------
        // Hold reset for 4 cycles then release
        wait_cycles(4);
        @(negedge clk); rst = 1'b0;   // release on falling edge to avoid race
        #1;                            // small delta so outputs settle

        check(key1_valid  === 1'b0,  "T1: key1_valid=0 after reset");
        check(key2_valid  === 1'b0,  "T1: key2_valid=0 after reset");
        check(key_out     === 128'b0, "T1: key_out=0 after reset");

        // ---- Test 2: Write Key1, Key2 unaffected -------------------
        @(negedge clk);
        key1_wr_en   = 1'b1;
        key1_wr_data = 128'hDEADBEEF_CAFEBABE_01234567_89ABCDEF;
        @(posedge clk); #1;            // let the register latch
        key1_wr_en   = 1'b0;

        check(key1_valid  === 1'b1,   "T2: key1_valid=1 after write");
        check(key2_valid  === 1'b0,   "T2: key2_valid unchanged");
        check(key_out     === 128'hDEADBEEF_CAFEBABE_01234567_89ABCDEF,
                                      "T2: key_out=Key1 when key_sel=0");

        // ---- Test 3: Write Key2, Key1 unaffected -------------------
        @(negedge clk);
        key2_wr_en   = 1'b1;
        key2_wr_data = 128'hFEEDFACE_C0FFEE00_AABBCCDD_EEFF0011;
        @(posedge clk); #1;
        key2_wr_en   = 1'b0;

        check(key2_valid  === 1'b1,   "T3: key2_valid=1 after write");
        check(key1_valid  === 1'b1,   "T3: key1_valid still 1");

        // ---- Test 4: key_sel mux -----------------------------------
        key_sel = 1'b1; #1;
        check(key_out === 128'hFEEDFACE_C0FFEE00_AABBCCDD_EEFF0011,
                                      "T4: key_out=Key2 when key_sel=1");
        key_sel = 1'b0; #1;
        check(key_out === 128'hDEADBEEF_CAFEBABE_01234567_89ABCDEF,
                                      "T4: key_out=Key1 when key_sel=0");

        // ---- Test 5: Async reset clears keys mid-operation ---------
        // Assert rst without waiting for a clock edge —
        // async reset must take effect immediately (no clock needed).
        rst = 1'b1;
        #1;   // one nanosecond — still no clock edge
        check(key1_valid  === 1'b0,   "T5: async rst: key1_valid clears immediately");
        check(key2_valid  === 1'b0,   "T5: async rst: key2_valid clears immediately");
        check(key_out     === 128'b0, "T5: async rst: key_out clears immediately");

        // Release reset and verify the module is functional again
        #2; rst = 1'b0;
        @(negedge clk);
        key1_wr_en   = 1'b1;
        key1_wr_data = 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
        @(posedge clk); #1;
        key1_wr_en   = 1'b0;
        check(key1_valid  === 1'b1,   "T5: functional after reset release");

        // ---- Summary -----------------------------------------------
        $display("-------------------------------");
        $display("Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("-------------------------------");
        $finish;
    end

endmodule

`default_nettype wire
