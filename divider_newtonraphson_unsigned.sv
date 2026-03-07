`timescale 1ns / 1ps
/*
    divider_newtonraphson_unsigned.sv

    Synthesisable SystemVerilog — Newton-Raphson iterative unsigned integer divider.

    Algorithm overview
    ------------------
    Newton-Raphson (N-R) computes the reciprocal of the denominator via the
    quadratically-convergent iteration:

        X_{i+1} = X_i * (2 - D * X_i)

    where X_i is the current approximation to 1/D (represented as a fixed-point
    fraction).  Starting from a coarse seed X_0 (from a lookup table), each step
    roughly doubles the number of correct bits.  The quotient is then recovered as:

        Q_approx = N * X_k

    Because N-R computes 1/D in fixed-point, the integer quotient must be corrected
    by one or two units in the last place (ulp) depending on rounding errors in the
    approximation, and the exact remainder is recovered from the corrected quotient.

    Fixed-point representation
    --------------------------
    Divisor D is normalised to the range [1.0, 2.0) by left-shifting until its MSB
    is 1.  The shift count (norm_shift) is stored.  All internal arithmetic uses
    an (W)-wide unsigned fixed-point format with FRAC_BITS fractional bits.

        FRAC_BITS     = DIV_DEN_BITS + 2
        W             = FRAC_BITS + 2  (= DIV_DEN_BITS + 4)

    Both D_norm and X are placed in a Q2.(W-2) working format for multiplication:
      - D_norm (Q1.(DEN-1)) goes into d_ext with its MSB at bit W-2 (integer bit)
      - X (Q0.FRAC_BITS) goes into x_ext with 2 leading zeros (pure fraction)

    The product of two Q2.(W-2) values is Q4.(2*(W-2)) in W2 bits.
    Extracting DX or X_new in Q2.(W-2) is a right-shift by (W-2).

    Seed table
    ----------
    The seed ROM maps the top (SEED_BITS-1) bits of the normalised denominator
    (below the leading 1) to a FRAC_BITS-bit initial approximation X_0.
    entry[i] = round( 2^FRAC_BITS / D_mid )  where D_mid = 1.0 + (i+0.5)/SEED_ENTRIES.

    Quotient recovery
    -----------------
    X_final approximates 1/D_norm_val where D_norm_val = D_saved * 2^norm_shift / 2^(DEN-1).
    Therefore  N/D = N * X_val * 2^norm_shift / 2^(DEN-1)
                   = (N * X_int) >> (FRAC_BITS + DIV_DEN_BITS - 1 - norm_shift).

    A two-step correction loop then adjusts Q_approx to the exact integer quotient.

    Brendan Lynskey 2025
*/

module divider_newtonraphson_unsigned
#(
    parameter  DIV_NUM_BITS = 8,
    parameter  DIV_DEN_BITS = 8,
    parameter  ITERATIONS   = 3,
    parameter  SEED_BITS    = 4
)
(
    input  wire                              SRST,
    input  wire                              CLK,
    input  wire                              CE,

    input  wire [DIV_NUM_BITS-1:0]           NUMERATOR_IN,
    input  wire [DIV_DEN_BITS-1:0]           DENOMINATOR_IN,
    output reg  [DIV_NUM_BITS-1:0]           QUOTIENT_OUT,
    output reg  [DIV_DEN_BITS-1:0]           REMAINDER_OUT,

    input  wire                              start,
    output reg                               error,
    output reg                               done
);

// ---------------------------------------------------------------------------
// Derived widths
// ---------------------------------------------------------------------------
localparam FRAC_BITS     = DIV_DEN_BITS + 2;
localparam W             = FRAC_BITS + 2;       // working register width
localparam W2            = 2 * W;               // product width
localparam Q_BITS        = DIV_NUM_BITS + 2;    // quotient + guard bits
localparam SEED_ENTRIES  = 1 << (SEED_BITS - 1);
localparam SHIFT_BITS    = $clog2(DIV_DEN_BITS);
localparam ITER_BITS     = $clog2(ITERATIONS + 1);
localparam CORR_W        = Q_BITS + DIV_DEN_BITS;
localparam CORR_PAD      = CORR_W - DIV_NUM_BITS;
// Base shift for quotient recovery: FRAC_BITS + DIV_DEN_BITS - 1
localparam RECIP_SHIFT_BASE = FRAC_BITS + DIV_DEN_BITS - 1;

// ---------------------------------------------------------------------------
// Seed ROM: pre-computed lookup table (Guide §3)
//
// For SEED_BITS=4, FRAC_BITS=10 (i.e. DIV_DEN_BITS=8):
//   D_mid[i] = 1.0 + (i + 0.5) / 8
//   entry[i] = round(1024 / D_mid[i])
//
// Python to regenerate for other parameters:
//   N = 1 << (SEED_BITS - 1)
//   for i in range(N):
//       d = 1.0 + (i + 0.5) / N
//       print(round(2**FRAC_BITS / d))
// ---------------------------------------------------------------------------
reg [FRAC_BITS-1:0] seed_rom [0:SEED_ENTRIES-1];

initial begin
    seed_rom[0] = 964;   // D_mid=1.0625
    seed_rom[1] = 862;   // D_mid=1.1875
    seed_rom[2] = 780;   // D_mid=1.3125
    seed_rom[3] = 712;   // D_mid=1.4375
    seed_rom[4] = 655;   // D_mid=1.5625
    seed_rom[5] = 607;   // D_mid=1.6875
    seed_rom[6] = 565;   // D_mid=1.8125
    seed_rom[7] = 529;   // D_mid=1.9375
end

// ---------------------------------------------------------------------------
// FSM states
// ---------------------------------------------------------------------------
localparam [3:0] S_IDLE           = 4'd0,
                 S_NORMALISE      = 4'd1,
                 S_MUL_DX         = 4'd2,
                 S_MUL_UPDATE     = 4'd3,
                 S_RECIPROCAL_DONE = 4'd4,
                 S_CORRECT_DOWN   = 4'd5,
                 S_CORRECT_UP     = 4'd6,
                 S_OUTPUT         = 4'd7,
                 S_ERROR          = 4'd8;

reg [3:0] state;

// ---------------------------------------------------------------------------
// Datapath registers
// ---------------------------------------------------------------------------
reg [DIV_DEN_BITS-1:0]              D_norm;
reg [SHIFT_BITS-1:0]               norm_shift;
reg [FRAC_BITS-1:0]                X;
reg [ITER_BITS-1:0]                iter_cnt;
reg [DIV_NUM_BITS-1:0]             N_saved;
reg [DIV_DEN_BITS-1:0]             D_saved;
reg [W-1:0]                        DX;
reg [Q_BITS-1:0]                   Q_work;

// Correction products — combinational (Guide §6)
reg [CORR_W-1:0]                   corr_prod_down;
reg [CORR_W-1:0]                   corr_prod_up;

// ---------------------------------------------------------------------------
// Hoisted local variables (Guide §1)
// ---------------------------------------------------------------------------
reg [SHIFT_BITS-1:0]               nr_mpos;
reg [SEED_BITS-2:0]                nr_seed_idx;
reg [DIV_DEN_BITS-1:0]             nr_dn;
reg [W-1:0]                        nr_d_ext, nr_x_ext;
reg [W2-1:0]                       nr_prod;
reg [W-1:0]                        nr_two_minus_dx;
reg [DIV_NUM_BITS+FRAC_BITS-1:0]   nr_nx_prod;
reg [DIV_NUM_BITS+FRAC_BITS-1:0]   nr_q_shifted;
reg [7:0]                          nr_total_shift;

// ---------------------------------------------------------------------------
// MSB position: combinational (Guide §4)
// ---------------------------------------------------------------------------
reg [SHIFT_BITS-1:0] c_msb_pos;
integer msb_i;
always @(*) begin
    c_msb_pos = 0;
    for (msb_i = 0; msb_i < DIV_DEN_BITS; msb_i = msb_i + 1)
        if (D_saved[msb_i]) c_msb_pos = msb_i[SHIFT_BITS-1:0];
end

// ---------------------------------------------------------------------------
// Correction products: combinational (Guide §6, §7)
// ---------------------------------------------------------------------------
always @(*) begin
    corr_prod_down = Q_work * D_saved;
    corr_prod_up   = (Q_work + 1) * D_saved;
end

// ---------------------------------------------------------------------------
// FSM + datapath
// ---------------------------------------------------------------------------
always @(posedge CLK) begin

    if (SRST) begin
        state         <= S_IDLE;
        QUOTIENT_OUT  <= 0;
        REMAINDER_OUT <= 0;
        error         <= 1'b0;
        done          <= 1'b0;
        X             <= 0;
        D_norm        <= 0;
        norm_shift    <= 0;
        N_saved       <= 0;
        D_saved       <= 0;
        DX            <= 0;
        Q_work        <= 0;
        iter_cnt      <= 0;

    end else if (CE) begin

        case (state)

        // ------------------------------------------------------------------
        // S_IDLE: sample inputs; handle divide-by-zero
        // ------------------------------------------------------------------
        S_IDLE: begin
            done  <= 1'b0;
            error <= 1'b0;

            if (start) begin
                if (DENOMINATOR_IN == 0) begin
                    state <= S_ERROR;
                end else begin
                    N_saved <= NUMERATOR_IN;
                    D_saved <= DENOMINATOR_IN;
                    state   <= S_NORMALISE;
                end
            end
        end

        // ------------------------------------------------------------------
        // S_NORMALISE: left-shift D until MSB=1; look up seed.
        // ------------------------------------------------------------------
        S_NORMALISE: begin
            nr_mpos    = c_msb_pos;
            norm_shift <= (DIV_DEN_BITS - 1) - nr_mpos;
            nr_dn      = D_saved << ((DIV_DEN_BITS - 1) - nr_mpos);
            D_norm     <= nr_dn;

            if (DIV_DEN_BITS - 2 >= SEED_BITS - 1) begin
                nr_seed_idx = nr_dn[DIV_DEN_BITS-2 -: (SEED_BITS-1)];
            end else begin
                nr_seed_idx = {nr_dn[DIV_DEN_BITS-2:0], {(SEED_BITS-1-(DIV_DEN_BITS-1)){1'b0}}};
            end
            X <= seed_rom[nr_seed_idx];

            iter_cnt <= 0;
            state    <= S_MUL_DX;
        end

        // ------------------------------------------------------------------
        // S_MUL_DX: compute  DX = D_norm * X  in Q2.(W-2) format.
        //
        // d_ext: D_norm (Q1.(DEN-1)) placed with MSB at bit W-2 (integer bit).
        //        Format: {0, D_norm, zeros} — value = D_norm_val in [1.0, 2.0).
        // x_ext: X (Q0.FRAC_BITS) placed with 2 leading zeros.
        //        Format: {00, X}            — value = X_val in (0.5, 1.0].
        //
        // Both are in the same Q2.(W-2) container.  Product is Q4.(2*(W-2)).
        // DX in Q2.(W-2) = product >> (W-2).
        // ------------------------------------------------------------------
        S_MUL_DX: begin
            nr_d_ext = {1'b0, D_norm, {(W - 1 - DIV_DEN_BITS){1'b0}}};
            nr_x_ext = {2'b00, X};
            nr_prod  = nr_d_ext * nr_x_ext;
            DX       <= nr_prod[W2-3 -: W];
            state    <= S_MUL_UPDATE;
        end

        // ------------------------------------------------------------------
        // S_MUL_UPDATE: compute  X_new = X * (2 - DX).
        //
        // "2" in Q2.(W-2): integer bit at position W-2, so 2 = bit W-1 set.
        // two_minus_dx = {1, 0...0} - DX.
        //
        // Product format same as S_MUL_DX.  X_new = product >> (W-2),
        // truncated to FRAC_BITS.
        // ------------------------------------------------------------------
        S_MUL_UPDATE: begin
            nr_two_minus_dx = {1'b1, {(W-1){1'b0}}} - DX;
            nr_x_ext = {2'b00, X};
            nr_prod  = nr_x_ext * nr_two_minus_dx;
            X        <= nr_prod[W-2+FRAC_BITS-1 -: FRAC_BITS];

            if (iter_cnt == ITERATIONS - 1) begin
                state <= S_RECIPROCAL_DONE;
            end else begin
                iter_cnt <= iter_cnt + 1;
                state    <= S_MUL_DX;
            end
        end

        // ------------------------------------------------------------------
        // S_RECIPROCAL_DONE: form Q_approx = N * X_final, then denormalise.
        //
        // X_final ≈ 2^FRAC_BITS / D_norm_val  where D_norm_val = D * 2^norm_shift / 2^(DEN-1).
        // Q = N/D = (N * X_int) >> (FRAC_BITS + DIV_DEN_BITS - 1 - norm_shift).
        //
        // Guide §8: use 8-bit shift amount to prevent truncation.
        // ------------------------------------------------------------------
        S_RECIPROCAL_DONE: begin
            nr_nx_prod   = N_saved * X;
            nr_total_shift = RECIP_SHIFT_BASE - {{(8-SHIFT_BITS){1'b0}}, norm_shift};
            nr_q_shifted = nr_nx_prod >> nr_total_shift;
            Q_work <= nr_q_shifted[Q_BITS-1:0];
            state  <= S_CORRECT_DOWN;
        end

        // ------------------------------------------------------------------
        // S_CORRECT_DOWN: if Q_work * D > N, decrement Q_work.
        // ------------------------------------------------------------------
        S_CORRECT_DOWN: begin
            if (corr_prod_down > {{CORR_PAD{1'b0}}, N_saved}) begin
                Q_work <= Q_work - 1;
            end else begin
                state <= S_CORRECT_UP;
            end
        end

        // ------------------------------------------------------------------
        // S_CORRECT_UP: if (Q_work+1) * D <= N, increment Q_work.
        // ------------------------------------------------------------------
        S_CORRECT_UP: begin
            if (corr_prod_up <= {{CORR_PAD{1'b0}}, N_saved}) begin
                Q_work <= Q_work + 1;
            end else begin
                state <= S_OUTPUT;
            end
        end

        // ------------------------------------------------------------------
        // S_OUTPUT: latch outputs.
        // ------------------------------------------------------------------
        S_OUTPUT: begin
            QUOTIENT_OUT  <= Q_work[DIV_NUM_BITS-1:0];
            REMAINDER_OUT <= N_saved - Q_work[DIV_NUM_BITS-1:0] * D_saved;
            done          <= 1'b1;
            state         <= S_IDLE;
        end

        // ------------------------------------------------------------------
        S_ERROR: begin
            error <= 1'b1;
            done  <= 1'b1;
            state <= S_IDLE;
        end

        default: state <= S_IDLE;

        endcase
    end // CE
end // always

endmodule
