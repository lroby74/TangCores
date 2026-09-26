# Attribution / licenses

## Game logic (`src/pong/`)

Atari PONG (1972) Verilog implementation by **Richard Eng** (2019),
taken from [MiSTer-devel/Arcade-Pong_MiSTer](https://github.com/MiSTer-devel/Arcade-Pong_MiSTer)
(`rtl/` directory, MiSTer framework files excluded).

- License: **MIT** (see headers in each file). Copyright notices preserved.
- MiSTer port glue by Sorgelig (`Arcade-Pong.sv`, `sys/`) is GPL-2.0+ but is
  **not used** here: the TangCore top level is written from scratch.

## Template / platform files (to be added)

- `iosys_bl616`, HDMI output, DS2/USB controller blocks, board constraints:
  adapted from [nand2mario/nestang](https://github.com/nand2mario/nestang)
  (**GPL-3.0**). PongTang as a whole will therefore be distributed under GPL-3.0.
- `dualshock_controller.v` (Katsumi Degawa): **freeware for non-commercial use**.
- HDMI core (`hdmi2/`, hdl-util/hdmi by Sameer Puri et al.): the upstream repo
  carries **no machine-readable license** (GitHub: NOASSERTION); used here
  exactly as in NESTang/SNESTang. If you need strict compliance, check with
  the hdl-util project before distributing.
- HDMI core: hdl-util/hdmi (license to be confirmed from upstream).

Personal / hobby use on Tang boards: fine. Commercial use: check the
dualshock freeware clause and GPL-3.0 obligations.
