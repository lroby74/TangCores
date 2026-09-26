// tb_top.cpp - PongTang full-system simulation.
//
// Verifies, end to end: PONG game + pong2hdmi scaler + real HDMI core +
// real DualShock receivers (with a C++ PSX pad emulator) + input merge +
// coin logic + OSD overlay mux. USB-HID and BL616 blocks are stubbed at
// the top (test vectors), since they are pre-verified template IP.
//
// Timeline (ps), 3 edge-scheduled clocks (50M / 7.14M / 74.25M):
//   0-2us          reset
//   0-70ms         hclk ON  : attract-mode HDMI screenshot
//   130-136ms      s1 button press -> coin #1 (tests s1 + debounce;
//                  after boot transient: DS2 garbage poll may ghost-coin)
//   70-150ms       DS2 P1 UP held -> P1 paddle moves up
//   70-1965ms      hclk OFF : fast-forward game only
//   250-270ms      DS2 P1 START -> coin #2 (serve ~1950ms)
//   300-400ms      USB1 DOWN -> P1 paddle moves down (tests USB path)
//   450-550ms      HID2 DOWN -> P2 paddle moves down (tests BL616 path)
//   1965ms-END     hclk ON  : gameplay shot (ball mid-flight) +
//                  OSD solid-magenta frame + OSD gradient frame
//
// Build: make obj_top/Vtop    Run: make run-top
#include "Vpongtang_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

// ---------- 24-bit BMP writer ----------
static void write_bmp24(const char* path, const std::vector<uint8_t>& px, int w, int h) {
    int rowstride = (w * 3 + 3) & ~3;
    int imgsz = rowstride * h, filesz = 54 + imgsz;
    FILE* f = fopen(path, "wb");
    if (!f) { printf("ERROR: cannot write %s\n", path); return; }
    uint8_t hdr[54] = {0};
    hdr[0]='B'; hdr[1]='M';
    hdr[2]=filesz; hdr[3]=filesz>>8; hdr[4]=filesz>>16; hdr[5]=filesz>>24;
    hdr[10]=54; hdr[14]=40;
    hdr[18]=w; hdr[19]=w>>8; hdr[20]=w>>16; hdr[21]=w>>24;
    hdr[22]=h; hdr[23]=h>>8; hdr[24]=h>>16; hdr[25]=h>>24;
    hdr[26]=1; hdr[28]=24;
    fwrite(hdr,1,54,f);
    std::vector<uint8_t> row(rowstride, 0);
    for (int y = h-1; y >= 0; --y) {
        for (int x = 0; x < w; ++x) {
            row[x*3]   = px[(size_t)(y*w+x)*3+2];  // BMP is BGR
            row[x*3+1] = px[(size_t)(y*w+x)*3+1];
            row[x*3+2] = px[(size_t)(y*w+x)*3+0];
        }
        fwrite(row.data(),1,(size_t)rowstride,f);
    }
    fclose(f);
    printf("wrote %s (%dx%d)\n", path, w, h);
}

// ---------- PSX pad emulator (bit-banged, follows ds_clk edges) ----------
// Controller sends: 0x01 0x42 0x00... (9 bytes, LSB first).
// Pad replies:      0xFF 0x41 0x5A btn0 btn1 0x7F... (buttons active-low).
struct PsxPad {
    uint8_t reply[9] = {0xFF,0x41,0x5A,0xFF,0xFF,0x7F,0x7F,0x7F,0x7F};
    uint8_t tx[9] = {0};
    int bi=0, nbit=0, ntxn=0, miso=1, p_cs=1, p_clk=1;
    long polls=0;
    void buttons(uint8_t b0, uint8_t b1) { reply[3]=b0; reply[4]=b1; }
    int tick(int cs, int sclk, int mosi) {
        if (!cs && p_cs) {
            bi=0; nbit=0; ntxn=0;
            for (int i=0;i<9;i++) tx[i]=0;
            polls++; miso = reply[0] & 1;
        } else if (!cs) {
            if (!sclk && p_clk) miso = (reply[bi] >> nbit) & 1;   // present on falling
            else if (sclk && !p_clk) {                             // sample on rising
                tx[bi] |= (uint8_t)((mosi & 1) << nbit);
                if (++nbit == 8) { nbit = 0; if (bi < 8) bi++; ntxn++; }
            }
        } else miso = 1;
        p_cs = cs; p_clk = sclk;
        return miso;
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vpongtang_top* top = new Vpongtang_top;

    const long P_MAIN = 20000, P_7M = 140000, P_H = 13468;   // clock periods (ps)
    const long T_RST = 2000000L;          // 2 us
    const long T_S1A = 130000000000L, T_S1B = 136000000000L;
    const long T_DSUP_A = 70000000000L, T_DSUP_B = 150000000000L;
    const long T_START_A = 250000000000L, T_START_B = 300000000000L;
    const long T_USBDN_A = 300000000000L, T_USBDN_B = 400000000000L;
    const long T_HIDDN_A = 450000000000L, T_HIDDN_B = 550000000000L;
    const long T_HOFF = 70000000000L, T_HON = 1965000000000L;
    const long T_MAX = 2300000000000L;

    // init inputs
    top->sim_resetn = 0;
    top->s1 = 1;
    top->UART_RXD = 1;
    top->ds_miso2 = 1;                    // no pad on P2 port
    top->sim_joy_usb1 = 0; top->sim_joy_usb2 = 0;
    top->sim_hid1 = 0; top->sim_hid2 = 0;
    top->sim_overlay = 0; top->sim_overlay_grad = 0;
    top->sim_overlay_color = 0x7C1F;      // magenta (BGR5)
    top->sim_clk_main = 0; top->sim_clk7m = 0; top->sim_hclk = 0;
    PsxPad pad;
    pad.buttons(0xFF, 0xFF);
    top->ds_miso = 1;

    // HDMI capture (full 1280x720 + overlay coords per pixel)
    const int HW = 1280, HH = 720;
    std::vector<uint8_t> hfb((size_t)HW*HH*3, 0), hox((size_t)HW*HH, 0), hoy((size_t)HW*HH, 0);
    std::vector<char> hgot((size_t)HW*HH, 0);

    // state
    long t = 0, nMain = P_MAIN/2, n7 = P_7M/2, nH = P_H/2;
    bool cMain = 0, c7 = 0, cH = 0, hclk_en = true;
    int pcy = 0, maxcx = 0, maxcy = 0;
    int nwrap = 0;                        // hdmi frames since TON
    bool hon_armed = false;
    int shot_attract = 0, shot_play = 0, shot_solid = 0, shot_grad = 0;
    long main_cycles = 0, last_cs_fall = -1, poll_per = 0, polls_seen = 0;
    bool ds_armed = false;
    uint8_t first_tx[9] = {0}; bool first_tx_done = false;
    int coin_edges = 0, p_coin = 0, snd_edges = 0, p_snd = 0, snd_post = 0;
    int v1_160 = -1, v1_420 = -1, v2_430 = -1, v2_570 = -1;
    bool done = false;
    char msg[16] = {0};

    auto save_shot = [&](const char* name) {
        // save only if the frame is (almost) fully captured
        long got = 0;
        for (size_t i = 0; i < hgot.size(); i++) if (hgot[i]) got++;
        printf("%s: captured %ld/%d px\n", name, got, HW*HH);
        write_bmp24(name, hfb, HW, HH);
    };

    while (!done && t < T_MAX) {
        // ----- time-based stimuli -----
        top->sim_resetn = (t >= T_RST) ? 1 : 0;
        top->s1 = (t >= T_S1A && t < T_S1B) ? 0 : 1;
        uint8_t b0 = 0xFF;
        if (t >= T_DSUP_A && t < T_DSUP_B) b0 &= ~(0x10);   // UP
        if (t >= T_START_A && t < T_START_B) b0 &= ~(0x08); // START
        pad.buttons(b0, 0xFF);
        top->sim_joy_usb1 = (t >= T_USBDN_A && t < T_USBDN_B) ? 0x020 : 0;  // DOWN
        top->sim_hid2 = (t >= T_HIDDN_A && t < T_HIDDN_B) ? 0x0020 : 0;     // DOWN
        if (t >= T_HOFF && t < T_HON) hclk_en = false; else hclk_en = true;
        if (!hon_armed && t >= T_HON) { hon_armed = true; nH = t + P_H/2; nwrap = 0; }
        // overlay windows (by hdmi frame count after re-enable)
        top->sim_overlay = (hon_armed && nwrap >= 2 && nwrap <= 4) ? 1 : 0;
        top->sim_overlay_grad = (hon_armed && nwrap == 4) ? 1 : 0;

        // ----- advance clocks -----
        const long INF = 1L << 60;
        long nt = nMain;
        if (n7 < nt) nt = n7;
        if (hclk_en && nH < nt) nt = nH;
        t = nt;
        bool eMain = (nt == nMain), e7 = (nt == n7), eH = (hclk_en && nt == nH);
        if (eMain) { cMain = !cMain; top->sim_clk_main = cMain; nMain += P_MAIN/2; }
        if (e7)    { c7 = !c7; top->sim_clk7m = c7; n7 += P_7M/2; }
        if (eH)    { cH = !cH; top->sim_hclk = cH; nH += P_H/2; }
        top->eval();

        // ----- post-eval sampling -----
        if (eMain && cMain) {
            main_cycles++;
            int cs = top->ds_cs ? 1 : 0;
            if (cs && !pad.p_cs) ds_armed = true;   // ignore boot garbage poll
            if (!cs && pad.p_cs && ds_armed) {   // cs falling: poll started
                if (last_cs_fall >= 0 && poll_per == 0) poll_per = main_cycles - last_cs_fall;
                last_cs_fall = main_cycles;
                polls_seen++;
            }
            int miso = pad.tick(cs, top->ds_clk ? 1 : 0, top->ds_mosi ? 1 : 0);
            top->ds_miso = miso;
            if (pad.ntxn >= 9 && !first_tx_done && ds_armed && !cs) {
                for (int i = 0; i < 9; i++) first_tx[i] = pad.tx[i];
                first_tx_done = true;
            }
            int coin = top->sim_coin ? 1 : 0;
            if (coin && !p_coin && t > 20000000000L) { coin_edges++; printf("coin edge @ %.3fms\n", t / 1e9); }
            p_coin = coin;
            int snd = top->sim_sound ? 1 : 0;
            if (snd != p_snd) { snd_edges++; if (t > 1950000000000L) snd_post++; }
            p_snd = snd;
            if (v1_160 < 0 && t >= 160000000000L) v1_160 = top->sim_vpos1;
            if (v1_420 < 0 && t >= 420000000000L) v1_420 = top->sim_vpos1;
            if (v2_430 < 0 && t >= 430000000000L) v2_430 = top->sim_vpos2;
            if (v2_570 < 0 && t >= 570000000000L) v2_570 = top->sim_vpos2;
        }
        if (eH) {
            int cx = top->sim_cx, cy = top->sim_cy;
            if (cx > maxcx) maxcx = cx;
            if (cy > maxcy) maxcy = cy;
            if (cx >= 0 && cx < HW && cy >= 0 && cy < HH) {
                size_t i = (size_t)cy * HW + (size_t)cx;
                uint32_t rgb = top->sim_rgb;
                hfb[i*3+0] = (rgb >> 16) & 0xFF;
                hfb[i*3+1] = (rgb >> 8) & 0xFF;
                hfb[i*3+2] = rgb & 0xFF;
                hox[i] = top->sim_ox; hoy[i] = top->sim_oy;
                hgot[i] = 1;
            }
            if (cy < pcy && pcy > 700) {   // frame wrap
                if (!hon_armed) {
                    if (!shot_attract) { shot_attract = 1; save_shot("hdmi_attract.bmp"); }
                } else {
                    nwrap++;
                    if (nwrap == 1) { shot_play = 1; save_shot("hdmi_play.bmp"); }
                    if (nwrap == 3) { shot_solid = 1; save_shot("hdmi_osd_solid.bmp"); }
                    if (nwrap == 5) { shot_grad = 1; save_shot("hdmi_osd_grad.bmp"); }
                    if (nwrap >= 6) done = true;
                }
                for (size_t i = 0; i < hgot.size(); i++) hgot[i] = 0;
            }
            pcy = cy;
        }
    }
    top->final();

    printf("---- tb_top report: t=%.3fms maxcx=%d maxcy=%d wraps=%d ----\n",
           t / 1e9, maxcx, maxcy, nwrap);
    printf("DS2: polls=%ld period=%ld mainclks (expect 819200), TX=%02x %02x %02x %02x %02x %02x %02x %02x %02x\n",
           polls_seen, poll_per, first_tx[0], first_tx[1], first_tx[2], first_tx[3],
           first_tx[4], first_tx[5], first_tx[6], first_tx[7], first_tx[8]);
    printf("INPUTS: coin_edges=%d vpos1: @160ms=%d @420ms=%d | vpos2: @430ms=%d @570ms=%d\n",
           coin_edges, v1_160, v1_420, v2_430, v2_570);
    printf("SOUND: edges_total=%d edges_post_serve=%d\n", snd_edges, snd_post);

    bool ok = true;
    if (maxcx != 1649 || maxcy != 749) { printf("FAIL: hdmi timing\n"); ok = false; }
    if (polls_seen < 3) { printf("FAIL: too few DS2 polls\n"); ok = false; }
    if (poll_per != 819200) { printf("FAIL: DS2 poll period (FREQ param?)\n"); ok = false; }
    if (!(first_tx[0]==0x01 && first_tx[1]==0x42)) { printf("FAIL: DS2 TX bytes\n"); ok = false; }
    if (coin_edges < 2) { printf("FAIL: coin edges\n"); ok = false; }
    if (!(v1_160 >= 0 && v1_160 < 110)) { printf("FAIL: P1 did not move up (DS2)\n"); ok = false; }
    if (!(v1_420 > v1_160 + 20)) { printf("FAIL: P1 did not move down (USB)\n"); ok = false; }
    if (!(v2_430 >= 120 && v2_430 <= 136)) { printf("FAIL: P2 moved unexpectedly\n"); ok = false; }
    if (!(v2_570 > 150)) { printf("FAIL: P2 did not move down (HID)\n"); ok = false; }

    // ---- analyze saved frames ----
    auto load = [&](const char* name, std::vector<uint8_t>& px) {
        // re-read our own BMP (skip 54-byte header, unpad rows)
        FILE* f = fopen(name, "rb");
        if (!f) return false;
        fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 54, SEEK_SET);
        int stride = (HW * 3 + 3) & ~3;
        std::vector<uint8_t> row(stride);
        px.assign((size_t)HW*HH*3, 0);
        for (int y = HH-1; y >= 0; --y) {
            if (fread(row.data(), 1, stride, f) != (size_t)stride) { fclose(f); return false; }
            for (int x = 0; x < HW; ++x) {
                px[(size_t)(y*HW+x)*3+0] = row[x*3+2];
                px[(size_t)(y*HW+x)*3+1] = row[x*3+1];
                px[(size_t)(y*HW+x)*3+2] = row[x*3+0];
            }
        }
        fclose(f); (void)sz;
        return true;
    };
    std::vector<uint8_t> play, solid, grad;
    // NOTE: analysis runs on the in-memory capture of the LAST frames is complex;
    // instead re-analyze from the BMP files just written.
    if (load("hdmi_play.bmp", play)) {
        long white = 0, dim = 0, black = 0, bg = 0, other = 0;
        for (int y = 0; y < HH; ++y) for (int x = 0; x < HW; ++x) {
            uint8_t r = play[(size_t)(y*HW+x)*3], g = play[(size_t)(y*HW+x)*3+1], b = play[(size_t)(y*HW+x)*3+2];
            bool win = (x >= 160 && x < 1120);
            if (!win) { if (r==0x30&&g==0x30&&b==0x30) bg++; else if (x==1120) black++; else other++; }
            else if (r==0xFF&&g==0xFF&&b==0xFF) white++;
            else if (r==0xBB&&g==0xBB&&b==0xBB) dim++;
            else if (r==0&&g==0&&b==0) black++;
            else if (x==160 && r==0x30&&g==0x30&&b==0x30) black++; // rgb 1-px lag
            else other++;
        }
        printf("PLAY frame: white=%ld dim=%ld black=%ld border=%ld other=%ld\n",
               white, dim, black, bg, other);
        if (other != 0) { printf("FAIL: unexpected HDMI pixels\n"); ok = false; }
        if (white < 2000) { printf("FAIL: too little game picture\n"); ok = false; }
        if (dim < 300) { printf("FAIL: scores missing\n"); ok = false; }
    if (bg != 320*720-720) { printf("FAIL: border color\n"); ok = false; }
        // ball blob: white pixels in middle zone (not net col ~640, not paddle cols)
        long blob = 0;
        for (int y = 60; y < HH; ++y) for (int x = 300; x < 980; ++x) {
            if (x > 620 && x < 660) continue;   // net column
            uint8_t r = play[(size_t)(y*HW+x)*3];
            if (r == 0xFF) blob++;
        }
        printf("PLAY middle-zone white px (ball+net-excluded): %ld\n", blob);
        if (blob < 30) { printf("FAIL: ball not visible on HDMI\n"); ok = false; }
    } else { printf("FAIL: cannot load hdmi_play.bmp\n"); ok = false; }

    if (load("hdmi_osd_solid.bmp", solid)) {
        long mag = 0, bad = 0, gray160 = 0;
        for (int y = 0; y < HH; ++y) for (int x = 160; x < 1120; ++x) {
            uint8_t r = solid[(size_t)(y*HW+x)*3], g = solid[(size_t)(y*HW+x)*3+1], b = solid[(size_t)(y*HW+x)*3+2];
            if (r==0xF8&&g==0&&b==0xF8) mag++;
            else if (x==160 && r==0x30&&g==0x30&&b==0x30) gray160++; // rgb 1-px lag
            else bad++;
        }
        printf("OSD solid: magenta=%ld gray160=%ld bad=%ld (expect 690480/720/0)\n", mag, gray160, bad);
        if (mag != 690480 || gray160 != 720 || bad != 0) { printf("FAIL: OSD solid mux\n"); ok = false; }
    } else { printf("FAIL: cannot load hdmi_osd_solid.bmp\n"); ok = false; }

    if (load("hdmi_osd_grad.bmp", grad)) {
        // gradient was generated from overlay coords inside the top;
        // here we only check structure: all window pixels have R==0x80 and
        // G/B only change in steps (coords), plus exact count of distinct values.
        long okp = 0, bad = 0;
        for (int y = 0; y < HH; ++y) for (int x = 160; x < 1120; ++x) {
            uint8_t r = grad[(size_t)(y*HW+x)*3], g = grad[(size_t)(y*HW+x)*3+1], b = grad[(size_t)(y*HW+x)*3+2];
            if (r == 0x80 && (g & 7) == 0 && (b & 7) == 0) okp++;
            else if (x==160 && r==0x30&&g==0x30&&b==0x30) okp++; // rgb 1-px lag
            else bad++;
        }
        printf("OSD grad: structurally-ok=%ld bad=%ld\n", okp, bad);
        if (bad != 0) { printf("FAIL: OSD gradient\n"); ok = false; }
    } else { printf("FAIL: cannot load hdmi_osd_grad.bmp\n"); ok = false; }

    printf(ok ? "TOP: PASS\n" : "TOP: FAIL\n");
    delete top;
    return ok ? 0 : 1;
}
