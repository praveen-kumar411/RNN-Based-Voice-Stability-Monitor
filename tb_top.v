`timescale 1ns/1ps
module tb_top;
  localparam NF = 100, GAP = 3000;          // idle cycles between frames (after frame 10)
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
  integer n_clk = 0, n_gclk = 0;
  reg measure = 0;
  reg [15:0] rs, ra, st;

  always @(posedge clk)      if (measure) n_clk  = n_clk + 1;
  always @(posedge dut.gclk) if (measure) n_gclk = n_gclk + 1;

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
        while (!s_tready) @(negedge clk);   // wait for back-pressure to release
      end
      @(negedge clk); s_tvalid = 0; s_tlast = 0;
    end
  endtask

  initial begin
    $readmemh("weights.hex",     wv);
    $readmemh("biases.hex",      bv);
    $readmemh("top_x.hex",       xv);
    $readmemh("top_vectors.hex", ev);
    $readmemh("top_cfg.hex",     cfg);
    #22 rst = 0;

    // 1. load weights and biases through the register map
    reg_write(A_WADDR, 0);
    for (i = 0; i < 1168; i = i + 1) reg_write(A_WDATA, {8'd0, wv[i]});
    reg_write(A_BADDR, 0);
    for (i = 0; i < 65; i = i + 1)   reg_write(A_BDATA, bv[i]);

    // 2. configure, then enable + flush + irq enable
    reg_write(A_TLO, cfg[0]);
    reg_write(A_THI, cfg[1]);
    reg_write(A_K,   cfg[2]);
    reg_write(A_CTRL, 16'h0007);
    measure = 1;

    fork
      // stream driver: first 10 frames back-to-back, then idle gaps
      begin
        for (f = 0; f < NF; f = f + 1) begin
          send_frame(xv[f]);
          if (f >= 10) repeat (GAP) @(negedge clk);
        end
      end
      // checker: one check per frame, after the alert has updated
      begin : checker
        integer c;
        for (c = 0; c < NF; c = c + 1) begin
          @(posedge dut.avg_valid);
          @(negedge clk); @(negedge clk);
          reg_read(A_SCORE, rs);
          reg_read(A_AVG, ra);
          reg_read(A_STATUS, st);
          if (rs !== ev[c][39:24] || ra !== ev[c][23:8] ||
              st[2] !== ev[c][4]  || st[1] !== ev[c][0]) begin
            if (errors < 20)
              $display("FAIL frame %0d: score %0d/%0d avg %0d/%0d alert %0b/%0b irq %0b/%0b",
                       c, rs, ev[c][39:24], ra, ev[c][23:8],
                       st[2], ev[c][4], st[1], ev[c][0]);
            errors = errors + 1;
          end
          if (st[1]) begin
            irqs = irqs + 1;
            reg_write(A_STATUS, 16'h0002);    // W1C clear of IRQ_PEND
          end
        end
      end
    join

    reg_read(A_FCNT, rs);
    $display("\nFrames counted by DUT : %0d (expected %0d)", rs, NF);
    $display("IRQs serviced         : %0d", irqs);
    $display("Core clock active     : %0d of %0d cycles (%0d%%)",
             n_gclk, n_clk, (n_gclk * 100) / n_clk);
    if (errors == 0 && rs == NF) $display("*** TOP LEVEL: ALL %0d FRAMES MATCH ***\n", NF);
    else                         $display("*** TOP LEVEL: %0d MISMATCHES ***\n", errors);
    $finish;
  end

  // ---- activity dump for power estimation (short window only) ----
  initial begin
    #300000;                          // skip weight loading + back-to-back frames
    $dumpfile("top.vcd");
    $dumpvars(0, tb_top.dut);
    #130000;                          // ~3 frames + idle gaps
    $dumpoff;
  end
endmodule
