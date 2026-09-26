# PongTang simulation Makefile (Verilator)
VERILATOR ?= /home/user/tools/venv/bin/verilator-cli

# --- baseline: game logic only ---
TOP = pong
SRC = $(wildcard ../src/pong/*.v)

obj_dir/Vpong: $(SRC) tb_pong.cpp
	$(VERILATOR) --cc --exe --build -j 2 --Mdir obj_dir --top-module $(TOP) \
		tb_pong.cpp $(SRC) -o Vpong

run: obj_dir/Vpong
	./obj_dir/Vpong

# --- full system: top + scaler + HDMI + DS2 ---
TOP_MODULE = pongtang_top
TOP_SRC = tb_top.cpp \
	../src/pong/*.v \
	../src/paddle_ctrl.v \
	../src/pong2hdmi.sv \
	../src/pongtang_top.sv \
	../src/ctrl/*.v ../src/ctrl/*.sv \
	../src/hdmi2/*.sv

obj_top/Vtop: $(TOP_SRC) pong_background.txt tb_top.cpp
	$(VERILATOR) --cc --exe --build -j 2 --Mdir obj_top --top-module $(TOP_MODULE) \
		-Wno-TIMESCALEMOD -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
		-Wno-ALWCOMBORDER -Wno-CASEINCOMPLETE -Wno-COMBDLY $(TOP_SRC) -o Vtop

pong_background.txt: ../src/pong_background.txt
	cp ../src/pong_background.txt .

run-top: obj_top/Vtop
	./obj_top/Vtop

all: obj_dir/Vpong obj_top/Vtop

clean:
	rm -rf obj_dir obj_top frame_*.bmp hdmi_*.bmp pong_background.txt *.log

.PHONY: all run run-top clean
