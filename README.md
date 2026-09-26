# TangCores

Open-source FPGA cores for the **Tang Console 138K** (Sipeed, Gowin GW5AST-138).
Each core lives in its own folder with full source, build scripts and docs.
Prebuilt binaries are published as
[Releases](https://github.com/lroby74/Tangcores/releases).

## Cores

| Folder | Core | Status |
|---|---|---|
| `TangPong/` | Atari PONG (1972) replica — 720p HDMI, USB controllers (+DS2 via PMOD, untested), OSD menu, sound | ✅ Working on hardware (v1.0) |

More cores coming soon.

## For players (no build tools needed)

1. Download the core `.bin` from
   [Releases](https://github.com/lroby74/Tangcores/releases).
2. Copy it to the microSD as `cores/<corename>.bin` (e.g. `cores/pongtang.bin`).
3. Insert the SD, power on, open the `cores` menu and select the core.
4. The firmware menu stays open after programming (it only auto-closes when
   loading a ROM). Press **SELECT + D-PAD RIGHT** (default OSD key) to hide
   the menu and play; press it again to summon it.

Requirements: Tang Console 138K with BL616 firmware (May 2025 or later).

## For builders

- Install **Gowin EDA Standard** (tested: V1.9.12.04, 64-bit) with a valid
  license.
- Open the core folder (e.g. `TangPong/`), follow its `README.md`:
  `buildall.bat` on Windows produces `impl/pnr/*_console138k.bin`.
- Simulation: Verilator testbenches under each core's `sim/` (see core README).

## Sources & licenses

Each core folder contains an `ATTRIBUTION.md` with the exact sources and
licenses of every third-party file (PONG logic: MIT, Richard Eng; system/IO
templates: NESTang by nand2mario; HDMI core: hdl-util/hdmi).
Original glue/RTL in this repo is MIT unless stated otherwise.

## Credits

- [nand2mario](https://github.com/nand2mario) — NESTang templates & TangCore
  BL616 firmware this work builds on
- Richard Eng — cycle-faithful PONG RTL (MIT)
- [hdl-util/hdmi](https://github.com/hdl-util/hdmi) — HDMI transmitter core
