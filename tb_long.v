`timescale 1ns/1ps
// tb_long: one-hour call, 180k frames, bit-exact every frame, no waveforms
module tb_long;
  localparam NF = 180000;
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
  reg [15:0] rs, ra, st;

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

  initial begin
    $readmemh("weights.hex",  wv);
    $readmemh("biases.hex",   bv);
    $readmemh("long_x.hex",   xv);
    $readmemh("long_exp.hex", ev);
    $readmemh("long_cfg.hex", cfg);
    #22 rst = 0;

    reg_write(A_WADDR, 0);
    for (i = 0; i < 1168; i = i + 1) reg_write(A_WDATA, {8'd0, wv[i]});
    reg_write(A_BADDR, 0);
    for (i = 0; i < 65; i = i + 1)   reg_write(A_BDATA, bv[i]);
    reg_write(A_TLO, cfg[0]);
    reg_write(A_THI, cfg[1]);
    reg_write(A_K,   cfg[2]);
    reg_write(A_CTRL, 16'h0007);                    // EN | FLUSH | IRQ_EN (once, at call start)

    for (f = 0; f < NF; f = f + 1) begin
      send_frame(xv[f]);
      @(posedge dut.avg_valid);
      @(negedge clk); @(negedge clk);
      reg_read(A_SCORE, rs);
      reg_read(A_AVG, ra);
      reg_read(A_STATUS, st);
      if (rs !== ev[f][39:24] || ra !== ev[f][23:8] || st[2] !== ev[f][4]) begin
        if (errors < 20)
          $display("FAIL frame %0d: score %0d/%0d avg %0d/%0d alert %0b/%0b",
                   f, rs, ev[f][39:24], ra, ev[f][23:8], st[2], ev[f][4]);
        errors = errors + 1;
      end
      if (st[1]) begin
        irqs = irqs + 1;
        reg_write(A_STATUS, 16'h0002);
      end
      if (f % 10000 == 0)
        $display("[progress] frame %0d / %0d, errors so far = %0d", f, NF, errors);
    end

    $display("\n================ ONE-HOUR CALL TEST ================");
    $display("Frames   : %0d (= %0d minutes at 20 ms)", NF, NF / 3000);
    $display("IRQs     : %0d", irqs);
    $display("Errors   : %0d", errors);
    if (errors == 0) $display("*** LONG TEST PASSED: state continuity verified ***");
    else             $display("*** LONG TEST FAILED ***");
    $finish;
  end
endmodule
