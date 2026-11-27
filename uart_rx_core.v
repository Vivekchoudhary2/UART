// UART receiver core (8N1), LSB first, 16x oversampling.
// No timing logic inside: it advances on 'tick' (one pulse per 1/OVERSAMPLE
// of a bit period) from baud_gen. 'rx' must already be synchronised to clk.
//
// How it samples (tick numbers counted from the start-bit falling edge):
//   tick  8       : middle of the start bit  -> still low? real start, else glitch
//   tick 8+16*n   : middle of data bit n-1   -> sample
//   tick 8+16*9   : middle of the stop bit   -> must be high, else frame error
// Returning to IDLE at the MIDDLE of the stop bit means back-to-back frames
// and a slightly fast sender are both handled.
//
//   busy      : high from the start-bit edge until the middle of the stop bit
//               (drive baud_gen's 'en' with this)
//   data      : received byte, valid when 'valid' pulses
//   valid     : one-clock pulse, byte received with a good stop bit
//   frame_err : one-clock pulse, stop bit was low (byte is discarded)

module uart_rx_core #(
    parameter OVERSAMPLE = 16
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,          // synchronised serial input
    input  wire       tick,        // oversample tick from baud_gen
    output wire       busy,
    output reg  [7:0] data,
    output reg        valid,
    output reg        frame_err
);

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0]                     state;
    reg [$clog2(OVERSAMPLE)-1:0]  tick_cnt;
    reg [2:0]                     bit_idx;
    reg [7:0]                     shift;
    reg                           rx_prev;

    wire falling = rx_prev & ~rx;          // start-bit edge
    assign busy  = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            tick_cnt  <= 0;
            bit_idx   <= 3'd0;
            shift     <= 8'b0;
            data      <= 8'b0;
            valid     <= 1'b0;
            frame_err <= 1'b0;
            rx_prev   <= 1'b1;
        end else begin
            rx_prev   <= rx;
            valid     <= 1'b0;             // default: pulses last one clock
            frame_err <= 1'b0;

            case (state)

                IDLE: begin
                    if (falling) begin
                        tick_cnt <= 0;
                        state    <= START;
                    end
                end

                START: if (tick) begin
                    if (tick_cnt == OVERSAMPLE/2 - 1) begin   // mid start bit
                        tick_cnt <= 0;
                        if (!rx) begin
                            bit_idx <= 3'd0;
                            state   <= DATA;
                        end else
                            state <= IDLE;                    // glitch, not a start bit
                    end else
                        tick_cnt <= tick_cnt + 1;
                end

                DATA: if (tick) begin
                    if (tick_cnt == OVERSAMPLE - 1) begin     // mid data bit
                        tick_cnt <= 0;
                        shift    <= {rx, shift[7:1]};         // LSB arrives first
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        tick_cnt <= tick_cnt + 1;
                end

                STOP: if (tick) begin
                    if (tick_cnt == OVERSAMPLE - 1) begin     // mid stop bit
                        tick_cnt <= 0;
                        state    <= IDLE;
                        if (rx) begin
                            data  <= shift;
                            valid <= 1'b1;
                        end else
                            frame_err <= 1'b1;
                    end else
                        tick_cnt <= tick_cnt + 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule