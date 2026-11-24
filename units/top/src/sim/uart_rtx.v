// This is confidential and proprietary software which may be used only as
// authorized by a licensing agreement from Fraunhofer Institute of
// Microelectronic Circuits and Systems, Duisburg, Germany.
//
// In the event of publication, the following notice is applicable:
//
// (C) COPYRIGHT 2026 FRAUNHOFER INSTITUTE OF MICROELECTRONIC CIRCUITS
// AND SYSTEMS, DUISBURG, GERMANY. ALL RIGHTS RESERVED.
//
// The entire notice above must be reproduced on all authorized copies.
//
// Project  : DI-OWAS
// File     : uart_rtx.v
// Author   : S. Nolting
// Creation : 21.06.2026
// Abstract : Simple UART receiver & transmitter.

`timescale 1 ns/1 ps // time-unit = 1 ns, precision = 1 ps

module uart_rtx_receiver
#(
  parameter CLOCK_FREQ = 100000000, // clock frequency of <clk_i> in Hz
  parameter BAUD_RATE  = 19200      // target baud rate
)(
  input        clk_i,  // clock input, triggering on rising edge
  input        txd_i,  // UART transmit data
  output [7:0] data_o, // character data
  output       valid_o // character data valid when set
);

  // duration of a single bit
  localparam UART_BAUD_VAL = CLOCK_FREQ / BAUD_RATE;

  // receiver
  reg  [4:0] uart_rx_sync;     // synchronizer shift register
  reg  [8:0] uart_rx_sreg;     // data shift register
  reg        uart_rx_busy;     // busy flag
  integer    uart_rx_baud_cnt; // bit-sample counter for baud rate
  integer    uart_rx_bitcnt;   // bit counter: 8 data bits, 1 start bit

  // initialize because we don't have a real reset
  initial begin
    uart_rx_sync     = 5'b11111;
    uart_rx_busy     = 1'b0;
    uart_rx_sreg     = 9'b000000000;
    uart_rx_baud_cnt = UART_BAUD_VAL / 2;
    uart_rx_bitcnt   = 0;
  end

  // UART receiver
  always @(posedge clk_i) begin
    // synchronizer
    uart_rx_sync <= {uart_rx_sync[3:0], txd_i};
    // arbiter
    if (!uart_rx_busy) begin // idle
      uart_rx_busy     <= 0;
      uart_rx_baud_cnt <= UART_BAUD_VAL / 2;
      uart_rx_bitcnt   <= 9;
      if (uart_rx_sync[4:1] == 4'b1100) begin // start bit (falling edge)?
        uart_rx_busy <= 1;
      end
    end else begin
      if (uart_rx_baud_cnt == 0) begin
        if (uart_rx_bitcnt == 1) begin
          uart_rx_baud_cnt <= UART_BAUD_VAL / 2;
        end else begin
          uart_rx_baud_cnt <= UART_BAUD_VAL;
        end
        // sample 8 data bits and 1 start bit
        if (uart_rx_bitcnt == 0) begin
          uart_rx_busy <= 1'b0; // done
          if ((uart_rx_sreg[8:1] >= 32) && (uart_rx_sreg[8:1] <= 127)) begin // is a printable char?
            $write("%c", uart_rx_sreg[8:1]);
          end else if (uart_rx_sreg[8:1] == 10) begin // Linux line break?
            $display(""); // force terminal line break
          end
        end else begin
          uart_rx_sreg   <= {uart_rx_sync[4], uart_rx_sreg[8:1]};
          uart_rx_bitcnt <= uart_rx_bitcnt - 1;
        end
      end else begin
        uart_rx_baud_cnt <= uart_rx_baud_cnt - 1;
      end
    end
  end

  // character output
  assign data_o  = uart_rx_sreg[8:1];
  assign valid_o = ((uart_rx_baud_cnt == 0) && (uart_rx_bitcnt == 0)) ? 1'b1 : 1'b0; // valid

endmodule


// ****************************************************************************
// Simulation UART transmitter.
// ****************************************************************************

module uart_rtx_transmitter #(
  parameter CLOCK_FREQ = 100000000, // clock frequency of clk in Hz
  parameter BAUD_RATE  = 19200      // target baud rate
)(
  input  wire clk,
  input  wire nrst,
  input  wire [7:0] data_in,
  input  wire valid,
  output reg  tx,
  output reg  busy
);

  localparam TICKS   = CLOCK_FREQ / BAUD_RATE;

  reg [$clog2(TICKS)-1:0] counter;
  reg baud_tick;

  always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
      counter   <= 0;
      baud_tick <= 0;
    end else begin
      if (counter == TICKS-1) begin
        counter   <= 0;
        baud_tick <= 1;
      end else begin
        counter   <= counter + 1;
        baud_tick <= 0;
      end
    end
  end

  reg [3:0] bit_cnt;
  reg [9:0] shift_reg;

  localparam [1:0]
    IDLE = 2'd0,
    LOAD = 2'd1,
    SEND = 2'd2;

  reg [1:0] state, next_state;

  always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
      state     <= IDLE;
      tx        <= 1'b1;
      busy      <= 1'b0;
      bit_cnt   <= 4'd0;
      shift_reg <= 10'b1111111111;
    end else begin
      state <= next_state;
      case (state)
        IDLE: begin
          tx   <= 1'b1;
          busy <= 1'b0;
          if (valid) begin
            shift_reg <= {1'b1, data_in, 1'b0};
            bit_cnt   <= 4'd0;
          end
        end
        LOAD: begin
          busy <= 1'b1;
        end
        SEND: begin
          busy <= 1'b1;
          if (baud_tick) begin
            tx        <= shift_reg[0];
            shift_reg <= {1'b1, shift_reg[9:1]};
            bit_cnt   <= bit_cnt + 1;
          end
        end
      endcase
    end
  end

  always @* begin
    case (state)
      IDLE:    next_state = valid ? LOAD : IDLE;
      LOAD:    next_state = SEND;
      SEND:    next_state = (bit_cnt < 10) ? SEND : IDLE;
      default: next_state = IDLE;
    endcase
  end

endmodule
