// Top level (structural): button conditioning + baud_gen + uart_tx_core
// Ports are unchanged, so the existing .xdc still applies.
//
//   confirm   : transmit button
//   READY_LED : ON while idle
//   LED0      : ON while a byte is being transmitted
//
//            +-----------+  tick   +---------------+
//  confirm ->| sync+edge |--start->|               |--> tx
//            +-----------+         | uart_tx_core  |
//  sw[7:0] ----------------data--->|               |
//                                  +-------+-------+
//            +-----------+  tick           | busy
//            | baud_gen  |-----------------+
//            |   en <----|-----------------+
//            +-----------+

module uart_transmitter #(
    parameter CLK_FREQ  = 100_000_000,   // board clock in Hz (100 MHz on Basys 3)
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       confirm,           // transmit button
    input  wire [7:0] sw,
    output wire       tx,
    output wire       READY_LED,
    output wire [0:0] LED0
);

    wire baud_tick;
    wire busy;

    // ---- button: synchronise + rising-edge detect -> one-clock pulse ----
    reg confirm_sync0, confirm_sync1, confirm_prev;
    wire confirm_pulse = confirm_sync1 & ~confirm_prev;

    always @(posedge clk) begin
        if (rst) begin
            confirm_sync0 <= 1'b0;
            confirm_sync1 <= 1'b0;
            confirm_prev  <= 1'b0;
        end else begin
            confirm_sync0 <= confirm;
            confirm_sync1 <= confirm_sync0;
            confirm_prev  <= confirm_sync1;
        end
    end

    // ---- baud rate generator: runs only while a frame is in progress ----
    baud_gen #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_baud_gen (
        .clk (clk),
        .rst (rst),
        .en  (busy),
        .tick(baud_tick)
    );

    // ---- transmitter core ----
    uart_tx_core u_tx_core (
        .clk  (clk),
        .rst  (rst),
        .start(confirm_pulse),
        .data (sw),
        .tick (baud_tick),
        .busy (busy),
        .tx   (tx)
    );

    // ---- status LEDs ----
    assign READY_LED = ~busy;
    assign LED0      = busy;

endmodule