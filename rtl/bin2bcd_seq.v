`timescale 1ns / 1ps
// ============================================================================
// bin2bcd_seq : sequential double-dabble binary -> BCD converter
//   W bits in, D decimal digits out, W clock cycles per conversion
// ============================================================================
module bin2bcd_seq #(
    parameter integer W = 40,
    parameter integer D = 13
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           start,
    input  wire [W-1:0]   bin,
    output reg  [4*D-1:0] bcd,
    output reg            done
);
    reg [W-1:0]           sh;
    reg [$clog2(W+1)-1:0] n;
    reg                   busy;
    reg [4*D-1:0]         adj;
    integer i;

    always @(*) begin
        adj = bcd;
        for (i = 0; i < D; i = i + 1)
            if (adj[4*i +: 4] >= 4'd5) adj[4*i +: 4] = adj[4*i +: 4] + 4'd3;
    end

    always @(posedge clk) begin
        if (rst) begin
            sh <= 0; n <= 0; busy <= 1'b0; bcd <= 0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                sh <= bin; bcd <= 0; n <= W; busy <= 1'b1;
            end else if (busy) begin
                bcd <= {adj[4*D-2:0], sh[W-1]};
                sh  <= {sh[W-2:0], 1'b0};
                n   <= n - 1'b1;
                if (n == 1) begin busy <= 1'b0; done <= 1'b1; end
            end
        end
    end
endmodule
