// ============================================================
// Part C Testbench — Halt/Resume Handshake
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Required waveforms / tests:
//   C1: haltreq -> halt -> halted -> allhalted
//   C2: resumereq -> resume -> running -> allrunning
//   C3: haltreq + resumereq same cycle -> halt wins
//   C4: Hart un-halts spontaneously (NMI) -> dmstatus reflects
// ============================================================

`timescale 1ns/1ps

module tb_partC;

    logic clk, rst_n;

    // halt_resume_ctrl ports
    logic haltreq, resumereq;
    logic halt_out, resume_out;
    logic hart_halted_in, hart_running_in;
    logic allhalted, anyhalted, allrunning, anyrunning;

    // hart_stub ports
    logic halt_req_stub, resume_req_stub;
    logic halted_stub, running_stub;

    // -------------------------------------------------------
    // DUTs
    // -------------------------------------------------------
    halt_resume_ctrl u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .haltreq     (haltreq),
        .resumereq   (resumereq),
        .halt_out    (halt_out),
        .resume_out  (resume_out),
        .hart_halted (hart_halted_in),
        .hart_running(hart_running_in),
        .allhalted   (allhalted),
        .anyhalted   (anyhalted),
        .allrunning  (allrunning),
        .anyrunning  (anyrunning)
    );

    hart_stub u_hart (
        .clk        (clk),
        .rst_n      (rst_n),
        .halt_req   (halt_req_stub),
        .resume_req (resume_req_stub),
        .halted     (halted_stub),
        .running    (running_stub),
        // Register bus not used in Part C
        .reg_ren    (1'b0),
        .reg_wen    (1'b0),
        .reg_regno  (16'h0),
        .reg_wdata  (32'h0),
        .reg_rdata  (),
        .reg_ack    (),
        .reg_err    ()
    );

    // Connect controller outputs to hart stub inputs
    assign halt_req_stub   = halt_out;
    assign resume_req_stub = resume_out;
    assign hart_halted_in  = halted_stub;
    assign hart_running_in = running_stub;

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Helpers
    // -------------------------------------------------------
    integer pass_cnt = 0, fail_cnt = 0;

    task check(input string label, input logic got, input logic exp);
        if (got === exp) begin
            $display("  PASS  %s : %b", label, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %s : got=%b  exp=%b", label, got, exp);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_partC.vcd");
        $dumpvars(0, tb_partC);

        haltreq = 0; resumereq = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n=== Part C Tests ===\n");

        // =====================================================
        // C1: haltreq -> halt_out -> hart halts -> allhalted
        // =====================================================
        $display("-- C1: haltreq -> halt -> halted -> allhalted --");
        @(negedge clk); haltreq = 1'b1;
        @(posedge clk);  // latch haltreq
        @(posedge clk);  // halt_out registers now
        check("C1 halt_out asserted after haltreq", halt_out, 1'b1);
        @(posedge clk);  // hart stub: RUNNING->HALTING
        @(posedge clk);  // hart stub: HALTING->HALTED
        repeat(2) @(posedge clk); // allhalted propagates
        check("C1 allhalted=1", allhalted, 1'b1);
        check("C1 allrunning=0", allrunning, 1'b0);
        @(negedge clk); haltreq = 1'b0;
        @(posedge clk);

        // =====================================================
        // C2: resumereq -> resume_out pulse -> hart runs -> allrunning
        // =====================================================
        $display("-- C2: resumereq -> resume -> running -> allrunning --");
        @(negedge clk); resumereq = 1'b1;
        @(posedge clk);  // resume_out pulse generated
        check("C2 resume_out pulsed", resume_out, 1'b1);
        @(negedge clk); resumereq = 1'b0;
        @(posedge clk);  // hart: HALTED->RESUMING
        @(posedge clk);  // hart: RESUMING->RUNNING
        repeat(2) @(posedge clk);
        check("C2 allrunning=1", allrunning, 1'b1);
        check("C2 allhalted=0", allhalted, 1'b0);

        // =====================================================
        // C3: haltreq + resumereq same cycle -> halt wins
        // Issue while hart is RUNNING (resume the hart first)
        // =====================================================
        $display("-- C3: haltreq+resumereq together -> halt wins --");
        // Resume the hart so it is running
        @(negedge clk); resumereq = 1'b1;
        @(posedge clk); @(negedge clk); resumereq = 1'b0;
        repeat(4) @(posedge clk);
        // Hart is now running; assert both simultaneously
        @(negedge clk); haltreq = 1'b1; resumereq = 1'b1;
        @(posedge clk);  // latch inputs
        @(posedge clk);  // halt_out registers
        // halt wins: halt_out should be high, resume_out low
        check("C3 halt wins: halt_out=1",  halt_out,  1'b1);
        check("C3 halt wins: resume_out=0", resume_out, 1'b0);
        @(negedge clk); haltreq = 1'b0; resumereq = 1'b0;
        repeat(4) @(posedge clk);

        // =====================================================
        // C4: Spontaneous un-halt (NMI) -> dmstatus detects
        // =====================================================
        $display("-- C4: Spontaneous un-halt (NMI sim) -> dmstatus updates --");
        // Ensure halted first
        @(negedge clk); haltreq = 1'b1;
        repeat(5) @(posedge clk);
        @(negedge clk); haltreq = 1'b0;
        check("C4 setup: allhalted before NMI", allhalted, 1'b1);
        // Simulate NMI: force hart stub back to running by asserting resume_req directly
        // (bypass controller — simulate external event)
        force u_hart.hstate = 2'b11;  // HART_RESUMING
        @(posedge clk);
        release u_hart.hstate;
        // Hart moves to RUNNING naturally next cycle
        repeat(3) @(posedge clk);
        check("C4 allhalted=0 after NMI", allhalted, 1'b0);
        check("C4 allrunning=1 after NMI", allrunning, 1'b1);

        $display("\n=== Results: %0d PASS, %0d FAIL ===\n", pass_cnt, fail_cnt);
        #20; $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
