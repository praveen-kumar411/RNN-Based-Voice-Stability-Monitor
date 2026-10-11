`timescale 1ns/1ps
// act_lut: sigmoid / tanh using one 256-entry sigmoid table
// mode = 0 -> sigmoid(x)        output 0 .. 2048   (Q4.11)
// mode = 1 -> tanh(x) = 2*sigmoid(2x) - 1   output -2048 .. 2048
module act_lut (
  input  wire               mode,
  input  wire signed [15:0] x_in,     // Q4.11
  output reg  signed [15:0] y_out     // Q4.11
);
  reg [15:0] rom [0:255];
  initial $readmemh("sigmoid.hex", rom);

  // tanh needs 2x: use 17 bits so the doubling can't overflow
  wire signed [16:0] x_ext = {x_in[15], x_in};
  wire signed [16:0] x_sel = mode ? (x_ext <<< 1) : x_ext;

  // clamp to the LUT range [-8, 8)  =  [-16384, 16383]
  wire signed [16:0] x_clamp = (x_sel >  17'sd16383) ?  17'sd16383 :
                               (x_sel < -17'sd16384) ? -17'sd16384 : x_sel;

  // address = (x >>> 7) + 128   ->  0 .. 255
  wire signed [16:0] x_sh = x_clamp >>> 7;
  wire [7:0] idx = x_sh[7:0] + 8'd128;

  wire signed [15:0] sig = rom[idx];

  always @(*)
    y_out = mode ? ((sig <<< 1) - 16'sd2048) : sig;
endmodule
