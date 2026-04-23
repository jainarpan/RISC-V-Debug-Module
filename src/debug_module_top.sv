// ============================================================
// RISC-V Debug Module — Top-Level Integration
// Assignment 2 | VLSI Architecture | BITS Pilani
// Student : Arpan Jain (2025ht08066)
//
// Connects: dmi_slave <-> dm_regfile <-> abs_cmd_fsm
//                     <-> halt_resume_ctrl <-> hart_stub
// ============================================================

module debug_module_top (
    input  logic clk,
    input  logic rst_n,

    // External DMI interface
    input  logic        dmi_req_valid,
    input  logic [6:0]  dmi_req_addr,
    input  logic [31:0] dmi_req_data,
    input  logic [1:0]  dmi_req_op,
    output logic        dmi_req_ready,
    output logic        dmi_resp_valid,
    output logic [31:0] dmi_resp_data,
    output logic [1:0]  dmi_resp_resp,

    // Hart interface (to/from hart_stub in tb)
    output logic        halt_out,
    output logic        resume_out,
    input  logic        hart_halted,
    input  logic        hart_running,

    output logic        hart_reg_ren,
    output logic        hart_reg_wen,
    output logic [15:0] hart_reg_regno,
    output logic [31:0] hart_reg_wdata,
    input  logic [31:0] hart_reg_rdata,
    input  logic        hart_reg_ack,
    input  logic        hart_reg_err
);

    // -------------------------------------------------------
    // Internal wires
    // -------------------------------------------------------
    logic        dm_wen, dm_ren;
    logic [6:0]  dm_addr;
    logic [31:0] dm_wdata, dm_rdata;
    logic        dm_error;

    logic        dmactive;
    logic        haltreq, resumereq;
    logic [31:0] command_out;
    logic        command_wen;
    logic [31:0] data0_out, data1_out;
    logic [31:0] data0_in;
    logic        data0_wen_fsm;

    logic [2:0]  cmderr_in;
    logic        cmderr_wen;
    logic        busy_in;

    logic        allhalted, anyhalted, allrunning, anyrunning;

    // -------------------------------------------------------
    // DMI Slave
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

    // -------------------------------------------------------
    // DM Register File
    // -------------------------------------------------------
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
        .clear_cmderr   (1'b0),
        .dmactive       (dmactive),
        .haltreq        (haltreq),
        .resumereq      (resumereq),
        .command_out    (command_out),
        .command_wen    (command_wen),
        .data0_out      (data0_out),
        .data1_out      (data1_out),
        .data0_in       (data0_in),
        .data0_wen      (data0_wen_fsm)
    );

    // -------------------------------------------------------
    // Abstract Command FSM
    // -------------------------------------------------------
    abs_cmd_fsm u_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .command_wen     (command_wen),
        .command_reg     (command_out),
        .data0_reg       (data0_out),
        .hart_halted     (hart_halted),
        .hart_reg_ren    (hart_reg_ren),
        .hart_reg_wen    (hart_reg_wen),
        .hart_reg_regno  (hart_reg_regno),
        .hart_reg_wdata  (hart_reg_wdata),
        .hart_reg_rdata  (hart_reg_rdata),
        .hart_reg_ack    (hart_reg_ack),
        .hart_reg_err    (hart_reg_err),
        .data0_in        (data0_in),
        .data0_wen       (data0_wen_fsm),
        .cmderr_out      (cmderr_in),
        .cmderr_wen      (cmderr_wen),
        .busy_out        (busy_in)
    );

    // -------------------------------------------------------
    // Halt/Resume Controller
    // -------------------------------------------------------
    halt_resume_ctrl u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .haltreq     (haltreq),
        .resumereq   (resumereq),
        .halt_out    (halt_out),
        .resume_out  (resume_out),
        .hart_halted (hart_halted),
        .hart_running(hart_running),
        .allhalted   (allhalted),
        .anyhalted   (anyhalted),
        .allrunning  (allrunning),
        .anyrunning  (anyrunning)
    );

endmodule
