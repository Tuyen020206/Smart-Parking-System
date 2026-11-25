`timescale 1ns/1ps
module parking_top #(
 parameter SLOTS=8,ENTRY_GATES=3,GATES=4,CLK_HZ=50000000,FIFO_DEPTH=8,DEDUP=32,
 parameter SENSOR_GAP_US=60000,SENSOR_TIMEOUT_US=30000,D_ON_MM=1000,D_OFF_MM=1200,CONFIRM=3,
 parameter GATE_TIMEOUT_CYCLES=100000000
)(
 input wire clk,rst,run_enable,input wire [23:0] epoch,
 input wire [GATES-1:0] vehicle_async,ticket_ok,open_limit_async,close_limit_async,
 input wire [GATES-1:0] passage_async,blocked_async,clear_async,cancel_verified,recovery_confirm,
 input wire [GATES*2-1:0] entry_mode,input wire [GATES*16-1:0] exit_slot,
 input wire [SLOTS-1:0] echo_async,output wire [SLOTS-1:0] trigger,
 output wire [SLOTS*3-1:0] led_rgb,
 output wire [GATES-1:0] open_cmd,close_cmd,fault,passage_pending,safety_stop,
 output wire [GATES*3-1:0] gate_states,output wire [GATES*16-1:0] assigned_slots,
 input wire host_valid,output wire host_ready,input wire [63:0] host_id,
 input wire [3:0] host_op,input wire [15:0] host_slot,host_data,host_tag,
 input wire retire_valid,input wire [7:0] retire_source,input wire [23:0] retire_epoch,
 input wire [31:0] retire_seq,output wire retire_ok,
 output wire rsp_valid,output wire [63:0] rsp_id,output wire [3:0] rsp_op,
 output wire [7:0] rsp_source,rsp_status,output wire [15:0] rsp_slot,rsp_tag,
 output wire [15:0] c_count,n_count,r_count,d_count,q_count,available,
 output wire online,overcommitted,
 output wire [SLOTS-1:0] occupied,valid_map,reserved,maintenance,admitted,
 output wire event_valid,input wire event_ready,output wire [255:0] event_data,
 output wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_count,
 output wire [31:0] dedup_hits,conflicts,stale_count,
 output wire [$clog2(DEDUP+1)-1:0] dedup_used,
 output wire commit_valid,output wire [3:0] commit_op,output wire [63:0] commit_id,
 output wire [SLOTS-1:0] sensor_known,sensor_occupied,sensor_status_pending,
 output wire [SLOTS*16-1:0] sensor_echo_us,sensor_median_mm
);
 localparam PORTS=GATES+1;
 wire [GATES-1:0] vehicle,opened,closed,passed,blocked,clear;
 sync_bits #(GATES,0) s0(clk,rst,vehicle_async,vehicle);
 sync_bits #(GATES,0) s1(clk,rst,open_limit_async,opened);
 sync_bits #(GATES,0) s2(clk,rst,close_limit_async,closed);
 sync_bits #(GATES,0) s3(clk,rst,passage_async,passed);
 sync_bits #(GATES,0) s4(clk,rst,blocked_async,blocked);
 sync_bits #(GATES,0) s5(clk,rst,clear_async,clear);
 wire [PORTS-1:0] req_valid,req_ready;
 wire [PORTS*64-1:0] ids;wire [PORTS*4-1:0] ops;
 wire [PORTS*16-1:0] slots,datas,tags;
 assign req_valid[GATES]=host_valid;assign host_ready=req_ready[GATES];
 assign ids[GATES*64+:64]=host_id;assign ops[GATES*4+:4]=host_op;
 assign slots[GATES*16+:16]=host_slot;assign datas[GATES*16+:16]=host_data;assign tags[GATES*16+:16]=host_tag;
 genvar g;
 generate for(g=0;g<GATES;g=g+1)begin: gates
  gate_node_fsm #(g,g>=ENTRY_GATES,GATE_TIMEOUT_CYCLES) gate(
   .clk(clk),.rst(rst),.epoch(epoch),.vehicle_detect(vehicle[g]),.ticket_ok(ticket_ok[g]),
   .entry_mode(entry_mode[g*2+:2]),.exit_slot(exit_slot[g*16+:16]),
   .open_limit(opened[g]),.close_limit(closed[g]),.passage_detected(passed[g]),
   .safety_blocked(blocked[g]),.clear_stable(clear[g]),.cancel_verified(cancel_verified[g]),.recovery_confirm(recovery_confirm[g]),
   .request_valid(req_valid[g]),.request_ready(req_ready[g]),.request_id(ids[g*64+:64]),
   .request_op(ops[g*4+:4]),.request_slot(slots[g*16+:16]),.request_data(datas[g*16+:16]),.request_tag(tags[g*16+:16]),
   .authorization_valid(rsp_valid&&rsp_source==g),.authorization_id(rsp_id),.authorization_op(rsp_op),
   .authorization_status(rsp_status),.authorization_slot(rsp_slot),.authorization_tag(rsp_tag),
   .open_cmd(open_cmd[g]),.close_cmd(close_cmd[g]),.fault(fault[g]),.state_debug(gate_states[g*3+:3]),
   .assigned_slot(assigned_slots[g*16+:16]),.session_tag(),.passage_pending_debug(passage_pending[g]),.safety_stop_pulse(safety_stop[g]));
 end endgenerate
 wire [SLOTS-1:0] sensor_ready;
 generate for(g=0;g<SLOTS;g=g+1)begin: sensors
  wire [2:0] raw_led;
  slot_node_sensor #(CLK_HZ,10,SENSOR_GAP_US,SENSOR_TIMEOUT_US,50,D_ON_MM,D_OFF_MM,CONFIRM) node(
   .clk(clk),.rst(rst),.echo_async(echo_async[g]),.trigger(trigger[g]),
   .known(sensor_known[g]),.occupied(sensor_occupied[g]),.led_rgb(raw_led),
   .status_valid(sensor_status_pending[g]),.status_ready(sensor_ready[g]),
   .echo_us(sensor_echo_us[g*16+:16]),.median_mm(sensor_median_mm[g*16+:16]),
   .sample_count(),.sample_pulse(),.timeout_pulse(),.echo_sync_debug());
  assign led_rgb[g*3+:3]=!valid_map[g]?3'b110:(maintenance[g]||reserved[g])?3'b110:raw_led;
 end endgenerate
 integer k,selection;reg found_sensor;reg [SLOTS-1:0] ack_sensor;
 reg [15:0] selected_sensor;wire mem_sensor_ready;reg [31:0] sensor_sequence;
 always @*begin
  found_sensor=0;selection=0;
  for(k=0;k<SLOTS;k=k+1)if(!found_sensor&&sensor_status_pending[k])begin found_sensor=1;selection=k;end
  selected_sensor=selection;ack_sensor=0;
  if(found_sensor&&mem_sensor_ready)ack_sensor[selection]=1;
 end
 assign sensor_ready=ack_sensor;
 always @(posedge clk)if(rst)sensor_sequence<=1;else if(found_sensor&&mem_sensor_ready)sensor_sequence<=sensor_sequence+1'b1;
 wire [SLOTS-1:0] exit_pending;
 parking_engine #(SLOTS,PORTS,ENTRY_GATES,FIFO_DEPTH,DEDUP) engine(
  .clk(clk),.rst(rst),.run_enable(run_enable),.epoch(epoch),.req_valid(req_valid),.req_ready(req_ready),
  .req_id(ids),.req_op(ops),.req_slot(slots),.req_data(datas),.req_tag(tags),
  .sensor_valid(found_sensor),.sensor_ready(mem_sensor_ready),.sensor_slot(selected_sensor),
  .sensor_known(sensor_known[selection]),.sensor_occupied(sensor_occupied[selection]),.sensor_id({8'hfe,epoch,sensor_sequence}),
  .retire_valid(retire_valid),.retire_source(retire_source),.retire_epoch(retire_epoch),.retire_seq(retire_seq),.retire_ok(retire_ok),
  .rsp_valid(rsp_valid),.rsp_id(rsp_id),.rsp_op(rsp_op),.rsp_source(rsp_source),.rsp_status(rsp_status),.rsp_slot(rsp_slot),.rsp_tag(rsp_tag),
  .c_count(c_count),.n_count(n_count),.r_count(r_count),.d_count(d_count),.q_count(q_count),.available(available),
  .online(online),.overcommitted(overcommitted),.occupied(occupied),.valid_map(valid_map),.reserved(reserved),
  .maintenance(maintenance),.admitted(admitted),.exit_pending(exit_pending),
  .event_valid(event_valid),.event_ready(event_ready),.event_data(event_data),.fifo_count(fifo_count),
  .dedup_hits(dedup_hits),.conflicts(conflicts),.stale_count(stale_count),.dedup_used(dedup_used),
  .commit_valid(commit_valid),.commit_op(commit_op),.commit_id(commit_id));
endmodule
