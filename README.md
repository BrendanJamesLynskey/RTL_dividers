# RTL Dividers

Synthesisable SystemVerilog implementations of classical integer division algorithms, with self-checking testbenches.

Four iterative architectures are provided, covering both unsigned and signed operands, and four common algorithmic strategies: non-performing (skip-restore), restoring, non-restoring, and SRT radix-4.

---

## Implementations

| Module | Algorithm | Signed | Latency |
|---|---|---|---|
| `divider_restoring_unsigned` | Restoring | No | N cycles |
| `divider_nonperforming_unsigned` | Non-performing (skip-restore) | No | ≤ N cycles |
| `divider_nonrestoring_signed` | Non-restoring | Yes | N + 1 cycles |
| `divider_srt4_unsigned` | SRT radix-4 | No | ceil(N/2) + 3 cycles |

All modules use a shift-and-subtract iterative datapath and are parameterised by operand width `N`.

---

## File Structure

```
RTL_dividers/
├── divider_restoring_unsigned.sv         # Restoring division, unsigned
├── divider_nonperforming_unsigned.sv     # Non-performing division, unsigned
├── divider_nonrestoring_signed.sv        # Non-restoring division, signed
├── divider_srt4_unsigned.sv              # SRT radix-4 division, unsigned
├── tb_divider_restoring_unsigned.sv      # Testbench — restoring
├── tb_divider_nonperforming_unsigned.sv  # Testbench — non-performing
├── tb_divider_nonrestoring_signed.sv     # Testbench — non-restoring
├── tb_divider_srt4_unsigned.sv           # Testbench — SRT radix-4
├── integer_dividers_report.md            # Technical report
└── README.md
```

---

## Simulation

Testbenches are compatible with **Icarus Verilog** (`iverilog`) and **Verilator**.

```bash
# Restoring unsigned
iverilog -g2012 -o sim_restoring tb_divider_restoring_unsigned.sv divider_restoring_unsigned.sv
vvp sim_restoring

# Non-performing unsigned
iverilog -g2012 -o sim_nonperforming tb_divider_nonperforming_unsigned.sv divider_nonperforming_unsigned.sv
vvp sim_nonperforming

# Non-restoring signed
iverilog -g2012 -o sim_nonrestoring tb_divider_nonrestoring_signed.sv divider_nonrestoring_signed.sv
vvp sim_nonrestoring

# SRT radix-4 unsigned
iverilog -g2012 -o sim_srt4 tb_divider_srt4_unsigned.sv divider_srt4_unsigned.sv
vvp sim_srt4
```

Each testbench defaults to an exhaustive sweep over all input combinations at 8-bit width (`TB_TEST_CNT = 0`).  Set `TB_TEST_CNT = N` for corner cases plus N random trials, which is appropriate for wider configurations.

---

## Algorithm Summary

### Restoring Division
At each iteration, subtract the divisor from the partial remainder. If the result is negative, restore by adding the divisor back, and record a quotient bit of 0. Otherwise keep the result and record 1. Simple but requires two adder operations per negative step.

### Non-Performing Division
An optimisation of restoring division that avoids the restore addition: trial subtraction is gated on a sign-check of the partial remainder, so the subtract is only performed when it is known to succeed. Reduces average switching activity and can improve throughput under sparse quotient patterns.

### Non-Restoring Division
Never restores; instead records −1 or +1 quotient digits. Remainders are allowed to go negative, and a final correction step converts the signed-digit quotient and adjusts any negative final remainder. Requires only one add/subtract per cycle regardless of sign.

### SRT Radix-4 Division
Produces **two quotient bits per cycle** by performing two consecutive non-restoring steps within each clock period.  The combined quotient digit comes from the redundant digit set {−3, −2, −1, 0, +1, +2, +3}, accumulated in a positive/negative pair of registers (QPOS, QNEG).  The final binary quotient is QPOS − QNEG, followed by a single remainder correction if needed.

The critical path per cycle is two cascaded adders of width `DEN_BITS + 2`, compared with one adder in the radix-2 variants.  For timing-sensitive targets, register the mid-step result to pipeline across two cycles — at the cost of doubling the per-step latency (offsetting the radix-4 gain).  The implementation here performs both steps combinationally within a single clock, which is appropriate for moderate clock frequencies.
