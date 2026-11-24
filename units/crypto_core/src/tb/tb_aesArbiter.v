module tb_aesArbiter;
    reg clk, rst;

    // control
    reg [1:0]   mode;
    reg         boot_active;
    reg         start;

    // shared feed + key
    reg [127:0] key;
    reg [127:0] block_in;
    reg         block_valid;
    reg         block_last;
    reg [4:0]   block_nbytes;

    // ccm-only inputs
    reg         decrypt;
    reg [103:0] nonce;
    reg [15:0]  payload_len;
    reg [127:0] tag_in;
    reg         out_ready;

    // arbiter <-> AES
    wire [127:0] aes_key, aes_din;
    wire         aes_en;
    wire [127:0] aes_dataOut;
    wire         aes_ready, aes_valid;

    // engine AES-facing outputs (into the arbiter)
    wire [127:0] cmac_key, cmac_din;  wire cmac_en;
    wire [127:0] ccm_key,  ccm_din;   wire ccm_en;

    // engine control outputs
    wire         cm_block_ready;
    wire [127:0] cm_tag;      wire cm_tag_valid;  wire cm_busy;

    wire         cc_block_ready;
    wire [127:0] cc_out_data; wire cc_out_valid;  wire [4:0] cc_out_nbytes;
    wire [127:0] cc_tag_out;  wire cc_tag_valid;  wire cc_auth_ok; wire cc_busy;

    integer pass_count, fail_count;

    reg  [127:0] cipher_in, ctr_nonce, boot_kek;
    wire [127:0] ctr_key, ctr_din;   wire ctr_en;
    wire [127:0] ctr_cipher_out;     wire ctr_busy, ctr_done;

    wire use_ctr        = boot_active | (mode == 2'd0);   // = arbiter's eff_mode==CTR
    wire ctr_ctrl_start = start &  use_ctr;
    wire cm_start       = start & (mode==2'd1) & ~boot_active;
    wire cc_start       = start & (mode==2'd2) & ~boot_active;
    wire block_ready_sel= (mode==2'd2) ? cc_block_ready : cm_block_ready;
    wire done_sel       = use_ctr ? ctr_done :
                        (mode==2'd2) ? cc_tag_valid : cm_tag_valid;

    // ---------------- DUTs ----------------
    cryptoCoreFSM u_ctr (
        .clk(clk), .rst(rst),
        .ctrl_start(ctr_ctrl_start), .ctrl_key_sel(1'b0),
        .cipher_in(cipher_in), .ctr_nonce(ctr_nonce),
        .key_out(key), .key1_valid(1'b1), .key2_valid(1'b0),
        .boot_active(boot_active), .boot_kek(boot_kek),
        .fsm_ready(aes_ready), .fsm_valid(aes_valid), .io_dataOut(aes_dataOut),
        .status_busy(ctr_busy), .status_done(ctr_done), .cipher_out(ctr_cipher_out),
        .io_key(ctr_key), .io_dataIn(ctr_din), .fsm_enable(ctr_en),
        .key_sel(), .key1_wr_en(), .key1_wr_data(), .key2_wr_en(), .key2_wr_data(),
        .ctr_overflow(1'b0), .ctr_count_inc(), .boot_done(1'b1)
    );

    aesArbiter u_arb (
        .mode(mode), .boot_active(boot_active),
        .ctr_key(ctr_key), .ctr_din(ctr_din), .ctr_en(ctr_en),  // no CTR master in this TB
        .cmac_key(cmac_key), .cmac_din(cmac_din), .cmac_en(cmac_en),
        .ccm_key (ccm_key),  .ccm_din (ccm_din),  .ccm_en (ccm_en),
        .aes_key(aes_key), .aes_din(aes_din), .aes_en(aes_en)
    );

    AES128_Sec_0_Area_0 aes (
        .control_clk(clk), .control_reset(rst),
        .io_key(aes_key), .io_dataIn(aes_din), .io_dataOut(aes_dataOut),
        .fsm_enable(aes_en), .fsm_ready(aes_ready), .fsm_valid(aes_valid)
    );

    cmacEngine u_cmac (
        .clk(clk), .rst(rst),
        .start(cm_start), .key(key),
        .block_in(block_in), .block_valid(block_valid),
        .block_last(block_last), .block_nbytes(block_nbytes),
        .block_ready(cm_block_ready),
        .tag(cm_tag), .tag_valid(cm_tag_valid), .busy(cm_busy),
        .io_key(cmac_key), .io_dataIn(cmac_din), .fsm_enable(cmac_en),
        .io_dataOut(aes_dataOut), .fsm_ready(aes_ready), .fsm_valid(aes_valid)
    );

    ccmEngine #(.Q(2)) u_ccm (
        .clk(clk), .rst(rst),
        .start(cc_start), .decrypt(decrypt), .key(key), .nonce(nonce),
        .payload_len(payload_len), .tag_in(tag_in),
        .block_in(block_in), .block_valid(block_valid),
        .block_last(block_last), .block_nbytes(block_nbytes),
        .block_ready(cc_block_ready),
        .out_data(cc_out_data), .out_valid(cc_out_valid),
        .out_nbytes(cc_out_nbytes), .out_ready(out_ready),
        .tag_out(cc_tag_out), .tag_valid(cc_tag_valid),
        .auth_ok(cc_auth_ok), .busy(cc_busy),
        .io_key(ccm_key), .io_dataIn(ccm_din), .fsm_enable(ccm_en),
        .io_dataOut(aes_dataOut), .fsm_ready(aes_ready), .fsm_valid(aes_valid)
    );

    // ---------------- clock / watchdog ----------------
    initial clk = 1'b0;
    always #5 clk = ~clk;
    initial begin
        #500000;
        $display("[TIMEOUT] watchdog  PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end

    // ---------------- tasks ----------------
    task check;
        input condition; input [1023:0] name;
        begin
            if (condition) begin $display("PASS: %s", name); pass_count=pass_count+1; end
            else begin $display("FAIL: %s (t=%0t)", name, $time); fail_count=fail_count+1; end
        end
    endtask

    task do_reset;
        integer i;
        begin
            rst = 1;
            repeat (4) @(negedge clk);
            rst = 0; @(negedge clk);
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
        end
    endtask

    task feed_block;                       // uses the mode-selected block_ready
        input [127:0] data; input last; input [4:0] nb;
        begin
            @(negedge clk);
            while (block_ready_sel !== 1'b1) @(negedge clk);
            block_in=data; block_valid=1'b1; block_last=last; block_nbytes=nb;
            @(posedge clk);
            @(negedge clk); block_valid=1'b0;
        end
    endtask

    function [127:0] mask_bytes;
        input [127:0] d; input [4:0] nb; integer i;
        begin
            mask_bytes = 128'b0;
            for (i=0;i<16;i=i+1) if (i<nb) mask_bytes[127-8*i -: 8] = d[127-8*i -: 8];
        end
    endfunction

    task capture_out;                      // CCM output stream
        input [127:0] expected; input [4:0] nb; input [8*12:1] name;
        begin
            @(negedge clk);
            while (cc_out_valid !== 1'b1) @(negedge clk);
            check(mask_bytes(cc_out_data,nb) === mask_bytes(expected,nb), name);
            out_ready=1'b1; @(posedge clk);
            @(negedge clk); out_ready=1'b0;
        end
    endtask

    task wait_done;
        integer t;
        begin
            t=0;
            while (done_sel !== 1'b1) begin
                @(negedge clk); t=t+1;
                if (t>20000) begin $display("[TIMEOUT] done"); $finish; end
            end
        end
    endtask

    task run_ctr;
        input [127:0] nonce_val, pt, expected; input [8*20:1] name;
        begin
            ctr_nonce = nonce_val; cipher_in = pt;
            pulse_start;
            wait_done;                       // done_sel → ctr_done
            @(posedge clk); @(negedge clk);  // cipher_out is registered 1 cycle AFTER status_done
            check(ctr_cipher_out === expected, name);
        end
    endtask


    // ---------------- stimulus ----------------
    initial begin
        pass_count=0; fail_count=0;
        mode=0; boot_active=0; start=0; key=0;
        block_in=0; block_valid=0; block_last=0; block_nbytes=0;
        decrypt=0; nonce=0; payload_len=0; tag_in=0; out_ready=0;
        boot_kek=0;

        do_reset;
        key = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;

        // 1) CTR — the default mode
        mode=2'd0; boot_active=0;
        run_ctr(128'h00010203_04050607_08090a0b_0c0d0e0f,
                128'h11111111_22222222_33333333_44444444,
                128'h41ef76dd_bb4f1094_e93a04da_dfeba824, "CTR via arbiter");
        check((cm_busy===1'b0)&&(cc_busy===1'b0), "engines idle during CTR");

        // 2) CMAC   (your existing block)
        mode=2'd1;
        pulse_start;
        feed_block(128'h6bc1bee2_2e409f96_e93d7e11_7393172a, 1'b1, 5'd16);
        wait_done;
        check(cm_tag === 128'h070a16b4_6b4d4144_f79bdd9d_d04a287c, "CMAC len16 via arbiter");
        check(cc_busy===1'b0, "CCM idle during CMAC");

        // 3) CCM    (your existing block)
        mode=2'd2; decrypt=0; nonce=104'h00112233445566778899aabbcc; payload_len=16'd16;
        pulse_start;
        feed_block (128'h20212223_24252627_28292a2b_2c2d2e2f, 1'b1, 5'd16);
        capture_out(128'h712ef053_5b0956aa_cab44659_6a4cf70a, 5'd16, "CCM16 C0 via arb");
        wait_done;
        check(cc_tag_out === 128'h4918ab9a_e37c7739_d4a9e14a_28a9c6e0, "CCM len16 tag via arbiter");
        check(cm_busy===1'b0, "CMAC idle during CCM");

        // 4) boot forces CTR even though mode says CMAC
        mode=2'd1; boot_active=1; boot_kek=128'hf00ff209_847506cc_080c0a0b_00110eaf;
        run_ctr(128'h00010203_04050607_08090a0b_0c0d0e0f,
                128'h11111111_22222222_33333333_44444444,
                128'h2d75eb9a_5848dcf9_0843880d_77539590, "boot forces CTR (mode=CMAC)");
        check((cm_busy===1'b0)&&(cc_busy===1'b0), "engines idle during boot");
        boot_active=0;

        // 5) back to CTR after all the switching — must still work (no state leak)
        mode=2'd0;
        run_ctr(128'h00010203_04050607_08090a0b_0c0d0e0f,
                128'h11111111_22222222_33333333_44444444,
                128'h41ef76dd_bb4f1094_e93a04da_dfeba824, "CTR again after switches");

        $display("==== arbiter TB done: PASS=%0d FAIL=%0d ====", pass_count, fail_count);
        $finish;

    end
endmodule
