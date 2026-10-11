`timescale 1ns/1ps
module tb_gru_core;
  localparam NF = 50;
  reg clk = 0, rst = 1, start = 0, flush = 0;
  always #5 clk = ~clk;                         // 100 MHz in simulation

  reg [127:0] xv [0:NF-1];
  reg [15:0]  es [0:NF-1];
  reg [255:0] eh [0:NF-1];
  reg [127:0] x_flat = 0;
  wire busy, done;
  wire signed [15:0] score;

  gru_core #(.WFILE("weights.hex"), .BFILE("biases.hex")) dut (
    .clk(clk), .rst(rst), .start(start), .flush(flush), .x_flat(x_flat),
    .busy(busy), .done(done), .score(score),
    .w_we(1'b0), .w_waddr(11'd0), .w_wdata(8'd0),
    .b_we(1'b0), .b_waddr(7'd0), .b_wdata(16'd0));

  integer f, k, errors = 0, cycles;
  time t0;
  reg signed [15:0] h_rtl, h_exp;

  initial begin
    $readmemh("x_vectors.hex",  xv);
    $readmemh("exp_scores.hex", es);
    $readmemh("exp_h.hex",      eh);
    #12 rst = 0;
    @(negedge clk) flush = 1;  @(negedge clk) flush = 0;

    for (f = 0; f < NF; f = f + 1) begin
      x_flat = xv[f];
      @(negedge clk) start = 1;  t0 = $time;
      @(negedge clk) start = 0;
      @(posedge done);
      @(negedge clk);
      cycles = ($time - t0) / 10;

      if (score !== es[f]) begin
        $display("FAIL frame %0d: score got %0d expected %0d", f, score, $signed(es[f]));
        errors = errors + 1;
      end
      for (k = 0; k < 16; k = k + 1) begin
        h_rtl = dut.u_h.bank_sel ? dut.u_h.bank1[k] : dut.u_h.bank0[k];
        h_exp = eh[f][16*k +: 16];
        if (h_rtl !== h_exp) begin
          if (errors < 20)
            $display("FAIL frame %0d: h[%0d] got %0d expected %0d", f, k, h_rtl, h_exp);
          errors = errors + 1;
        end
      end
    end

    $display("\nLatency: %0d cycles per frame (= %0d us at 10 MHz)", cycles, cycles/10);
    if (errors == 0) $display("*** GRU CORE: ALL %0d FRAMES BIT-EXACT ***\n", NF);
    else             $display("*** GRU CORE: %0d MISMATCHES ***\n", errors);
    $finish;
  end
endmodule
