# Low-Power VLSI Design — Clock Gating & Power Domains
### Resume Project | Final Year ECE | VLSI / RTL Design

---

## Project Overview

This project demonstrates **industry-standard low-power design techniques** used in modern SoCs (System-on-Chip). It implements three key concepts:

1. **Integrated Clock Gating (ICG)** — disables clock to idle logic blocks
2. **Power Domain Management** — independently powers up/down functional blocks
3. **Retention Registers** — preserves state across power-down cycles

These techniques are critical in chips like mobile processors (Snapdragon, Apple A-series) and IoT SoCs where minimizing power consumption is the #1 design constraint.

---

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           low_power_top                 │
                    │                                         │
  clk ──────────────┼──► ICG_ALU ──► gated_clk_alu ──►       │
                    │                              ALU Domain │
                    │                           (PD_ALU)      │
                    │                              │           │
                    │                         iso_cells       │
                    │                              │           │
                    │                         alu_result ────►│──► output
                    │                                         │
  clk ──────────────┼──► ICG_MEM ──► gated_clk_mem ──►       │
                    │                              MEM Domain │
                    │                           (PD_MEM)      │
                    │                              │           │
                    │                         iso_cells       │
                    │                              │           │
                    │                        mem_rd_data ────►│──► output
                    │                                         │
  clk ──────────────┼────────────────────► CTRL Domain       │
                    │                       (Always-On)       │
                    │                    manages: pwr_en,     │
                    │                    clk_en, iso_en,      │
                    │                    save, restore        │
                    └─────────────────────────────────────────┘
```

---

## Files

| File | Description |
|------|-------------|
| `low_power_design.v` | RTL design — all modules |
| `low_power_top_tb.v` | Testbench — 8 test cases |
| `README.md` | This file |

---

## Module Descriptions

### `icg_cell` — Integrated Clock Gate
- Latch-based clock gating (industry standard)
- Negative-level latch prevents glitches on `gated_clk`
- `test_mode` input forces clock ON during scan testing
- **Power savings**: eliminates dynamic power in idle flip-flops

### `iso_cell` — Isolation Cell
- Clamps outputs of a powered-off domain to logic 0
- Prevents X-propagation into always-on logic
- **Why needed**: without isolation, powering off a domain causes floating/unknown outputs

### `retention_reg` — Retention Register
- Shadow latch stores state before power-down (`save` pulse)
- Restores state after power-up (`restore` pulse)
- **Why needed**: regular registers lose state on power-off; retention registers preserve it using a small always-powered shadow latch

### `alu_domain` — Arithmetic Logic Unit (PD_ALU)
- 8-bit ALU: ADD, SUB, AND, OR
- Powered down by controller after idle threshold
- Receives gated clock from ICG cell

### `mem_domain` — Register File (PD_MEM)
- 8-entry × 8-bit synchronous register file
- Retention logic saves/restores all entries
- Power-cycled between memory bursts

### `ctrl_domain` — Power Controller (Always-On)
- Never powers down — manages all other domains
- Implements correct power-up/power-down sequencing:
  - **Power-up**: Enable Power → Start Clock → Release Isolation
  - **Power-down**: Assert Isolation → Stop Clock → Disable Power
- Auto power-down via programmable idle counters

---

## Power-Up / Power-Down Sequence

**Correct order matters** — violating it causes signal glitches or metastability.

```
POWER-UP SEQUENCE:
  Step 1: Assert pwr_en (turn on power supply to domain)
  Step 2: Assert clk_en (start clock via ICG)
  Step 3: Deassert iso_en (release isolation cells)
  Step 4: Assert restore (load retention data into registers)

POWER-DOWN SEQUENCE:
  Step 1: Assert save (copy register state to shadow latches)
  Step 2: Assert iso_en (clamp outputs before power off)
  Step 3: Deassert clk_en (stop clock to save dynamic power)
  Step 4: Deassert pwr_en (cut power supply to domain)
```

---

## How to Simulate

### Option 1: Icarus Verilog (Free, Linux/Mac/Windows)

```bash
# Install Icarus Verilog
sudo apt install iverilog   # Ubuntu/Debian
brew install icarus-verilog # macOS

# Compile and run
iverilog -o sim_out low_power_top_tb.v low_power_design.v
vvp sim_out

# View waveforms in GTKWave
gtkwave low_power_sim.vcd
```

### Option 2: ModelSim / QuestaSim

```tcl
# In ModelSim console
vlib work
vlog low_power_design.v low_power_top_tb.v
vsim low_power_top_tb
run -all
```

### Option 3: Vivado Simulator (Xilinx)

1. Create a new RTL project in Vivado
2. Add `low_power_design.v` as design source
3. Add `low_power_top_tb.v` as simulation source
4. Run Behavioral Simulation → Run All

---

## Test Cases

| Test | What It Verifies |
|------|-----------------|
| TEST 1 | Both domains OFF at idle (power_state = 00) |
| TEST 2 | All 4 ALU operations (ADD, SUB, AND, OR) + carry |
| TEST 3 | ALU auto power-down after idle threshold |
| TEST 4 | Isolation cells clamp outputs when domain is off |
| TEST 5 | Memory domain write + read all 8 entries |
| TEST 6 | Retention: data survives power-down/restore cycle |
| TEST 7 | Both domains active simultaneously (power_state = 11) |
| TEST 8 | ICG test mode bypass for scan compatibility |

---

## Expected Simulation Output

```
====================================================
 TEST SUITE: Low-Power Design Verification
====================================================

--- TEST 1: Idle Power State ---
[PASS] Power State [IDLE] = 00

--- TEST 2: ALU Operations ---
[PASS] ALU Test 1 | Result=75 (expected 75)
[PASS] ALU Test 2 | Result=40 (expected 40)
[PASS] ALU Test 3 | Result=15 (expected 15)
[PASS] ALU Test 4 | Result=171 (expected 171)
[PASS] ALU Test 5 | Result=400 (expected 400)

--- TEST 3: ALU Auto Power-Down ---
[PASS] ALU domain powered down after idle

--- TEST 4: Isolation Cells ---
[PASS] Isolation working — ALU outputs clamped to 0 when domain off

--- TEST 5: Memory Domain Write/Read ---
[PASS] MEM Test 10 | Data=aa (expected aa)
[PASS] MEM Test 11 | Data=dd (expected dd)
[PASS] MEM Test 12 | Data=44 (expected 44)

--- TEST 6: Retention Register ---
[PASS] MEM domain powered down (retention save triggered)
[PASS] MEM Test 20 | Data=aa (expected aa)
[PASS] MEM Test 21 | Data=dd (expected dd)
[PASS] MEM Test 22 | Data=44 (expected 44)

--- TEST 7: Both Domains Active ---
[PASS] ALU Test 30 | Result=20 (expected 20)
[PASS] Power State [BOTH_ON] = 11

====================================================
 SIMULATION COMPLETE
 PASSED : 18
 FAILED : 0
 STATUS : ALL TESTS PASSED ✓
====================================================
```

---

## Resume Bullet Points (Copy-Paste Ready)

```
• Designed a multi-domain low-power SoC subsystem in Verilog implementing
  integrated clock gating (ICG), power domain isolation, and retention
  registers; verified via an 8-scenario self-checking testbench in ModelSim

• Implemented correct power-up/power-down sequencing (power → clock →
  isolation release) across 3 independent power domains with an always-on
  controller managing idle-based auto power-down

• Designed latch-based ICG cells eliminating dynamic power consumption in
  idle flip-flops, and isolation cells preventing X-propagation from
  powered-off domains into always-on logic

• Verified retention register behavior across full save/restore cycles,
  confirming 100% state integrity after power-down and restoration
```

---

## Concepts to Understand for Interviews

- **Why latch-based ICG?** — A latch sampling enable on the LOW phase of the clock ensures the enable is stable before the rising edge, preventing glitches on `gated_clk`. Simple AND-gating can produce glitches.

- **Why isolate before power-off?** — When you cut power to a domain, its outputs float or go to unknown states. Isolation cells clamp these to a known safe value (0) before that happens.

- **What is a balloon/shadow register?** — A tiny always-powered latch shadowing a main register. Only the shadow needs always-on power; the main register can be power-gated.

- **UPF / CPF** — In real chip flows, power intent is described in a Unified Power Format (UPF) file, which EDA tools use to insert ICG/ISO/retention cells automatically. This project implements those concepts manually to understand the underlying hardware.

---

## Tools & Skills Demonstrated

- Verilog RTL coding (parameterized, synthesizable)
- Clock domain management and clock gating
- Power domain architecture and sequencing
- Functional verification with self-checking testbench
- Waveform analysis (GTKWave / ModelSim)
- Low-power design methodology (ICG, ISO, Retention)

---

## Next Steps to Strengthen the Project

1. **Add UPF file** — Describe power intent formally; synthesize with Synopsys DC or Cadence Genus
2. **Run synthesis** — Report LUT count and Fmax on Xilinx Artix-7 via Vivado
3. **Add power analysis** — Use Vivado power estimator or PrimePower to show switching activity reduction
4. **Extend ALU** — Add multiply, shift, compare operations
5. **Add CDC** — Introduce a second clock domain and async FIFO between them
