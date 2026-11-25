`timescale 1ns/1ps
module tb_sensor;
 parameter HOLD_STATUS=0;
 reg clk=0;always #500 clk=~clk; // 1 MHz simulation clock, 1 us per cycle
 reg rst=1,echo=0,ready=1;wire trigger,known,occupied,valid,sample,timeout;
 wire [2:0] led,count;wire [15:0] echo_us,median_mm;
 slot_node_sensor #(1000000,10,100,3000,50,100,140,3) dut(
 .clk(clk),.rst(rst),.echo_async(echo),.trigger(trigger),.known(known),.occupied(occupied),
 .led_rgb(led),.status_valid(valid),.status_ready(ready),.echo_us(echo_us),.median_mm(median_mm),
 .sample_count(count),.sample_pulse(sample),.timeout_pulse(timeout),.echo_sync_debug());
 reg [2047:0] input_path,output_path,wave_path;integer fi,fo,code,width,index,guard,cycles=0;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(cycles>500000)$fatal(1,"sensor watchdog");
  if(!rst&&known&&led!==(occupied?3'b100:3'b010))$fatal(1,"RGB");
 end
 initial begin
  if(!$value$plusargs("INPUT=%s",input_path))$fatal;
  if(!$value$plusargs("OUTPUT=%s",output_path))$fatal;
  if($value$plusargs("WAVE=%s",wave_path))begin $dumpfile(wave_path);$dumpvars(0,tb_sensor);end
  fi=$fopen(input_path,"r");fo=$fopen(output_path,"w");
  $fdisplay(fo,"index,width,echo_us,sample_count,median_mm,known,occupied,led,timeout");
  repeat(4)@(negedge clk);rst=0;index=0;if(HOLD_STATUS)ready=0;
  while(!$feof(fi))begin
   code=$fscanf(fi,"%d\n",width);
   if(code==1)begin
    if(valid&&!ready)begin
     repeat(HOLD_STATUS==2?10000:200)begin @(posedge clk);#1;if(!valid||trigger||!known)$fatal(1,"sensor backpressure");end
     @(negedge clk);ready=1;
     if(HOLD_STATUS==2)begin
      @(posedge clk);#1;if(known||!valid||count!=0)$fatal(1,"stale status not replaced by UNKNOWN");
      @(posedge clk);#1;if(valid)$fatal(1,"UNKNOWN not acknowledged");
     end
    end
    @(negedge trigger);repeat(20)@(negedge clk);
    if(width>0)begin echo=1;repeat(width)@(negedge clk);echo=0;end
    else if(width<0)echo=1;
    guard=0;
    while(!sample&&!timeout&&guard<6500)begin @(posedge clk);#1;guard=guard+1;end
    if(guard>=6500)$fatal(1,"missing sample");
    $fdisplay(fo,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",index,width,echo_us,count,median_mm,known,occupied,led,timeout);
    @(negedge clk);echo=0;index=index+1;
   end
  end
  $fclose(fi);$fclose(fo);$display("PASS sensor samples=%0d cycles=%0d",index,cycles);$finish;
 end
endmodule
