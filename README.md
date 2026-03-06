# RTL Dividers

Synthesisable SystemVerilog implementations of classical integer division algorithms, with self-checking testbenches.

Three iterative architectures are provided, covering both unsigned and signed operands, and three common algorithmic strategies: non-performing (skip-restore), restoring, and non-restoring.

---

## Implementations

| Module | Algorithm | Signed | Latency |
|---|---|---|---|
| `divider_restoring_unsigned` | Restoring | No | N cycles |
| `divider_nonperforming_unsigned` | Non-performing (SRT-like skip-restore) | No | ≤ N cycles |
| `divider_nonrestoring_signed` | Non-restoring | Yes | N cycles |

All modules use a shift-and-subtract iterative datapath and are parameterised by operand width `N`.

---

## File Structure

```
RTL_dividers/
├── divider_restoring_unsigned.sv         # Restoring division, unsigned
├── divider_nonperforming_unsigned.sv     # Non-performing division, unsigned
├── divider_nonrestoring_signed.sv        # Non-restoring division, signed
├── tb_divider_restoring_unsigned.sv      # Testbench — restoring
├── tb_divider_nonperforming_unsigned.sv  # Testbench — non-performing
├── tb_divider_nonrestoring_signed.sv     # Testbench — non-restoring
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
```

---

## Algorithm Summary

### Restoring Division
At each iteration, subtract the divisor from the partial remainder. If the result is negative, restore by adding the divisor back, and record a quotient bit of 0. Otherwise keep the result and record 1. Simple but requires two adder operations per negative step.

### Non-Performing Division
An optimisation of restoring division that avoids the restore addition: trial subtraction is gated on a sign-check of the partial remainder, so the subtract is only performed when it is known to succeed. Reduces average switching activity and can improve throughput under sparse quotient patterns.

### Non-Restoring Division
Never restores; instead records −1 or +1 quotient digits. Remainders are allowed to go negative, and a final correction step converts the signed-digit quotient and adjusts any negative final remainder. Requires only one add/subtract per cycle regardless of sign.

---

## Related Repositories

- [RISCV_RV32I_MCU](https://github.com/BrendanJamesLynskey/RISCV_RV32I_MCU) — Pipelined RV32I MCU
- [RISCV_RV32IC_MCU](https://github.com/BrendanJamesLynskey/RISCV_RV32IC_MCU) — RV32IC with D-cache and AXI bus
- [LLM_Transformer_Decoder_RTL](https://github.com/BrendanJamesLynskey/LLM_Transformer_Decoder_RTL) — Transformer decoder accelerator in SystemVerilog
