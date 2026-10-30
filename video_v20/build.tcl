cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project competition_video_v20.al
elaborate -top competition
write_verilog competition_elaborated.vnew
read_adc competition.adc
read_sdc competition.sdc
optimize_rtl
report_area -file competition_rtl.area
optimize_gate -packarea competition_gate.area
legalize_phy_inst
place
route
update_timing -mode final
report_area -io_info -file competition_phy.area
report_timing_summary -file competition_pr.timing
check_timing -verbose -file competition_check.timing
export_db competition_pr.db
bitgen -bit competition_video_v20.bit
exit
