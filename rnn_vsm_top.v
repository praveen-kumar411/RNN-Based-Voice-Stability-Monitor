`timescale 1ns/1ps
// rnn_vsm_top: RNN-based voice stability monitor
module rnn_vsm_top #(
  parameter WFILE = "",
  parameter BFILE = ""
)(
  input  wire        clk, rst,
  input  wire        s_tvalid,
  output wire        s_tready,
  input  wire [15:0] s_tdata,
  input  wire        s_tlast,
  input  wire        reg_wr,
  input  wire [3:0]  reg_addr,
  input  wire [15:0] reg_wdata,
  output wire [15:0] reg_rdata,
  output wire        irq
);
  wire en, irq_en, flush, irq_clr, w_we, b_we;
  wire signed [15:0] t_lo, t_hi, score, avg;
  wire [3:0]  k;
  wire [10:0] w_addr;
  wire [7:0]  w_data;
  wire [6:0]  b_addr;
  wire [15:0] b_data;
  wire [127:0] x_flat;
  wire start, busy, done, avg_valid, alert_state, irq_pend, gclk;
  reg  [15:0] frame_cnt;

  regs u_regs (.clk(clk), .rst(rst), .reg_wr(reg_wr), .reg_addr(reg_addr),
    .reg_wdata(reg_wdata), .reg_rdata(reg_rdata), .en(en), .irq_en(irq_en),
    .flush(flush), .irq_clr(irq_clr), .t_lo(t_lo), .t_hi(t_hi), .k(k),
    .w_we(w_we), .w_addr(w_addr), .w_data(w_data),
    .b_we(b_we), .b_addr(b_addr), .b_data(b_data),
    .busy(busy), .irq_pend(irq_pend), .alert_state(alert_state),
    .score(score), .avg(avg), .frame_cnt(frame_cnt));

  axis_feat_buf u_axis (.clk(clk), .rst(rst), .en(en), .core_busy(busy),
    .s_tvalid(s_tvalid), .s_tready(s_tready), .s_tdata(s_tdata),
    .s_tlast(s_tlast), .x_flat(x_flat), .start(start));

  // core clock runs only when there is work to do
  wire core_en = rst | busy | start | flush | w_we | b_we;
  icg u_icg (.clk(clk), .en(core_en), .gclk(gclk));

  gru_core #(.WFILE(WFILE), .BFILE(BFILE)) u_core (
    .clk(gclk), .rst(rst), .start(start), .flush(flush), .x_flat(x_flat),
    .busy(busy), .done(done), .score(score),
    .w_we(w_we), .w_waddr(w_addr), .w_wdata(w_data),
    .b_we(b_we), .b_waddr(b_addr), .b_wdata(b_data));

  ema u_ema (.clk(clk), .rst(rst), .flush(flush), .k(k),
    .score_valid(done), .score(score), .avg(avg), .avg_valid(avg_valid));

  alert u_alert (.clk(clk), .rst(rst), .flush(flush), .avg_valid(avg_valid),
    .avg(avg), .t_lo(t_lo), .t_hi(t_hi), .irq_en(irq_en), .irq_clr(irq_clr),
    .alert_state(alert_state), .irq_pend(irq_pend), .irq(irq));

  always @(posedge clk)
    if (rst || flush) frame_cnt <= 16'd0;
    else if (done)    frame_cnt <= frame_cnt + 1'b1;
endmodule
