// tb_pong.cpp - Baseline testbench for PONG game logic (MiSTer/Richard Eng RTL)
//
//  1. Runs the `pong` module (7.159 MHz clock, C++ driven)
//  2. Measures video timing: clocks/line (455), lines/frame (262), active window
//  3. Inserts coin, moves P1 paddle, prints a per-frame trace:
//     paddle positions, ball bbox, score digit activity
//  4. Captures screenshots (attract + gameplay) as BMP
//  5. PASS/FAIL checks
//
// Build: make        Run: make run
#include "Vpong.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static void write_bmp(const char* path, const std::vector<uint8_t>& px, int w, int h) {
    int rowstride = (w * 3 + 3) & ~3;
    int imgsz = rowstride * h;
    int filesz = 54 + imgsz;
    FILE* f = fopen(path, "wb");
    if (!f) { printf("ERROR: cannot write %s\n", path); return; }
    uint8_t hdr[54] = {0};
    hdr[0]='B'; hdr[1]='M';
    hdr[2]=filesz; hdr[3]=filesz>>8; hdr[4]=filesz>>16; hdr[5]=filesz>>24;
    hdr[10]=54; hdr[14]=40;
    hdr[18]=w; hdr[19]=w>>8; hdr[20]=w>>16; hdr[21]=w>>24;
    hdr[22]=h; hdr[23]=h>>8; hdr[24]=h>>16; hdr[25]=h>>24;
    hdr[26]=1; hdr[28]=24;
    hdr[34]=imgsz; hdr[35]=imgsz>>8; hdr[36]=imgsz>>16; hdr[37]=imgsz>>24;
    fwrite(hdr,1,54,f);
    std::vector<uint8_t> row(rowstride, 0);
    for (int y = h-1; y >= 0; --y) {
        for (int x = 0; x < w; ++x) {
            uint8_t g = px[(size_t)y*w+x];
            row[x*3]=g; row[x*3+1]=g; row[x*3+2]=g;
        }
        fwrite(row.data(),1,(size_t)rowstride,f);
    }
    fclose(f);
    printf("wrote %s (%dx%d)\n", path, w, h);
}

static uint32_t fnv1a(const std::vector<uint8_t>& px) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < px.size(); ++i) { h ^= px[i]; h *= 16777619u; }
    return h;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vpong* top = new Vpong;

    const int MAXW = 512, MAXH = 320;
    std::vector<uint8_t> fb((size_t)MAXW*MAXH, 0);

    const int COIN_AT_FRAME = 3;
    const int STOP_AT_FRAME = 220;

    top->coin_sw = 0;
    top->dip_sw = 0;               // 11 points game
    top->paddle1_vpos = 128;
    top->paddle2_vpos = 128;

    int prev_hb = 0, prev_vb = 0, prev_hs = 0;
    int frame = 0, x = 0, y = 0, xmax = 0, coin_hold = 0;
    int total_lines = 0;           // hblank risings per frame (all lines)
    long cycle = 0, last_hs_cycle = -1;
    long hs_min = 1<<30, hs_max = 0;
    bool coin_done = false, motion = false, ball_seen = false;
    uint32_t h0 = 0;
    int p1_attract = -1, p1_play = -1;
    std::vector<uint8_t> shotA, shotB, shotC;
    int sAw=0,sAh=0,sBw=0,sBh=0,sCw=0,sCh=0;

    printf("fr | lines | P1y P2y | ball(x0,y0,x1,y1,n) | scoreL scoreR | hash\n");

    while (frame < STOP_AT_FRAME && cycle < 30000000L) {
        top->clk7_159 = 1; top->eval();
        top->clk7_159 = 0; top->eval();
        cycle++;

        int hb = top->hblank ? 1 : 0;
        int vb = top->vblank ? 1 : 0;
        int hs = top->hsync ? 1 : 0;

        if (hs && !prev_hs) {
            if (last_hs_cycle >= 0) {
                long p = cycle - last_hs_cycle;
                if (p < hs_min) hs_min = p;
                if (p > hs_max) hs_max = p;
            }
            last_hs_cycle = cycle;
        }
        if (hb && !prev_hb) total_lines++;          // every line, incl. vblank

        if (vb && !prev_vb) {                       // ---- end of frame ----
            int W = xmax, H = y;
            // compact framebuffer
            std::vector<uint8_t> fr((size_t)W*H, 0);
            for (int r = 0; r < H; ++r)
                for (int c = 0; c < W; ++c) fr[(size_t)r*W+c] = fb[(size_t)r*MAXW+c];
            uint32_t hh = fnv1a(fr);
            if (frame == 0) h0 = hh;
            if (frame > 0 && hh != h0) motion = true;

            // find net column (most white px in middle rows)
            int netx = W/2, netbest = -1;
            for (int c = 0; c < W; ++c) {
                int n = 0;
                for (int r = 50; r < H-10; ++r) if (fr[(size_t)r*W+c] > 100) n++;
                if (n > netbest) { netbest = n; netx = c; }
            }
            // paddle zones (P1 left, P2 right), ball zone (middle, below score)
            int p1n=0,p1ysum=0,p2n=0,p2ysum=0;
            int bx0=W,by0=H,bx1=0,by1=0,balln=0;
            int scL=0, scR=0;
            for (int r = 0; r < H; ++r) {
                for (int c = 0; c < W; ++c) {
                    if (fr[(size_t)r*W+c] < 100) continue;
                    if (r < 45) {  // score row
                        if (c < W/2) scL++; else scR++;
                    } else if (c < 60) { p1n++; p1ysum += r; }
                    else if (c >= W-78) { p2n++; p2ysum += r; }
                    else if ((c < netx-3 || c > netx+3) && r > 55) {
                        balln++;
                        if (c<bx0)bx0=c; if (c>bx1)bx1=c;
                        if (r<by0)by0=r; if (r>by1)by1=r;
                    }
                }
            }
            int p1y = p1n ? p1ysum/p1n : -1;
            int p2y = p2n ? p2ysum/p2n : -1;
            if (balln > 0) ball_seen = true;
            if (frame == 90) p1_attract = p1y;
            if (frame == 120) p1_play = p1y;
            printf("%2d | %3d | %3d[%d] %3d[%d] | ball(%3d,%3d,%3d,%3d,n=%4d) | sc %5d %5d | %08x%s\n",
                   frame, total_lines, p1y, p1n, p2y, p2n,
                   balln?bx0:-1, balln?by0:-1, balln?bx1:-1, balln?by1:-1, balln,
                   scL, scR, hh, (frame==COIN_AT_FRAME)?"  <-- coin":"");
            if (frame == 1)   { shotA = fr; sAw=W; sAh=H; }
            if (frame == 110) { shotB = fr; sBw=W; sBh=H; }
            if (frame == STOP_AT_FRAME-1) { shotC = fr; sCw=W; sCh=H; }

            frame++; y = 0; x = 0; xmax = 0; total_lines = 0;
        } else if (!vb) {
            if (hb && !prev_hb) {
                if (x > xmax) xmax = x;
                if (x > 0) y++;
                x = 0;
            }
            if (!hb) {
                if (x < MAXW && y < MAXH) {
                    uint8_t r = top->r & 0xF;
                    fb[(size_t)y*MAXW+x] = (r == 0xF) ? 255 : (r == 0xB) ? 170 : (uint8_t)(r*17);
                }
                x++;
            }
        }

        if (frame == COIN_AT_FRAME && y > 20 && !coin_done) {
            top->coin_sw = 1;
            if (++coin_hold > 20000) { top->coin_sw = 0; coin_done = true; }
            top->paddle1_vpos = 200;
        }
        if (frame == 100) top->paddle1_vpos = 60;  // live input test (outside coin-if!)

        prev_hb = hb; prev_vb = vb; prev_hs = hs;
    }
    top->final();

    printf("---- summary: cycles=%ld frames=%d hsync=[%ld..%ld] ----\n", cycle, frame, hs_min, hs_max);
    bool ok = true;
    if (hs_min != 455 || hs_max != 455) { printf("FAIL: hsync period\n"); ok = false; }
    if (!motion)                        { printf("FAIL: no motion\n"); ok = false; }
    if (!ball_seen)                     { printf("FAIL: ball never visible\n"); ok = false; }
    if (p1_attract < 0 || p1_play < 0 || p1_attract == p1_play)
                                        { printf("FAIL: P1 paddle did not move\n"); ok = false; }
    if (!shotA.empty()) write_bmp("frame_attract.bmp", shotA, sAw, sAh);
    if (!shotB.empty()) write_bmp("frame_early.bmp", shotB, sBw, sBh);
    if (!shotC.empty()) write_bmp("frame_play.bmp", shotC, sCw, sCh);
    printf(ok ? "BASELINE: PASS\n" : "BASELINE: FAIL\n");
    delete top;
    return ok ? 0 : 1;
}
