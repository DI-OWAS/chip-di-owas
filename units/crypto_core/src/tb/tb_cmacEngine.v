module tb_cmacEngine;
    reg             clk;
    reg             rst;

    // ---- control/data interface (testbench or higher-level FSM) ----
    reg             start;        // 1-cycle pulse: begin a new message
    reg     [127:0] key;          // AES key, held stable for the whole message
    reg     [127:0] block_in;     // current 128-bit message block
    reg             block_valid;  // block_in is presented
    reg             block_last;   // this is the final block of the message
    reg     [4:0]   block_nbytes; // valid bytes in the FINAL block, 0..16 (16=full)
    wire            block_ready;  // engine will consume a block this cycle
    wire    [127:0] tag;          // CMAC result
    wire            tag_valid;    // 1 when tag is valid (message complete)
    wire            busy;

    // Internal tb connections to AES
    wire [127:0] aes_key;
    wire [127:0] aes_dataIn;
    wire         aes_enable;
    wire [127:0] aes_dataOut;
    wire         aes_ready;
    wire         aes_valid;


    // Instantiate cmacEngine and AES128_Sec_0_Area_0
cmacEngine dut (
    .clk          (clk),
    .rst          (rst),

    // control/data interface (driven by the TB)
    .start        (start),
    .key          (key),
    .block_in     (block_in),
    .block_valid  (block_valid),
    .block_last   (block_last),
    .block_nbytes (block_nbytes),
    .block_ready  (block_ready),
    .tag          (tag),
    .tag_valid    (tag_valid),
    .busy         (busy),

    // AES primitive interface (these wires go to the AES instance, NOT the TB)
    .io_key       (aes_key),
    .io_dataIn    (aes_dataIn),
    .fsm_enable   (aes_enable),
    .io_dataOut   (aes_dataOut),
    .fsm_ready    (aes_ready),
    .fsm_valid    (aes_valid)
);

AES128_Sec_0_Area_0 aes (
    .control_clk   (clk),
    .control_reset (rst),
    .io_key        (aes_key),
    .io_dataIn     (aes_dataIn),
    .io_dataOut    (aes_dataOut),
    .fsm_enable    (aes_enable),
    .fsm_ready     (aes_ready),
    .fsm_valid     (aes_valid)
);


    // ----------------------------------------------------------------
    // Clock: 100 MHz (10 ns period)
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer timeout_ctr;
    integer end_loop;


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


    task do_reset;
        begin
            rst = 1;
            wait_cycles(4);
            @(negedge clk); rst = 1'b0;
            #1;
        end
    endtask


    task feed_block;
        input [127:0] data;
        input         last;
        input [4:0]   nbytes;
        begin
            @(negedge clk);
            while (block_ready !== 1'b1) @(negedge clk);   // wait for ABSORB_EN
            block_in = data; block_valid = 1'b1; block_last = last; block_nbytes = nbytes;
            @(posedge clk);                                 // consumed here
            @(negedge clk); block_valid = 1'b0;
        end
    endtask


    task pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);   // start is high across exactly one posedge
            start = 1'b0;
        end
    endtask


    task wait_tag;
        integer t;
        begin
            t = 0;
            while (tag_valid !== 1'b1) begin
                @(negedge clk);
                t = t + 1;
                if (t > 5000) begin
                    $display("[TIMEOUT] tag_valid never asserted");
                    $finish;
                end
            end
        end
    endtask


    task check_tag;
        input [127:0] got;
        input [127:0] expected;
        input [8*8:1] name;    // short string label
        begin
            if (got === expected) begin
                $display("[PASS] %0s tag=%032h", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s got=%032h exp=%032h", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask


    initial begin
      #200000;                                  // 200,000 ns = 200 us
        $display("==== [TIMEOUT] global watchdog fired at %0t ====", $time);
        $display("==== partial results: PASS=%0d FAIL=%0d ====", pass_count, fail_count);
        $finish;
    end



    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0; 
        fail_count = 0;
        start=0; 
        block_valid=0; 
        block_in=0; 
        block_last=0; 
        block_nbytes=0; 
        key=0; 
        

        do_reset;

        // Negative self-test: two different values must compare unequal
        check((128'hdeadbeef_deadbeef_deadbeef_deadbeef !==
            128'h070a16b4_6b4d4144_f79bdd9d_d04a287c),
            "negative: mismatch is detected");

        // Check subkey generation
        key = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;


        // ---------- Vector: len = 16 (also verify subkeys, once) ----------
        pulse_start;
        @(negedge clk);
        while (block_ready !== 1'b1) @(negedge clk);            // subkey phase complete
        check((dut.L  === 128'h7df76b0c_1ab899b3_3e42f047_b91b546f), "subkey L");
        check((dut.K1 === 128'hfbeed618_35713366_7c85e08f_7236a8de), "subkey K1");
        check((dut.K2 === 128'hf7ddac30_6ae266cc_f90bc11e_e46d513b), "subkey K2");
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b1, 5'd16);
        wait_tag;
        check_tag(tag, 128'h070a16b4_6b4d4144_f79bdd9d_d04a287c, "len16");

        // ---------- Vector: len = 0 (empty) ----------
        pulse_start;
        feed_block(128'h0, 1'b1, 5'd0);                         // engine builds 0x80 00..
        wait_tag;
        check_tag(tag, 128'hbb1d6929_e9593728_7fa37d12_9b756746, "len0");

        // ---------- Vector: len = 40 (2 full + 1 partial of 8 bytes) ----------
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b0, 5'd16);
        feed_block(128'hae2d8a57_1e03ac9c_9eb76fac_45af8e51, 1'b0, 5'd16);
        feed_block(128'h30c81c46_a35ce411_00000000_00000000, 1'b1, 5'd8);
        wait_tag;
        check_tag(tag, 128'hdfa66747_de9ae630_30ca3261_1497c827, "len40");

        // ---------- Vector: len = 64 (4 full blocks) ----------
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b0, 5'd16);
        feed_block(128'hae2d8a57_1e03ac9c_9eb76fac_45af8e51, 1'b0, 5'd16);
        feed_block(128'h30c81c46_a35ce411_e5fbc119_1a0a52ef, 1'b0, 5'd16);
        feed_block(128'hf69f2445_df4f9b17_ad2b417b_e66c3710, 1'b1, 5'd16);
        wait_tag;
        check_tag(tag, 128'h51f0bebf_7e3b9d92_fc497417_79363cfe, "len64");


        // ---------- len = 1 (single partial byte, nbytes=1) ----------
        pulse_start;
        feed_block(128'h6b000000_00000000_00000000_00000000, 1'b1, 5'd1);
        wait_tag;
        check_tag(tag, 128'h8e48c3c1_d9f1c17c_295c7aef_d232bb14, "len1");

        // ---------- len = 15 (almost-full final block, nbytes=15) ----------
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_73931700, 1'b1, 5'd15);
        wait_tag;
        check_tag(tag, 128'hf212d4c2_154c8766_de60c18c_98fa0c93, "len15");

        // ---------- len = 20 (1 full block + 4-byte partial) ----------
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b0, 5'd16);
        feed_block(128'hae2d8a57_00000000_00000000_00000000, 1'b1, 5'd4);
        wait_tag;
        check_tag(tag, 128'h7d85449e_a6ea19c8_23a7bf78_837dfade, "len20");

        // ---------- len = 31 (1 full block + 15-byte partial) ----------
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b0, 5'd16);
        feed_block(128'hae2d8a57_1e03ac9c_9eb76fac_45af8e00, 1'b1, 5'd15);
        wait_tag;
        check_tag(tag, 128'h8a157acf_f517d21b_cd6ab65c_d014cc70, "len31");


        // ---------- Summary ----------
        $display("==== CMAC TB done: PASS=%0d FAIL=%0d ====", pass_count, fail_count);
        $finish;

    end
endmodule