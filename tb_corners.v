`timescale 1ns/1ps
// tb_corners: saturated inputs, reset mid-call, flush mid-call
module tb_corners;
  localparam NF = 61;
  localparam A_CTRL=4'h0, A_STATUS=4'h1, A_TLO=4'h2, A_THI=4'h3, A_K=4'h4,
             A_SCORE=4'h5, A_AVG=4'h6, A_WADDR=4'h7, A_WDATA=4'h8,
             A_BADDR=4'h9, A_BDATA=4'hA, A_FCNT=4'hB;

  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  reg         s_tvalid = 0, s_tlast = 0;
  reg  [15:0] s_tdata = 0;
  wire        s_tready;
  reg         reg_wr = 0;
  reg  [3:0]  reg_addr = 0;
  reg  [15:0] reg_wdata = 0;
  wire [15:0] reg_rdata;
  wire        irq;

  rnn_vsm_top dut (.clk(clk), .rst(rst), .s_tvalid(s_tvalid), .s_tready(s_tready),
    .s_tdata(s_tdata), .s_tlast(s_tlast), .reg_wr(reg_wr), .reg_addr(reg_addr),
    .reg_wdata(reg_wdata), .reg_rdata(reg_rdata), .irq(irq));

  reg [7:0]   wv [0:1167];
  reg [15:0]  bv [0:64];
  reg [127:0] xv [0:NF-1];
  reg [39:0]  ev [0:NF-1];
  reg [15:0]  cfg[0:2];
  integer i, f, errors = 0, irqs = 0;
  reg [15:0] rs, ra, st, rd;

  task reg_write(input [3:0] a, input [15:0] d);
    begin
      @(negedge clk); reg_wr = 1; reg_addr = a; reg_wdata = d;
      @(negedge clk); reg_wr = 0;
    end
  endtask

  task reg_read(input [3:0] a, output [15:0] d);
    begin reg_addr = a; #1; d = reg_rdata; end
  endtask

  task send_frame(input [127:0] x);
    integer j;
    begin
      for (j = 0; j < 8; j = j + 1) begin
        @(negedge clk);
        s_tvalid = 1; s_tdata = x[16*j +: 16]; s_tlast = (j == 7);
        while (!s_tready) @(negedge clk);
      end
      @(negedge clk); s_tvalid = 0; s_tlast = 0;
    end
  endtask

  task check_frame(input integer n);
    begin
      @(posedge dut.avg_valid);
      @(negedge clk); @(negedge clk);
      reg_read(A_SCORE, rs);
      reg_read(A_AVG, ra);
      reg_read(A_STATUS, st);
      if (rs !== ev[n][39:24] || ra !== ev[n][23:8] ||
          st[2] !== ev[n][4]  || st[1] !== ev[n][0]) begin
        $display("  FAIL frame %0d: score %0d/%0d avg %0d/%0d alert %0b/%0b irq %0b/%0b",
                 n, rs, ev[n][39:24], ra, ev[n][23:8], st[2], ev[n][4], st[1], ev[n][0]);
        errors = errors + 1;
      end
      if (st[1]) begin
        irqs = irqs + 1;
        reg_write(A_STATUS, 16'h0002);
      end
    end
  endtask

  task expect_eq(input [15:0] got, input [15:0] exp, input [8*32-1:0] what);
    if (got !== exp) begin
      $display("  FAIL %0s: got %0d expected %0d", what, got, exp);
      errors = errors + 1;
    end else
      $display("  ok   %0s = %0d", what, got);
  endtask

  task configure;
    begin
      reg_write(A_TLO, cfg[0]);
      reg_write(A_THI, cfg[1]);
      reg_write(A_K,   cfg[2]);
      reg_write(A_CTRL, 16'h0007);               // EN | FLUSH | IRQ_EN
    end
  endtask

  initial begin
    $readmemh("weights.hex",    wv);
    $readmemh("biases.hex",     bv);
    $readmemh("corner_x.hex",   xv);
    $readmemh("corner_exp.hex", ev);
    $readmemh("corner_cfg.hex", cfg);
    #22 rst = 0;

    reg_write(A_WADDR, 0);
    for (i = 0; i < 1168; i = i + 1) reg_write(A_WDATA, {8'd0, wv[i]});
    reg_write(A_BADDR, 0);
    for (i = 0; i < 65; i = i + 1)   reg_write(A_BDATA, bv[i]);
    configure;

    // ---------- T1: normal + saturated inputs ----------
    $display("\n[T1] frames 0-19 (saturated at 5, 6)");
    for (f = 0; f < 20; f = f + 1) begin send_frame(xv[f]); check_frame(f); end

    // ---------- T2: reset in the middle of a computation ----------
    $display("\n[T2] reset mid-call (during frame 20)");
    send_frame(xv[20]);
    repeat (500) @(negedge clk);
    reg_read(A_STATUS, rd);
    expect_eq(rd[0], 1, "BUSY before reset");
    rst = 1;  repeat (3) @(negedge clk);  rst = 0;
    @(negedge clk);
    reg_read(A_STATUS, rd); expect_eq(rd,       0, "STATUS after reset");
    reg_read(A_CTRL,   rd); expect_eq(rd,       0, "CTRL after reset");
    reg_read(A_FCNT,   rd); expect_eq(rd,       0, "FRAME_CNT after reset");
    expect_eq({15'd0, s_tready}, 0, "TREADY while disabled");
    configure;                                   // weights NOT reloaded on purpose
    for (f = 21; f < 41; f = f + 1) begin send_frame(xv[f]); check_frame(f); end

    // ---------- T3: flush between frames ----------
    $display("\n[T3] flush mid-call (between frames 40 and 41)");
    reg_write(A_CTRL, 16'h0007);
    @(negedge clk);
    reg_read(A_FCNT, rd); expect_eq(rd, 0, "FRAME_CNT after flush");
    for (f = 41; f < 61; f = f + 1) begin send_frame(xv[f]); check_frame(f); end
    reg_read(A_FCNT, rd); expect_eq(rd, 20, "FRAME_CNT at end");

    $display("\nIRQs serviced: %0d", irqs);
    if (errors == 0) $display("*** CORNER CASES: ALL PASSED (reset kept weights, flush cleared state) ***\n");
    else             $display("*** CORNER CASES: %0d FAILURES ***\n", errors);
    $finish;
  end
endmodule
