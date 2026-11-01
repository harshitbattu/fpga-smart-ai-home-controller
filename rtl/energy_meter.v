`timescale 1ns / 1ps
// ============================================================================
// energy_meter : per-appliance energy estimate
//   tick_e every 36 ms = 1e-5 h. Per tick the fan adds FAN_W*duty and the
//   light adds LIGHT_W*100, i.e. 1 count = 1e-7 Wh (0.1 uWh).
//   Energy [Wh] = acc / 10^7  (formatted by telemetry_tx).
//   FAN_W / LIGHT_W = rated power of the connected loads (W).
// ============================================================================
module energy_meter #(
    parameter integer FAN_W   = 50,
    parameter integer LIGHT_W = 9
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_e,
    input  wire [6:0]  fan_duty,
    input  wire        light_on,
    output reg  [39:0] fan_acc,
    output reg  [39:0] light_acc
);
    always @(posedge clk) begin
        if (rst) begin
            fan_acc <= 40'd0; light_acc <= 40'd0;
        end else if (tick_e) begin
            fan_acc <= fan_acc + FAN_W * fan_duty;
            if (light_on) light_acc <= light_acc + LIGHT_W * 100;
        end
    end
endmodule
