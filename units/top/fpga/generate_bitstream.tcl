# author: nolting, FhG IMS

open_proj work/nexys_video.xpr
  
set run_name impl_1
  
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

launch_runs $run_name -to_step write_bitstream
wait_on_run $run_name
  
set status [get_property STATUS [get_runs $run_name]]
if {$status != "write_bitstream Complete!"} {
  exit 1
}
exit 0

