`timescale 1ns/1ps
// Registered outgoing transaction holds valid/payload through timeout/backpressure.
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
 reg armed,passed,pass_pending,cancel_pending,cancel_issued,cancel_done;
 reg auth_wait,motion_wait,owns_grant;
 reg [31:0] seq,timer;reg [2:0] previous_state;
 reg [63:0] auth_request_id,motion_request_id;reg [3:0] auth_request_op,motion_request_op;
 reg tx_valid;reg [63:0] tx_id;reg [3:0] tx_op;reg [15:0] tx_slot,tx_data,tx_tag;
 assign request_valid=tx_valid&&!rst;
 assign request_id=tx_id;assign request_op=tx_op;
 assign request_slot=tx_slot;assign request_data=tx_data;assign request_tag=tx_tag;
 assign open_cmd=(state_debug==OPENING)&&!cancel_issued&&!rst;
 assign close_cmd=(state_debug==CLOSING)&&!safety_blocked&&!rst;
 assign fault=(state_debug==FAULT);
 assign passage_pending_debug=pass_pending;
 wire fire=request_valid&&request_ready;
 always @(posedge clk)begin
  if(rst)begin
   state_debug<=FAULT;previous_state<=FAULT;armed<=1;passed<=0;pass_pending<=0;
   cancel_pending<=0;cancel_issued<=0;cancel_done<=0;auth_wait<=0;motion_wait<=0;owns_grant<=0;
   seq<=1;timer<=0;assigned_slot<=16'hffff;session_tag<=0;safety_stop_pulse<=0;
   auth_request_id<=0;motion_request_id<=0;auth_request_op<=0;motion_request_op<=0;
   tx_valid<=0;tx_id<=0;tx_op<=0;tx_slot<=16'hffff;tx_data<=0;tx_tag<=0;
  end else begin
   safety_stop_pulse<=0;previous_state<=state_debug;
   if(state_debug!=previous_state||state_debug==IDLE||state_debug==FAULT)timer<=0;else timer<=timer+1'b1;
   if(!vehicle_detect)armed<=1;
   if(fire)begin
    tx_valid<=0;
    if(tx_op==0||tx_op==5||tx_op==7||tx_op==11)begin
     auth_wait<=1;auth_request_id<=tx_id;auth_request_op<=tx_op;
    end else begin
     motion_wait<=1;motion_request_id<=tx_id;motion_request_op<=tx_op;
     if(tx_op==2)cancel_pending<=0;else pass_pending<=0;
    end
   end
   // A verified cancel assumes the vehicle cannot subsequently pass.
   if(state_debug==WAIT_PASS&&passage_detected&&!passed)begin
    if(cancel_issued)state_debug<=FAULT;
    else begin passed<=1;pass_pending<=1;end
   end else if(!IS_EXIT&&cancel_verified&&!passed&&!cancel_issued&&owns_grant&&
      (state_debug==OPENING||state_debug==WAIT_PASS||state_debug==FAULT))begin
    cancel_pending<=1;cancel_issued<=1;
   end
   if(!tx_valid&&!auth_wait&&!motion_wait&&(pass_pending||cancel_pending))begin
    tx_valid<=1;tx_id<={SOURCE[7:0],epoch,seq};seq<=seq+1'b1;
    tx_op<=pass_pending?(IS_EXIT?4'd3:4'd1):4'd2;
    tx_slot<=assigned_slot;tx_data<=1;tx_tag<=session_tag;
   end
   case(state_debug)
    IDLE:if(vehicle_detect&&armed&&!tx_valid&&!auth_wait&&!motion_wait&&
             !pass_pending&&!cancel_pending&&!owns_grant)begin
     armed<=0;passed<=0;cancel_issued<=0;cancel_done<=0;session_tag<=session_tag+1'b1;
     assigned_slot<=16'hffff;state_debug<=WAIT_AUTH;
     tx_valid<=1;tx_id<={SOURCE[7:0],epoch,seq};seq<=seq+1'b1;
     tx_op<=IS_EXIT?4'd11:entry_mode==1?4'd5:entry_mode==2?4'd7:4'd0;
     tx_slot<=IS_EXIT?exit_slot:16'hffff;tx_data<={15'h0,ticket_ok};tx_tag<=session_tag+1'b1;
    end
    WAIT_AUTH:begin end
    OPENING:if(open_limit&&!cancel_issued)state_debug<=WAIT_PASS;
    WAIT_PASS:if(!cancel_issued&&(passed||passage_detected)&&clear_stable&&!safety_blocked)state_debug<=CLOSING;
    CLOSING:begin
     if(safety_blocked)begin state_debug<=OPENING;safety_stop_pulse<=1;end
     else if(close_limit)state_debug<=IDLE;
    end
    FAULT:if(recovery_confirm&&close_limit&&clear_stable&&!safety_blocked&&!vehicle_detect&&
              !tx_valid&&!auth_wait&&!motion_wait&&!owns_grant&&!pass_pending&&!cancel_pending)state_debug<=IDLE;
    default:state_debug<=FAULT;
   endcase
   // A cancel ACK is sticky until the region becomes clear.
   if(cancel_done&&clear_stable&&!safety_blocked&&
      (state_debug==OPENING||state_debug==WAIT_PASS||state_debug==FAULT))state_debug<=CLOSING;
   if(authorization_valid&&authorization_tag==session_tag)begin
    if(auth_wait&&authorization_id==auth_request_id&&authorization_op==auth_request_op)begin
     auth_wait<=0;
     if(authorization_status==0)begin
      assigned_slot<=authorization_slot;owns_grant<=1;
      if(state_debug==WAIT_AUTH)state_debug<=OPENING;
     end else if(state_debug==WAIT_AUTH)state_debug<=IDLE;
    end else if(motion_wait&&authorization_id==motion_request_id&&authorization_op==motion_request_op)begin
     motion_wait<=0;
     if(authorization_status!=0)state_debug<=FAULT;
     else begin
      owns_grant<=0;
      if(motion_request_op==2)begin
       cancel_done<=1;
       if(clear_stable&&!safety_blocked)state_debug<=CLOSING;
      end
     end
    end
   end
   if(state_debug!=IDLE&&state_debug!=FAULT&&timer>=TIMEOUT_CYCLES-1)state_debug<=FAULT;
   if(state_debug==WAIT_PASS&&passage_detected&&!passed&&cancel_issued)state_debug<=FAULT;
  end
 end
endmodule
