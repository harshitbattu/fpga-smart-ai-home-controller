`timescale 1ns / 1ps
// ============================================================================
// adt7420_reader : I2C master that reads the ADT7420 temperature sensor
//                  soldered on the Nexys 4 DDR board (I2C address 0x4B)
//   * open-drain outputs: *_oe = 1 pulls the line LOW, 0 releases it
//   * SCL = f_clk / (4*QDIV)  -> 100 kHz with QDIV = 250 @ 100 MHz
//   * every POLL_CYCLES: START, 0x97 (addr+R), read MSB (ACK), LSB (NACK), STOP
//     (the ADT7420 address pointer resets to 0x00 = temperature register)
//   * temp_raw : 13-bit two's complement, 1 LSB = 0.0625 degC (1/16 degC)
//   * fault    : set when the sensor does not acknowledge its address
// ============================================================================
module adt7420_reader #(
    parameter integer QDIV        = 250,
    parameter integer POLL_CYCLES = 25_000_000,   // 250 ms (ADT7420 conversion = 240 ms)
    parameter [6:0]   ADDR        = 7'h4B
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              sda_in,
    output reg               sda_oe,
    output reg               scl_oe,
    output reg signed [12:0] temp_raw,
    output reg               valid,
    output reg               fault
);
    localparam integer QW = (QDIV < 2) ? 1 : $clog2(QDIV);
    localparam integer PW = $clog2(POLL_CYCLES);
    localparam [3:0] S_IDLE = 4'd0, S_START = 4'd1, S_ADDR = 4'd2, S_AACK = 4'd3,
                     S_RD1  = 4'd4, S_MACK  = 4'd5, S_RD2  = 4'd6, S_MNACK = 4'd7,
                     S_STOP = 4'd8;

    reg [QW-1:0] qcnt;
    reg [PW-1:0] poll;
    reg [3:0]    st;
    reg [1:0]    q;
    reg [2:0]    bitn;
    reg [7:0]    sh, msb;
    reg          nack;
    reg          sda_s0, sda_s1;

    wire qtick = (qcnt == QDIV - 1);

    always @(posedge clk) begin
        if (rst) begin
            qcnt <= 0; poll <= 0; st <= S_IDLE; q <= 2'd0; bitn <= 3'd7;
            sh <= 8'd0; msb <= 8'd0; nack <= 1'b0;
            sda_oe <= 1'b0; scl_oe <= 1'b0;
            temp_raw <= 13'sd0; valid <= 1'b0; fault <= 1'b0;
            sda_s0 <= 1'b1; sda_s1 <= 1'b1;
        end else begin
            sda_s0 <= sda_in;
            sda_s1 <= sda_s0;
            valid  <= 1'b0;
            qcnt   <= qtick ? 0 : qcnt + 1'b1;

            case (st)
            S_IDLE: begin
                sda_oe <= 1'b0; scl_oe <= 1'b0;
                if (poll == POLL_CYCLES - 1) begin poll <= 0; st <= S_START; q <= 2'd0; end
                else poll <= poll + 1'b1;
            end
            // START: SDA falls while SCL is high
            S_START: if (qtick) begin
                case (q)
                    2'd0: begin sda_oe <= 1'b0; scl_oe <= 1'b0; end
                    2'd1: sda_oe <= 1'b1;
                    2'd2: scl_oe <= 1'b1;
                    2'd3: begin st <= S_ADDR; sh <= {ADDR, 1'b1}; bitn <= 3'd7; end
                endcase
                q <= q + 1'b1;
            end
            // write address byte, MSB first (data changes while SCL low)
            S_ADDR: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= ~sh[7];
                    2'd1: scl_oe <= 1'b0;
                    2'd2: ;
                    2'd3: begin
                        scl_oe <= 1'b1;
                        sh <= {sh[6:0], 1'b0};
                        if (bitn == 3'd0) st <= S_AACK; else bitn <= bitn - 1'b1;
                    end
                endcase
                q <= q + 1'b1;
            end
            // slave acknowledge
            S_AACK: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= 1'b0;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: nack   <= sda_s1;
                    2'd3: begin
                        scl_oe <= 1'b1;
                        if (nack) begin fault <= 1'b1; st <= S_STOP; end
                        else      begin st <= S_RD1; bitn <= 3'd7; end
                    end
                endcase
                q <= q + 1'b1;
            end
            // read a byte (sample while SCL high)
            S_RD1, S_RD2: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= 1'b0;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: sh <= {sh[6:0], sda_s1};
                    2'd3: begin
                        scl_oe <= 1'b1;
                        if (bitn == 3'd0) st <= (st == S_RD1) ? S_MACK : S_MNACK;
                        else bitn <= bitn - 1'b1;
                    end
                endcase
                q <= q + 1'b1;
            end
            // master ACK after MSB
            S_MACK: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= 1'b1;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: ;
                    2'd3: begin scl_oe <= 1'b1; msb <= sh; st <= S_RD2; bitn <= 3'd7; end
                endcase
                q <= q + 1'b1;
            end
            // master NACK after LSB, latch the result
            S_MNACK: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= 1'b0;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: ;
                    2'd3: begin
                        scl_oe   <= 1'b1;
                        temp_raw <= {msb, sh[7:3]};
                        valid    <= 1'b1;
                        fault    <= 1'b0;
                        st       <= S_STOP;
                    end
                endcase
                q <= q + 1'b1;
            end
            // STOP: SDA rises while SCL is high
            S_STOP: if (qtick) begin
                case (q)
                    2'd0: sda_oe <= 1'b1;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: sda_oe <= 1'b0;
                    2'd3: st <= S_IDLE;
                endcase
                q <= q + 1'b1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
