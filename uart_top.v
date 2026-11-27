// Basys 3 board-level top: UART transmitter + UART receiver
//
//  TX side : set sw[7:0], press confirm -> byte is sent on 'tx' (to the PC)
//  RX side : a byte typed in the PC terminal arrives on 'rx' and its value
//            is shown on rx_led[7:0] (e.g. 'A' = 0x41 = 01000001)
//
//  READY_LED     : ON while the transmitter is idle
//  LED0          : ON while the transmitter is sending
//  frame_err_led : latches ON if a byte arrived with a bad stop bit
//                  (cleared by rst)

module uart_top #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst,
    // transmit side
    input  wire       confirm,
    input  wire [7:0] sw,
    output wire       tx,
    output wire       READY_LED,
    output wire [0:0] LED0,
    // receive side
    input  wire       rx,
    output reg  [7:0] rx_led,
    output reg        frame_err_led
);

    // ---------------- transmitter ----------------
    uart_transmitter #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk      (clk),
        .rst      (rst),
        .confirm  (confirm),
        .sw       (sw),
        .tx       (tx),
        .READY_LED(READY_LED),
        .LED0     (LED0)
    );

    // ---------------- receiver ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_frame_err;

    uart_receiver #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk      (clk),
        .rst      (rst),
        .rx       (rx),
        .data     (rx_data),
        .valid    (rx_valid),
        .frame_err(rx_frame_err)
    );

    // hold the last received byte / error flag so the LEDs stay visible
    always @(posedge clk) begin
        if (rst) begin
            rx_led        <= 8'b0;
            frame_err_led <= 1'b0;
        end else begin
            if (rx_valid)     rx_led        <= rx_data;
            if (rx_frame_err) frame_err_led <= 1'b1;
        end
    end

endmodule