`timescale 1ns/1ps
// alert: threshold with hysteresis + sticky W1C interrupt
module alert (
  input  wire               clk, rst, flush,
  input  wire               avg_valid,
  input  wire signed [15:0] avg, t_lo, t_hi,
  input  wire               irq_en,
  input  wire               irq_clr,      // write-1-to-clear pulse
  output reg                alert_state,
  output reg                irq_pend,
  output wire               irq
);
  always @(posedge clk) begin
    if (rst || flush) begin
      alert_state <= 1'b0;
      irq_pend    <= 1'b0;
    end else begin
      if (irq_clr) irq_pend <= 1'b0;
      if (avg_valid) begin
        if (!alert_state && avg < t_lo) begin
          alert_state <= 1'b1;
          irq_pend    <= 1'b1;                 // set wins over a clear in the same cycle
        end else if (alert_state && avg > t_hi)
          alert_state <= 1'b0;
      end
    end
  end
  assign irq = irq_pend & irq_en;
endmodule
