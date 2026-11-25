module dff
  #(parameter [0:0] reset_val_p = 1'b0)
  (input [0:0] clk_i
  ,input [0:0] reset_i
  ,input [0:0] d_i
  ,input [0:0] en_i
  ,output [0:0] q_o);

   logic [0:0] q_r;
   always_ff @(posedge clk_i) begin
      if(reset_i) begin
	q_r <= reset_val_p;
      end else if (en_i) begin
	q_r <= d_i;
      end
   end
   assign q_o = q_r;
endmodule
