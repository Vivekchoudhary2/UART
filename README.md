# UART Transmitter & Receiver in Verilog

A UART (Universal Asynchronous Receiver/Transmitter) implemented in Verilog and tested on an FPGA board. An 8-bit value is entered with on-board switches, latched with a confirm button, and shifted out serially at **9600 baud**. A matching receiver deserialises incoming data back into an 8-bit word.

## Features

- 8-bit data entry via switches, latched with a confirm (transmit) button
- UART transmitter built around a shift register, 9600 baud
- UART receiver, 9600 baud
- Structural design: baud rate generator, transmitter core and receiver are separate modules instantiated together in a top-level wrapper (`uart_top`)
- Ready indicator LED to show when the transmitter can accept new data
- Verified on hardware

## How it works

```
                 ┌──────────────────────────── uart_top ────────────────────────────┐
                 │                                                                  │
 sw[7:0] ──────► │  input latch ──► internal_reg ──► TX core ──────────────────────►│──► tx
 confirm ──────► │  (confirm = transmit)            (shift register)                │
                 │                                       ▲                          │
                 │                           baud rate generator                    │
                 │                                       ▼                          │
 rx ───────────► │                                  RX core ──► received data       │
                 │                                                                  │
                 └──────────────────────────────────────────────────────────────────┘
                   READY_LED / LED0 show transmitter status
```

### Transmit path

1. The user sets 8 bits on the switches (`sw`).
2. Pressing **confirm** latches the switch value into `internal_reg` and starts a transmission.
3. The transmitter shifts the bits out on `tx`, one bit per baud tick, framed as a standard UART frame (start bit, 8 data bits, stop bit).
4. When the frame finishes, the transmitter returns to idle and `READY_LED` indicates it can accept a new byte.

### Receive path

1. The receiver watches `rx` for a falling edge (start bit).
2. It samples each data bit at the middle of its bit period.
3. After the stop bit, the 8-bit word is made available as received data.

### Baud rate generation

The baud rate generator divides the board clock down to one tick per bit period:

```
CLKS_PER_BIT = f_clk / baud_rate
```

For example, with a 100 MHz clock at 9600 baud: `100_000_000 / 9600 ≈ 10417` clock cycles per bit.

## Modules

| Module | Description |
|---|---|
| `uart_top` | Top level. Instantiates the baud generator, transmitter and receiver and connects them to the board I/O. |
| `baud_rate_generator` | Produces the baud tick from the system clock. |
| `uart_tx` | Transmitter core. Loads `internal_reg` and shifts it out serially. |
| `uart_rx` | Receiver core. Detects the start bit, samples the data bits and outputs the received byte. |

> Adjust the module names above to match your source files.

## Ports

| Signal | Direction | Description |
|---|---|---|
| `clk` | in | Board system clock |
| `sw[7:0]` | in | 8-bit data input switches |
| `confirm` | in | Button that latches the data and starts transmission |
| `rx` | in | Serial receive line |
| `tx` | out | Serial transmit line |
| `READY_LED` | out | Indicates the transmitter is ready for new data |
| `LED0` | out | Status indicator |

## UART settings

| Parameter | Value |
|---|---|
| Baud rate | 9600 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |

## Getting started

### Requirements

- An FPGA development board with switches, a push button, LEDs and a UART/USB-serial connection
- A synthesis toolchain for your board (e.g. Xilinx Vivado)
- A serial terminal on the PC (e.g. PuTTY, Tera Term or `screen`)

### Build and program

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/<your-repo>.git
   ```
2. Create a new project in your toolchain and add all `.v` files from `src/`.
3. Add the constraints file from `constraints/` and set `uart_top` as the top module.
4. Run synthesis, implementation and generate the bitstream.
5. Program the board.

### Try it out

1. Open a serial terminal at **9600 baud, 8N1**, no flow control.
2. Set a byte on the switches.
3. Press the confirm button. The byte appears in the terminal as its ASCII character.
4. Send a character from the terminal to test the receiver.

## Repository structure

```
.
├── src/
│   ├── uart_top.v
│   ├── baud_rate_generator.v
│   ├── uart_tx.v
│   └── uart_rx.v
├── sim/
│   └── tb_uart.v
├── constraints/
│   └── <board>.xdc
└── README.md
```

> Update the tree to match your repository.

## Testing

- **Simulation:** a testbench drives a byte into the transmitter and checks the serial output frame. It can also loop `tx` back into `rx` and compare the received byte with the one sent.
- **Hardware:** the transmitter and receiver (combined in `uart_top`) were tested on the board and work as intended.

## Possible improvements

- Switch debouncing for the confirm button
- Configurable baud rate and data width through parameters
- Parity bit support
- FIFO buffering for transmit and receive
- Framing and overrun error flags on the receiver

## License

Add a license of your choice (e.g. MIT) and include a `LICENSE` file.
