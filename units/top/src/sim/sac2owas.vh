`ifndef SAC2OWAS_BYTE_SEQUENCE_VH
`define SAC2OWAS_BYTE_SEQUENCE_VH

localparam integer SAC2OWAS_BYTE_COUNT = 2176;

reg [7:0] sac2owas_bytes [0:SAC2OWAS_BYTE_COUNT-1];

task sac2owas_write_frame;
  input [7:0] frame_number;
  input payload_descending;
  input integer offset;
  integer i;
  begin
    sac2owas_bytes[offset + 0]  = 8'h7B;
    sac2owas_bytes[offset + 1]  = 8'h11;
    sac2owas_bytes[offset + 2]  = 8'h01;
    sac2owas_bytes[offset + 3]  = 8'h78;
    sac2owas_bytes[offset + 4]  = 8'hA0;
    sac2owas_bytes[offset + 5]  = 8'hA1;
    sac2owas_bytes[offset + 6]  = 8'hA2;
    sac2owas_bytes[offset + 7]  = 8'hA3;
    sac2owas_bytes[offset + 8]  = frame_number;
    sac2owas_bytes[offset + 9]  = 8'hB1;
    sac2owas_bytes[offset + 10] = 8'hB2;
    sac2owas_bytes[offset + 11] = 8'hB3;
    for (i = 0; i < 112; i = i + 1) begin
      if (payload_descending) begin
        sac2owas_bytes[offset + 12 + i] = 8'h6F - i;
      end else begin
         sac2owas_bytes[offset + 12 + i] = i;
      end
    end
    sac2owas_bytes[offset + 124] = 8'h10;
    sac2owas_bytes[offset + 125] = 8'h11;
    sac2owas_bytes[offset + 126] = 8'h7D;
    sac2owas_bytes[offset + 127] = 8'h7E;
  end
endtask


task sac2owas_load;
  begin
    sac2owas_write_frame(8'h00, 1'b0,    0);
    sac2owas_write_frame(8'h01, 1'b1,  128);
    sac2owas_write_frame(8'h02, 1'b0,  256);
    sac2owas_write_frame(8'h03, 1'b1,  384);
    sac2owas_write_frame(8'h04, 1'b0,  512);
    sac2owas_write_frame(8'h05, 1'b1,  640);
    sac2owas_write_frame(8'h06, 1'b0,  768);
    sac2owas_write_frame(8'h07, 1'b1,  896);
    
    sac2owas_write_frame(8'h08, 1'b1, 1024);
    sac2owas_write_frame(8'h09, 1'b1, 1152);
    sac2owas_write_frame(8'h0A, 1'b1, 1280);
    sac2owas_write_frame(8'h0B, 1'b1, 1408);
    sac2owas_write_frame(8'h0C, 1'b1, 1536);
    sac2owas_write_frame(8'h0D, 1'b1, 1664);
    sac2owas_write_frame(8'h0E, 1'b1, 1792);
    sac2owas_write_frame(8'h0F, 1'b1, 1920);
    sac2owas_write_frame(8'h10, 1'b1, 2048);
  end
endtask

`endif
