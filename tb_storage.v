`timescale 1ns/1ps
module tb_storage;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;
  integer errors = 0, i;

  // ---------- weight memory ----------
  reg         w_we;
  reg  [10:0] w_waddr, w_raddr;
  reg  [7:0]  w_wdata;
  wire [7:0]  w_rdata;
  mem_rw #(.WIDTH(8), .DEPTH(1168), .AW(11)) u_wmem (
    .clk(clk), .we(w_we), .waddr(w_waddr), .wdata(w_wdata),
    .raddr(w_raddr), .rdata(w_rdata));

  // ---------- hidden state ----------
  reg               flush = 0, swap = 0, h_we = 0;
  reg  [3:0]        h_raddr, h_waddr;
  reg  signed [15:0] h_wdata;
  wire signed [15:0] h_rdata;
  wire              bank_sel;
  hstate_rf u_h (.clk(clk), .rst(rst), .flush(flush), .swap(swap),
    .raddr(h_raddr), .rdata(h_rdata), .we(h_we), .waddr(h_waddr),
    .wdata(h_wdata), .bank_sel(bank_sel));

  task expect16(input [15:0] got, input [15:0] exp, input [8*24-1:0] name);
    if (got !== exp) begin
      $display("FAIL %0s: got %0d expected %0d", name, $signed(got), $signed(exp));
      errors = errors + 1;
    end
  endtask

  initial begin
    w_we = 0;
    #12 rst = 0;

    // T1: write weights 0..1167 with pattern, read back
    for (i = 0; i < 1168; i = i + 1) begin
      @(negedge clk); w_we = 1; w_waddr = i; w_wdata = i[7:0] ^ 8'hA5;
    end
    @(negedge clk); w_we = 0;
    for (i = 0; i < 1168; i = i + 1) begin
      w_raddr = i; #1;
      expect16({8'd0, w_rdata}, {8'd0, i[7:0] ^ 8'hA5}, "weight readback");
    end

    // T2: write h_next while h_prev still reads 0
    for (i = 0; i < 16; i = i + 1) begin
      @(negedge clk); h_we = 1; h_waddr = i; h_wdata = 100 + i;
    end
    @(negedge clk); h_we = 0;
    for (i = 0; i < 16; i = i + 1) begin
      h_raddr = i; #1; expect16(h_rdata, 0, "h_prev before swap");
    end

    // T3: swap -> new values visible
    @(negedge clk); swap = 1; @(negedge clk); swap = 0;
    for (i = 0; i < 16; i = i + 1) begin
      h_raddr = i; #1; expect16(h_rdata, 100 + i, "h after swap");
    end

    // T4: flush -> everything zero
    @(negedge clk); flush = 1; @(negedge clk); flush = 0;
    for (i = 0; i < 16; i = i + 1) begin
      h_raddr = i; #1; expect16(h_rdata, 0, "h after flush");
    end
    if (bank_sel !== 1'b0) begin $display("FAIL bank_sel after flush"); errors = errors + 1; end

    if (errors == 0) $display("\n*** STORAGE: ALL TESTS PASSED ***\n");
    else             $display("\n*** STORAGE: %0d FAILED ***\n", errors);
    $finish;
  end
endmodule
