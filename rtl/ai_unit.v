`timescale 1ns / 1ps
// ============================================================================
// ai_unit : neural-network occupancy detection service
//   * one-shot  : "AI t rh lux co2"  -> classify the given reading, reply
//                 "AI OCC=x P=yyy%"  (used for hardware-in-the-loop testing
//                 with recorded real data streamed from a PC)
//   * live mode : "ENV rh lux co2"   -> humidity, light and CO2 values from an
//                 external sensor gateway; once per second the network
//                 classifies (live ADT7420 temperature + ENV values) and the
//                 result ai_occ is fused into the room-occupancy decision
// ============================================================================
module ai_unit (
    input  wire               clk,
    input  wire               rst,
    input  wire               tick_1s,
    input  wire               cmd_valid,
    input  wire [4:0]         cmd,
    input  wire [13:0]        arg0,
    input  wire [13:0]        arg1,
    input  wire [13:0]        arg2,
    input  wire [13:0]        arg3,
    input  wire signed [12:0] temp_raw,     // 1/16 degC
    input  wire               temp_ok,
    output reg                live_en,
    output reg                ai_occ,
    output reg  [6:0]         ai_prob,
    output reg                ev_ai,        // one-shot result ready (pulse)
    output reg                ev_occ,
    output reg  [6:0]         ev_prob
);
    `include "home_defs.vh"

    reg  [13:0] env_rh, env_lux, env_co2;
    reg  [13:0] q_t, q_rh, q_lux, q_co2;     // queued one-shot request
    reg         q_req, cur_oneshot;
    reg         start;
    reg  signed [15:0] in_t, in_rh, in_lux, in_co2;
    wire        busy, done, occ;
    wire [6:0]  prob;
    wire signed [23:0] z;

    // live temperature in 0.1 degC: (T/16)*10
    wire signed [16:0] t10_full = (temp_raw * 17'sd10) >>> 4;

    nn_engine u_nn (.clk(clk), .rst(rst), .start(start), .t_x10(in_t), .rh_x10(in_rh),
                    .lux(in_lux), .co2(in_co2), .busy(busy), .done(done),
                    .occ(occ), .prob(prob), .z(z));

    always @(posedge clk) begin
        if (rst) begin
            env_rh <= 14'd0; env_lux <= 14'd0; env_co2 <= 14'd0; live_en <= 1'b0;
            q_t <= 0; q_rh <= 0; q_lux <= 0; q_co2 <= 0; q_req <= 1'b0; cur_oneshot <= 1'b0;
            start <= 1'b0; in_t <= 0; in_rh <= 0; in_lux <= 0; in_co2 <= 0;
            ai_occ <= 1'b0; ai_prob <= 7'd0; ev_ai <= 1'b0; ev_occ <= 1'b0; ev_prob <= 7'd0;
        end else begin
            start <= 1'b0;
            ev_ai <= 1'b0;

            if (cmd_valid && cmd == CMD_ENV) begin
                env_rh <= arg0; env_lux <= arg1; env_co2 <= arg2; live_en <= 1'b1;
            end
            if (cmd_valid && cmd == CMD_AI) begin
                q_t <= arg0; q_rh <= arg1; q_lux <= arg2; q_co2 <= arg3; q_req <= 1'b1;
            end

            // launch: one-shot requests first, then the 1 s live inference
            if (!busy && !start) begin
                if (q_req) begin
                    in_t <= {2'b00, q_t}; in_rh <= {2'b00, q_rh}; in_lux <= {2'b00, q_lux}; in_co2 <= {2'b00, q_co2};
                    q_req <= 1'b0; cur_oneshot <= 1'b1; start <= 1'b1;
                end else if (tick_1s && live_en && temp_ok) begin
                    in_t <= t10_full[15:0]; in_rh <= {2'b00, env_rh}; in_lux <= {2'b00, env_lux}; in_co2 <= {2'b00, env_co2};
                    cur_oneshot <= 1'b0; start <= 1'b1;
                end
            end

            if (done) begin
                if (cur_oneshot) begin ev_ai <= 1'b1; ev_occ <= occ; ev_prob <= prob; end
                else             begin ai_occ <= occ; ai_prob <= prob; end
            end
        end
    end
endmodule
