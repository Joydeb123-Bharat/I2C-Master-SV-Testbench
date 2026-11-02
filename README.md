# 🚀 Advanced I2C Master Controller & SystemVerilog Layered Testbench

## 📌 Project Overview
This repository contains a production-grade, fully synthesizable **I2C Master Controller** written in Verilog, accompanied by a robust, from-scratch **Object-Oriented SystemVerilog Layered Testbench**. 

This project was specifically designed, simulated, and verified using **AMD Xilinx Vivado (XSim)**. 

**⚠️ Note on Verification Methodology:** This verification environment explicitly bypasses Vivado’s auto-generated GUI testbenches and standard IP blocks. Instead, it utilizes a 100% custom-coded, industry-standard SystemVerilog layered architecture (TLM) to demonstrate deep protocol knowledge, constrained randomization, and automated self-checking capabilities.

---
<img width="3400" height="3180" alt="i2c_master_block_diagram" src="https://github.com/user-attachments/assets/bb7b1cf1-8a41-4f53-a83b-b331c8dc102b" />

## 🛠️ RTL Architecture: I2C Master FSM
The Device Under Test (DUT) is a robust Inter-Integrated Circuit (I2C) Master Controller capable of initiating and sustaining complex read/write transactions.

### Key Hardware Features
* **Clock Generation:** Generates a standard 100kHz SCL from a 50MHz system clock via an internal configurable clock divider.
* **Open-Drain Simulation:** Accurately models physical I2C open-drain behavior (`1'bz` for HIGH, `1'b0` for LOW) on bidirectional `SDA` and `SCL` pads.
* **Dynamic Multi-Byte Support:** Utilizes a custom 9-bit `wdata` bus (8-bit payload + 1-bit `more_byte` flag) to seamlessly handle continuous multi-byte bursts without dropping the bus or issuing premature `STOP` conditions.
* **Error Handling & Watchdogs:** Built-in hardware watchdog timers to detect bus lockups (Clock Stretching timeouts), Arbitration Loss, and `NACK` errors.
* **Glitch-Free Shifting:** Data is securely shifted precisely on the SCL `FALL` phase, guaranteeing SDA is completely stable during the SCL `HIGH` phase per I2C protocol standards.

---

## 🧬 SystemVerilog Layered Testbench (Verification Environment)
The testbench is built entirely from scratch using Object-Oriented Programming (OOP) principles, abstracting physical pin wiggles into high-level Transaction-Level Modeling (TLM).

### Component Breakdown
1. **SystemVerilog Interface (`i2c_if`):** Bundles the physical pins, manages bidirectional logic, and provides organized `modport` access to restrict directionality.
2. **Transaction Class (`i2c_transaction`):** Defines the data object. Utilizes `rand` variables and `constraint` blocks to generate strictly valid I2C traffic (e.g., ensuring `more_byte` is handled mathematically correctly during single-byte testing).
3. **Generator:** Creates hundreds of randomized transaction objects and safely routes them to the Driver and Scoreboard via Inter-Process Communication (IPC) `mailbox` channels.
4. **Driver:** Fetches TLM objects and translates them into picosecond-accurate physical bit-banging on the Vivado virtual interface, utilizing strict busy-wait synchronization.
5. **Monitor:** Passively oversamples the interface, reconstructs the physical waveforms back into software objects, and routes the actual outcomes to the Scoreboard.
6. **Scoreboard:** The automated judge. Compares the Expected data (from the Generator) against the Actual data (from the Monitor). It throws fatal errors on mismatches or hardware timeouts, allowing for unattended overnight regressions.
7. **Synchronous BFM Slave (`mock_slave`):** A highly advanced, custom-built Bus Functional Model. 
   * *Architecture:* Instead of using asynchronous edge-triggers (`always @(negedge scl)`), this slave uses the 50MHz system clock to continuously oversample the I2C bus. 
   * *Benefit:* This makes the slave completely immune to simulator delta-cycle race conditions, guaranteeing flawless ACK/NACK generation and data transmission.

---

## 🐛 Bug Hunt: What this Testbench Caught
This rigorous verification environment was not just theoretical; it successfully identified and allowed the patching of several complex RTL bugs during development:
1. **The Delta-Cycle Race Condition:** The initial asynchronous slave caused simultaneous read/write collisions on the `SDA` line at exactly `time = 0ns` of the falling edge, resulting in even-addresses passing and odd-addresses failing. *Fixed via the 50MHz Synchronous Oversampled BFM.*
2. **The "Instantaneous" START Flaw:** The RTL FSM originally held the `START` condition for only 20ns before moving to the address phase, violating the 0.6µs I2C hold-time requirement and failing to latch CPU inputs. *Fixed by strictly locking state transitions to the internal `scl_phase` generator.*
3. **The Premature Data Shift:** The Master originally shifted write data during the `LOW` phase rather than the `FALL` phase, corrupting the payload before the slave could read it. *Fixed by aligning the shift register specifically to the end of the bit cycle.*

---

## 💻 Simulation & Execution (Vivado)

### Requirements
* AMD Xilinx Vivado (Tested on 2025.x / 2022.x +)
* OS: Windows / Linux

### How to Run the Regression
1. Clone this repository to a **local, non-cloud-synced directory** (Avoid OneDrive/Dropbox as Vivado XSim generates temporary files that cause cloud-sync file lock crashes).
2. Open Vivado and create a new project.
3. Add `i2c_master.v` to your Design Sources.
4. Add `tb_top.sv` to your Simulation Sources.
5. Set `tb_top` as the Top Module.
6. Click **Run Simulation -> Run Behavioral Simulation**.
7. Observe the Tcl Console for the automated Scoreboard `[PASS]` output and view the generated Waveforms.

---
*Designed and verified from the ground up as a demonstration of production-grade digital logic verification.*
