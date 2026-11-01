`timescale 1ns / 1ps
// ============================================================================
// nn_engine : 8-bit neural-network inference engine (MLP 4-8-1, ReLU)
//   Occupancy detection from temperature, humidity, light and CO2.
//   Weights trained offline on the UCI Occupancy Detection dataset
//   (ai/train_nn.py) and quantised to 8 bits (rtl/nn_weights.vh).
//
//   Datapath: ONE multiply-accumulate unit, time-multiplexed
//     1. normalise   xq[i] = clamp(((x[i] - MU[i]) * K[i]) >>> 12, -127, 127)   4 cycles x2
//     2. hidden      acc   = b1[j] + sum_i W1[j][i] * xq[i]                      8 x 4 MACs
//                    h[j]  = clamp((ReLU(acc) * M1) >> 16, 0, 127)
//     3. output      z     = b2 + sum_j W2[j] * h[j]                             8 MACs
//     4. decision    occ   = (z > 0),  prob = sigmoid LUT[clamp(z >>> SH)]
//   Latency: 58 clock cycles (0.58 us at 100 MHz). Bit-exact with the Python
//   integer model (verified on all 12 417 test samples, tb/tb_nn_engine.v).
//
//   Inputs : t_x10  temperature in 0.1 degC     rh_x10 relative humidity in 0.1 %
//            lux    illuminance in lux          co2    CO2 in ppm
// ============================================================================
module nn_engine (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,
    input  wire signed [15:0] t_x10,
    input  wire signed [15:0] rh_x10,
    input  wire signed [15:0] lux,
    input  wire signed [15:0] co2,
    output reg                busy,
    output reg                done,
    output reg                occ,
    output reg  [6:0]         prob,
    output reg  signed [23:0] z
);
    `include "nn_weights.vh"

    localparam [2:0] S_IDLE = 3'd0, S_NMUL = 3'd1, S_NCLP = 3'd2, S_L1 = 3'd3,
                     S_L1Q = 3'd4, S_L2 = 3'd5, S_OUT = 3'd6;

    reg [2:0]         st;
    reg [2:0]         j;
    reg [1:0]         i;
    reg signed [15:0] x   [0:3];
    reg signed [7:0]  xq  [0:3];
    reg        [6:0]  h   [0:7];
    reg signed [33:0] p;             // normalisation product
    reg signed [23:0] acc;

    // per-input normalisation constants
    reg signed [15:0] mu_i, k_i;
    always @(*) begin
        case (i)
            2'd0: begin mu_i = NN_MU0; k_i = NN_K0; end
            2'd1: begin mu_i = NN_MU1; k_i = NN_K1; end
            2'd2: begin mu_i = NN_MU2; k_i = NN_K2; end
            default: begin mu_i = NN_MU3; k_i = NN_K3; end
        endcase
    end

    wire signed [16:0] diff    = {x[i][15], x[i]} - {mu_i[15], mu_i};
    wire signed [21:0] p_shift = p >>> 12;
    wire signed [7:0]  clampq  = (p_shift > 22'sd127)  ? 8'sd127  :
                                 (p_shift < -22'sd127) ? -8'sd127 : p_shift[7:0];

    // hidden-layer MAC and requantisation
    wire signed [15:0] mac1  = nn_w1(j, i) * xq[i];
    wire signed [23:0] relu  = acc[23] ? 24'sd0 : acc;
    wire        [41:0] rq    = relu[22:0] * NN_M1;               // non-negative
    wire        [25:0] rqs   = rq >> 16;
    wire        [6:0]  hq    = (rqs > 26'd127) ? 7'd127 : rqs[6:0];
    // output-layer MAC
    wire signed [15:0] mac2  = nn_w2(j) * $signed({1'b0, h[j]});
    // sigmoid LUT index
    wire signed [23:0] zsh   = acc >>> NN_SH;
    wire        [7:0]  lidx  = (zsh > 24'sd127)  ? 8'd127 :
                               (zsh < -24'sd128) ? 8'h80  : zsh[7:0];

    integer n;
    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; busy <= 1'b0; done <= 1'b0; occ <= 1'b0; prob <= 7'd0; z <= 24'sd0;
            j <= 3'd0; i <= 2'd0; p <= 34'sd0; acc <= 24'sd0;
            for (n = 0; n < 4; n = n + 1) begin x[n] <= 16'sd0; xq[n] <= 8'sd0; end
            for (n = 0; n < 8; n = n + 1) h[n] <= 7'd0;
        end else begin
            done <= 1'b0;
            case (st)
            S_IDLE: if (start) begin
                x[0] <= t_x10; x[1] <= rh_x10; x[2] <= lux; x[3] <= co2;
                i <= 2'd0; busy <= 1'b1; st <= S_NMUL;
            end
            // ---- 1. input normalisation ----
            S_NMUL: begin p <= diff * k_i; st <= S_NCLP; end
            S_NCLP: begin
                xq[i] <= clampq;
                if (i == 2'd3) begin i <= 2'd0; j <= 3'd0; acc <= nn_b1(3'd0); st <= S_L1; end
                else begin i <= i + 1'b1; st <= S_NMUL; end
            end
            // ---- 2. hidden layer ----
            S_L1: begin
                acc <= acc + mac1;
                if (i == 2'd3) st <= S_L1Q;
                i <= i + 1'b1;
            end
            S_L1Q: begin
                h[j] <= hq;
                if (j == 3'd7) begin j <= 3'd0; acc <= NN_B2; st <= S_L2; end
                else begin j <= j + 1'b1; acc <= nn_b1(j + 1'b1); st <= S_L1; end
            end
            // ---- 3. output layer ----
            S_L2: begin
                acc <= acc + mac2;
                if (j == 3'd7) st <= S_OUT;
                j <= j + 1'b1;
            end
            // ---- 4. decision ----
            S_OUT: begin
                z    <= acc;
                occ  <= (acc > 24'sd0);
                prob <= nn_prob(lidx);
                busy <= 1'b0; done <= 1'b1; st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
