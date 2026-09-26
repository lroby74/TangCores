// PongTang top level for Tang Console 138K (GW5AST-LV138PG484AC1/I0)
// Atari PONG (1972) core for TangCore.
// - HDMI-only video (720p, 4:3 game window + OSD overlay)
// - Inputs: DualShock 2 x2 (PMOD1) + USB HID (FPGA USB-A) + USB/XInput (BL616)
// - No SDRAM, no ROMs: SDRAM pins driven to idle levels
// - Clocking: sys_clk 50 MHz (logic/UART) -> pll 14.2857 MHz -> /2 = 7.1428 MHz
//   game clock (0.23% below nominal 7.159 MHz: inaudible/invisible),
//   27 MHz -> 371.25 MHz -> /5 = 74.25 MHz HDMI, 12 MHz USB.
`timescale 1ns / 1ps

module pongtang_top (
    input  logic sys_clk,       // 50 MHz board oscillator
    input  logic s1,            // active-low push button (coin)
    input  logic UART_RXD,
    output logic UART_TXD,

    // SDRAM (unused by PONG, driven to idle levels)
    output logic O_sdram_clk,
    output logic O_sdram_cs_n,
    output logic O_sdram_cas_n,
    output logic O_sdram_ras_n,
    output logic O_sdram_wen_n,
    inout  wire [15:0] IO_sdram_dq,
    output logic [12:0] O_sdram_addr,
    output logic [1:0] O_sdram_ba,
    output logic [1:0] O_sdram_dqm,

    output logic [7:0] led,     // PMOD0

    // DualShock 2 controllers x2 (PMOD1)
    output logic ds_clk,
    input  logic ds_miso,
    output logic ds_mosi,
    output logic ds_cs,
    output logic ds_clk2,
    input  logic ds_miso2,
    output logic ds_mosi2,
    output logic ds_cs2,

    // USB host x2 (FPGA USB-A ports)
    inout wire usb1_dp,
    inout wire usb1_dn,
    inout wire usb2_dp,
    inout wire usb2_dn,

    // HDMI TX
    output logic tmds_clk_n,
    output logic tmds_clk_p,
    output logic [2:0] tmds_d_n,
    output logic [2:0] tmds_d_p
`ifdef VERILATOR
    // simulation-only ports (clocks in, stubs, probes out)
    ,input  logic        sim_clk_main,   // 50 MHz
    input  logic        sim_clk7m,      // ~7.14 MHz
    input  logic        sim_hclk,       // 74.25 MHz
    input  logic        sim_resetn,
    input  logic [11:0] sim_joy_usb1,
    input  logic [11:0] sim_joy_usb2,
    input  logic [15:0] sim_hid1,
    input  logic [15:0] sim_hid2,
    input  logic        sim_overlay,
    input  logic        sim_overlay_grad,
    input  logic [14:0] sim_overlay_color,
    output logic [23:0] sim_rgb,
    output logic [10:0] sim_cx,
    output logic [9:0]  sim_cy,
    output logic        sim_active,
    output logic [7:0]  sim_ox,
    output logic [7:0]  sim_oy,
    output logic [7:0]  sim_vpos1,
    output logic [7:0]  sim_vpos2,
    output logic        sim_coin,
    output logic        sim_sound
`endif
);

///////////////////////////
// Clocks
///////////////////////////
wire clk_main;          // 50 MHz logic clock (= sys_clk)
wire clk12;             // 12 MHz USB clock
wire clk14m;            // 14.2857 MHz (game clock x2)
logic clk7m;            // 7.1428 MHz game clock (exact /2, 50% duty)
wire clk27;             // 27 MHz (HDMI chain)
wire hclk5;             // 371.25 MHz TMDS bit clock x5
wire hclk;              // 74.25 MHz HDMI pixel clock
reg sys_resetn;      // no init: Verilator counts initializers as drivers (MULTIDRIVEN)
wire pll_lock_12;

`ifndef VERILATOR
assign clk_main = sys_clk;
pll_12_14m pll_game (.lock(pll_lock_12), .clkout0(clk12), .clkout1(clk14m), .clkin(sys_clk));
gowin_pll_27 pll_27 (.clkin(sys_clk), .clkout0(clk27));
gowin_pll_hdmi pll_hdmi (.clkin(clk27), .clkout(hclk5));
CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk), .HCLKIN(hclk5), .RESETN(sys_resetn), .CALIB(1'b0)
);
always_ff @(posedge clk14m or negedge sys_resetn) begin
    if (!sys_resetn)
        clk7m <= 1'b0;
    else
        clk7m <= ~clk7m;
end
`else
assign clk_main = sim_clk_main;
assign clk12 = 1'b0;
assign clk14m = 1'b0;
assign clk27 = 1'b0;
assign hclk5 = 1'b0;
assign hclk = sim_hclk;
assign pll_lock_12 = 1'b1;
always_comb clk7m = sim_clk7m;
`endif

///////////////////////////
// Reset
///////////////////////////
`ifndef VERILATOR
reg [7:0] reset_cnt = 255;
always @(posedge clk_main) begin
    reset_cnt <= (reset_cnt == 0) ? 0 : reset_cnt - 1;
    if (reset_cnt == 0) sys_resetn <= 1'b1;
end
`else
always_comb sys_resetn = sim_resetn;
`endif

// game-clock-domain reset (synchronized)
logic grst_r = 0, game_resetn = 0;
always @(posedge clk7m or negedge sys_resetn) begin
    if (!sys_resetn) begin grst_r <= 0; game_resetn <= 0; end
    else begin grst_r <= 1'b1; game_resetn <= grst_r; end
end

///////////////////////////
// Controllers (clk_main domain)
// SNES layout [11:0]: R L X A RT LT DN UP START SELECT Y B
///////////////////////////
wire [11:0] ds1, ds2;                 // DualShock 2 via PMOD1
wire [11:0] usb1_raw, usb2_raw;       // USB HID via FPGA ports
logic [11:0] usb1, usb2;              // ... synchronized to clk_main
wire [15:0] hid16_1, hid16_2;         // USB/XInput via BL616 MCU
wire [11:0] hid1 = hid16_1[11:0];
wire [11:0] hid2 = hid16_2[11:0];
wire [11:0] joy1 = ds1 | usb1 | hid1;
wire [11:0] joy2 = ds2 | usb2 | hid2;

// DualShock 2 receivers (real RTL in sim too; timing verified by testbench)
controller_ds2 #(.FREQ(50_000_000)) ds2_p1 (
    .clk(clk_main), .snes_buttons(ds1),
    .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs));
controller_ds2 #(.FREQ(50_000_000)) ds2_p2 (
    .clk(clk_main), .snes_buttons(ds2),
    .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2));

`ifndef VERILATOR
wire [1:0] usb_type1, usb_type2;
wire usb_conerr1, usb_conerr2;
usb_hid_host usb_hid1 (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb1_dn), .usb_dp(usb1_dp),
    .game_snes(usb1_raw), .typ(usb_type1), .conerr(usb_conerr1));
usb_hid_host usb_hid2 (
    .usbclk(clk12), .usbrst_n(pll_lock_12),
    .usb_dm(usb2_dn), .usb_dp(usb2_dp),
    .game_snes(usb2_raw), .typ(usb_type2), .conerr(usb_conerr2));
`else
assign usb1_raw = sim_joy_usb1;
assign usb2_raw = sim_joy_usb2;
`endif

// synchronize USB buttons (12 MHz / async test vectors) to clk_main
genvar g;
generate for (g = 0; g < 12; g++) begin : sync_usb
    logic s1a, s1b, s2a, s2b;
    always @(posedge clk_main or negedge sys_resetn) begin
        if (!sys_resetn) begin s1a <= 0; s1b <= 0; s2a <= 0; s2b <= 0; end
        else begin
            s1a <= usb1_raw[g]; s1b <= s1a;
            s2a <= usb2_raw[g]; s2b <= s2a;
        end
    end
    assign usb1[g] = s1b;
    assign usb2[g] = s2b;
end endgenerate

///////////////////////////
// Coin (s1 button + START), debounced, 100 ms pulse
///////////////////////////
logic s1_r1 = 1, s1_r2 = 1;
always @(posedge clk_main or negedge sys_resetn) begin
    if (!sys_resetn) begin s1_r1 <= 1; s1_r2 <= 1; end
    else begin s1_r1 <= s1; s1_r2 <= s1_r1; end
end
wire s1_pressed = ~s1_r2;

logic [16:0] db_cnt = 0;
logic s1_db = 0, s1_db_r = 0;
always @(posedge clk_main or negedge sys_resetn) begin
    if (!sys_resetn) begin db_cnt <= 0; s1_db <= 0; s1_db_r <= 0; end
    else begin
        s1_db_r <= s1_db;
        if (s1_pressed != s1_db) begin
            if (db_cnt == 17'd131071) begin s1_db <= s1_pressed; db_cnt <= 0; end
            else db_cnt <= db_cnt + 1;
        end else db_cnt <= 0;
    end
end
wire s1_edge = s1_db && !s1_db_r;

wire joy1_up = joy1[4], joy1_dn = joy1[5], joy1_st = joy1[3];
wire joy2_up = joy2[4], joy2_dn = joy2[5], joy2_st = joy2[3];

logic st1_r = 0, st2_r = 0;
always @(posedge clk_main or negedge sys_resetn) begin
    if (!sys_resetn) begin st1_r <= 0; st2_r <= 0; end
    else begin st1_r <= joy1_st; st2_r <= joy2_st; end
end
wire st1_edge = joy1_st && !st1_r;
wire st2_edge = joy2_st && !st2_r;

localparam COIN_CLKS = 5_000_000;     // 100 ms @ 50 MHz
logic [22:0] coin_cnt = 0;
always @(posedge clk_main or negedge sys_resetn) begin
    if (!sys_resetn) coin_cnt <= 0;
    else if (s1_edge || st1_edge || st2_edge) coin_cnt <= COIN_CLKS;
    else if (coin_cnt != 0) coin_cnt <= coin_cnt - 1;
end
wire coin_main = (coin_cnt != 0);

// to game clock domain (single-bit 2-flop syncs)
logic up1_a, up1_7, dn1_a, dn1_7, up2_a, up2_7, dn2_a, dn2_7, coin_a, coin_7m;
always @(posedge clk7m or negedge game_resetn) begin
    if (!game_resetn) begin
        up1_a <= 0; up1_7 <= 0; dn1_a <= 0; dn1_7 <= 0;
        up2_a <= 0; up2_7 <= 0; dn2_a <= 0; dn2_7 <= 0;
        coin_a <= 0; coin_7m <= 0;
    end else begin
        up1_a <= joy1_up; up1_7 <= up1_a;
        dn1_a <= joy1_dn; dn1_7 <= dn1_a;
        up2_a <= joy2_up; up2_7 <= up2_a;
        dn2_a <= joy2_dn; dn2_7 <= dn2_a;
        coin_a <= coin_main; coin_7m <= coin_a;
    end
end

///////////////////////////
// Game: paddles + PONG machine
///////////////////////////
wire [7:0] vpos1, vpos2;
wire [3:0] pr;
wire phsync, pvsync, phblank, pvblank, psound;

paddle_ctrl #(6, 128) p1ctl (
    .clk(clk7m), .resetn(game_resetn), .vsync(pvsync),
    .up(up1_7), .down(dn1_7), .vpos(vpos1));
paddle_ctrl #(6, 128) p2ctl (
    .clk(clk7m), .resetn(game_resetn), .vsync(pvsync),
    .up(up2_7), .down(dn2_7), .vpos(vpos2));

pong game (
    .clk7_159(clk7m), .coin_sw(coin_7m), .dip_sw(8'b0),   // 11-point game
    .paddle1_vpos(vpos1), .paddle2_vpos(vpos2),
    .net(), ._hsync(), ._vsync(), .sync_2_2k(), .pads_net_1k(), .score_1_2k(),
    .sound_out(psound), .hsync(phsync), .vsync(pvsync),
    .hblank(phblank), .vblank(pvblank), .r(pr), .g(), .b());

///////////////////////////
// OSD overlay + BL616 link
///////////////////////////
wire overlay;
wire [7:0] overlay_x, overlay_y;
wire [14:0] overlay_color;

`ifndef VERILATOR
// PONG has no ROMs: rom_* left unconnected. Logo bitmap (gowin_dpb_menu)
// will be replaced with the PONG logo; COLOR_LOGO=white is neutral.
iosys_bl616 #(.COLOR_LOGO(15'h7FFF), .FREQ(50_000_000), .CORE_ID(7)) sys_inst (
    .clk(clk_main), .hclk(hclk), .resetn(sys_resetn),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(ds1 | usb1), .joy2(ds2 | usb2),
    .hid1(hid16_1), .hid2(hid16_2),
    .uart_tx(UART_TXD), .uart_rx(UART_RXD),
    .rom_loading(), .rom_do(), .rom_do_valid());
`else
assign overlay = sim_overlay;
assign overlay_color = sim_overlay_grad ? {overlay_y[4:0], overlay_x[4:0], 5'h10}
                                        : sim_overlay_color;
assign hid16_1 = sim_hid1;
assign hid16_2 = sim_hid2;
assign UART_TXD = 1'b1;
`endif

///////////////////////////
// HDMI video + audio
///////////////////////////
pong2hdmi u_hdmi (
    .clk(clk7m), .resetn(game_resetn),
    .r(pr), .hblank(phblank), .vblank(pvblank), .sound(psound),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
`ifdef VERILATOR
    ,.sim_rgb(sim_rgb), .sim_cx(sim_cx), .sim_cy(sim_cy), .sim_active(sim_active)
`endif
);

///////////////////////////
// SDRAM idle levels + LEDs + sim probes
///////////////////////////
assign O_sdram_clk = 1'b0;
assign O_sdram_cs_n = 1'b1;
assign O_sdram_ras_n = 1'b1;
assign O_sdram_cas_n = 1'b1;
assign O_sdram_wen_n = 1'b1;
assign O_sdram_addr = 13'b0;
assign O_sdram_ba = 2'b0;
assign O_sdram_dqm = 2'b11;
assign IO_sdram_dq = 16'bz;

reg [22:0] hb_cnt = 0;
always @(posedge clk7m or negedge game_resetn) begin
    if (!game_resetn) hb_cnt <= 0;
    else hb_cnt <= hb_cnt + 1;
end
reg coin_sticky = 0;
always @(posedge clk_main or negedge sys_resetn) begin
    if (!sys_resetn) coin_sticky <= 0;
    else if (coin_main) coin_sticky <= 1;
end
`ifndef VERILATOR
assign led = {usb_conerr1, usb_conerr2,
              (usb_type1 == 2'b11), (usb_type2 == 2'b11),
              psound, coin_sticky, hb_cnt[22], hb_cnt[21]};
`else
assign led = {6'b0, hb_cnt[22], hb_cnt[21]};
assign sim_ox = overlay_x;
assign sim_oy = overlay_y;
assign sim_vpos1 = vpos1;
assign sim_vpos2 = vpos2;
assign sim_coin = coin_7m;
assign sim_sound = psound;
`endif

endmodule
