`timescale 1ns / 1ps
// ============================================================================
// sync_debounce : 2-flip-flop synchronizer + counter debouncer
//   * removes metastability for asynchronous inputs (switches, buttons, PIR)
//   * output changes only after the input is stable for CYCLES clocks
//   * rise / fall : single-cycle edge pulses of the debounced signal
// ============================================================================
module sync_debounce #(
    parameter integer CYCLES = 1_000_000          // 10 ms @ 100 MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg  dout,
    output wire rise,
    output wire fall
);
    localparam integer W = (CYCLES < 2) ? 1 : $clog2(CYCLES);

    reg         s0, s1, dprev;
    reg [W-1:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            s0 <= 1'b0; s1 <= 1'b0; dout <= 1'b0; dprev <= 1'b0; cnt <= {W{1'b0}};
        end else begin
            s0    <= din;
            s1    <= s0;
            dprev <= dout;
            if (s1 == dout)
                cnt <= {W{1'b0}};
            else if (cnt == CYCLES-1) begin
                dout <= s1;
                cnt  <= {W{1'b0}};
            end else
                cnt <= cnt + 1'b1;
        end
    end

    assign rise =  dout & ~dprev;
    assign fall = ~dout &  dprev;
endmodule
