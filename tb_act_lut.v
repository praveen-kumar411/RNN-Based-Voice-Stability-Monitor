`timescale 1ns/1ps
module tb_act_lut;
  localparam N = 1000;
  reg  [35:0] vec [0:N-1];          // {mode(4b), x(16b), expected(16b)}
  reg               mode;
  reg  signed [15:0] x, expected;
  wire signed [15:0] y;
  integer i, errors = 0;

  act_lut dut (.mode(mode), .x_in(x), .y_out(y));

  initial begin
    $readmemh("lut_vectors.hex", vec);
    for (i = 0; i < N; i = i + 1) begin
      mode     = vec[i][32];
      x        = vec[i][31:16];
      expected = vec[i][15:0];
      #1;
      if (y !== expected) begin
        if (errors < 10)
          $display("FAIL #%0d: mode=%0d x=%0d  got %0d  expected %0d",
                   i, mode, x, y, expected);
        errors = errors + 1;
      end
    end
    if (errors == 0) $display("\n*** ALL %0d VECTORS PASSED ***\n", N);
    else             $display("\n*** %0d / %0d FAILED ***\n", errors, N);
    $finish;
  end
endmodule
