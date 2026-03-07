`timescale 1ns / 1ps
/*
    tb_divider_newtonraphson_unsigned.sv

    Self-checking testbench for divider_newtonraphson_unsigned.sv.

    Strategy
    --------
    Mirrors the structure of the other testbenches in this repository:
      - TB_TEST_CNT == 0 : exhaustive sweep over all (num, den) combinations
                           at the parameterised width (use 8-bit for CI).
      - TB_TEST_CNT > 0  : corner cases plus TB_TEST_CNT random trials
                           (use for wider operands where exhaustive is impractical).

    Each trial feeds (num, den) into the UUT, waits for done, then checks:
      - QUOTIENT_OUT  == num / den   (integer division)
      - REMAINDER_OUT == num % den
      - error == 0 (for non-zero den)
    For den == 0, only checks that error is asserted.

    Brendan Lynskey 2025
*/

module tb_divider_newtonraphson_unsigned;

// -------------------------------------------------------------------------
// UUT parameters
// -------------------------------------------------------------------------
localparam DIV_NUM_BITS = 8;
localparam DIV_DEN_BITS = 8;
localparam ITERATIONS   = 3;
localparam SEED_BITS    = 4;

// -------------------------------------------------------------------------
// Testbench parameters
// -------------------------------------------------------------------------
localparam [DIV_NUM_BITS-1:0] STIM_NUM_MIN = 0;
localparam [DIV_NUM_BITS-1:0] STIM_NUM_MAX = (2**DIV_NUM_BITS) - 1;
localparam [DIV_DEN_BITS-1:0] STIM_DEN_MIN = 0;
localparam [DIV_DEN_BITS-1:0] STIM_DEN_MAX = (2**DIV_DEN_BITS) - 1;

// TB_TEST_CNT = 0  -> exhaustive; > 0 -> corners + N random.
localparam TB_TEST_CNT = 0;

// Maximum number of cycles to wait for done before declaring a timeout.
localparam TIMEOUT_CYCLES = 64;

// -------------------------------------------------------------------------
// Clock and reset
// -------------------------------------------------------------------------
reg tb_clk  = 1'b0;
reg tb_srst = 1'b1;
reg tb_ce   = 1'b1;

always #5 tb_clk = ~tb_clk;   // 100 MHz

initial begin
    repeat (10) @(negedge tb_clk);
    tb_srst = 1'b0;
end

// -------------------------------------------------------------------------
// UUT connections
// -------------------------------------------------------------------------
reg  [DIV_NUM_BITS-1:0]  tb_numerator;
reg  [DIV_DEN_BITS-1:0]  tb_denominator;
wire [DIV_NUM_BITS-1:0]  tb_quotient;
wire [DIV_DEN_BITS-1:0]  tb_remainder;
reg                       tb_start = 1'b0;
wire                      tb_error;
wire                      tb_done;

// -------------------------------------------------------------------------
// Pass / fail counters
// -------------------------------------------------------------------------
integer pass_cnt = 0;
integer fail_cnt = 0;

// -------------------------------------------------------------------------
// Task: drive one (num, den) pair, wait for done, check outputs
// -------------------------------------------------------------------------
task stim_check_divider;
    input integer num;
    input integer den;
    input integer expected_quot;
    input integer expected_rem;

    integer timeout;
begin
    // Present stimulus
    tb_numerator   = num[DIV_NUM_BITS-1:0];
    tb_denominator = den[DIV_DEN_BITS-1:0];

    @(negedge tb_clk);
    tb_start = 1'b1;
    @(negedge tb_clk);
    tb_start = 1'b0;

    // Wait for done (with timeout guard)
    timeout = 0;
    while (!tb_done && timeout < TIMEOUT_CYCLES) begin
        @(posedge tb_clk);
        timeout = timeout + 1;
    end

    if (timeout >= TIMEOUT_CYCLES) begin
        $display("***TIMEOUT: num=%0d den=%0d — done never asserted", num, den);
        fail_cnt = fail_cnt + 1;
    end else if (den == 0) begin
        if (!tb_error) begin
            $display("***FAIL (div-by-zero flag): num=%0d den=%0d — error not asserted", num, den);
            fail_cnt = fail_cnt + 1;
        end else begin
            pass_cnt = pass_cnt + 1;
        end
    end else begin
        if (tb_error) begin
            $display("***FAIL: num=%0d den=%0d — spurious error", num, den);
            fail_cnt = fail_cnt + 1;
        end else if (tb_quotient !== expected_quot[DIV_NUM_BITS-1:0]) begin
            $display("***FAIL (quotient): num=%0d den=%0d — got Q=%0d expected Q=%0d",
                     num, den, tb_quotient, expected_quot);
            fail_cnt = fail_cnt + 1;
        end else if (tb_remainder !== expected_rem[DIV_DEN_BITS-1:0]) begin
            $display("***FAIL (remainder): num=%0d den=%0d — got R=%0d expected R=%0d",
                     num, den, tb_remainder, expected_rem);
            fail_cnt = fail_cnt + 1;
        end else begin
            pass_cnt = pass_cnt + 1;
        end
    end
end
endtask

// -------------------------------------------------------------------------
// Stimulus process
// -------------------------------------------------------------------------
initial begin

    integer stim_num;
    integer stim_den;

    // Wait for reset to complete
    @(negedge tb_srst);
    repeat (5) @(negedge tb_clk);

    if (TB_TEST_CNT == 0) begin
        // ----------------------------------------------------------------
        // Exhaustive sweep
        // ----------------------------------------------------------------
        for (stim_num = STIM_NUM_MIN; stim_num <= STIM_NUM_MAX; stim_num = stim_num + 1) begin
            for (stim_den = STIM_DEN_MIN; stim_den <= STIM_DEN_MAX; stim_den = stim_den + 1) begin
                if (stim_den == 0) begin
                    stim_check_divider(stim_num, stim_den, 0, 0);
                end else begin
                    stim_check_divider(stim_num, stim_den,
                                       stim_num / stim_den,
                                       stim_num % stim_den);
                end
            end
        end

    end else begin
        // ----------------------------------------------------------------
        // Corner cases
        // ----------------------------------------------------------------
        stim_check_divider(0, 1, 0, 0);
        stim_check_divider(STIM_NUM_MAX, 1, STIM_NUM_MAX, 0);
        stim_check_divider(STIM_NUM_MAX, STIM_DEN_MAX, 1, 0);
        stim_check_divider(1, STIM_DEN_MAX, 0, 1);
        stim_check_divider(STIM_NUM_MAX, 0, 0, 0);

        // ----------------------------------------------------------------
        // Random trials
        // ----------------------------------------------------------------
        for (stim_num = 0; stim_num < TB_TEST_CNT; stim_num = stim_num + 1) begin
            stim_den = $urandom % (2**DIV_DEN_BITS);
            stim_num = $urandom % (2**DIV_NUM_BITS);
            if (stim_den == 0) begin
                stim_check_divider(stim_num, stim_den, 0, 0);
            end else begin
                stim_check_divider(stim_num, stim_den,
                                   stim_num / stim_den,
                                   stim_num % stim_den);
            end
        end
    end

    // ----------------------------------------------------------------
    // Summary
    // ----------------------------------------------------------------
    repeat (10) @(negedge tb_clk);
    $display("\n\t*** TB completed: %0d passed, %0d failed ***", pass_cnt, fail_cnt);
    if (fail_cnt > 0)
        $display("\t*** FAILURES DETECTED — see above ***");
    else
        $display("\t*** ALL TESTS PASSED ***");
    $finish;

end

// -------------------------------------------------------------------------
// UUT instantiation
// -------------------------------------------------------------------------
divider_newtonraphson_unsigned #(
    .DIV_NUM_BITS (DIV_NUM_BITS),
    .DIV_DEN_BITS (DIV_DEN_BITS),
    .ITERATIONS   (ITERATIONS),
    .SEED_BITS    (SEED_BITS)
) u_dut (
    .SRST           (tb_srst),
    .CLK            (tb_clk),
    .CE             (tb_ce),
    .NUMERATOR_IN   (tb_numerator),
    .DENOMINATOR_IN (tb_denominator),
    .QUOTIENT_OUT   (tb_quotient),
    .REMAINDER_OUT  (tb_remainder),
    .start          (tb_start),
    .error          (tb_error),
    .done           (tb_done)
);

endmodule
