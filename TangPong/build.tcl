# PongTang bitstream build (Tang Console 138K only).
# Run from pongtang/: gw_sh build.tcl   (or buildall.bat on Windows)
# Output: impl/pnr/pongtang_console138k.{fs,bin} -> microSD as cores/pongtang.bin
set_device GW5AST-LV138PG484AC1/I0 -device_version B
add_file src/pongtang_top.sv
add_file -type cst "src/boards/console138k.cst"
add_file -type verilog "src/pll/gowin_pll_27.v"
add_file -type verilog "src/pll/gowin_pll_hdmi.v"
add_file -type verilog "src/pll/pll_12_14m.v"
# NOTE: src/pll/pll_12.v is the unmodified template, kept for reference only.
add_file -type verilog "src/ctrl/usb_hid_host.v"
add_file -type sdc "src/boards/pongtang.sdc"
set_option -output_base_name pongtang_console138k

# PONG game logic (MIT, Richard Eng)
add_file -type verilog "src/pong/ball_horizontal.v"
add_file -type verilog "src/pong/ball_horizontal_direction.v"
add_file -type verilog "src/pong/ball_horizontal_move.v"
add_file -type verilog "src/pong/ball_horizontal_video.v"
add_file -type verilog "src/pong/ball_vertical.v"
add_file -type verilog "src/pong/ball_vertical_counter.v"
add_file -type verilog "src/pong/ball_vertical_move.v"
add_file -type verilog "src/pong/dm9316.v"
add_file -type verilog "src/pong/game_control.v"
add_file -type verilog "src/pong/hcounter.v"
add_file -type verilog "src/pong/hsync.v"
add_file -type verilog "src/pong/ls00.v"
add_file -type verilog "src/pong/ls02.v"
add_file -type verilog "src/pong/ls04.v"
add_file -type verilog "src/pong/ls10.v"
add_file -type verilog "src/pong/ls107.v"
add_file -type verilog "src/pong/ls153.v"
add_file -type verilog "src/pong/ls20.v"
add_file -type verilog "src/pong/ls25.v"
add_file -type verilog "src/pong/ls27.v"
add_file -type verilog "src/pong/ls30.v"
add_file -type verilog "src/pong/ls48.v"
add_file -type verilog "src/pong/ls50.v"
add_file -type verilog "src/pong/ls74.v"
add_file -type verilog "src/pong/ls83.v"
add_file -type verilog "src/pong/ls86.v"
add_file -type verilog "src/pong/ls90.v"
add_file -type verilog "src/pong/ls93.v"
add_file -type verilog "src/pong/net.v"
add_file -type verilog "src/pong/paddle.v"
add_file -type verilog "src/pong/paddles.v"
add_file -type verilog "src/pong/png_dff.v"
add_file -type verilog "src/pong/png_jkff.v"
add_file -type verilog "src/pong/pong.v"
add_file -type verilog "src/pong/score.v"
add_file -type verilog "src/pong/score_counters.v"
add_file -type verilog "src/pong/score_counters_to_segments.v"
add_file -type verilog "src/pong/score_segments_to_video.v"
add_file -type verilog "src/pong/sound.v"
add_file -type verilog "src/pong/srlatch.v"
add_file -type verilog "src/pong/timer.v"
add_file -type verilog "src/pong/vcounter.v"
add_file -type verilog "src/pong/video.v"
add_file -type verilog "src/pong/vsync.v"

# PongTang: paddle control + HDMI scaler
add_file -type verilog "src/paddle_ctrl.v"
add_file -type verilog "src/pong2hdmi.sv"

# Controllers (DS2 receivers; USB-HID added above)
add_file -type verilog "src/ctrl/controller_ds2.sv"
add_file -type verilog "src/ctrl/dualshock_controller.v"

# BL616 OSD/menu/uplink (template, no ROM blocks used)
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"

# HDMI core (hdl-util/hdmi, as in NESTang)
add_file -type verilog "src/hdmi2/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi2/audio_info_frame.sv"
add_file -type verilog "src/hdmi2/audio_sample_packet.sv"
add_file -type verilog "src/hdmi2/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi2/hdmi.sv"
add_file -type verilog "src/hdmi2/packet_assembler.sv"
add_file -type verilog "src/hdmi2/packet_picker.sv"
add_file -type verilog "src/hdmi2/serializer.sv"
add_file -type verilog "src/hdmi2/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi2/tmds_channel.sv"

# NOTE: pong_background.txt ($readmemb init) and usb_hid_host_rom.hex
# ($readmemh init) are read from disk at elaboration (gw_sh runs here, so
# they live next to this file); they are not add_file sources. The txt is
# duplicated under src/ for the Verilator sim (see sim/Makefile).

set_option -synthesis_tool gowinsynthesis
set_option -top_module pongtang_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_mspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -multi_boot 1
set_option -place_option 2

run all
