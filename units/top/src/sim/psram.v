// DIOWAS - Simple SPI/QPI PSRAM Model
// (c) Copyright 2024 - 2026 DI-OWAS team
// This module was developed using AI tools. Use with care!!!

module psram_model #(
  parameter MEM_BYTES = 8*1024 // memory size in bytes, has to be a power of 2, accesses wrap around
) (
  input  wire       sck,  // clock
  input  wire       cs_n, // chip select, low-active
  inout  wire [3:0] sio   // data interface (sio[0]=SDI, sio[1]=SDO)
);

  // phase encoding --------------------------------------------------------
  localparam [2:0] P_CMD   = 3'd0;
  localparam [2:0] P_ADDR  = 3'd1;
  localparam [2:0] P_DUMMY = 3'd2;
  localparam [2:0] P_READ  = 3'd3;
  localparam [2:0] P_WRITE = 3'd4;
  localparam [2:0] P_ID    = 3'd5;
  localparam [2:0] P_DONE  = 3'd6;

  localparam [23:0] ADDR_MASK = MEM_BYTES - 1;

  // memory array ------------------------------------------------------------
  reg [7:0] mem [0:MEM_BYTES-1];

  // fixed 8-byte ID code -----------------------------------------------------
  reg [7:0] id_rom [0:7];
  initial begin
    id_rom[0] = 8'h01;
    id_rom[1] = 8'h23;
    id_rom[2] = 8'h45;
    id_rom[3] = 8'h67;
    id_rom[4] = 8'h89;
    id_rom[5] = 8'hab;
    id_rom[6] = 8'hcd;
    id_rom[7] = 8'hef;
  end

  integer i;
  initial begin
    for (i = 0; i < MEM_BYTES; i = i + 1) begin
      mem[i] = 8'h00;
    end
  end

  // states and stuff --------------------------------------------------------
  reg [2:0]  phase    = P_CMD;
  reg        qpi      = 1'b0;
  reg [7:0]  cmd      = 8'h00;
  reg [7:0]  din      = 8'h00;
  reg [7:0]  outsr    = 8'h00;
  reg [23:0] addr     = 24'h000000;
  integer    bitcnt   = 0;
  integer    ibits    = 0;
  integer    obits    = 8;
  integer    dcnt     = 0;
  integer    dummy_c  = 0;
  integer    addr_w   = 1;
  integer    data_w   = 1;
  integer    idx      = 0;
  reg        is_read  = 1'b0;
  reg        is_write = 1'b0;
  reg        is_id    = 1'b0;

  // tri-state output control
  reg [3:0] sio_out = 4'b0000;
  reg [3:0] sio_oe  = 4'b0000;

  assign sio[0] = sio_oe[0] ? sio_out[0] : 1'bz;
  assign sio[1] = sio_oe[1] ? sio_out[1] : 1'bz;
  assign sio[2] = sio_oe[2] ? sio_out[2] : 1'bz;
  assign sio[3] = sio_oe[3] ? sio_out[3] : 1'bz;

  // Decode command (sets operating mode / next phase) -----------------------
  task decode_cmd(input [7:0] c);
  begin
    addr     <= 24'h000000;
    bitcnt   <= 0;
    is_read  <= 1'b0;
    is_write <= 1'b0;
    is_id    <= 1'b0;
    dummy_c  <= 0;
    if (qpi) begin // interface mode QPI
      addr_w <= 4;
      data_w <= 4;
    end else begin // interface mode SPI
      addr_w <= 1;
      data_w <= 1;
    end
    case (c) // access command
      8'h03: begin is_read  <= 1'b1; phase <= P_ADDR; end // read
      8'h0B: begin is_read  <= 1'b1; dummy_c <= 8; phase <= P_ADDR; end // fast read
      8'hEB: begin is_read  <= 1'b1; addr_w <= 4; data_w <= 4; dummy_c <= 6; phase <= P_ADDR; end // fast read quad
      8'h02: begin is_write <= 1'b1; phase <= P_ADDR; end // write
      8'h38: begin is_write <= 1'b1; addr_w <= 4; data_w <= 4; phase <= P_ADDR; end // quad write
      8'h9F: begin is_id    <= 1'b1; phase <= P_ADDR; end // read id
      8'h35: begin qpi <= 1'b1; phase <= P_DONE; end // enter qpi
      8'hF5: begin qpi <= 1'b0; phase <= P_DONE; end // exit qpi
      default: begin phase <= P_DONE; end // incl. reset 0x66/0x99
    endcase
  end
  endtask

  // Start access once the full address is received (am is already masked) --
  task start_access(input [23:0] am);
  begin
    addr   <= am;
    bitcnt <= 0;
    if (is_id) begin
      outsr <= id_rom[0];
      idx   <= 1;
      obits <= 8;
      phase <= P_ID;
    end else if (dummy_c > 0) begin
      dcnt  <= 0;
      phase <= P_DUMMY;
    end else if (is_read) begin
      outsr <= mem[am];
      obits <= 8;
      phase <= P_READ;
    end else begin
      ibits <= 0;
      phase <= P_WRITE;
    end
  end
  endtask

  // Load next output byte (read burst / ID rollover) -------------------------
  task load_next;
  begin
    if (phase == P_ID) begin
      outsr <= id_rom[idx];
      idx   <= (idx + 1) % 8;
    end else begin
      outsr <= mem[(addr + 1) & ADDR_MASK];
      addr  <= (addr + 1) & ADDR_MASK; // wrap around
    end
    obits <= 8;
  end
  endtask

  // Input: sample on rising edge (clock mode 0) -------------------------------
  always @(posedge sck or posedge cs_n) begin
    if (cs_n) begin
      phase  <= P_CMD;
      bitcnt <= 0;
      cmd    <= 8'h00;
    end else begin
      case (phase)

        P_CMD: begin
          if (qpi) begin
            if (bitcnt == 4) begin // second nibble completes the byte
              decode_cmd({cmd[3:0], sio});
            end else begin
              cmd    <= {cmd[3:0], sio};
              bitcnt <= bitcnt + 4;
            end
          end else begin
            if (bitcnt == 7) begin // eighth bit completes the byte
              decode_cmd({cmd[6:0], sio[0]});
            end else begin
              cmd    <= {cmd[6:0], sio[0]};
              bitcnt <= bitcnt + 1;
            end
          end
        end

        P_ADDR: begin
          if (addr_w == 4) begin
            if (bitcnt == 20) begin // 6th nibble => 24 bits complete
              start_access(({addr[19:0], sio}) & ADDR_MASK);
            end else begin
              addr   <= {addr[19:0], sio};
              bitcnt <= bitcnt + 4;
            end
          end else begin
            if (bitcnt == 23) begin // 24th bit complete
              start_access(({addr[22:0], sio[0]}) & ADDR_MASK);
            end else begin
              addr   <= {addr[22:0], sio[0]};
              bitcnt <= bitcnt + 1;
            end
          end
        end

        P_DUMMY: begin
          if (dcnt == dummy_c - 1) begin
            outsr <= mem[addr];
            obits <= 8;
            phase <= P_READ;
          end else begin
            dcnt <= dcnt + 1;
          end
        end

        P_WRITE: begin
          if (data_w == 4) begin
            if (ibits == 4) begin
              mem[addr] <= {din[3:0], sio};
              addr      <= (addr + 1) & ADDR_MASK; // wrap around
              ibits     <= 0;
            end else begin
              din   <= {din[3:0], sio};
              ibits <= ibits + 4;
            end
          end else begin
            if (ibits == 7) begin
              mem[addr] <= {din[6:0], sio[0]};
              addr      <= (addr + 1) & ADDR_MASK; // wrap around
              ibits     <= 0;
            end else begin
              din   <= {din[6:0], sio[0]};
              ibits <= ibits + 1;
            end
          end
        end

        default: begin
          // P_READ / P_ID / P_DONE: ignore input
        end
      endcase
    end
  end

  // Output: drive on falling edge (clock mode 0) ------------------------------
  always @(negedge sck or posedge cs_n) begin
    if (cs_n) begin
      sio_oe <= 4'b0000;
    end else begin
      if ((phase == P_READ) || (phase == P_ID)) begin
        if (data_w == 4) begin
          sio_out <= outsr[7:4];
          sio_oe  <= 4'b1111;
          if (obits == 4) begin
            load_next;
          end else begin
            outsr <= {outsr[3:0], 4'b0000};
            obits <= obits - 4;
          end
        end else begin
          sio_oe     <= 4'b0010; // drive only SO (IO1)
          sio_out[1] <= outsr[7];
          if (obits == 1) begin
            load_next;
          end else begin
            outsr <= {outsr[6:0], 1'b0};
            obits <= obits - 1;
          end
        end
      end else begin
        sio_oe <= 4'b0000;
      end
    end
  end

endmodule
