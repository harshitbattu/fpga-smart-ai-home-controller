`timescale 1ns / 1ps
// ============================================================================
// timebase : system ticks and time-of-day clock
//   tick_1s   : 1 pulse per second (all delays / timeouts use this)
//   tick_e    : 1 pulse every 36 ms (= 1e-5 hour) for the energy meter
//   hh:mm     : time of day, set with the TIME command
//   fast = 1  : demo mode, one simulated minute every 1/60 s
//               (1 hour of home time = 1 s, 1 day = 24 s)
//   hour_tick : pulse at every hour boundary, end_hh = hour that just ended
// ============================================================================
module timebase #(
    parameter integer SEC_DIV = 100_000_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       fast,
    input  wire       set_time,
    input  wire [4:0] set_hh,
    input  wire [5:0] set_mm,
    output reg        tick_1s,
    output reg        tick_e,
    output reg  [4:0] hh,
    output reg  [5:0] mm,
    output reg        hour_tick,
    output reg  [4:0] end_hh
);
    localparam integer E_DIV = (SEC_DIV / 1000) * 36;
    localparam integer F_DIV = SEC_DIV / 60;
    localparam integer SW = $clog2(SEC_DIV);
    localparam integer EW = $clog2(E_DIV);
    localparam integer FW = $clog2(F_DIV);

    reg [SW-1:0] sc;
    reg [EW-1:0] ec;
    reg [FW-1:0] fc;
    reg [5:0]    ss;

    wire sec_end     = (sc == SEC_DIV - 1);
    wire minute_tick = fast ? (fc == F_DIV - 1) : (sec_end && ss == 6'd59);

    always @(posedge clk) begin
        if (rst) begin
            sc <= 0; ec <= 0; fc <= 0; ss <= 0;
            hh <= 5'd0; mm <= 6'd0; end_hh <= 5'd0;
            tick_1s <= 1'b0; tick_e <= 1'b0; hour_tick <= 1'b0;
        end else begin
            tick_1s   <= 1'b0;
            tick_e    <= 1'b0;
            hour_tick <= 1'b0;

            if (sec_end) begin sc <= 0; tick_1s <= 1'b1; ss <= (ss == 6'd59) ? 6'd0 : ss + 1'b1; end
            else sc <= sc + 1'b1;

            if (ec == E_DIV - 1) begin ec <= 0; tick_e <= 1'b1; end
            else ec <= ec + 1'b1;

            fc <= (fc == F_DIV - 1) ? 0 : fc + 1'b1;

            if (set_time) begin
                hh <= set_hh; mm <= set_mm; ss <= 6'd0;
            end else if (minute_tick) begin
                if (mm == 6'd59) begin
                    mm        <= 6'd0;
                    end_hh    <= hh;
                    hour_tick <= 1'b1;
                    hh        <= (hh == 5'd23) ? 5'd0 : hh + 1'b1;
                end else
                    mm <= mm + 1'b1;
            end
        end
    end
endmodule
