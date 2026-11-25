`timescale 1ns/1ps
module gate_node_fsm #(
 parameter SOURCE=0,IS_EXIT=0,TIMEOUT_CYCLES=100000000
)(
 input wire clk,rst,input wire [23:0] epoch,
 input wire vehicle_detect,ticket_ok,input wire [1:0] entry_mode,input wire [15:0] exit_slot,
 input wire open_limit,close_limit,passage_detected,safety_blocked,clear_stable,
 input wire cancel_verified,recovery_confirm,
 output wire request_valid,input wire request_ready,
 output wire [63:0] request_id,output wire [3:0] request_op,
 output wire [15:0] request_slot,request_data,request_tag,
 input wire authorization_valid,input wire [63:0] authorization_id,
 input wire [3:0] authorization_op,input wire [7:0] authorization_status,
 input wire [15:0] authorization_slot,authorization_tag,
 output wire open_cmd,close_cmd,fault,
 output reg [2:0] state_debug,output reg [15:0] assigned_slot,session_tag,
 output wire passage_pending_debug,output reg safety_stop_pulse
);
 localparam IDLE=0,WAIT_AUTH=1,OPENING=2,WAIT_PASS=3,CLOSING=4,FAULT=5;
 reg armed,req_sent,passed,pass_pending,cancel_pending,permit,cancel_issued;
 reg [1:0] mode;reg [15:0] exit_slot_latched;
 reg [31:0] seq,timer;reg [2:0] previous_state;
 reg [63:0] auth_request_id,motion_request_id;
 wire request_phase=(state_debug==WAIT_AUTH&&!req_sent);
 assign request_valid=pass_pending||cancel_pending||request_phase;
 assign request_id={SOURCE[7:0],epoch,seq};
 assign request_tag=session_tag;
 assign request_op=pass_pending?(IS_EXIT?4'd3:4'd1):cancel_pending?4'd2:
                   IS_EXIT?4'd11:mode==1?4'd5:mode==2?4'd7:4'd0;
 assign request_slot=request_phase?(IS_EXIT?exit_slot_latched:16'hffff):assigned_slot;
 assign request_data=request_phase?{15'h0,permit}:16'h1;
 assign open_cmd=(state_debug==OPENING)&&!cancel_pending&&!rst;
 assign close_cmd=(state_debug==CLOSING)&&!safety_blocked&&!rst;
 assign fault=(state_debug==FAULT);
 assign passage_pending_debug=pass_pending;
 wire fire=request_valid&&request_ready;
 always @(posedge clk)begin
  if(rst)begin
   state_debug<=FAULT;previous_state<=FAULT;armed<=1;req_sent<=0;passed<=0;
   pass_pending<=0;cancel_pending<=0;cancel_issued<=0;permit<=0;mode<=0;exit_slot_latched<=0;
   seq<=1;timer<=0;assigned_slot<=16'hffff;session_tag<=0;auth_request_id<=0;motion_request_id<=0;safety_stop_pulse<=0;
  end else begin
   safety_stop_pulse<=0;previous_state<=state_debug;
   if(state_debug!=previous_state||state_debug==IDLE||state_debug==FAULT)timer<=0;else timer<=timer+1'b1;
   if(!vehicle_detect)armed<=1;
   if(fire)begin
    seq<=seq+1'b1;
    if(pass_pending)begin pass_pending<=0;motion_request_id<=request_id;end
    else if(cancel_pending)begin cancel_pending<=0;motion_request_id<=request_id;end
    else if(request_phase)begin req_sent<=1;auth_request_id<=request_id;end
   end
   // Passage is latched before considering cancellation; motion never waits for host/FIFO.
   if(state_debug==WAIT_PASS&&passage_detected&&!passed)begin passed<=1;pass_pending<=1;end
   else if(!IS_EXIT&&(state_debug==OPENING||state_debug==WAIT_PASS)&&cancel_verified&&!passed&&!cancel_issued)begin
    cancel_pending<=1;cancel_issued<=1;
   end
   case(state_debug)
    IDLE:if(vehicle_detect&&armed&&!pass_pending&&!cancel_pending)begin
     armed<=0;req_sent<=0;passed<=0;cancel_issued<=0;session_tag<=session_tag+1'b1;
     permit<=ticket_ok;mode<=entry_mode;exit_slot_latched<=exit_slot;state_debug<=WAIT_AUTH;
    end
    WAIT_AUTH:begin end
    OPENING:if(open_limit)state_debug<=WAIT_PASS;
    WAIT_PASS:if((passed||passage_detected)&&clear_stable&&!safety_blocked)state_debug<=CLOSING;
    CLOSING:begin
     if(safety_blocked)begin state_debug<=OPENING;safety_stop_pulse<=1;end
     else if(close_limit)state_debug<=IDLE;
    end
    FAULT:if(recovery_confirm&&close_limit&&clear_stable&&!safety_blocked&&!vehicle_detect&&!pass_pending&&!cancel_pending)begin
     state_debug<=IDLE;req_sent<=0;
    end
    default:state_debug<=FAULT;
   endcase
   // Responses take priority over ordinary limit transitions.
   if(authorization_valid&&authorization_tag==session_tag)begin
    if(state_debug==WAIT_AUTH&&req_sent&&authorization_id==auth_request_id)begin
     if(authorization_status==0)begin assigned_slot<=authorization_slot;state_debug<=OPENING;end
     else state_debug<=IDLE;
    end else if(authorization_op==2&&authorization_id==motion_request_id)begin
     if(authorization_status==0&&clear_stable&&!safety_blocked)state_debug<=CLOSING;
     else if(authorization_status!=0)state_debug<=FAULT;
    end else if((authorization_op==1||authorization_op==3)&&authorization_id==motion_request_id&&authorization_status!=0)state_debug<=FAULT;
   end
   if(state_debug!=IDLE&&state_debug!=FAULT&&timer>=TIMEOUT_CYCLES-1)state_debug<=FAULT;
  end
 end
endmodule
