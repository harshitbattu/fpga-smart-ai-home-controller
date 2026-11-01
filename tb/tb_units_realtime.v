`timescale 1ns / 1ps
// ============================================================================
// tb_units_realtime : unit tests at the REAL hardware rates (100 MHz clock)
//   U1 uart_tx -> uart_rx loop-back at 115200 baud, all 256 byte values
//   U2 pwm_gen at 25 kHz: period and duty measured in ns
//   U3 adt7420_reader at 100 kHz SCL against the ADT7420 model
// ============================================================================
module tb_units_realtime;
    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;

    integer errors = 0, checks = 0;
    task check;
        input cond;
        input [8*64-1:0] name;
        begin
            checks = checks + 1;
            if (cond) $display("[%t] PASS : %0s", $time, name);
            else begin errors = errors + 1; $display("[%t] FAIL : %0s", $time, name); end
        end
    endtask

    // ---------------- U1 UART loop-back ----------------
    reg  [7:0] txd = 8'd0;
    reg        txs = 1'b0;
    wire       line, busy, rxv, ferr;
    wire [7:0] rxd;
    uart_tx #(.CLKS_PER_BIT(868)) u_tx (.clk(clk), .rst(rst), .data(txd), .start(txs), .tx(line), .busy(busy));
    uart_rx #(.CLKS_PER_BIT(868)) u_rx (.clk(clk), .rst(rst), .rx(line), .data(rxd), .valid(rxv), .frame_err(ferr));

    // ---------------- U2 PWM ----------------
    reg  [6:0] duty = 7'd0;
    wire       pwm;
    pwm_gen #(.PERIOD(4000)) u_pwm (.clk(clk), .rst(rst), .duty(duty), .pwm(pwm));

    // ---------------- U3 I2C temperature ----------------
    wire scl, sda, sda_oe, scl_oe, tvalid, tfault;
    wire signed [12:0] traw;
    pullup (scl);
    pullup (sda);
    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;
    adt7420_reader #(.QDIV(250), .POLL_CYCLES(1000)) u_i2c (
        .clk(clk), .rst(rst), .sda_in(sda), .sda_oe(sda_oe), .scl_oe(scl_oe),
        .temp_raw(traw), .valid(tvalid), .fault(tfault));
    adt7420_model sensor (.scl(scl), .sda(sda));

    reg measure = 1'b0;
    realtime m_fall = 0, m_rise = 0;
    always @(negedge line) if (measure && m_fall == 0) m_fall = $realtime;
    always @(posedge line) if (measure && m_fall != 0 && m_rise == 0) m_rise = $realtime;

    integer i, bad, t_rise1, t_rise2, t_fall, bit_ns;
    realtime ts, tf, tr;

    initial $timeformat(-6, 1, " us", 12);

    initial begin
        $dumpfile("sim/tb_units_realtime.vcd");
        $dumpvars(0, tb_units_realtime.line, tb_units_realtime.rxv, tb_units_realtime.rxd,
                     tb_units_realtime.pwm, tb_units_realtime.duty,
                     tb_units_realtime.scl, tb_units_realtime.sda, tb_units_realtime.traw,
                     tb_units_realtime.tvalid);
        repeat (10) @(posedge clk); rst = 1'b0;

        // ---- U1 ----
        $display("\n==== U1 : UART loop-back at 115200 baud ====");
        bad = 0;
        for (i = 0; i < 256; i = i + 1) begin
            measure = (i == 8'h55);             // measure the start-bit width once
            @(posedge clk); txd = i[7:0]; txs = 1'b1;
            @(posedge clk); txs = 1'b0;
            @(posedge rxv);
            if (rxd !== i[7:0] || ferr) bad = bad + 1;
            wait (!busy);
        end
        bit_ns = m_rise - m_fall;
        check(bad == 0, "U1 all 256 byte values received correctly");
        $display("        start-bit width = %0d ns (ideal 8680.6 ns for 115200 baud)", bit_ns);
        check(bit_ns >= 8670 && bit_ns <= 8690, "U1 bit time = 8.68 us (115200 baud, 0.01 % error)");

        // ---- U2 ----
        $display("\n==== U2 : fan PWM at 25 kHz ====");
        duty = 7'd47;
        repeat (8000) @(posedge clk);
        @(posedge pwm); tr = $realtime;
        @(negedge pwm); tf = $realtime;
        @(posedge pwm); ts = $realtime;
        $display("        period = %0.1f ns (%0.2f kHz), high time = %0.1f ns (%0.1f %%)",
                 ts - tr, 1.0e6 / (ts - tr), tf - tr, 100.0 * (tf - tr) / (ts - tr));
        check((ts - tr) == 40000.0, "U2 PWM period 40 us = 25 kHz");
        check((tf - tr) == 18800.0, "U2 duty 47 % -> 18.8 us high");
        duty = 7'd100; repeat (8000) @(posedge clk);
        check(pwm == 1'b1, "U2 duty 100 % -> always high");
        duty = 7'd0; repeat (8000) @(posedge clk);
        check(pwm == 1'b0, "U2 duty 0 % -> always low");

        // ---- U3 ----
        $display("\n==== U3 : ADT7420 read at 100 kHz SCL ====");
        sensor.set_temp16(27*16 + 8);            // 27.5 C
        @(posedge tvalid); @(posedge tvalid);
        $display("        temp_raw = %0d  (= %0.4f C)", traw, traw / 16.0);
        check(traw == 13'sd440, "U3 27.5 C read correctly");
        wait (u_i2c.st == 4'd4);                 // inside the first data byte
        @(posedge scl); ts = $realtime; @(posedge scl); tr = $realtime;
        $display("        SCL period = %0.0f ns (%0.1f kHz)", tr - ts, 1.0e6 / (tr - ts));
        check((tr - ts) == 10000.0, "U3 SCL = 100 kHz");
        sensor.set_temp16(-(10*16 + 4));         // -10.25 C
        @(posedge tvalid); @(posedge tvalid);
        check(traw == -13'sd164, "U3 -10.25 C (two's complement) read correctly");

        $display("\n==================================================");
        $display(" TOTAL CHECKS : %0d   FAILED : %0d", checks, errors);
        if (errors == 0) $display(" RESULT       : ALL TESTS PASSED");
        else             $display(" RESULT       : FAILURES PRESENT");
        $display("==================================================\n");
        $finish;
    end
endmodule
