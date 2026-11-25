// this counter will hold once at the max or min value unless an input decrements/increments it away
module counter_sat
  #(parameter width_p = 4,
    /* verilator lint_off WIDTHTRUNC */
    parameter [width_p-1:0] reset_val_p = '0,
    // sat_val will always be greater than reset_val_p, and less than (1<< (width_p - 1))
    parameter [width_p-1:0] sat_val_p = '0
    )
    /* verilator lint_on WIDTHTRUNC */
   (input [0:0] clk_i // clock signal
   ,input [0:0] reset_i // reset signal
   ,input [0:0] up_i // up input
   ,input [0:0] down_i // down input
   ,output [width_p-1:0] count_o); // counter output

   logic [width_p-1:0] count_r; // register to hold the count value

   assign count_o = count_r;

   // Your code here:
   always_ff @(posedge clk_i) begin
    if (reset_i) begin // when reset asserted set counter back to value dictated by reset paramter
      count_r <= reset_val_p;
    end else if (up_i && !down_i && (count_r != sat_val_p)) begin // if input is increment and not decrement, and counter is not full
      count_r <= count_r + 1'b1; // increment counter
    end else if (down_i && !up_i && (count_r != '0)) begin // if input is decrement and not incremented, and counter is not empty
      count_r <= count_r - 1'b1; // decrement counter
    end
  end

endmodule
