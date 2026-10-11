`timescale 1ns/1ps
// mem_rw: simple memory, synchronous write, combinational read
// Used for weights (8-bit x 1168) and biases (16-bit x 65)
module mem_rw #(
  parameter WIDTH     = 8,
  parameter DEPTH     = 1168,
  parameter AW        = 11,          // address bits
  parameter INIT_FILE = ""           // optional hex file for simulation
)(
  input  wire             clk,
  input  wire             we,        // write enable (weight loading)
  input  wire [AW-1:0]    waddr,
  input  wire [WIDTH-1:0] wdata,
  input  wire [AW-1:0]    raddr,
  output wire [WIDTH-1:0] rdata
);
  reg [WIDTH-1:0] mem [0:DEPTH-1];

  initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

  always @(posedge clk)
    if (we) mem[waddr] <= wdata;

  assign rdata = mem[raddr];
endmodule
