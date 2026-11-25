task check_invariants;
 integer j,popn,popr;
 begin
  if(!rst)begin
   popn=0;popr=0;
   for(j=0;j<SLOTS;j=j+1)begin
    if(admitted[j])popn=popn+1;
    if(reserved[j]&&!admitted[j])popr=popr+1;
    if(exit_pending[j]&&!admitted[j])$fatal(1,"exit without admitted");
   end
   if(n_count!=popn||r_count!=popr)$fatal(1,"bitmap/count mismatch at %d",cycle);
   if(fifo_count>FIFO_DEPTH||dedup_used>DEDUP)$fatal(1,"bounded memory overflow");
   if((pre_ready&(pre_ready-1))!=0)$fatal(1,"double command grant");
   if(!overcommitted&&n_count+r_count+d_count+q_count>c_count)$fatal(1,"capacity invariant");
  end
 end
endtask
