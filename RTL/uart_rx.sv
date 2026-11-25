module uart_rx (
    input [0:0] clk_12mhz_i,
    input [0:0] reset_r,
    input [0:0] uart_rx_r,
    output [7:0] esp_temp_c_o,
    output [0:0] uart_rx_led_o,
    output [0:0] esp_connected_o
);
  // Similar to the rangefinder module, declare the states as localparams
   localparam [1:0] U_IDLE  = 2'd0;
   localparam [1:0] U_START = 2'd1;
   localparam [1:0] U_DATA  = 2'd2;
   localparam [1:0] U_STOP  = 2'd3;

   logic [1:0] u_state_r; // current uart state
   logic [6:0] u_tick_r; // clock divider
   logic [2:0] u_bit_idx_r; // tracks which bit is currently being sampled
   logic [7:0] u_shift_r; // temporary register assembling 8 incoming serial bits
   logic [7:0] esp_temp_c_r; //latched output temp register
   logic [0:0] uart_rx_led_r; // I wanted to show that the uart bridge between the esp32 and fpga are working so I included a toggling led to show sustained connection
   logic [24:0] watchdog_cnt_r; // counts clock cycles since last valid packet and times out after 2.5s, then the fpga switches to using a constant 25C value for measuring
   logic [0:0] esp_connected_r; // connection status flag

   // Built-In 115,200 Baud 8N1 UART Receiver (104 clocks/bit @ 12 MHz)
   always_ff @(posedge clk_12mhz_i) begin
     if (reset_r) begin // upon reset go back to initial state and clear all registers
       u_state_r       <= U_IDLE;
       u_tick_r        <= 7'd0;
       u_bit_idx_r     <= 3'd0;
       u_shift_r       <= 8'd0;
       esp_temp_c_r    <= 8'd25;
       uart_rx_led_r   <= 1'b0;
       watchdog_cnt_r  <= 25'd0;
       esp_connected_r <= 1'b0;
     end else begin
       // 2.5-second watchdog timer (30,000,000 cycles @ 12 MHz)
       if (watchdog_cnt_r >= 25'd30000000) begin // if 2.5s go by with no packet sent, turn off led indicating lost connection
         esp_connected_r <= 1'b0;
         uart_rx_led_r   <= 1'b0;
       end else begin
         watchdog_cnt_r <= watchdog_cnt_r + 25'd1; // 
       end
       // state transitions pretty much the same as other modules
       case (u_state_r)
         U_IDLE: begin
           u_tick_r <= 7'd0;
           if (uart_rx_r == 1'b0) u_state_r <= U_START;
         end
         U_START: begin
           if (u_tick_r == 7'd51) begin
             if (uart_rx_r == 1'b0) begin
               u_tick_r    <= 7'd0;
               u_bit_idx_r <= 3'd0;
               u_state_r   <= U_DATA;
             end else begin
               u_state_r <= U_IDLE;
             end
           end else begin
             u_tick_r <= u_tick_r + 7'd1;
           end
         end
         U_DATA: begin
           if (u_tick_r == 7'd103) begin
             u_tick_r               <= 7'd0;
             u_shift_r[u_bit_idx_r] <= uart_rx_r;
             if (u_bit_idx_r == 3'd7) u_state_r <= U_STOP;
             else                     u_bit_idx_r <= u_bit_idx_r + 3'd1;
           end else begin
             u_tick_r <= u_tick_r + 7'd1;
           end
         end
         U_STOP: begin
           if (u_tick_r == 7'd103) begin
             u_state_r <= U_IDLE;
             if ((u_shift_r >= 8'd10) && (u_shift_r <= 8'd50)) begin
               esp_temp_c_r    <= u_shift_r;
               uart_rx_led_r   <= ~uart_rx_led_r;
               watchdog_cnt_r  <= 25'd0;
               esp_connected_r <= 1'b1;
             end
           end else begin
             u_tick_r <= u_tick_r + 7'd1;
           end
         end
         default: u_state_r <= U_IDLE;
       endcase
     end
   end

  assign esp_temp_c_o    = esp_temp_c_r;
  assign uart_rx_led_o   = uart_rx_led_r;
  assign esp_connected_o = esp_connected_r;

endmodule
