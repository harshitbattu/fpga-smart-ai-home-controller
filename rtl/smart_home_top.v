`timescale 1ns / 1ps
// ============================================================================
// smart_home_top : FPGA Smart AI Home Controller  (Nexys 4 DDR, Artix-7)
//
//   AI           : on-chip neural network (MLP 4-8-1) for occupancy detection
//   Sensors      : ADT7420 on-board temperature sensor (I2C)
//                  PIR motion, LDR darkness, MQ-2 gas, door reed switch
//                  (Pmod JA, enabled by SW14; SW0..SW3 simulate them)
//   User inputs  : USB-UART commands (115200 8-N-1), push buttons
//   Actuators    : Pmod JB  fan PWM (25 kHz), light relay, siren, gas valve
//                  audio jack siren, 7-segment display, LEDs, RGB LEDs
//
//   Switches : SW0 motion  SW1 dark  SW2 gas  SW3 door open
//              SW12 fast-time demo  SW13 mute siren  SW14 use Pmod JA sensors
//   Buttons  : BTNC arm  BTNU/BTND threshold +/-  BTNL display page
//              BTNR acknowledge (gas emergency / learner warnings)
//              CPU_RESET reset
// ============================================================================
module smart_home_top #(
    parameter integer CLK_HZ       = 100_000_000,
    parameter integer SEC_DIV      = 100_000_000,   // clock cycles per second
    parameter integer CLKS_PER_BIT = 868,           // 115200 baud
    parameter integer DB_CYCLES    = 1_000_000,     // 10 ms debounce
    parameter integer I2C_QDIV     = 250,           // 100 kHz SCL
    parameter integer TEMP_POLL    = 25_000_000,    // 250 ms
    parameter integer PWM_PERIOD   = 4000,          // 25 kHz fan PWM
    parameter integer REFRESH_BITS = 17,
    parameter integer EXIT_SECS    = 10,
    parameter integer ENTRY_SECS   = 15,
    parameter integer LOCK_SECS    = 30,
    parameter integer GAS_CLEAR_S  = 5,
    parameter         LDR_ACTIVE_HIGH = 1           // Pmod LDR module: 1 = DO high when dark
)(
    input  wire        clk,
    input  wire        cpu_resetn,
    input  wire [15:0] sw,
    input  wire        btnc,
    input  wire        btnu,
    input  wire        btnd,
    input  wire        btnl,
    input  wire        btnr,
    output wire [15:0] led,
    output wire        led16_r, led16_g, led16_b,
    output wire        led17_r, led17_g, led17_b,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [7:0]  an,
    input  wire        uart_rxd,        // PC -> FPGA
    output wire        uart_txd,        // FPGA -> PC
    inout  wire        tmp_scl,
    inout  wire        tmp_sda,
    input  wire [3:0]  ja,              // JA1 PIR, JA2 LDR DO, JA3 MQ-2 DO (active low), JA4 door reed
    output wire [3:0]  jb,              // JB1 fan PWM, JB2 light, JB3 siren/buzzer, JB4 gas valve
    output wire        aud_pwm,
    output wire        aud_sd
);
    `include "home_defs.vh"

    // ------------------------------------------------------------------
    // Reset: power-on + CPU_RESET button, synchronised to clk
    // ------------------------------------------------------------------
    reg [3:0] rst_sh = 4'hF;
    always @(posedge clk) rst_sh <= {rst_sh[2:0], ~cpu_resetn};
    wire rst = rst_sh[3];

    // ------------------------------------------------------------------
    // Sensor selection (switch simulation OR external Pmod sensors)
    // ------------------------------------------------------------------
    wire ext_en    = sw[14];
    wire motion_in = sw[0] | (ext_en &  ja[0]);
    wire dark_in   = sw[1] | (ext_en & (LDR_ACTIVE_HIGH ? ja[1] : ~ja[1]));
    wire gas_in    = sw[2] | (ext_en & ~ja[2]);
    wire door_in   = sw[3] | (ext_en &  ja[3]);
    wire mute      = sw[13];

    wire motion, dark, door_open, fast_sw;
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_mot  (.clk(clk), .rst(rst), .din(motion_in), .dout(motion),    .rise(), .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_dark (.clk(clk), .rst(rst), .din(dark_in),   .dout(dark),      .rise(), .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_door (.clk(clk), .rst(rst), .din(door_in),   .dout(door_open), .rise(), .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_fast (.clk(clk), .rst(rst), .din(sw[12]),    .dout(fast_sw),   .rise(), .fall());

    wire b_arm, b_up, b_dn, b_page, b_ack;
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_bc (.clk(clk), .rst(rst), .din(btnc), .dout(), .rise(b_arm),  .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_bu (.clk(clk), .rst(rst), .din(btnu), .dout(), .rise(b_up),   .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_bd (.clk(clk), .rst(rst), .din(btnd), .dout(), .rise(b_dn),   .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_bl (.clk(clk), .rst(rst), .din(btnl), .dout(), .rise(b_page), .fall());
    sync_debounce #(.CYCLES(DB_CYCLES)) u_db_br (.clk(clk), .rst(rst), .din(btnr), .dout(), .rise(b_ack),  .fall());

    // ------------------------------------------------------------------
    // UART receive + command parser
    // ------------------------------------------------------------------
    wire [7:0]  rx_data;
    wire        rx_valid;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_rxd), .data(rx_data), .valid(rx_valid), .frame_err());

    wire        cmd_valid;
    wire [4:0]  cmd;
    wire [13:0] arg0, arg1, arg2, arg3;
    wire        p_rsp_valid;
    wire [2:0]  p_rsp_code;
    cmd_parser u_parser (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .cmd_valid(cmd_valid), .cmd(cmd), .arg0(arg0), .arg1(arg1), .arg2(arg2), .arg3(arg3),
        .rsp_valid(p_rsp_valid), .rsp_code(p_rsp_code));

    // ------------------------------------------------------------------
    // Time base
    // ------------------------------------------------------------------
    wire       fast_cmd, set_time;
    wire [4:0] set_hh;
    wire [5:0] set_mm;
    wire       tick_1s, tick_e, hour_tick;
    wire [4:0] hh, end_hh;
    wire [5:0] mm;
    timebase #(.SEC_DIV(SEC_DIV)) u_time (
        .clk(clk), .rst(rst), .fast(fast_cmd | fast_sw),
        .set_time(set_time), .set_hh(set_hh), .set_mm(set_mm),
        .tick_1s(tick_1s), .tick_e(tick_e), .hh(hh), .mm(mm),
        .hour_tick(hour_tick), .end_hh(end_hh));

    // ------------------------------------------------------------------
    // Temperature sensor (ADT7420 over I2C)
    // ------------------------------------------------------------------
    wire               sda_oe, scl_oe;
    wire signed [12:0] temp_raw;
    wire               temp_valid, i2c_fault;
    assign tmp_sda = sda_oe ? 1'b0 : 1'bz;
    assign tmp_scl = scl_oe ? 1'b0 : 1'bz;
    adt7420_reader #(.QDIV(I2C_QDIV), .POLL_CYCLES(TEMP_POLL)) u_temp (
        .clk(clk), .rst(rst), .sda_in(tmp_sda), .sda_oe(sda_oe), .scl_oe(scl_oe),
        .temp_raw(temp_raw), .valid(temp_valid), .fault(i2c_fault));

    reg temp_ok;
    always @(posedge clk) begin
        if (rst) temp_ok <= 1'b0;
        else if (temp_valid) temp_ok <= 1'b1;
    end
    // sensor fault: no I2C acknowledge, or implausible reading
    wire implausible = temp_ok && ((temp_raw > 13'sd1360) || (temp_raw < -13'sd320));  // >85 C or <-20 C
    wire fault = i2c_fault | implausible;
    reg  fault_d;
    always @(posedge clk) fault_d <= rst ? 1'b0 : fault;
    wire ev_fault = fault & ~fault_d;

    // ------------------------------------------------------------------
    // Gas / smoke safety interlock (independent hardware path)
    // ------------------------------------------------------------------
    wire gas_now, emergency, valve_close;
    wire s_rsp_valid, ev_gas, ev_gas_clear;
    wire [2:0] s_rsp_code;
    wire ack_cmd = cmd_valid && (cmd == CMD_ACK);
    safety_interlock #(.CLEAR_SECS(GAS_CLEAR_S)) u_safety (
        .clk(clk), .rst(rst), .gas_in(gas_in), .tick_1s(tick_1s),
        .ack(ack_cmd | b_ack), .ack_is_cmd(ack_cmd),
        .gas_now(gas_now), .emergency(emergency), .valve_close(valve_close),
        .rsp_valid(s_rsp_valid), .rsp_code(s_rsp_code),
        .evt_trip(ev_gas), .evt_clear(ev_gas_clear));

    // ------------------------------------------------------------------
    // Security FSM
    // ------------------------------------------------------------------
    wire [2:0] sec_state;
    wire [5:0] secs_left, lock_left;
    wire       locked;
    wire       k_rsp_valid;
    wire [2:0] k_rsp_code;
    wire       ev_armed, ev_disarmed, ev_entry, ev_intr, ev_lock;
    security_fsm #(.EXIT_SECS(EXIT_SECS), .ENTRY_SECS(ENTRY_SECS), .LOCK_SECS(LOCK_SECS)) u_sec (
        .clk(clk), .rst(rst), .tick_1s(tick_1s), .motion(motion), .door_open(door_open),
        .btn_arm(b_arm), .cmd_valid(cmd_valid), .cmd(cmd), .arg0(arg0), .arg1(arg1),
        .state(sec_state), .secs_left(secs_left), .locked(locked), .lock_left(lock_left),
        .rsp_valid(k_rsp_valid), .rsp_code(k_rsp_code),
        .evt_armed(ev_armed), .evt_disarmed(ev_disarmed), .evt_entry(ev_entry),
        .evt_intrusion(ev_intr), .evt_lockout(ev_lock));
    wire alarm_active = (sec_state == SEC_ALARM);

    // ------------------------------------------------------------------
    // Occupancy learner (on-chip adaptive model)
    // ------------------------------------------------------------------
    wire [191:0] profile;
    wire [7:0]   cur_score, days;
    wire         trained, predicted, ev_anom, ev_inact;
    wire [4:0]   ev_hh;
    occupancy_learner u_learn (
        .clk(clk), .rst(rst), .motion(motion), .cur_hh(hh),
        .hour_tick(hour_tick), .end_hh(end_hh),
        .clear(cmd_valid && cmd == CMD_CLEAR), .alerts_en(sec_state == SEC_DISARMED),
        .profile(profile), .cur_score(cur_score), .days(days),
        .trained(trained), .predicted(predicted),
        .evt_anomaly(ev_anom), .evt_inactive(ev_inact), .evt_hh(ev_hh));

    // learner warnings latch until acknowledged
    reg warn;
    always @(posedge clk) begin
        if (rst) warn <= 1'b0;
        else if (ev_anom || ev_inact) warn <= 1'b1;
        else if (ack_cmd || b_ack) warn <= 1'b0;
    end

    // ------------------------------------------------------------------
    // AI: neural-network occupancy detection (MLP 4-8-1, 8-bit, on-chip)
    // ------------------------------------------------------------------
    wire       ai_live, ai_occ, ev_ai, ev_ai_occ;
    wire [6:0] ai_prob, ev_ai_prob;
    ai_unit u_ai (
        .clk(clk), .rst(rst), .tick_1s(tick_1s),
        .cmd_valid(cmd_valid), .cmd(cmd), .arg0(arg0), .arg1(arg1), .arg2(arg2), .arg3(arg3),
        .temp_raw(temp_raw), .temp_ok(temp_ok),
        .live_en(ai_live), .ai_occ(ai_occ), .ai_prob(ai_prob),
        .ev_ai(ev_ai), .ev_occ(ev_ai_occ), .ev_prob(ev_ai_prob));

    // ------------------------------------------------------------------
    // Mode / settings / occupancy / lighting
    // ------------------------------------------------------------------
    wire        manual, manual_light, eco, occupied, light_out;
    wire [6:0]  manual_duty;
    wire [5:0]  th;
    wire [11:0] occ_timeout;
    control_unit u_ctrl (
        .clk(clk), .rst(rst), .tick_1s(tick_1s),
        .cmd_valid(cmd_valid), .cmd(cmd), .arg0(arg0), .arg1(arg1),
        .btn_up(b_up), .btn_down(b_dn), .motion(motion), .dark(dark),
        .alarm_active(alarm_active), .ai_occ(ai_live & ai_occ),
        .manual(manual), .manual_duty(manual_duty), .manual_light(manual_light),
        .th(th), .occ_timeout(occ_timeout), .eco(eco), .fast(fast_cmd),
        .set_time(set_time), .set_hh(set_hh), .set_mm(set_mm),
        .occupied(occupied), .light_out(light_out));

    // ------------------------------------------------------------------
    // Climate (fan) control + PWM
    // ------------------------------------------------------------------
    wire [6:0] duty;
    wire       hot;
    climate_ctrl u_climate (
        .clk(clk), .rst(rst), .temp(temp_raw), .temp_ok(temp_ok), .fault(fault),
        .th(th), .manual(manual), .manual_duty(manual_duty),
        .occupied(occupied), .predicted(predicted), .eco(eco), .emergency(emergency),
        .duty(duty), .hot(hot));

    wire fan_pwm_raw;
    pwm_gen #(.PERIOD(PWM_PERIOD)) u_pwm (.clk(clk), .rst(rst), .duty(duty), .pwm(fan_pwm_raw));
    // safety override: fan forced fully ON the moment the interlock trips
    wire fan_pwm = fan_pwm_raw | emergency;

    // ------------------------------------------------------------------
    // Energy meter
    // ------------------------------------------------------------------
    wire [39:0] fan_acc, light_acc;
    energy_meter u_energy (
        .clk(clk), .rst(rst), .tick_e(tick_e), .fan_duty(duty), .light_on(light_out),
        .fan_acc(fan_acc), .light_acc(light_acc));

    // ------------------------------------------------------------------
    // Telemetry / replies over UART TX
    // ------------------------------------------------------------------
    wire       rsp_valid = p_rsp_valid | k_rsp_valid | s_rsp_valid;
    wire [2:0] rsp_code  = p_rsp_valid ? p_rsp_code : k_rsp_valid ? k_rsp_code : s_rsp_code;
    wire [7:0] tx_data;
    wire       tx_start, tx_busy;
    telemetry_tx u_tel (
        .clk(clk), .rst(rst), .tx_busy(tx_busy), .tx_data(tx_data), .tx_start(tx_start),
        .rsp_valid(rsp_valid), .rsp_code(rsp_code),
        .ev_gas(ev_gas), .ev_gas_clear(ev_gas_clear), .ev_intr(ev_intr), .ev_entry(ev_entry),
        .ev_armed(ev_armed), .ev_disarmed(ev_disarmed), .ev_lock(ev_lock),
        .ev_anom(ev_anom), .ev_inact(ev_inact), .ev_hh(ev_hh), .ev_fault(ev_fault),
        .ev_ai(ev_ai), .ev_ai_occ(ev_ai_occ), .ev_ai_prob(ev_ai_prob),
        .temp(temp_raw), .temp_ok(temp_ok), .fault(fault), .th(th), .duty(duty),
        .light(light_out), .manual(manual), .eco(eco), .sec_state(sec_state),
        .emergency(emergency), .occupied(occupied), .predicted(predicted),
        .hh(hh), .mm(mm), .days(days), .profile(profile),
        .fan_acc(fan_acc), .light_acc(light_acc),
        .ai_live(ai_live), .ai_occ(ai_occ), .ai_prob(ai_prob));
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .data(tx_data), .start(tx_start), .tx(uart_txd), .busy(tx_busy));

    // ------------------------------------------------------------------
    // Siren
    // ------------------------------------------------------------------
    wire siren_on = emergency | alarm_active;
    wire tone;
    siren_gen #(.CLK_HZ(CLK_HZ)) u_siren (
        .clk(clk), .rst(rst), .alarm(siren_on),
        .chirp(sec_state == SEC_EXIT || sec_state == SEC_ENTRY), .tone(tone));
    assign aud_pwm = (tone & ~mute) ? 1'bz : 1'b0;   // open-drain style per Nexys 4 DDR manual
    assign aud_sd  = 1'b1;

    // ------------------------------------------------------------------
    // Display
    // ------------------------------------------------------------------
    reg [$clog2(CLK_HZ)-1:0] bl_cnt;
    reg blink;
    always @(posedge clk) begin
        if (rst) begin bl_cnt <= 0; blink <= 1'b0; end
        else if (bl_cnt == CLK_HZ/4 - 1) begin bl_cnt <= 0; blink <= ~blink; end
        else bl_cnt <= bl_cnt + 1'b1;
    end

    wire [39:0] chars;
    wire [7:0]  dps;
    display_ctrl u_disp_ctrl (
        .clk(clk), .rst(rst), .page_btn(b_page), .blink(blink), .emergency(emergency),
        .sec_state(sec_state), .secs_left(secs_left), .locked(locked), .lock_left(lock_left),
        .temp(temp_raw), .temp_ok(temp_ok), .hh(hh), .mm(mm), .duty(duty), .th(th),
        .cur_score(cur_score), .days(days), .ai_live(ai_live), .ai_occ(ai_occ), .ai_prob(ai_prob),
        .chars(chars), .dps(dps));
    seg7_mux #(.REFRESH_BITS(REFRESH_BITS)) u_seg (
        .clk(clk), .rst(rst), .chars(chars), .dps(dps), .seg(seg), .dp(dp), .an(an));

    // ------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------
    assign jb[0] = fan_pwm;
    assign jb[1] = light_out;
    assign jb[2] = siren_on & ~mute;
    assign jb[3] = valve_close;

    assign led[0]  = motion;
    assign led[1]  = dark;
    assign led[2]  = gas_now;
    assign led[3]  = door_open;
    assign led[4]  = light_out;
    assign led[5]  = (duty != 7'd0);
    assign led[6]  = manual;
    assign led[7]  = (sec_state != SEC_DISARMED);
    assign led[8]  = alarm_active;
    assign led[9]  = valve_close;
    assign led[10] = warn;
    assign led[11] = fault;
    assign led[12] = predicted;
    assign led[13] = occupied;
    assign led[14] = trained;
    assign led[15] = fast_cmd | fast_sw;

    // RGB LEDs are very bright: drive at 1/16 duty
    reg [3:0] dim_cnt = 4'd0;
    always @(posedge clk) dim_cnt <= dim_cnt + 1'b1;
    wire dim = (dim_cnt == 4'd0);
    wire st_red    = (emergency | alarm_active) & blink;
    wire st_yellow = ~(emergency | alarm_active) &
                     (warn | fault | locked | sec_state == SEC_EXIT | sec_state == SEC_ENTRY);
    wire st_green  = ~(emergency | alarm_active) & ~st_yellow;
    assign led16_r = dim & (st_red | st_yellow);
    assign led16_g = dim & (st_yellow | st_green);
    assign led16_b = 1'b0;
    assign led17_r = 1'b0;
    assign led17_g = dim & ai_live & ai_occ;       // neural network says: occupied
    assign led17_b = dim & fan_pwm;          // brightness follows fan speed
endmodule
