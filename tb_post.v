`timescale 1ns/1ps
module tb_post;
  localparam NF = 300;
  reg clk = 0, rst = 1, flush = 0;
  always #5 clk = ~clk;

  reg  [39:0] vec [0:NF-1];             // score | avg | alert | irq
  reg         score_valid = 0, irq_clr = 0;
  reg  signed [15:0] score = 0;
  wire signed [15:0] avg;
  wire avg_valid, alert_state, irq_pend, irq;

  ema u_ema (.clk(clk), .rst(rst), .flush(flush), .k(4'd3),
             .score_valid(score_valid), .score(score),
             .avg(avg), .avg_valid(avg_valid));

  alert u_alert (.clk(clk), .rst(rst), .flush(flush), .avg_valid(avg_valid),
                 .avg(avg), .t_lo(16'sd1024), .t_hi(16'sd1280),
                 .irq_en(1'b1), .irq_clr(irq_clr),
                 .alert_state(alert_state), .irq_pend(irq_pend), .irq(irq));

  integer f, errors = 0, irqs = 0;
  reg [15:0] e_avg;
  reg        e_alert, e_irq;

  initial begin
    $readmemh("post_vectors.hex", vec);
    #12 rst = 0;
    @(negedge clk) flush = 1;  @(negedge clk) flush = 0;

    for (f = 0; f < NF; f = f + 1) begin
      score   = vec[f][39:24];
      e_avg   = vec[f][23:8];
      e_alert = vec[f][4];
      e_irq   = vec[f][0];

      @(negedge clk) score_valid = 1;
      @(negedge clk) score_valid = 0;   // EMA updates here
      @(negedge clk);                   // alert updates here

      if (avg !== e_avg || alert_state !== e_alert || irq_pend !== e_irq) begin
        if (errors < 20)
          $display("FAIL frame %0d: avg %0d/%0d alert %0b/%0b irq %0b/%0b (got/exp)",
                   f, avg, e_avg, alert_state, e_alert, irq_pend, e_irq);
        errors = errors + 1;
      end
      if (irq) begin                    // software services the interrupt
        irqs = irqs + 1;
        @(negedge clk) irq_clr = 1;
        @(negedge clk) irq_clr = 0;
      end
    end

    $display("\nIRQs seen: %0d", irqs);
    if (errors == 0) $display("*** EMA + ALERT: ALL %0d FRAMES MATCH ***\n", NF);
    else             $display("*** EMA + ALERT: %0d MISMATCHES ***\n", errors);
    $finish;
  end
endmodule
