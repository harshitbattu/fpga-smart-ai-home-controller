`timescale 1ns / 1ps
// ============================================================================
// security_fsm : intrusion alarm with PIN, exit/entry delays and lockout
//   DISARMED --ARM pin / BTNC--> EXIT --(EXIT_SECS)--> ARMED
//   ARMED  --door open--> ENTRY --(ENTRY_SECS, no PIN)--> ALARM
//   ARMED  --motion (no door)------------------------------> ALARM
//   any state --DISARM correct pin--> DISARMED
//   MAX_FAILS wrong PINs -> LOCKOUT for LOCK_SECS (all PIN commands refused)
// ============================================================================
module security_fsm #(
    parameter integer EXIT_SECS   = 10,
    parameter integer ENTRY_SECS  = 15,
    parameter integer LOCK_SECS   = 30,
    parameter integer MAX_FAILS   = 3,
    parameter [13:0]  DEFAULT_PIN = 14'd1234
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_1s,
    input  wire        motion,
    input  wire        door_open,
    input  wire        btn_arm,
    input  wire        cmd_valid,
    input  wire [4:0]  cmd,
    input  wire [13:0] arg0,
    input  wire [13:0] arg1,
    output reg  [2:0]  state,
    output reg  [5:0]  secs_left,
    output reg         locked,
    output reg  [5:0]  lock_left,
    output reg         rsp_valid,
    output reg  [2:0]  rsp_code,
    output reg         evt_armed,
    output reg         evt_disarmed,
    output reg         evt_entry,
    output reg         evt_intrusion,
    output reg         evt_lockout
);
    `include "home_defs.vh"

    reg [13:0] pin;
    reg [1:0]  fails;

    wire pin_ok  = (arg0 == pin);
    wire sec_cmd = cmd_valid && (cmd == CMD_ARM || cmd == CMD_DISARM || cmd == CMD_PIN);

    always @(posedge clk) begin
        if (rst) begin
            state <= SEC_DISARMED; secs_left <= 6'd0; locked <= 1'b0; lock_left <= 6'd0;
            pin <= DEFAULT_PIN; fails <= 2'd0;
            rsp_valid <= 1'b0; rsp_code <= RSP_NONE;
            evt_armed <= 1'b0; evt_disarmed <= 1'b0; evt_entry <= 1'b0;
            evt_intrusion <= 1'b0; evt_lockout <= 1'b0;
        end else begin
            rsp_valid <= 1'b0;
            evt_armed <= 1'b0; evt_disarmed <= 1'b0; evt_entry <= 1'b0;
            evt_intrusion <= 1'b0; evt_lockout <= 1'b0;

            // ---- 1 s timers ----
            if (tick_1s) begin
                if (locked) begin
                    if (lock_left <= 6'd1) begin locked <= 1'b0; lock_left <= 6'd0; fails <= 2'd0; end
                    else lock_left <= lock_left - 1'b1;
                end
                if ((state == SEC_EXIT || state == SEC_ENTRY) && secs_left != 0)
                    secs_left <= secs_left - 1'b1;
            end

            // ---- automatic transitions ----
            case (state)
                SEC_EXIT:  if (secs_left == 0) begin state <= SEC_ARMED; evt_armed <= 1'b1; end
                SEC_ARMED: if (door_open) begin
                               state <= SEC_ENTRY; secs_left <= ENTRY_SECS; evt_entry <= 1'b1;
                           end else if (motion) begin
                               state <= SEC_ALARM; evt_intrusion <= 1'b1;
                           end
                SEC_ENTRY: if (secs_left == 0) begin state <= SEC_ALARM; evt_intrusion <= 1'b1; end
                default: ;
            endcase

            // ---- local arm button (no PIN needed to arm) ----
            if (btn_arm && state == SEC_DISARMED) begin
                state <= SEC_EXIT; secs_left <= EXIT_SECS;
            end

            // ---- PIN-protected commands (highest priority) ----
            if (sec_cmd) begin
                rsp_valid <= 1'b1;
                if (locked) begin
                    rsp_code <= RSP_LOCKED;
                end else if (!pin_ok) begin
                    if (fails == MAX_FAILS - 1) begin
                        locked <= 1'b1; lock_left <= LOCK_SECS; evt_lockout <= 1'b1;
                        rsp_code <= RSP_LOCKED;
                    end else begin
                        fails <= fails + 1'b1;
                        rsp_code <= RSP_DENIED;
                    end
                end else begin
                    fails <= 2'd0;
                    case (cmd)
                        CMD_ARM: begin
                            rsp_code <= RSP_OK;
                            if (state == SEC_DISARMED) begin state <= SEC_EXIT; secs_left <= EXIT_SECS; end
                        end
                        CMD_DISARM: begin
                            rsp_code <= RSP_OK;
                            if (state != SEC_DISARMED) evt_disarmed <= 1'b1;
                            state <= SEC_DISARMED; secs_left <= 6'd0;
                        end
                        default: begin    // CMD_PIN : change PIN, only while disarmed
                            if (state == SEC_DISARMED) begin pin <= arg1; rsp_code <= RSP_OK; end
                            else rsp_code <= RSP_DENIED;
                        end
                    endcase
                end
            end
        end
    end
endmodule
