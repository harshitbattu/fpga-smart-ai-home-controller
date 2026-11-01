`timescale 1ns / 1ps
// ============================================================================
// pwm_gen : fixed-frequency PWM, duty in percent (0..100)
//   f_pwm = f_clk / PERIOD  -> 100 MHz / 4000 = 25 kHz (standard fan PWM)
// ============================================================================
module pwm_gen #(
    parameter integer PERIOD = 4000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [6:0] duty,
    output reg        pwm
);
    localparam integer STEP = PERIOD / 100;
    localparam integer W    = $clog2(PERIOD);

    reg  [W-1:0] cnt;
    wire [W+6:0] cmp = duty * STEP;

    always @(posedge clk) begin
        if (rst) begin
            cnt <= 0; pwm <= 1'b0;
        end else begin
            cnt <= (cnt == PERIOD - 1) ? 0 : cnt + 1'b1;
            pwm <= (cnt < cmp);
        end
    end
endmodule
