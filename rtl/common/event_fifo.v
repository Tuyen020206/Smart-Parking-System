`timescale 1ns/1ps
module event_fifo #(parameter WIDTH=256,DEPTH=8)(
 input wire clk,rst,push,input wire [WIDTH-1:0] din,input wire pop,
 output wire [WIDTH-1:0] dout,output wire full,empty,
 output wire [$clog2(DEPTH+1)-1:0] count
);
 localparam PW=(DEPTH<=1)?1:$clog2(DEPTH);
 reg [WIDTH-1:0] mem[0:DEPTH-1];reg [PW-1:0] head,tail;
 reg [$clog2(DEPTH+1)-1:0] used;
 wire rd=pop&&!empty;wire wr=push&&(!full||rd);
 assign empty=(used==0);assign full=(used==DEPTH);assign count=used;
 assign dout=empty?{WIDTH{1'b0}}:mem[head];
 always @(posedge clk)begin
  if(rst)begin head<=0;tail<=0;used<=0;end
  else begin
   if(wr)begin mem[tail]<=din;tail<=(tail==DEPTH-1)?0:tail+1'b1;end
   if(rd)head<=(head==DEPTH-1)?0:head+1'b1;
   case({wr,rd})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:used<=used;endcase
  end
 end
endmodule
