`timescale 1ns / 1ps
/*
    tb_divider_nonperforming_unsigned.sv
    
    SV TB module for divider_nonperforming_unsigned.sv
    
    Brendan Lynskey 2023
*/


module tb_divider_nonperforming_unsigned;

// Parameterise UUT
localparam DIV_NUM_BITS = 8;
localparam DIV_DEN_BITS = 8;

localparam logic unsigned [DIV_NUM_BITS-1:0] stim_num_min = 0;
localparam logic unsigned [DIV_NUM_BITS-1:0] stim_num_max = (2**DIV_NUM_BITS)-1;
localparam logic unsigned [DIV_DEN_BITS-1:0] stim_den_min = 0;
localparam logic unsigned [DIV_DEN_BITS-1:0] stim_den_max = (2**DIV_DEN_BITS)-1;


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
int     tb_numerator;
int     tb_denominator;
int     tb_quotient;
int     tb_remainder;
                                              
logic   tb_start = 1'b0;
logic   tb_error;
logic   tb_done;

task stim_check_divider(input int num, den, quot, rem);

    // Feed in parameters
    tb_numerator    = num;
    tb_denominator  = den;

    // Initiate computation
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

        // Check results in quotient and remainder
        if (tb_quotient != quot) begin
            $display("***Error in quotient!");
            $stop;
        end
        if (tb_remainder != rem) begin
            $display("***Error in remainder!");
            $stop;
        end
        
    end

endtask

initial begin

    int stim_num;
    int stim_den;

    // Allow reset to complete
    @ (negedge tb_srst);
    for (int i=0; i<5; i++) @ (negedge tb_clk);
    
    



    // Stimulus: sweep divider params exhaustively
    // Check results on the fly
    if (TB_TEST_CNT == 0) begin
        for (stim_num = stim_num_min; stim_num <= stim_num_max; stim_num++)
            for (stim_den = stim_den_min; stim_den <= stim_den_max; stim_den++)
                stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);
                
    end else begin
        // Test extreme values
        stim_num = stim_num_min; stim_den = stim_den_min;
        stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

        stim_num = stim_num_max; stim_den = stim_den_max;
        stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

        stim_num = stim_num_min; stim_den = stim_den_max;
        stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

        stim_num = stim_num_max; stim_den = stim_den_max;
        stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);

        // Test a number of random values
        for (int test_cnt = 0; test_cnt < TB_TEST_CNT; test_cnt++) begin
            stim_num = $urandom % (2**DIV_NUM_BITS);
            stim_den = $urandom % (2**DIV_DEN_BITS);
            //$display("stim_num = %x, stim_den = %x", stim_num, stim_den);
            stim_check_divider(stim_num, stim_den, stim_num/stim_den, stim_num%stim_den);
        end        
    end   

    // Signal completion of TB
    for (int i=0; i<10; i++) @ (negedge tb_clk);
    $display("\n\t***TB completed");
    $stop;
  
end




divider_nonperforming_unsigned #(DIV_NUM_BITS, DIV_DEN_BITS) u_divider_nonperforming_unsigned
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
