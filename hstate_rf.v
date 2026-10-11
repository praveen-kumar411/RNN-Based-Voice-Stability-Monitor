`timescale 1ns/1ps
// hstate_rf: hidden state, ping-pong banks
// read  -> active bank   (h_prev)
// write -> inactive bank (h_next)
// swap  -> flips banks at end of frame
// flush -> clears everything (new call)
module hstate_rf #(
  parameter H  = 16,
  parameter AW = 4
)(
  input  wire               clk, rst,
  input  wire               flush,
  input  wire               swap,
  input  wire [AW-1:0]      raddr,
  output wire signed [15:0] rdata,
  input  wire               we,
  input  wire [AW-1:0]      waddr,
  input  wire signed [15:0] wdata,
  output reg                bank_sel
);
  reg signed [15:0] bank0 [0:H-1];
  reg signed [15:0] bank1 [0:H-1];
  integer k;

  always @(posedge clk) begin
    if (rst || flush) begin
      for (k = 0; k < H; k = k + 1) begin
        bank0[k] <= 16'sd0;
        bank1[k] <= 16'sd0;
      end
      bank_sel <= 1'b0;
    end else begin
      if (we) begin
        if (bank_sel) bank0[waddr] <= wdata;   // write the INACTIVE bank
        else          bank1[waddr] <= wdata;
      end
      if (swap) bank_sel <= ~bank_sel;
    end
  end

  assign rdata = bank_sel ? bank1[raddr] : bank0[raddr];
endmodule
