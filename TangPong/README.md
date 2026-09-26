# PongTang - Atari PONG (1972) core for TangCore

PONG core for Sipeed Tang Console 138K, following the TangCore architecture:
game logic + HDMI 720p output + `iosys_bl616` (UART to BL616 MCU for menu,
overlay and USB controllers) + DualShock 2 direct input via DS2 PMOD.

- Video: **HDMI only** (720p, 4:3 game window)
- Input: USB controllers (via BL616) and/or DualShock 2 (via DS2 PMOD)
- Loading: copy `pongtang.bin` to `cores/console138k/` on the SD/USB drive,
  select it from the TangCore "cores" menu. No JTAG cable needed.
- No ROMs, no SDRAM: the game is pure logic.

## Status (Phase 1: design + simulation)

- [x] Game logic imported (MiSTer `Arcade-Pong`, MIT, Richard Eng)
- [x] Baseline simulation with Verilator (timing + screenshots)
- [ ] `pong2hdmi` scaler (framebuffer + 720p + OSD)
- [ ] Paddle digital control (D-pad/stick up-down + start=coin)
- [ ] Top level for console138k (clocks, iosys, DS2, USB)
- [ ] Gowin project (`build.tcl`, `.cst`, `.sdc`) -> `.bin` (built on user PC)

## Simulate

```bash
cd sim
make run     # builds with Verilator and runs the baseline test
```

Verilator used here is installed via `pip install verilator`
(see `/home/user/tools/venv` in the dev sandbox).

## Credits / licenses

See [ATTRIBUTION.md](ATTRIBUTION.md).

## Full-system simulation (`sim/`, `make run-top`, ~45 s)

`tb_top.cpp` boots the whole core (game + scaler + real HDMI core + real DS2
receivers with a C++ PSX pad emulator) through 2.06 s of simulated time:

- HDMI 720p timing exact (1650x750), gameplay + OSD screenshots saved
- DS2 poll period exactly 819200 main clocks (proves FREQ=50M), TX bytes
  `01 42 00...`, real START/UP buttons move P1
- USB-HID path moves P1 down, BL616-HID path moves P2 down (stub vectors)
- s1 button + START both coin (100 ms pulse); 15 sound edges (audio alive)
- OSD solid frame exactly full-window magenta; OSD gradient structurally exact

Result: `TOP: PASS`. Screenshots (`hdmi_*.bmp`, gitignored): convert to PNG
with PIL for viewing; `review_system.png` is the labeled 2x2 montage.

## Known quirks (all verified harmless)

- **Boot ghost-coin.** The DS2 receiver has no reset (as in NESTang): the first
  ~2.3 ms poll is misaligned and can latch a phantom START, auto-starting one
  game at power-on. Harmless for an arcade core (attract is skipped).
- **Single framebuffer.** First HDMI frame after reset is partially black
  (capture races display once); in steady state a 1-frame tear can cross the
  ball/paddles for 2-3 frames every ~28 s (16.67 vs 16.68 ms beat). Invisible
  in practice for slow PONG sprites; saves 63 Kb BRAM vs double buffering.
- **RGB 1-px lag.** `rgb` registers one `hclk` after `cx`/`active` (same
  structure as nes2hdmi): first window column repeats the border color, last
  game column leaks one pixel into the border. Cosmetic, invisible on TV.

## Building the bitstream (Windows + Gowin EDA Standard)

Prerequisites: Gowin EDA Standard installed (any 1.9.x: the scripts
auto-detect `gw_sh`) + free license activated (Help -&gt; Manage License).

```
buildall.bat
```

Output: `impl/pnr/pongtang_console138k.{fs,bin}`. Copy the `.bin` to the
microSD (or USB stick) as `cores/pongtang.bin`, insert into the Tang Console,
power on, open the `cores` menu and select `pongtang` - no JTAG needed.
PONG has no ROMs, so the firmware menu stays open after programming (it only
auto-closes when loading a ROM - same for any core started via `cores`).
Press SELECT + D-PAD RIGHT (firmware OSD combo, default key) to hide the menu
and play; press it again to summon the menu (e.g. to switch cores).

Notes:

- Only Tang Console 138K is supported (single `GW5AST-138` target).
- `src/pong_background.txt` is read by synthesis from disk (like NESTang
  assets); if GowinSynthesis reports it missing, copy it next to the
  generated project file and re-run.
- Timing (`.sdc`) mirrors the NESTang style; if P&R reports violations on
  the 2-flop clock-domain crossings, add `set_false_path` for them.
- Menu logo: regenerate with `tools/genlogo_pong.py` (prints the 4 DPB
  `INIT_RAM` lines + ASCII preview) after editing the artwork.
