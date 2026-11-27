`timescale 1ns/1ps
// Testbench plant, not synthesized hardware or a physical safety model.
module barrier_model #(parameter TRAVEL=12)(
 input wire clk,rst,open_cmd,close_cmd,jam,
 output wire open_limit,close_limit,output reg [7:0] position
);
 assign open_limit=(position==TRAVEL);
 assign close_limit=(position==0);
 always @(posedge clk)begin
  if(rst)position<=0;
  else if(!jam)begin
   if(open_cmd&&!close_cmd&&position<TRAVEL)position<=position+1'b1;
   else if(close_cmd&&!open_cmd&&position>0)position<=position-1'b1;
  end
  if(!rst&&open_cmd&&close_cmd)$fatal(1,"contradictory barrier commands");
 end
endmodule
