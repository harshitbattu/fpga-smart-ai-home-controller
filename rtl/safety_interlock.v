`timescale 1ns / 1ps
// ============================================================================
// safety_interlock : gas / smoke emergency path (highest priority)
//   * independent of the command parser, security FSM and learner:
//     no other module can delay or block it
//   * FAST TRIP : emergency asserts 2 clock cycles after the gas input
//                 (2-FF synchronizer only, no debounce = fail-safe)
//   * SLOW RESET: stays latched until gas has been absent for CLEAR_SECS
//                 AND the user acknowledges (ACK command or BTNR)
//   * outputs   : valve_close (gas solenoid), used by top to force the
//                 exhaust fan to 100 % and sound the siren
// ============================================================================
module safety_interlock #(
    parameter integer CLEAR_SECS = 5
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       gas_in,        // asynchronous, active high
    input  wire       tick_1s,
    input  wire       ack,           // ACK command or button (pulse)
    input  wire       ack_is_cmd,    // 1 = ack came from UART (needs a reply)
    output wire       gas_now,
    output wire       emergency,
    output wire       valve_close,
    output reg        rsp_valid,
    output reg  [2:0] rsp_code,
    output reg        evt_trip,
    output reg        evt_clear
);
    `include "home_defs.vh"

    reg g0, g1;                      // synchronizer
    reg latched;
    reg [7:0] clear_cnt;
    reg emerg_d;

    assign gas_now     = g1;
    assign emergency   = latched | g1;
    assign valve_close = emergency;

    wire can_clear = latched && !g1 && (clear_cnt >= CLEAR_SECS);

    always @(posedge clk) begin
        if (rst) begin
            g0 <= 1'b0; g1 <= 1'b0; latched <= 1'b0; clear_cnt <= 8'd0; emerg_d <= 1'b0;
            rsp_valid <= 1'b0; rsp_code <= RSP_NONE; evt_trip <= 1'b0; evt_clear <= 1'b0;
        end else begin
            g0 <= gas_in;
            g1 <= g0;
            emerg_d   <= emergency;
            rsp_valid <= 1'b0;
            evt_trip  <= emergency & ~emerg_d;
            evt_clear <= 1'b0;

            if (g1) begin
                latched   <= 1'b1;
                clear_cnt <= 8'd0;
            end else if (latched && tick_1s && clear_cnt < CLEAR_SECS) begin
                clear_cnt <= clear_cnt + 1'b1;
                if (clear_cnt == CLEAR_SECS - 1) evt_clear <= 1'b1;   // gas gone long enough
            end

            if (ack) begin
                if (can_clear) latched <= 1'b0;
                if (ack_is_cmd) begin
                    rsp_valid <= 1'b1;
                    rsp_code  <= (!latched || can_clear) ? RSP_OK : RSP_DENIED;
                end
            end
        end
    end
endmodule
