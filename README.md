# RTL Dividers

Synthesisable SystemVerilog implementations of classical integer division algorithms, with self-checking testbenches.

Five iterative architectures are provided, covering both unsigned and signed operands, and five common algorithmic strategies: non-performing (skip-restore), restoring, non-restoring, SRT radix-4, and Newton–Raphson functional iteration.

---

## Implementations

| Module | Algorithm | Signed | Latency |
|---|---|---|---|
| `divider_restoring_unsigned` | Restoring | No | N cycles |
| `divider_nonperforming_unsigned` | Non-performing (skip-restore) | No | ≤ N cycles |
| `divider_nonrestoring_signed` | Non-restoring | Yes | N + 1 cycles |
| `divider_srt4_unsigned` | SRT radix-4 | No | ceil(N/2) + 3 cycles |
| `divider_newtonraphson_unsigned` | Newton–Raphson | No | (ITERATIONS × 2) + 5 cycles |

All shift-subtract modules use a single adder/subtractor per active step and are parameterised by operand width `N`.  The Newton–Raphson module uses two sequential multipliers of width `DEN_BITS + 4`.

---

## File Structure

```
RTL_dividers/
├── divider_restoring_unsigned.sv             # Restoring division, unsigned
├── divider_nonperforming_unsigned.sv         # Non-performing division, unsigned
├── divider_nonrestoring_signed.sv            # Non-restoring division, signed
├── divider_srt4_unsigned.sv                  # SRT radix-4 division, unsigned
├── divider_newtonraphson_unsigned.sv         # Newton-Raphson division, unsigned
├── tb_divider_restoring_unsigned.sv          # Testbench — restoring
├── tb_divider_nonperforming_unsigned.sv      # Testbench — non-performing
├── tb_divider_nonrestoring_signed.sv         # Testbench — non-restoring
├── tb_divider_srt4_unsigned.sv               # Testbench — SRT radix-4
├── tb_divider_newtonraphson_unsigned.sv      # Testbench — Newton-Raphson
├── integer_dividers_report.md                # Technical report
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

# Newton-Raphson unsigned
iverilog -g2012 -o sim_nr tb_divider_newtonraphson_unsigned.sv divider_newtonraphson_unsigned.sv
vvp sim_nr
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

### Newton–Raphson Division
Computes the reciprocal of the denominator via the quadratically-convergent iteration `X_{i+1} = X_i × (2 − D × X_i)`, starting from a small lookup-table seed, then multiplies by the numerator to obtain the quotient.

Each N-R step (2 clock cycles: one multiply to form `D×X`, one to form the update `X×(2−D×X)`) doubles the number of correct bits, so only `ITERATIONS=3` steps are needed for operands up to ~30 bits wide.  Latency is therefore `(ITERATIONS × 2) + 5` cycles — around 11 cycles for 8-bit operands — independent of the operand values.

A post-iteration correction loop (at most 2 cycles) converts the approximate quotient to the exact integer value and recovers the exact remainder.  The dominant hardware cost is two multipliers of width `DEN_BITS + 4`; the module is therefore significantly larger than the shift-subtract variants but offers constant, operand-value-independent latency.
