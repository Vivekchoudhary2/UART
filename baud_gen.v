// Baud rate generator
// While 'en' is high, 'tick' pulses for one clock at the END of every bit
// period (every CLKS_PER_BIT clocks). While 'en' is low the counter is held
// at 0, so the first bit period starts exactly when 'en' rises.

module baud_gen #(
    parameter CLK_FREQ  = 100_000_000,   // board clock in Hz
    parameter BAUD_RATE = 9600
)(
    input  wire clk,
    input  wire rst,
    input  wire en,
    output wire tick
);

    // Rounded divider: (100_000_000 + 4800) / 9600 = 10417
    localparam integer CLKS_PER_BIT = (CLK_FREQ + BAUD_RATE/2) / BAUD_RATE;

    reg [$clog2(CLKS_PER_BIT)-1:0] cnt;

    assign tick = en & (cnt == CLKS_PER_BIT-1);

    always @(posedge clk) begin
        if (rst || !en || tick)
            cnt <= 0;
        else
            cnt <= cnt + 1;
    end

endmodule