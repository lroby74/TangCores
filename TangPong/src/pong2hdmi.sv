// PONG video and sound to HDMI converter (720p)
// Captures the 374x246 PONG frame @clk7m into a 256x246 framebuffer
// (374->256 horizontal decimation), scales to a centered 960x720 (4:3)
// window in 1280x720, mixes the OSD overlay, embeds 48kHz audio.
// Adapted from NESTang nes2hdmi.sv (nand2mario).
`timescale 1ns / 1ps

module pong2hdmi (
    input  logic       clk,            // PONG clock (~7.14 MHz)
    input  logic       resetn,

    // PONG video signals
    input  logic [3:0] r,              // pixel: 0x0 black, 0xB score, 0xF white
    input  logic       hblank,
    input  logic       vblank,
    input  logic       sound,          // 1-bit beep

    // overlay interface (same protocol as nes2hdmi)
    input  logic       overlay,
    output logic [7:0] overlay_x,      // 0-255
    output logic [7:0] overlay_y,      // 0-245
    input  logic [14:0] overlay_color, // BGR5

    // video clocks
    input  logic       clk_pixel,      // 74.25 MHz
    input  logic       clk_5x_pixel,   // 371.25 MHz (serializer only, unused in sim)

    // HDMI outputs
    output logic       tmds_clk_n,
    output logic       tmds_clk_p,
    output logic [2:0] tmds_d_n,
    output logic [2:0] tmds_d_p
`ifdef VERILATOR
    ,output logic [23:0] sim_rgb,     // pixel sent to HDMI (for testbench)
    output logic [10:0]  sim_cx,
    output logic [9:0]   sim_cy,
    output logic         sim_active
`endif
);

localparam VIDEOID = 4;              // 720p
localparam VIDEO_REFRESH = 60.0;
localparam CLKFRQ = 74250;           // 74.25 MHz in kHz
localparam AUDIO_BIT_WIDTH = 16;
localparam AUDIO_RATE = 48000;

// framebuffer geometry (measured on real RTL sim: 374x246 active)
localparam WIDTH = 256;              // stored pixels per line
localparam HEIGHT = 246;             // stored lines
localparam SRCW = 374;               // PONG active pixels per line
localparam MEM_DEPTH = WIDTH*HEIGHT; // 62976

// 2-bit pixels: 00 black, 01 dim (score), 10 white
logic [1:0] mem [0:MEM_DEPTH-1];
logic [15:0] mem_portA_addr;
logic [1:0]  mem_portA_wdata;
logic        mem_portA_we;
wire [15:0] mem_portB_addr;
logic [1:0]  mem_portB_rdata;

always_ff @(posedge clk) begin
    if (mem_portA_we) mem[mem_portA_addr] <= mem_portA_wdata;
end
always_ff @(posedge clk_pixel) begin
    mem_portB_rdata <= mem[mem_portB_addr];
end

initial begin
    $readmemb("pong_background.txt", mem);
end

//
// Capture side (clk domain): decimate 374 -> 256, store 246 lines
//
logic hb_r, vb_r;
logic [7:0] wx;
logic [7:0] wy;
logic [9:0] acc;                     // fractional accumulator 0..629
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        hb_r <= 0; vb_r <= 0; wx <= 0; wy <= 0; acc <= 0;
        mem_portA_we <= 0;
        mem_portA_addr <= 0; mem_portA_wdata <= 0;
    end else begin
        hb_r <= hblank; vb_r <= vblank;
        mem_portA_we <= 0;
        if (vblank && !vb_r) begin
            wy <= 0; wx <= 0; acc <= 0;         // end of visible frame
        end else if (!vblank) begin
            if (hblank && !hb_r) begin
                if (wx != 0 && wy < 8'(HEIGHT-1)) wy <= wy + 1;
                wx <= 0; acc <= 0;              // end of line
            end else if (!hblank) begin
                if (acc + 256 >= SRCW) begin   // emit one stored pixel
                    acc <= acc + 256 - SRCW;
                    mem_portA_addr <= {wy, wx};
                    mem_portA_wdata <= (r == 4'hF) ? 2'b10 :
                                       (r == 4'hB) ? 2'b01 : 2'b00;
                    mem_portA_we <= (wy < 8'(HEIGHT));
                    if (wx < 8'(WIDTH-1)) wx <= wx + 1;
                end else begin
                    acc <= acc + 256;
                end
            end
        end
    end
end

//
// Audio side: 48 kHz strobe + 1-bit beep to 16-bit signed square
//
localparam AUDIO_CLK_DELAY = CLKFRQ * 1000 / AUDIO_RATE / 2;
localparam [9:0] AUDIO_DIV_END = AUDIO_CLK_DELAY - 1;
logic [$clog2(AUDIO_CLK_DELAY)-1:0] audio_divider;
logic clk_audio;
always_ff @(posedge clk_pixel or negedge resetn) begin
    if (!resetn) begin audio_divider <= 0; clk_audio <= 0; end
    else if (audio_divider != AUDIO_DIV_END)
        audio_divider <= audio_divider + 1;
    else begin clk_audio <= ~clk_audio; audio_divider <= 0; end
end

logic snd_r, snd_rr;
always_ff @(posedge clk_pixel or negedge resetn) begin
    if (!resetn) begin snd_r <= 0; snd_rr <= 0; end
    else begin snd_r <= sound; snd_rr <= snd_r; end
end

logic signed [15:0] sample;
reg [15:0] audio_sample_word [1:0];
always_ff @(posedge clk_pixel or negedge resetn) begin
    if (!resetn) begin
        sample <= 0; audio_sample_word[0] <= 0; audio_sample_word[1] <= 0;
    end else begin
        sample <= snd_rr ? 16'sh2000 : -16'sh2000;
        audio_sample_word[0] <= sample;
        audio_sample_word[1] <= sample;
    end
end

//
// Display side (clk_pixel domain): fractional scale 256x246 -> 960x720
//
wire [9:0] cy;
wire [10:0] cx;
localparam XSTART = (1280-960)/2;    // 160
localparam XSTOP = (1280+960)/2;     // 1120

reg [23:0] rgb;
reg active;
reg [7:0] xx;
reg [7:0] yy;
reg [10:0] xcnt;
reg [10:0] ycnt;
reg [9:0] cy_r;
assign mem_portB_addr = {yy, 8'd0} + {8'd0, xx};
assign overlay_x = xx;
assign overlay_y = yy;

always @(posedge clk_pixel or negedge resetn) begin
    reg active_t;
    reg [10:0] xcnt_next;
    reg [10:0] ycnt_next;
    if (!resetn) begin
        active <= 0; xx <= 0; yy <= 0; xcnt <= 0; ycnt <= 0; cy_r <= 0;
    end else begin
        xcnt_next = xcnt + 256;
        ycnt_next = ycnt + HEIGHT;

        active_t = 0;
        if (cx == XSTART-1) begin active_t = 1; active <= 1; end
        else if (cx == XSTOP-1) begin active_t = 0; active <= 0; end

        if (active_t | active) begin
            xcnt <= xcnt_next;
            if (xcnt_next >= 960) begin xcnt <= xcnt_next - 960; xx <= xx + 1; end
        end

        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin
            ycnt <= ycnt_next;
            if (ycnt_next >= 720) begin ycnt <= ycnt_next - 720; yy <= yy + 1; end
        end

        if (cx == 0) begin xx <= 0; xcnt <= 0; end
        if (cy == 0) begin yy <= 0; ycnt <= 0; end
    end
end

function [23:0] pong_palette(input [1:0] p);
    case (p)
        2'b10:   pong_palette = 24'hFFFFFF;   // paddles / net / ball
        2'b01:   pong_palette = 24'hBBBBBB;   // score digits (dimmer)
        default: pong_palette = 24'h000000;
    endcase
endfunction

always @(posedge clk_pixel) begin
    if (active) begin
        if (overlay)
            rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};
        else
            rgb <= pong_palette(mem_portB_rdata);
    end else
        rgb <= 24'h303030;
end

//
// HDMI output (hdl-util/hdmi core, same as NESTang)
//
logic [2:0] tmds;
logic tmdsClk;
logic [10:0] frameWidth;
logic [9:0] frameHeight;
logic [10:0] screenWidth;
logic [9:0] screenHeight;

hdmi #(.VIDEO_ID_CODE(VIDEOID),
       .DVI_OUTPUT(0),
       .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
       .IT_CONTENT(1),
       .AUDIO_RATE(AUDIO_RATE),
       .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
       .VENDOR_NAME("TangCore"),
       .PRODUCT_DESCRIPTION({"PongTang", 64'd0}),
       .START_X(0),
       .START_Y(0))
hdmi (.clk_pixel_x5(clk_5x_pixel),
      .clk_pixel(clk_pixel),
      .clk_audio(clk_audio),
      .rgb(rgb),
      .reset(~resetn),
      .audio_sample_word(audio_sample_word),
      .tmds(tmds),
      .tmds_clock(tmdsClk),
      .cx(cx),
      .cy(cy),
      .frame_width(frameWidth),
      .frame_height(frameHeight),
      .screen_width(screenWidth),
      .screen_height(screenHeight));

`ifndef VERILATOR
// Gowin LVDS output buffers (pixel clock on the clock pair, as in NESTang)
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_pixel, tmds}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);
`else
assign {tmds_clk_p, tmds_d_p} = 0;
assign {tmds_clk_n, tmds_d_n} = 0;
assign sim_rgb = rgb;
assign sim_cx = cx;
assign sim_cy = cy;
assign sim_active = active;
`endif

endmodule
