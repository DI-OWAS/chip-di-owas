`timescale 1ns / 1ps
`default_nettype none

module keyStorage (
    input  wire          clk,
    input  wire          rst,

    // Write ports — FSM only, no AXI path
    input  wire          key1_wr_en,
    input  wire [127:0]  key1_wr_data,
    input  wire          key2_wr_en,
    input  wire [127:0]  key2_wr_data,

    // Read port — to AES key mux only
    input  wire          key_sel,
    output wire [127:0]  key_out,

    // Status flags — readable by STATUS register, not the key data
    output reg           key1_valid,
    output reg           key2_valid
);

    reg [127:0] key1;
    reg [127:0] key2;

    // Async reset: keys zeroize immediately when rst asserts,
    // regardless of clock state (defeats clock-glitching attacks).
    // When keyn_wr_en the key is loaded and then keyn_valid is set to 1
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key1       <= 128'b0;
            key1_valid <= 1'b0;
        end else if (key1_wr_en) begin
            key1       <= key1_wr_data;
            key1_valid <= 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key2       <= 128'b0;
            key2_valid <= 1'b0;
        end else if (key2_wr_en) begin
            key2       <= key2_wr_data;
            key2_valid <= 1'b1;
        end
    end

    // Combinational mux — no register, just routing
    assign key_out = key_sel ? key2 : key1;

endmodule

`default_nettype wire
