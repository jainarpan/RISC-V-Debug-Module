// ============================================================
// RISC-V Debug Module — Halt/Resume Handshake Controller
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Implements all 4 Part C requirements:
//   C1: haltreq=1 -> assert halt to hart -> wait for halted -> set allhalted
//   C2: resumereq=1 -> pulse resume to hart -> wait for running -> set allrunning
//   C3: haltreq + resumereq same cycle -> halt wins
//   C4: hart halted=0 spontaneously (NMI) -> DM detects and updates dmstatus
// ============================================================

module halt_resume_ctrl (
    input  logic clk,
    input  logic rst_n,

    // --- from dmcontrol register ---
    input  logic haltreq,
    input  logic resumereq,

    // --- to/from hart ---
    output logic halt_out,    // asserted to request hart halt
    output logic resume_out,  // single-cycle pulse to request resume

    input  logic hart_halted, // hart asserts when in debug mode
    input  logic hart_running,// hart asserts when running normally

    // --- to dmstatus register ---
    output logic allhalted,
    output logic anyhalted,
    output logic allrunning,
    output logic anyrunning
);

    // -------------------------------------------------------
    // C3: halt wins over resume in same cycle
    // -------------------------------------------------------
    wire effective_haltreq  =  haltreq;
    wire effective_resumereq = resumereq && !haltreq;   // halt wins

    // -------------------------------------------------------
    // halt_out: level signal — stays high while haltreq held
    // Hart is expected to halt; we deassert once halted
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            halt_out <= 1'b0;
        else if (effective_haltreq && !hart_halted)
            halt_out <= 1'b1;
        else if (hart_halted)
            halt_out <= 1'b0;
    end

    // -------------------------------------------------------
    // resume_out: single-cycle pulse when resumereq rises
    // and hart is currently halted
    // -------------------------------------------------------
    logic resumereq_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            resumereq_prev <= 1'b0;
        else
            resumereq_prev <= effective_resumereq;
    end

    // Pulse resume for one cycle on rising edge of effective_resumereq
    assign resume_out = effective_resumereq && !resumereq_prev && hart_halted;

    // -------------------------------------------------------
    // dmstatus flags — directly reflect hart signals
    // C4: spontaneous deassertion of halted is caught here
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            allhalted  <= 1'b0;
            anyhalted  <= 1'b0;
            allrunning <= 1'b0;
            anyrunning <= 1'b0;
        end else begin
            allhalted  <= hart_halted;
            anyhalted  <= hart_halted;
            allrunning <= hart_running;
            anyrunning <= hart_running;
        end
    end

endmodule
