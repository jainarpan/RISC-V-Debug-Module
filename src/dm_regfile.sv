// ============================================================
// RISC-V Debug Module — DM Register File
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Implements the following DM registers (RISC-V Debug Spec 0.13.2 §3.12):
//   0x04  data0      — abstract data register 0
//   0x05  data1      — abstract data register 1
//   0x10  dmcontrol  — DM control
//   0x11  dmstatus   — DM status  (read-only fields)
//   0x12  hartinfo   — hart info  (read-only, constant)
//   0x16  abstractcs — abstract command status
//   0x17  command    — abstract command trigger
//
// Reset rule (A3):
//   dmactive=0 on reset. All other registers held in reset
//   until dmactive=1. Writes to any register except dmcontrol
//   are ignored while dmactive=0.
// ============================================================

module dm_regfile (
    input  logic        clk,
    input  logic        rst_n,

    // --- from DMI slave ---
    input  logic        dm_wen,
    input  logic        dm_ren,
    input  logic [6:0]  dm_addr,
    input  logic [31:0] dm_wdata,
    output logic [31:0] dm_rdata,
    output logic        dm_error,    // 1 = unsupported address

    // --- status inputs (driven by hart handshake / FSM) ---
    input  logic        allhalted,
    input  logic        allrunning,
    input  logic        anyhalted,
    input  logic        anyrunning,
    input  logic [2:0]  cmderr_in,   // written by abstract FSM
    input  logic        cmderr_wen,  // abstract FSM sets cmderr
    input  logic        busy_in,     // abstract FSM busy flag
    input  logic        clear_cmderr,// debugger write 1 to abstractcs clears cmderr

    // --- control outputs to rest of DM ---
    output logic        dmactive,
    output logic        haltreq,
    output logic        resumereq,
    output logic [31:0] command_out, // latched command word
    output logic        command_wen, // pulse when command written
    output logic [31:0] data0_out,
    output logic [31:0] data1_out,
    input  logic [31:0] data0_in,    // abstract FSM may update data0
    input  logic        data0_wen    // abstract FSM updates data0
);

    // -------------------------------------------------------
    // Register storage
    // -------------------------------------------------------
    logic [31:0] reg_data0;
    logic [31:0] reg_data1;
    logic [31:0] reg_dmcontrol;
    logic [31:0] reg_abstractcs;
    logic [31:0] reg_command;

    // hartinfo is constant (single hart, no nscratch, no dataaccess)
    localparam logic [31:0] HARTINFO_CONST = 32'h0000_0000;

    // -------------------------------------------------------
    // dmactive convenience
    // -------------------------------------------------------
    assign dmactive = reg_dmcontrol[0];   // bit 0 of dmcontrol

    // -------------------------------------------------------
    // dmcontrol write (always writable, even while dmactive=0)
    // bit 31: haltreq, bit 30: resumereq, bit 0: dmactive
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_dmcontrol <= 32'h0000_0000;  // dmactive=0 on reset
        else if (dm_wen && dm_addr == 7'h10)
            // mask reserved bits — keep only haltreq[31], resumereq[30], dmactive[0]
            reg_dmcontrol <= {dm_wdata[31:1], dm_wdata[0]};
    end

    assign haltreq   = reg_dmcontrol[31];
    assign resumereq = reg_dmcontrol[30];

    // -------------------------------------------------------
    // data0 — writable by debugger (if dmactive) and by FSM
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_data0 <= '0;
        else if (data0_wen)                               // FSM updates after read
            reg_data0 <= data0_in;
        else if (dm_wen && dm_addr == 7'h04 && dmactive)
            reg_data0 <= dm_wdata;
    end

    // -------------------------------------------------------
    // data1 — writable by debugger only
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_data1 <= '0;
        else if (dm_wen && dm_addr == 7'h05 && dmactive)
            reg_data1 <= dm_wdata;
    end

    // -------------------------------------------------------
    // abstractcs
    //   [31:24] progbufsize = 0  (no program buffer)
    //   [12]    busy             (set/clear by FSM)
    //   [10:8]  cmderr           (set by FSM, cleared by debugger writing 0x7 mask)
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_abstractcs <= 32'h0000_0000;
        end else begin
            // FSM updates busy and cmderr
            if (cmderr_wen)
                reg_abstractcs[10:8] <= cmderr_in;
            if (dm_wen && dm_addr == 7'h16 && dmactive) begin
                // W1C on cmderr: writing 1s to [10:8] clears them
                reg_abstractcs[10:8] <= reg_abstractcs[10:8] & ~dm_wdata[10:8];
            end
            reg_abstractcs[12] <= busy_in;
        end
    end

    // -------------------------------------------------------
    // command — write triggers FSM; reading returns last written
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reg_command <= '0;
        else if (dm_wen && dm_addr == 7'h17 && dmactive)
            reg_command <= dm_wdata;
    end

    // command_wen: pulse for exactly one cycle when command is written
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            command_wen <= 1'b0;
        else
            command_wen <= (dm_wen && dm_addr == 7'h17 && dmactive);
    end

    // -------------------------------------------------------
    // dmstatus — read-only status register
    //   [17] allresumeack = allrunning (simplified)
    //   [16] anyresumeack
    //   [11] allnonexistent = 0
    //   [10] anynonexistent = 0
    //   [9]  allunavail = 0
    //   [8]  anyunavail = 0
    //   [7]  allrunning
    //   [6]  anyrunning
    //   [5]  allhalted
    //   [4]  anyhalted
    //   [3]  authenticated = 1 (always)
    //   [2]  authbusy = 0
    //   [1]  devtreevalid = 0
    //   [0]  version = 2 (debug spec 0.13)
    // -------------------------------------------------------
    function automatic logic [31:0] build_dmstatus(
        input logic ahalted, arunning, anyh, anyr
    );
        build_dmstatus = {
            14'b0,
            arunning, anyr,   // [17:16] resumeack
            4'b0,             // [15:12]
            1'b0, 1'b0,       // [11:10] nonexistent
            1'b0, 1'b0,       // [9:8]   unavail
            arunning, anyr,   // [7:6]   running
            ahalted,  anyh,   // [5:4]   halted
            1'b1,             // [3]     authenticated
            3'b010            // [2:0]   version=2
        };
    endfunction

    // -------------------------------------------------------
    // Read mux
    // -------------------------------------------------------
    always_comb begin
        dm_rdata = 32'h0;
        dm_error = 1'b0;
        if (dm_ren) begin
            case (dm_addr)
                7'h04:   dm_rdata = reg_data0;
                7'h05:   dm_rdata = reg_data1;
                7'h10:   dm_rdata = reg_dmcontrol;
                7'h11:   dm_rdata = build_dmstatus(allhalted, allrunning, anyhalted, anyrunning);
                7'h12:   dm_rdata = HARTINFO_CONST;
                7'h16:   dm_rdata = reg_abstractcs;
                7'h17:   dm_rdata = reg_command;
                default: begin
                    dm_rdata = 32'h0;
                    dm_error = 1'b1;
                end
            endcase
        end
    end

    // -------------------------------------------------------
    // Output connections
    // -------------------------------------------------------
    assign command_out = reg_command;
    assign data0_out   = reg_data0;
    assign data1_out   = reg_data1;

endmodule
