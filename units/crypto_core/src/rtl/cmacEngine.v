module cmacEngine (
    input  wire         clk,
    input  wire         rst,

    // ---- control/data interface (testbench or higher-level FSM) ----
    input  wire         start,        // 1-cycle pulse: begin a new message
    input  wire [127:0] key,          // AES key, held stable for the whole message
    input  wire [127:0] block_in,     // current 128-bit message block
    input  wire         block_valid,  // block_in is presented
    input  wire         block_last,   // this is the final block of the message
    input  wire [4:0]   block_nbytes, // valid bytes in the FINAL block, 0..16 (16=full)
    output reg          block_ready,  // engine will consume a block this cycle
    output reg  [127:0] tag,          // CMAC result
    output reg          tag_valid,    // 1 when tag is valid (message complete)
    output reg          busy,

    // ---- AES primitive interface (drive + consume) ----
    output reg  [127:0] io_key,
    output reg  [127:0] io_dataIn,
    output reg          fsm_enable,
    input  wire [127:0] io_dataOut,
    input  wire         fsm_ready,
    input  wire         fsm_valid
);



// localparams and state registers
localparam [2:0] IDLE           = 3'd0;
localparam [2:0] SUBKEY_EN      = 3'd1;
localparam [2:0] SUBKEY_WAIT    = 3'd2;
localparam [2:0] ABSORB_EN      = 3'd3;
localparam [2:0] ABSORB_WAIT    = 3'd4;
localparam [2:0] DONE           = 3'd5;

reg [2:0] state;
reg [2:0] next_state;

reg [127:0] chaining_reg;
reg [127:0] L;

reg last_r;

localparam [127:0] RB = 128'h00000000_00000000_00000000_00000087; // GF(2^128) reduction


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst)    state <= IDLE; 
    else        state <= next_state;
end


function [127:0] dbl (input [127:0] x);
    reg [127:0] a;
    reg         sel;
    begin
        a = {x[126:0], 1'b0};
        sel = x[127];
        dbl = sel ? (a ^ RB) : a;
    end
endfunction


wire [127:0] K1 = dbl(L);
wire [127:0] K2 = dbl(K1);

// datapath  registers
always @(posedge clk or posedge rst) begin
    if (rst) begin
        chaining_reg <= 128'd0;
        L            <= 128'd0;
        last_r       <= 1'b0;
    end else if (start) begin               // synchronous clear at message start
        chaining_reg <= 128'd0;
        L            <= 128'd0;
        last_r       <= 1'b0;
    end else begin

        if (state == SUBKEY_WAIT && fsm_valid) begin
            L <= io_dataOut;
        end

        if (state == ABSORB_WAIT && fsm_valid) begin
            chaining_reg <= io_dataOut;    
        end

        if (state == ABSORB_EN && block_ready && block_valid) begin
            last_r <= block_last;
        end
    end
end

// combinational datapath
wire         is_full_last = block_last && (block_nbytes == 5'd16);
reg [127:0] blk_padded;    // block_in with 0x80 marker + zero fill
reg [127:0] blk_present;   // what actually gets XORed into the chain this step
integer i;

always @(*) begin
    if (is_full_last)begin
        blk_present = block_in ^ K1;
    end else if (block_last && !(is_full_last)) begin
        blk_present = blk_padded ^ K2;
    end else begin
        blk_present = block_in;
    end
end

always @(*) begin    
    for (i = 0; i < 16; i = i +1) begin
        if (i < block_nbytes)begin
            blk_padded[127 - 8*i -: 8] = block_in[127 - 8*i -: 8];
        end else if (i == block_nbytes) begin
            blk_padded[127 - 8*i -: 8] = 8'h80;
        end else begin
            blk_padded[127 - 8*i -: 8] = 8'h00;
        end
    end
end


always @(*) begin
    next_state  = state;
    fsm_enable  = 1'b0;
    block_ready = 1'b0;
    busy        = 1'b0;
    tag_valid   = 1'b0;
    io_key      = key;              // hold the key across the whole op
    io_dataIn   = 128'd0;           // overridden per-state below
    tag = chaining_reg;
    
    case (state)
        IDLE : begin
            
            if (start && fsm_ready) begin
                next_state = SUBKEY_EN;
            end
        end

        SUBKEY_EN : begin
            io_dataIn = 0;
            fsm_enable = 1;
            busy = 1;
            next_state = SUBKEY_WAIT;
        end

        SUBKEY_WAIT : begin
            busy=1;
            if (fsm_valid) begin
                next_state = ABSORB_EN;
            end
        end

        ABSORB_EN : begin
            busy = 1;
            block_ready = 1;
            if (block_valid) begin
                io_dataIn = chaining_reg ^ blk_present;
                fsm_enable = 1;
                next_state = ABSORB_WAIT;
            end
        end

        ABSORB_WAIT : begin
            busy = 1;
            if (fsm_valid) begin
                if (last_r) begin
                    next_state = DONE;
                end else begin
                    next_state = ABSORB_EN;
                end
            end
        end 

        DONE : begin
            tag_valid = 1;
            next_state = IDLE;
        end    
    endcase
end

endmodule