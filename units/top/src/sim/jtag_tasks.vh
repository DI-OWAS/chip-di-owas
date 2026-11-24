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
// Project  : EUCA-APECS PIC opto-chiplet
// File     : jtag_tasks.vh
// Author   : S. Nolting
// Creation : 21.06.2026
// Abstract : Low-level JTAG task for accessing the RISC-V core.

  // ------------------------------------------------------
  // reset tap controller (to RUN_IDLE state)
  // ------------------------------------------------------
  task jtag_tap_reset;
  begin
    tdi <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
  end
  endtask

  // ------------------------------------------------------
  // write data to DM register via DMI
  // ------------------------------------------------------
  task jtag_dmi_write;
    input [6:0] addr;
    input [31:0] data;
    integer i;
  begin
    // goto IR_SHIFT
    tdi <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // Shift in address of DMI register (LSB to MSB)
    tms <= 1'b0;
    tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1;
    tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // goto IR_UPDATE
    tdi <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // goto DR_SHIFT
    tdi <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // shift in DMI address (7), data (32) and write command (2)
    tms <= 1'b0;
    tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= 1'b0;
    for (i=0; i<32; i=i+1) begin
      tdi <= data[i]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    end
    tdi <= addr[0]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= addr[1]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= addr[2]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= addr[3]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= addr[4]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tdi <= addr[5]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; // goto DR_EXIT1
    tdi <= addr[6]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // goto DR_UPDATE
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // goto RUN_IDLE + idle
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    for (i = 0; i < 10; i = i + 1) begin
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    end
  end
  endtask

  // ------------------------------------------------------
  // read data from DM register via DMI
  // ------------------------------------------------------
  task jtag_dmi_read;
    input  [6:0]  addr;
    output [31:0] result;
    reg    [1:0]  status;
    integer i;
  begin
    // RTI -> Select-DR -> Select-IR -> Capture-IR -> Shift-IR
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // Shift-IR: 5'b10001 = 0x11 (DMI), LSB first
    tms <= 1'b0; tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b1; tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // -> Exit1-IR
    // Exit1-IR -> Update-IR -> RTI
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // -> RTI

    // DR Scan: Read-Request
    // RTI -> Select-DR -> Capture-DR -> Shift-DR
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    // Shift 41 bits: op[1:0]=01(read), data[31:0]=0, addr[6:0]
    tms <= 1'b0; tdi <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // op[0]=1
    tms <= 1'b0; tdi <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // op[1]=0
    tdi <= 1'b0;
    for (i = 0; i < 32; i = i + 1) begin                                                               // data=0
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    end
    for (i = 0; i < 6; i = i + 1) begin                                                                // addr[5:0]
      tms <= 1'b0; tdi <= addr[i]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    end
    tms <= 1'b1; tdi <= addr[6]; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // -> Exit1-DR
    // Exit1-DR -> Update-DR -> RTI
    tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0; // -> RTI

    // Idle cycles in RTI
    for (i = 0; i < 10; i = i + 1) begin
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
    end

    // loop: read response until not busy
    status = 2'b11; // init als busy
    while (status == 2'b11) begin

      // Idle cycles in RTI
      for (i = 0; i < 10; i = i + 1) begin
        tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      end

      // DR-Scan: write NOP, read response
      tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      // Get status (op[1:0])
      tms <= 1'b0; tdi <= 1'b0;
      #(`JTAG_CLK_PERIOD/2) status[0] <= tdo; tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      #(`JTAG_CLK_PERIOD/2) status[1] <= tdo; tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      // Get data (data[31:0])
      for (i = 0; i < 31; i = i + 1) begin
        #(`JTAG_CLK_PERIOD/2) result[i] <= tdo; tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      end
      tms <= 1'b1;
      #(`JTAG_CLK_PERIOD/2) result[31] <= tdo; tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      // Exit1-DR -> Update-DR -> RTI
      tms <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;
      tms <= 1'b0; #(`JTAG_CLK_PERIOD/2) tck <= 1'b1; #(`JTAG_CLK_PERIOD/2) tck <= 1'b0;

      #(`JTAG_CLK_PERIOD);

    end

    if (status != 2'b00) begin
      $display("DMI READ WARNING: status = %b (addr=0x%02x)", status, addr);
    end

  end
  endtask

  // ------------------------------------------------------
  // reset RISC-V core (and let it run)
  // ------------------------------------------------------
  task jtag_riscv_reset;
  begin
    $display("[TB:jtag_riscv_reset] Resetting core...");
    jtag_dmi_write(7'h10, 32'h00000003); // ndmreset=1
    jtag_dmi_write(7'h10, 32'h00000001); // ndmreset=0
  end
  endtask

  // ------------------------------------------------------
  // Halt RISC-V core (enter debug mode)
  // ------------------------------------------------------
  task jtag_riscv_halt;
    reg [31:0] tmp;
  begin
    $display("[TB:jtag_riscv_halt] Halting CPU...");
    jtag_dmi_write(7'h10, 32'h80000001); // halt: dmstatus <- haltreq=1, dmactive=1
    jtag_dmi_read(7'h11, tmp);
    while (tmp[9] != 1'b1) begin // wait for allhalted = 1
      jtag_dmi_read(7'h11, tmp);
    end
    jtag_dmi_write(7'h10, 32'h00000001); // halt: dmstatus <- haltreq=0, dmactive=1
  end
  endtask

  // ------------------------------------------------------
  // RISC-V write data to memory address using s0/s1 regs
  // ------------------------------------------------------
  task jtag_riscv_memory_wr;
    input [31:0] addr;
    input [31:0] wdata;
    reg   [31:0] tmp;
  begin

    // Set memory address -> s0
    jtag_dmi_write(7'h04, addr);         // data0 = address
    jtag_dmi_write(7'h17, 32'h00231008); // command: transfer=1, write=1, regno=s0
    #1000;

    // Set memory data -> s1
    jtag_dmi_write(7'h04, wdata);        // data0 = data
    jtag_dmi_write(7'h17, 32'h00231009); // command: transfer=1, write=1, regno=s1
    #1000;

    // Setup program buffer (store)
    jtag_dmi_write(7'h20, 32'h00942023); // sw s1, 0(s0)
    jtag_dmi_write(7'h21, 32'h00100073); // ebreak
    #1000;

    // Trigger execution
    jtag_dmi_write(7'h17, 32'h00241000); // command: postexec=1, transfer=0
    #1000;

    // Wait while busy and check error status
    tmp = 32'h00000000;
    jtag_dmi_read(7'h16, tmp);
    while (tmp[12] == 1'b1) begin
      jtag_dmi_read(7'h16, tmp);
    end
    if (tmp[10:8] != 3'b000) begin
      $display("[TB:jtag_riscv_memory_wr] ERROR! Write command failed (0x%08x)! ADDR=0x%08x, WDATA=0x%08x", tmp, addr, wdata);
      $finish;
    end

    $display("[TB:jtag_riscv_memory_wr] MEM[0x%08h] <= 0x%08h", addr, wdata);

  end
  endtask

  // ------------------------------------------------------
  // RISC-V read data from memory address using s0/s1 regs
  // ------------------------------------------------------
  task jtag_riscv_memory_rd;
    input  [31:0] addr;
    output [31:0] rdata;
    reg    [31:0] tmp;
  begin
    // Set memory address -> s0
    jtag_dmi_write(7'h04, addr);         // data0 = address
    jtag_dmi_write(7'h17, 32'h00231008); // command: transfer=1, write=1, regno=s0
    #1000;

    // Setup program buffer (load)
    jtag_dmi_write(7'h20, 32'h00042483); // lw s1, 0(s0)
    jtag_dmi_write(7'h21, 32'h00100073); // ebreak
    #1000;

    // Command 1: only execute program buffer (load)
    jtag_dmi_write(7'h17, 32'h00241000); // postexec=1, transfer=0
    #1000;

    // Wait while busy
    tmp = 32'h00000000;
    jtag_dmi_read(7'h16, tmp);
    while (tmp[12] == 1'b1) begin
      jtag_dmi_read(7'h16, tmp);
    end
    if (tmp[10:8] != 3'b000) begin
      $display("[TB:jtag_riscv_memory_rd] ERROR! Execution failed!");
      $finish;
    end
    #1000;

    // Command 2: only copy s1 to data0 (NO postexec!)
    jtag_dmi_write(7'h17, 32'h00221009); // transfer=1, write=0, postexec=0, regno=s1
    #1000;

    // Wait while busy
    tmp = 32'h00000000;
    jtag_dmi_read(7'h16, tmp);
    while (tmp[12] == 1'b1) begin
      jtag_dmi_read(7'h16, tmp);
    end
    if (tmp[10:8] != 3'b000) begin
      $display("[TB:jtag_riscv_memory_rd] ERROR! Transfer failed!");
      $finish;
    end
    #1000;

    // Get data from data0
    jtag_dmi_read(7'h04, tmp);
    rdata = tmp;

    $display("[TB:jtag_riscv_memory_rd] MEM[0x%08h] => 0x%08h", addr, rdata);
  end
  endtask
