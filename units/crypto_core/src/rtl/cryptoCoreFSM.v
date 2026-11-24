module cryptoCoreFSM (
    input  wire             clk,
    input  wire             rst,



    //inputs from axi4LiteRegs module
    input wire              ctrl_start,
    input wire              ctrl_key_sel,
    input wire [127:0]      cipher_in,
    input wire [127:0]      ctr_nonce,

    //inputs from key_storage
    input wire [127:0]      key_out,
    input wire              key1_valid,
    input wire              key2_valid,
    // boot wires also for key_storage
    input wire              boot_active,
    input wire [127:0]      boot_kek,

    //inputs from AES engine
    input wire              fsm_ready,
    input wire              fsm_valid,
    input wire [127:0]      io_dataOut, 



    //outputs from axi4LiteRegs module
    output reg              status_busy,
    output reg              status_done,
    output reg [127:0]      cipher_out,

    //outputs to AES engine
    output reg [127:0]      io_key,
    output reg [127:0]      io_dataIn,
    output reg              fsm_enable,

    //output to keyStorage
    output reg              key_sel,
    output reg              key1_wr_en,
    output reg [127:0]      key1_wr_data,
    output reg              key2_wr_en,
    output reg [127:0]      key2_wr_data,

    //ctr ports
    input wire              ctr_overflow,
    output reg              ctr_count_inc,

    input wire              boot_done

);


// localparams and state registers
localparam [2:0] RUNTIME_IDLE   = 3'd0;
localparam [2:0] RUNTIME_ENABLE = 3'd1;
localparam [2:0] RUNTIME_WAIT   = 3'd2;
localparam [2:0] RUNTIME_DONE   = 3'd3;
// (boot states can be 3'd4 through 3'd6 when added later)

reg [2:0] state;
reg [2:0] next_state;


//cipher_out register (needed so that output is held for multiple cycles)
always @(posedge clk or posedge rst) begin
    if (rst) begin
        cipher_out <= 128'd0;
    end

    else begin
        if (state == RUNTIME_DONE) begin
            cipher_out <= io_dataOut ^ cipher_in;    
        end
    end
end


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst)    state <= RUNTIME_IDLE; 
    else        state <= next_state;
end


//Combinational Block
always @(*) begin
    next_state    = state;   // default: stay in current state
    status_busy   = 1'b0;
    status_done   = 1'b0;
    fsm_enable    = 1'b0;
    key_sel       = ctrl_key_sel;  // always mirrors the control bit
    io_key        = boot_active ? boot_kek : key_out;       // if boot_active use boot_kek, else use selected key
    io_dataIn     = ctr_nonce;     // always feed the counter block
    ctr_count_inc = 1'b0;

    //Defaulting to zero for now (change later when implementing boot phase)
    key1_wr_en   = 1'b0;
    key1_wr_data = 128'b0;
    key2_wr_en   = 1'b0;
    key2_wr_data = 128'b0;


    case (state)
        RUNTIME_IDLE: begin
            if (ctrl_start && fsm_ready && !ctr_overflow) begin
                // if boot_active we can run aes without keys1/2 being valid
                if (boot_active) begin
                    next_state = RUNTIME_ENABLE;
                end

                else if (boot_done && ((key_sel == 1'b0 && key1_valid) || (key_sel == 1'b1 && key2_valid)) ) begin
                    next_state = RUNTIME_ENABLE;
                end 
            end
        end

        RUNTIME_ENABLE: begin
            fsm_enable = 1'b1;
            status_busy = 1'b1;
            next_state = RUNTIME_WAIT;
        end

        RUNTIME_WAIT: begin
            status_busy = 1'b1;

            if (fsm_valid) begin
                next_state = RUNTIME_DONE;
            end
        end

        RUNTIME_DONE: begin
            status_done = 1'b1;
            next_state = RUNTIME_IDLE;
            ctr_count_inc = 1'b1;
        end
    endcase
end


    
endmodule