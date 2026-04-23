# RISC-V Debug Module — VLSI Architecture Assignment 2

**Student:** Arpan Jain | 2025ht08066  
**Course:** VLSI Architecture, BITS Pilani (Sem 2)

---

## Overview

A minimal RISC-V External Debug Module (DM) implemented in SystemVerilog, compliant with **RISC-V Debug Spec v0.13.2**. Supports halt/resume, GPR read/write, and CSR read/write via Abstract Commands over a DMI interface. Simulated using **Icarus Verilog**.

---

## Repository Structure

```
src/
  dmi_slave.sv          # DMI bus slave (Part A)
  dm_regfile.sv         # DM register file - dmcontrol, dmstatus, data0/1, command, abstractcs (Part A)
  hart_stub.sv          # Behavioural hart model - 32 GPRs + 4 CSRs (used by all parts)
  abs_cmd_fsm.sv        # Abstract Command FSM: IDLE→DECODE→EXEC→DONE (Part B)
  halt_resume_ctrl.sv   # Halt/Resume handshake controller (Part C)
  debug_module_top.sv   # Top-level integration of all modules (Part D)

tb/
  tb_partA.sv           # Part A testbench - DMI + register file
  tb_partB.sv           # Part B testbench - Abstract Command FSM
  tb_partC.sv           # Part C testbench - Halt/Resume handshake
  tb_partD.sv           # Part D integration testbench

sim/                    # VCD waveform outputs (generated on simulation run)

REFLECTION.txt          # Part E written answers (Q1-Q5)
```

---

## Simulation Results

| Part | Tests | Result |
|------|-------|--------|
| A — DMI Slave + Register File | 10 | ✅ 10/10 PASS |
| B — Abstract Command FSM | 3 | ✅ 3/3 PASS |
| C — Halt/Resume Handshake | 11 | ✅ 11/11 PASS |
| D — Integration Testbench | 9 | ✅ 9/9 PASS |

---

## How to Simulate

Requires [Icarus Verilog](https://bleyer.org/icarus/) (v12+).

**Part A:**
```bash
iverilog -g2012 -o sim/tb_partA.vvp src/dmi_slave.sv src/dm_regfile.sv tb/tb_partA.sv
vvp sim/tb_partA.vvp
```

**Part B:**
```bash
iverilog -g2012 -o sim/tb_partB.vvp src/dmi_slave.sv src/dm_regfile.sv src/hart_stub.sv src/abs_cmd_fsm.sv tb/tb_partB.sv
vvp sim/tb_partB.vvp
```

**Part C:**
```bash
iverilog -g2012 -o sim/tb_partC.vvp src/halt_resume_ctrl.sv src/hart_stub.sv tb/tb_partC.sv
vvp sim/tb_partC.vvp
```

**Part D (Full Integration):**
```bash
iverilog -g2012 -o sim/tb_partD.vvp src/dmi_slave.sv src/dm_regfile.sv src/hart_stub.sv src/abs_cmd_fsm.sv src/halt_resume_ctrl.sv src/debug_module_top.sv tb/tb_partD.sv
vvp sim/tb_partD.vvp
```

View waveforms: `gtkwave sim/tb_partD.vcd`

---

## Key Design Decisions

- **dmactive lock (A3):** All register writes except dmcontrol are ignored while `dmactive=0`, ensuring a clean reset state.
- **Halt wins (C3):** When `haltreq` and `resumereq` are asserted simultaneously, halt takes priority per spec requirement.
- **Single-cycle hart ack:** The hart stub responds to register access in one clock cycle, simplifying FSM design.
- **cmderr W1C:** `abstractcs[10:8]` is Write-1-to-Clear, matching the spec exactly.
