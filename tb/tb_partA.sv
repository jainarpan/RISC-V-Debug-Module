// ============================================================
// Part A Testbench — DMI Slave + DM Register File
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Tests:
//   1. DMI write to dmcontrol  (set dmactive=1)
//   2. DMI read  of dmstatus   (check version field)
//   3. DMI write then read-after-write to data0
//   4. Reset release: writes ignored until dmactive=1
//   5. Back-to-back DMI transactions
// ============================================================

`timescale 1ns/1ps

module tb_partA;

    // -------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------
    logic        clk, rst_n;

    // DMI
    logic        dmi_req_valid;
    logic [6:0]  dmi_req_addr;
    logic [31:0] dmi_req_data;
    logic [1:0]  dmi_req_op;
    logic        dmi_req_ready;
    logic        dmi_resp_valid;
    logic [31:0] dmi_resp_data;
    logic [1:0]  dmi_resp_resp;

    // Internal bus (DMI slave → reg file)
    logic        dm_wen, dm_ren;
    logic [6:0]  dm_addr;
    logic [31:0] dm_wdata, dm_rdata;
    logic        dm_error;

    // Reg file status inputs (tie off for Part A)
    logic        allhalted=0, allrunning=0, anyhalted=0, anyrunning=0;
    logic [2:0]  cmderr_in=0;
    logic        cmderr_wen=0, busy_in=0, clear_cmderr=0;
    logic [31:0] data0_in=0;
    logic        data0_wen=0;

    // Reg file outputs
    logic        dmactive;
    logic        haltreq, resumereq;
    logic [31:0] command_out;
    logic        command_wen;
    logic [31:0] data0_out, data1_out;

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    dmi_slave u_dmi (
        .clk            (clk),
        .rst_n          (rst_n),
        .dmi_req_valid  (dmi_req_valid),
        .dmi_req_addr   (dmi_req_addr),
        .dmi_req_data   (dmi_req_data),
        .dmi_req_op     (dmi_req_op),
        .dmi_req_ready  (dmi_req_ready),
        .dmi_resp_valid (dmi_resp_valid),
        .dmi_resp_data  (dmi_resp_data),
        .dmi_resp_resp  (dmi_resp_resp),
        .dm_wen         (dm_wen),
        .dm_ren         (dm_ren),
        .dm_addr        (dm_addr),
        .dm_wdata       (dm_wdata),
        .dm_rdata       (dm_rdata),
        .dm_error       (dm_error)
    );

    dm_regfile u_regfile (
        .clk            (clk),
        .rst_n          (rst_n),
        .dm_wen         (dm_wen),
        .dm_ren         (dm_ren),
        .dm_addr        (dm_addr),
        .dm_wdata       (dm_wdata),
        .dm_rdata       (dm_rdata),
        .dm_error       (dm_error),
        .allhalted      (allhalted),
        .allrunning     (allrunning),
        .anyhalted      (anyhalted),
        .anyrunning     (anyrunning),
        .cmderr_in      (cmderr_in),
        .cmderr_wen     (cmderr_wen),
        .busy_in        (busy_in),
        .clear_cmderr   (clear_cmderr),
        .dmactive       (dmactive),
        .haltreq        (haltreq),
        .resumereq      (resumereq),
        .command_out    (command_out),
        .command_wen    (command_wen),
        .data0_out      (data0_out),
        .data1_out      (data1_out),
        .data0_in       (data0_in),
        .data0_wen      (data0_wen)
    );

    // -------------------------------------------------------
    // Clock: 10 ns period
    // -------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Task: send one DMI transaction and wait for response
    // -------------------------------------------------------
    task automatic dmi_write(input [6:0] addr, input [31:0] data);
        @(posedge clk);
        wait (dmi_req_ready);
        dmi_req_valid = 1'b1;
        dmi_req_addr  = addr;
        dmi_req_data  = data;
        dmi_req_op    = 2'b10;  // write
        @(posedge clk);
        dmi_req_valid = 1'b0;
        wait (dmi_resp_valid);
        @(posedge clk);
    endtask

    task automatic dmi_read(input [6:0] addr, output [31:0] rdata);
        @(posedge clk);
        wait (dmi_req_ready);
        dmi_req_valid = 1'b1;
        dmi_req_addr  = addr;
        dmi_req_data  = 32'h0;
        dmi_req_op    = 2'b01;  // read
        @(posedge clk);
        dmi_req_valid = 1'b0;
        wait (dmi_resp_valid);
        rdata = dmi_resp_data;
        @(posedge clk);
    endtask

    // -------------------------------------------------------
    // Test flow
    // -------------------------------------------------------
    logic [31:0] rdata;
    integer pass_count = 0;
    integer fail_count = 0;

    task check(input string label, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  %s : got=0x%08h", label, got);
            pass_count++;
        end else begin
            $display("  FAIL  %s : got=0x%08h  exp=0x%08h", label, got, exp);
            fail_count++;
        end
    endtask

    initial begin
        // Dump VCD for waveform viewer
        $dumpfile("sim/tb_partA.vcd");
        $dumpvars(0, tb_partA);

        // Default inputs
        dmi_req_valid = 0;
        dmi_req_addr  = 0;
        dmi_req_data  = 0;
        dmi_req_op    = 0;

        // -----------------------------------------------
        // Apply reset
        // -----------------------------------------------
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("\n=== Part A Tests ===\n");

        // -----------------------------------------------
        // Test A3: writes blocked while dmactive=0
        // -----------------------------------------------
        $display("-- A3: dmactive=0, write to data0 should be ignored --");
        dmi_write(7'h04, 32'hDEAD_BEEF);   // data0 addr
        dmi_read(7'h04, rdata);
        check("data0 ignored (dmactive=0)", rdata, 32'h0000_0000);

        // -----------------------------------------------
        // Test A1/A2: enable DM by writing dmcontrol[0]=1
        // -----------------------------------------------
        $display("-- A1/A2: enable DM (dmactive=1) --");
        dmi_write(7'h10, 32'h0000_0001);   // dmcontrol: dmactive=1
        dmi_read(7'h10, rdata);
        check("dmcontrol dmactive=1", rdata[0], 1'b1);

        // -----------------------------------------------
        // Test A2: read dmstatus version field
        // -----------------------------------------------
        $display("-- A2: dmstatus version check --");
        dmi_read(7'h11, rdata);
        check("dmstatus version=2", rdata[2:0], 3'b010);
        check("dmstatus authenticated=1", rdata[3], 1'b1);

        // -----------------------------------------------
        // Test A1: write/read-after-write to data0
        // -----------------------------------------------
        $display("-- A1: write then read-after-write data0 --");
        dmi_write(7'h04, 32'hCAFE_1234);
        dmi_read(7'h04, rdata);
        check("data0 read-after-write", rdata, 32'hCAFE_1234);

        // -----------------------------------------------
        // Test A1: write/read data1
        // -----------------------------------------------
        $display("-- A1: write then read data1 --");
        dmi_write(7'h05, 32'hABCD_EF01);
        dmi_read(7'h05, rdata);
        check("data1 read-after-write", rdata, 32'hABCD_EF01);

        // -----------------------------------------------
        // Test A1: haltreq bit in dmcontrol
        // -----------------------------------------------
        $display("-- A1: set haltreq --");
        dmi_write(7'h10, 32'h8000_0001);   // haltreq=1, dmactive=1
        dmi_read(7'h10, rdata);
        check("dmcontrol haltreq=1", rdata[31], 1'b1);

        // -----------------------------------------------
        // Test A2: hartinfo reads as 0
        // -----------------------------------------------
        $display("-- A2: hartinfo constant --");
        dmi_read(7'h12, rdata);
        check("hartinfo=0", rdata, 32'h0);

        // -----------------------------------------------
        // Test A1: back-to-back transactions
        // -----------------------------------------------
        $display("-- A1: back-to-back: write data0, then data1 --");
        dmi_write(7'h04, 32'h1111_1111);
        dmi_write(7'h05, 32'h2222_2222);
        dmi_read(7'h04, rdata);
        check("back-to-back data0", rdata, 32'h1111_1111);
        dmi_read(7'h05, rdata);
        check("back-to-back data1", rdata, 32'h2222_2222);

        // -----------------------------------------------
        // Summary
        // -----------------------------------------------
        $display("\n=== Results: %0d PASS, %0d FAIL ===\n", pass_count, fail_count);

        #20;
        $finish;
    end

    // Safety timeout
    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
