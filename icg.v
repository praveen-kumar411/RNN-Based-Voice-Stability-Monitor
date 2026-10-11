`timescale 1ns/1ps
// icg: behavioural integrated clock gate (latch + AND)
// For ASIC synthesis, replace with the library ICG cell
module icg (
  input  wire clk,
  input  wire en,
  output wire gclk
);
  reg en_lat;
  initial en_lat = 1'b0;
  always @(clk or en)
    if (!clk) en_lat = en;          // latch is transparent while clk is low
  assign gclk = clk & en_lat;       // no glitches: en can only change while clk is low
endmodule
