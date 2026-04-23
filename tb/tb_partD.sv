// ============================================================
// Part D Testbench — Full Integration
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Scenario 1: dmactive -> read dmstatus -> halt -> read x5
//             -> write x5 -> read-back -> resume
// Scenario 2: Exec Abs Cmd while running -> cmderr=4 -> halt
//             -> clear cmderr -> retry (GPR write)
// Scenario 3: Write mtvec CSR (0x305), read back, confirm
// ============================================================

`timescale 1ns/1ps

module tb_partD;

    logic clk, rst_n;

    // DMI
    logic        dmi_req_valid;
    logic [6:0]  dmi_req_addr;
    logic [31:0] dmi_req_data;
    logic [1:0]  dmi_req_op;
    logic        dmi_req_ready;
    logic        dmi_resp_valid;
    logic [31:0] dmi_resp_data;
    logic [1:0]  dmi_resp_resp;

    // Hart
    logic        halt_out, resume_out;
    logic        halted_stub, running_stub;
    logic        hart_reg_ren, hart_reg_wen;
    logic [15:0] hart_reg_regno;
    logic [31:0] hart_reg_wdata, hart_reg_rdata;
    logic        hart_reg_ack, hart_reg_err;

    // -------------------------------------------------------
    // DUT: debug_module_top
    // -------------------------------------------------------
    debug_module_top u_dm (
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
        .halt_out       (halt_out),
        .resume_out     (resume_out),
        .hart_halted    (halted_stub),
        .hart_running   (running_stub),
        .hart_reg_ren   (hart_reg_ren),
        .hart_reg_wen   (hart_reg_wen),
        .hart_reg_regno (hart_reg_regno),
        .hart_reg_wdata (hart_reg_wdata),
        .hart_reg_rdata (hart_reg_rdata),
        .hart_reg_ack   (hart_reg_ack),
        .hart_reg_err   (hart_reg_err)
    );

    // -------------------------------------------------------
    // Hart stub
    // -------------------------------------------------------
    hart_stub u_hart (
        .clk        (clk),
        .rst_n      (rst_n),
        .halt_req   (halt_out),
        .resume_req (resume_out),
        .halted     (halted_stub),
        .running    (running_stub),
        .reg_ren    (hart_reg_ren),
        .reg_wen    (hart_reg_wen),
        .reg_regno  (hart_reg_regno),
        .reg_wdata  (hart_reg_wdata),
        .reg_rdata  (hart_reg_rdata),
        .reg_ack    (hart_reg_ack),
        .reg_err    (hart_reg_err)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Helpers
    // -------------------------------------------------------
    integer pass_cnt = 0, fail_cnt = 0;

    task check32(input string label, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  %s : 0x%08h", label, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %s : got=0x%08h  exp=0x%08h", label, got, exp);
            fail_cnt++;
        end
    endtask

    task check1(input string label, input logic got, input logic exp);
        if (got === exp) begin
            $display("  PASS  %s : %b", label, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %s : got=%b  exp=%b", label, got, exp);
            fail_cnt++;
        end
    endtask

    // DMI write
    task dmi_write(input [6:0] addr, input [31:0] data);
        wait (dmi_req_ready);
        @(negedge clk);
        dmi_req_valid = 1; dmi_req_addr = addr;
        dmi_req_data  = data; dmi_req_op = 2'b10;
        @(negedge clk); dmi_req_valid = 0;
        wait (dmi_resp_valid);
        @(posedge clk);
    endtask

    // DMI read — returns data
    task dmi_read(input [6:0] addr, output [31:0] rdata);
        wait (dmi_req_ready);
        @(negedge clk);
        dmi_req_valid = 1; dmi_req_addr = addr;
        dmi_req_data  = 0; dmi_req_op = 2'b01;
        @(negedge clk); dmi_req_valid = 0;
        wait (dmi_resp_valid);
        rdata = dmi_resp_data;
        @(posedge clk);
    endtask

    // Issue abstract command via DMI and wait for busy=0 in abstractcs
    task abs_cmd(input [31:0] cmd, input [31:0] d0);
        logic [31:0] acs;
        // Write data0 first if needed
        if (d0 !== 32'hx)
            dmi_write(7'h04, d0);
        dmi_write(7'h17, cmd);
        // Poll abstractcs.busy (bit 12)
        repeat(20) begin
            dmi_read(7'h16, acs);
            if (!acs[12]) disable abs_cmd;
            @(posedge clk);
        end
        $display("  WARN  abs_cmd timeout waiting for busy=0");
    endtask

    logic [31:0] rd;

    // -------------------------------------------------------
    // Scenario 1: dmactive -> halt -> GPR read/write -> resume
    // -------------------------------------------------------
    task scenario1;
        $display("\n-- Scenario 1: dmactive -> halt -> read x5 -> write x5 -> resume --");

        // Enable DM
        dmi_write(7'h10, 32'h0000_0001);  // dmcontrol: dmactive=1
        dmi_read(7'h11, rd);
        check1("S1 dmstatus authenticated", rd[3], 1'b1);

        // Halt hart
        dmi_write(7'h10, 32'h8000_0001);  // haltreq=1, dmactive=1
        repeat(6) @(posedge clk);
        dmi_read(7'h11, rd);
        check1("S1 allhalted=1", rd[5], 1'b1);

        // Read x5 (gpr[5] init = 5*4 = 0x14)
        // cmd: cmdtype=0, aarsize=010, transfer=1, write=0, regno=0x1005
        abs_cmd(32'h0022_1005, 32'hx);
        dmi_read(7'h04, rd);
        check32("S1 GPR x5 read", rd, 32'h0000_0014);

        // Write x5 = 0xDEAD_1234
        // cmd: cmdtype=0, aarsize=010, transfer=1, write=1, regno=0x1005
        abs_cmd(32'h0023_1005, 32'hDEAD_1234);

        // Read x5 back
        abs_cmd(32'h0022_1005, 32'hx);
        dmi_read(7'h04, rd);
        check32("S1 GPR x5 write+readback", rd, 32'hDEAD_1234);

        // Resume hart
        dmi_write(7'h10, 32'h4000_0001);  // resumereq=1, dmactive=1
        repeat(6) @(posedge clk);
        dmi_read(7'h11, rd);
        check1("S1 allrunning=1 after resume", rd[7], 1'b1);
    endtask

    // -------------------------------------------------------
    // Scenario 2: cmd while running -> cmderr=4 -> halt -> clear -> retry
    // -------------------------------------------------------
    task scenario2;
        $display("\n-- Scenario 2: cmd while running -> cmderr=4 -> clear -> retry --");

        // Issue command while hart is RUNNING
        dmi_write(7'h17, 32'h0022_1003);  // read x3
        repeat(5) @(posedge clk);
        dmi_read(7'h16, rd);
        check32("S2 cmderr=4 in abstractcs", rd[10:8], 3'd4);

        // Halt hart
        dmi_write(7'h10, 32'h8000_0001);
        repeat(6) @(posedge clk);

        // Clear cmderr (W1C: write 0x700 to abstractcs [10:8])
        dmi_write(7'h16, 32'h0000_0700);
        dmi_read(7'h16, rd);
        check32("S2 cmderr cleared", rd[10:8], 3'd0);

        // Retry: read x3 (gpr[3] = 3*4 = 0xC)
        abs_cmd(32'h0022_1003, 32'hx);
        dmi_read(7'h04, rd);
        check32("S2 GPR x3 retry success", rd, 32'h0000_000C);
    endtask

    // -------------------------------------------------------
    // Scenario 3: Write mtvec CSR, read back
    // -------------------------------------------------------
    task scenario3;
        $display("\n-- Scenario 3: Write mtvec CSR (0x305), read back --");

        // Hart should be halted from scenario 2
        // Write mtvec = 0xCAFE_0004
        // cmd: cmdtype=0, aarsize=010, transfer=1, write=1, regno=0x0305
        abs_cmd(32'h0023_0305, 32'hCAFE_0004);

        // Read mtvec back
        abs_cmd(32'h0022_0305, 32'hx);
        dmi_read(7'h04, rd);
        check32("S3 mtvec CSR write+readback", rd, 32'hCAFE_0004);
    endtask

    // -------------------------------------------------------
    // Main
    // -------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_partD.vcd");
        $dumpvars(0, tb_partD);

        dmi_req_valid = 0; dmi_req_addr = 0;
        dmi_req_data  = 0; dmi_req_op   = 0;

        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n=== Part D Integration Tests ===");

        scenario1;
        scenario2;
        scenario3;

        $display("\n=== Results: %0d PASS, %0d FAIL ===\n", pass_cnt, fail_cnt);
        #20; $finish;
    end

    initial begin #500000; $display("TIMEOUT"); $finish; end

endmodule
