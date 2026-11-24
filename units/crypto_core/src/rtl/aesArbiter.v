module aesArbiter (
    input  wire [1:0]   mode,        // 0=CTR, 1=CMAC, 2=CCM
    input  wire         boot_active, // boot uses the CTR FSM → force CTR

    // from CTR FSM (cryptoCoreFSM)
    input  wire [127:0] ctr_key,  input wire [127:0] ctr_din,  input wire ctr_en,
    // from cmacEngine
    input  wire [127:0] cmac_key, input wire [127:0] cmac_din, input wire cmac_en,
    // from ccmEngine
    input  wire [127:0] ccm_key,  input wire [127:0] ccm_din,  input wire ccm_en,

    // to the shared AES
    output reg  [127:0] aes_key,
    output reg  [127:0] aes_din,
    output reg          aes_en
);
    localparam [1:0] MODE_CTR = 2'd0, MODE_CMAC = 2'd1, MODE_CCM = 2'd2;

    wire [1:0] eff_mode = boot_active ? MODE_CTR : mode;   // ← key line

    always @(*) begin
        case (eff_mode)
            MODE_CTR : begin
                aes_key = ctr_key;
                aes_din = ctr_din;
                aes_en  = ctr_en;
            end

            MODE_CMAC : begin
                aes_key = cmac_key;
                aes_din = cmac_din;
                aes_en  = cmac_en;
            end

            MODE_CCM : begin
                aes_key = ccm_key;
                aes_din = ccm_din;
                aes_en  = ccm_en;
            end

            //       default to the CTR master (safest).
            default : begin
                aes_key = ctr_key;
                aes_din = ctr_din;
                aes_en  = ctr_en;
            end
        endcase
    end
endmodule
