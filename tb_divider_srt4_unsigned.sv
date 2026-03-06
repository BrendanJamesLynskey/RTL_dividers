`timescale 1ns / 1ps
/*
    tb_divider_srt4_unsigned.sv

    Self-checking testbench for divider_srt4_unsigned.sv.

    Test strategy
    -------------
    TB_TEST_CNT = 0  ->  exhaustive sweep over all (numerator, denominator)
                          pairs.  Full coverage at 8-bit width.
    TB_TEST_CNT = N  ->  corner cases + N random pairs.  Use for widths > 8
                          where exhaustive simulation is impractical.

    For every valid pair the testbench verifies:
        QUOTIENT_OUT  == numerator / denominator   (integer truncation)
        REMAINDER_OUT == numerator % denominator

    For denominator = 0 the testbench verifies that the error flag is asserted.

    Brendan Lynskey 2025
*/

module tb_divider_srt4_unsigned;

    // -------------------------------------------------------------------------
    // UUT parameters
    // -------------------------------------------------------------------------
    localparam DIV_NUM_BITS = 8;
    localparam DIV_DEN_BITS = 8;

    // -------------------------------------------------------------------------
    // Testbench parameters
    // -------------------------------------------------------------------------
    localparam TB_TEST_CNT = 0;   // 0 = exhaustive

    localparam logic unsigned [DIV_NUM_BITS-1:0] stim_num_min = 0;
    localparam logic unsigned [DIV_NUM_BITS-1:0] stim_num_max = (2**DIV_NUM_BITS) - 1;
    localparam logic unsigned [DIV_DEN_BITS-1:0] stim_den_min = 0;
    localparam logic unsigned [DIV_DEN_BITS-1:0] stim_den_max = (2**DIV_DEN_BITS) - 1;

    // -------------------------------------------------------------------------
    // Clocks and resets
    // -------------------------------------------------------------------------
    logic tb_srst = 1'b1;
    logic tb_clk  = 1'b0;
    logic tb_ce   = 1'b1;

    initial forever #5 tb_clk = ~tb_clk;

    initial begin
        repeat (10) @(negedge tb_clk);
        tb_srst = 1'b0;
    end

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic unsigned [DIV_NUM_BITS-1:0] tb_numerator;
    logic unsigned [DIV_DEN_BITS-1:0] tb_denominator;
    logic unsigned [DIV_NUM_BITS-1:0] tb_quotient;
    logic unsigned [DIV_DEN_BITS-1:0] tb_remainder;
    logic                             tb_start = 1'b0;
    logic                             tb_error;
    logic                             tb_done;

    // -------------------------------------------------------------------------
    // Stimulus / check task
    // -------------------------------------------------------------------------
    task stim_check_divider(input int num, den, quot, rem);

        tb_numerator   = num[DIV_NUM_BITS-1:0];
        tb_denominator = den[DIV_DEN_BITS-1:0];

        @(negedge tb_clk);
        tb_start = 1'b1;
        @(negedge tb_clk);
        tb_start = 1'b0;

        // Wait for completion
        while (!tb_done) @(posedge tb_clk);

        if (den == 0) begin
            if (!tb_error) begin
                $display("***ERROR: divide-by-zero not flagged (num=%0d)", num);
                $stop;
            end
        end else begin
            if (tb_quotient != quot[DIV_NUM_BITS-1:0]) begin
                $display("***QUOTIENT ERROR: %0d / %0d  expected %0d  got %0d",
                         num, den, quot, tb_quotient);
                $stop;
            end
            if (tb_remainder != rem[DIV_DEN_BITS-1:0]) begin
                $display("***REMAINDER ERROR: %0d / %0d  expected rem %0d  got %0d",
                         num, den, rem, tb_remainder);
                $stop;
            end
        end

    endtask

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin : stim_proc
        int stim_num, stim_den;

        @(negedge tb_srst);
        repeat (5) @(negedge tb_clk);

        if (TB_TEST_CNT == 0) begin
            // Exhaustive sweep
            for (stim_num = stim_num_min; stim_num <= stim_num_max; stim_num++)
                for (stim_den = stim_den_min; stim_den <= stim_den_max; stim_den++)
                    stim_check_divider(stim_num, stim_den,
                                       stim_den ? stim_num/stim_den : 0,
                                       stim_den ? stim_num%stim_den : 0);
        end else begin
            // Corner cases
            stim_num = 0;             stim_den = 0;
            stim_check_divider(stim_num, stim_den, 0, 0);

            stim_num = 0;             stim_den = 1;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = 1;             stim_den = 1;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = stim_num_max;  stim_den = 1;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = stim_num_max;  stim_den = stim_den_max;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = stim_num_min;  stim_den = stim_den_max;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = 127;           stim_den = 7;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = 200;           stim_den = 13;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            stim_num = 255;           stim_den = 255;
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

            // Random cases
            for (int i = 0; i < TB_TEST_CNT; i++) begin
                stim_num = $urandom % (1 << DIV_NUM_BITS);
                stim_den = $urandom % (1 << DIV_DEN_BITS);
                stim_check_divider(stim_num, stim_den,
                                   stim_den ? stim_num/stim_den : 0,
                                   stim_den ? stim_num%stim_den : 0);
            end
        end

        repeat (10) @(negedge tb_clk);
        $display("\n\t***TB completed (SRT-4 unsigned)");
        $stop;
    end

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    divider_srt4_unsigned #(DIV_NUM_BITS, DIV_DEN_BITS) u_dut (
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
