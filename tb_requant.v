`timescale 1ns/1ps
module tb_requant;
  reg  signed [31:0] acc;
  wire signed [15:0] q;
  wire               sat;
  integer errors = 0;

  requant #(.SHIFT(6)) dut (.acc_in(acc), .q_out(q), .sat(sat));

  // apply one input, compare with the expected output
  task check(input signed [31:0] a, input signed [15:0] exp_q, input exp_sat);
    begin
      acc = a; #1;
      if (q !== exp_q || sat !== exp_sat) begin
        $display("FAIL: acc=%0d  got q=%0d sat=%0b  expected q=%0d sat=%0b",
                 a, q, sat, exp_q, exp_sat);
        errors = errors + 1;
      end else
        $display("ok  : acc=%0d  ->  q=%0d sat=%0b", a, q, sat);
    end
  endtask

  initial begin
    // normal values
    check( 32'sd0,          16'sd0,      1'b0);   // zero
    check( 32'sd131072,     16'sd2048,   1'b0);   // 1.0
    check(-32'sd131072,    -16'sd2048,   1'b0);   // -1.0
    // rounding
    check( 32'sd131103,     16'sd2048,   1'b0);   // +31 : rounds down
    check( 32'sd131104,     16'sd2049,   1'b0);   // +32 : exactly half, rounds up
    check(-32'sd131104,    -16'sd2048,   1'b0);   // negative half rounds toward +inf
    check(-32'sd131105,    -16'sd2049,   1'b0);
    // saturation edges
    check( 32'sd2097087,    16'sd32767,  1'b0);   // just fits
    check( 32'sd2097120,    16'sd32767,  1'b1);   // rounds to 32768 -> clipped
    check(-32'sd2097152,   -16'sd32768,  1'b0);   // exactly minimum
    check(-32'sd2097185,   -16'sd32768,  1'b1);   // below minimum -> clipped
    // extreme inputs
    check( 32'sh7FFFFFFF,   16'sd32767,  1'b1);
    check( 32'sh80000000,  -16'sd32768,  1'b1);

    if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
    else             $display("\n*** %0d TESTS FAILED ***\n", errors);
    $finish;
  end
endmodule
