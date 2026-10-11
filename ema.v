`timescale 1ns/1ps
// ema: shift-based exponential moving average (no dividers)
module ema (
  input  wire               clk, rst, flush,
  input  wire [3:0]         k,            // alpha = 1 / 2^k
  input  wire               score_valid,
  input  wire signed [15:0] score,        // Q4.11, 0..2048
  output wire signed [15:0] avg,          // Q4.11
  output reg                avg_valid     // 1 cycle after score_valid
);
  localparam signed [27:0] INIT = 28'sd8388608;     // 2048 << 12  (avg = 1.0)

  reg  signed [27:0] avg_ext;                       // Q4.23 (12 extra fraction bits)
  wire signed [27:0] s_ext = $signed({score, 12'b0});
  wire signed [27:0] diff  = s_ext - avg_ext;

  always @(posedge clk) begin
    if (rst || flush) begin
      avg_ext   <= INIT;
      avg_valid <= 1'b0;
    end else begin
      avg_valid <= score_valid;
      if (score_valid) avg_ext <= avg_ext + (diff >>> k);
    end
  end

  assign avg = avg_ext[27:12];
endmodule
