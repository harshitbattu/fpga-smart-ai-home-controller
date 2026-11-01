`timescale 1ns / 1ps
// ============================================================================
// uart_tx : 8-N-1 UART transmitter
//   start = 1-cycle request (accepted only when busy = 0)
// ============================================================================
module uart_tx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output wire       busy
);
    localparam integer W = $clog2(CLKS_PER_BIT);

    reg [9:0]   sh;       // {stop, data[7:0], start}
    reg [3:0]   n;
    reg [W-1:0] cnt;
    reg         active;

    assign busy = active;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1; active <= 1'b0; n <= 0; cnt <= 0; sh <= 10'h3FF;
        end else if (!active) begin
            tx <= 1'b1;
            if (start) begin
                sh     <= {1'b1, data, 1'b0};
                active <= 1'b1;
                n      <= 4'd0;
                cnt    <= 0;
                tx     <= 1'b0;                 // start bit
            end
        end else begin
            if (cnt == CLKS_PER_BIT - 1) begin
                cnt <= 0;
                if (n == 4'd9) begin
                    active <= 1'b0;
                    tx     <= 1'b1;
                end else begin
                    n  <= n + 1'b1;
                    tx <= sh[n + 1'b1];
                end
            end else cnt <= cnt + 1'b1;
        end
    end
endmodule
