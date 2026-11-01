`timescale 1ns / 1ps
// ============================================================================
// climate_ctrl : fan duty-cycle decision
//   priority: emergency (100 %) > manual > sensor fault (50 % fail-safe)
//             > automatic
//   automatic:
//     * hysteresis: fan ON at T >= TH + 0.5 C, OFF at T < TH - 0.5 C
//     * proportional speed: duty = 30 % + 70 % * (T - TH) / 4 C  (max 100 %)
//     * ECO: run only if the room is occupied OR the learner predicts
//       occupancy (pre-cooling); empty and not expected -> fan off
//   temp : 1 LSB = 1/16 degC
// ============================================================================
module climate_ctrl (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [12:0] temp,
    input  wire               temp_ok,
    input  wire               fault,
    input  wire [5:0]         th,
    input  wire               manual,
    input  wire [6:0]         manual_duty,
    input  wire               occupied,
    input  wire               predicted,
    input  wire               eco,
    input  wire               emergency,
    output reg  [6:0]         duty,
    output reg                hot
);
    wire signed [13:0] t    = {temp[12], temp};
    wire signed [13:0] th16 = $signed({4'b0000, th, 4'b0000});
    wire signed [13:0] diff = t - th16;

    // 30 + (diff*70)/64 for 0 <= diff < 64, clamped
    wire [12:0] mul  = diff[6:0] * 7'd70;
    wire [6:0]  prop = (diff <= 0)  ? 7'd30  :
                       (diff >= 64) ? 7'd100 :
                                      7'd30 + mul[12:6];

    always @(posedge clk) begin
        if (rst) begin
            duty <= 7'd0; hot <= 1'b0;
        end else begin
            if (!temp_ok)                      hot <= 1'b0;
            else if (!hot && (t >= th16 + 8))  hot <= 1'b1;
            else if ( hot && (t <  th16 - 8))  hot <= 1'b0;

            if (emergency)      duty <= 7'd100;
            else if (manual)    duty <= manual_duty;
            else if (fault)     duty <= 7'd50;
            else if (!temp_ok)  duty <= 7'd0;
            else if (hot && (!eco || occupied || predicted)) duty <= prop;
            else                duty <= 7'd0;
        end
    end
endmodule
