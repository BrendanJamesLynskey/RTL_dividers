`timescale 1ns / 1ps
/*
    divider_nonrestoring_signed.sv
    SV module which implements synthesisable 'non-restoring' signed integer divide

    Numerator and denominator have same word-width
        Independent widths would necessitate internal extension anyway, in order to preserve sign-bits

    
    Iterative division algorithm, related to 'long division', producing:
        Polynomial with coefficients +/-1, which codes quotient
        Remainder within range +/- denominator
    For each iteration:
        shift new numerator bit into remainder register (MSb into LSb)
        (shifting re-aligns new remainder MSb to denominator LSb)
        reduce remainder magnitude by adding or subtracting denominator
        record choice of operation in result quotient polynomial
     Note: alignment implies zero-magnitude in less significant part of denominator, which has no effect on results
     At the end:
        convert quotient polynomial to 2's complement form
        
        
     Note: division produces non-unique results
        Signed inputs produces number of possible quotient-remainder combinations
        No attempt is made to adjust output signs
    
    TODO:
        Could add numerator leading-zeros detector to FSM
        Compare Fmax of dividers
    

    Brendan Lynskey 2023
*/

module divider_nonrestoring_signed
# (
    parameter WORD_WIDTH        = 10
)
(

    input           SRST,
    input           CLK,
    input           CE,
    
    input  logic signed [WORD_WIDTH-1:0]    NUMERATOR_IN,
    input  logic signed [WORD_WIDTH-1:0]    DENOMINATOR_IN,
    output logic signed [WORD_WIDTH-1:0]    QUOTENT_OUT,
    output logic signed [WORD_WIDTH-1:0]    REMAINDER_OUT,

    
    input  logic    start,
    output logic    error,
    output logic    done
    
);

// Internal registers
logic signed [WORD_WIDTH-1:0] den;
logic signed [WORD_WIDTH-1:0] rem;
logic signed [WORD_WIDTH-1:0] quot_poly;
logic signed [WORD_WIDTH-1:0] quot_2c;
logic signed [WORD_WIDTH-1:0] quot_2c_d;


// FSM definitions
enum {  S_IDLE,
        S_ADD_DEN_REM, S_SUB_DEN_REM, S_STORE_QUOT,
        S_ERROR, S_OUTPUT} state;
logic [$clog2(WORD_WIDTH)-1:0] cnt_bits;

always_ff @(posedge CLK) begin

    if (SRST) begin
        state           <= S_IDLE;
        QUOTENT_OUT     <= '0;
        REMAINDER_OUT   <= '0;
        error           <= '0;
        done            <= 1'b0;

    end else begin
    
        if (CE) begin

            unique case(state)
            
            // Store numerator temporarily in quot_poly reg;
            //  numerator shifted-out as quotient coeffs shifted-in
            //
            // On start:
            //  Sample parameters
            //  Prime rem shift-reg with MSb of numerator
            //  If denominator is zero flag error, else perform computation
            //      
            S_IDLE: begin
                done        <= 1'b0;
                error       <= 1'b0;
    
                if (start) begin
                    // Prime rem register with correct sign-extension for numerator
                    if (den>=0)
                        {rem, quot_poly} <= {'0, NUMERATOR_IN};
                    else
                        {rem, quot_poly} <= {'1, NUMERATOR_IN};

                    den         <= DENOMINATOR_IN; 

                    cnt_bits    <= WORD_WIDTH-1;
                    
                    // Check inputs:
                    //  Output q=0, r=0 whenever numerator is zero
                    //  Signal error for divide-by-zero
                    if (DENOMINATOR_IN == '0) begin 
                        state       <= S_ERROR;
                    end else begin
                        state       <= S_STORE_QUOT;
                    end
                end                        
            end
            
            // Shift rem and quot_poly regs,
            //  shifting another bit of quot_poly into rem LSb
            //
            // Update quot_poly reg according to sgn(rem),
            //  registering that value for next iteration
            S_STORE_QUOT: begin

                // Shift remainder and quot_poly regs left
                //  NB - non-blocking assignment
                {rem, quot_poly}    <= {rem, quot_poly} << 1;

                // Choose next operation before the shift completes
                // Record coeff for sign of quotient wrt pre-shift remainder
                //  Over-ride previous non-blocking assignment to quot_poly[0]
                if ((den>0 && rem<0) || (den<0 && rem>=0)) begin
                    state           <= S_ADD_DEN_REM;
                    quot_poly[0]    <= 1'b0;    // Coeff for '-1' coefficient
                end else begin
                    state           <= S_SUB_DEN_REM;
                    quot_poly[0]    <= 1'b1;    // Coeff for '+1' coefficient
                end
            end

            // Reduce magnitude of rem by adding aligned denominator
            S_ADD_DEN_REM: begin            
                if (cnt_bits == 0) begin
                    quot_2c_d   <= quot_2c; 
                    state       <= S_OUTPUT;
                end else begin
                    state       <= S_STORE_QUOT;
                end

                cnt_bits    <= cnt_bits - 1;                
             
                rem         <= rem + den;
            end

            // Reduce magnitude of rem by subtracting aligned denominator
            S_SUB_DEN_REM: begin            
                if (cnt_bits == 0) begin
                    quot_2c_d   <= quot_2c; 
                    state       <= S_OUTPUT;
                end else begin
                    state       <= S_STORE_QUOT;
                end

                cnt_bits    <= cnt_bits - 1;                
             
                rem         <= rem - den;
            end
                                
            // Signal error in parameters (divide-by-zero)
            S_ERROR: begin  
                state           <= S_IDLE;
                        
                error           <= 1'b1;
                done            <= 1'b1;
            end    
            
            // Output result
            default: begin  //S_OUTPUT
                state           <= S_IDLE;
            
                QUOTENT_OUT     <= quot_2c_d;
                REMAINDER_OUT   <= rem[WORD_WIDTH-1:0];
                
                done            <= 1'b1;
            end    
            
            endcase
            
        end // CE
    end // not SRST
end // always_ff

// Convert quotient polynomial to 2's complement format:
//  Then basic relationship holds: numerator = rem + den*quot_2c
//  Equivalent conversion would be quot_2c = (quot_poly << 1) + 1;
assign quot_2c = quot_poly - ~quot_poly;


endmodule
