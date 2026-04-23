// ============================================================
// RISC-V Debug Module — Hart Stub (simulated CPU)
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// This is a behavioural stub — not a real CPU.
// It holds a 32-entry GPR file and 4 CSRs.
// It responds to halt/resume and register read/write requests
// from the Debug Module via a simple handshake bus.
// ============================================================

module hart_stub (
    input  logic        clk,
    input  logic        rst_n,

    // --- Halt / Resume from DM ---
    input  logic        halt_req,      // DM wants hart to halt
    input  logic        resume_req,    // DM wants hart to resume
    output logic        halted,        // hart is in debug mode
    output logic        running,       // hart is running normally

    // --- Register access bus from DM ---
    input  logic        reg_ren,       // read request
    input  logic        reg_wen,       // write request
    input  logic [15:0] reg_regno,     // 0x1000-0x101F = GPR x0-x31
                                       // 0x0300,0x0341,0x0342,0x0305 = CSRs
    input  logic [31:0] reg_wdata,
    output logic [31:0] reg_rdata,
    output logic        reg_ack,       // handshake: access complete
    output logic        reg_err        // 1 = unknown register
);

    // -------------------------------------------------------
    // Internal state
    // -------------------------------------------------------
    logic [31:0] gpr [0:31];   // x0–x31  (x0 always 0)
    logic [31:0] mstatus;      // CSR 0x300
    logic [31:0] mepc;         // CSR 0x341
    logic [31:0] mcause;       // CSR 0x342
    logic [31:0] mtvec;        // CSR 0x305

    typedef enum logic [1:0] {
        HART_RUNNING = 2'b00,
        HART_HALTING = 2'b01,
        HART_HALTED  = 2'b10,
        HART_RESUMING= 2'b11
    } hart_state_t;

    hart_state_t hstate;

    // -------------------------------------------------------
    // Halt / Resume FSM  (takes 1 cycle to respond)
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hstate <= HART_RUNNING;
        end else begin
            case (hstate)
                HART_RUNNING:  if (halt_req)   hstate <= HART_HALTING;
                HART_HALTING:                  hstate <= HART_HALTED;   // 1-cycle latency
                HART_HALTED:   if (resume_req) hstate <= HART_RESUMING;
                HART_RESUMING:                 hstate <= HART_RUNNING;
            endcase
        end
    end

    assign halted  = (hstate == HART_HALTED);
    assign running = (hstate == HART_RUNNING);

    // -------------------------------------------------------
    // Register initialisation
    // -------------------------------------------------------
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i++)
                gpr[i] <= 32'(i * 4);   // fill with recognisable values
            mstatus <= 32'h0000_1800;
            mepc    <= 32'h0000_0000;
            mcause  <= 32'h0000_0000;
            mtvec   <= 32'h0000_0000;
        end else begin
            // Write path (only while halted)
            if (reg_wen && halted) begin
                if (reg_regno >= 16'h1000 && reg_regno <= 16'h101F)
                    if (reg_regno[4:0] != 5'b0)   // x0 stays 0
                        gpr[reg_regno[4:0]] <= reg_wdata;
                case (reg_regno)
                    16'h0300: mstatus <= reg_wdata;
                    16'h0341: mepc    <= reg_wdata;
                    16'h0342: mcause  <= reg_wdata;
                    16'h0305: mtvec   <= reg_wdata;
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // Read path  (combinational — ack on same cycle)
    // -------------------------------------------------------
    always_comb begin
        reg_rdata = 32'h0;
        reg_err   = 1'b0;
        reg_ack   = (reg_ren || reg_wen);   // always single-cycle ack

        if (reg_ren) begin
            if (reg_regno >= 16'h1000 && reg_regno <= 16'h101F)
                reg_rdata = gpr[reg_regno[4:0]];
            else case (reg_regno)
                16'h0300: reg_rdata = mstatus;
                16'h0341: reg_rdata = mepc;
                16'h0342: reg_rdata = mcause;
                16'h0305: reg_rdata = mtvec;
                default: begin
                    reg_rdata = 32'hDEAD_BEEF;
                    reg_err   = 1'b1;
                end
            endcase
        end
    end

endmodule
