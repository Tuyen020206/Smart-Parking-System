`timescale 1ns/1ps
module slot_node_sensor #(
 parameter CLK_HZ=50000000,TRIGGER_US=10,GAP_US=60000,MAX_ECHO_US=30000,MIN_ECHO_US=50,
 parameter D_ON_MM=1000,D_OFF_MM=1200,CONFIRM=3,
 parameter STALE_US=2*(GAP_US+MAX_ECHO_US+TRIGGER_US)
)(
 input wire clk,rst,echo_async,
 output wire trigger,output reg known,occupied,
 output wire [2:0] led_rgb,
 output reg status_valid,input wire status_ready,
 output reg [15:0] echo_us,median_mm,output reg [2:0] sample_count,
 output reg sample_pulse,timeout_pulse,output wire echo_sync_debug
);
 localparam DIV=(CLK_HZ/1000000<1)?1:CLK_HZ/1000000;
 localparam GAP=0,TRIG=1,WAIT_RISE=2,MEASURE=3;
 reg [1:0] phase;reg [31:0] divider,timer_us,width_us;
 wire tick=(divider==DIV-1);wire echo_sync;
 reg echo_prev;
 sync_bits #(1,0) echo_cdc(clk,rst,echo_async,echo_sync);
 assign echo_sync_debug=echo_sync;
 assign trigger=(phase==TRIG)&&!rst;
 assign led_rgb=!known?3'b110:occupied?3'b100:3'b010;
 reg [15:0] samples[0:4];reg [15:0] sorted[0:4];reg [15:0] swap;
 reg [31:0] distance_mm;reg candidate,last_candidate,candidate_valid;
 reg [15:0] confirm_count;reg fault_reported;
 reg [31:0] age_us;reg stale_pending;
 integer i,j;
 always @*begin
  for(i=0;i<4;i=i+1)sorted[i]=samples[i+1];
  sorted[4]=width_us+1;
  swap=0;
  for(i=0;i<5;i=i+1)for(j=0;j<4;j=j+1)begin
   if(j<4-i&&sorted[j]>sorted[j+1])begin swap=sorted[j];sorted[j]=sorted[j+1];sorted[j+1]=swap;end
  end
  distance_mm=(sorted[2]*32'd343)/32'd2000;
  candidate=occupied;candidate_valid=known;
  if(distance_mm<=D_ON_MM)begin candidate=1;candidate_valid=1;end
  else if(distance_mm>=D_OFF_MM)begin candidate=0;candidate_valid=1;end
 end
 integer k;
 always @(posedge clk)begin
  if(rst)begin
   phase<=GAP;divider<=0;timer_us<=0;width_us<=0;echo_prev<=0;
   known<=0;occupied<=0;status_valid<=0;echo_us<=0;median_mm<=0;sample_count<=0;
   confirm_count<=0;last_candidate<=0;fault_reported<=0;sample_pulse<=0;timeout_pulse<=0;age_us<=0;stale_pending<=0;
   for(k=0;k<5;k=k+1)samples[k]<=0;
  end else begin
   divider<=tick?0:divider+1'b1;echo_prev<=echo_sync;sample_pulse<=0;timeout_pulse<=0;
   if(tick&&age_us<STALE_US)age_us<=age_us+1'b1;
   if(status_valid&&status_ready)status_valid<=0;
   case(phase)
    GAP:if(tick&&!status_valid)begin
     if(timer_us>=GAP_US-1)begin phase<=TRIG;timer_us<=0;end else timer_us<=timer_us+1'b1;
    end
    TRIG:if(tick)begin
     if(timer_us>=TRIGGER_US-1)begin phase<=WAIT_RISE;timer_us<=0;end else timer_us<=timer_us+1'b1;
    end
    WAIT_RISE:begin
     if(echo_sync&&!echo_prev)begin phase<=MEASURE;width_us<=0;timer_us<=0;end
     else if(tick)begin
      if(timer_us>=MAX_ECHO_US-1)begin
       phase<=GAP;timer_us<=0;known<=0;sample_count<=0;confirm_count<=0;timeout_pulse<=1;
       if(known||!fault_reported)status_valid<=1;fault_reported<=1;
       for(k=0;k<5;k=k+1)samples[k]<=0;
      end else timer_us<=timer_us+1'b1;
     end
    end
    MEASURE:begin
     if(!echo_sync&&echo_prev)begin
      phase<=GAP;timer_us<=0;echo_us<=width_us+1;
      if(width_us+1<MIN_ECHO_US||width_us+1>MAX_ECHO_US)begin
       known<=0;sample_count<=0;confirm_count<=0;timeout_pulse<=1;
       if(known||!fault_reported)status_valid<=1;fault_reported<=1;
       for(k=0;k<5;k=k+1)samples[k]<=0;
      end else begin
       sample_pulse<=1;fault_reported<=0;age_us<=0;stale_pending<=0;
       for(k=0;k<4;k=k+1)samples[k]<=samples[k+1];samples[4]<=width_us+1;
       if(sample_count<5)sample_count<=sample_count+1'b1;
       if(sample_count>=4)begin
        median_mm<=distance_mm;
        if(candidate_valid)begin
         if(known&&candidate==occupied)confirm_count<=0;
         else begin
          last_candidate<=candidate;
          if(candidate==last_candidate)confirm_count<=confirm_count+1'b1;else confirm_count<=1;
          if(CONFIRM==1||(candidate==last_candidate&&confirm_count>=CONFIRM-1))begin
           known<=1;occupied<=candidate;confirm_count<=0;
           if(!known||candidate!=occupied)status_valid<=1;
          end
         end
        end else confirm_count<=0;
       end
      end
     end else if(tick)begin
      if(width_us>=MAX_ECHO_US)begin
       phase<=GAP;timer_us<=0;known<=0;sample_count<=0;confirm_count<=0;timeout_pulse<=1;
       if(known||!fault_reported)status_valid<=1;fault_reported<=1;
       for(k=0;k<5;k=k+1)samples[k]<=0;
      end else width_us<=width_us+1'b1;
     end
    end
    default:phase<=GAP;
   endcase
   // Preserve a stalled snapshot. At its ACK, immediately replace it with
   // UNKNOWN before permitting a new scan/command to use stale FREE data.
   if(known&&(stale_pending||age_us>=STALE_US))begin
    if(status_valid&&!status_ready)stale_pending<=1;
    else begin
     known<=0;status_valid<=1;sample_count<=0;confirm_count<=0;fault_reported<=1;
     stale_pending<=0;age_us<=0;timeout_pulse<=1;
     for(k=0;k<5;k=k+1)samples[k]<=0;
    end
   end
  end
 end
endmodule
