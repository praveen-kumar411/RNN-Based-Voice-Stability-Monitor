`timescale 1ns/1ps
// gru_core: one GRU step per 'start' using a single time-multiplexed MAC
// F = 8 features, H = 16 hidden units, Q4.11 activations, INT8 Q1.6 weights
module gru_core #(
  parameter WFILE = "",
  parameter BFILE = ""
)(
  input  wire               clk, rst,
  input  wire               start,
  input  wire               flush,
  input  wire [127:0]       x_flat,          // x[j] = x_flat[16*j +: 16]
  output wire               busy,
  output wire               done,            // 1-cycle pulse
  output reg  signed [15:0] score,           // Q4.11, 0..2048
  input  wire               w_we,            // weight loading port
  input  wire [10:0]        w_waddr,
  input  wire [7:0]         w_wdata,
  input  wire               b_we,            // bias loading port
  input  wire [6:0]         b_waddr,
  input  wire [15:0]        b_wdata
);
  localparam PZ = 3'd0, PR = 3'd1, PN1 = 3'd2, PN2 = 3'd3, POUT = 3'd4;
  localparam S_IDLE = 3'd0, S_BIAS = 3'd1, S_MAC = 3'd2, S_POST = 3'd3,
             S_UPD  = 3'd4, S_SWAP = 3'd5, S_DONE = 3'd6;

  reg [2:0] state, phase;
  reg [3:0] row;
  reg [4:0] col;
  reg signed [31:0] acc;
  reg signed [15:0] ra, n_reg;
  reg signed [15:0] z_buf [0:15];
  reg signed [15:0] r_buf [0:15];

  // ---------------- weight memory ----------------
  wire [10:0] row24 = {row, 4'b0000} + {row, 3'b000};     // row * 24
  reg  [10:0] w_raddr;
  always @(*) case (phase)
    PZ:      w_raddr = row24 + col;
    PR:      w_raddr = 11'd384 + row24 + col;
    PN1:     w_raddr = 11'd768 + row24 + col;
    PN2:     w_raddr = 11'd784 + row24 + col;              // 768 + 16
    default: w_raddr = 11'd1152 + col;
  endcase
  wire [7:0] w_rdata;
  mem_rw #(.WIDTH(8), .DEPTH(1168), .AW(11), .INIT_FILE(WFILE)) u_wmem (
    .clk(clk), .we(w_we), .waddr(w_waddr), .wdata(w_wdata),
    .raddr(w_raddr), .rdata(w_rdata));

  // ---------------- bias memory ----------------
  reg [6:0] b_raddr;
  always @(*) case (phase)
    PZ:      b_raddr = {3'b000, row};
    PR:      b_raddr = 7'd16 + row;
    PN1:     b_raddr = 7'd48 + row;                         // hidden part of n
    PN2:     b_raddr = 7'd32 + row;                         // input part of n
    default: b_raddr = 7'd64;
  endcase
  wire [15:0] b_rdata;
  mem_rw #(.WIDTH(16), .DEPTH(65), .AW(7), .INIT_FILE(BFILE)) u_bmem (
    .clk(clk), .we(b_we), .waddr(b_waddr), .wdata(b_wdata),
    .raddr(b_raddr), .rdata(b_rdata));

  // ---------------- hidden state ----------------
  wire [4:0] colm8 = col - 5'd8;
  reg  [3:0] h_raddr;
  always @(*)
    if (state == S_UPD)                h_raddr = row;
    else if (phase == PZ || phase == PR) h_raddr = colm8[3:0];
    else                               h_raddr = col[3:0];
  wire signed [15:0] h_rdata, h_new;
  wire bank_sel;
  hstate_rf u_h (.clk(clk), .rst(rst), .flush(flush), .swap(state == S_SWAP),
    .raddr(h_raddr), .rdata(h_rdata), .we(state == S_UPD), .waddr(row),
    .wdata(h_new), .bank_sel(bank_sel));

  // ---------------- MAC operand ----------------
  wire signed [15:0] x_sel = x_flat[{col[2:0], 4'b0000} +: 16];
  reg  signed [15:0] v;
  always @(*) case (phase)
    PZ, PR:  v = (col < 5'd8) ? x_sel : h_rdata;
    PN2:     v = x_sel;
    default: v = h_rdata;                                   // PN1, POUT
  endcase
  wire signed [7:0]  w_s  = w_rdata;
  wire signed [31:0] prod = w_s * v;

  // ---------------- requant + activation ----------------
  wire signed [15:0] q, lut_y;
  wire sat_q;
  requant #(.SHIFT(6)) u_rq6 (.acc_in(acc), .q_out(q), .sat(sat_q));
  act_lut u_lut (.mode(phase == PN2), .x_in(q), .y_out(lut_y));

  // reset gate: ra = rq11(r * a)
  wire signed [15:0] r_cur = r_buf[row];
  wire signed [31:0] ra_prod = r_cur * q;
  wire signed [15:0] ra_next;
  wire sat_ra;
  requant #(.SHIFT(11)) u_rq_ra (.acc_in(ra_prod), .q_out(ra_next), .sat(sat_ra));

  // bias loads
  wire signed [15:0] b_s   = b_rdata;
  wire signed [31:0] b32   = b_s;
  wire signed [31:0] rab32 = ra + b_s;

  // gate combine: h_new = sat16(n + rq11(z * (h - n)))
  wire signed [15:0] z_cur = z_buf[row];
  wire signed [16:0] diff  = h_rdata - n_reg;
  wire signed [31:0] zd    = z_cur * diff;
  wire signed [15:0] upd;
  wire sat_u;
  requant #(.SHIFT(11)) u_rq_z (.acc_in(zd), .q_out(upd), .sat(sat_u));
  wire signed [16:0] hsum = n_reg + upd;
  assign h_new = (hsum >  17'sd32767) ?  16'sd32767 :
                 (hsum < -17'sd32768) ? -16'sd32768 : hsum[15:0];

  // ---------------- control FSM ----------------
  assign busy = (state != S_IDLE);
  assign done = (state == S_DONE);
  wire [4:0] last_col = (phase == PZ || phase == PR) ? 5'd23 :
                        (phase == PN2) ? 5'd7 : 5'd15;

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE; phase <= PZ; row <= 0; col <= 0;
      acc <= 0; ra <= 0; n_reg <= 0; score <= 0;
    end else begin
      case (state)
        S_IDLE: if (start) begin phase <= PZ; row <= 0; state <= S_BIAS; end
        S_BIAS: begin
          col   <= 0;
          acc   <= (phase == PN2) ? (rab32 <<< 6) : (b32 <<< 6);
          state <= S_MAC;
        end
        S_MAC: begin
          acc <= acc + prod;
          if (col == last_col) state <= S_POST;
          else                 col   <= col + 1;
        end
        S_POST: case (phase)
          PZ: begin
            z_buf[row] <= lut_y; state <= S_BIAS;
            if (row == 4'd15) begin row <= 0; phase <= PR; end else row <= row + 1;
          end
          PR: begin
            r_buf[row] <= lut_y; state <= S_BIAS;
            if (row == 4'd15) begin row <= 0; phase <= PN1; end else row <= row + 1;
          end
          PN1:     begin ra <= ra_next; phase <= PN2; state <= S_BIAS; end
          PN2:     begin n_reg <= lut_y; state <= S_UPD; end
          default: begin score <= lut_y; state <= S_DONE; end
        endcase
        S_UPD:
          if (row == 4'd15) state <= S_SWAP;
          else begin row <= row + 1; phase <= PN1; state <= S_BIAS; end
        S_SWAP: begin phase <= POUT; row <= 0; state <= S_BIAS; end
        S_DONE: state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
