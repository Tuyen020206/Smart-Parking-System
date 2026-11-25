`timescale 1ns/1ps
module parking_mem_opt #(parameter SLOTS=8,SOURCES=5,FIFO_DEPTH=8,DEDUP=16)(
 input wire clk,rst,input wire [23:0] epoch,
 input wire probe_valid,input wire [63:0] id,input wire [3:0] op,
 input wire [15:0] slot,data,tag,input wire [7:0] source,
 output reg ready,duplicate,early_reject,candidate_ok,
 output reg [7:0] candidate_status,early_status,cached_status,
 output reg [15:0] candidate_slot,cached_slot,
 input wire fire,input wire [7:0] final_status,input wire [15:0] final_slot,
 input wire [15:0] c_next,n_next,r_next,d_next,q_next,
 input wire sensor_valid,output wire sensor_ready,input wire [15:0] sensor_slot,
 input wire sensor_known,sensor_occupied,input wire [63:0] sensor_id,
 input wire [15:0] c_now,n_now,r_now,d_now,q_now,
 input wire retire_valid,input wire [7:0] retire_source,input wire [23:0] retire_epoch,
 input wire [31:0] retire_seq,output reg retire_ok,
 output wire event_valid,input wire event_ready,output wire [255:0] event_data,
 output wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_count,
 output reg [SLOTS-1:0] occupied,valid_map,reserved,maintenance,admitted,exit_pending,
 output reg [31:0] dedup_hits,conflicts,stale_count,
 output reg [$clog2(DEDUP+1)-1:0] dedup_used
);
 localparam OK=0,DENIED=1,BAD_SLOT=2,BAD_STATE=3,CONFLICT=4,STALE=5,
            BAD_EPOCH=6,BAD_SOURCE=7,BAD_OP=8,NOT_AUTH=9;
 reg [7:0] owner[0:SLOTS-1],exit_owner[0:SLOTS-1];
 reg [15:0] owner_tag[0:SLOTS-1],exit_tag[0:SLOTS-1];
 reg [63:0] keys[0:DEDUP-1];reg [55:0] payloads[0:DEDUP-1];
 reg [7:0] results[0:DEDUP-1];reg [15:0] result_slots[0:DEDUP-1];
 reg [DEDUP-1:0] used;
 reg [31:0] highwater[0:SOURCES-1],delivered[0:SOURCES-1];
 reg [SOURCES-1:0] seen_seq,seen_delivered;
 integer i,hit,free_index;reg found;
 wire [55:0] payload={{4{1'b0}},op,slot,data,tag};
 wire fifo_full,fifo_empty;
 wire fifo_space=!fifo_full||event_ready;
 assign sensor_ready=!rst&&fifo_space;
 assign event_valid=!rst&&!fifo_empty;
 wire sensor_fire=sensor_valid&&sensor_ready;
 reg push;reg [255:0] fifo_input;
 event_fifo #(256,FIFO_DEPTH) events(clk,rst,push,fifo_input,event_ready,event_data,fifo_full,fifo_empty,fifo_count);
 always @*begin
  hit=-1;free_index=-1;
  for(i=0;i<DEDUP;i=i+1)begin
   if(used[i]&&keys[i]==id)hit=i;
   if(!used[i]&&free_index<0)free_index=i;
  end
  duplicate=0;early_reject=0;early_status=0;cached_status=0;cached_slot=16'hffff;
  if(source>=SOURCES||id[63:56]!=source)begin early_reject=1;early_status=BAD_SOURCE;end
  else if(id[55:32]!=epoch)begin early_reject=1;early_status=BAD_EPOCH;end
  else if(hit>=0)begin
   if(payloads[hit]!=payload)begin early_reject=1;early_status=CONFLICT;end
   else begin duplicate=1;cached_status=results[hit];cached_slot=result_slots[hit];end
  end else if(seen_seq[source]&&id[31:0]<=highwater[source])begin
   early_reject=1;early_status=STALE;
  end
  candidate_ok=1;candidate_status=OK;candidate_slot=slot;found=0;
  case(op)
   0,5,7:begin
    candidate_slot=16'hffff;candidate_ok=0;candidate_status=DENIED;
    for(i=0;i<SLOTS;i=i+1)if(!found&&valid_map[i]&&!occupied[i]&&!reserved[i]&&!maintenance[i]&&!admitted[i])begin
     found=1;candidate_slot=i;candidate_ok=1;candidate_status=OK;
    end
   end
   1,2:begin
    if(slot>=SLOTS)begin candidate_ok=0;candidate_status=BAD_SLOT;end
    else if(!reserved[slot]||admitted[slot]||owner[slot]!=source||owner_tag[slot]!=tag)begin
     candidate_ok=0;candidate_status=BAD_STATE;
    end
   end
   3:begin
    if(slot>=SLOTS)begin candidate_ok=0;candidate_status=BAD_SLOT;end
    else if(!admitted[slot]||!exit_pending[slot]||occupied[slot]||exit_owner[slot]!=source||exit_tag[slot]!=tag)begin
     candidate_ok=0;candidate_status=BAD_STATE;
    end
   end
   10:if(slot>=SLOTS)begin candidate_ok=0;candidate_status=BAD_SLOT;end
   11:begin
    if(slot>=SLOTS)begin candidate_ok=0;candidate_status=BAD_SLOT;end
    else if(!admitted[slot]||occupied[slot]||exit_pending[slot])begin candidate_ok=0;candidate_status=BAD_STATE;end
   end
   4,6,8,9,12:begin end
   default:begin candidate_ok=0;candidate_status=BAD_OP;end
  endcase
  ready=!rst&&!sensor_valid&&(duplicate||early_reject||(free_index>=0&&fifo_space));
 end
 always @*begin
  push=0;fifo_input=0;
  if(sensor_fire)begin
   push=1;
   fifo_input={sensor_id,8'h80,8'h00,sensor_slot,16'h0,16'h0,c_now,n_now,r_now,d_now,q_now,
               6'h0,sensor_known,sensor_occupied,40'h0};
  end else if(fire&&!duplicate&&!early_reject)begin
   push=1;
   fifo_input={id,4'h0,op,final_status,final_slot,tag,data,c_next,n_next,r_next,d_next,q_next,48'h0};
  end
 end
 integer j,k;integer freed;
 always @(posedge clk)begin
  if(rst)begin
   occupied<=0;valid_map<=0;reserved<=0;maintenance<=0;admitted<=0;exit_pending<=0;
   used<=0;seen_seq<=0;seen_delivered<=0;dedup_used<=0;
   dedup_hits<=0;conflicts<=0;stale_count<=0;retire_ok<=0;
   for(j=0;j<SOURCES;j=j+1)begin highwater[j]<=0;delivered[j]<=0;end
   for(j=0;j<SLOTS;j=j+1)begin owner[j]<=0;owner_tag[j]<=0;exit_owner[j]<=0;exit_tag[j]<=0;end
  end else begin
   retire_ok<=0;
   if(event_valid&&event_ready&&event_data[255:248]<SOURCES)begin
    k=event_data[255:248];
    if(!seen_delivered[k]||event_data[223:192]>delivered[k])delivered[k]<=event_data[223:192];
    seen_delivered[k]<=1;
   end
   // Checkpoint is trusted only up to an already-delivered sequence. No auto eviction.
   freed=0;
   if(retire_valid&&retire_source<SOURCES&&retire_epoch==epoch&&seen_delivered[retire_source]
      &&retire_seq<=delivered[retire_source])begin
    retire_ok<=1;
    for(j=0;j<DEDUP;j=j+1)if(used[j]&&keys[j][63:56]==retire_source
       &&keys[j][55:32]==epoch&&keys[j][31:0]<=retire_seq)begin used[j]<=0;freed=freed+1;end
   end
   if(sensor_fire&&sensor_slot<SLOTS)begin
    valid_map[sensor_slot]<=sensor_known;
    if(sensor_known)begin
     occupied[sensor_slot]<=sensor_occupied;
     if(sensor_occupied&&admitted[sensor_slot])reserved[sensor_slot]<=0;
    end
   end
   if(fire)begin
    if(duplicate)dedup_hits<=dedup_hits+1'b1;
    else if(early_reject)begin
     if(early_status==CONFLICT)conflicts<=conflicts+1'b1;
     if(early_status==STALE)stale_count<=stale_count+1'b1;
    end else begin
     used[free_index]<=1;keys[free_index]<=id;payloads[free_index]<=payload;
     results[free_index]<=final_status;result_slots[free_index]<=final_slot;
     highwater[source]<=id[31:0];seen_seq[source]<=1;
     if(final_status==OK)case(op)
      0,5,7:begin reserved[final_slot]<=1;owner[final_slot]<=source;owner_tag[final_slot]<=tag;end
      1:begin admitted[slot]<=1;if(occupied[slot])reserved[slot]<=0;end
      2:reserved[slot]<=0;
      3:begin admitted[slot]<=0;reserved[slot]<=0;exit_pending[slot]<=0;end
      10:maintenance[slot]<=data[0];
      11:begin exit_pending[slot]<=1;exit_owner[slot]<=source;exit_tag[slot]<=tag;end
      default:begin end
     endcase
    end
   end
   if(fire&&!duplicate&&!early_reject)dedup_used<=dedup_used+1-freed;
   else if(freed>0)dedup_used<=dedup_used-freed;
  end
 end
endmodule
