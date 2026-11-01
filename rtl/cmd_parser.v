`timescale 1ns / 1ps
// ============================================================================
// cmd_parser : streaming ASCII command-line parser
//   Line format :  KEYWORD [ARG1] .. [ARG4] <CR or LF>   (case-insensitive)
//   * keyword  : up to 8 letters, packed right-justified in a 64-bit register
//   * ARG1..ARG4: decimal numbers (max 4 digits); ARG1 is also kept as a word
//                (AUTO / MANUAL / ON / OFF)
//   * syntax + range are validated here; invalid lines are answered "ERR"
//   * security (ARM/DISARM/PIN) and safety (ACK) commands are answered by
//     their owner modules; everything else is answered here.
// ============================================================================
module cmd_parser (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         cmd_valid,
    output reg  [4:0]  cmd,
    output reg  [13:0] arg0,
    output reg  [13:0] arg1,
    output reg  [13:0] arg2,
    output reg  [13:0] arg3,
    output reg         rsp_valid,
    output reg  [2:0]  rsp_code
);
    `include "home_defs.vh"

    // keyword constants (right-justified ASCII)
    localparam [63:0] K_STATUS = "STATUS", K_S      = "S",
                      K_MODE   = "MODE",   K_FAN    = "FAN",
                      K_LIGHT  = "LIGHT",  K_TH     = "TH",
                      K_OCC    = "OCC",    K_ARM    = "ARM",
                      K_DISARM = "DISARM", K_PIN    = "PIN",
                      K_ACK    = "ACK",    K_TIME   = "TIME",
                      K_FAST   = "FAST",   K_ECO    = "ECO",
                      K_PROF   = "PROFILE",K_ENERGY = "ENERGY",
                      K_CLEAR  = "CLEAR",  K_AI     = "AI",
                      K_ENV    = "ENV",
                      W_AUTO   = "AUTO",   W_MANUAL = "MANUAL",
                      W_ON     = "ON",     W_OFF    = "OFF";

    reg [63:0] kw, w1;
    reg [3:0]  kw_len, w1_len;
    reg [13:0] n0, n1, n2, n3;
    reg [2:0]  d0, d1, d2, d3;
    reg        nn0, nn1, nn2, nn3;   // argument contains a non-digit
    reg [2:0]  ntok;                 // tokens started on this line (max 5)
    reg        in_tok, bad;

    // upper-case conversion
    wire [7:0] c        = (rx_data >= "a" && rx_data <= "z") ? (rx_data - 8'd32) : rx_data;
    wire       is_digit = (c >= "0") && (c <= "9");
    wire [3:0] dv       = c[3:0];
    wire       is_space = (c == 8'h20) || (c == 8'h09);
    wire       is_eol   = (c == 8'h0D) || (c == 8'h0A);
    wire [2:0] cur      = in_tok ? (ntok - 1'b1) : ntok;

    // ---- decode helpers (valid at end-of-line) ----
    wire [2:0] nargs = ntok - 1'b1;
    wire num0 = (d0 != 0) && !nn0;
    wire num1 = (d1 != 0) && !nn1;
    wire num2 = (d2 != 0) && !nn2;
    wire num3 = (d3 != 0) && !nn3;
    wire pin0 = num0 && (d0 == 3'd4);
    wire pin1 = num1 && (d1 == 3'd4);

    always @(posedge clk) begin
        if (rst) begin
            kw <= 0; w1 <= 0; kw_len <= 0; w1_len <= 0;
            n0 <= 0; n1 <= 0; d0 <= 0; d1 <= 0; nn0 <= 0; nn1 <= 0;
            n2 <= 0; n3 <= 0; d2 <= 0; d3 <= 0; nn2 <= 0; nn3 <= 0;
            ntok <= 0; in_tok <= 0; bad <= 0;
            cmd_valid <= 0; cmd <= CMD_NONE; arg0 <= 0; arg1 <= 0; arg2 <= 0; arg3 <= 0;
            rsp_valid <= 0; rsp_code <= RSP_NONE;
        end else begin
            cmd_valid <= 1'b0;
            rsp_valid <= 1'b0;
            if (rx_valid) begin
                if (is_eol) begin
                    if (ntok != 0) begin
                        // ------------------ execute the line ------------------
                        arg0 <= n0;
                        arg1 <= n1;
                        arg2 <= n2;
                        arg3 <= n3;
                        if (bad) begin
                            rsp_valid <= 1'b1; rsp_code <= RSP_ERR;
                        end else if ((kw == K_STATUS || kw == K_S) && nargs == 0) begin
                            rsp_valid <= 1'b1; rsp_code <= RSP_STATUS;
                        end else if (kw == K_MODE && nargs == 1 && (w1 == W_AUTO || w1 == W_MANUAL)) begin
                            cmd_valid <= 1'b1; cmd <= CMD_MODE; arg0 <= (w1 == W_MANUAL) ? 14'd1 : 14'd0;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_FAN && nargs == 1 && num0 && n0 <= 100) begin
                            cmd_valid <= 1'b1; cmd <= CMD_FAN;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_LIGHT && nargs == 1 &&
                                     ((num0 && n0 <= 1) || w1 == W_ON || w1 == W_OFF)) begin
                            cmd_valid <= 1'b1; cmd <= CMD_LIGHT;
                            arg0 <= (w1 == W_ON || (num0 && n0 == 1)) ? 14'd1 : 14'd0;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_TH && nargs == 1 && num0 && n0 >= 10 && n0 <= 45) begin
                            cmd_valid <= 1'b1; cmd <= CMD_TH;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_OCC && nargs == 1 && num0 && n0 >= 5 && n0 <= 3600) begin
                            cmd_valid <= 1'b1; cmd <= CMD_OCC;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_ARM && nargs == 1 && pin0) begin
                            cmd_valid <= 1'b1; cmd <= CMD_ARM;              // security replies
                        end else if (kw == K_DISARM && nargs == 1 && pin0) begin
                            cmd_valid <= 1'b1; cmd <= CMD_DISARM;           // security replies
                        end else if (kw == K_PIN && nargs == 2 && pin0 && pin1) begin
                            cmd_valid <= 1'b1; cmd <= CMD_PIN;              // security replies
                        end else if (kw == K_ACK && nargs == 0) begin
                            cmd_valid <= 1'b1; cmd <= CMD_ACK;              // safety replies
                        end else if (kw == K_TIME && nargs == 2 && num0 && num1 && n0 <= 23 && n1 <= 59) begin
                            cmd_valid <= 1'b1; cmd <= CMD_TIME;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_FAST && nargs == 1 && num0 && n0 <= 1) begin
                            cmd_valid <= 1'b1; cmd <= CMD_FAST;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_ECO && nargs == 1 && num0 && n0 <= 1) begin
                            cmd_valid <= 1'b1; cmd <= CMD_ECO;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_PROF && nargs == 0) begin
                            rsp_valid <= 1'b1; rsp_code <= RSP_PROFILE;
                        end else if (kw == K_ENERGY && nargs == 0) begin
                            rsp_valid <= 1'b1; rsp_code <= RSP_ENERGY;
                        end else if (kw == K_CLEAR && nargs == 0) begin
                            cmd_valid <= 1'b1; cmd <= CMD_CLEAR;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else if (kw == K_AI && nargs == 4 && num0 && num1 && num2 && num3) begin
                            cmd_valid <= 1'b1; cmd <= CMD_AI;                // AI unit replies
                        end else if (kw == K_ENV && nargs == 3 && num0 && num1 && num2) begin
                            cmd_valid <= 1'b1; cmd <= CMD_ENV;
                            rsp_valid <= 1'b1; rsp_code <= RSP_OK;
                        end else begin
                            rsp_valid <= 1'b1; rsp_code <= RSP_ERR;
                        end
                    end
                    // clear line state
                    kw <= 0; w1 <= 0; kw_len <= 0; w1_len <= 0;
                    n0 <= 0; n1 <= 0; d0 <= 0; d1 <= 0; nn0 <= 0; nn1 <= 0;
                    n2 <= 0; n3 <= 0; d2 <= 0; d3 <= 0; nn2 <= 0; nn3 <= 0;
                    ntok <= 0; in_tok <= 0; bad <= 0;
                end else if (is_space) begin
                    in_tok <= 1'b0;
                end else begin
                    if (!in_tok) begin
                        in_tok <= 1'b1;
                        if (ntok == 3'd5) bad <= 1'b1;
                        else              ntok <= ntok + 1'b1;
                    end
                    case (cur)
                        3'd0: if (kw_len == 4'd8) bad <= 1'b1;
                              else begin kw <= {kw[55:0], c}; kw_len <= kw_len + 1'b1; end
                        3'd1: begin
                                  if (w1_len != 4'd8) begin w1 <= {w1[55:0], c}; w1_len <= w1_len + 1'b1; end
                                  if (is_digit) begin
                                      if (d0 == 3'd4) bad <= 1'b1;
                                      else begin n0 <= n0 * 10 + dv; d0 <= d0 + 1'b1; end
                                  end else nn0 <= 1'b1;
                              end
                        3'd2: begin
                                  if (is_digit) begin
                                      if (d1 == 3'd4) bad <= 1'b1;
                                      else begin n1 <= n1 * 10 + dv; d1 <= d1 + 1'b1; end
                                  end else nn1 <= 1'b1;
                              end
                        3'd3: begin
                                  if (is_digit) begin
                                      if (d2 == 3'd4) bad <= 1'b1;
                                      else begin n2 <= n2 * 10 + dv; d2 <= d2 + 1'b1; end
                                  end else nn2 <= 1'b1;
                              end
                        3'd4: begin
                                  if (is_digit) begin
                                      if (d3 == 3'd4) bad <= 1'b1;
                                      else begin n3 <= n3 * 10 + dv; d3 <= d3 + 1'b1; end
                                  end else nn3 <= 1'b1;
                              end
                        default: bad <= 1'b1;
                    endcase
                end
            end
        end
    end
endmodule
