module cryptoDmaCtrl  #( 
    parameter AXI_ADDR_WIDTH = 16, 
    parameter LEN_WIDTH = 20 
)
(
    input wire  clk,
    input wire  rst,
    input wire  GO,
    input wire [31:0] SRC_ADDR,
    input wire [31:0] DST_ADDR,
    input wire [31:0] DMA_BLOCKS,
    input wire  rd_desc_ready,
    input wire  wr_desc_ready,
    input wire  wr_status_valid,
    input wire [31:0] ctr_count,
    input wire  ctr_overflow,
    input wire  ctrl_key_sel,
    input wire  ctrl_bypass,
    input wire  key1_valid,
    input wire  key2_valid,
    input wire  boot_active,
    input wire  read_only,
    input wire  engine_mode,     // 1 for CMAC/CCM
    input wire [15:0] payload_len,

    
    output reg [AXI_ADDR_WIDTH-1:0] rd_desc_addr,
    output reg [LEN_WIDTH-1:0] rd_desc_len,
    output reg  rd_desc_valid,
    output reg [AXI_ADDR_WIDTH-1:0] wr_desc_addr,
    output reg [LEN_WIDTH-1:0] wr_desc_len,
    output reg  wr_desc_valid,
    output reg  dma_go_clr,
    output reg  dma_busy,
    output reg  dma_done,
    output reg  dma_error
);


// localparams and state registers
localparam [3:0] IDLE       = 4'd0;
localparam [3:0] ISSUE_RD   = 4'd1;
localparam [3:0] ISSUE_WR   = 4'd2;
localparam [3:0] WAIT       = 4'd3;
localparam [3:0] FINISH     = 4'd4;
localparam [3:0] ERROR      = 4'd5;


reg [3:0] state;
reg [3:0] next_state;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        dma_done <= 1'b0;
        dma_error <= 1'b0;
    end
    else if (state == IDLE && GO) begin
        dma_done <= 1'b0;
        dma_error <= 1'b0;
    end
    else if (state == FINISH) begin
        dma_done <= 1'b1;
    end
    else if (state == ERROR) begin
        dma_done <= 1'b1;
        dma_error <= 1'b1;
    end
end


// Sequential Block
always @(posedge clk or posedge rst) begin
    if (rst)    state <= IDLE; 
    else        state <= next_state;
end

// combinational logic for error logic
wire key_ok        = (ctrl_key_sel==1'b0 && key1_valid) || (ctrl_key_sel==1'b1 && key2_valid);
wire [32:0] end_count     = {1'b0, ctr_count} + {1'b0, DMA_BLOCKS};      // 33-bit
wire overflow_risk = ctr_overflow || (end_count > 33'h1_0000_0000);
wire refuse        = !boot_active && !ctrl_bypass && (overflow_risk || !key_ok);  // bypass needs neither key nor counter


wire [31:0] xfer_len = engine_mode ? {16'd0, payload_len} : (DMA_BLOCKS << 4);


//Combinational Block
always @(*) begin

    //default values
    next_state      = state;   // default: stay in current state
    rd_desc_addr    = 32'h00000000;  
    rd_desc_len     = 32'h0000;
    rd_desc_valid   = 1'b0;
    wr_desc_addr    = 32'h00000000;
    wr_desc_len     = 32'h0000;
    wr_desc_valid   = 1'b0;
    dma_go_clr      = 1'b0;
    dma_busy        = 1'b0;

    case (state)

        IDLE: begin
            dma_busy = 0;
            if (GO) begin
                dma_go_clr = (state == IDLE && GO);
                if (refuse) next_state = ERROR;
                else next_state = ISSUE_RD;
            end
        end

        ISSUE_RD: begin
            dma_busy = 1;
            rd_desc_addr = SRC_ADDR;
            rd_desc_len = xfer_len[LEN_WIDTH-1:0];   // ISSUE_RD
            rd_desc_valid = 1;
            if (rd_desc_ready) begin
                if (read_only) next_state = FINISH;
                else next_state = ISSUE_WR;                
            end 
        end

        ISSUE_WR: begin
            dma_busy = 1;
            wr_desc_addr = DST_ADDR;
            wr_desc_len = xfer_len[LEN_WIDTH-1:0];   // ISSUE_WR
            wr_desc_valid = 1;
            if (wr_desc_ready) begin
                next_state = WAIT;                
            end 
        end

        WAIT: begin
            dma_busy = 1;
            if (wr_status_valid) begin
                next_state = FINISH;
            end
        end

        FINISH: begin
            dma_busy = 0;
            next_state = IDLE;
        end

        ERROR: begin
            dma_busy = 0;
            next_state = IDLE;
        end
        
    endcase

end

endmodule