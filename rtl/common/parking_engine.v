`timescale 1ns/1ps
// Wires the two main state owners without a combinational ready loop.
module parking_engine #(parameter SLOTS=8,PORTS=5,ENTRY_GATES=3,FIFO_DEPTH=8,DEDUP=16)(
 input wire clk,rst,run_enable,input wire [23:0] epoch,
 input wire [PORTS-1:0] req_valid,output wire [PORTS-1:0] req_ready,
 input wire [PORTS*64-1:0] req_id,input wire [PORTS*4-1:0] req_op,
 input wire [PORTS*16-1:0] req_slot,req_data,req_tag,
 input wire sensor_valid,output wire sensor_ready,input wire [15:0] sensor_slot,
 input wire sensor_known,sensor_occupied,input wire [63:0] sensor_id,
 input wire retire_valid,input wire [7:0] retire_source,input wire [23:0] retire_epoch,
 input wire [31:0] retire_seq,output wire retire_ok,
 output wire rsp_valid,output wire [63:0] rsp_id,output wire [3:0] rsp_op,
 output wire [7:0] rsp_source,rsp_status,output wire [15:0] rsp_slot,rsp_tag,
 output wire [15:0] c_count,n_count,r_count,d_count,q_count,available,
 output wire online,overcommitted,
 output wire [SLOTS-1:0] occupied,valid_map,reserved,maintenance,admitted,exit_pending,
 output wire event_valid,input wire event_ready,output wire [255:0] event_data,
 output wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_count,
 output wire [31:0] dedup_hits,conflicts,stale_count,
 output wire [$clog2(DEDUP+1)-1:0] dedup_used,
 output wire commit_valid,output wire [3:0] commit_op,output wire [63:0] commit_id
);
 wire probe_valid,mem_ready,duplicate,early_reject,candidate_ok,fire;
 wire [63:0] id;wire [3:0] op;wire [15:0] slot,data,tag,candidate_slot,cached_slot,final_slot;
 wire [7:0] source,candidate_status,early_status,cached_status,final_status;
 wire [15:0] c_next,n_next,r_next,d_next,q_next;
 central_arbiter #(SLOTS,PORTS,ENTRY_GATES) central(
  .clk(clk),.rst(rst),.run_enable(run_enable),.req_valid(req_valid),.req_ready(req_ready),
  .req_id(req_id),.req_op(req_op),.req_slot(req_slot),.req_data(req_data),.req_tag(req_tag),
  .probe_valid(probe_valid),.id(id),.op(op),.slot(slot),.data(data),.tag(tag),.source(source),
  .mem_ready(mem_ready),.duplicate(duplicate),.early_reject(early_reject),.candidate_ok(candidate_ok),
  .candidate_status(candidate_status),.early_status(early_status),.cached_status(cached_status),
  .candidate_slot(candidate_slot),.cached_slot(cached_slot),.fire(fire),.final_status(final_status),.final_slot(final_slot),
  .c_next(c_next),.n_next(n_next),.r_next(r_next),.d_next(d_next),.q_next(q_next),
  .c_count(c_count),.n_count(n_count),.r_count(r_count),.d_count(d_count),.q_count(q_count),
  .online(online),.available(available),.overcommitted(overcommitted),
  .rsp_valid(rsp_valid),.rsp_id(rsp_id),.rsp_op(rsp_op),.rsp_source(rsp_source),.rsp_status(rsp_status),
  .rsp_slot(rsp_slot),.rsp_tag(rsp_tag),.commit_valid(commit_valid),.commit_op(commit_op),.commit_id(commit_id));
 parking_mem_opt #(SLOTS,PORTS,FIFO_DEPTH,DEDUP) memory(
  .clk(clk),.rst(rst),.epoch(epoch),.probe_valid(probe_valid),.id(id),.op(op),.slot(slot),.data(data),.tag(tag),.source(source),
  .ready(mem_ready),.duplicate(duplicate),.early_reject(early_reject),.candidate_ok(candidate_ok),
  .candidate_status(candidate_status),.early_status(early_status),.cached_status(cached_status),
  .candidate_slot(candidate_slot),.cached_slot(cached_slot),.fire(fire),.final_status(final_status),.final_slot(final_slot),
  .c_next(c_next),.n_next(n_next),.r_next(r_next),.d_next(d_next),.q_next(q_next),
  .sensor_valid(sensor_valid),.sensor_ready(sensor_ready),.sensor_slot(sensor_slot),
  .sensor_known(sensor_known),.sensor_occupied(sensor_occupied),.sensor_id(sensor_id),
  .c_now(c_count),.n_now(n_count),.r_now(r_count),.d_now(d_count),.q_now(q_count),
  .retire_valid(retire_valid),.retire_source(retire_source),.retire_epoch(retire_epoch),.retire_seq(retire_seq),.retire_ok(retire_ok),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.fifo_count(fifo_count),
  .occupied(occupied),.valid_map(valid_map),.reserved(reserved),.maintenance(maintenance),.admitted(admitted),.exit_pending(exit_pending),
  .dedup_hits(dedup_hits),.conflicts(conflicts),.stale_count(stale_count),.dedup_used(dedup_used));
endmodule
