module rangefinder
  (input  [0:0] clk_12mhz_i // global clock
  ,input  [0:0] reset_r // global reset
  ,input  [0:0] echo_rising_w // single cycle pulse when echo goes high
  ,input  [0:0] echo_falling_w // single cycle pulse when echo goes low
  ,input  [9:0] ticks_per_cm_w // temperature-affected clock cycles per 1 cm round trip
  ,output [0:0] trig_o // output trigger pulses sent to RCWL sensor
  ,output [3:0] disp_ones_o // latched ones digit output
  ,output [3:0] disp_tens_o); // latched tens digit output

   localparam [1:0] S_TRIGGER   = 2'd0; // State 0: drive trig high to start ping
   localparam [1:0] S_WAIT_ECHO = 2'd1; // State 1: wait for sensor to echo
   localparam [1:0] S_MEASURE   = 2'd2; // State 2: count centimeters while echo is still high
   localparam [1:0] S_COOLDOWN  = 2'd3; // State 3: wait ~333 ms between pings to prevent overlapping signal interference

   logic [1:0]  state_r, state_n; // current state and next state registers
   logic [23:0] timer_r, timer_n; // 24 bit cycle timer (up to ~1.4 seconds)
   logic [9:0]  cm_tick_r, cm_tick_n; // sub-cm cc counter
   logic [3:0]  ones_r, ones_n; // counts ones digit during measurement
   logic [3:0]  tens_r, tens_n; // counts tens digit during measurement
   logic [3:0]  disp_ones_r, disp_tens_r; // Latched distance for 7-seg display
   logic [0:0]  trig_r; // drive signal for combinational trig sensor pin

   always_comb begin // state machine logic block
    state_n = state_r; // Default case: stay in current state
    timer_n = timer_r + 24'd1; // Default case: increment cycle timer by 1 every cc
    cm_tick_n = cm_tick_r; // Default case: hold current tick count
    ones_n = ones_r; // Default case: keep same ones digit
    tens_n = tens_r; // Default case: keep same tens digit
    trig_r = 1'b0; // Default case: Keep trigger pin low (forces an idle)
    case (state_r) // Branch behavior based on the current state
      S_TRIGGER: begin // This is what happens when we receive trigger pulse
        trig_r = 1'b1; // Trig goes high
        cm_tick_n = 10'd0; // clear tick counter before measurement
        ones_n = 4'd0; // reset live ones digit
        tens_n = 4'd0; // reset live tens digit
        if (timer_r >= 24'd125) begin // check if 126 cycles has elapsed
          state_n = S_WAIT_ECHO; // TRANSITION: wait for the return echo rising edge
          timer_n = 24'd0; // reset cycle timer to 0 for timeout check
        end // end of trigger duration check
      end // end trigger case
      S_WAIT_ECHO: begin // Wait for echo to go high state
        if (echo_rising_w) begin // if echo pin goes high
          state_n = S_MEASURE; // TRANSITION: move to active measurement state
          timer_n = 24'd0; // reset the cycle timer
        end else if (timer_r >= 24'd720000) begin // otherwise if 60ms has elapsed with no echo
          state_n = S_TRIGGER; // TRANSITION: move back to the waiting for trigger state
          timer_n = 24'd0; // reset timer
        end // end echo wait check
      end // end case
      S_MEASURE: begin // Measuring echo pulse state
        if (echo_falling_w || (timer_r >= 24'd720000)) begin // if falling edge detected or timeout occurs
          state_n = S_COOLDOWN; // TRANSITION: move to cooldown state before next ping
          timer_n = 24'd0; // reset timer
        end else begin
          if (cm_tick_r >= (ticks_per_cm_w - 10'd1)) begin // otherwise check if 1 full centimeter of time has passed
            cm_tick_n = 10'd0; // reset cycle counter for next cm
            if (ones_r == 4'd9) begin // check if ones digit is about to roll over
              if (tens_r < 4'd9) begin // only increment tens digit if its below 9
                ones_n = 4'd0; // roll ones back to 0
                tens_n = tens_r + 4'd1; // increment tens digit by 1
              end
            end else begin
              ones_n = ones_r + 4'd1; // otherwise just increment ones digit
            end
          end else begin
            cm_tick_n = cm_tick_r + 10'd1; // increment sub-cm cycle counter by 1
          end
        end
      end
      S_COOLDOWN: begin
        if (timer_r >= 24'd4000000) begin // wait ~3 Hz
          state_n = S_TRIGGER; // TRANSITION: move to wait for trigger cycle to start fresh measurement cycle
          timer_n = 24'd0; // reset cycle timer
        end
      end
      default: begin
        state_n = S_TRIGGER; // Here this gives us a clean way to reset if something may prevent us from going back to default case
      end
    endcase
   end
   
   always_ff @(posedge clk_12mhz_i) begin // latches everything to update on posedge of clock
    if (reset_r) begin // essentially resets all moving values to 0 and returns to initial state
      state_r <= S_TRIGGER;
      timer_r <= '0;
      cm_tick_r <= '0;
      ones_r <= '0;
      tens_r <= '0;
      disp_ones_r <= '0;
      disp_tens_r <= '0;
    end else begin // otherwise on each clock edge each register latches to whatever was asserted the past clock cycle, whether it was a new one or to stay the same
      state_r <= state_n;
      timer_r <= timer_n;
      cm_tick_r <= cm_tick_n;
      ones_r <= ones_n;
      tens_r <= tens_n;
      if (state_r == S_MEASURE) begin
        if (echo_falling_w) begin // only update the display if something changes
          disp_ones_r <= ones_r;
          disp_tens_r <= tens_r;
        end else if (timer_r >= 24'd720000) begin // if the measurement times out (i.e. cm is over 99cm) just latch both digits to 99 (max distance readable)
          disp_ones_r <= 4'd9;
          disp_tens_r <= 4'd9;
        end
      end
    end
   end

   // connecting outputs to their logic registers (can be done by just declaring outputs as logic initially but this is better for clarity sometimes)
   assign trig_o = trig_r;
   assign disp_ones_o = disp_ones_r;
   assign disp_tens_o = disp_tens_r;

endmodule
