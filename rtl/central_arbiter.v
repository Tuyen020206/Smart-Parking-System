`timescale 1ns/1ps
module central_arbiter #(parameter SLOTS=8,PORTS=5,ENTRY_GATES=3)(
 input wire clk,rst,run_enable,
 input wire [PORTS-1:0] req_valid,output reg [PORTS-1:0] req_ready,
 input wire [PORTS*64-1:0] req_id,input wire [PORTS*4-1:0] req_op,
 input wire [PORTS*16-1:0] req_slot,req_data,req_tag,
 output wire probe_valid,output reg [63:0] id,output reg [3:0] op,
 output reg [15:0] slot,data,tag,output reg [7:0] source,
 input wire mem_ready,duplicate,early_reject,candidate_ok,
 input wire [7:0] candidate_status,early_status,cached_status,
 input wire [15:0] candidate_slot,cached_slot,
 output wire fire,output reg [7:0] final_status,output reg [15:0] final_slot,
 output reg [15:0] c_next,n_next,r_next,d_next,q_next,
 output reg [15:0] c_count,n_count,r_count,d_count,q_count,
 output reg online,output wire [15:0] available,output wire overcommitted,
 output reg rsp_valid,output reg [63:0] rsp_id,output reg [3:0] rsp_op,
 output reg [7:0] rsp_source,rsp_status,output reg [15:0] rsp_slot,rsp_tag,
 output reg commit_valid,output reg [3:0] commit_op,output reg [63:0] commit_id
);
 integer i,index,selected,used_capacity;reg found;reg [7:0] rr;
 reg online_next;reg allowed;
 assign probe_valid=found;
 assign fire=found&&mem_ready&&!rst;
 wire [18:0] total={3'b0,n_count}+{3'b0,r_count}+{3'b0,d_count}+{3'b0,q_count};
 assign available=total>=c_count?0:c_count-total;
 assign overcommitted=total>c_count;
 always @*begin
  selected=0;found=0;
  for(i=0;i<PORTS;i=i+1)begin
   index=(rr+i)%PORTS;
   if(!found&&req_valid[index])begin found=1;selected=index;end
  end
  source=selected;id=req_id[selected*64+:64];op=req_op[selected*4+:4];
  slot=req_slot[selected*16+:16];data=req_data[selected*16+:16];tag=req_tag[selected*16+:16];
 end
 always @*begin
  req_ready=0;if(found&&mem_ready&&!rst)req_ready[selected]=1;
  c_next=c_count;n_next=n_count;r_next=r_count;d_next=d_count;q_next=q_count;online_next=online;
  final_status=0;final_slot=candidate_slot;allowed=1;
  used_capacity=n_count+r_count+d_count+q_count;
  if(early_reject)begin final_status=early_status;final_slot=slot;end
  else if(duplicate)begin final_status=cached_status;final_slot=cached_slot;end
  else if(!candidate_ok)final_status=candidate_status;
  else begin
   case(op)
    0,5,7:begin
     if(source>=ENTRY_GATES||!data[0])begin allowed=0;final_status=9;end
     else if(!run_enable)begin allowed=0;final_status=10;end
     else if(op==0&&(!online||used_capacity>=c_count))allowed=0;
     else if(op==5&&(!online||d_count==0))allowed=0;
     else if(op==7&&(online||q_count==0))allowed=0;
     if(allowed)begin
      r_next=r_count+1'b1;
      if(op==5)d_next=d_count-1'b1;
      if(op==7)q_next=q_count-1'b1;
     end
    end
    1:begin
     if(source>=ENTRY_GATES||!data[0])begin allowed=0;final_status=9;end
     else if(r_count==0)allowed=0;
     if(allowed)begin r_next=r_count-1'b1;n_next=n_count+1'b1;end
    end
    2:begin
     if(source>=ENTRY_GATES||!data[0])begin allowed=0;final_status=9;end
     else if(r_count==0)allowed=0;
     if(allowed)r_next=r_count-1'b1;
    end
    3:begin
     if(source<ENTRY_GATES||source>=PORTS-1||!data[0])begin allowed=0;final_status=9;end
     else if(n_count==0)allowed=0;
     if(allowed)n_next=n_count-1'b1;
    end
    4,6:begin
     if(source!=PORTS-1)begin allowed=0;final_status=9;end
     else if(data==0||used_capacity+data>c_count||!online)allowed=0;
     if(allowed)begin if(op==4)d_next=d_count+data;else q_next=q_count+data;end
    end
    8:begin if(source!=PORTS-1)begin allowed=0;final_status=9;end else online_next=data[0];end
    9:begin
     if(source!=PORTS-1)begin allowed=0;final_status=9;end
     else if(data>SLOTS)allowed=0;
     if(allowed)c_next=data;
    end
    10:if(source!=PORTS-1)begin allowed=0;final_status=9;end
    11:begin
     if(source<ENTRY_GATES||source>=PORTS-1||!data[0])begin allowed=0;final_status=9;end
     else if(!run_enable)begin allowed=0;final_status=10;end
    end
    12:begin
     if(source!=PORTS-1)begin allowed=0;final_status=9;end
     else if(data==0||data>d_count)allowed=0;
     if(allowed)d_next=d_count-data;
    end
    default:begin allowed=0;final_status=8;end
   endcase
   if(!allowed&&final_status==0)final_status=1;
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   rr<=0;c_count<=SLOTS;n_count<=0;r_count<=0;d_count<=0;q_count<=0;online<=1;
   rsp_valid<=0;rsp_id<=0;rsp_op<=0;rsp_source<=0;rsp_status<=0;rsp_slot<=16'hffff;rsp_tag<=0;
   commit_valid<=0;commit_op<=0;commit_id<=0;
  end else begin
   rsp_valid<=fire;commit_valid<=0;
   if(fire)begin
    rr<=(selected==PORTS-1)?0:selected+1;
    rsp_id<=id;rsp_op<=op;rsp_source<=source;rsp_status<=final_status;rsp_slot<=final_slot;rsp_tag<=tag;
    if(!duplicate&&!early_reject&&final_status==0)begin
     c_count<=c_next;n_count<=n_next;r_count<=r_next;d_count<=d_next;q_count<=q_next;online<=online_next;
     commit_valid<=1;commit_op<=op;commit_id<=id;
    end
   end
  end
 end
endmodule
