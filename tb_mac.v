    `timescale 1ns/1ps
    module tb_mac;
      reg clk = 0, rst = 1, clr = 0, en = 0;
      reg  signed [7:0]  w;
      reg  signed [15:0] v;
      wire signed [31:0] acc;

      mac dut (.clk(clk), .rst(rst), .clr(clr), .en(en), .w(w), .v(v), .acc(acc));

      always #5 clk = ~clk;

      initial begin
        #12 rst = 0;
        en = 1; w = 8'sd64;  v = 16'sd2048; #10;
                w = -8'sd32; v = 16'sd4096; #10;
        en = 0; #10;
        $display("acc = %0d  (expected 0)", acc);
        $finish;
      end
    endmodule
