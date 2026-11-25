`timescale 1ns/1ps
module tb_parking_top;
 localparam SLOTS=8,FIFO_DEPTH=8,DEDUP=32;
 reg clk=0;always #500 clk=~clk;
 reg rst=1,run_enable=0;reg [23:0] epoch=1;
 reg [3:0] vehicle_async=0,ticket_ok=15,open_limit_async=0,close_limit_async=15;
 reg [3:0] passage_async=0,blocked_async=0,clear_async=15,cancel_verified=0,recovery_confirm=0;
 reg [7:0] entry_mode=0;reg [63:0] exit_slot=0;
 reg [7:0] echo_async=0;wire [7:0] trigger;wire [23:0] led_rgb;
 wire [3:0] open_cmd,close_cmd,fault,passage_pending,safety_stop;wire [11:0] gate_states;wire [63:0] assigned_slots;
 reg host_valid=0;wire host_ready;reg [63:0] host_id=0;reg [3:0] host_op=0;
 reg [15:0] host_slot=0,host_data=0,host_tag=0;integer host_seq=0;
 reg retire_valid=0;reg [7:0] retire_source=0;reg [23:0] retire_epoch=1;reg [31:0] retire_seq=0;wire retire_ok;
 wire rsp_valid,online,overcommitted,event_valid,commit_valid;
 wire [63:0] rsp_id,commit_id;wire [3:0] rsp_op,commit_op;
 wire [7:0] rsp_source,rsp_status;wire [15:0] rsp_slot,rsp_tag,c_count,n_count,r_count,d_count,q_count,available;
 wire [7:0] occupied,valid_map,reserved,maintenance,admitted;wire [7:0] exit_pending=dut.exit_pending;
 reg event_ready=1;wire [255:0] event_data;wire [3:0] fifo_count;wire [5:0] dedup_used;
 wire [31:0] dedup_hits,conflicts,stale_count;
 wire [7:0] sensor_known,sensor_occupied,sensor_status_pending;wire [127:0] sensor_echo_us,sensor_median_mm;
 parking_top #(.CLK_HZ(1000000),.SENSOR_GAP_US(100),.SENSOR_TIMEOUT_US(3000),
 .D_ON_MM(100),.D_OFF_MM(140),.CONFIRM(3),.GATE_TIMEOUT_CYCLES(100000)) dut(
 .clk(clk),
 .rst(rst),
 .run_enable(run_enable),
 .epoch(epoch),
 .vehicle_async(vehicle_async),
 .ticket_ok(ticket_ok),
 .open_limit_async(open_limit_async),
 .close_limit_async(close_limit_async),
 .passage_async(passage_async),
 .blocked_async(blocked_async),
 .clear_async(clear_async),
 .cancel_verified(cancel_verified),
 .recovery_confirm(recovery_confirm),
 .entry_mode(entry_mode),
 .exit_slot(exit_slot),
 .echo_async(echo_async),
 .trigger(trigger),
 .led_rgb(led_rgb),
 .open_cmd(open_cmd),
 .close_cmd(close_cmd),
 .fault(fault),
 .passage_pending(passage_pending),
 .safety_stop(safety_stop),
 .gate_states(gate_states),
 .assigned_slots(assigned_slots),
 .host_valid(host_valid),
 .host_ready(host_ready),
 .host_id(host_id),
 .host_op(host_op),
 .host_slot(host_slot),
 .host_data(host_data),
 .host_tag(host_tag),
 .retire_valid(retire_valid),
 .retire_source(retire_source),
 .retire_epoch(retire_epoch),
 .retire_seq(retire_seq),
 .retire_ok(retire_ok),
 .rsp_valid(rsp_valid),
 .rsp_id(rsp_id),
 .rsp_op(rsp_op),
 .rsp_source(rsp_source),
 .rsp_status(rsp_status),
 .rsp_slot(rsp_slot),
 .rsp_tag(rsp_tag),
 .c_count(c_count),
 .n_count(n_count),
 .r_count(r_count),
 .d_count(d_count),
 .q_count(q_count),
 .available(available),
 .online(online),
 .overcommitted(overcommitted),
 .occupied(occupied),
 .valid_map(valid_map),
 .reserved(reserved),
 .maintenance(maintenance),
 .admitted(admitted),
 .event_valid(event_valid),
 .event_ready(event_ready),
 .event_data(event_data),
 .fifo_count(fifo_count),
 .dedup_hits(dedup_hits),
 .conflicts(conflicts),
 .stale_count(stale_count),
 .dedup_used(dedup_used),
 .commit_valid(commit_valid),
 .commit_op(commit_op),
 .commit_id(commit_id),
 .sensor_known(sensor_known),
 .sensor_occupied(sensor_occupied),
 .sensor_status_pending(sensor_status_pending),
 .sensor_echo_us(sensor_echo_us),
 .sensor_median_mm(sensor_median_mm));
 integer widths[0:7];genvar g;
 generate for(g=0;g<8;g=g+1)begin: echo_models
  integer width;
  always @(negedge trigger[g])if(!rst)begin
   width=widths[g];repeat(20)@(negedge clk);
   if(width>0)begin echo_async[g]=1;repeat(width)@(negedge clk);echo_async[g]=0;end
  end
 end endgenerate
 wire [4:0] req_ready=dut.req_ready;
 wire sensor_ready=dut.mem_sensor_ready;
 reg [4:0] pre_ready;reg pre_ev,pre_sensor_ready;reg [255:0] pre_data;reg [759:0] pre_vector;
 integer cycle=0,fo,fm,testcase,j,guard;reg [2047:0] path,marks,wave;
 `include "monitors/engine_checks.vh"
 `include "tasks/top_tasks.vh"
 always @(posedge clk)begin
  pre_ready=req_ready;pre_ev=event_valid;pre_data=event_data;pre_sensor_ready=sensor_ready;
  pre_vector={rst,run_enable,epoch,
 dut.req_valid[0],dut.ids[0+:64],dut.ops[0+:4],dut.slots[0+:16],dut.datas[0+:16],dut.tags[0+:16],
 dut.req_valid[1],dut.ids[64+:64],dut.ops[4+:4],dut.slots[16+:16],dut.datas[16+:16],dut.tags[16+:16],
 dut.req_valid[2],dut.ids[128+:64],dut.ops[8+:4],dut.slots[32+:16],dut.datas[32+:16],dut.tags[32+:16],
 dut.req_valid[3],dut.ids[192+:64],dut.ops[12+:4],dut.slots[48+:16],dut.datas[48+:16],dut.tags[48+:16],
 dut.req_valid[4],dut.ids[256+:64],dut.ops[16+:4],dut.slots[64+:16],dut.datas[64+:16],dut.tags[64+:16],
 dut.found_sensor,dut.selected_sensor,sensor_known[dut.selection],sensor_occupied[dut.selection],
 {8'hfe,epoch,dut.sensor_sequence},event_ready,retire_valid,retire_source,retire_epoch,retire_seq};
  #2;check_invariants();
  if(!rst&&(close_cmd&dut.blocked)!=0)$fatal(1,"top unsafe close");
   if(cycle>0)$fwrite(fo,"%0d,%h,%0d,%0d,%h,%0d,%h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%h,%h,%h,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%h,%h,%h,%h,%h\n",
    cycle,pre_ready,pre_sensor_ready,pre_ev,pre_data,rsp_valid,rsp_id,rsp_op,rsp_source,rsp_status,rsp_slot,rsp_tag,
    c_count,n_count,r_count,d_count,q_count,available,online,overcommitted,occupied,valid_map,reserved,maintenance,admitted,
    exit_pending,fifo_count,dedup_used,dedup_hits,conflicts,stale_count,retire_ok,commit_valid,commit_op,commit_id,pre_vector,gate_states,open_cmd,close_cmd,passage_pending,dut.blocked,blocked_async);
  cycle=cycle+1;if(cycle>150000)$fatal(1,"top watchdog case %0d",testcase);
 end
 initial begin
  if(!$value$plusargs("CASE=%d",testcase)||!$value$plusargs("OUTPUT=%s",path)||!$value$plusargs("MARKS=%s",marks))$fatal;
  fo=$fopen(path,"w");fm=$fopen(marks,"w");
  $fwrite(fo,"cycle,ready,sensor_ready,event_valid_pre,event_data_pre,rsp_valid,rsp_id,rsp_op,rsp_source,rsp_status,rsp_slot,rsp_tag,c,n,r,d,q,available,online,overcommitted,occupied,valid,reserved,maintenance,admitted,exit_pending,fifo_count,dedup_used,dedup_hits,conflicts,stale_count,retire_ok,commit_valid,commit_op,commit_id,input_vector,states,open,close,pending,blocked_sync,raw_blocked\n");
  $fdisplay(fm,"milestone,c,n,r,d,q,occupied,valid,reserved");
  if($value$plusargs("WAVE=%s",wave))begin
   $dumpfile(wave);$dumpvars(1,tb_parking_top);$dumpvars(1,dut);
  end
  for(j=0;j<8;j=j+1)widths[j]=1200;
  cycles(4);@(negedge clk);rst=0;run_enable=1;recovery_confirm=15;
  cycles(8);@(negedge clk);recovery_confirm=0;
  guard=0;while(valid_map!=255)begin tick;guard=guard+1;if(guard>20000)$fatal(1,"cold sensor");end
  milestone("ready");
  case(testcase)
   1:begin
    enter(0);milestone("entered");widths[0]=200;wait_occupied(0,1);milestone("parked");
    widths[0]=1200;wait_occupied(0,0);milestone("left_slot");
    exit_slot[48+:16]=0;enter(3);milestone("exited");
   end
   2:begin
    host_command(9,0,1,0);for(j=1;j<8;j=j+1)host_command(10,j,1,0);
    @(negedge clk);vehicle_async=7;cycles(15);
    if(r_count!=1||$countones(open_cmd)!=1)$fatal(1,"last slot double grant");
    milestone("one_grant");
   end
   3:begin
    request_open(0);open_barrier(0);
    @(negedge clk);event_ready=0;
    for(j=0;j<8;j=j+1)host_command(15,0,j,0);
    pass_barrier(0);cycles(5);if(n_count!=0||r_count!=1||!passage_pending[0])$fatal(1,"lost blocked event");
    milestone("fifo_stalled");
    @(negedge clk);blocked_async[0]=1;cycles(4);
    if(close_cmd[0]||!open_cmd[0])$fatal(1,"obstacle host dependence");milestone("obstacle");
    @(negedge clk);blocked_async[0]=0;cycles(5);
    @(negedge clk);open_limit_async[0]=1;cycles(5);
    @(negedge clk);close_limit_async[0]=1;open_limit_async[0]=0;event_ready=1;cycles(15);
    if(gate_states[0+:3]!=0)$fatal(1,"barrier did not finish reclose");
    if(n_count!=1||r_count!=0)$fatal(1,"passage not recovered");milestone("event_recovered");
   end
   4:begin
    host_command(6,0,1,0);host_command(6,0,1,1);if(q_count!=1||dedup_hits!=1)$fatal(1,"quota replay");
    host_command(8,0,0,0);entry_mode[4+:2]=2;enter(2);milestone("offline_entered");
    entry_mode[2+:2]=2;@(negedge clk);vehicle_async[1]=1;cycles(15);
    if(open_cmd[1]||r_count!=0||q_count!=0)$fatal(1,"offline exhausted");milestone("quota_empty");
    host_command(8,0,1,0);milestone("reconnected");
   end
   5:begin
    host_command(4,0,2,0);entry_mode[2+:2]=1;enter(1);milestone("booked_entered");
    host_command(12,0,1,0);milestone("booking_cancelled");
   end
   6:begin
    @(negedge clk);vehicle_async=7;cycles(15);if(r_count!=3)$fatal(1,"three sessions");
    @(negedge clk);close_limit_async=8;open_limit_async=7;cycles(5);
    @(negedge clk);passage_async=7;cycles(5);@(negedge clk);passage_async=0;
    cycles(10);if(n_count!=3||r_count!=0)$fatal(1,"simultaneous passages lost");milestone("three_entered");
   end
   7:begin
    request_open(0);milestone("before_reset");@(negedge clk);rst=1;run_enable=0;epoch=2;
    cycles(3);if(fault!=15||valid_map!=0||n_count!=0||r_count!=0||open_cmd||close_cmd)$fatal(1,"reset recovery");
    milestone("reset_locked");
   end
   8:begin
    @(negedge clk);ticket_ok[0]=0;vehicle_async[0]=1;cycles(20);
    if(open_cmd[0]||n_count!=0||r_count!=0)$fatal(1,"invalid ticket opened gate");
    milestone("ticket_denied");
   end
  endcase
  cycles(8);@(negedge clk);$fclose(fo);$fclose(fm);$display("PASS top case=%0d cycles=%0d",testcase,cycle);$finish;
 end
endmodule
