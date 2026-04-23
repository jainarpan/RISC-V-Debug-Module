// ============================================================
// RISC-V Debug Module — Abstract Command FSM
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Implements the 5-state Abstract Command FSM per spec §3.7:
//   ABS_IDLE → ABS_DECODE → ABS_EXEC_READ
//                         → ABS_EXEC_WRITE
//                         → ABS_DONE → ABS_IDLE
//
// Supports only cmdtype=0 (AccessRegister), aarsize=2 (32-bit).
// GPR regno: 0x1000–0x101F
// CSR regno: 0x0000–0x0FFF
//
// cmderr encoding (abstractcs[10:8]):
//   0 = none
//   1 = busy       (command written while FSM busy)
//   2 = not supported (bad cmdtype / aarsize)
//   3 = exception  (unused here)
//   4 = halt/resume mismatch (command while hart running)
//   5 = bus error  (unused here)
// ============================================================

module abs_cmd_fsm (
    input  logic        clk,
    input  logic        rst_n,

    // --- trigger from dm_regfile ---
    input  logic        command_wen,    // pulse when command register written
    input  logic [31:0] command_reg,    // latched command word
    input  logic [31:0] data0_reg,      // current data0 value (for writes)

    // --- hart status ---
    input  logic        hart_halted,    // hart is in debug mode

    // --- hart register access bus ---
    output logic        hart_reg_ren,
    output logic        hart_reg_wen,
    output logic [15:0] hart_reg_regno,
    output logic [31:0] hart_reg_wdata,
    input  logic [31:0] hart_reg_rdata,
    input  logic        hart_reg_ack,
    input  logic        hart_reg_err,

    // --- feedback to dm_regfile ---
    output logic [31:0] data0_in,       // result of a read goes here
    output logic        data0_wen,      // write enable into data0

    output logic [2:0]  cmderr_out,     // error code
    output logic        cmderr_wen,     // pulse to latch cmderr
    output logic        busy_out        // drives abstractcs[12]
);

    // -------------------------------------------------------
    // Command field decode  (command_reg layout per spec §3.7.1)
    //   [31:24] cmdtype   (must be 0 = AccessRegister)
    //   [22:20] aarsize   (must be 2'b010 = 32-bit)
    //   [19]    aarpostincrement (ignored)
    //   [18]    postexec  (ignored, no progbuf)
    //   [17]    transfer  (must be 1 to do anything)
    //   [16]    write     (1=write regno, 0=read regno)
    //   [15:0]  regno
    // -------------------------------------------------------
    logic [7:0]  cmdtype;
    logic [2:0]  aarsize;
    logic        transfer;
    logic        write_flag;
    logic [15:0] regno;

    assign cmdtype    = command_reg[31:24];
    assign aarsize    = command_reg[22:20];
    assign transfer   = command_reg[17];
    assign write_flag = command_reg[16];
    assign regno      = command_reg[15:0];

    // -------------------------------------------------------
    // FSM states
    // -------------------------------------------------------
    typedef enum logic [2:0] {
        ABS_IDLE       = 3'd0,
        ABS_DECODE     = 3'd1,
        ABS_EXEC_READ  = 3'd2,
        ABS_EXEC_WRITE = 3'd3,
        ABS_DONE       = 3'd4
    } abs_state_t;

    abs_state_t state, next_state;

    // -------------------------------------------------------
    // Latch the command fields at DECODE entry
    // -------------------------------------------------------
    logic [7:0]  lat_cmdtype;
    logic [2:0]  lat_aarsize;
    logic        lat_transfer;
    logic        lat_write;
    logic [15:0] lat_regno;
    logic [31:0] lat_wdata;   // snapshot of data0 when DECODE entered

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_cmdtype  <= '0;
            lat_aarsize  <= '0;
            lat_transfer <= '0;
            lat_write    <= '0;
            lat_regno    <= '0;
            lat_wdata    <= '0;
        end else if (state == ABS_IDLE && command_wen && !busy_out) begin
            lat_cmdtype  <= cmdtype;
            lat_aarsize  <= aarsize;
            lat_transfer <= transfer;
            lat_write    <= write_flag;
            lat_regno    <= regno;
            lat_wdata    <= data0_reg;   // capture data0 at command issue time
        end
    end

    // -------------------------------------------------------
    // State register
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ABS_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)

            ABS_IDLE: begin
                if (command_wen) begin
                    if (busy_out)
                        next_state = ABS_IDLE;     // error handled below
                    else
                        next_state = ABS_DECODE;
                end
            end

            ABS_DECODE: begin
                // Error checks happen here (one cycle)
                // If any error → back to IDLE (cmderr set by output logic)
                if (!hart_halted)
                    next_state = ABS_IDLE;         // cmderr=4
                else if (lat_cmdtype != 8'h00 || lat_aarsize != 3'b010 || !lat_transfer)
                    next_state = ABS_IDLE;         // cmderr=2
                else if (lat_write)
                    next_state = ABS_EXEC_WRITE;
                else
                    next_state = ABS_EXEC_READ;
            end

            ABS_EXEC_READ: begin
                if (hart_reg_ack)
                    next_state = ABS_DONE;
            end

            ABS_EXEC_WRITE: begin
                if (hart_reg_ack)
                    next_state = ABS_DONE;
            end

            ABS_DONE: begin
                next_state = ABS_IDLE;
            end

            default: next_state = ABS_IDLE;
        endcase
    end

    // -------------------------------------------------------
    // Output logic
    // -------------------------------------------------------

    // busy: high from DECODE through DONE
    assign busy_out = (state != ABS_IDLE);

    // Hart register bus
    always_comb begin
        hart_reg_ren   = 1'b0;
        hart_reg_wen   = 1'b0;
        hart_reg_regno = lat_regno;
        hart_reg_wdata = lat_wdata;

        case (state)
            ABS_EXEC_READ:  hart_reg_ren = 1'b1;
            ABS_EXEC_WRITE: hart_reg_wen = 1'b1;
            default: ;
        endcase
    end

    // data0 update after a read completes
    assign data0_in  = hart_reg_rdata;
    assign data0_wen = (state == ABS_EXEC_READ && hart_reg_ack && !hart_reg_err);

    // cmderr generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmderr_out <= 3'b000;
            cmderr_wen <= 1'b0;
        end else begin
            cmderr_wen <= 1'b0;
            cmderr_out <= 3'b000;

            case (state)
                ABS_IDLE: begin
                    // cmderr=1: command written while busy
                    if (command_wen && busy_out) begin
                        cmderr_out <= 3'd1;
                        cmderr_wen <= 1'b1;
                    end
                end

                ABS_DECODE: begin
                    if (!hart_halted) begin
                        cmderr_out <= 3'd4;   // halt/resume mismatch — hart not halted
                        cmderr_wen <= 1'b1;
                    end else if (lat_cmdtype != 8'h00 || lat_aarsize != 3'b010 || !lat_transfer) begin
                        cmderr_out <= 3'd2;   // not supported
                        cmderr_wen <= 1'b1;
                    end
                end

                ABS_EXEC_READ,
                ABS_EXEC_WRITE: begin
                    if (hart_reg_ack && hart_reg_err) begin
                        cmderr_out <= 3'd2;   // unsupported register
                        cmderr_wen <= 1'b1;
                    end
                end

                ABS_DONE: begin
                    // clear cmderr only if no error occurred (wen=0 means no change)
                end

                default: ;
            endcase
        end
    end

endmodule
