module ssd_mux
  (input  [0:0] clk_12mhz_i
  ,input  [0:0] reset_r
  ,input  [0:0] btn3_deb_w // debounced button connection from top module
  ,input  [7:0] active_temp_c_w // active temperature value from esp32
  ,input  [3:0] disp_ones_r // measured ones digit
  ,input  [3:0] disp_tens_r // measured tens digit
  ,output [7:0] ssd_o);

   logic [14:0] mux_cnt_r; // free running counter to alternate display digits
   logic [3:0] temp_ones_w, temp_tens_w; // binary-coded decimal (bcd) digits for temperature
   logic [3:0] shown_ones_w, shown_tens_w; // actual digits that get shown
   wire [0:0] digit_sel_w; // selects which physical digit gets lit
   wire [3:0] active_bcd_w; // 4-bit bcd number sent to decoder
   wire [6:0] seg_pins_w; // active low segments a-g

   always_ff @(posedge clk_12mhz_i) begin
    if (reset_r) begin // when reset clear the counter
      mux_cnt_r <= '0;
    end else begin
      mux_cnt_r <= mux_cnt_r + 15'd1; // otherwise every clock cycle add 1 to the counter
    end
   end

   always_comb begin // combinational binary to bcd converter for temperature
    if (active_temp_c_w >= 8'd40) begin
      temp_tens_w = 4'd4;
      temp_ones_w = 4'(active_temp_c_w - 8'd40); // truncating 8-bit difference to lower 4 bits
    end else if (active_temp_c_w >= 8'd30) begin
      temp_tens_w = 4'd3;
      temp_ones_w = 4'(active_temp_c_w - 8'd30);
    end else if (active_temp_c_w >= 8'd20) begin
      temp_tens_w = 4'd2;
      temp_ones_w = 4'(active_temp_c_w - 8'd20);
    end else if (active_temp_c_w >= 8'd10) begin
      temp_tens_w = 4'd1;
      temp_ones_w = 4'(active_temp_c_w - 8'd10);
    end else begin
      temp_tens_w = 4'd0;
      temp_ones_w = 4'(active_temp_c_w);
    end
   end
   // when button 3 is held, override distance display with temperature display to verify connection
   assign shown_ones_w = btn3_deb_w ? temp_ones_w : disp_ones_r;
   assign shown_tens_w = btn3_deb_w ? temp_tens_w : disp_tens_r;

   // MSB toggles every ~1.36 ms so that both digits appear lit at the same time to the human eye
   assign digit_sel_w = mux_cnt_r[14];
   assign active_bcd_w = digit_sel_w ? shown_ones_w : shown_tens_w;
   
   // decodes the 4-bit bcd digit into 7 individual led segment patterns
   hex2ssd ssd_inst (
    .hex_i(active_bcd_w),
    .ssd_o(seg_pins_w)
   );

   // concatenated digit select bit as the MSB of the 7 segment lines so the PMOD knows which digit the following pins should light up
   assign ssd_o = {digit_sel_w, seg_pins_w};

endmodule
