module tb_ccmEngine;
    reg clk;
    reg rst;

    reg         start;
    reg         decrypt;
    reg [127:0] key;
    reg [103:0] nonce;        // 13 bytes  (NOT reg nonce[103:0] — that's a memory!)
    reg [15:0]  payload_len;  // 2 bytes
    reg [127:0] tag_in;
    reg [127:0] block_in;
    reg         block_valid;
    reg         block_last;
    reg [4:0]   block_nbytes;
    reg         out_ready;

    wire         block_ready;
    wire [127:0] out_data;
    wire         out_valid;
    wire [4:0]   out_nbytes;
    wire [127:0] tag_out;
    wire         tag_valid;
    wire         auth_ok;
    wire         busy;

    wire [127:0] aes_key;
    wire [127:0] aes_dataIn;
    wire         aes_enable;
    wire [127:0] aes_dataOut;
    wire         aes_ready;
    wire         aes_valid;



    ccmEngine #(.Q(2)) dut (
        .clk          (clk),
        .rst          (rst),

        .start        (start),
        .decrypt      (decrypt),
        .key          (key),
        .nonce        (nonce),
        .payload_len  (payload_len),
        .tag_in       (tag_in),

        .block_in     (block_in),
        .block_valid  (block_valid),
        .block_last   (block_last),
        .block_nbytes (block_nbytes),
        .block_ready  (block_ready),

        .out_data     (out_data),
        .out_valid    (out_valid),
        .out_nbytes   (out_nbytes),
        .out_ready    (out_ready),

        .tag_out      (tag_out),
        .tag_valid    (tag_valid),
        .auth_ok      (auth_ok),
        .busy         (busy),

        // AES-facing group → the shared wires to the AES instance
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


    function [127:0] mask_bytes;
        input [127:0] d; input [4:0] nb; integer i;
        begin
            mask_bytes = 128'b0;
            for (i = 0; i < 16; i = i + 1)
                if (i < nb) mask_bytes[127 - 8*i -: 8] = d[127 - 8*i -: 8];
        end
    endfunction


    task capture_out;
        input [127:0] expected; input [4:0] nb; input [8*10:1] name;
        begin
            @(negedge clk);
            while (out_valid !== 1'b1) @(negedge clk);   // wait for EMIT
            check(mask_bytes(out_data,nb) === mask_bytes(expected,nb), name);
            out_ready = 1'b1;                            // accept
            @(posedge clk);                              // consume (valid & ready)
            @(negedge clk); out_ready = 1'b0;
        end
    endtask


    task wait_done;
        integer t;
        begin
            t = 0;
            while (tag_valid !== 1'b1) begin
                @(negedge clk); t = t + 1;
                if (t > 20000) begin $display("[TIMEOUT] tag_valid never asserted"); $finish; end
            end
        end
    endtask


    task drain_out;   // accept one output block without checking it
        begin
            @(negedge clk);
            while (out_valid !== 1'b1) @(negedge clk);
            out_ready = 1'b1; @(posedge clk);
            @(negedge clk); out_ready = 1'b0;
        end
    endtask


    initial begin
        #1000000;
        $display("[TIMEOUT] global watchdog  PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end

    initial clk = 1'b0;
    always #5 clk = ~clk;



    initial begin
    // ---- init ----
    pass_count=0; fail_count=0;
    start=0; decrypt=0; key=0; nonce=0; payload_len=0; tag_in=0;
    block_in=0; block_valid=0; block_last=0; block_nbytes=0; out_ready=0;

    do_reset;

    key   = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
    nonce = 104'h00112233445566778899aabbcc;

    // ---- negative self-test (checker bites) ----
    check(128'h1 !== 128'h0, "selftest inequality");

    // ================= ENCRYPT =================
    // len 0 (empty payload)
    decrypt=0; payload_len=16'd0;
    pulse_start; wait_done;
    check(tag_out === 128'h7b0ab239_056afc23_70c60c26_9739d22d, "enc0 tag");

    // len 16
    decrypt=0; payload_len=16'd16;
    pulse_start;
    feed_block  (128'h20212223_24252627_28292a2b_2c2d2e2f, 1'b1, 5'd16);
    capture_out (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 5'd16, "enc16 C0");
    wait_done;
    check(tag_out === 128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e0, "enc16 tag");

    // len 20 (full + 4-byte partial)
    decrypt=0; payload_len=16'd20;
    pulse_start;
    feed_block  (128'h20212223_24252627_28292a2b_2c2d2e2f, 1'b0, 5'd16);
    capture_out (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 5'd16, "enc20 C0");
    feed_block  (128'h30313233_00000000_00000000_00000000, 1'b1, 5'd4);
    capture_out (128'h0cbe8409_00000000_00000000_00000000, 5'd4,  "enc20 C1");
    wait_done;
    check(tag_out === 128'hd75e527f_55e83085_9597fee8_14fcfa9a, "enc20 tag");

    // len 40 (2 full + 8-byte partial)
    decrypt=0; payload_len=16'd40;
    pulse_start;
    feed_block  (128'h20212223_24252627_28292a2b_2c2d2e2f, 1'b0, 5'd16);
    capture_out (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 5'd16, "enc40 C0");
    feed_block  (128'h30313233_34353637_38393a3b_3c3d3e3f, 1'b0, 5'd16);
    capture_out (128'h0cbe8409_c84f6e92_36b7f62b_0721c1d1, 5'd16, "enc40 C1");
    feed_block  (128'h40414243_44454647_00000000_00000000, 1'b1, 5'd8);
    capture_out (128'h4ec325be_351cedb9_00000000_00000000, 5'd8,  "enc40 C2");
    wait_done;
    check(tag_out === 128'hf74938bf_b02ba438_bdba5bb7_da6aa972, "enc40 tag");

    // ================= DECRYPT (feed C, capture P, tag_in=U) =================
    // len 0
    decrypt=1; payload_len=16'd0; tag_in=128'h7b0ab239_056afc23_70c60c26_9739d22d;
    pulse_start; wait_done;
    check(auth_ok === 1'b1, "dec0 auth_ok");

    // len 16
    decrypt=1; payload_len=16'd16; tag_in=128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e0;
    pulse_start;
    feed_block  (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 1'b1, 5'd16);
    capture_out (128'h20212223_24252627_28292a2b_2c2d2e2f, 5'd16, "dec16 P0");
    wait_done;
    check(auth_ok === 1'b1, "dec16 auth_ok");

    // len 40
    decrypt=1; payload_len=16'd40; tag_in=128'hf74938bf_b02ba438_bdba5bb7_da6aa972;
    pulse_start;
    feed_block  (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 1'b0, 5'd16);
    capture_out (128'h20212223_24252627_28292a2b_2c2d2e2f, 5'd16, "dec40 P0");
    feed_block  (128'h0cbe8409_c84f6e92_36b7f62b_0721c1d1, 1'b0, 5'd16);
    capture_out (128'h30313233_34353637_38393a3b_3c3d3e3f, 5'd16, "dec40 P1");
    feed_block  (128'h4ec325be_351cedb9_00000000_00000000, 1'b1, 5'd8);
    capture_out (128'h40414243_44454647_00000000_00000000, 5'd8,  "dec40 P2");
    wait_done;
    check(auth_ok === 1'b1, "dec40 auth_ok");

    // ================= NEGATIVE (corrupt tag → auth_ok=0) =================
    decrypt=1; payload_len=16'd16; tag_in=128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e1; // last nibble flipped
    pulse_start;
    feed_block  (128'h712ef053_5b0956aa_cab44659_6a4cf70a, 1'b1, 5'd16);
    capture_out (128'h20212223_24252627_28292a2b_2c2d2e2f, 5'd16, "neg P0"); // plaintext still correct
    wait_done;
    check(auth_ok === 1'b0, "neg auth_ok=0");


    // tampered ciphertext (flip 1 bit of C0), correct tag → must reject
    decrypt=1; payload_len=16'd16; tag_in=128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e0;
    pulse_start;
    feed_block(128'h712ef053_5b0956aa_cab44659_6a4cf70b, 1'b1, 5'd16); // ...0a → ...0b
    drain_out;
    wait_done;
    check(auth_ok === 1'b0, "tamper-ct auth_ok=0");


    // len 1
    decrypt=0; payload_len=16'd1; pulse_start;
    feed_block (128'h20000000_00000000_00000000_00000000, 1'b1, 5'd1);
    capture_out(128'h71000000_00000000_00000000_00000000, 5'd1, "enc1 C0");
    wait_done;
    check(tag_out === 128'h9b22fe19_319a781d_24d1856c_e4f2298b, "enc1 tag");

    // len 15
    decrypt=0; payload_len=16'd15; pulse_start;
    feed_block (128'h20212223_24252627_28292a2b_2c2d2e00, 1'b1, 5'd15);
    capture_out(128'h712ef053_5b0956aa_cab44659_6a4cf700, 5'd15, "enc15 C0");
    wait_done;
    check(tag_out === 128'haaf97e06_55b54347_a9e717c7_fe70800e, "enc15 tag");


    $display("==== CCM TB done: PASS=%0d FAIL=%0d ====", pass_count, fail_count);
    $finish;
end
endmodule