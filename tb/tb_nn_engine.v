`timescale 1ns / 1ps
// ============================================================================
// tb_nn_engine : runs ALL 12 417 unseen test samples of the UCI Occupancy
//   dataset through the hardware neural-network engine at 100 MHz.
//   * checks every output is bit-exact with the Python integer model
//   * computes the hardware classification accuracy against the true labels
//   Vector format (ai/nn_test_vectors.mem, one line per sample, hex):
//     T_x10[16] RH_x10[16] LUX[16] CO2[16] LABEL[4] Z_EXPECTED[24]
// ============================================================================
module tb_nn_engine;
    reg clk = 1'b0, rst = 1'b1, start = 1'b0;
    always #5 clk = ~clk;
    reg  signed [15:0] t, rh, lx, c2;
    wire busy, done, occ;
    wire [6:0] prob;
    wire signed [23:0] z;
    nn_engine dut (.clk(clk), .rst(rst), .start(start), .t_x10(t), .rh_x10(rh), .lux(lx), .co2(c2),
                   .busy(busy), .done(done), .occ(occ), .prob(prob), .z(z));

    localparam integer N = 12417;
    reg [91:0] vec [0:N-1];
    integer k, exact, correct, tp, tn, fp, fn, cycles, lat;
    reg lab;
    reg signed [23:0] zexp;

    initial $timeformat(-6, 1, " us", 12);
    initial begin
        $readmemh("nn_test_vectors.mem", vec);
        exact = 0; correct = 0; tp = 0; tn = 0; fp = 0; fn = 0;
        repeat (5) @(posedge clk); rst = 1'b0;
        for (k = 0; k < N; k = k + 1) begin
            {t, rh, lx, c2} = vec[k][91:28];
            lab  = vec[k][24];
            zexp = vec[k][23:0];
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0; cycles = 1;
            while (!done) begin @(negedge clk); cycles = cycles + 1; end
            if (k == 0) lat = cycles;
            if (z === zexp) exact = exact + 1;
            else if (exact - k > -5) $display("MISMATCH sample %0d: z=%0d expected %0d", k, z, zexp);
            if (occ == lab) correct = correct + 1;
            if (occ && lab) tp = tp + 1;  if (!occ && !lab) tn = tn + 1;
            if (occ && !lab) fp = fp + 1; if (!occ && lab) fn = fn + 1;
            if (k < 3) $display("sample %0d: T=%0d.%0d C RH=%0d.%0d %% lux=%0d CO2=%0d -> z=%0d occ=%0d P=%0d%% (label %0d)",
                                k, t/10, t%10, rh/10, rh%10, lx, c2, z, occ, prob, lab);
        end
        $display("\n==================================================");
        $display(" Test samples            : %0d", N);
        $display(" Bit-exact with Python   : %0d / %0d", exact, N);
        $display(" Hardware accuracy       : %0d / %0d = %0.2f %%", correct, N, 100.0 * correct / N);
        $display(" TP %0d  TN %0d  FP %0d  FN %0d", tp, tn, fp, fn);
        $display(" Latency per inference   : %0d clock cycles (%0d ns)", lat, lat * 10);
        if (exact == N) $display(" RESULT                  : PASS (bit-exact on all samples)");
        else            $display(" RESULT                  : FAIL");
        $display("==================================================\n");
        $finish;
    end
endmodule
