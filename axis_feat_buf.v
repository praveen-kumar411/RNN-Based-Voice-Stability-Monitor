`timescale 1ns/1ps
// axis_feat_buf: AXI-Stream slave, collects 8 features, pulses 'start' on TLAST
module axis_feat_buf (
  input  wire         clk, rst,
  input  wire         en,
  input  wire         core_busy,
  input  wire         s_tvalid,
  output wire         s_tready,
  input  wire [15:0]  s_tdata,
  input  wire         s_tlast,
  output reg  [127:0] x_flat,
  output reg          start
);
  reg [2:0] cnt;
  assign s_tready = en && !core_busy && !start;    // back-pressure while computing
  wire hs = s_tvalid && s_tready;                  // a transfer happens

  always @(posedge clk) begin
    if (rst) begin
      cnt <= 0; start <= 0; x_flat <= 0;
    end else begin
      start <= 1'b0;
      if (hs) begin
        x_flat[{cnt, 4'b0000} +: 16] <= s_tdata;
        if (s_tlast) begin cnt <= 0; start <= 1'b1; end
        else         cnt <= cnt + 1'b1;
      end
    end
  end
endmodule
