// ============================================================================
// bcd_func.vh : combinational 8-bit binary -> 3-digit BCD (double dabble)
//   bcd8(v) = {hundreds, tens, ones}, about 30 LUTs, no dividers
// ============================================================================
function [11:0] bcd8;
    input [7:0] b;
    integer n;
    reg [19:0] s;
    begin
        s = {12'd0, b};
        for (n = 0; n < 8; n = n + 1) begin
            if (s[11:8]  >= 4'd5) s[11:8]  = s[11:8]  + 4'd3;
            if (s[15:12] >= 4'd5) s[15:12] = s[15:12] + 4'd3;
            if (s[19:16] >= 4'd5) s[19:16] = s[19:16] + 4'd3;
            s = s << 1;
        end
        bcd8 = s[19:8];
    end
endfunction
