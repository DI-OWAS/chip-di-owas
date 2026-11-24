module aesStreamAdapter #
(
    parameter DATA_WIDTH = 32,
    parameter BEATS = (128 / DATA_WIDTH) 
)
(
    input wire clk, 
    input wire rst,
    
    // AXIS in (from axi_dma read stream)
    input wire [DATA_WIDTH-1:0] in_tdata,   
    input wire in_tvalid,  
    output reg in_tready,
    input wire in_tlast,

    // AXIS out (to axi_dma write stream)
    output reg [DATA_WIDTH-1:0] out_tdata,  
    output reg out_tvalid, 
    input wire out_tready,
    output reg out_tlast,
    
    // to/from cryptoCoreFSM
    output reg [127:0] cipher_in,
    output reg start,
    input wire [127:0] cipher_out,
    input wire status_busy,
    input wire status_done,

    
    // skips crypto when activated (only moving data) 
    input wire  bypass,

    input wire discard_output,

    input  wire [1:0]   mode,          // 0=CTR, 1=CMAC, 2=CCM  (pass eff_mode from cryptoCore)
    output reg  [127:0] block_in,
    output reg          block_valid,
    output reg          block_last,
    output reg  [4:0]   block_nbytes,
    input  wire         block_ready,

    input  wire [127:0] eng_out_data,
    input  wire         eng_out_valid,
    input  wire [4:0]   eng_out_nbytes,   // unused in whole-block v1
    output reg          eng_out_ready
);


reg [127:0] block_reg;
reg         tlast_reg;
reg [1:0]   beat_cnt;   //needed to make sure that AES has been completly send/written
reg [4:0]   blk_nbytes_r;

wire       partial_out = (mode == 2'd2) && (blk_nbytes_r < 5'd16);   // CCM short last block
wire [1:0] scat_last   = partial_out ? ((blk_nbytes_r >> 2) - 2'd1) : (BEATS-1);


// localparams and state registers
localparam [2:0] IDLE_GATHER    = 3'd0;
localparam [2:0] LOAD           = 3'd1;
localparam [2:0] WAIT           = 3'd2;
localparam [2:0] OUTPUT_SCATTER = 3'd3;
localparam [2:0] ENGINE_FEED    = 3'd4;
localparam [2:0] ENG_OUT        = 3'd5;
reg [127:0] eng_out_reg;


reg [2:0] state;
reg [2:0] next_state;


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst) begin
        beat_cnt     <= 0;
        block_reg    <= 128'd0;
        tlast_reg    <= 1'b0;
        blk_nbytes_r <= 5'd16;   // full block, matches the combinational default block_nbytes = 16
        eng_out_reg  <= 128'd0;

    end else if (state == IDLE_GATHER && in_tvalid && in_tready) begin
        block_reg[beat_cnt*DATA_WIDTH +: DATA_WIDTH] <= in_tdata;
        tlast_reg <= in_tlast;
        if ((beat_cnt == BEATS-1) || in_tlast) begin
            blk_nbytes_r <= (in_tlast && (beat_cnt != BEATS-1)) ? ((beat_cnt + 1) << 2) : 5'd16;
            beat_cnt     <= 2'd0;
        end else begin
            beat_cnt     <= beat_cnt + 1;
        end
    end else if (state == OUTPUT_SCATTER && (out_tready || discard_output)) begin
        beat_cnt <= (beat_cnt == scat_last) ? 2'd0 : beat_cnt + 1;
    end else if (state == ENG_OUT && eng_out_valid) begin
        eng_out_reg <= eng_out_data;               // ← capture here (clocked), like C2
    end


end

always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE_GATHER;
    else     state <= next_state;
end


reg [127:0] block_in_j;
always @(*) begin
    case (blk_nbytes_r)
        5'd4:    block_in_j = {block_reg[31:0],  96'd0};
        5'd8:    block_in_j = {block_reg[31:0], block_reg[63:32], 64'd0};
        5'd12:   block_in_j = {block_reg[31:0], block_reg[63:32], block_reg[95:64], 32'd0};
        default: block_in_j = block_reg;   // 16
    endcase
end



//Combinational Block
always @(*) begin
    eng_out_ready   = 1'b0;
    block_in        = block_reg;
    block_valid     = 1'b0;
    block_last      = 1'b0;
    block_nbytes    = 5'd16;      // whole-block v1

    next_state      = state;   // default: stay in current state
    in_tready       = 0;
    out_tdata       = {DATA_WIDTH{1'b0}};
    out_tvalid      = 0;
    out_tlast       = 0;
    cipher_in       = block_reg;
    start           = 0;

    case (state)

        IDLE_GATHER: begin
            in_tready = 1;
            start = 0;
            out_tvalid = 0;
            if (in_tvalid && in_tready && ((beat_cnt == BEATS-1) || in_tlast)) begin
                if (bypass)           next_state = OUTPUT_SCATTER;
                else if (mode==2'd0)  next_state = LOAD;
                else                  next_state = ENGINE_FEED;
            end
        end


        LOAD: begin
            in_tready = 0;
            start = 1;
            if (status_busy) begin
                next_state = WAIT;
            end
        end

        WAIT: begin
            start = 0;
            if (status_done) begin
                next_state = OUTPUT_SCATTER;
            end
        end

        OUTPUT_SCATTER: begin
            out_tvalid = ~discard_output;
            out_tdata  = bypass          ? block_reg[beat_cnt*DATA_WIDTH +: DATA_WIDTH]
                       : (mode == 2'd2)  ? (partial_out ? eng_out_reg[127 - 32*beat_cnt -: 32]
                                                        : eng_out_reg[beat_cnt*DATA_WIDTH +: DATA_WIDTH])
                                         : cipher_out[beat_cnt*DATA_WIDTH +: DATA_WIDTH];
            out_tlast  = (beat_cnt == scat_last) && tlast_reg;
            if ((out_tready || discard_output) && beat_cnt == scat_last)
                next_state = IDLE_GATHER;
        end


        ENGINE_FEED: begin
            in_tready    = 1'b0;
            block_in     = block_in_j;
            block_valid  = 1'b1;
            block_last   = tlast_reg;
            block_nbytes = blk_nbytes_r;
            if (block_ready) next_state = (mode == 2'd2) ? ENG_OUT : IDLE_GATHER;
        end


        ENG_OUT: begin
            in_tready     = 1'b0;
            eng_out_ready = 1'b1;                 // accept the engine's block
            if (eng_out_valid) next_state = OUTPUT_SCATTER;   // captured this cycle (seq)
        end

    endcase
end
endmodule