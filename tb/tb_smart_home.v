`timescale 1ns / 1ps
// ============================================================================
// tb_smart_home : self-checking system testbench for smart_home_top
//   Time is scaled so the simulation finishes quickly:
//     1 "second"  = 10 000 clocks (100 us)      UART = 16 clocks per bit
//     fast mode   : 1 "hour" = 1 second -> a full day = 2.4 ms of sim time
//   Every check prints PASS/FAIL; the summary is printed at the end.
// ============================================================================
module tb_smart_home;
    // ---------------- parameters (scaled for simulation) ----------------
    localparam integer SEC   = 10_000;
    localparam integer BIT   = 16;
    localparam integer PWM_P = 100;

    // ---------------- DUT connections ----------------
    reg         clk = 1'b0;
    reg         cpu_resetn = 1'b0;
    reg  [15:0] sw = 16'h0000;
    reg         btnc = 0, btnu = 0, btnd = 0, btnl = 0, btnr = 0;
    wire [15:0] led;
    wire        led16_r, led16_g, led16_b, led17_r, led17_g, led17_b;
    wire [6:0]  seg;
    wire        dp;
    wire [7:0]  an;
    reg         uart_rxd = 1'b1;
    wire        uart_txd;
    wire        tmp_scl, tmp_sda;
    reg  [3:0]  ja = 4'b0100;           // MQ-2 output idle HIGH (no gas)
    wire [3:0]  jb;
    wire        aud_pwm, aud_sd;

    pullup (tmp_scl);
    pullup (tmp_sda);
    pullup (aud_pwm);

    always #5 clk = ~clk;               // 100 MHz

    smart_home_top #(
        .CLK_HZ(100_000), .SEC_DIV(SEC), .CLKS_PER_BIT(BIT), .DB_CYCLES(20),
        .I2C_QDIV(5), .TEMP_POLL(3000), .PWM_PERIOD(PWM_P), .REFRESH_BITS(4),
        .EXIT_SECS(10), .ENTRY_SECS(15), .LOCK_SECS(30), .GAS_CLEAR_S(5)
    ) dut (
        .clk(clk), .cpu_resetn(cpu_resetn), .sw(sw),
        .btnc(btnc), .btnu(btnu), .btnd(btnd), .btnl(btnl), .btnr(btnr),
        .led(led), .led16_r(led16_r), .led16_g(led16_g), .led16_b(led16_b),
        .led17_r(led17_r), .led17_g(led17_g), .led17_b(led17_b),
        .seg(seg), .dp(dp), .an(an), .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .tmp_scl(tmp_scl), .tmp_sda(tmp_sda), .ja(ja), .jb(jb),
        .aud_pwm(aud_pwm), .aud_sd(aud_sd));

    adt7420_model sensor (.scl(tmp_scl), .sda(tmp_sda));

    // friendly names for the waveform
    wire fan_pwm   = jb[0];
    wire light_out = jb[1];
    wire siren     = jb[2];
    wire valve     = jb[3];

    // ---------------- bookkeeping ----------------
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

    task wait_cycles;
        input integer n;
        begin repeat (n) @(posedge clk); end
    endtask

    task wait_secs;
        input integer n;
        begin repeat (n) wait_cycles(SEC); end
    endtask

    // ---------------- UART driver (PC -> FPGA) ----------------
    task uart_byte;
        input [7:0] b;
        integer i;
        begin
            uart_rxd = 1'b0; wait_cycles(BIT);
            for (i = 0; i < 8; i = i + 1) begin uart_rxd = b[i]; wait_cycles(BIT); end
            uart_rxd = 1'b1; wait_cycles(BIT);
        end
    endtask

    task send_cmd;                       // string + CR
        input [8*32-1:0] s;
        input integer    n;
        integer i;
        begin
            $display("[%t] >> %0s", $time, s);
            for (i = n - 1; i >= 0; i = i - 1) uart_byte(s[8*i +: 8]);
            uart_byte(8'h0D);
        end
    endtask

    // ---------------- UART monitor (FPGA -> PC) ----------------
    reg [7:0] lb [0:255];                // current / last complete line
    reg [7:0] cb [0:255];                // line being received
    integer   llen = 0, clen = 0, line_count = 0;
    reg [7:0] rxb;
    integer   mi;
    reg [8*200-1:0] line_str;

    initial begin : monitor
        forever begin
            @(negedge uart_txd);
            wait_cycles(BIT + BIT/2);
            for (mi = 0; mi < 8; mi = mi + 1) begin rxb[mi] = uart_txd; wait_cycles(BIT); end
            if (rxb == 8'h0A) begin
                line_str = 0;
                for (mi = 0; mi < clen; mi = mi + 1) begin
                    lb[mi] = cb[mi];
                    line_str = {line_str[8*199-1:0], cb[mi]};
                end
                llen = clen; clen = 0; line_count = line_count + 1;
                $display("[%t] << %0s", $time, line_str);
            end else if (rxb != 8'h0D) begin
                cb[clen] = rxb; clen = clen + 1;
            end
        end
    end

    function has_prefix;
        input [8*48-1:0] p;
        input integer n;
        integer i;
        begin
            has_prefix = (llen >= n);
            for (i = 0; i < n; i = i + 1)
                if (i < llen && lb[i] != p[8*(n-1-i) +: 8]) has_prefix = 0;
        end
    endfunction

    function has_sub;
        input [8*48-1:0] p;
        input integer n;
        integer i, j;
        reg ok;
        begin
            has_sub = 0;
            for (i = 0; i + n <= llen; i = i + 1) begin
                ok = 1;
                for (j = 0; j < n; j = j + 1)
                    if (lb[i+j] != p[8*(n-1-j) +: 8]) ok = 0;
                if (ok) has_sub = 1;
            end
        end
    endfunction

    // wait until a line starting with p arrives (or timeout)
    task expect_line;
        input [8*48-1:0] p;
        input integer n;
        input integer timeout;
        input [8*64-1:0] name;
        integer t, seen;
        reg found;
        begin
            found = 0; seen = line_count;
            for (t = 0; t < timeout && !found; t = t + 1) begin
                @(posedge clk);
                if (line_count != seen) begin
                    seen = line_count;
                    if (has_prefix(p, n)) found = 1;
                end
            end
            check(found, name);
        end
    endtask

    // wait until a line containing p arrives (or timeout)
    task expect_sub;
        input [8*48-1:0] p;
        input integer n;
        input integer timeout;
        input [8*64-1:0] name;
        integer t, seen;
        reg found;
        begin
            found = 0; seen = line_count;
            for (t = 0; t < timeout && !found; t = t + 1) begin
                @(posedge clk);
                if (line_count != seen) begin
                    seen = line_count;
                    if (has_sub(p, n)) found = 1;
                end
            end
            check(found, name);
        end
    endtask

    // ---------------- measurements ----------------
    task measure_duty;                   // % of time fan_pwm is high over 4 PWM periods
        output integer pct;
        integer i, hi;
        begin
            hi = 0;
            for (i = 0; i < 4*PWM_P; i = i + 1) begin @(posedge clk); if (fan_pwm) hi = hi + 1; end
            pct = (hi * 100) / (4*PWM_P);
        end
    endtask

    task set_temp;                       // degC * 10  (e.g. 285 = 28.5 C)
        input integer t10;
        begin
            sensor.set_temp16((t10 * 16) / 10);
            wait_cycles(2*3000 + 2000);  // two sensor polls
        end
    endtask

    integer d, lat, i;
    reg [7:0] s18;

    // hours in which the "family" is at home in the learning test
    function active_hour;
        input [4:0] h;
        active_hour = (h >= 7 && h <= 9) || (h >= 18 && h <= 22);
    endfunction
    reg pattern_en = 1'b0;
    always @(posedge clk) if (pattern_en) sw[0] <= active_hour(dut.hh) && (dut.mm < 6'd58);

    // ========================================================================
    initial $timeformat(-6, 1, " us", 12);

    initial begin
        $dumpfile("sim/tb_smart_home.vcd");
        $dumpvars(0, tb_smart_home.cpu_resetn, tb_smart_home.sw, tb_smart_home.uart_rxd,
                     tb_smart_home.uart_txd, tb_smart_home.fan_pwm, tb_smart_home.light_out,
                     tb_smart_home.siren, tb_smart_home.valve, tb_smart_home.tmp_scl,
                     tb_smart_home.tmp_sda, tb_smart_home.led);
        $dumpvars(0, dut.ai_occ, dut.ai_prob, dut.ai_live, dut.temp_raw, dut.duty, dut.sec_state, dut.emergency, dut.occupied,
                     dut.predicted, dut.hh, dut.days, dut.cur_score, dut.manual, dut.th,
                     dut.fault, dut.u_climate.hot, dut.cmd_valid, dut.cmd, dut.locked,
                     dut.secs_left, dut.ev_anom, dut.ev_inact, dut.warn, dut.motion, dut.dark,
                     dut.door_open, dut.gas_in, dut.u_safety.g0, dut.u_safety.g1);

        // ------------------------------------------------ T1 reset / banner
        $display("\n==== T1 : reset and start-up banner ====");
        wait_cycles(20); cpu_resetn = 1'b1;
        expect_line("SMART HOME CONTROLLER READY", 27, 5000, "T1 banner after reset");

        // ------------------------------------------------ T2 temperature over I2C
        $display("\n==== T2 : ADT7420 temperature over I2C ====");
        set_temp(250);
        check(dut.temp_raw == 13'sd400, "T2 temp_raw = 400 (25.0 C)");
        send_cmd("STATUS", 6);
        expect_sub("T=+25.0C", 8, 30000, "T2 STATUS reports T=+25.0C");
        set_temp(-55);
        check(dut.temp_raw == -13'sd88, "T2 negative temperature -5.5 C");
        send_cmd("S", 1);
        expect_sub("T=-05.5C", 8, 30000, "T2 STATUS reports T=-05.5C");

        // ------------------------------------------------ T3 fan hysteresis + proportional
        $display("\n==== T3 : automatic fan control (hysteresis + proportional) ====");
        sw[0] = 1'b1;                                  // someone in the room
        set_temp(284);  measure_duty(d); check(d == 0,              "T3 28.4 C (<TH+0.5) fan OFF");
        set_temp(290);  measure_duty(d); check(d >= 45 && d <= 49,  "T3 29.0 C fan ON ~47 %");
        $display("        measured duty = %0d %%", d);
        set_temp(300);  measure_duty(d); check(d >= 63 && d <= 67,  "T3 30.0 C fan ~65 %");
        set_temp(320);  measure_duty(d); check(d == 100,            "T3 32.0 C fan 100 %");
        set_temp(276);  measure_duty(d); check(d >= 28 && d <= 32,  "T3 27.6 C hysteresis keeps fan ON (30 %)");
        set_temp(274);  measure_duty(d); check(d == 0,              "T3 27.4 C fan OFF");

        // ------------------------------------------------ T4 occupancy, light, ECO
        $display("\n==== T4 : occupancy timeout, lighting, ECO ====");
        send_cmd("OCC 5", 5);  expect_line("OK", 2, 20000, "T4 OCC 5 accepted");
        set_temp(300);
        sw[1] = 1'b1;                                  // dark
        wait_cycles(100);
        check(light_out == 1'b1, "T4 dark + motion -> light ON");
        sw[0] = 1'b0;                                  // person leaves
        wait_secs(3);
        check(light_out == 1'b1 && dut.occupied, "T4 light stays ON inside timeout (3 s)");
        wait_secs(3);
        check(light_out == 1'b0 && !dut.occupied, "T4 light OFF after 5 s empty");
        measure_duty(d); check(d == 0, "T4 ECO: hot but empty room -> fan OFF");
        send_cmd("ECO 0", 5);  expect_line("OK", 2, 20000, "T4 ECO 0 accepted");
        wait_cycles(50); measure_duty(d); check(d >= 63 && d <= 67, "T4 ECO off -> fan runs in empty room");
        send_cmd("ECO 1", 5);  expect_line("OK", 2, 20000, "T4 ECO 1 accepted");

        // ------------------------------------------------ T5 manual mode
        $display("\n==== T5 : manual control over UART ====");
        send_cmd("FAN 70", 6);   expect_line("OK", 2, 20000, "T5 FAN 70 -> OK");
        wait_cycles(50); measure_duty(d);
        check(dut.manual && d >= 68 && d <= 72, "T5 manual fan 70 %");
        send_cmd("light on", 8); expect_line("OK", 2, 20000, "T5 lower-case 'light on' -> OK");
        wait_cycles(20); check(light_out == 1'b1, "T5 manual light ON");
        send_cmd("MODE AUTO", 9); expect_line("OK", 2, 20000, "T5 MODE AUTO -> OK");
        wait_cycles(20); check(!dut.manual, "T5 back in AUTO mode");
        send_cmd("TH 26", 5);     expect_line("OK", 2, 20000, "T5 TH 26 -> OK");
        wait_cycles(5); check(dut.th == 26, "T5 threshold = 26");
        send_cmd("TH 28", 5);     expect_line("OK", 2, 20000, "T5 TH 28 -> OK");

        // ------------------------------------------------ T6 error handling
        $display("\n==== T6 : invalid commands ====");
        send_cmd("FOO", 3);        expect_line("ERR", 3, 20000, "T6 unknown keyword -> ERR");
        send_cmd("FAN 150", 7);    expect_line("ERR", 3, 20000, "T6 FAN 150 out of range -> ERR");
        send_cmd("TH 5", 4);       expect_line("ERR", 3, 20000, "T6 TH 5 out of range -> ERR");
        send_cmd("ARM 12", 6);     expect_line("ERR", 3, 20000, "T6 PIN must have 4 digits -> ERR");

        // ------------------------------------------------ T7 gas safety interlock
        $display("\n==== T7 : gas leak safety interlock ====");
        @(negedge clk); sw[2] = 1'b1; lat = 0;
        while (valve !== 1'b1) begin @(posedge clk); #1; lat = lat + 1; end
        $display("        gas input -> valve closed latency = %0d clock cycles (%0d ns)", lat, lat*10);
        check(lat <= 3, "T7 valve closes within 3 clock cycles");
        wait_cycles(5);
        check(fan_pwm == 1'b1 && siren == 1'b1, "T7 exhaust fan forced 100 % + siren ON");
        expect_line("EVT GAS_LEAK VALVE_CLOSED", 25, 20000, "T7 EVT GAS_LEAK reported");
        send_cmd("FAN 0", 5);      expect_line("OK", 2, 20000, "T7 FAN 0 accepted");
        wait_cycles(20); check(fan_pwm == 1'b1 && valve, "T7 user command cannot override emergency");
        check(dut.u_disp_ctrl.chars == {5'd16,5'd10,5'd5,5'd31,5'd10,5'd19,5'd23,5'd24} ||
              dut.u_disp_ctrl.chars == {8{5'd31}}, "T7 display shows blinking 'GAS ALrt'");
        send_cmd("ACK", 3);        expect_line("DENIED", 6, 20000, "T7 ACK refused while gas present");
        sw[2] = 1'b0;
        wait_secs(2);
        check(valve == 1'b1, "T7 stays latched after gas clears (slow reset)");
        expect_line("EVT GAS_CLEAR SEND_ACK", 22, 6*SEC, "T7 EVT GAS_CLEAR after 5 s");
        send_cmd("ACK", 3);        expect_line("OK", 2, 20000, "T7 ACK accepted");
        wait_cycles(10); check(valve == 1'b0 && siren == 1'b0, "T7 valve reopened, siren off");
        send_cmd("MODE AUTO", 9);  expect_line("OK", 2, 20000, "T7 MODE AUTO");

        // ------------------------------------------------ T8 security
        $display("\n==== T8 : security (arm, entry delay, intrusion) ====");
        sw[1] = 1'b0;
        send_cmd("ARM 1234", 8);   expect_line("OK", 2, 20000, "T8 ARM 1234 -> OK");
        wait_cycles(10); check(dut.sec_state == 3'd1, "T8 exit delay running");
        expect_line("EVT ARMED", 9, 11*SEC, "T8 EVT ARMED after 10 s exit delay");
        sw[3] = 1'b1; wait_cycles(100); sw[3] = 1'b0;              // door opened
        expect_line("EVT ENTRY_DELAY", 15, 20000, "T8 door open -> entry delay");
        send_cmd("DISARM 1111", 11); expect_line("DENIED", 6, 20000, "T8 wrong PIN -> DENIED");
        send_cmd("DISARM 1234", 11); expect_line("OK", 2, 20000, "T8 correct PIN -> OK");
        expect_line("EVT DISARMED", 12, 20000, "T8 EVT DISARMED");

        // arm with BTNC, then motion without door -> immediate intrusion
        btnc = 1'b1; wait_cycles(100); btnc = 1'b0;
        wait_cycles(10); check(dut.sec_state == 3'd1, "T8 BTNC starts exit delay");
        expect_line("EVT ARMED", 9, 11*SEC, "T8 armed by button");
        sw[0] = 1'b1; wait_cycles(100); sw[0] = 1'b0;
        expect_line("EVT INTRUSION", 13, 20000, "T8 motion while armed -> INTRUSION");
        check(siren && light_out, "T8 siren ON + panic lighting ON");
        send_cmd("DISARM 1234", 11); expect_line("OK", 2, 20000, "T8 disarm alarm");
        wait_cycles(30); check(!siren, "T8 siren OFF after disarm");

        // entry-delay timeout
        send_cmd("ARM 1234", 8);   expect_line("OK", 2, 20000, "T8 re-arm");
        expect_line("EVT ARMED", 9, 11*SEC, "T8 armed again");
        sw[3] = 1'b1; wait_cycles(100); sw[3] = 1'b0;
        expect_line("EVT ENTRY_DELAY", 15, 20000, "T8 entry delay started");
        expect_line("EVT INTRUSION", 13, 16*SEC, "T8 no PIN within 15 s -> INTRUSION");
        send_cmd("DISARM 1234", 11); expect_line("OK", 2, 20000, "T8 disarm");

        // ------------------------------------------------ T9 lockout / PIN change
        $display("\n==== T9 : PIN lockout and PIN change ====");
        send_cmd("DISARM 0000", 11); expect_line("DENIED", 6, 20000, "T9 wrong PIN 1");
        send_cmd("DISARM 0001", 11); expect_line("DENIED", 6, 20000, "T9 wrong PIN 2");
        send_cmd("DISARM 0002", 11); expect_line("EVT LOCKOUT", 11, 20000, "T9 3rd wrong PIN -> EVT LOCKOUT");
        send_cmd("DISARM 1234", 11); expect_line("LOCKED", 6, 20000, "T9 even correct PIN refused while locked");
        wait_secs(31);
        send_cmd("PIN 1234 4321", 13); expect_line("OK", 2, 20000, "T9 PIN changed after lockout expires");
        send_cmd("ARM 1234", 8);   expect_line("DENIED", 6, 20000, "T9 old PIN rejected");
        send_cmd("ARM 4321", 8);   expect_line("OK", 2, 20000, "T9 new PIN accepted");
        send_cmd("DISARM 4321", 11); expect_line("OK", 2, 20000, "T9 disarm with new PIN");
        expect_line("EVT DISARMED", 12, 20000, "T9 disarmed");

        // ------------------------------------------------ T10 learning
        $display("\n==== T10 : on-chip occupancy learning (5 simulated days) ====");
        set_temp(250);
        send_cmd("CLEAR", 5);      expect_line("OK", 2, 20000, "T10 learned profile cleared");
        send_cmd("TIME 0 0", 8);   expect_line("OK", 2, 20000, "T10 time set 00:00");
        send_cmd("FAST 1", 6);     expect_line("OK", 2, 20000, "T10 fast time on (1 h = 1 s)");
        pattern_en = 1'b1;                         // at home 07-09 h and 18-22 h
        wait (dut.days == 8'd3);
        $display("        3 days learned, trained = %0d", dut.trained);
        check(dut.trained, "T10 model trained after 3 days");
        wait (dut.days == 8'd4);
        pattern_en = 1'b0; sw[0] = 1'b0;
        check(dut.u_learn.score[8] == 8'd174 && dut.u_learn.score[20] == 8'd174,
              "T10 busy hours learned: score = 174 after 4 days");
        check(dut.u_learn.score[3] == 8'd0 && dut.u_learn.score[13] == 8'd0,
              "T10 empty hours stay 0");

        // day 5, 03:xx -> unusual motion
        wait (dut.hh == 5'd3); wait_cycles(2000);
        sw[0] = 1'b1; wait_cycles(200); sw[0] = 1'b0;
        expect_line("EVT ANOMALY H=03", 16, 20000, "T10 motion at 03 h -> EVT ANOMALY");
        check(led[10], "T10 warning LED latched");
        // 07:00-08:00 normally busy, now empty -> inactivity
        expect_line("EVT INACTIVITY H=07", 19, 6*SEC, "T10 no activity in busy hour 07 -> EVT INACTIVITY");

        // prediction / pre-cooling (nobody home, eco on)
        set_temp(300);
        wait (dut.hh == 5'd12); wait_cycles(2000);
        measure_duty(d); check(!dut.predicted && d == 0, "T10 12 h: not predicted -> fan OFF (energy saved)");
        wait (dut.hh == 5'd17); wait_cycles(2000);
        measure_duty(d); check(dut.predicted && d >= 63 && d <= 67,
                               "T10 17 h: arrival predicted at 18 h -> pre-cooling fan ON");
        send_cmd("PROFILE", 7);
        expect_sub(" 20=174", 7, 60000, "T10 PROFILE shows learned busy hour 20 = 174");
        check(has_sub(" 07=131", 7) && has_sub(" 03=063", 7), "T10 PROFILE shows 07=131 and 03=063");
        send_cmd("FAST 0", 6);     expect_line("OK", 2, 20000, "T10 fast time off");
        btnr = 1'b1; wait_cycles(100); btnr = 1'b0; wait_cycles(10);
        check(!led[10], "T10 BTNR clears warning");

        // ------------------------------------------------ T11 sensor fault
        $display("\n==== T11 : temperature sensor failure ====");
        sensor.present = 1'b0;
        expect_line("EVT SENSOR_FAULT", 16, 10000, "T11 sensor NACK -> EVT SENSOR_FAULT");
        wait_cycles(20); measure_duty(d); check(d == 50, "T11 fail-safe fan 50 %");
        sensor.present = 1'b1;
        wait_cycles(8000); check(!dut.fault, "T11 fault clears when sensor answers");

        // ------------------------------------------------ T12 energy + status
        $display("\n==== T12 : energy report and status ====");
        send_cmd("ENERGY", 6);
        expect_line("ENERGY FAN=", 11, 40000, "T12 ENERGY report");
        check(llen == 44 && has_sub("Wh LIGHT=", 9), "T12 ENERGY line format");
        send_cmd("STATUS", 6);
        expect_sub("SEC=DISARMED", 12, 40000, "T12 STATUS line");

        // ------------------------------------------------ T13 neural network (AI)
        $display("\n==== T13 : on-chip neural network occupancy detection ====");
        send_cmd("AI 237 263 585 749", 18);
        expect_line("AI OCC=1 P=", 11, 20000, "T13 real occupied sample -> AI OCC=1");
        send_cmd("AI 224 250 0 806", 16);
        expect_line("AI OCC=0 P=", 11, 20000, "T13 real empty sample -> AI OCC=0");
        send_cmd("AI 1 2 3", 8);
        expect_line("ERR", 3, 20000, "T13 AI needs 4 values -> ERR");
        sw[0] = 1'b0; sw[1] = 1'b1;                      // dark, no PIR motion
        set_temp(237);
        send_cmd("ENV 263 585 749", 15);  expect_line("OK", 2, 20000, "T13 ENV (live mode) accepted");
        wait_secs(2);
        check(dut.ai_live && dut.ai_occ && dut.occupied && light_out,
              "T13 live AI detects occupancy without PIR -> light ON");
        send_cmd("STATUS", 6);
        expect_sub("AI=1 P=", 7, 40000, "T13 STATUS shows AI=1");
        send_cmd("OCC 5", 5);             expect_line("OK", 2, 20000, "T13 OCC 5");
        send_cmd("ENV 263 0 450", 13);    expect_line("OK", 2, 20000, "T13 ENV empty-room values");
        wait_secs(7);
        check(dut.ai_live && !dut.ai_occ && !dut.occupied && !light_out,
              "T13 live AI: empty room -> not occupied, light OFF");

        // ------------------------------------------------ summary
        $display("\n==================================================");
        $display(" TOTAL CHECKS : %0d   FAILED : %0d", checks, errors);
        if (errors == 0) $display(" RESULT       : ALL TESTS PASSED");
        else             $display(" RESULT       : FAILURES PRESENT");
        $display("==================================================\n");
        $finish;
    end

    // watchdog
    initial begin
        #1_500_000_000;
        $display("TIMEOUT"); $finish;
    end
endmodule
