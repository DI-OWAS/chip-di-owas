module axi4LiteRegister (
    input wire              clk,
    input wire              rst,

    output reg [4:0]        CTRL,
    input wire [7:0]        STATUS,

    //ports for axil_reg_if module
    input  wire [7:0]       s_axil_awaddr,
    input  wire [2:0]       s_axil_awprot,
    input  wire             s_axil_awvalid,
    output wire             s_axil_awready,
    input  wire [31:0]      s_axil_wdata,
    input  wire [3:0]       s_axil_wstrb,
    input  wire             s_axil_wvalid,
    output wire             s_axil_wready,
    output wire [1:0]       s_axil_bresp,
    output wire             s_axil_bvalid,
    input  wire             s_axil_bready,
    input  wire [7:0]       s_axil_araddr,
    input  wire [2:0]       s_axil_arprot,
    input  wire             s_axil_arvalid,
    output wire             s_axil_arready,
    output wire [31:0]      s_axil_rdata,
    output wire [1:0]       s_axil_rresp,
    output wire             s_axil_rvalid,
    input  wire             s_axil_rready,

    output reg              ctr_overflow,
    input wire              ctr_count_inc,
    output wire [127:0]     ctr_nonce,
    output wire [31:0]      ctr_count_val,
    input wire              dma_error,

    output reg  [103:0]     ccm_nonce,    // 13-byte CCM nonce
    output reg  [15:0]      payload_len,  // total payload bytes
    output reg  [127:0]     tag_in,       // received tag U (CCM decrypt)
    input  wire [127:0]     tag_out,      // latched engine result (from cryptoCore)


    output reg [31:0]      SRC_ADDR,
    output reg [31:0]      DST_ADDR,
    output reg [31:0]      DMA_BLOCKS,
    output reg             GO,

    input wire             dma_go_clr,
    input wire             dma_busy,
    input wire             dma_done,

    input wire             boot_iv_load,
    input wire [95:0]      boot_iv_data,
    input wire             boot_active    
    
);

    // internal wires/reg for axil_reg_if module
    wire reg_wr_en;
    wire [31:0] reg_wr_data;
    wire [7:0] reg_wr_addr;
    wire [3:0] reg_wr_strb;
    wire reg_rd_en;
    reg [31:0] reg_rd_data;
    wire [7:0] reg_rd_addr;

    wire reg_wr_wait;
    wire reg_wr_ack;
    wire reg_rd_wait;
    wire reg_rd_ack;

    reg [95:0] ctr_iv;
    reg [31:0] ctr_count;

    //assign wait and ack signals
    assign reg_wr_wait = 1'b0;
    assign reg_wr_ack  = reg_wr_en;
    assign reg_rd_wait = 1'b0;
    assign reg_rd_ack  = reg_rd_en;

    // build ctr_nonce 
    assign ctr_nonce = {ctr_iv, ctr_count};

    assign ctr_count_val = ctr_count;


    //Instantiating axil_reg_if module
    axil_reg_if #(.ADDR_WIDTH(8)) u_axil_reg_if (
        .clk            (clk),
        .rst            (rst),

        /*
        * AXI-Lite slave interface
        */
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awprot  (s_axil_awprot),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arprot  (s_axil_arprot),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),

        /*
        * Register interface
        */
        .reg_wr_addr    (reg_wr_addr),
        .reg_wr_data    (reg_wr_data),
        .reg_wr_strb    (reg_wr_strb),
        .reg_wr_en      (reg_wr_en),
        .reg_wr_wait    (reg_wr_wait),
        .reg_wr_ack     (reg_wr_ack),
        .reg_rd_addr    (reg_rd_addr),
        .reg_rd_en      (reg_rd_en),
        .reg_rd_data    (reg_rd_data),
        .reg_rd_wait    (reg_rd_wait),
        .reg_rd_ack     (reg_rd_ack)
    );


    //Declaring registers

    //CTRL register: CTRL[0]=key_sel, CTRL[1]=bypass (decoded in cryptoCore)

    //STATUS register
    wire BUSY = STATUS[0];
    wire DONE = STATUS[1];
    wire BOOT_DONE = STATUS[2];
    wire KEY1_VALID = STATUS[3];
    wire KEY2_VALID = STATUS[4];


    //Constants for readability for register address mapping
    localparam ADDR_CTRL            = 8'h00;
    localparam ADDR_STATUS          = 8'h04;
    
    localparam ADDR_CTR_NONCE_1     = 8'h40;
    localparam ADDR_CTR_NONCE_2     = 8'h44;
    localparam ADDR_CTR_NONCE_3     = 8'h48;
    
    localparam ADDR_SRC_ADDR        = 8'h50;
    localparam ADDR_DST_ADDR        = 8'h54;
    
    localparam ADDR_DMA_BLOCKS      = 8'h58;
    localparam ADDR_GO              = 8'h5C;
    localparam ADDR_DMA_STATUS      = 8'h60;

    localparam ADDR_CCM_NONCE_0     = 8'h64;
    localparam ADDR_CCM_NONCE_1     = 8'h68;
    localparam ADDR_CCM_NONCE_2     = 8'h6C;
    localparam ADDR_CCM_NONCE_3     = 8'h70;   // only low 8 bits used (nonce[103:96])

    localparam ADDR_PAYLOAD_LEN     = 8'h74;

    localparam ADDR_TAG_IN_0        = 8'h80;
    localparam ADDR_TAG_IN_1        = 8'h84;
    localparam ADDR_TAG_IN_2        = 8'h88;
    localparam ADDR_TAG_IN_3        = 8'h8C;
    localparam ADDR_TAG_OUT_0       = 8'h90;
    localparam ADDR_TAG_OUT_1       = 8'h94;
    localparam ADDR_TAG_OUT_2       = 8'h98;
    localparam ADDR_TAG_OUT_3       = 8'h9C;




    // Write-decoder
    always @(posedge clk or posedge rst) begin
        
        if (rst) begin
            CTRL            <= 5'd0;
            ccm_nonce       <= 104'd0;
            payload_len     <= 16'd0;
            tag_in          <= 128'd0;
            ctr_iv          <= 96'd0;
            ctr_count       <= 32'd0;
            ctr_overflow    <= 1'b0;
            SRC_ADDR        <= 32'd0;
            DST_ADDR        <= 32'd0;
            DMA_BLOCKS      <= 32'd0;
            GO              <= 1'b0;
        end
        
        //Write into the correct registers (check-address)
        else begin

            if (dma_go_clr) GO <= 1'b0;

            if (reg_wr_en && ~boot_active) begin
                case (reg_wr_addr)
                    
                    ADDR_CTRL: begin
                        if (reg_wr_strb[0]) begin
                            CTRL <= reg_wr_data[4:0];
                        end
                    end


                    ADDR_CTR_NONCE_1: begin
                        if (reg_wr_strb[0]) ctr_iv[7:0]      <= reg_wr_data[7:0];
                            
                        if (reg_wr_strb[1]) ctr_iv[15:8]     <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) ctr_iv[23:16]    <= reg_wr_data[23:16];
                            
                        if (reg_wr_strb[3]) ctr_iv[31:24]    <= reg_wr_data[31:24];

                        //if new nonce is written we need to restart the overflow ctr and normal ctr
                        ctr_overflow <= 0;
                        ctr_count <= 32'h0;
                    end

                    ADDR_CTR_NONCE_2: begin
                        if (reg_wr_strb[0]) ctr_iv[39:32]    <= reg_wr_data[7:0];
                        
                        if (reg_wr_strb[1]) ctr_iv[47:40]    <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) ctr_iv[55:48]    <= reg_wr_data[23:16];
                        
                        if (reg_wr_strb[3]) ctr_iv[63:56]    <= reg_wr_data[31:24];

                        //if new nonce is written we need to restart the overflow ctr and normal ctr
                        ctr_overflow <= 0;
                        ctr_count <= 32'h0;
                    end

                    ADDR_CTR_NONCE_3: begin
                        if (reg_wr_strb[0]) ctr_iv[71:64]    <= reg_wr_data[7:0];
                        
                        if (reg_wr_strb[1]) ctr_iv[79:72]    <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) ctr_iv[87:80]    <= reg_wr_data[23:16];
                        
                        if (reg_wr_strb[3]) ctr_iv[95:88]    <= reg_wr_data[31:24];

                        //if new nonce is written we need to restart the overflow ctr and normal ctr
                        ctr_overflow <= 0;
                        ctr_count <= 32'h0;
                    end

                    // last part of nonce is not writable from outside as it is increased by ctr



                    ADDR_SRC_ADDR: begin
                        if (reg_wr_strb[0]) SRC_ADDR[7:0]      <= reg_wr_data[7:0];
                            
                        if (reg_wr_strb[1]) SRC_ADDR[15:8]     <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) SRC_ADDR[23:16]    <= reg_wr_data[23:16];
                            
                        if (reg_wr_strb[3]) SRC_ADDR[31:24]    <= reg_wr_data[31:24];
                    end


                    ADDR_DST_ADDR: begin
                        if (reg_wr_strb[0]) DST_ADDR[7:0]      <= reg_wr_data[7:0];
                            
                        if (reg_wr_strb[1]) DST_ADDR[15:8]     <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) DST_ADDR[23:16]    <= reg_wr_data[23:16];
                            
                        if (reg_wr_strb[3]) DST_ADDR[31:24]    <= reg_wr_data[31:24];
                    end

                    
                    ADDR_DMA_BLOCKS: begin
                        if (reg_wr_strb[0]) DMA_BLOCKS[7:0]    <= reg_wr_data[7:0];
                            
                        if (reg_wr_strb[1]) DMA_BLOCKS[15:8]   <= reg_wr_data[15:8];
                        
                        if (reg_wr_strb[2]) DMA_BLOCKS[23:16]  <= reg_wr_data[23:16];
                            
                        if (reg_wr_strb[3]) DMA_BLOCKS[31:24]  <= reg_wr_data[31:24];
                    end


                    ADDR_GO: begin
                        if (reg_wr_strb[0]) GO          <= reg_wr_data[0];
                    end

                    ADDR_CCM_NONCE_0: begin
                        if (reg_wr_strb[0]) ccm_nonce[7:0]    <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) ccm_nonce[15:8]   <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) ccm_nonce[23:16]  <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) ccm_nonce[31:24]  <= reg_wr_data[31:24];
                    end
                    ADDR_CCM_NONCE_1: begin
                        if (reg_wr_strb[0]) ccm_nonce[39:32]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) ccm_nonce[47:40]  <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) ccm_nonce[55:48]  <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) ccm_nonce[63:56]  <= reg_wr_data[31:24];
                    end
                    ADDR_CCM_NONCE_2: begin
                        if (reg_wr_strb[0]) ccm_nonce[71:64]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) ccm_nonce[79:72]  <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) ccm_nonce[87:80]  <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) ccm_nonce[95:88]  <= reg_wr_data[31:24];
                    end
                    ADDR_CCM_NONCE_3: begin
                        if (reg_wr_strb[0]) ccm_nonce[103:96] <= reg_wr_data[7:0];   // top byte only
                    end

                    ADDR_PAYLOAD_LEN: begin
                        if (reg_wr_strb[0]) payload_len[7:0]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) payload_len[15:8] <= reg_wr_data[15:8];
                    end

                    ADDR_TAG_IN_0: begin
                        if (reg_wr_strb[0]) tag_in[7:0]     <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) tag_in[15:8]    <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) tag_in[23:16]   <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) tag_in[31:24]   <= reg_wr_data[31:24];
                    end
                    ADDR_TAG_IN_1: begin
                        if (reg_wr_strb[0]) tag_in[39:32]   <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) tag_in[47:40]   <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) tag_in[55:48]   <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) tag_in[63:56]   <= reg_wr_data[31:24];
                    end
                    ADDR_TAG_IN_2: begin
                        if (reg_wr_strb[0]) tag_in[71:64]   <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) tag_in[79:72]   <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) tag_in[87:80]   <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) tag_in[95:88]   <= reg_wr_data[31:24];
                    end
                    ADDR_TAG_IN_3: begin
                        if (reg_wr_strb[0]) tag_in[103:96]  <= reg_wr_data[7:0];
                        if (reg_wr_strb[1]) tag_in[111:104] <= reg_wr_data[15:8];
                        if (reg_wr_strb[2]) tag_in[119:112] <= reg_wr_data[23:16];
                        if (reg_wr_strb[3]) tag_in[127:120] <= reg_wr_data[31:24];
                    end

                    default: begin
                        
                    end
                    
                endcase
            end

            // increment the ctr
            if (ctr_count_inc) begin
                if (ctr_count == 32'hFFFFFFFF) begin
                    ctr_overflow <= 1'b1;
                end
                else begin
                    ctr_count <= ctr_count + 1; 
                end
            end

            if (boot_iv_load) begin
                ctr_iv       <= boot_iv_data;
                ctr_count    <= 32'd0;
                ctr_overflow <= 1'b0;
            end
        end
    end


    // Read-decoder
    always @(*) begin
        case (reg_rd_addr)
            
            //As CTRL and STATUS are smaller then 32 bit the need to be zero padded
            ADDR_CTRL: begin
                reg_rd_data[31:0] = {27'b0, CTRL};
            end

            ADDR_STATUS: begin
                reg_rd_data[31:0] = {24'b0, STATUS}; 
            end

            
            // all parts of the nonce are readable for debugging (nonces are often send in plaintext so read access should be ok)
            ADDR_CTR_NONCE_1: begin
                reg_rd_data[31:0] = ctr_iv[31:0];
            end

            ADDR_CTR_NONCE_2: begin
                reg_rd_data[31:0] = ctr_iv[63:32];
            end

            ADDR_CTR_NONCE_3: begin
                reg_rd_data[31:0] = ctr_iv[95:64];
            end


            ADDR_SRC_ADDR: begin
                reg_rd_data[31:0] = SRC_ADDR;
            end

            ADDR_DST_ADDR: begin
                reg_rd_data[31:0] = DST_ADDR;
            end

            ADDR_DMA_BLOCKS: begin
                reg_rd_data[31:0] = DMA_BLOCKS;
            end

            ADDR_GO: begin
                reg_rd_data[31:0] = 32'h00000000;
                reg_rd_data[0] = GO;
            end

            ADDR_DMA_STATUS: begin
                reg_rd_data[31:0] = {29'b0, dma_error, dma_done, dma_busy};
            end

            ADDR_CCM_NONCE_0: reg_rd_data = ccm_nonce[31:0];
            ADDR_CCM_NONCE_1: reg_rd_data = ccm_nonce[63:32];
            ADDR_CCM_NONCE_2: reg_rd_data = ccm_nonce[95:64];
            ADDR_CCM_NONCE_3: reg_rd_data = {24'b0, ccm_nonce[103:96]};
            ADDR_PAYLOAD_LEN: reg_rd_data = {16'b0, payload_len};
            ADDR_TAG_IN_0:    reg_rd_data = tag_in[31:0];
            ADDR_TAG_IN_1:    reg_rd_data = tag_in[63:32];
            ADDR_TAG_IN_2:    reg_rd_data = tag_in[95:64];
            ADDR_TAG_IN_3:    reg_rd_data = tag_in[127:96];
            ADDR_TAG_OUT_0:   reg_rd_data = tag_out[31:0];
            ADDR_TAG_OUT_1:   reg_rd_data = tag_out[63:32];
            ADDR_TAG_OUT_2:   reg_rd_data = tag_out[95:64];
            ADDR_TAG_OUT_3:   reg_rd_data = tag_out[127:96];

            default: begin
                reg_rd_data = 32'b0;
            end
        endcase
    end 


endmodule