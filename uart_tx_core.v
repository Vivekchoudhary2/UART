// UART transmitter core (8N1), LSB first.
// No timing logic inside: it advances one step per 'tick' from baud_gen.
//
//   start : one-clock pulse, accepted only while idle (!busy)
//   data  : byte to send, latched when start is accepted
//   tick  : end-of-bit-period pulse from baud_gen
//   busy  : high from the start bit until the end of the stop bit
//           (drive baud_gen's 'en' with this)

module uart_tx_core (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    input  wire       tick,
    output wire       busy,
    output reg        tx
);

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [7:0] data_reg;

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            tx       <= 1'b1;
            bit_idx  <= 3'd0;
            data_reg <= 8'b0;
        end else begin
            case (state)

                IDLE: begin
                    tx <= 1'b1;
                    if (start) begin
                        data_reg <= data;        // latch the byte
                        tx       <= 1'b0;        // start bit
                        state    <= START;
                    end
                end

                START: if (tick) begin
                    tx      <= data_reg[0];      // first data bit (LSB)
                    bit_idx <= 3'd0;
                    state   <= DATA;
                end

                DATA: if (tick) begin
                    if (bit_idx == 3'd7) begin
                        tx    <= 1'b1;           // stop bit
                        state <= STOP;
                    end else begin
                        bit_idx <= bit_idx + 3'd1;
                        tx      <= data_reg[bit_idx + 3'd1];
                    end
                end

                STOP: if (tick) begin
                    state <= IDLE;               // tx is already high
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule