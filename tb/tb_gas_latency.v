`timescale 1ns / 1ps
// ============================================================================
// tb_gas_latency : zoomed view of the gas safety interlock at the real clock
//   Shows clk, gas input, synchronizer stages, emergency, valve, fan, siren.
// ============================================================================
module tb_gas_latency;
    reg         clk = 1'b0, cpu_resetn = 1'b0;
    reg  [15:0] sw = 16'h0000;
    wire [15:0] led;
    wire [6:0]  seg;
    wire [7:0]  an;
    wire [3:0]  jb;
    wire        tmp_scl, tmp_sda, uart_txd, dp, aud_pwm, aud_sd;
    wire        l16r, l16g, l16b, l17r, l17g, l17b;
    pullup (tmp_scl);
    pullup (tmp_sda);
    always #5 clk = ~clk;

    smart_home_top #(.CLK_HZ(100_000), .SEC_DIV(10_000), .CLKS_PER_BIT(16), .DB_CYCLES(20),
                     .I2C_QDIV(5), .TEMP_POLL(3000), .PWM_PERIOD(100), .REFRESH_BITS(4)) dut (
        .clk(clk), .cpu_resetn(cpu_resetn), .sw(sw), .btnc(1'b0), .btnu(1'b0), .btnd(1'b0),
        .btnl(1'b0), .btnr(1'b0), .led(led), .led16_r(l16r), .led16_g(l16g), .led16_b(l16b),
        .led17_r(l17r), .led17_g(l17g), .led17_b(l17b), .seg(seg), .dp(dp), .an(an),
        .uart_rxd(1'b1), .uart_txd(uart_txd), .tmp_scl(tmp_scl), .tmp_sda(tmp_sda),
        .ja(4'b0100), .jb(jb), .aud_pwm(aud_pwm), .aud_sd(aud_sd));

    wire gas_sw    = sw[2];
    wire sync_ff1  = dut.u_safety.g0;
    wire sync_ff2  = dut.u_safety.g1;
    wire emergency = dut.emergency;
    wire valve     = jb[3];
    wire fan_pwm   = jb[0];
    wire siren     = jb[2];

    initial begin
        repeat (20) @(posedge clk); cpu_resetn = 1'b1;
        repeat (500) @(posedge clk);
        #3;
        $dumpfile("sim/tb_gas_latency.vcd");
        $dumpvars(0, clk, gas_sw, sync_ff1, sync_ff2, emergency, valve, fan_pwm, siren);
        repeat (4) @(posedge clk); #3 sw[2] = 1'b1;      // gas detected (asynchronous)
        repeat (8) @(posedge clk);
        #3 $finish;
    end
endmodule
