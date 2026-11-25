// edge detectors convert button presses into clean one cycle pulses so that logic that needs button presses sees only one press
module detect_edge
   (input [0:0] clk_i
    // reset_i will go low at least one cycle before a button is pushed.
   ,input [0:0] reset_i
   ,input [0:0] button_i
    // Should go high for 1 cycle, after a positive edge
   ,output [0:0] button_o
    // Should go high for 1 cycle, after a negative edge
   ,output [0:0] unbutton_o
   );

   logic [0:0] old_button_r;
   logic [0:0] button_r;
   logic [0:0] unbutton_r;

   assign button_o = button_r;
   assign unbutton_o = unbutton_r;

   always_ff @(posedge clk_i) begin
      if (reset_i) begin // resets all our logic registers to 0
         old_button_r <= 1'b0;
         button_r <= 1'b0;
         unbutton_r <= 1'b0;
      end else begin // otherwise syncs the button press with the clock so that we only get one pulse from a button press
         old_button_r <= button_i;
         button_r <= (button_i && ~old_button_r);
         unbutton_r <= (~button_i && old_button_r);
      end
   end


endmodule
