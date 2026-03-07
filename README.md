# Integer Dividers

Synthesisable SystemVerilog implementations of classical integer division algorithms, with self-checking testbenches.

Five architectures are provided, spanning both unsigned and signed operands, and covering the two principal algorithm families: digit-recurrence (shift-and-subtract) and functional iteration (Newton–Raphson).

---

## Implementations

| Module | Algorithm | Signed | Latency |
|---|---|---|---|
| `divider_restoring_unsigned` | Restoring | No | N cycles |
| `divider_nonperforming_unsigned` | Non-performing (skip-restore) | No | ≤ N cycles |
| `divider_nonrestoring_signed` | Non-restoring | Yes | N + 1 cycles |
| `divider_srt4_unsigned` | SRT radix-4 | No | ceil(N/2) + 3 cycles |
| `divider_newtonraphson_unsigned` | Newton–Raphson | No | (ITERATIONS × 2) + 5 cycles |

The four digit-recurrence modules share a common interface and are parameterised by operand width `N`.  Each uses a single adder/subtractor per active step.  The Newton–Raphson module uses two sequential fixed-point multipliers of width `DEN_BITS + 4` and a small seed ROM.

---

## File Structure

```
Integer_dividers/
├── divider_restoring_unsigned.sv             # Restoring division, unsigned
├── divider_nonperforming_unsigned.sv         # Non-performing division, unsigned
├── divider_nonrestoring_signed.sv            # Non-restoring division, signed
├── divider_srt4_unsigned.sv                  # SRT radix-4 division, unsigned
├── divider_newtonraphson_unsigned.sv         # Newton–Raphson division, unsigned
├── tb_divider_restoring_unsigned.sv          # Testbench — restoring
├── tb_divider_nonperforming_unsigned.sv      # Testbench — non-performing
├── tb_divider_nonrestoring_signed.sv         # Testbench — non-restoring
├── tb_divider_srt4_unsigned.sv               # Testbench — SRT radix-4
├── tb_divider_newtonraphson_unsigned.sv      # Testbench — Newton–Raphson
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

# Newton–Raphson unsigned
iverilog -g2012 -o sim_nr tb_divider_newtonraphson_unsigned.sv divider_newtonraphson_unsigned.sv
vvp sim_nr
```

Each testbench defaults to an exhaustive sweep over all input combinations at 8-bit width (`TB_TEST_CNT = 0`).  Set `TB_TEST_CNT = N` for corner cases plus N random trials, which is appropriate for wider configurations.

> **Note — Newton–Raphson simulation time:** The exhaustive 8-bit sweep (65,536 cases) runs significantly longer than for the digit-recurrence modules because each test case waits for `done` across multiple multiply cycles.  For iterative debugging, set `TB_TEST_CNT = 200` to complete in seconds; reserve `TB_TEST_CNT = 0` for final validation.

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

The critical path per cycle is two cascaded adders of width `DEN_BITS + 2`.  For timing-sensitive targets, register the mid-step result to pipeline across two cycles at the cost of one extra latency cycle per iteration.

### Newton–Raphson Division
Computes the reciprocal of the denominator via the quadratically-convergent iteration `X_{i+1} = X_i × (2 − D × X_i)`, using fixed-point arithmetic throughout, then multiplies by the numerator to obtain the quotient.

The denominator is first normalised to [0.5, 1) by left-shifting, enabling a small seed ROM (2^(SEED_BITS−1) entries) to provide an initial approximation accurate to `SEED_BITS` bits.  Each of the `ITERATIONS` refinement steps (2 clock cycles each) doubles the number of correct bits, so three iterations cover operands up to ~30 bits wide.  Total latency is `(ITERATIONS × 2) + 5` cycles, independent of operand values.

A post-iteration correction loop (at most 2 additional cycles) converts the fixed-point approximation to the exact integer quotient; the exact remainder follows as `N − Q × D`.  See Section 6.2 of the technical report for detailed justification of a fixed-point integer N-R implementation.

---

## Why Newton–Raphson in an Integer Divider Repository?

Newton–Raphson division is most commonly described in floating-point contexts, where the normalisation step is free and an FMA unit is assumed. Its inclusion here in an integer, fixed-point RTL repository is deliberate.

**Completing the algorithm taxonomy.** The four digit-recurrence modules span the shift-and-subtract design space. Newton–Raphson is the principal alternative family. A repository that omits it gives an incomplete picture of the tradeoff landscape and leaves the most important latency-vs-area crossover unillustrated.

**Constant latency.** All digit-recurrence dividers have latency that varies with the quotient bit pattern, even if the worst case is bounded. Newton–Raphson's latency depends only on operand width and iteration count, never on the input values. This matters in fixed-latency pipelines, real-time systems, and any design where variable-latency division would require stall logic.

**RTL multipliers are first-class resources.** The assumption that N-R requires a dedicated FMA unit is a processor-architecture habit, not an RTL constraint. An FPGA or ASIC datapath that already contains DSP multiplier blocks can reuse them for N-R division at zero additional area cost. The fixed-point formulation here makes that reuse explicit and directly portable to any synthesisable RTL flow.

**Fixed-point is the natural form for hardware.** The iteration `X ← X(2 − DX)` is purely a fixed-point recurrence. Expressing it in integer fixed-point, as done here, strips away the floating-point abstraction and shows the arithmetic as it actually executes in silicon — no floating-point library dependency required.

**Exact integer result.** The post-iteration correction loop in `divider_newtonraphson_unsigned.sv` adjusts the approximate quotient by ±1 ulp as needed (at most two cycles) and recovers the exact remainder as `N − Q × D`. The result is bit-for-bit identical to the digit-recurrence modules and passes the same exhaustive testbench.
