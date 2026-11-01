`timescale 1ns / 1ps
// ============================================================================
// seg7_mux : time-multiplexed driver for the 8-digit common-anode display
//   chars[5*i +: 5] = character code of digit i (0 = rightmost)
//   seg[6:0] = CG..CA (active LOW), an[7:0] active LOW
//   digit rate = f_clk / 2^REFRESH_BITS (763 Hz per digit @ 100 MHz, 95 Hz frame)
// ============================================================================
module seg7_mux #(
    parameter integer REFRESH_BITS = 17
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [39:0] chars,
    input  wire [7:0]  dps,
    output reg  [6:0]  seg,
    output reg         dp,
    output reg  [7:0]  an
);
    // character codes
    localparam [4:0] C_A = 5'd10, C_B = 5'd11, C_C = 5'd12, C_D = 5'd13, C_E = 5'd14,
                     C_F = 5'd15, C_G = 5'd16, C_H = 5'd17, C_h = 5'd18, C_L = 5'd19,
                     C_N = 5'd20, C_O = 5'd21, C_P = 5'd22, C_R = 5'd23, C_T = 5'd24,
                     C_U = 5'd25, C_I = 5'd26, C_DASH = 5'd27, C_BLANK = 5'd31;

    function [6:0] enc;          // active-high {g,f,e,d,c,b,a}
        input [4:0] ch;
        case (ch)
            5'd0: enc = 7'h3F;  5'd1: enc = 7'h06;  5'd2: enc = 7'h5B;  5'd3: enc = 7'h4F;
            5'd4: enc = 7'h66;  5'd5: enc = 7'h6D;  5'd6: enc = 7'h7D;  5'd7: enc = 7'h07;
            5'd8: enc = 7'h7F;  5'd9: enc = 7'h6F;
            C_A:  enc = 7'h77;  C_B:  enc = 7'h7C;  C_C:  enc = 7'h39;  C_D:  enc = 7'h5E;
            C_E:  enc = 7'h79;  C_F:  enc = 7'h71;  C_G:  enc = 7'h3D;  C_H:  enc = 7'h76;
            C_h:  enc = 7'h74;  C_L:  enc = 7'h38;  C_N:  enc = 7'h54;  C_O:  enc = 7'h5C;
            C_P:  enc = 7'h73;  C_R:  enc = 7'h50;  C_T:  enc = 7'h78;  C_U:  enc = 7'h1C;
            C_I:  enc = 7'h30;  C_DASH: enc = 7'h40;
            default: enc = 7'h00;
        endcase
    endfunction

    reg  [REFRESH_BITS+2:0] cnt;
    wire [2:0] sel = cnt[REFRESH_BITS+2:REFRESH_BITS];

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 0; seg <= 7'h7F; dp <= 1'b1; an <= 8'hFF;
        end else begin
            cnt <= cnt + 1'b1;
            an  <= ~(8'd1 << sel);
            seg <= ~enc(chars[5*sel +: 5]);
            dp  <= ~dps[sel];
        end
    end
endmodule
