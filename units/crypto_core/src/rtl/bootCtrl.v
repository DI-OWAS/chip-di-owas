module bootCtrl #
(
    parameter [31:0]  BOOT_SRC_ADDR = 32'h0,
    parameter [31:0]  BOOT_DST_ADDR = 32'h1000,
    parameter integer BOOT_N_BLOCKS = 8,
    // 0 = skip the boot sequence after reset (start directly in BOOT_DONE, no bus accesses)
    parameter         BOOT_ENABLE   = 1
) (
    input  wire        clk, rst,
    output reg         boot_active,
    output reg         boot_done,
    // drives the muxed cryptoDmaCtrl inputs
    output reg         boot_go,
    output reg [31:0]  boot_src, boot_dst, boot_blocks,
    // from cryptoDmaCtrl
    input  wire        dma_busy,
    input  wire        dma_done,
    input  wire        dma_error,   // unused this milestone; wire it for later

    // snoop the read data stream (observe only)
    input  wire [31:0] rd_tdata,
    input  wire        rd_tvalid,
    input  wire        rd_tready,
    // controls
    output reg         boot_bypass,
    output reg         boot_iv_load,
    output reg [95:0]  boot_iv_data,

    input  wire         status_done,          // FSM per-block completion pulse
    input  wire [127:0] cipher_out,           // FSM decrypted block
    output reg          read_only,            // → cryptoDmaCtrl
    output reg          boot_discard,         // → adapter discard_output
    output reg          boot_key1_wr_en,
    output reg          boot_key2_wr_en,
    output reg [127:0]  boot_key_wr_data


);


// localparams and state registers
localparam [3:0] B0_GO          = 4'd0;
localparam [3:0] B0_WAIT        = 4'd1;
localparam [3:0] B0_LOAD        = 4'd2;
localparam [3:0] B1_GO          = 4'd3;
localparam [3:0] B1_WAIT        = 4'd4;
localparam [3:0] B2_GO          = 4'd5;
localparam [3:0] B2_WAIT        = 4'd6;
localparam [3:0] BOOT_DONE      = 4'd7;

reg [3:0] state;
reg [3:0] next_state;


reg [127:0] boot_iv_reg;
reg [1:0]   iv_beat;

reg [3:0]   key_index;
reg sd_d;                       // status_done delayed one cycle

reg [3:0]   flush_cnt;


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state   <= BOOT_ENABLE ? B0_GO : BOOT_DONE;
        iv_beat <= 2'd0;
        key_index <= 4'd0;
        sd_d      <= 1'b0;
        flush_cnt <= 4'd0;
        boot_iv_reg <= 128'd0;
    end else begin
        state <= next_state;
        // capture the 4 beats of block 0 as the DMA reads them
        if ((state == B0_GO || state == B0_WAIT) && rd_tvalid && rd_tready) begin
            boot_iv_reg[iv_beat*32 +: 32] <= rd_tdata;   // low-word-first
            iv_beat <= iv_beat + 2'd1;
        end

        if (state == B2_GO || state == B2_WAIT) begin
            sd_d <= status_done;                 // becomes 1 the cycle AFTER a block finishes
            if (sd_d) key_index <= key_index + 1; // one increment per captured key
        end

        if (state == B2_WAIT && key_index == 4'd2) flush_cnt <= flush_cnt + 4'd1;
    end
end



//Combinational Block
always @(*) begin
    next_state    = state;   // default: stay in current state
    boot_active  = 1'b0;
    boot_go      = 1'b0;
    boot_done    = 1'b0;
    boot_bypass  = 1'b0;
    boot_iv_load = 1'b0;
    boot_iv_data = boot_iv_reg[127:32];       // top 96 bits = nonce
    boot_src     = BOOT_SRC_ADDR + 32'd16;    // B1 body defaults
    boot_dst     = BOOT_DST_ADDR;
    boot_blocks  = BOOT_N_BLOCKS - 3;
    read_only = 0;
    boot_discard = 0; 
    boot_key1_wr_en = 0; 
    boot_key2_wr_en = 0; 
    boot_key_wr_data = cipher_out;

    
    case (state)
        
        B0_GO : begin
            boot_active = 1'b1;
            boot_bypass = 1'b1;               // move the IV, don't decrypt it
            boot_go     = 1'b1;
            boot_src    = BOOT_SRC_ADDR;      // block 0 = the IV
            boot_dst    = BOOT_SRC_ADDR;      // identity copy (touches nothing else)
            boot_blocks = 32'd1;
            if (dma_busy) next_state = B0_WAIT;
        end

        B0_WAIT : begin
            boot_active = 1'b1;
            boot_bypass = 1'b1;               // hold stable — write desc issued during this state
            boot_src    = BOOT_SRC_ADDR;
            boot_dst    = BOOT_SRC_ADDR;
            boot_blocks = 32'd1;
            if (dma_done) next_state = B0_LOAD;
        end

        B0_LOAD : begin
            boot_active  = 1'b1;
            boot_iv_load = 1'b1;              // one-cycle pulse → axi4LiteRegs loads nonce, clears count
            next_state   = B1_GO;
        end

        B1_GO : begin
            boot_active = 1'b1;
            boot_go = 1'b1;

            if (dma_busy) begin
                next_state = B1_WAIT;
            end
        end

        B1_WAIT : begin
            boot_active = 1'b1;

            if (dma_done) begin
                next_state = B2_GO;
            end
        end

        B2_GO : begin
            boot_active = 1;
            boot_bypass = 0;
            read_only = 1;
            boot_discard = 1;
            boot_src = BOOT_SRC_ADDR + (BOOT_N_BLOCKS-2)*16;
            boot_blocks = 32'd2;

            boot_go = 1;
            if (dma_busy) begin
                next_state = B2_WAIT;
            end
        end

        B2_WAIT : begin
            boot_active = 1;
            boot_bypass = 0;
            read_only = 1;
            boot_discard = 1;
            boot_src = BOOT_SRC_ADDR + (BOOT_N_BLOCKS-2)*16;
            boot_blocks = 32'd2;

            boot_go = 0;
            
            if (sd_d && key_index == 4'd0) boot_key1_wr_en = 1'b1;  // first key → key1
            if (sd_d && key_index == 4'd1) boot_key2_wr_en = 1'b1;  // second key → key2

            if (key_index == 4'd2 && flush_cnt >= 4'd8) next_state = BOOT_DONE; // both captured
        end

        BOOT_DONE : begin
            boot_active = 1'b0;
            boot_done = 1'b1;
            boot_go = 1'b0;
        end
    endcase
end
    
endmodule