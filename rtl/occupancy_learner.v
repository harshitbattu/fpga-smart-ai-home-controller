`timescale 1ns / 1ps
// ============================================================================
// occupancy_learner : on-chip online learning of the household routine
//
//   The day is split into 24 hourly slots. For every slot the learner keeps
//   an 8-bit score s[h] = exponential moving average (EMA) of "was the home
//   occupied in this hour?", updated once per day at the end of the hour:
//
//        s[h] <- s[h] - s[h]/4 + 63*a        (a = 1 if motion seen, else 0)
//
//   Learning rate alpha = 1/4, steady state s = 252*p where p is the observed
//   probability of occupancy in that hour. Only shifts and adds are needed.
//
//   Uses of the learned model (active after MIN_DAYS days of learning):
//     * ANOMALY    : motion in an hour that is normally empty  (s < LOW_TH)
//                    e.g. movement at 3 AM -> possible intruder / someone unwell
//     * INACTIVITY : no motion for a whole hour that is normally busy
//                    (s >= HIGH_TH) -> elderly / lone-occupant safety alert
//     * PREDICTION : predicted = s[now] or s[next hour] >= PRED_TH
//                    -> climate control pre-cools the room before arrival
//   Anomaly / inactivity alerts are suppressed while the alarm is armed.
// ============================================================================
module occupancy_learner #(
    parameter integer MIN_DAYS = 3,
    parameter [7:0]   LOW_TH   = 8'd40,
    parameter [7:0]   HIGH_TH  = 8'd160,
    parameter [7:0]   PRED_TH  = 8'd96
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         motion,
    input  wire [4:0]   cur_hh,
    input  wire         hour_tick,
    input  wire [4:0]   end_hh,
    input  wire         clear,
    input  wire         alerts_en,
    output wire [191:0] profile,
    output wire [7:0]   cur_score,
    output reg  [7:0]   days,
    output wire         trained,
    output wire         predicted,
    output reg          evt_anomaly,
    output reg          evt_inactive,
    output reg  [4:0]   evt_hh
);
    reg [7:0] score [0:23];
    reg       active;          // motion seen during the current hour
    reg       anomaly_done;    // at most one anomaly alert per hour

    wire [4:0] next_hh = (cur_hh == 5'd23) ? 5'd0 : cur_hh + 1'b1;
    wire [7:0] s_old   = score[end_hh];
    wire [7:0] s_new   = s_old - {2'b00, s_old[7:2]} + (active ? 8'd63 : 8'd0);

    assign cur_score = score[cur_hh];
    assign trained   = (days >= MIN_DAYS);
    assign predicted = trained && ((score[cur_hh] >= PRED_TH) || (score[next_hh] >= PRED_TH));

    genvar g;
    generate
        for (g = 0; g < 24; g = g + 1) begin : g_prof
            assign profile[8*g +: 8] = score[g];
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        if (rst || clear) begin
            for (i = 0; i < 24; i = i + 1) score[i] <= 8'd0;
            days <= 8'd0; active <= 1'b0; anomaly_done <= 1'b0;
            evt_anomaly <= 1'b0; evt_inactive <= 1'b0; evt_hh <= 5'd0;
        end else begin
            evt_anomaly  <= 1'b0;
            evt_inactive <= 1'b0;
            if (hour_tick) begin
                score[end_hh] <= s_new;
                if (trained && alerts_en && s_old >= HIGH_TH && !active) begin
                    evt_inactive <= 1'b1; evt_hh <= end_hh;
                end
                active       <= motion;
                anomaly_done <= 1'b0;
                if (end_hh == 5'd23 && days != 8'd255) days <= days + 1'b1;
            end else if (motion) begin
                active <= 1'b1;
                if (trained && alerts_en && !anomaly_done && score[cur_hh] < LOW_TH) begin
                    evt_anomaly <= 1'b1; evt_hh <= cur_hh; anomaly_done <= 1'b1;
                end
            end
        end
    end
endmodule
