`timescale 1ns / 1ps
// ============================================================================
// control_unit : user settings, operating mode, occupancy and lighting
//   * MODE AUTO / MANUAL ; FAN n and LIGHT x switch to MANUAL automatically
//   * TH (threshold, also BTNU / BTND), OCC (occupancy timeout), ECO, FAST, TIME
//   * occupancy: occupied while motion is present, for OCC seconds after
//     the last motion, or while the neural network detects occupancy
//   * light: ALARM -> ON (panic lighting); MANUAL -> user value;
//            AUTO  -> dark AND occupied
// ============================================================================
module control_unit #(
    parameter [5:0]  TH_DEFAULT  = 6'd28,
    parameter [11:0] OCC_DEFAULT = 12'd30
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_1s,
    input  wire        cmd_valid,
    input  wire [4:0]  cmd,
    input  wire [13:0] arg0,
    input  wire [13:0] arg1,
    input  wire        btn_up,
    input  wire        btn_down,
    input  wire        motion,
    input  wire        dark,
    input  wire        alarm_active,
    input  wire        ai_occ,          // neural-network occupancy (live mode)
    output reg         manual,
    output reg  [6:0]  manual_duty,
    output reg         manual_light,
    output reg  [5:0]  th,
    output reg  [11:0] occ_timeout,
    output reg         eco,
    output reg         fast,
    output reg         set_time,
    output reg  [4:0]  set_hh,
    output reg  [5:0]  set_mm,
    output wire        occupied,
    output wire        light_out
);
    `include "home_defs.vh"

    reg [11:0] occ_left;

    assign occupied  = motion || (occ_left != 12'd0) || ai_occ;
    assign light_out = alarm_active ? 1'b1 :
                       manual       ? manual_light :
                                      (dark && occupied);

    always @(posedge clk) begin
        if (rst) begin
            manual <= 1'b0; manual_duty <= 7'd0; manual_light <= 1'b0;
            th <= TH_DEFAULT; occ_timeout <= OCC_DEFAULT; eco <= 1'b1; fast <= 1'b0;
            set_time <= 1'b0; set_hh <= 5'd0; set_mm <= 6'd0; occ_left <= 12'd0;
        end else begin
            set_time <= 1'b0;

            // occupancy timer (re-triggered by motion)
            if (motion)                       occ_left <= occ_timeout;
            else if (tick_1s && occ_left != 0) occ_left <= occ_left - 1'b1;

            // threshold buttons
            if (btn_up   && th < 6'd45) th <= th + 1'b1;
            if (btn_down && th > 6'd10) th <= th - 1'b1;

            if (cmd_valid) begin
                case (cmd)
                    CMD_MODE:  manual <= arg0[0];
                    CMD_FAN:   begin manual <= 1'b1; manual_duty <= arg0[6:0]; end
                    CMD_LIGHT: begin manual <= 1'b1; manual_light <= arg0[0]; end
                    CMD_TH:    th <= arg0[5:0];
                    CMD_OCC:   occ_timeout <= arg0[11:0];
                    CMD_ECO:   eco <= arg0[0];
                    CMD_FAST:  fast <= arg0[0];
                    CMD_TIME:  begin set_time <= 1'b1; set_hh <= arg0[4:0]; set_mm <= arg1[5:0]; end
                    default: ;
                endcase
            end
        end
    end
endmodule
