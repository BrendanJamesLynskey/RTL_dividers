`timescale 1ns / 1ps
/*
    tb_divider_nonrestoring_signed.sv
    
    SV TB module for divider_nonrestoring_signed.sv    

    Brendan Lynskey 2023
*/


module tb_divider_nonrestoring_signed;

// Parameterise UUT
localparam WORD_WIDTH = 8;

localparam logic signed [WORD_WIDTH-1:0] stim_num_min = -1 * 2**(WORD_WIDTH-1);
localparam logic signed [WORD_WIDTH-1:0] stim_num_max = 2**(WORD_WIDTH-1)-1;
localparam logic signed [WORD_WIDTH-1:0] stim_den_min = -1 * 2**(WORD_WIDTH-1);
localparam logic signed [WORD_WIDTH-1:0] stim_den_max = 2**(WORD_WIDTH-1)-1;


// Parameterise TB
localparam TB_TEST_CNT  = 0; // Zero for exhaustive

// Clocks and resets
logic tb_srst   = 1'b1;
logic tb_clk    = 1'b0;
logic tb_ce     = 1'b1;

initial while (1) #5 tb_clk = ~tb_clk;

initial begin
    for (int i=0; i<10; i++) @ (negedge tb_clk);
    tb_srst = 1'b0;
end


// Stim and checking
logic signed [WORD_WIDTH-1:0] tb_numerator;
logic signed [WORD_WIDTH-1:0] tb_denominator;
logic signed [WORD_WIDTH-1:0] tb_quotient;
logic signed [WORD_WIDTH-1:0] tb_remainder;

                                              
logic   tb_start = 1'b0;
logic   tb_error;
logic   tb_done;

task stim_check_divider(input logic signed [WORD_WIDTH-1:0] num,
                        input logic signed [WORD_WIDTH-1:0] den );

    // Feed stimulus into UUT, then initiate computation
    tb_numerator    = num;
    tb_denominator  = den;
    @ (negedge tb_clk);
    tb_start        = 1'b1;
    @ (negedge tb_clk);
    tb_start        = 1'b0;
    
    
    // Await completion
    while (!tb_done) @(posedge tb_clk);


    // Check results
    if (tb_denominator == 0) begin
    
        // When denominator is zero, only check that ERROR is asserted
        if (tb_error != 1'b1) begin
            $display("***Error in error signal (divide-by-zero)!");
            $stop;
        end
        
    end else begin

        // Division produces non-unique results
        //  signed inputs produces number of possible quotient-remainder combinations
        // Check that computed result is congruent to correct result
        //  Do not check that signs of results match SV arithmetic sign convention
        if ((den*(num/den)+(num%den)) != (tb_denominator*tb_quotient+tb_remainder)) begin
            $display("***Error! Test: %d / %d", num, den);
            $display("SV calc: num=%d, den=%d, num/den=%d, num_mod_den=%d", num, den, (num/den), (num%den));
            $display("\tTB calculated quotient, remainder, implicit numerator: %d %d %d", (num/den), (num%den), (den*(num/den)+(num%den)));
            $display("\tUUT calculated quotient, remainder, implicit numerator:%d %d %d", tb_quotient, tb_remainder, (tb_denominator*tb_quotient+tb_remainder));
            $stop;
        end
        
    end

endtask

initial begin

    // Create stimulus in 2-state signed 32b integers
    logic signed [WORD_WIDTH-1:0] stim_num;
    logic signed [WORD_WIDTH-1:0] stim_den;


    // Allow reset to complete
    @ (negedge tb_srst);
    for (int i=0; i<5; i++) @ (negedge tb_clk);

        
    // Stimulus: sweep divider params exhaustively
    // Check results on the fly
    if (TB_TEST_CNT == 0) begin
        for (stim_num = stim_num_min; stim_num <= stim_num_max; stim_num++)
            for (stim_den = stim_den_min; stim_den <= stim_num_max; stim_den++)
                stim_check_divider(stim_num, stim_den);
                
    end else begin
        // Test extreme values
        stim_num = 0; stim_den = 0;
        stim_check_divider(stim_num, stim_den);

        stim_num = 0; stim_den = stim_den_min;
        stim_check_divider(stim_num, stim_den);

        stim_num = stim_num_min; stim_den = stim_den_min;
        stim_check_divider(stim_num, stim_den);

        stim_num = stim_num_min; stim_den = stim_den_max;
        stim_check_divider(stim_num, stim_den);

        stim_num = stim_num_max; stim_den = stim_den_min;
        stim_check_divider(stim_num, stim_den);

        stim_num = stim_num_max; stim_den = stim_den_max;
        stim_check_divider(stim_num, stim_den);


        // Test a number of random values
        for (int test_cnt = 0; test_cnt < TB_TEST_CNT; test_cnt++) begin
            stim_num = $random;
            stim_den = $random;
            //$display("stimulus: %d / %d", stim_num, stim_den);
            stim_check_divider(stim_num, stim_den);
        end        
    end   

    // Signal completion of TB
    for (int i=0; i<10; i++) @ (negedge tb_clk);
    $display("\n\t***TB completed");
    $stop;
  
end




divider_nonrestoring_signed #(WORD_WIDTH) u_divider_nonrestoring_signed
(

    .SRST               (tb_srst),
    .CLK                (tb_clk),
    .CE                 (tb_ce),
    
    .NUMERATOR_IN       (tb_numerator),
    .DENOMINATOR_IN     (tb_denominator),
    .QUOTENT_OUT        (tb_quotient),
    .REMAINDER_OUT      (tb_remainder),
        
    .start              (tb_start),
    .error              (tb_error),
    .done               (tb_done)
    
);


     
endmodule
