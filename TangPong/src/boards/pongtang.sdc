// PongTang timing constraints (console138k)
// All clocks are created on top-level nets, NESTang style (PLL outputs get
// plain create_clock, RTL dividers get create_generated_clock).
// No false paths v1 (same as template): cross-domain crossings are 2-flop
// syncs between slow clocks; add set_false_path only if P&R reports
// violations on them.

// 50 MHz board clock: logic, UART, DS2 receivers
create_clock -name sys_clk -period 20 [get_nets {sys_clk}]

// Game-clock PLL: 12 MHz USB + 14.2857 MHz game x2 (VCO 900 / 75, / 63)
create_clock -name clk12 -period 83.333 [get_nets {clk12}]
create_clock -name clk14m -period 70 [get_nets {clk14m}]
create_generated_clock -name clk7m -source [get_nets {clk14m}] -divide_by 2 [get_nets {clk7m}]

// HDMI chain: 27 MHz -> 371.25 MHz -> CLKDIV /5 = 74.25 MHz
create_clock -name clk27 -period 37.037 [get_nets {clk27}]
create_clock -name hclk5 -period 2.6936 [get_nets {hclk5}]
create_generated_clock -name hclk -source [get_nets {hclk5}] -divide_by 5 [get_nets {hclk}]
