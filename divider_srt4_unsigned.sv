`timescale 1ns / 1ps
/*
    divider_srt4_unsigned.sv

    Synthesisable SystemVerilog -- Radix-4 SRT unsigned integer divider.

    Algorithm overview
    ------------------
    SRT (Sweeney-Robertson-Tocher) radix-4 produces TWO quotient bits per
    iteration cycle, halving latency compared with the radix-2 variants in
    this repository.

    Each cycle performs two consecutive non-restoring steps, producing a
    combined quotient digit q = q1*2 + q2 from the digit set {-3,-2,-1,0,+1,+2,+3}.
    The pair (q1, q2) each come from the radix-2 digit set {-1, +1}.

    Step 1 (within cycle i):
        P_temp = 2*P_in + bit(2i)           -- shift in MSB of the pair
        if P_temp < 0:  q1 = -1,  P_mid = P_temp + D
        else:           q1 = +1,  P_mid = P_temp - D

    Step 2 (within cycle i):
        P_temp = 2*P_mid + bit(2i+1)        -- shift in next bit
        if P_temp < 0:  q2 = -1,  P_out = P_temp + D
        else:           q2 = +1,  P_out = P_temp - D

    Combined digit: q = q1*2 + q2, range {-3,-2,-1,0,+1,+2,+3}.

    Redundant quotient
    ------------------
    q is split into positive and negative contributions:
        if q >= 0:  qpos += q,  qneg unchanged
        if q <  0:  qneg += |q|, qpos unchanged

    Each accumulator grows by 2 bits per iteration.  Final conversion:
        Q = qpos - qneg     (carry-propagate subtraction)

    Remainder correction
    --------------------
    After the last iteration, P lies in (-D, +D).  If P < 0, a correction
    step adds D and decrements Q by 1, giving remainder in [0, D).

    Latency
    -------
    ceil(DIV_NUM_BITS/2) iteration cycles + 3 overhead cycles (IDLE, CORRECT,
    OUTPUT) ~= N/2 + 3  vs  N + 2 for the radix-2 variants.

    Critical path per iteration
    ---------------------------
    Two cascaded adders (Step 1 and Step 2), each of width DEN_BITS + guard.
    Comparable in depth to the non-restoring divider (also one adder), but
    with twice the throughput.

    Interface
    ---------
    Port-compatible with divider_restoring_unsigned and
    divider_nonperforming_unsigned.

    Brendan Lynskey 2025
*/

module divider_srt4_unsigned
#(
    parameter DIV_NUM_BITS = 8,
    parameter DIV_DEN_BITS = 8
)
(
    input  logic                              SRST,
    input  logic                              CLK,
    input  logic                              CE,

    input  logic unsigned [DIV_NUM_BITS-1:0]  NUMERATOR_IN,
    input  logic unsigned [DIV_DEN_BITS-1:0]  DENOMINATOR_IN,
    output logic unsigned [DIV_NUM_BITS-1:0]  QUOTIENT_OUT,
    output logic unsigned [DIV_DEN_BITS-1:0]  REMAINDER_OUT,

    input  logic                              start,
    output logic                              error,
    output logic                              done
);

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------

    localparam ITERS = (DIV_NUM_BITS + 1) / 2;   // ceil(N/2) iterations

    // Signed partial remainder width.
    // P stays in (-D, +D); D is DEN_BITS wide.  Add 2 guard bits to absorb
    // the x2 shift within each step.
    localparam W = DIV_DEN_BITS + 2;

    // FSM states
    localparam [2:0] S_IDLE    = 3'd0,
                     S_ITERATE = 3'd1,
                     S_CORRECT = 3'd2,
                     S_OUTPUT  = 3'd3,
                     S_ERROR   = 3'd4;

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------

    logic [2:0]                        state;
    logic signed [W-1:0]               P;       // Signed partial remainder in (-D, D)
    logic unsigned [DIV_DEN_BITS-1:0]  D;       // Divisor
    logic unsigned [DIV_NUM_BITS+1:0]  qpos;    // Positive redundant quotient
    logic unsigned [DIV_NUM_BITS+1:0]  qneg;    // Negative redundant quotient
    logic [$clog2(ITERS):0]            cnt;
    // Numerator shift register (MSB first)
    logic unsigned [DIV_NUM_BITS-1:0]  num_sr;

    // -------------------------------------------------------------------------
    // Combinational: two cascaded non-restoring steps within each cycle
    // -------------------------------------------------------------------------

    // Signed divisor for arithmetic (zero-extended to W bits)
    logic signed [W-1:0]   Ds;
    assign Ds = $signed({2'b00, D});

    // Step 1: shift in numerator bit (2i) = MSB of num_sr
    logic                   b0;
    logic signed [W-1:0]    P1_in, P_mid;
    logic                   q1;

    assign b0    = num_sr[DIV_NUM_BITS-1];
    assign P1_in = (P <<< 1) + W'(b0);   // 2*P + bit0

    // Non-restoring selection for step 1
    assign q1    = (P1_in[W-1] == 1'b0) ? 1'b1 : 1'b0;   // 1 if P1_in >= 0
    assign P_mid = (q1) ? (P1_in - Ds) : (P1_in + Ds);

    // Step 2: shift in numerator bit (2i+1) = second MSB of num_sr
    logic                   b1;
    logic signed [W-1:0]    P2_in, P_out;
    logic                   q2;

    assign b1    = num_sr[DIV_NUM_BITS-2];
    assign P2_in = (P_mid <<< 1) + W'(b1);   // 2*P_mid + bit1

    assign q2    = (P2_in[W-1] == 1'b0) ? 1'b1 : 1'b0;
    assign P_out = (q2) ? (P2_in - Ds) : (P2_in + Ds);

    // Combined digit: q = q1*2 + q2, range {-3,-2,-1,0,+1,+2,+3}
    // Encoded as signed 3-bit: q1 in {-1,+1} -> q1_s; q2 in {-1,+1} -> q2_s
    logic signed [2:0]      q1_s, q2_s, q_combined;
    assign q1_s       = q1 ? 3'sd1 : -3'sd1;
    assign q2_s       = q2 ? 3'sd1 : -3'sd1;
    assign q_combined = (q1_s <<< 1) + q2_s;   // 2*q1 + q2

    // Unsigned magnitude of the combined digit (for positive/negative split)
    logic [1:0]             q_mag;
    logic signed [2:0]      q_neg_val;
    assign q_neg_val = -q_combined;
    assign q_mag     = q_combined[2] ? q_neg_val[1:0] : q_combined[1:0];

    // -------------------------------------------------------------------------
    // Final quotient and remainder correction (combinational)
    // -------------------------------------------------------------------------

    logic unsigned [DIV_NUM_BITS+1:0]  q_bin_pos, q_bin_neg;
    logic signed   [W-1:0]             P_corrected;

    assign q_bin_pos   = qpos - qneg;
    assign q_bin_neg   = qpos - qneg - 1;
    assign P_corrected = P + Ds;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------

    always_ff @(posedge CLK) begin
        if (SRST) begin
            state         <= S_IDLE;
            QUOTIENT_OUT  <= '0;
            REMAINDER_OUT <= '0;
            error         <= 1'b0;
            done          <= 1'b0;
            P             <= '0;
            D             <= '0;
            qpos          <= '0;
            qneg          <= '0;
            num_sr        <= '0;
            cnt           <= '0;

        end else if (CE) begin

            case (state)

            // ------------------------------------------------------------------
            S_IDLE: begin
                done  <= 1'b0;
                error <= 1'b0;

                if (start) begin
                    if (DENOMINATOR_IN == '0) begin
                        state <= S_ERROR;
                    end else begin
                        D      <= DENOMINATOR_IN;
                        // P starts at 0; numerator bits are shifted in MSB-first.
                        // For odd DIV_NUM_BITS, left-pad num_sr with a 0 bit so
                        // the first iteration pair is {0, MSB(numerator)}.
                        P      <= '0;
                        if (DIV_NUM_BITS[0])
                            num_sr <= {1'b0, NUMERATOR_IN[DIV_NUM_BITS-1:1],
                                       NUMERATOR_IN[0]};
                        else
                            num_sr <= NUMERATOR_IN;
                        qpos   <= '0;
                        qneg   <= '0;
                        cnt    <= ITERS - 1;
                        state  <= S_ITERATE;
                    end
                end
            end

            // ------------------------------------------------------------------
            // Two non-restoring steps per cycle
            // ------------------------------------------------------------------
            S_ITERATE: begin
                P      <= P_out;
                num_sr <= num_sr << 2;   // advance to next bit-pair

                // Accumulate combined digit into redundant quotient
                if (!q_combined[2]) begin
                    // q >= 0
                    qpos <= (qpos << 2) | {{DIV_NUM_BITS{1'b0}}, q_mag};
                    qneg <=  qneg << 2;
                end else begin
                    // q < 0
                    qpos <=  qpos << 2;
                    qneg <= (qneg << 2) | {{DIV_NUM_BITS{1'b0}}, q_mag};
                end

                if (cnt == 0)
                    state <= S_CORRECT;
                else
                    cnt   <= cnt - 1;
            end

            // ------------------------------------------------------------------
            // Remainder correction and quotient output
            // ------------------------------------------------------------------
            S_CORRECT: begin
                if (P[W-1]) begin
                    // P < 0: add D and decrement Q
                    QUOTIENT_OUT  <= q_bin_neg[DIV_NUM_BITS-1:0];
                    REMAINDER_OUT <= P_corrected[DIV_DEN_BITS-1:0];
                end else begin
                    QUOTIENT_OUT  <= q_bin_pos[DIV_NUM_BITS-1:0];
                    REMAINDER_OUT <= P[DIV_DEN_BITS-1:0];
                end
                state <= S_OUTPUT;
            end

            // ------------------------------------------------------------------
            S_OUTPUT: begin
                state <= S_IDLE;
                done  <= 1'b1;
            end

            // ------------------------------------------------------------------
            S_ERROR: begin
                state <= S_IDLE;
                error <= 1'b1;
                done  <= 1'b1;
            end

            default: state <= S_IDLE;

            endcase
        end
    end

endmodule
