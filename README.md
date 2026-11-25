# Temperature-Compensated FPGA Ultrasonic Rangefinder

A hardware/software co-design integrating an **ESP32-C3** microcontroller and an **iCEBreaker v1.1a FPGA** (Lattice iCE40UP5K) to perform real-time, temperature-compensated ultrasonic distance measurement.

The ESP32-C3 polls an onboard SHTC3 temperature/humidity sensor over I2C and transmits the ambient Celsius reading once per second over a **115,200 baud 8N1 UART** link. The FPGA decodes the telemetry in pure SystemVerilog, dynamically recalculates the speed-of-sound clock threshold using fixed-point arithmetic, and drives an **RCWL-1601** ultrasonic rangefinder and 2-digit 7-segment display. A **2.5-second hardware watchdog timer** automatically fails over to a calibrated **25°C** default if the microcontroller link disconnects, and resumes live telemetry upon reconnection.

---

## Repository Structure & Modules

### FPGA SystemVerilog RTL & Bitstream
* **`top.sv`**: Top-level interconnect instantiating 2-FF clock-domain synchronizers, the 25°C failover multiplexer, status LED assignments, and fixed-point speed-of-sound compensation (`Ticks/cm = 724 - ((T * 5) >> 2)`).
* **`uart_rx.sv`**: Custom 115,200 baud 8N1 UART receiver FSM (`104` clocks/bit at 12 MHz) with range validation (`10°C–50°C`) and a 2.5-second (`30,000,000`-cycle) connection watchdog (`esp_connected_o`).
* **`rangefinder.sv`**: 4-state ultrasonic FSM (`S_TRIGGER`, `S_WAIT_ECHO`, `S_MEASURE`, `S_COOLDOWN`) converting return echo pulse width directly into saturated Binary-Coded Decimal (BCD) centimeters (`00–99 cm`).
* **`ssd_mux.sv`**: Time-multiplexed 7-segment display driver (~366 Hz refresh) with combinational binary-to-BCD temperature conversion.
* **`debounce.sv` / `detect_edge.sv` / `counter_sat.sv`**: Synchronous input conditioning, single-cycle edge detection, and saturating counter utility modules.
* **`icebrk.bin`**: Pre-compiled Lattice iCE40UP5K bitstream ready to flash directly to an iCEBreaker v1.1a board.

### ESP32-C3 Firmware (`esp32_fpga_temp/`)
* **`main/main.c`** *(ESP-IDF)*: Configures I2C master (`GPIO 8` SCL, `GPIO 10` SDA) to read and CRC-verify SHTC3 temperature measurements, transmitting rounded 1-byte Celsius packets over `UART1` (`GPIO 4` TX).

---

## Hardware Pinout & Wiring

| Signal | Direction | iCEBreaker Pin | ESP32-C3 / Sensor Pin | Description |
| :--- | :--- | :--- | :--- | :--- |
| **`uart_rx_i`** | Input | PMOD 1B1 (`Pin 43`) | `GPIO 4` (`IO4`) | 115,200 baud UART temperature telemetry |
| **`trig_o`** | Output | PMOD 1B2 (`Pin 38`) | RCWL-1601 `TRIG` | 10.5 µs ultrasonic trigger pulse |
| **`echo_i`** | Input | PMOD 1B3 (`Pin 34`) | RCWL-1601 `ECHO` | Ultrasonic return echo pulse |
| **`3V3` / `GND`** | Power | PMOD 1B `3V3`/`GND` | `3V3` / `GND` | Shared 3.3V rail and common ground reference |

---

## Controls & Status Indicators (PMOD 2)

* **Onboard `UBUTTON`:** Synchronous active-low global system reset.
* **Button 3 (Hold):** Switches the 7-segment display from measured distance (`cm`) to the active temperature (`°C`) currently used by the speed-of-sound datapath.
* **LED 1 (Red):** **ON** when the ESP32 link is disconnected (`25°C` fallback active); **OFF** when receiving live UART packets.
* **LED 2 (Green):** Heartbeat indicator toggling once per second upon receipt of each valid ESP32 temperature byte.
* **LED 3 (Green):** Pulses during active ultrasonic `ECHO` pulse reception.

---

## Flashing & Build Notes

### Flash Pre-Built Bitstream (iCEBreaker v1.1a)
```bash
openFPGALoader -b ice40_generic icebrk.bin
```

### Build & Flash ESP32-C3 Firmware (ESP-IDF v5.x)
```bash
cd esp32_fpga_temp
idf.py build flash monitor
```

### Synthesizing RTL from Source
To synthesize the `.sv` modules from scratch using the open-source **Yosys / nextpnr-ice40 / IceStorm** toolchain, provide an iCEBreaker `.pcf` constraint file matching the pinout table above alongside standard synchronous primitives (`dff`, `inv`, `hex2ssd`).

---

## Acknowledgments
* **Toolchain & Primitive Architecture:** Inspired by the open-source iCEBreaker synthesis workflow and synchronous hardware design patterns developed by **Professor Dustin Richmond** (UCSC Baskin School of Engineering).
