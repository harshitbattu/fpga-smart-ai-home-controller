`timescale 1ns / 1ps
// ============================================================================
// adt7420_model : behavioural I2C slave model of the ADT7420 (testbench only)
//   * responds to address 0x4B, returns the 16-bit temperature register
//   * value = temperature(1/16 degC) << 3   (13-bit mode)
//   * present = 0 simulates a disconnected / failed sensor (address NACK)
// ============================================================================
module adt7420_model (
    input  wire scl,
    inout  wire sda
);
    reg        sda_drv = 1'b0;
    assign sda = sda_drv ? 1'b0 : 1'bz;

    reg [15:0] value   = 16'h0C80;     // 25.0 degC
    reg        present = 1'b1;

    reg [7:0]  sh = 8'd0, cur = 8'd0;
    integer    bitc  = 0;
    integer    phase = 0;              // 0 idle,1 addr,2 addr done,3 send,4 wait master ack,5 ack drive,6 next byte
    reg        rd = 1'b0;

    task set_temp16;                   // temperature in 1/16 degC
        input integer t16;
        begin value = t16 << 3; end
    endtask

    task drive_bit;
        begin sda_drv = ~cur[7 - bitc]; bitc = bitc + 1; end
    endtask

    // START / STOP detection
    always @(negedge sda) if (scl === 1'b1) begin phase = 1; bitc = 0; sda_drv = 1'b0; end
    always @(posedge sda) if (scl === 1'b1) begin phase = 0; sda_drv = 1'b0; end

    always @(posedge scl) begin
        case (phase)
            1: begin
                   sh = {sh[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
                   bitc = bitc + 1;
                   if (bitc == 8) phase = 2;
               end
            4: if (sda === 1'b0) phase = 6; else phase = 0;   // master ACK -> next byte
            default: ;
        endcase
    end

    always @(negedge scl) begin
        case (phase)
            2: if (present && sh[7:1] == 7'h4B) begin sda_drv = 1'b1; rd = sh[0]; phase = 5; end
               else phase = 0;
            5: begin
                   sda_drv = 1'b0;
                   if (rd) begin cur = value[15:8]; bitc = 0; drive_bit; phase = 3; end
                   else phase = 0;
               end
            3: if (bitc == 8) begin sda_drv = 1'b0; phase = 4; end
               else drive_bit;
            6: begin cur = value[7:0]; bitc = 0; drive_bit; phase = 3; end
            default: ;
        endcase
    end
endmodule
