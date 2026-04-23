// ============================================================
// RISC-V Debug Module — DMI Slave Interface
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Implements the Debug Module Interface (DMI) slave port.
// Spec: RISC-V External Debug Support v0.13.2 §6.1
//
// Signal widths:
//   dmi_addr  [6:0]  — 7-bit register address
//   dmi_data  [31:0] — 32-bit read/write data
//   dmi_op    [1:0]  — 0=nop, 1=read, 2=write, 3=reserved
//   dmi_resp  [1:0]  — 0=success, 2=failed, 3=busy
// ============================================================

module dmi_slave (
    input  logic        clk,
    input  logic        rst_n,          // active-low reset

    // --- DMI request from debugger (JTAG DR capture) ---
    input  logic        dmi_req_valid,
    input  logic [6:0]  dmi_req_addr,
    input  logic [31:0] dmi_req_data,
    input  logic [1:0]  dmi_req_op,
    output logic        dmi_req_ready,  // DM can accept request

    // --- DMI response back to debugger ---
    output logic        dmi_resp_valid,
    output logic [31:0] dmi_resp_data,
    output logic [1:0]  dmi_resp_resp,

    // --- Internal DM register bus ---
    output logic        dm_wen,         // write enable to DM reg file
    output logic        dm_ren,         // read  enable to DM reg file
    output logic [6:0]  dm_addr,        // register address
    output logic [31:0] dm_wdata,       // data to write
    input  logic [31:0] dm_rdata,       // data read back
    input  logic        dm_error        // reg file signals unsupported addr
);

    // -------------------------------------------------------
    // State machine: IDLE → PROCESS → RESPOND
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE    = 2'b00,
        S_PROCESS = 2'b01,
        S_RESPOND = 2'b10
    } state_t;

    state_t state, next_state;

    logic [6:0]  lat_addr;
    logic [31:0] lat_data;
    logic [1:0]  lat_op;
    logic [31:0] resp_data_r;
    logic [1:0]  resp_resp_r;

    // -------------------------------------------------------
    // State register
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------
    // Latch incoming request
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_addr <= '0;
            lat_data <= '0;
            lat_op   <= '0;
        end else if (state == S_IDLE && dmi_req_valid) begin
            lat_addr <= dmi_req_addr;
            lat_data <= dmi_req_data;
            lat_op   <= dmi_req_op;
        end
    end

    // -------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            S_IDLE:    if (dmi_req_valid) next_state = S_PROCESS;
            S_PROCESS: next_state = S_RESPOND;
            S_RESPOND: next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------
    // Internal bus drive (combinational from latched values)
    // -------------------------------------------------------
    always_comb begin
        dm_wen   = 1'b0;
        dm_ren   = 1'b0;
        dm_addr  = lat_addr;
        dm_wdata = lat_data;

        if (state == S_PROCESS) begin
            case (lat_op)
                2'b01:  dm_ren = 1'b1;    // read
                2'b10:  dm_wen = 1'b1;    // write
                default: ;                // nop / reserved
            endcase
        end
    end

    // -------------------------------------------------------
    // Capture response data one cycle after PROCESS
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_data_r <= '0;
            resp_resp_r <= 2'b00;
        end else if (state == S_PROCESS) begin
            resp_data_r <= dm_rdata;
            resp_resp_r <= dm_error ? 2'b10 : 2'b00;   // 2=failed, 0=success
        end
    end

    // -------------------------------------------------------
    // Output assignments
    // -------------------------------------------------------
    assign dmi_req_ready  = (state == S_IDLE);
    assign dmi_resp_valid = (state == S_RESPOND);
    assign dmi_resp_data  = resp_data_r;
    assign dmi_resp_resp  = resp_resp_r;

endmodule
