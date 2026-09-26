# Developing cores for the Tang Console 138K

Practical notes from building TangPong — a working core for the Sipeed
Tang Console 138K (Gowin GW5AST-138). If you write a new core, start here.

## You will need

- Tang Console 138K with BL616 firmware (May 2025)
- Gowin EDA Standard (V1.9.12.04 tested) with a valid license
- microSD card (cores load from `cores/*.bin`, no JTAG needed)
- Optional: Verilator for simulation

## Start from TangPong

`TangPong/` is a complete, hardware-proven skeleton: copy it and adapt.
It bundles NESTang system templates (`iosys_bl616` UART link, USB-HID host,
DS2 receivers, PLL wrappers), an hdl-util/hdmi 720p output chain, a Gowin
build flow (`build.tcl` + `buildall.bat`) and Verilator testbenches.

Per-core layout: `README.md`, `ATTRIBUTION.md`, `VERSION`, `build.tcl`,
`buildall.bat`, `$readmem` data files at root, `src/`, `sim/`, `tools/`.

## How the firmware sees your core

- Known core IDs are 1-6 (NES..PC/XT). An unknown ID is SAFE: the firmware
  will simply always reprogram when switching systems. Never spoof a known ID.
- Cores started manually from the `cores` menu never auto-close the OSD
  (it only closes when loading a ROM). For ROM-less cores, players dismiss
  the menu with the OSD combo: **SELECT + D-PAD RIGHT** (default key, exact
  match). Document this in your core README!
- FPGA↔firmware UART runs at 2 Mbaud; the command protocol (core ID, config
  string, overlay control, HID forwarding, ROM loading) is documented in the
  header of `iosys_bl616.v`. Set its `FREQ` parameter to your real clock.

## Gowin gotchas (hard-won troubleshooting)

1. `default_nettype none` leaks across files (single compilation unit!):
   every file that sets it MUST end with `` `default_nettype wire ``.
   Verilator won't catch this (different file order). Symptom: EX3094 floods.
2. SystemVerilog needs `set_option -verilog_std sysv2017`, or every `logic` /
   `always_ff` is a parse error.
3. Async reset ONLY in canonical form (`if (!rstn) ... else ...`). A ternary
   reset is a hard EX2452 error, even though simulators accept it.
4. `$readmemb`/`$readmemh` files are resolved from the build directory:
   ship them at project root (e.g. don't forget `usb_hid_host_rom.hex`!).
5. Initializers on port declarations are IGNORED (EX2478 warning) — use a
   real reset for every initial value.
6. Unconnected `mgmt_*` / `kbd_*` / `fdd_*` on `iosys_bl616` is normal
   (NESTang does the same); EX2565 "tied to 0" warnings are harmless.
7. `.cst` pin names must match the top-level ports EXACTLY, or P&R fails.
8. Check generated `defparam` lines for trailing semicolons (EX3863).

Tip: make your build script save a full `build.log` and print all ERROR
lines at the end — the real error is always above the visible tail.

## Publishing checklist

- Standalone per-core README (build steps + OSD note if ROM-less).
- `ATTRIBUTION.md` with every third-party source and license.
- `LICENSE`: NESTang-derived work must be **GPL-3.0** (copyleft).
- Tag the release and attach the `.bin` so players don't need Gowin.

## Links

- Templates: [nand2mario/nestang](https://github.com/nand2mario/nestang)
- Firmware: [nand2mario/firmware-bl616](https://github.com/nand2mario/firmware-bl616)
- HDMI: [hdl-util/hdmi](https://github.com/hdl-util/hdmi) (Apache-2.0)
