`timescale 1ns / 1ps
// ============================================================================
// telemetry_tx : ASCII replies and event messages on the UART transmitter
//   * events and command replies are queued as "pending" flags and sent in
//     priority order: banner, gas, intrusion, command reply, other events
//     -> nothing is lost when several things happen at the same time
//   * every message has a fixed layout; characters come from a generated
//     look-up table (msg_rom.vh) indexed by message kind and position
//   * the status fields are captured once per message (consistent snapshot)
//   * ENERGY values are converted to decimal with a sequential double-dabble
// ============================================================================
module telemetry_tx (
    input  wire               clk,
    input  wire               rst,
    // UART transmitter handshake
    input  wire               tx_busy,
    output reg  [7:0]         tx_data,
    output reg                tx_start,
    // replies
    input  wire               rsp_valid,
    input  wire [2:0]         rsp_code,
    // events (single-cycle pulses)
    input  wire               ev_gas,
    input  wire               ev_gas_clear,
    input  wire               ev_intr,
    input  wire               ev_entry,
    input  wire               ev_armed,
    input  wire               ev_disarmed,
    input  wire               ev_lock,
    input  wire               ev_anom,
    input  wire               ev_inact,
    input  wire [4:0]         ev_hh,
    input  wire               ev_fault,
    input  wire               ev_ai,          // neural-network one-shot result
    input  wire               ev_ai_occ,
    input  wire [6:0]         ev_ai_prob,
    // live status
    input  wire signed [12:0] temp,
    input  wire               temp_ok,
    input  wire               fault,
    input  wire [5:0]         th,
    input  wire [6:0]         duty,
    input  wire               light,
    input  wire               manual,
    input  wire               eco,
    input  wire [2:0]         sec_state,
    input  wire               emergency,
    input  wire               occupied,
    input  wire               predicted,
    input  wire [4:0]         hh,
    input  wire [5:0]         mm,
    input  wire [7:0]         days,
    input  wire [191:0]       profile,
    input  wire [39:0]        fan_acc,
    input  wire [39:0]        light_acc,
    input  wire               ai_live,        // live neural-network status
    input  wire               ai_occ,
    input  wire [6:0]         ai_prob
);
    `include "home_defs.vh"

    // message kinds (0..10 = events, same order as the pending bits)
    localparam [4:0] K_READY = 5'd0,  K_GAS    = 5'd1,  K_INTR   = 5'd2,  K_GASCLR = 5'd3,
                     K_LOCK  = 5'd4,  K_ENTRY  = 5'd5,  K_ARMED  = 5'd6,  K_DISARM = 5'd7,
                     K_ANOM  = 5'd8,  K_INACT  = 5'd9,  K_FAULT  = 5'd10, K_OK     = 5'd11,
                     K_ERR   = 5'd12, K_DENIED = 5'd13, K_LOCKED = 5'd14, K_STATUS = 5'd15,
                     K_PROFILE = 5'd16, K_ENERGY = 5'd17, K_AI = 5'd18;
    localparam [3:0] P_RSP = 4'd11;                // pending bit of the command reply
    localparam [3:0] P_AI  = 4'd12;                // pending bit of the AI reply

    localparam [2:0] T_IDLE = 3'd0, T_CONV1 = 3'd1, T_CONV2 = 3'd2, T_CAPT = 3'd3,
                     T_SEND = 3'd4, T_WAITB = 3'd5, T_WAITD = 3'd6, T_PREP = 3'd7;

    reg [12:0] pend;
    reg [2:0]  rsp_q;
    reg [4:0]  anom_hh, inact_hh;
    reg [4:0]  kind;
    reg [2:0]  st;
    reg [7:0]  idx;
    reg [51:0] fan_bcd, light_bcd;

    // ---------------- BCD converter for energy ----------------
    reg         bcd_start;
    reg  [39:0] bcd_in;
    wire [51:0] bcd_out;
    wire        bcd_done;
    bin2bcd_seq #(.W(40), .D(13)) u_b2b (
        .clk(clk), .rst(rst), .start(bcd_start), .bin(bcd_in), .bcd(bcd_out), .done(bcd_done));

    // ---------------- pending messages / priority ----------------
    wire [12:0] set_mask = {ev_ai, rsp_valid, ev_fault, ev_inact, ev_anom, ev_disarmed, ev_armed,
                            ev_entry, ev_lock, ev_gas_clear, ev_intr, ev_gas, 1'b0};
    reg  [3:0]  sel;
    integer pi;
    always @(*) begin
        sel = 4'd0;
        if (pend[P_AI]) sel = P_AI;
        for (pi = 10; pi >= 0; pi = pi - 1)
            if (pend[pi]) sel = pi[3:0];
        if (pend[P_RSP] && pend[2:0] == 3'b000) sel = P_RSP;
    end

    function [4:0] rsp_kind;
        input [2:0] r;
        case (r)
            RSP_OK:      rsp_kind = K_OK;
            RSP_DENIED:  rsp_kind = K_DENIED;
            RSP_LOCKED:  rsp_kind = K_LOCKED;
            RSP_STATUS:  rsp_kind = K_STATUS;
            RSP_PROFILE: rsp_kind = K_PROFILE;
            RSP_ENERGY:  rsp_kind = K_ENERGY;
            default:     rsp_kind = K_ERR;
        endcase
    endfunction

    // ---------------- status snapshot (decimal digits) ----------------
    wire [12:0] tabs = temp[12] ? (~temp + 1'b1) : temp;
    wire [7:0]  tint = (tabs[12:4] > 9'd99) ? 8'd99 : {1'b0, tabs[10:4]};
    wire [7:0]  tfr  = ({4'd0, tabs[3:0]} * 8'd10) >> 4;

    reg        c_tok, c_tneg, c_light, c_manual, c_eco, c_gas, c_occ, c_pred, c_fault;
    reg        c_ail, c_aio, c_xo;          // AI: live enabled, live result, one-shot result
    reg [3:0]  c_ap_h, c_ap_t, c_ap_o, c_xp_h, c_xp_t, c_xp_o;
    reg        ev_ai_occ_q;
    reg [6:0]  ev_ai_prob_q;
    reg [2:0]  c_sec;
    reg [3:0]  c_tt, c_to, c_tf, c_th_t, c_th_o, c_du_h, c_du_t, c_du_o;
    reg [3:0]  c_hh_t, c_hh_o, c_mm_t, c_mm_o, c_dy_h, c_dy_t, c_dy_o, c_ev_t, c_ev_o;

    // learned-profile slot selected by the character position (from msg_rom)
    reg  [4:0] pj, pj_r;               // pj from msg_rom, registered for timing
    reg        prep2;
    always @(posedge clk) pj_r <= pj;
    wire [7:0] ps   = profile[8*pj_r +: 8];
    `include "bcd_func.vh"
    // decimal digits, registered every clock (pipeline stage for 100 MHz timing)
    reg [11:0] ps_b, b_t, b_th, b_du, b_hh, b_mm, b_dy, b_an, b_in, b_ap, b_xp;
    reg [3:0]  tfr_r;
    wire [11:0] ps_bn = bcd8(ps),               b_tn  = bcd8(tint);
    wire [11:0] b_thn = bcd8({2'd0, th}),       b_dun = bcd8({1'b0, duty});
    wire [11:0] b_hhn = bcd8({3'd0, hh}),       b_mmn = bcd8({2'd0, mm});
    wire [11:0] b_dyn = bcd8(days);
    wire [11:0] b_ann = bcd8({3'd0, anom_hh}),  b_inn = bcd8({3'd0, inact_hh});
    wire [11:0] b_apn = bcd8({1'b0, ai_prob}),  b_xpn = bcd8({1'b0, ev_ai_prob_q});
    always @(posedge clk) begin
        ps_b <= ps_bn;  b_t  <= b_tn;  tfr_r <= tfr[3:0];
        b_th <= b_thn;  b_du <= b_dun; b_hh  <= b_hhn; b_mm <= b_mmn;
        b_dy <= b_dyn;  b_an <= b_ann; b_in  <= b_inn;
        b_ap <= b_apn;  b_xp <= b_xpn;
    end
    wire [3:0] ps_h = ps_b[11:8];
    wire [3:0] ps_t = ps_b[7:4];
    wire [3:0] ps_o = ps_b[3:0];

    function [7:0] asc;
        input [3:0] d;
        asc = 8'h30 + {4'd0, d};
    endfunction

    // ---------------- character look-up table ----------------
    reg [7:0] ch, len;
    wire      rom_ce = (st == T_PREP) && prep2;     // idx/kind stable for 2 cycles here
    `include "msg_rom.vh"

    // ---------------- sequencer ----------------
    always @(posedge clk) begin
        if (rst) begin
            pend <= 13'b0_0000_0000_0001;             // "READY" banner after reset
            c_ail <= 1'b0; c_aio <= 1'b0; c_xo <= 1'b0; ev_ai_occ_q <= 1'b0; ev_ai_prob_q <= 7'd0;
            {c_ap_h, c_ap_t, c_ap_o, c_xp_h, c_xp_t, c_xp_o} <= 24'd0;
            rsp_q <= RSP_NONE; anom_hh <= 5'd0; inact_hh <= 5'd0;
            kind <= K_READY; st <= T_IDLE; idx <= 8'd0; prep2 <= 1'b0;
            tx_data <= 8'h00; tx_start <= 1'b0;
            bcd_start <= 1'b0; bcd_in <= 40'd0; fan_bcd <= 52'd0; light_bcd <= 52'd0;
            {c_tok, c_tneg, c_light, c_manual, c_eco, c_gas, c_occ, c_pred, c_fault} <= 9'd0;
            c_sec <= 3'd0;
            {c_tt, c_to, c_tf, c_th_t, c_th_o, c_du_h, c_du_t, c_du_o} <= 32'd0;
            {c_hh_t, c_hh_o, c_mm_t, c_mm_o, c_dy_h, c_dy_t, c_dy_o, c_ev_t, c_ev_o} <= 36'd0;
        end else begin
            if (rsp_valid) rsp_q    <= rsp_code;
            if (ev_anom)   anom_hh  <= ev_hh;
            if (ev_inact)  inact_hh <= ev_hh;
            if (ev_ai) begin ev_ai_occ_q <= ev_ai_occ; ev_ai_prob_q <= ev_ai_prob; end

            case (st)
            T_IDLE: begin
                tx_start <= 1'b0;
                if (pend != 13'd0) begin
                    kind <= (sel == P_RSP) ? rsp_kind(rsp_q) : (sel == P_AI) ? K_AI : {1'b0, sel};
                    pend <= (pend & ~(13'd1 << sel)) | set_mask;
                    if (sel == P_RSP && rsp_q == RSP_ENERGY) begin
                        bcd_in <= fan_acc; bcd_start <= 1'b1; st <= T_CONV1;
                    end else
                        st <= T_CAPT;
                end else
                    pend <= pend | set_mask;
            end

            T_CONV1: begin
                pend      <= pend | set_mask;
                bcd_start <= 1'b0;
                if (bcd_done) begin
                    fan_bcd <= bcd_out; bcd_in <= light_acc; bcd_start <= 1'b1; st <= T_CONV2;
                end
            end

            T_CONV2: begin
                pend      <= pend | set_mask;
                bcd_start <= 1'b0;
                if (bcd_done) begin light_bcd <= bcd_out; st <= T_CAPT; end
            end

            T_CAPT: begin                              // freeze the status fields
                pend     <= pend | set_mask;
                c_tok    <= temp_ok;          c_tneg   <= temp[12];
                c_tt     <= b_t[7:4];         c_to     <= b_t[3:0];   c_tf <= tfr_r;
                c_th_t   <= b_th[7:4];        c_th_o   <= b_th[3:0];
                c_du_h   <= b_du[11:8];       c_du_t   <= b_du[7:4];  c_du_o <= b_du[3:0];
                c_light  <= light;            c_manual <= manual;  c_eco  <= eco;
                c_sec    <= sec_state;        c_gas    <= emergency;
                c_occ    <= occupied;         c_pred   <= predicted; c_fault <= fault;
                c_ail    <= ai_live;          c_aio    <= ai_occ;
                c_ap_h   <= b_ap[11:8];       c_ap_t   <= b_ap[7:4];  c_ap_o <= b_ap[3:0];
                c_xo     <= ev_ai_occ_q;
                c_xp_h   <= b_xp[11:8];       c_xp_t   <= b_xp[7:4];  c_xp_o <= b_xp[3:0];
                c_hh_t   <= b_hh[7:4];        c_hh_o   <= b_hh[3:0];
                c_mm_t   <= b_mm[7:4];        c_mm_o   <= b_mm[3:0];
                c_dy_h   <= b_dy[11:8];       c_dy_t   <= b_dy[7:4];  c_dy_o <= b_dy[3:0];
                c_ev_t   <= (kind == K_ANOM) ? b_an[7:4] : b_in[7:4];
                c_ev_o   <= (kind == K_ANOM) ? b_an[3:0] : b_in[3:0];
                idx      <= 8'd0;
                prep2    <= 1'b0;
                st       <= T_PREP;
            end

            T_PREP: begin                              // 2 cycles: pj_r, then profile digits settle
                pend  <= pend | set_mask;
                prep2 <= ~prep2;
                if (prep2) st <= T_SEND;
            end

            T_SEND: begin
                pend     <= pend | set_mask;
                tx_data  <= ch;
                tx_start <= 1'b1;
                st       <= T_WAITB;
            end

            T_WAITB: begin
                pend     <= pend | set_mask;
                tx_start <= 1'b0;
                if (tx_busy) st <= T_WAITD;
            end

            T_WAITD: begin
                pend <= pend | set_mask;
                if (!tx_busy) begin
                    if (idx == len - 1) st <= T_IDLE;
                    else begin idx <= idx + 1'b1; prep2 <= 1'b0; st <= T_PREP; end
                end
            end

            default: st <= T_IDLE;
            endcase
        end
    end
endmodule
