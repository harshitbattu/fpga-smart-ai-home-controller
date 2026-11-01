`timescale 1ns / 1ps
// ============================================================================
// uart_rx : 8-N-1 UART receiver
//   * 2-FF synchronizer on the RX line (line idles HIGH)
//   * start bit detected on falling edge, re-checked at mid-bit (glitch reject)
//   * each data bit sampled at the centre of its bit period
//   * frame_err pulses when the stop bit is not HIGH
//   CLKS_PER_BIT = f_clk / baud  (100 MHz / 115200 = 868)
// ============================================================================
module uart_rx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        frame_err
);
    localparam integer W = $clog2(CLKS_PER_BIT);
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg         rx_s0, rx_s1;
    reg [1:0]   st;
    reg [W-1:0] cnt;
    reg [2:0]   bitn;
    reg [7:0]   sh;

    always @(posedge clk) begin
        if (rst) begin
            rx_s0 <= 1'b1; rx_s1 <= 1'b1;
            st <= S_IDLE; cnt <= 0; bitn <= 0; sh <= 8'd0;
            data <= 8'd0; valid <= 1'b0; frame_err <= 1'b0;
        end else begin
            rx_s0     <= rx;
            rx_s1     <= rx_s0;
            valid     <= 1'b0;
            frame_err <= 1'b0;
            case (st)
                S_IDLE:
                    if (!rx_s1) begin st <= S_START; cnt <= 0; end
                S_START:
                    if (cnt == CLKS_PER_BIT/2 - 1) begin
                        cnt <= 0;
                        if (!rx_s1) begin st <= S_DATA; bitn <= 3'd0; end
                        else          st <= S_IDLE;          // glitch
                    end else cnt <= cnt + 1'b1;
                S_DATA:
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 0;
                        sh  <= {rx_s1, sh[7:1]};              // LSB first
                        if (bitn == 3'd7) st <= S_STOP;
                        else              bitn <= bitn + 1'b1;
                    end else cnt <= cnt + 1'b1;
                S_STOP:
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= 0;
                        st  <= S_IDLE;
                        if (rx_s1) begin data <= sh; valid <= 1'b1; end
                        else            frame_err <= 1'b1;
                    end else cnt <= cnt + 1'b1;
            endcase
        end
    end
endmodule
