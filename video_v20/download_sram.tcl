cd [file dirname [file normalize [info script]]]
# Deliberately JTAG/SRAM only. Never use program_spi in this experiment.
read_device_id -cable 0 -level 1 -total 1
download -bit competition_video_v20.bit -mode jtag -spd 7 -cable 0
puts "V20_SRAM_DOWNLOAD_FINISHED_FLASH_NOT_WRITTEN"
exit
