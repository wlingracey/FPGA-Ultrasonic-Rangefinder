# Temperature-Compensated FPGA Ultrasonic Rangefinder

A hardware/software co-design integrating an **ESP32-C3** microcontroller and an **iCEBreaker v1.1a FPGA** (Lattice iCE40UP5K) to perform real-time, temperature-compensated ultrasonic distance measurement.

The ESP32-C3 polls an onboard SHTC3 temperature/humidity sensor over I2C and transmits the ambient Celsius reading once per second over a **115,200-baud 8N1 UART** link. The FPGA decodes the telemetry in SystemVerilog, dynamically recalculates the speed-of-sound clock threshold using fixed-point arithmetic, and drives an **RCWL-1601** ultrasonic rangefinder and 2-digit 7-segment display. A **2.5-second hardware watchdog timer** automatically fails over to a calibrated **25°C** default if the microcontroller link disconnects, and resumes live telemetry upon reconnection.

---

## Repository Structure

```text
FPGA-Ultrasonic-Rangefinder/
├── RTL/
│   ├── top.sv             # Top-level interconnect, 2-FF synchronizers, 25°C failover mux, fixed-point compensation
│   ├── uart_rx.sv         # 115,200-baud 8N1 UART receiver FSM with 10°C–50°C validation & 2.5s watchdog
│   ├── rangefinder.sv     # 4-state ultrasonic FSM converting echo pulse width to saturated BCD cm (00–99)
│   ├── ssd_mux.sv         # Time-multiplexed 7-segment display driver (~366 Hz) & binary-to-BCD converter
│   ├── debounce.sv        # Synchronous button debouncer
│   ├── detect_edge.sv     # Single-cycle edge detector
│   ├── counter_sat.sv     # Parameterized saturating counter
│   └── icebrk.bin         # Pre-compiled Lattice iCE40UP5K bitstream
├── ESP-IDF_firmware/
│   └── main/
│       └── main.c         # ESP32-C3 I2C SHTC3 reader (CRC-verified) & UART1 telemetry transmitter
└── README.md
```

---

## Hardware Architecture & Pinout

### Datapath Highlights
* **Fixed-Point Speed-of-Sound Compensation (`RTL/top.sv`):** Dynamically adjusts echo clock ticks per centimeter via `Ticks/cm = 724 - ((T * 5) >> 2)` using live ambient Celsius telemetry or the 25°C fallback.
* **Connection Watchdog (`RTL/uart_rx.sv`):** Monitors `104` clocks/bit at 12 MHz, validates incoming readings (`10°C–50°C`), and asserts `esp_connected_o` only while valid packets arrive within a `30,000,000`-cycle (2.5 s) window.
* **Direct BCD Echo Measurement (`RTL/rangefinder.sv`):** Steps through `S_TRIGGER`, `S_WAIT_ECHO`, `S_MEASURE`, and `S_COOLDOWN`, counting echo duration directly into saturated 2-digit BCD centimeters (`00–99 cm`).

### Wiring Table

| Signal | Direction | iCEBreaker Pin | ESP32-C3 / Sensor Pin | Description |
| :--- | :--- | :--- | :--- | :--- |
| **`uart_rx_i`** | Input | PMOD 1B1 (`Pin 43`) | `GPIO 4` (`IO4`) | 115,200-baud UART temperature telemetry |
| **`trig_o`** | Output | PMOD 1B2 (`Pin 38`) | RCWL-1601 `TRIG` | 10.5 µs ultrasonic trigger pulse |
| **`echo_i`** | Input | PMOD 1B3 (`Pin 34`) | RCWL-1601 `ECHO` | Ultrasonic return echo pulse |
| **`3V3` / `GND`** | Power | PMOD 1B `3V3`/`GND` | `3V3` / `GND` | Shared 3.3V rail and common ground reference |

### Controls & Status Indicators (PMOD 2)
* **Onboard `UBUTTON`:** Synchronous active-low global system reset.
* **Button 3 (Hold):** Switches the 7-segment display from measured distance (`cm`) to the active temperature (`°C`) currently feeding the speed-of-sound datapath.
* **LED 1 (Red):** **ON** when the ESP32 link is disconnected (`25°C` fallback active); **OFF** when receiving live UART packets.
* **LED 2 (Green):** Heartbeat indicator toggling once per second upon receipt of each valid ESP32 temperature byte.
* **LED 3 (Green):** Pulses during active ultrasonic `ECHO` pulse reception.

---

## Flashing & Synthesis Notes

### 1. Flash Pre-Compiled Bitstream (iCEBreaker v1.1a)
```bash
openFPGALoader -b ice40_generic RTL/icebrk.bin
```

### 2. Build & Flash ESP32-C3 Firmware (ESP-IDF v5.x)
```bash
cd ESP-IDF_firmware
idf.py build flash monitor
```

### 3. External Primitives & Synthesis Disclosure
To keep this repository focused strictly on original RTL and firmware, standard course-provided helper primitives and build scripts are intentionally omitted. Synthesizing `RTL/*.sv` from scratch using **Yosys**, **nextpnr-ice40**, and **IceStorm** requires supplying compatible implementations for:
* **`hex2ssd`:** Combinational 4-bit hexadecimal-to-7-segment decoder instantiated by `ssd_mux.sv`.
* **`dff` / `inv`:** Standard positive-edge-triggered D flip-flop and inverter primitives.
* **Board Constraints:** An iCEBreaker `.pcf` constraint file matching the PMOD 1B/2 pinout table above and the 12 MHz onboard oscillator.

---

## Acknowledgments
* **Toolchain & Primitive Architecture:** Built within a modular synchronous FPGA design flow inspired by the open-source iCEBreaker curriculum developed by **Professor Dustin Richmond** (UCSC Baskin School of Engineering).
