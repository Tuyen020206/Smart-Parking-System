`timescale 1ns/1ps
module tb_gate;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,vehicle=0,ticket=1,opened=0,closed=1,passage=0,blocked=0,clear=1,cancel=0,recover=0;
 reg ready=0,auth=0;reg [63:0] auth_id=0;reg [3:0] auth_op=0;reg [7:0] auth_status=0;reg [15:0] auth_tag=0;
 wire valid,open_cmd,close_cmd,fault,pending,stop;wire [63:0] req_id;wire [3:0] req_op;
 wire [15:0] req_slot,req_data,req_tag,assigned,session;wire [2:0] state;
 gate_node_fsm #(0,0,80) dut(clk,rst,24'd1,vehicle,ticket,2'd0,16'd0,opened,closed,passage,blocked,clear,cancel,recover,
 valid,ready,req_id,req_op,req_slot,req_data,req_tag,auth,auth_id,auth_op,auth_status,16'd0,auth_tag,
 open_cmd,close_cmd,fault,state,assigned,session,pending,stop);
 integer testcase,fo,fm,cycle=0,accepts=0;reg [2047:0] path,marks,wave;
 reg [63:0] saved_id,pass_id;reg [15:0] saved_tag;
 `include "tasks/gate_tasks.vh"
 always @(posedge clk)begin
  if(!rst&&valid&&ready)accepts=accepts+1;
  #2;cycle=cycle+1;
  if(!rst&&blocked&&close_cmd)$fatal(1,"unsafe close");
  $fdisplay(fo,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0h,%0d",cycle,state,vehicle,passage,blocked,open_cmd,close_cmd,pending,valid,ready,req_op,req_id,stop);
  if(cycle>2000)$fatal(1,"gate watchdog");
 end
 initial begin
  if(!$value$plusargs("CASE=%d",testcase))$fatal;
  if(!$value$plusargs("OUTPUT=%s",path))$fatal;
  if(!$value$plusargs("MARKS=%s",marks))$fatal;
  fo=$fopen(path,"w");fm=$fopen(marks,"w");
  $fdisplay(fo,"cycle,state,vehicle,passage,blocked,open,close,pending,valid,ready,op,id,stop");
  $fdisplay(fm,"milestone,state,open,close,pending");
  if($value$plusargs("WAVE=%s",wave))begin $dumpfile(wave);$dumpvars(0,tb_gate);end
  reset_system;milestone("recovered");
  case(testcase)
   1:begin
    grant;milestone("granted");opened_barrier;send_passage;milestone("passed");
    @(negedge clk);ready=1;tick;@(negedge clk);ready=0;closed=1;opened=0;tick;
    milestone("closed");cycles(5);expect_state(0);if(accepts!=2)$fatal(1,"held vehicle repeated");
   end
   2:begin request_entry;reply(1,saved_tag,saved_id,0);milestone("denied");expect_state(0);end
   3:begin
    request_entry;reply(0,saved_tag+1,saved_id,0);milestone("wrong_tag");expect_state(1);
    reply(0,saved_tag,saved_id+1,0);milestone("wrong_id");expect_state(1);
    reply(0,saved_tag,saved_id,0);milestone("correct");expect_state(2);
   end
   4:begin
    grant;opened_barrier;send_passage;pass_id=req_id;milestone("stalled_passage");
    cycles(8);if(!pending||req_id!=pass_id||req_op!=1)$fatal(1,"lost stalled passage");
    @(negedge clk);blocked=1;#1;if(close_cmd)$fatal(1,"interlock late");tick;
    milestone("obstacle");expect_state(2);
    @(negedge clk);blocked=0;tick;expect_state(3);tick;expect_state(4);
    @(negedge clk);ready=1;tick;@(negedge clk);ready=0;closed=1;tick;cycles(3);
    milestone("delivered_once");if(accepts!=2)$fatal(1,"passage repeated");
   end
   5:begin
    grant;opened_barrier;@(negedge clk);cancel=1;tick;
    if(req_op!=2||!valid)$fatal(1,"cancel request");
    @(negedge clk);ready=1;pass_id=req_id;tick;@(negedge clk);ready=0;
    reply(0,saved_tag,pass_id,2);milestone("cancelled");expect_state(4);cycles(4);
    if(valid||accepts!=2)$fatal(1,"cancel repeated");
   end
   6:begin grant;cycles(85);milestone("opening_timeout");expect_state(5);end
   7:begin grant;opened_barrier;send_passage;cycles(85);milestone("closing_timeout");expect_state(5);end
   8:begin grant;@(negedge clk);rst=1;tick;milestone("reset_active");expect_state(5);end
   9:begin
    grant;opened_barrier;@(negedge clk);passage=1;cancel=1;tick;
    milestone("passage_wins");if(!pending||req_op!=1)$fatal(1,"cancel over passage");
   end
   10:begin request_entry;cycles(85);milestone("authorization_timeout");expect_state(5);end
  endcase
  @(negedge clk);$fclose(fo);$fclose(fm);$display("PASS gate case=%0d cycles=%0d",testcase,cycle);$finish;
 end
endmodule
