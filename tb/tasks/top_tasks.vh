task tick;begin @(posedge clk);#3;end endtask
task cycles;input integer k;integer i;begin for(i=0;i<k;i=i+1)tick;end endtask
task milestone;input [255:0] name;begin
 $fdisplay(fm,"%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",name,c_count,n_count,r_count,d_count,q_count,occupied,valid_map,reserved);
end endtask
task wait_gate_state;input integer g,value;integer w;begin
 w=0;while(gate_states[g*3+:3]!=value)begin tick;w=w+1;if(w>1000)$fatal(1,"state wait gate%0d wanted%0d",g,value);end
end endtask
task automatic_entry;input integer g;begin
 request_open(g);wait_gate_state(g,3);pass_barrier(g);
 @(negedge clk);vehicle_async[g]=0;wait_gate_state(g,0);cycles(5);
 if(!model_closed[g])$fatal(1,"plant not closed");
end endtask
task host_command;input [3:0] op;input [15:0] slot,data;input replay;integer wait_count;begin
 @(negedge clk);if(!replay)host_seq=host_seq+1;
 host_id={8'd4,epoch,host_seq[31:0]};host_op=op;host_slot=slot;host_data=data;host_valid=1;
 wait_count=0;@(posedge clk);
 while(!host_ready)begin @(posedge clk);wait_count=wait_count+1;if(wait_count>500)$fatal(1,"host stall");end
 #3;if(!rsp_valid||rsp_source!=4||rsp_id!=host_id)$fatal(1,"host response route");
 if(op!=15&&rsp_status!=0)$fatal(1,"host status %d",rsp_status);
 @(negedge clk);host_valid=0;
end endtask
task request_open;input integer g;integer w;begin
 @(negedge clk);vehicle_async[g]=1;w=0;
 while(!open_cmd[g])begin tick;w=w+1;if(w>200)$fatal(1,"no grant gate %0d",g);end
end endtask
task open_barrier;input integer g;begin
 @(negedge clk);close_limit_async[g]=0;open_limit_async[g]=1;cycles(5);
 if(gate_states[g*3+:3]!=3)$fatal(1,"gate not WAIT_PASS");
end endtask
task pass_barrier;input integer g;begin
 @(negedge clk);passage_async[g]=1;cycles(4);@(negedge clk);passage_async[g]=0;open_limit_async[g]=0;
end endtask
task enter;input integer g;begin
 request_open(g);open_barrier(g);pass_barrier(g);cycles(5);
 @(negedge clk);vehicle_async[g]=0;open_limit_async[g]=0;close_limit_async[g]=1;cycles(5);
 if(gate_states[g*3+:3]!=0)$fatal(1,"gate not closed");
end endtask
task wait_occupied;input integer slot,value;integer w;begin
 w=0;while(occupied[slot]!=value||!valid_map[slot])begin tick;w=w+1;if(w>22000)$fatal(1,"sensor did not settle");end
end endtask
