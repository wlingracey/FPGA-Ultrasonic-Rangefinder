// The debounce module exists so that when a button press is made, the rapid micro-movements from the physical contact doesn't trigger false signals
// Using this, button presses get passed cleanly so that they are only counted as single inputs
module debounce
  #(parameter min_delay_p = 4
    )
   (input [0:0] clk_i // connected to global clock
   ,input [0:0] reset_i // connected to global reset
   ,input [0:0] button_i // button press we just got
   ,output [0:0] button_o); // debounced button press we want to output

   wire [15:0] timer_w;

   counter_sat #(.width_p(16), // uses the saturating counter
   .sat_val_p(min_delay_p), // here the saturated value will be the minimum delay required to dissolve debounce signals
   .reset_val_p(16'd0)
   ) counter_sat_inst(
    .clk_i(clk_i), // connects clocks together
    .reset_i(reset_i), // connects resets together
    .up_i(button_i), // when button is pressed, increment counter
    .down_i(~button_i), // decrement when button is not pressed (keeps counter at 0, in logic it takes time, irl its practically instant)
    .count_o(timer_w)
   );

  assign button_o = (timer_w == 16'(min_delay_p)); // our outputted button press is asserted when the counter has hit the saturated value

   
endmodule
