`timescale 1ns/1ps
module request_monitor #(parameter WIDTH=116)(
 input wire clk,rst,valid,ready,input wire [WIDTH-1:0] payload
);
 reg stalled=0;reg [WIDTH-1:0] held;
 always @(posedge clk)begin
  if(rst)stalled<=0;
  else begin
   if(stalled&&(!valid||payload!==held))$fatal(1,"valid/payload changed before handshake");
   stalled<=valid&&!ready;held<=payload;
  end
 end
endmodule
