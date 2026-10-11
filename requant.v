`timescale 1ns/1ps
// requant: round, arithmetic shift right, saturate to INT16
// SHIFT = 6  -> after MAC (Q5.17 -> Q4.11)
// SHIFT = 11 -> after Q4.11 x Q4.11 multiply (Q8.22 -> Q4.11)
module requant #(
  parameter SHIFT = 6
)(
  input  wire signed [31:0] acc_in,
  output reg  signed [15:0] q_out,
  output reg                sat      // 1 = value was clipped
);
  // 33 bits so adding the rounding constant can never overflow
  wire signed [32:0] acc_ext = {acc_in[31], acc_in};
  wire signed [32:0] rounded = acc_ext + (33'sd1 <<< (SHIFT-1));
  wire signed [32:0] shifted = rounded >>> SHIFT;

  always @(*) begin
    if (shifted > 33'sd32767) begin
      q_out = 16'sd32767;
      sat   = 1'b1;
    end else if (shifted < -33'sd32768) begin
      q_out = -16'sd32768;
      sat   = 1'b1;
    end else begin
      q_out = shifted[15:0];
      sat   = 1'b0;
    end
  end
endmodule
