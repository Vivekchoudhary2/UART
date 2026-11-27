# UART Transmitter & Receiver (8N1) — Design Documentation

A full-duplex UART written in Verilog and implemented directly on a **Basys 3** (Artix-7) board. The design sends a byte chosen on the switches to a PC serial terminal and displays any byte typed in the terminal on the LEDs.

This document covers every module, every port and internal signal, the overall behavior, the timing numbers, and the engineering judgements behind the design.

---

## 1. Overview

| Direction | What the user does | What the design does |
|---|---|---|
| **Transmit** (FPGA → PC) | Sets a byte on `sw[7:0]` and presses the center button (`confirm`) | Sends the byte on `tx` as one 8N1 frame at 9600 baud |
| **Receive** (PC → FPGA) | Types a character in the terminal | Decodes the frame from `rx` and shows the byte in binary on `rx_led[7:0]` (for example `'A'` = `0x41` = `01000001`) |

Status LEDs show whether the transmitter is idle (`READY_LED`) or sending (`LED0`), and whether a frame with a bad stop bit has been received (`frame_err_led`).

## 2. Specification

| Parameter | Value |
|---|---|
| Target board | Digilent Basys 3 |
| System clock | 100 MHz (`CLK_FREQ` parameter) |
| Baud rate | 9600 (`BAUD_RATE` parameter) |
| Frame format | 8N1: 1 start bit, 8 data bits (LSB first), no parity, 1 stop bit |
| Idle line level | High |
| Transmitter bit timing | 1 tick per bit |
| Receiver bit timing | 16× oversampling (`OVERSAMPLE` parameter), samples at the middle of each bit |
| Reset | Synchronous, active high, on the up button (`btnU`) |
| Buffering | None (one byte at a time in each direction) |

## 3. Source files and hierarchy

| File | Module | Role |
|---|---|---|
| `uart_top.v` | `uart_top` | Board-level top. Instantiates the transmitter and receiver, holds the received byte and the error flag for the LEDs |
| `uart_transmitter.v` | `uart_transmitter` | Transmit wrapper: button conditioning, baud generator, transmitter core, status LEDs |
| `uart_tx_core.v` | `uart_tx_core` | Transmit state machine (8N1, LSB first) |
| `uart_receiver.v` | `uart_receiver` | Receive wrapper: `rx` synchronizer, 16× baud generator, receiver core |
| `uart_rx_core.v` | `uart_rx_core` | Receive state machine with oversampling |
| `baud_gen.v` | `baud_gen` | Gated tick generator, used by both the transmitter and the receiver |
| `uart_top.xdc` | — | Basys 3 pin and clock constraints |

```
                         uart_top.v
                              |
                  +-----------+-----------+
                  |                       |
          uart_transmitter.v        uart_receiver.v
                  |                       |
        +---------+---------+   +---------+---------+
        |                   |   |                   |
    baud_gen.v       uart_tx_core.v   baud_gen.v   uart_rx_core.v
   (1x, 9600)                        (16x, 153600)

uart_top.xdc : pin and clock constraints for uart_top
```

`baud_gen` is instantiated twice, once inside each wrapper, with different parameters.

## 4. Top-level interface and pin map

### 4.1 `uart_top` parameters

| Parameter | Default | Purpose |
|---|---|---|
| `CLK_FREQ` | `100_000_000` | Board clock frequency in Hz. Passed down to both baud generators |
| `BAUD_RATE` | `9600` | Serial bit rate. Passed down to both wrappers |

### 4.2 `uart_top` ports

| Signal | Dir | Width | Purpose | Basys 3 resource | Pin |
|---|---|---|---|---|---|
| `clk` | in | 1 | 100 MHz system clock | Oscillator | W5 |
| `rst` | in | 1 | Synchronous active-high reset for the whole design | `btnU` | T18 |
| `confirm` | in | 1 | Transmit button. A press starts sending the byte on `sw` | `btnC` | U18 |
| `sw` | in | 8 | Byte to transmit. `sw[0]` is the LSB | SW0 (LSB) to SW7 (MSB) | V17, V16, W16, W17, W15, V15, W14, W13 |
| `tx` | out | 1 | Serial output, FPGA to PC | USB-UART `RsTx` | A18 |
| `READY_LED` | out | 1 | On while the transmitter is idle and can accept a new byte | LD14 | P1 |
| `LED0` | out | 1 (`[0:0]`) | On while the transmitter is sending a frame | LD15 | L1 |
| `rx` | in | 1 | Serial input, PC to FPGA | USB-UART `RsRx` | B18 |
| `rx_led` | out (reg) | 8 | Last correctly received byte, `rx_led[0]` is the LSB | LD0 to LD7 | U16, E19, U19, V19, W18, U15, U14, V14 |
| `frame_err_led` | out (reg) | 1 | Latches on if any received frame had a low stop bit. Cleared by `rst` | LD13 | N3 |

Pin names `tx` and `rx` follow the FPGA's point of view, as in Digilent's master constraints file.

### 4.3 Constraints (`uart_top.xdc`)

| Constraint | Purpose |
|---|---|
| `create_clock -period 10.00 -waveform {0 5}` on `clk` | Defines the 100 MHz clock (10 ns period, 50 % duty) so timing analysis is meaningful |
| `IOSTANDARD LVCMOS33` on all ports | Basys 3 I/O banks run at 3.3 V |
| `CFGBVS VCCO` and `CONFIG_VOLTAGE 3.3` | Tell Vivado the configuration bank voltage, required for a valid bitstream on this board |

Port names in the XDC must match the top module exactly. `LED0` is declared as a 1-bit vector and is constrained as `LED0[0]`.

### 4.4 Internal signals in `uart_top`

| Signal | Type | Purpose |
|---|---|---|
| `rx_data[7:0]` | wire | Byte output of the receiver |
| `rx_valid` | wire | One-clock pulse from the receiver: `rx_data` holds a new, good byte |
| `rx_frame_err` | wire | One-clock pulse from the receiver: a frame ended with a low stop bit |

The `always @(posedge clk)` block in `uart_top` turns these short pulses into steady LED outputs:

- On `rst`, `rx_led` and `frame_err_led` are cleared.
- On `rx_valid`, `rx_led` takes `rx_data` and holds it until the next valid byte.
- On `rx_frame_err`, `frame_err_led` is set and stays set until `rst`.

## 5. Functional description

### 5.1 Transmit operation

1. The user sets a byte on `sw[7:0]` and presses `confirm`.
2. The press is synchronized to `clk` and converted into a single-clock `confirm_pulse` (about 3 clock cycles, ~30 ns, after the press).
3. If the core is idle, it latches `sw` into `data_reg`, drives `tx` low (start bit) and enters `START`. `busy` goes high.
4. `busy` enables the baud generator. Every `CLKS_PER_BIT` clocks it emits a `tick`, and each tick advances the core by one bit: start bit, then `data_reg[0]` to `data_reg[7]` (LSB first), then the stop bit.
5. At the end of the stop bit the core returns to idle. `busy` drops, the baud generator stops and resets, and `READY_LED` turns back on.

A press while `busy` is high is ignored (not queued).

### 5.2 Receive operation

1. `rx` passes through a 2-flip-flop synchronizer, because it is asynchronous to `clk`.
2. In `IDLE`, the core watches for a falling edge on the synchronized line (the start bit). The edge moves it to `START` and raises `busy`.
3. `busy` enables the baud generator at 16 times the baud rate. Its counter starts from zero at the start-bit edge, so all sampling is aligned to that frame.
4. The core counts oversample ticks and samples `rx` at the middle of each bit:
   - 8 ticks after the edge, it re-checks the start bit. If `rx` is high again, it was a glitch and the core returns to `IDLE`.
   - Every 16 ticks after that, it samples one data bit and shifts it in from the top, so the first bit (LSB) ends up at bit 0 after 8 shifts.
   - 16 ticks after the last data bit, it samples the stop bit.
5. If the stop bit is high, `data` is loaded and `valid` pulses for one clock. If it is low, `frame_err` pulses for one clock and the byte is discarded.
6. The core returns to `IDLE` at the *middle* of the stop bit, so a closely following start bit is not missed.

### 5.3 Frame format

Frame for `'A'` = `0x41` = `0100_0001`, sent LSB first:

| Bit period | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| Meaning | Start | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | Stop |
| `tx` level | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 |

The line idles high between frames. A frame is 10 bit periods long.

## 6. Module reference

### 6.1 `baud_gen`

Generates a one-clock `tick` pulse at the end of every bit period, but only while `en` is high.

**Parameters**

| Name | Default | Purpose |
|---|---|---|
| `CLK_FREQ` | `100_000_000` | Input clock frequency in Hz |
| `BAUD_RATE` | `9600` | Tick rate in Hz. The receiver passes `BAUD_RATE * OVERSAMPLE` here |

**Derived constant**

| Name | Value | Purpose |
|---|---|---|
| `CLKS_PER_BIT` | `(CLK_FREQ + BAUD_RATE/2) / BAUD_RATE` | Clocks per tick, rounded to the nearest integer. 10417 for 9600 baud, 651 for 153600 |

**Ports**

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst` | in | 1 | Synchronous reset, clears the counter |
| `en` | in | 1 | Enable. While low, the counter is held at 0 |
| `tick` | out | 1 | One-clock pulse when the counter reaches `CLKS_PER_BIT-1`. Low whenever `en` is low |

**Internal**

| Signal | Width | Purpose |
|---|---|---|
| `cnt` | `$clog2(CLKS_PER_BIT)` (14 bits for 9600, 10 bits for 153600) | Counts clocks within the current period. Resets on `rst`, on `!en`, and on `tick` |

**Behavior.** `tick = en & (cnt == CLKS_PER_BIT-1)` is combinational. Because the counter is held at 0 while `en` is low, the first period starts exactly when `en` rises. The first tick arrives `CLKS_PER_BIT` clocks later, and then every `CLKS_PER_BIT` clocks while `en` stays high.

### 6.2 `uart_tx_core`

Transmit state machine. It contains no timing logic of its own and advances one step per `tick`.

**Ports**

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst` | in | 1 | Synchronous reset. Returns to `IDLE` with `tx` high |
| `start` | in | 1 | One-clock pulse requesting a transmission. Accepted only in `IDLE` |
| `data` | in | 8 | Byte to send. Latched when `start` is accepted |
| `tick` | in | 1 | End-of-bit-period pulse from `baud_gen` |
| `busy` | out | 1 | High from the start bit until the end of the stop bit. Drives `baud_gen`'s `en` |
| `tx` | out (reg) | 1 | Serial output. Registered, so it is glitch-free |

**Internal**

| Signal | Width | Purpose |
|---|---|---|
| `state` | 2 | Current FSM state |
| `bit_idx` | 3 | Index of the data bit currently on the line |
| `data_reg` | 8 | Holding copy of `data`. Stays stable even if the switches change mid-frame |
| `IDLE`, `START`, `DATA`, `STOP` | localparams | State encodings 0 to 3 |

`busy = (state != IDLE)`.

**State machine**

| State | `tx` | Action | Exit |
|---|---|---|---|
| `IDLE` | 1 | Waits. On `start`: `data_reg <= data`, `tx <= 0` | `start` → `START` |
| `START` | 0 | Start bit is on the line | `tick`: `tx <= data_reg[0]`, `bit_idx <= 0` → `DATA` |
| `DATA` | `data_reg[bit_idx]` | On each `tick`, put the next bit on the line | `tick` with `bit_idx==7`: `tx <= 1` → `STOP`. Otherwise `bit_idx` increments and `tx <= data_reg[bit_idx+1]` |
| `STOP` | 1 | Stop bit is on the line | `tick` → `IDLE` |

All four encodings are used. The `default` branch returns to `IDLE` as a defensive recovery.

### 6.3 `uart_transmitter`

Wrapper that connects a button, the baud generator and the transmit core.

**Parameters**: `CLK_FREQ` and `BAUD_RATE`, passed to `baud_gen`.

**Ports**

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst` | in | 1 | Synchronous reset |
| `confirm` | in | 1 | Raw, asynchronous transmit button |
| `sw` | in | 8 | Byte to transmit, passed straight to the core |
| `tx` | out | 1 | Serial output from the core |
| `READY_LED` | out | 1 | `~busy`: transmitter idle |
| `LED0` | out | 1 (`[0:0]`) | `busy`: frame in progress |

**Internal**

| Signal | Type | Purpose |
|---|---|---|
| `confirm_sync0` | reg | First synchronizer flip-flop for the button |
| `confirm_sync1` | reg | Second synchronizer flip-flop. Output is safe to use in the `clk` domain |
| `confirm_prev` | reg | `confirm_sync1` delayed by one clock, for edge detection |
| `confirm_pulse` | wire | `confirm_sync1 & ~confirm_prev`: one clock wide on each rising edge of the button. Connected to the core's `start` |
| `baud_tick` | wire | Tick from `baud_gen` to the core |
| `busy` | wire | From the core. Drives `baud_gen`'s `en` and the LEDs |

**Instances**: `u_baud_gen` (`en = busy`) and `u_tx_core`.

### 6.4 `uart_rx_core`

Receive state machine with 16× oversampling. It contains no timing logic of its own and advances on oversample ticks. Its `rx` input must already be synchronized to `clk`.

**Parameter**

| Name | Default | Purpose |
|---|---|---|
| `OVERSAMPLE` | 16 | Ticks per bit period. The middle of a bit is at `OVERSAMPLE/2` ticks |

**Ports**

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst` | in | 1 | Synchronous reset |
| `rx` | in | 1 | Synchronized serial input |
| `tick` | in | 1 | Oversample tick from `baud_gen` |
| `busy` | out | 1 | High from the start-bit edge until the middle of the stop bit. Drives `baud_gen`'s `en` |
| `data` | out (reg) | 8 | Received byte. Updated only on a good frame and then held |
| `valid` | out (reg) | 1 | One-clock pulse: a byte was received with a good stop bit |
| `frame_err` | out (reg) | 1 | One-clock pulse: stop bit was low, byte discarded |

**Internal**

| Signal | Width | Purpose |
|---|---|---|
| `state` | 2 | Current FSM state |
| `tick_cnt` | `$clog2(OVERSAMPLE)` (4 bits) | Counts oversample ticks inside the current bit |
| `bit_idx` | 3 | Number of data bits sampled so far |
| `shift` | 8 | Shift register collecting the data bits |
| `rx_prev` | 1 | `rx` delayed by one clock, for edge detection |
| `falling` | wire | `rx_prev & ~rx`: start-bit falling edge |
| `IDLE`, `START`, `DATA`, `STOP` | localparams | State encodings 0 to 3 |

`busy = (state != IDLE)`. `valid` and `frame_err` default to 0 on every clock, which makes them single-clock pulses.

**State machine**

| State | Condition | Action |
|---|---|---|
| `IDLE` | `falling` | `tick_cnt <= 0`, go to `START` |
| `START` | `tick` and `tick_cnt == OVERSAMPLE/2 - 1` (8th tick, middle of start bit) | If `rx` is low: `bit_idx <= 0`, go to `DATA`. If high: glitch, go to `IDLE`. In both cases `tick_cnt <= 0` |
| `START` | `tick`, count not reached | `tick_cnt` increments |
| `DATA` | `tick` and `tick_cnt == OVERSAMPLE - 1` (middle of a data bit) | `shift <= {rx, shift[7:1]}`. If `bit_idx == 7` go to `STOP`, otherwise `bit_idx` increments. `tick_cnt <= 0` |
| `DATA` | `tick`, count not reached | `tick_cnt` increments |
| `STOP` | `tick` and `tick_cnt == OVERSAMPLE - 1` (middle of stop bit) | Go to `IDLE`. If `rx` is high: `data <= shift`, `valid <= 1`. If low: `frame_err <= 1` |
| `STOP` | `tick`, count not reached | `tick_cnt` increments |

Sampling instants, counted in ticks from the start-bit edge: tick 8 (middle of start bit), tick `8 + 16n` (middle of data bit `n-1`), tick 152 (middle of stop bit).

### 6.5 `uart_receiver`

Wrapper that connects the `rx` synchronizer, the 16× baud generator and the receive core. It has no board-specific logic and can be reused.

**Parameters**

| Name | Default | Purpose |
|---|---|---|
| `CLK_FREQ` | `100_000_000` | Board clock in Hz |
| `BAUD_RATE` | `9600` | Serial bit rate |
| `OVERSAMPLE` | 16 | Oversampling factor. `baud_gen` runs at `BAUD_RATE * OVERSAMPLE` |

**Ports**

| Signal | Dir | Width | Purpose |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst` | in | 1 | Synchronous reset |
| `rx` | in | 1 | Raw, asynchronous serial input |
| `data` | out | 8 | Received byte |
| `valid` | out | 1 | One-clock pulse: `data` holds a new byte |
| `frame_err` | out | 1 | One-clock pulse: stop bit was low |

**Internal**

| Signal | Type | Purpose |
|---|---|---|
| `rx_sync0` | reg, `ASYNC_REG`, initial 1 | First synchronizer flip-flop |
| `rx_sync1` | reg, `ASYNC_REG`, initial 1 | Second synchronizer flip-flop. Feeds the core |
| `os_tick` | wire | Oversample tick from `baud_gen` to the core |
| `busy` | wire | From the core. Drives `baud_gen`'s `en` |

**Instances**: `u_baud_gen` (`en = busy`, rate `BAUD_RATE * OVERSAMPLE`) and `u_rx_core`.

### 6.6 `uart_transmitter` and `uart_receiver` compared

| | Transmitter | Receiver |
|---|---|---|
| Tick rate | `BAUD_RATE` (9600) | `BAUD_RATE * 16` (153,600) |
| Divider | 10417 clocks | 651 clocks |
| Generator starts when | A byte is accepted (`busy` rises) | A start-bit edge is seen (`busy` rises) |
| Generator stops when | End of stop bit | Middle of stop bit |
| Data path | `data_reg` indexed by `bit_idx` | `shift` register |
| Input conditioning | 2-FF sync + edge detect on the button | 2-FF sync on `rx` |

## 7. Timing budget

At 100 MHz one clock is 10 ns.

| Quantity | Value |
|---|---|
| Transmitter divider | `(100,000,000 + 4,800) / 9600` = 10417 clocks (104.17 µs) per bit |
| Transmitter baud error | 100 MHz / 10417 = 9599.69 baud, about −0.003 % |
| Transmit frame length | 10 bits = 104,170 clocks ≈ 1.042 ms |
| Receiver divider | `(100,000,000 + 76,800) / 153,600` = 651 clocks (6.51 µs) per oversample tick |
| Receiver baud error | 100 MHz / (651 × 16) = 9600.61 baud, about +0.006 % |
| Receiver bit period | 16 × 651 = 10,416 clocks |
| Button to start bit | About 3 clocks (~30 ns) |
| Start edge to `valid` or `frame_err` | 9.5 bit periods (about 0.99 ms) plus a few clocks |
| Sampling point offset | A few clocks (synchronizer and edge detect) against a 10,416-clock bit: well under 0.1 % of a bit |

**Tolerance.** The receiver samples the last bit (stop bit) at 9.5 bit periods after the start edge. A baud mismatch that moves that sample by half a bit, about ±5 % in theory, would break reception. The design's own divider errors (below 0.01 %) use a negligible part of this margin, so the PC's baud accuracy dominates. Because the counter restarts at every start-bit edge, error does not accumulate across frames.

## 8. Engineering judgements

**1. Fixed 8N1 framing, LSB first.**
This is what standard terminals use by default and it needs no parity logic. Parity and variable data width were left out to keep the design small and easy to verify on hardware.

**2. Timing-free cores with separate wrappers.**
`uart_tx_core` and `uart_rx_core` only react to `tick`, and all clock division lives in `baud_gen`. This separates protocol logic from timing, lets one `baud_gen` serve both directions with different parameters, and makes each block easy to reason about and reuse.

**3. Baud generator gated by `busy`.**
`baud_gen` counts only while a frame is in progress and is held at 0 otherwise.
- Receiver: the tick train restarts at every start-bit edge, so the receiver is aligned to the sender's clock for every frame. This matters because the PC's clock is unrelated to the FPGA's.
- Transmitter: the start bit begins immediately on a button press instead of waiting for a free-running tick.
- Cost: two counters instead of one shared free-running counter.

**4. Rounded clock divider.**
`CLKS_PER_BIT = (CLK_FREQ + BAUD_RATE/2) / BAUD_RATE` rounds to the nearest integer instead of truncating, which minimizes baud error for any clock and baud combination. A `$clog2`-sized counter follows the parameters automatically.

**5. 16× oversampling and mid-bit sampling in the receiver.**
Sampling in the middle of each bit gives maximum margin against edge jitter and baud mismatch. 16× is the conventional factor: it places the start-bit edge within 1/16 of a bit. The transmitter needs only 1× because it generates the signal.

**6. Start-bit validation.**
At the middle of the start bit the receiver re-checks that `rx` is still low. A short glitch on an idle line returns it to `IDLE` instead of producing a false byte.

**7. Return to `IDLE` at the middle of the stop bit.**
Ending the frame half a bit early lets the receiver catch a start bit that arrives immediately after the stop bit (back-to-back frames) or from a sender running slightly fast. The tick generator is switched off and reset in the meantime.

**8. Stop-bit check and error reporting.**
A frame with a low stop bit is rejected: `data` is not updated and `frame_err` pulses. The top level latches the flag on an LED so a one-clock event is visible to the user, and `rst` clears it. Good bytes and bad frames are never mixed on the `rx_led` display.

**9. Edge-triggered start detection.**
The receiver looks for a falling edge, not a low level. If the line is held low (a break condition), the receiver produces one frame error and then waits for the line to go high again, instead of repeatedly decoding the same low level as new frames.

**10. Two-flip-flop synchronizers, marked `ASYNC_REG`, initialized to idle.**
`rx` and `confirm` are asynchronous to `clk`, so each goes through two flip-flops before use. On `rx`, the flops carry the `ASYNC_REG` attribute so Vivado keeps them adjacent and does not optimize them, and they start at 1 (the idle level) so the power-up state cannot look like a start bit. The synchronizer flops are intentionally not reset.

**11. Rising-edge detect on the button.**
Holding `confirm` down sends exactly one byte, because only the rising edge produces a `start` pulse.

**12. Latch the byte when the frame starts; ignore requests while busy.**
`data_reg` captures `sw` when `start` is accepted, so changing the switches during transmission cannot corrupt the byte on the wire. A `start` that arrives while `busy` is ignored, which prevents a second press from corrupting the frame in progress. `READY_LED` tells the user when it is safe to send the next byte.

**13. Holding register with an index in the transmitter, shift register in the receiver.**
The transmitter selects bits from `data_reg` with `bit_idx`, which keeps the stored byte intact for the whole frame and makes the current bit position easy to follow. The receiver naturally shifts bits in as they arrive, so it uses a shift register, with the first bit received ending up as the LSB.

**14. Registered outputs and pulse-style handshakes.**
`tx` is a register output, so it cannot glitch. `valid` and `frame_err` are one-clock pulses that default to 0 every cycle, which keeps the receiver interface simple. The top level decides how long to display them.

**15. Parameterization.**
`CLK_FREQ`, `BAUD_RATE` and `OVERSAMPLE` are parameters, so the design can be retargeted to another clock or baud rate without editing the logic. The receiver wrapper has no board-specific logic.

**16. Synchronous reset on a button.**
All state is cleared with one synchronous, active-high reset. It also returns `tx` to idle high and clears the error LED.

**17. Defensive FSM defaults.**
Every state machine has a `default` branch to `IDLE`, so an illegal state would recover on its own.

**18. On-board observability.**
The received byte is shown in binary on LD0 to LD7, the transmitter state on LD14 and LD15, and framing errors on LD13. This allowed the design to be verified on the board directly with a terminal, without extra instrumentation.

## 9. Known limitations and possible improvements

| Item | Detail |
|---|---|
| Button debouncing | `confirm` has synchronization and edge detection but no debounce. A press is ignored only while a frame is in progress (about 1.04 ms), so contact bounce lasting longer than that could trigger a second transmission |
| Reset synchronization | `rst` goes straight to synchronous reset logic. A reset-release synchronizer would make release strictly safe |
| `ASYNC_REG` on `confirm` | Only the `rx` synchronizer carries the attribute. Adding it to `confirm_sync0` and `confirm_sync1` would make the two consistent |
| Switch inputs | `sw` is not synchronized. This is acceptable for static switches latched on a button press |
| No transmit buffering | A press while busy is lost, not queued. A FIFO would remove this |
| No receive buffering | Only the latest byte is kept on `rx_led`. A new byte replaces the old one |
| Single-sample bit decision | Each bit is sampled once at the center. Majority voting over three samples would improve noise immunity |
| Combinational `tick` | `tick` is decoded combinationally from the counter. It meets 100 MHz comfortably, but registering it would help at higher clock rates |
| Divider range | `CLKS_PER_BIT` must be at least 2 (and `OVERSAMPLE` even) for the counters and mid-bit points to be valid |
| Header comment | `uart_transmitter.v` still describes itself as the top level. `uart_top` is now the top module |
| Fixed format | Only 8N1 is supported. Parity, other data widths and 2 stop bits would need extra states and parameters |
