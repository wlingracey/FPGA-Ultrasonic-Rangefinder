module top
  (input [0:0] clk_12mhz_i // global clock signal
  ,input [0:0] reset_n_async_unsafe_i
  ,input [3:1] button_async_unsafe_i
  ,input [0:0] uart_rx_i // FOR ESP32 COMMUNICATION
  ,input [0:0] echo_i
  ,output [0:0] trig_o
  ,output [7:0] ssd_o
  ,output [5:1] led_o);
   wire [0:0] reset_n_sync_r;
   wire [0:0] reset_sync_r;
   wire [0:0] reset_r; // global reset signal

   // The next 3 modules are from the lab environment created by Professor Richmond
   dff
     #()
   sync_a
     (.clk_i(clk_12mhz_i)
     ,.reset_i(1'b0)
     ,.en_i(1'b1)
     ,.d_i(reset_n_async_unsafe_i)
     ,.q_o(reset_n_sync_r));

   inv
     #()
   inv
     (.a_i(reset_n_sync_r)
     ,.b_o(reset_sync_r));

   dff
     #()
   sync_b
     (.clk_i(clk_12mhz_i)
     ,.reset_i(1'b0)
     ,.en_i(1'b1)
     ,.d_i(reset_sync_r)
     ,.q_o(reset_r));
       
  // CODE STARTS HERE:

   wire [0:0] button_sync_r; // temp toggle button
   wire [0:0] button_r;

   wire [0:0] echo_sync_r;
   wire [0:0] echo_r; // for sound pulse
   wire [0:0] echo_rising_w; // when starting to receive
   wire [0:0] echo_falling_w; // right when full return

   wire [0:0] uart_sync_r;
   wire [0:0] uart_rx_r;

   wire [0:0] btn3_deb_w;


   // Button synchronizer for button 3
   dff #() sync_btn3_a (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(button_async_unsafe_i[3]),
    .q_o(button_sync_r)
   );

   dff #() sync_btn_b (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(button_sync_r),
    .q_o(button_r)
   );

   // RCWL-1601 ECHO pin synchronizer + edge detector
   // Synchronizer ensures all signals received happen with the clock
   // edge detector ensures all signals happen on the right clock edge
   dff #() sync_echo_a (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(echo_i),
    .q_o(echo_sync_r)
    );

   dff #() sync_echo_b (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(echo_sync_r),
    .q_o(echo_r)
    );

   detect_edge echo_edge_inst (
    .clk_i(clk_12mhz_i),
    .reset_i(reset_r),
    .button_i(echo_r),
    .button_o(echo_rising_w),
    .unbutton_o(echo_falling_w)
    );

   // ESP32 UART RX pin synchronizer
   dff #() sync_uart_a (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(uart_rx_i),
    .q_o(uart_sync_r)
    );

   dff #() sync_uart_b (
    .clk_i(clk_12mhz_i),
    .reset_i(1'b0),
    .en_i(1'b1),
    .d_i(uart_sync_r),
    .q_o(uart_rx_r)
    );

   // Button 3: Level/Hold button (Hold to inspect temperature on 7-seg display)
   debounce #(
    .min_delay_p(16'd60000)
    ) deb_btn3 (
      .clk_i(clk_12mhz_i),
      .reset_i(reset_r),
      .button_i(button_r),
      .button_o(btn3_deb_w)
    );

      // --- Stage 2 Declarations: UART RX & Temperature Math ---
   wire [7:0] esp_temp_c_r;
   wire [0:0] uart_rx_led_r;
   wire [0:0] esp_connected_w;
   wire [7:0] active_temp_c_w;
   wire [9:0] ticks_per_cm_w;

   uart_rx uart_rx_inst (
     .clk_12mhz_i(clk_12mhz_i),
     .reset_r(reset_r),
     .uart_rx_r(uart_rx_r),
     .esp_temp_c_o(esp_temp_c_r),
     .uart_rx_led_o(uart_rx_led_r),
     .esp_connected_o(esp_connected_w)
   );

   assign active_temp_c_w = esp_connected_w ? esp_temp_c_r : 8'd25; // Use live ESP32 temp when connected, else default to 25C
   assign ticks_per_cm_w = 10'd724 - 10'((active_temp_c_w * 8'd5) >> 2); // distance calculation

   // state machine for the rangefinder
   wire [3:0] disp_ones_r, disp_tens_r;

   rangefinder rangefinder_inst (
     .clk_12mhz_i(clk_12mhz_i),
     .reset_r(reset_r),
     .echo_rising_w(echo_rising_w),
     .echo_falling_w(echo_falling_w),
     .ticks_per_cm_w(ticks_per_cm_w),
     .trig_o(trig_o),
     .disp_ones_o(disp_ones_r),
     .disp_tens_o(disp_tens_r)
   );

   ssd_mux ssd_mux_inst (
     .clk_12mhz_i(clk_12mhz_i),
     .reset_r(reset_r),
     .btn3_deb_w(btn3_deb_w),
     .active_temp_c_w(active_temp_c_w),
     .disp_ones_r(disp_ones_r),
     .disp_tens_r(disp_tens_r),
     .ssd_o(ssd_o)
   );

   assign led_o[1] = ~esp_connected_w; // Red LED 1: ON when no ESP32 connection (25C fallback), OFF when ESP32 is sending
   assign led_o[2] = uart_rx_led_r;    // Green LED 2: Flashes every second during continuous ESP32 data stream
   assign led_o[3] = echo_r;           // Green LED 3: Flashes as ultrasonic echo pulses return
   assign led_o[4] = 1'b0;             // Unused (OFF)
   assign led_o[5] = 1'b0;             // Unused (OFF)


endmodule
