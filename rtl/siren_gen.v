`timescale 1ns / 1ps
// ============================================================================
// siren_gen : audible alarm tones for the board's mono audio output
//   alarm = 1 : two-tone siren, 800 Hz / 1200 Hz alternating every 0.5 s
//   chirp = 1 : 2 kHz beep for 0.1 s every second (entry / exit delay)
// ============================================================================
module siren_gen #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire clk,
    input  wire rst,
    input  wire alarm,
    input  wire chirp,
    output reg  tone
);
    localparam integer H_LO  = CLK_HZ / 1600;    // half period of 800 Hz
    localparam integer H_HI  = CLK_HZ / 2400;    // half period of 1200 Hz
    localparam integer H_CH  = CLK_HZ / 4000;    // half period of 2000 Hz
    localparam integer SW    = $clog2(CLK_HZ);
    localparam integer HW    = $clog2(H_LO + 1);

    reg [SW-1:0] slow;        // 1 s period counter
    reg [HW-1:0] hc;
    reg          sq;

    wire hi_phase = (slow >= CLK_HZ / 2);
    wire [HW-1:0] half = alarm ? (hi_phase ? H_HI : H_LO) : H_CH;
    wire beep_win = (slow < CLK_HZ / 10);

    always @(posedge clk) begin
        if (rst) begin
            slow <= 0; hc <= 0; sq <= 1'b0; tone <= 1'b0;
        end else begin
            slow <= (slow == CLK_HZ - 1) ? 0 : slow + 1'b1;
            if (hc >= half - 1) begin hc <= 0; sq <= ~sq; end
            else hc <= hc + 1'b1;
            tone <= alarm ? sq : (chirp && beep_win) ? sq : 1'b0;
        end
    end
endmodule
