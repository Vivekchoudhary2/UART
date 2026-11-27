// Receiver (structural): rx synchroniser + baud_gen (16x) + uart_rx_core
// Reusable block, no board-specific logic.
//
//            +--------+        +-----------+  tick   +--------------+
//  rx ------>| 2-FF   |--rx--->|           |<--------| baud_gen     |
//            | sync   |        |uart_rx_   |  busy ->|  (en = busy) |
//            +--------+        |   core    |         +--------------+
//                              +-----------+
//                               | data[7:0], valid, frame_err

module uart_receiver #(
    parameter CLK_FREQ   = 100_000_000,  // board clock in Hz (100 MHz on Basys 3)
    parameter BAUD_RATE  = 9600,
    parameter OVERSAMPLE = 16
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,                // raw, asynchronous serial input
    output wire [7:0] data,
    output wire       valid,             // 1-clock pulse: 'data' holds a new byte
    output wire       frame_err          // 1-clock pulse: stop bit was low
);

    // ---- 2-FF synchroniser for the asynchronous rx line (idle level = 1) ----
    (* ASYNC_REG = "TRUE" *) reg rx_sync0 = 1'b1;
    (* ASYNC_REG = "TRUE" *) reg rx_sync1 = 1'b1;

    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end

    wire os_tick;
    wire busy;

    // ---- oversample tick: baud_gen run at BAUD_RATE * OVERSAMPLE, only while
    //      a frame is being received, so it re-aligns to every start-bit edge ----
    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE * OVERSAMPLE)
    ) u_baud_gen (
        .clk (clk),
        .rst (rst),
        .en  (busy),
        .tick(os_tick)
    );

    // ---- receiver core ----
    uart_rx_core #(
        .OVERSAMPLE(OVERSAMPLE)
    ) u_rx_core (
        .clk      (clk),
        .rst      (rst),
        .rx       (rx_sync1),
        .tick     (os_tick),
        .busy     (busy),
        .data     (data),
        .valid    (valid),
        .frame_err(frame_err)
    );

endmodule