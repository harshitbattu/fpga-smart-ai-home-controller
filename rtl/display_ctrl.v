`timescale 1ns / 1ps
// ============================================================================
// display_ctrl : chooses what the 8-digit display shows
//   alerts (highest first):  "GAS ALrt"  gas emergency (blinking)
//                            "SEC ALrt"  intrusion alarm (blinking)
//                            "PIn   ss"  entry delay countdown
//                            "Out   ss"  exit delay countdown
//                            "LOC   ss"  PIN lockout countdown
//   normal pages (BTNL):  0: "27.5C14.05"  -> temperature + time
//                         1: "F045th28"    -> fan duty + threshold
//                         2: "L126d003"    -> learned score of this hour + days learned
//                         3: "A1 097 1"    -> neural-network probability + occupancy
// ============================================================================
module display_ctrl (
    input  wire               clk,
    input  wire               rst,
    input  wire               page_btn,
    input  wire               blink,
    input  wire               emergency,
    input  wire [2:0]         sec_state,
    input  wire [5:0]         secs_left,
    input  wire               locked,
    input  wire [5:0]         lock_left,
    input  wire signed [12:0] temp,
    input  wire               temp_ok,
    input  wire [4:0]         hh,
    input  wire [5:0]         mm,
    input  wire [6:0]         duty,
    input  wire [5:0]         th,
    input  wire [7:0]         cur_score,
    input  wire [7:0]         days,
    input  wire               ai_live,
    input  wire               ai_occ,
    input  wire [6:0]         ai_prob,
    output reg  [39:0]        chars,
    output reg  [7:0]         dps
);
    `include "home_defs.vh"

    localparam [4:0] C_A = 5'd10, C_C = 5'd12, C_D = 5'd13, C_E = 5'd14, C_F = 5'd15,
                     C_G = 5'd16, C_h = 5'd18, C_L = 5'd19, C_N = 5'd20, C_O = 5'd21,
                     C_P = 5'd22, C_R = 5'd23, C_T = 5'd24, C_U = 5'd25, C_I = 5'd26,
                     C_DASH = 5'd27, C_BL = 5'd31;

    reg [1:0] page;
    always @(posedge clk) begin
        if (rst) page <= 2'd0;
        else if (page_btn) page <= page + 1'b1;      // 4 pages
    end

    // stage 1 : absolute temperature, registered
    wire [12:0] tabs_w = temp[12] ? (~temp + 1'b1) : temp;
    reg  [7:0]  tint, tfr;
    reg         tneg;
    always @(posedge clk) begin
        tint <= (tabs_w[12:4] > 9'd99) ? 8'd99 : tabs_w[11:4];
        tfr  <= ({4'd0, tabs_w[3:0]} * 8'd10) >> 4;
        tneg <= temp[12];
    end

    `include "bcd_func.vh"
    function [4:0] d_h;  input [7:0] v; reg [11:0] t; begin t = bcd8(v); d_h = {1'b0, t[11:8]}; end endfunction
    function [4:0] d_t;  input [7:0] v; reg [11:0] t; begin t = bcd8(v); d_t = {1'b0, t[7:4]};  end endfunction
    function [4:0] d_o;  input [7:0] v; reg [11:0] t; begin t = bcd8(v); d_o = {1'b0, t[3:0]};  end endfunction

    reg [39:0] chars_n;
    reg [7:0]  dps_n;
    always @(posedge clk) begin chars <= chars_n; dps <= dps_n; end

    always @(*) begin
        dps_n = 8'h00;
        if (emergency) begin
            chars_n = blink ? {C_G, C_A, 5'd5, C_BL, C_A, C_L, C_R, C_T} : {8{C_BL}};
        end else if (sec_state == SEC_ALARM) begin
            chars_n = blink ? {5'd5, C_E, C_C, C_BL, C_A, C_L, C_R, C_T} : {8{C_BL}};
        end else if (sec_state == SEC_ENTRY) begin
            chars_n = {C_P, C_I, C_N, C_BL, C_BL, C_BL, d_t({2'd0, secs_left}), d_o({2'd0, secs_left})};
        end else if (sec_state == SEC_EXIT) begin
            chars_n = {C_O, C_U, C_T, C_BL, C_BL, C_BL, d_t({2'd0, secs_left}), d_o({2'd0, secs_left})};
        end else if (locked) begin
            chars_n = {C_L, C_O, C_C, C_BL, C_BL, C_BL, d_t({2'd0, lock_left}), d_o({2'd0, lock_left})};
        end else begin
            case (page)
                2'd1: chars_n = {C_F, d_h({1'b0, duty}), d_t({1'b0, duty}), d_o({1'b0, duty}),
                               C_T, C_h, d_t({2'd0, th}), d_o({2'd0, th})};
                2'd3: chars_n = {C_A, 5'd1, C_BL, d_h({1'b0, ai_prob}), d_t({1'b0, ai_prob}), d_o({1'b0, ai_prob}),
                               C_BL, ai_live ? (ai_occ ? 5'd1 : 5'd0) : C_DASH};
                2'd2: chars_n = {C_L, d_h(cur_score), d_t(cur_score), d_o(cur_score),
                               C_D, d_h(days), d_t(days), d_o(days)};
                default: begin
                    if (!temp_ok)
                        chars_n = {C_DASH, C_DASH, C_DASH, C_C,
                                 d_t({3'd0, hh}), d_o({3'd0, hh}), d_t({2'd0, mm}), d_o({2'd0, mm})};
                    else if (tneg)
                        chars_n = {C_DASH, d_o(tint), d_o(tfr), C_C,
                                 d_t({3'd0, hh}), d_o({3'd0, hh}), d_t({2'd0, mm}), d_o({2'd0, mm})};
                    else
                        chars_n = {d_t(tint), d_o(tint), d_o(tfr), C_C,
                                 d_t({3'd0, hh}), d_o({3'd0, hh}), d_t({2'd0, mm}), d_o({2'd0, mm})};
                    dps_n = 8'b0100_0100;    // "27.5C 14.05"
                end
            endcase
        end
    end
endmodule
