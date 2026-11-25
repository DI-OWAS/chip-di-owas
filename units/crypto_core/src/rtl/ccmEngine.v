module ccmEngine #(
    parameter Q    = 2,          // length/counter field size in bytes (q)
    parameter NLEN = 15 - Q      // nonce length in bytes (13 when Q=2)
)(
    input  wire                clk,
    input  wire                rst,

    // ---- control ----
    input  wire                start,        // 1-cycle pulse: begin a message
    input  wire                decrypt,      // 0 = encrypt+gen tag, 1 = decrypt+verify
    input  wire [127:0]        key,
    input  wire [8*NLEN-1:0]   nonce,        // NLEN bytes (104 bits when Q=2)
    input  wire [8*Q-1:0]      payload_len,  // total payload byte length (Q bytes)
    input  wire [127:0]        tag_in,       // received encrypted tag U (decrypt only)

    // ---- input block feed (encrypt: plaintext P_i ; decrypt: ciphertext C_i) ----
    input  wire [127:0]        block_in,
    input  wire                block_valid,
    input  wire                block_last,
    input  wire [4:0]          block_nbytes,
    output wire                block_ready,

    // ---- output block stream (encrypt: C_i ; decrypt: P_i) ----
    output reg  [127:0]        out_data,
    output wire                out_valid,
    output reg  [4:0]          out_nbytes,
    input  wire                out_ready,

    // ---- tag / status ----
    output reg  [127:0]        tag_out,      // encrypt: encrypted tag U
    output wire                tag_valid,    // encrypt: U is valid
    output reg                 auth_ok,      // decrypt: 1 if tag verified
    output wire                busy,

    // ---- AES primitive (same contract as CMAC) ----
    output reg  [127:0]        io_key,
    output reg  [127:0]        io_dataIn,
    output wire                fsm_enable,
    input  wire [127:0]        io_dataOut,
    input  wire                fsm_ready,
    input  wire                fsm_valid
);


localparam [2:0] QM1 = Q - 1;                       // the (q-1) field, exactly 3 bits
wire [7:0] FLAGS_FIRST_BLOCK  = {1'b0, 1'b0, 3'b111, QM1};   // 0x39 when Q=2
wire [7:0] FLAGS_CTR = {2'b00, 3'b000, QM1};        // 0x01 when Q=2


reg [127:0]     tag_keystream;
reg [8*Q-1:0]   ctr_index;
reg [127:0]     mac_state;

reg [127:0] ctr_keystream;      // S_i captured from the CTR AES op
reg [127:0] cur_block;          // latched input block (P_i on enc, C_i on dec)
reg [4:0]   cur_nbytes;         // latched valid-byte count of this block
reg         cur_last;           // latched "this was the last block"



// localparams and state registers
localparam [3:0] IDLE               = 4'd0;
localparam [3:0] FIRST_BLOCK_EN     = 4'd1;
localparam [3:0] FIRST_BLOCK_WAIT   = 4'd2;
localparam [3:0] TAG_KEYSTREAM_EN   = 4'd3;
localparam [3:0] TAG_KEYSTREAM_WAIT = 4'd4;
localparam [3:0] FEED               = 4'd5;
localparam [3:0] CTR_EN             = 4'd6;
localparam [3:0] CTR_WAIT           = 4'd7;
localparam [3:0] EMIT               = 4'd8;
localparam [3:0] MAC_EN             = 4'd9;
localparam [3:0] MAC_WAIT           = 4'd10;
localparam [3:0] DONE               = 4'd11;

reg [3:0] state;
reg [3:0] next_state;


wire [127:0] first_block = { FLAGS_FIRST_BLOCK, nonce, payload_len };   // 8 + 8*NLEN + 8*Q = 128 bits
wire [127:0] ctr_block = { FLAGS_CTR, nonce, ctr_index};     // counter is [8*Q-1:0]



function [127:0] zeropad;
    input [127:0] block; 
    input [4:0] nbytes;     // number of valid bytes, 0..16
    integer i;
    begin
        zeropad = 128'b0;
        for (i = 0; i < 16; i = i + 1) begin    // 16 byte lanes, byte 0 = MSB
            if (i < nbytes) begin
                zeropad[127 - 8*i -: 8] = block[127 - 8*i -: 8];
            end
        // lanes i >= nbytes are left at 0x00  ← that's the zero padding
        end
    end
endfunction



// datapath  registers
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mac_state     <= 0;
        ctr_index     <= 0;
        tag_keystream <= 128'd0;
        ctr_keystream <= 128'd0;
        cur_block     <= 128'd0;
        cur_nbytes    <= 5'd0;
        cur_last      <= 1'b0;

    end else if (start) begin
        ctr_index <= 0;

    end else if (state == FIRST_BLOCK_WAIT && fsm_valid) begin
        mac_state <= io_dataOut;

    end else if (state == TAG_KEYSTREAM_WAIT && fsm_valid) begin
        tag_keystream <= io_dataOut; 
        ctr_index <= ctr_index + 1;

    end else if (state == FEED && block_ready && block_valid) begin
        cur_block <= block_in; 
        cur_nbytes <= block_nbytes; 
        cur_last <= block_last;

    end else if (state == CTR_WAIT && fsm_valid) begin
        ctr_keystream <= io_dataOut; 
        ctr_index <= ctr_index + 1;

    end else if (state == MAC_WAIT && fsm_valid) begin
        mac_state <= io_dataOut;
    end
end

wire [127:0] xor_result      = cur_block ^ ctr_keystream;        // enc: C_i ; dec: P_i
wire [127:0] plaintext_block = decrypt ? xor_result : cur_block; // the plaintext, both dirs
wire [127:0] mac_input       = zeropad(plaintext_block, cur_nbytes) ^ mac_state;


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst)    state <= IDLE; 
    else        state <= next_state;
end


// Decoded from the state register, not in the combinational block below, so that
// iverilog does not loop in zero time with the AES fsm_ready/fsm_valid handshake.
// Same function.
assign fsm_enable  = (state == FIRST_BLOCK_EN) || (state == TAG_KEYSTREAM_EN) ||
                     (state == CTR_EN) || (state == MAC_EN);
assign busy        = (state >= FIRST_BLOCK_EN) && (state <= MAC_WAIT);
assign block_ready = (state == FEED);
assign out_valid   = (state == EMIT);
assign tag_valid   = (state == DONE);

always @(*) begin
    next_state  = state;
    out_data    = 128'b0;
    out_nbytes  = 5'b0;
    io_key      = key;                                      // hold key every cycle
    io_dataIn   = 128'b0;
    tag_out     = mac_state ^ tag_keystream;               // U = T ^ S0  (encrypt)
    auth_ok     = (mac_state == (tag_in ^ tag_keystream)); // verdict     (decrypt)

    // case (state)    
    case (state)
        IDLE : begin
            if (start && fsm_ready) begin
                next_state = FIRST_BLOCK_EN;
            end
        end

        FIRST_BLOCK_EN : begin
            io_dataIn = first_block; 

            next_state = FIRST_BLOCK_WAIT;
        end

        FIRST_BLOCK_WAIT : begin

            if (fsm_valid) begin
                next_state = TAG_KEYSTREAM_EN;
            end
        end

        TAG_KEYSTREAM_EN : begin
            io_dataIn = ctr_block; 
            
            next_state = TAG_KEYSTREAM_WAIT; 
        end

        TAG_KEYSTREAM_WAIT : begin

            if (fsm_valid) begin
                next_state = (payload_len == 0) ? DONE : FEED;
            end
        end 

        FEED : begin

            if (block_valid) begin
                next_state = CTR_EN;
            end
        end

        CTR_EN : begin
            io_dataIn = ctr_block; 

            next_state = CTR_WAIT;
        end

        CTR_WAIT : begin

            if (fsm_valid) begin
                next_state = EMIT;
            end
        end

        EMIT : begin
            out_data = xor_result; 
            out_nbytes = cur_nbytes; 

            if (out_ready) begin
                next_state = MAC_EN;
            end
        end

        MAC_EN : begin
            io_dataIn = mac_input; 

            next_state = MAC_WAIT;
        end

        MAC_WAIT : begin

            if (fsm_valid) begin
                next_state = cur_last ? DONE : FEED;
            end
        end

        DONE : begin
            next_state = IDLE;
        end    

        default : begin
            next_state = IDLE;
        end
    endcase
end

endmodule
