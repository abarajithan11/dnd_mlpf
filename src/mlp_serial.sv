`timescale 1ns/1ps

module mlp_serial #(
  parameter   N1 = 98,
              N2 = 10,
              P  = 2,
              W_X = 4,
              W_K = 4,
              W_Y = 16
)(
  input  logic clk, in_vld, rst,
  input  logic [P   -1:0][W_X-1:0] in_mag,
  input  logic [P   -1:0][1:0]     in_pol,
  output logic [W_Y -1:0]          out,
  output logic                     out_vld
);
  genvar n2, p;
  localparam  N_BEATS       = (1+N1/2)/2,
              W_SUM_FC1     = W_X + W_K + $clog2(N1/2),
              W_SUM_FC1_POL = 2   + W_K + $clog2(N1/2),
              W_SUM_FC2     = W_X + W_K + $clog2(N2);

  // Weights initialized from luts generated by python
  logic [N2-1:0][N_BEATS-1:0][P-1:0][W_K-1:0] weights_n1_mag; 
  logic [N2-1:0][N_BEATS-1:0][P-1:0][W_K-1:0] weights_n1_pol;
  logic                     [N2  :0][W_K-1:0] weights_n2;
  logic                 [2**W_X-1:0][W_Y-1:0] tanh;
  luts LUTS (.*);

  logic [$clog2(N_BEATS)-1:0] n_beats;

  always_ff @(posedge clk)
    if      (rst   ) n_beats <= 0;
    else if (in_vld) n_beats <= n_beats == N_BEATS-1 ? 0 : n_beats + 1;

  wire [P-1:0][W_X-1:0] in_mag_bias = (n_beats == N_BEATS-1) ? {W_X'(1), in_mag[0]} : in_mag;
  wire [P-1:0][1    :0] in_pol_bias = (n_beats == N_BEATS-1) ? {2'd1   , in_pol[0]} : in_pol;

  logic mul_last, mul_vld, add_last;
  always_ff @(posedge clk) begin
    mul_vld  <= rst ? '0 : in_vld;
    mul_last <= n_beats == N_BEATS-1;
    add_last <= rst ? '0 : mul_last;
  end

  logic [P -1:0][N2-1:0][W_X + W_K-1:0] fc1_mag_mul;
  logic [P -1:0][N2-1:0][1   + W_K-1:0] fc1_pol_mul;

  logic [N2-1:0][W_SUM_FC1 -1:0] fc1_out;
  logic [N2-1:0][W_X       -1:0] fc2_in;

  for (n2=0; n2<N2; n2=n2+1) begin
    for (p=0; p<P; p=p+1)
      always_ff @(posedge clk) begin
        fc1_mag_mul[p][n2] <= $signed(weights_n1_mag[n2][n_beats][p]) * $signed(in_mag_bias[p]);
        fc1_pol_mul[p][n2] <= $signed(weights_n1_pol[n2][n_beats][p]) * $signed(in_pol_bias[p]);
      end

    always_ff @(posedge clk)
      if (rst || add_last) fc1_out[n2] <= '0;
      else if (mul_vld)    fc1_out[n2] <= $signed(fc1_out[n2]) + $signed(fc1_mag_mul[0][n2]) + $signed(fc1_pol_mul[0][n2]) + $signed(fc1_mag_mul[1][n2]) + $signed(fc1_pol_mul[1][n2]);


    assign fc2_in[n2] = add_last ? fc1_out[n2][N2-1:0] : '0;
  end

  logic [W_SUM_FC2-1:0] fc2_out;
  
  matvec_mul #(
    .R(1), .C(N2+1), .W_X(W_X), .W_K(W_K)
  ) FC2_MAG (  
    .clk(clk), 
    .cen(1'b1), 
    .k(weights_n2),
    .x({W_X'(1), fc2_in}),
    .y(fc2_out)
  );

  assign out = tanh[W_X'(fc2_out)];

  logic [$clog2(N2) -1:0] vld_shift;
  always_ff @(posedge clk) 
    {out_vld, vld_shift} = rst ? '0 : {vld_shift, add_last};

endmodule