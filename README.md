# UART Transmitter & Receiver in Verilog

A UART (Universal Asynchronous Receiver/Transmitter) implemented in Verilog and run directly on an FPGA board. An 8-bit value is entered with on-board switches, latched with a confirm button, and shifted out serially at **9600 baud**. A matching receiver deserialises incoming data back into an 8-bit word.

## Features

- 8-bit data entry via switches, latched with a confirm (transmit) button
- UART transmitter built around a shift register, 9600 baud
- UART receiver, 9600 baud
- Structural design: baud rate generator, transmitter core and receiver are separate modules instantiated together in a top-level wrapper (`uart_top`)
- Ready indicator LED to show when the transmitter can accept new data
- Implemented and tested directly on the FPGA board

## How it works

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
| `baud_gen` | Produces the baud tick from the system clock. |
| `uart_transmitter` | Transmitter core. Loads `internal_reg` and shifts it out serially. |
| `uart_receiver` | Receiver core. Detects the start bit, samples the data bits and outputs the received byte. |

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

## Testing

The design was implemented and tested directly on the FPGA board:

- **Transmitter:** each byte set on the switches and confirmed with the button was received correctly in a serial terminal at 9600 baud.
- **Receiver:** characters sent from the terminal were received and decoded correctly on the board.

## Possible improvements
- Configurable baud rate and data width through parameters
- FIFO buffering for transmit and receive

