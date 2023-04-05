`timescale 1ns / 1ps
/*
    divider_restoring_unsigned.sv
    SV module which implements synthesisable restoring unsigned integer divide
    
    Uses extended working register:
        Numerator is first loaded as 'initial remainder'
        Extra MS bits allow alignment of MSb of numerator to LSb of denominator, and sign-bit
        As LS bits vacated, LS bits used to store result (quotient)
        Denominator remains left-shifted by constant throughout computation
    
    Process iterated for all numerator bits:
        subtract den from rem, restoring if result is negative
        left-shift new remainder, re-aligning denominator
        result bits (quotient) stored in LS bits of same register, as vacated by shifts

    TODO: could add numerator leading-zeros detector, to eliminate unnecessary MS operations

    Brendan Lynskey 2023
*/

module divider_restoring_unsigned
# (
    parameter DIV_NUM_BITS          = 8,
    parameter DIV_DEN_BITS          = 8    
)
(

    input           SRST,
    input           CLK,
    input           CE,
    
    input  logic unsigned [DIV_NUM_BITS-1:0]  NUMERATOR_IN,
    input  logic unsigned [DIV_DEN_BITS-1:0]  DENOMINATOR_IN,
    output logic unsigned [DIV_NUM_BITS-1:0]  QUOTENT_OUT,
    output logic unsigned [DIV_DEN_BITS-1:0]  REMAINDER_OUT,

    
    input  logic    start,
    output logic    error,
    output logic    done
    
);

// Internal registers
logic unsigned [DIV_DEN_BITS-1:0]  den;
logic signed   [DIV_NUM_BITS+DIV_DEN_BITS-1:0]  rem_quot;

// FSM definitions
enum {S_IDLE, S_SUBTRACT, S_RESTORE, S_ERROR, S_OUTPUT} state;
logic [$clog2(DIV_NUM_BITS)-1:0] cnt_subs;

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
            
            // On start:
            // Sample parameters
            // If denominator is zero, flag error, else:
            //      Numerator loaded as initial remainder
            //      Shift denominator to align LSb with MSb of remainder
            S_IDLE: begin
                done        <= 1'b0;
                error       <= 1'b0;
    
                if (start) begin
                    rem_quot    <= NUMERATOR_IN;
                    den         <= DENOMINATOR_IN; 
                    cnt_subs    <= DIV_NUM_BITS-1;
                    
                    if (DENOMINATOR_IN == '0) begin
                        state       <= S_ERROR;
                    end else begin
                        state       <= S_SUBTRACT;
                    end
                end                        
            end
            
            // Subtract current denominator from current remainder, to compare sizes
            S_SUBTRACT: begin        
                rem_quot    <= rem_quot - (den << (DIV_NUM_BITS-1));
                state       <= S_RESTORE;
            end
            
            // Left-shift rem_quot to keep it aligned with denominator
            // If result negative, restore subtracted denom before shifting
            // If result positive, record '1' in quotient
            //
            // Quotient result bits stored in rem_quot LS bits as left-shifting frees space
            //    Quotient result bits left-shifted with remainder
            S_RESTORE: begin
                if (rem_quot < 0) begin
                    rem_quot     <= (rem_quot + (den << (DIV_NUM_BITS-1)))<<1;
                end else begin
                    rem_quot     <= (rem_quot << 1) + 1;
                end
                
                if (cnt_subs == 0)
                    state       <= S_OUTPUT;
                else
                    state       <= S_SUBTRACT;
    
                cnt_subs    <= cnt_subs - 1;
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
            
                QUOTENT_OUT     <= rem_quot[DIV_NUM_BITS-1:0];
                REMAINDER_OUT   <= rem_quot[DIV_NUM_BITS+DIV_DEN_BITS-1:DIV_NUM_BITS];
                
                done            <= 1'b1;
            end    
            
            endcase
            
        end // CE
    end // not SRST
end // always_ff



endmodule
