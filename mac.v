   `timescale 1ns/1ps
   module mac (
     input  wire               clk, rst, clr, en,
     input  wire signed [7:0]  w,
     input  wire signed [15:0] v,
     output reg  signed [31:0] acc
   );
     always @(posedge clk)
       if (rst | clr) acc <= 0;
       else if (en)   acc <= acc + w * v;
   endmodule
