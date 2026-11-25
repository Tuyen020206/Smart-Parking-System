`timescale 1ns/1ps
module sync_bits #(parameter WIDTH=1, RESET_VALUE=0)(
 input wire clk,rst,input wire [WIDTH-1:0] async_in,output reg [WIDTH-1:0] sync_out
);
 (* ASYNC_REG="TRUE" *) reg [WIDTH-1:0] stage;
 always @(posedge clk) begin
  if(rst)begin stage<=RESET_VALUE;sync_out<=RESET_VALUE;end
  else begin stage<=async_in;sync_out<=stage;end
 end
endmodule
