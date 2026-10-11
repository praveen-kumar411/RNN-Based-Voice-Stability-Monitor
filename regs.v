`timescale 1ns/1ps
// regs: simple register interface (wr strobe + addr + data, combinational read)
module regs (
  input  wire        clk, rst,
  input  wire        reg_wr,
  input  wire [3:0]  reg_addr,
  input  wire [15:0] reg_wdata,
  output reg  [15:0] reg_rdata,
  // control outputs
  output reg         en, irq_en,
  output reg         flush,               // 1-cycle pulse
  output reg         irq_clr,             // 1-cycle pulse
  output reg  signed [15:0] t_lo, t_hi,
  output reg  [3:0]  k,
  output wire        w_we,
  output reg  [10:0] w_addr,
  output wire [7:0]  w_data,
  output wire        b_we,
  output reg  [6:0]  b_addr,
  output wire [15:0] b_data,
  // status inputs
  input  wire        busy, irq_pend, alert_state,
  input  wire signed [15:0] score, avg,
  input  wire [15:0] frame_cnt
);
  localparam A_CTRL = 4'h0, A_STATUS = 4'h1, A_TLO   = 4'h2, A_THI   = 4'h3,
             A_K    = 4'h4, A_SCORE  = 4'h5, A_AVG   = 4'h6, A_WADDR = 4'h7,
             A_WDATA= 4'h8, A_BADDR  = 4'h9, A_BDATA = 4'hA, A_FCNT  = 4'hB;

  assign w_we   = reg_wr && (reg_addr == A_WDATA);
  assign w_data = reg_wdata[7:0];
  assign b_we   = reg_wr && (reg_addr == A_BDATA);
  assign b_data = reg_wdata;

  always @(posedge clk) begin
    if (rst) begin
      en <= 0; irq_en <= 0; flush <= 0; irq_clr <= 0;
      t_lo <= 16'sd1024; t_hi <= 16'sd1280; k <= 4'd3;
      w_addr <= 0; b_addr <= 0;
    end else begin
      flush   <= 1'b0;                      // pulses clear themselves
      irq_clr <= 1'b0;
      if (reg_wr) case (reg_addr)
        A_CTRL:   begin en <= reg_wdata[0]; flush <= reg_wdata[1]; irq_en <= reg_wdata[2]; end
        A_STATUS: irq_clr <= reg_wdata[1];
        A_TLO:    t_lo   <= reg_wdata;
        A_THI:    t_hi   <= reg_wdata;
        A_K:      k      <= reg_wdata[3:0];
        A_WADDR:  w_addr <= reg_wdata[10:0];
        A_WDATA:  w_addr <= w_addr + 1'b1;
        A_BADDR:  b_addr <= reg_wdata[6:0];
        A_BDATA:  b_addr <= b_addr + 1'b1;
        default: ;
      endcase
    end
  end

  always @(*) case (reg_addr)
    A_CTRL:   reg_rdata = {13'd0, irq_en, 1'b0, en};
    A_STATUS: reg_rdata = {13'd0, alert_state, irq_pend, busy};
    A_TLO:    reg_rdata = t_lo;
    A_THI:    reg_rdata = t_hi;
    A_K:      reg_rdata = {12'd0, k};
    A_SCORE:  reg_rdata = score;
    A_AVG:    reg_rdata = avg;
    A_WADDR:  reg_rdata = {5'd0, w_addr};
    A_BADDR:  reg_rdata = {9'd0, b_addr};
    A_FCNT:   reg_rdata = frame_cnt;
    default:  reg_rdata = 16'd0;
  endcase
endmodule
