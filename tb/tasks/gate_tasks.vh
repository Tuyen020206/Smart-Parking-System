task tick;begin @(posedge clk);#1;end endtask
task cycles;input integer k;integer j;begin for(j=0;j<k;j=j+1)tick;end endtask
task expect_state;input integer value;begin
 if(state!==value)$fatal(1,"case %0d state %0d expected %0d",testcase,state,value);
end endtask
task milestone;input [255:0] label;begin
 $fdisplay(fm,"%0s,%0d,%0d,%0d,%0d",label,state,open_cmd,close_cmd,pending);
end endtask
task reset_system;begin
 @(negedge clk);rst=1;vehicle=0;opened=0;closed=1;passage=0;blocked=0;clear=1;cancel=0;recover=0;
 ready=0;auth=0;cycles(3);expect_state(5);
 if(open_cmd||close_cmd)$fatal(1,"motion after reset");
 @(negedge clk);rst=0;recover=1;cycles(2);@(negedge clk);recover=0;expect_state(0);
end endtask
task request_entry;begin
 @(negedge clk);vehicle=1;tick;expect_state(1);
 @(negedge clk);ready=1;saved_id=req_id;saved_tag=req_tag;tick;
 @(negedge clk);ready=0;
end endtask
task reply;input [7:0] status;input [15:0] tag_value;input [63:0] id_value;input [3:0] op_value;begin
 @(negedge clk);auth=1;auth_status=status;auth_tag=tag_value;auth_id=id_value;auth_op=op_value;tick;
 @(negedge clk);auth=0;
end endtask
task grant;begin request_entry;reply(0,saved_tag,saved_id,0);expect_state(2);end endtask
task opened_barrier;begin @(negedge clk);closed=0;opened=1;tick;expect_state(3);end endtask
task send_passage;begin @(negedge clk);passage=1;tick;@(negedge clk);passage=0;expect_state(4);end endtask
