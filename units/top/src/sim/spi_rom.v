// ***********************************************************
// The DI-OWAS Project
//
// Simple SPI memory simulation module.
//
// (c) Copyright 2024 - 2026 DI-OWAS team
// (c) Copyright 2024 - 2026 Fraunhofer IMS (nolting)
// ***********************************************************

`timescale 1ns/1ps

module spi_rom #(
  parameter        INIT_FILE   = "flash_image.hex", // plain HEX initializatio file
  parameter        SIZE_BYTES  = 1024*1024,         // memory aize (power of two)
  parameter [31:0] ADDR_OFFSET = 32'h00000000,      // init file memory offset
  parameter        ADDR_BYTES  = 3,                 // address lenght (3 = 24-bit, 4 = 32-bit)
  parameter        PAGE_SIZE   = 256,               // in bytes
  parameter        BLOCK_SIZE  = 65536,             // in bytes
  parameter [23:0] JEDEC_ID    = 24'h012345,        // identifier
  parameter        SWAP_BYTES  = 0,                 // 1 = swap endianness of init file
  parameter        VERBOSE     = 1                  // output debug messages when 1
)(
  input  wire sck,
  input  wire csn,
  input  wire sdi,
  output wire sdo
);

  // --------------------------------------------------------------------------
  // Commands
  // --------------------------------------------------------------------------
  localparam [7:0] CMD_WREN = 8'h06, CMD_WRDI = 8'h04, CMD_RDSR = 8'h05,
                   CMD_READ = 8'h03, CMD_FRD  = 8'h0B, CMD_PP   = 8'h02,
                   CMD_SE   = 8'h20, CMD_BE   = 8'hD8, CMD_CE   = 8'hC7,
                   CMD_RDID = 8'h9F, CMD_WAKE = 8'hAB;

  localparam integer NWORDS = SIZE_BYTES/4;
  localparam [31:0]  AMASK  = SIZE_BYTES-1;

  reg [31:0] mem [0:NWORDS-1];

  // --------------------------------------------------------------------------
  // Initialization
  // --------------------------------------------------------------------------
  integer i;
  reg [31:0] w;
  initial begin
    for (i=0; i<NWORDS; i=i+1) mem[i] = 32'hFFFFFFFF;
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
      if (SWAP_BYTES != 0)
        for (i=0; i<NWORDS; i=i+1) begin
          w = mem[i];
          mem[i] = {w[7:0], w[15:8], w[23:16], w[31:24]};
        end
      if (VERBOSE) $display("[spi_flash] init from '%s', %0d bytes", INIT_FILE, SIZE_BYTES);
    end
  end

  // --------------------------------------------------------------------------
  // Byte access
  // ---------------------------------------------------------------------------
  function [29:0] widx(input [31:0] a);
    widx = (((a - ADDR_OFFSET) & AMASK) >> 2);
  endfunction

  function [7:0] rd_byte(input [31:0] a);
    reg [31:0] d;
    begin
      d = mem[widx(a)];
      case (a[1:0])
        2'd0:    rd_byte = d[31:24];
        2'd1:    rd_byte = d[23:16];
        2'd2:    rd_byte = d[15:8];
        default: rd_byte = d[7:0];
      endcase
    end
  endfunction

  task wr_byte(input [31:0] a, input [7:0] b);
    reg [31:0] d;
    reg [29:0] k;
    begin
      k = widx(a); d = mem[k];
      case (a[1:0])
        2'd0:    d[31:24] = d[31:24] & b;
        2'd1:    d[23:16] = d[23:16] & b;
        2'd2:    d[15:8]  = d[15:8]  & b;
        default: d[7:0]   = d[7:0]   & b;
      endcase
      mem[k] = d;
    end
  endtask

  task erase_range(input [31:0] a, input integer nbytes);
    integer k;
    reg [29:0] base;
    begin
      base = widx(a);
      for (k=0; k<nbytes/4; k=k+1)
        if ((base+k) < NWORDS) mem[base+k] = 32'hFFFFFFFF;
      if (VERBOSE) $display("[spi_flash] erase @0x%08x (%0d bytes)", a, nbytes);
    end
  endtask

  function has_addr(input [7:0] c);
    has_addr = (c==CMD_READ)||(c==CMD_FRD)||(c==CMD_PP)||(c==CMD_SE)||(c==CMD_BE);
  endfunction

  // --------------------------------------------------------------------------
  // State machine (helpers)
  // --------------------------------------------------------------------------
  reg [7:0]  cmd    = 8'h00;
  reg [7:0]  shin   = 8'h00;
  reg [7:0]  shout  = 8'h00;
  reg [2:0]  bitcnt = 3'd0;
  integer    bcnt   = 0;
  reg [31:0] addr   = 32'h0;
  reg        wel    = 1'b0;
  reg        sdo_r  = 1'b0;

  wire [7:0] status = {6'b000000, wel, 1'b0};

  assign sdo = csn ? 1'b0 : sdo_r;

  task handle_byte(input [7:0] b);
    begin
      if (bcnt == 0) begin // command byte
        cmd = b; addr = 32'h0; shout = 8'h00;
        case (b)
          CMD_WREN: wel = 1'b1;
          CMD_WRDI: wel = 1'b0;
          CMD_RDSR: shout = status;
          CMD_RDID: shout = JEDEC_ID[23:16];
          CMD_CE:   if (wel) begin erase_range(ADDR_OFFSET, SIZE_BYTES); wel = 1'b0; end
          default:  ; // rest: nop
        endcase
      end
      else if (has_addr(cmd) && (bcnt <= ADDR_BYTES)) begin // adress bytes
        addr = (addr << 8) | b;
        if (bcnt == ADDR_BYTES) begin
          case (cmd)
            CMD_READ: begin shout = rd_byte(addr); addr = addr + 1; end
            CMD_SE:   if (wel) begin erase_range(addr & ~32'd4095, 4096);          wel = 1'b0; end
            CMD_BE:   if (wel) begin erase_range(addr & ~(BLOCK_SIZE-1), BLOCK_SIZE); wel = 1'b0; end
            default:  ;
          endcase
        end
      end
      else begin // data
        case (cmd)
          CMD_READ,
          CMD_FRD:  begin shout = rd_byte(addr); addr = addr + 1; end // dummy bytes=
          CMD_RDSR: shout = status;
          CMD_RDID: shout = (bcnt==1) ? JEDEC_ID[15:8] :
                            (bcnt==2) ? JEDEC_ID[7:0]  : 8'h00;
          CMD_PP:   if (wel) begin
                      wr_byte(addr, b);
                      addr = (addr & ~(PAGE_SIZE-1)) | ((addr+1) & (PAGE_SIZE-1));
                    end
          default:  shout = 8'h00;
        endcase
      end
    end
  endtask

  // start transaction with active CS
  always @(negedge csn) begin
    bitcnt = 3'd0; bcnt = 0; cmd = 8'h00; shin = 8'h00; shout = 8'h00;
  end

  // reset WEL after end of write operation
  always @(posedge csn) begin
    if (cmd == CMD_PP) wel = 1'b0;
  end

  // sample on rising edge (SPI clock mode 0)
  always @(posedge sck) if (!csn) begin
    shin = {shin[6:0], sdi};
    if (bitcnt == 3'd7) begin
      bitcnt = 3'd0;
      handle_byte(shin);
      bcnt = bcnt + 1;
    end else
      bitcnt = bitcnt + 1;
  end

  // output on falling edge (SPI clock mode 0)
  always @(negedge sck) if (!csn) begin
    sdo_r = shout[7];
    shout = {shout[6:0], 1'b0};
  end

endmodule
