`timescale 1ns/1ps
module tb_memory;
 parameter SLOTS=8,FIFO_DEPTH=8,DEDUP=16;
 reg clk=0;always #5 clk=~clk;
 reg [759:0] vector;integer cycle,rc,fi,fo;
 wire rst,run_enable;wire [23:0] epoch;
 wire [4:0] req_valid,req_ready;wire [319:0] req_id;
 wire [19:0] req_op;wire [79:0] req_slot,req_data,req_tag;
 wire sensor_valid,sensor_ready,sensor_known,sensor_occupied,event_ready,retire_valid,retire_ok;
 wire [15:0] sensor_slot;wire [63:0] sensor_id;wire [7:0] retire_source;wire [23:0] retire_epoch;wire [31:0] retire_seq;
 assign {rst,run_enable,epoch,
  req_valid[0],req_id[0+:64],req_op[0+:4],req_slot[0+:16],req_data[0+:16],req_tag[0+:16],
  req_valid[1],req_id[64+:64],req_op[4+:4],req_slot[16+:16],req_data[16+:16],req_tag[16+:16],
  req_valid[2],req_id[128+:64],req_op[8+:4],req_slot[32+:16],req_data[32+:16],req_tag[32+:16],
  req_valid[3],req_id[192+:64],req_op[12+:4],req_slot[48+:16],req_data[48+:16],req_tag[48+:16],
  req_valid[4],req_id[256+:64],req_op[16+:4],req_slot[64+:16],req_data[64+:16],req_tag[64+:16],
  sensor_valid,sensor_slot,sensor_known,sensor_occupied,sensor_id,event_ready,
  retire_valid,retire_source,retire_epoch,retire_seq}=vector;
 wire rsp_valid,online,overcommitted,event_valid,commit_valid;
 wire [63:0] rsp_id,commit_id;wire [3:0] rsp_op,commit_op;
 wire [7:0] rsp_source,rsp_status;wire [15:0] rsp_slot,rsp_tag,c_count,n_count,r_count,d_count,q_count,available;
 wire [SLOTS-1:0] occupied,valid_map,reserved,maintenance,admitted,exit_pending;
 wire [255:0] event_data;wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;
 wire [31:0] dedup_hits,conflicts,stale_count;wire [$clog2(DEDUP+1)-1:0] dedup_used;
 parking_engine #(SLOTS,5,3,FIFO_DEPTH,DEDUP) dut(
  .clk(clk),.rst(rst),.run_enable(run_enable),.epoch(epoch),.req_valid(req_valid),.req_ready(req_ready),
  .req_id(req_id),.req_op(req_op),.req_slot(req_slot),.req_data(req_data),.req_tag(req_tag),
  .sensor_valid(sensor_valid),.sensor_ready(sensor_ready),.sensor_slot(sensor_slot),.sensor_known(sensor_known),
  .sensor_occupied(sensor_occupied),.sensor_id(sensor_id),.retire_valid(retire_valid),.retire_source(retire_source),
  .retire_epoch(retire_epoch),.retire_seq(retire_seq),.retire_ok(retire_ok),
  .rsp_valid(rsp_valid),.rsp_id(rsp_id),.rsp_op(rsp_op),.rsp_source(rsp_source),.rsp_status(rsp_status),.rsp_slot(rsp_slot),.rsp_tag(rsp_tag),
  .c_count(c_count),.n_count(n_count),.r_count(r_count),.d_count(d_count),.q_count(q_count),.available(available),
  .online(online),.overcommitted(overcommitted),.occupied(occupied),.valid_map(valid_map),.reserved(reserved),
  .maintenance(maintenance),.admitted(admitted),.exit_pending(exit_pending),.event_valid(event_valid),
  .event_ready(event_ready),.event_data(event_data),.fifo_count(fifo_count),.dedup_hits(dedup_hits),
  .conflicts(conflicts),.stale_count(stale_count),.dedup_used(dedup_used),
  .commit_valid(commit_valid),.commit_op(commit_op),.commit_id(commit_id));
 reg [4:0] pre_ready;reg pre_ev,pre_sensor_ready;reg [255:0] pre_data;
 reg [4095:0] in_path,out_path,wave;
 `include "monitors/engine_checks.vh"
 initial begin
  vector=0;vector[759]=1;
  if(!$value$plusargs("INPUT=%s",in_path)||!$value$plusargs("OUTPUT=%s",out_path))$fatal(1,"missing paths");
  if($value$plusargs("WAVE=%s",wave))begin $dumpfile(wave);$dumpvars(0,tb_memory);end
  fi=$fopen(in_path,"r");fo=$fopen(out_path,"w");if(!fi||!fo)$fatal(1,"cannot open");
  $fwrite(fo,"cycle,ready,sensor_ready,event_valid_pre,event_data_pre,rsp_valid,rsp_id,rsp_op,rsp_source,rsp_status,rsp_slot,rsp_tag,c,n,r,d,q,available,online,overcommitted,occupied,valid,reserved,maintenance,admitted,exit_pending,fifo_count,dedup_used,dedup_hits,conflicts,stale_count,retire_ok,commit_valid,commit_op,commit_id\n");
  while(!$feof(fi))begin
   @(negedge clk);rc=$fscanf(fi,"%h %d\n",vector,cycle);if(rc!=2)$fatal(1,"bad vector");
   #1;pre_ready=req_ready;pre_ev=event_valid;pre_data=event_data;pre_sensor_ready=sensor_ready;
   @(posedge clk);#1;check_invariants();
   $fwrite(fo,"%0d,%h,%0d,%0d,%h,%0d,%h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%h,%h,%h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h\n",
    cycle,pre_ready,pre_sensor_ready,pre_ev,pre_data,rsp_valid,rsp_id,rsp_op,rsp_source,rsp_status,rsp_slot,rsp_tag,
    c_count,n_count,r_count,d_count,q_count,available,online,overcommitted,occupied,valid_map,reserved,maintenance,admitted,
    exit_pending,fifo_count,dedup_used,dedup_hits,conflicts,stale_count,retire_ok,commit_valid,commit_op,commit_id);
  end
  $fclose(fi);$fclose(fo);$finish;
 end
endmodule
