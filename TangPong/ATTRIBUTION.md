# Attribution / licenses

## Game logic (`src/pong/`)

Atari PONG (1972) Verilog implementation by **Richard Eng** (2019),
taken from [MiSTer-devel/Arcade-Pong_MiSTer](https://github.com/MiSTer-devel/Arcade-Pong_MiSTer)
(`rtl/` directory, MiSTer framework files excluded).

- License: **MIT** (see headers in each file). Copyright notices preserved.
- MiSTer port glue by Sorgelig (`Arcade-Pong.sv`, `sys/`) is GPL-2.0+ but is
  **not used** here: the TangCore top level is written from scratch.

## Template / platform files

- `iosys_bl616`, HDMI output glue, DS2/USB controller blocks, board
  constraints, PLL wrappers and build flow: adapted from
  [nand2mario/nestang](https://github.com/nand2mario/nestang) (**GPL-3.0**).
  PongTang as a whole is therefore distributed under GPL-3.0 (see `LICENSE`
  at the repo root).
- `dualshock_controller.v` (PSX controller receiver, Katsumi Degawa, via
  NESTang): freeware for **non-commercial use** — see the header in the file.
  Commercial users must comply with both this clause and GPL-3.0.
- HDMI core `hdmi2/`: [hdl-util/hdmi](https://github.com/hdl-util/hdmi) by
  Sameer Puri, **Apache License 2.0** (upstream `LICENSE-APACHE`), used here
  exactly as in NESTang/SNESTang.
