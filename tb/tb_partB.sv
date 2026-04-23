// ============================================================
// Part B Testbench — Abstract Command FSM  [v2 - fixed timing]
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Required scenarios:
//   (a) Successful GPR read  (x5 = regno 0x1005)
//   (b) Successful CSR write (mtvec = regno 0x0305)
//   (c) Error path: write command while hart is RUNNING -> cmderr=4
// ============================================================

`timescale 1ns/1ps

module tb_partB;

    logic clk, rst_n;

    // --- FSM ports ---
    logic        command_wen;
    logic [31:0] command_reg;
    logic [31:0] data0_reg;
    logic        hart_halted;

    logic        hart_reg_ren, hart_reg_wen;
    logic [15:0] hart_reg_regno;
    logic [31:0] hart_reg_wdata;
    logic [31:0] hart_reg_rdata;
    logic        hart_reg_ack, hart_reg_err;

    logic [31:0] data0_in;
    logic        data0_wen;
    logic [2:0]  cmderr_out;
    logic        cmderr_wen;
    logic        busy_out;

    // --- Hart stub ports ---
    logic        halt_req, resume_req;
    logic        halted, running;
    logic        stub_reg_ren, stub_reg_wen;
    logic [15:0] stub_reg_regno;
    logic [31:0] stub_reg_wdata;
    logic [31:0] stub_reg_rdata;
    logic        stub_reg_ack, stub_reg_err;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    abs_cmd_fsm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .command_wen     (command_wen),
        .command_reg     (command_reg),
        .data0_reg       (data0_reg),
        .hart_halted     (hart_halted),
        .hart_reg_ren    (hart_reg_ren),
        .hart_reg_wen    (hart_reg_wen),
        .hart_reg_regno  (hart_reg_regno),
        .hart_reg_wdata  (hart_reg_wdata),
        .hart_reg_rdata  (hart_reg_rdata),
        .hart_reg_ack    (hart_reg_ack),
        .hart_reg_err    (hart_reg_err),
        .data0_in        (data0_in),
        .data0_wen       (data0_wen),
        .cmderr_out      (cmderr_out),
        .cmderr_wen      (cmderr_wen),
        .busy_out        (busy_out)
    );

    hart_stub u_hart (
        .clk        (clk),
        .rst_n      (rst_n),
        .halt_req   (halt_req),
        .resume_req (resume_req),
        .halted     (halted),
        .running    (running),
        .reg_ren    (stub_reg_ren),
        .reg_wen    (stub_reg_wen),
        .reg_regno  (stub_reg_regno),
        .reg_wdata  (stub_reg_wdata),
        .reg_rdata  (stub_reg_rdata),
        .reg_ack    (stub_reg_ack),
        .reg_err    (stub_reg_err)
    );

    // Wire FSM bus → hart stub
    assign stub_reg_ren   = hart_reg_ren;
    assign stub_reg_wen   = hart_reg_wen;
    assign stub_reg_regno = hart_reg_regno;
    assign stub_reg_wdata = hart_reg_wdata;
    assign hart_reg_rdata = stub_reg_rdata;
    assign hart_reg_ack   = stub_reg_ack;
    assign hart_reg_err   = stub_reg_err;

    // Connect halted signal
    assign hart_halted = halted;

    // -------------------------------------------------------
    // Clock
    // -------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Latch data0 whenever FSM writes it (mimics dm_regfile)
    // -------------------------------------------------------
    logic [31:0] tb_data0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) tb_data0 <= 32'h0;
        else if (data0_wen) tb_data0 <= data0_in;
    end

    // Latch cmderr whenever FSM pulses cmderr_wen
    logic [2:0] tb_cmderr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) tb_cmderr <= 3'h0;
        else if (cmderr_wen) tb_cmderr <= cmderr_out;
    end

    // -------------------------------------------------------
    // Helpers
    // -------------------------------------------------------
    integer pass_cnt = 0, fail_cnt = 0;

    task check(input string label, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS  %s : 0x%08h", label, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %s : got=0x%08h  exp=0x%08h", label, got, exp);
            fail_cnt++;
        end
    endtask

    // Issue command and wait for FSM to return to IDLE
    // Works even when FSM errors out immediately (busy may never rise)
    task run_cmd(input [31:0] cmd, input [31:0] d0);
        wait (!busy_out);
        @(negedge clk);
        command_reg = cmd;
        data0_reg   = d0;
        command_wen = 1'b1;
        @(negedge clk);
        command_wen = 1'b0;
        // Give FSM at least 8 cycles to complete (covers IDLE->DECODE->EXEC->DONE->IDLE)
        repeat(8) @(posedge clk);
        // Then wait until definitively idle
        wait (!busy_out);
        repeat(2) @(posedge clk);
    endtask

    // -------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------
    initial begin
        $dumpfile("sim/tb_partB.vcd");
        $dumpvars(0, tb_partB);

        command_wen = 0; command_reg = 0; data0_reg = 0;
        halt_req = 0; resume_req = 0;

        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n=== Part B Tests ===\n");

        // =====================================================
        // (c) Error: command while hart RUNNING -> cmderr=4
        // =====================================================
        $display("-- (c) Error: command while hart RUNNING (cmderr=4) --");
        // cmdtype=0, aarsize=010, transfer=1, write=0, regno=0x1005 -> 0x0022_1005
        run_cmd(32'h0022_1005, 32'h0);
        check("cmderr=4 (running)", {29'b0, tb_cmderr}, 32'h4);

        // =====================================================
        // Halt the hart
        // =====================================================
        $display("-- Halting hart --");
        @(negedge clk); halt_req = 1'b1;
        @(negedge clk); halt_req = 1'b0;
        repeat(4) @(posedge clk);
        $display("  INFO  halted=%b", halted);

        // =====================================================
        // (a) GPR read: x5 — gpr[5] initialised to 5*4=0x14
        // =====================================================
        $display("-- (a) GPR read: x5 (regno=0x1005) --");
        run_cmd(32'h0022_1005, 32'h0);
        check("GPR x5 read into data0", tb_data0, 32'h0000_0014);

        // =====================================================
        // (b) CSR write mtvec (0x0305) then read back
        // =====================================================
        $display("-- (b) CSR write: mtvec (regno=0x0305) value=0xBEEF0000 --");
        // write: cmdtype=0 aarsize=010 transfer=1 write=1 regno=0x0305 -> 0x0023_0305
        run_cmd(32'h0023_0305, 32'hBEEF_0000);
        // read back: write=0 -> 0x0022_0305
        run_cmd(32'h0022_0305, 32'h0);
        check("CSR mtvec write+readback", tb_data0, 32'hBEEF_0000);

        $display("\n=== Results: %0d PASS, %0d FAIL ===\n", pass_cnt, fail_cnt);
        #20; $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
