#!/usr/bin/env python3
"""Generate the PONG menu-logo defparams for gowin_dpb_menu.v.

Logo canvas: 72x14 monochrome (same format as NESTang logo.py):
"PONG" in double-size 5x7, framed by paddles + balls.
Outputs the 4 INIT_RAM_1C..1F defparam lines + ASCII preview.
"""
FONT = {
    'P': [".XXX.", "X...X", "X...X", "XXXXX", "X....", "X....", "X...."],
    'O': [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
    'N': ["X...X", "XX..X", "XX..X", "X.X.X", "X..XX", "X..XX", "X...X"],
    'G': [".XXXX", "X....", "X....", "X.XXX", "X...X", "X...X", ".XXX."],
}

W, H = 72, 14
px = [['0'] * W for _ in range(H)]

def put(x, y, rows):
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == 'X':
                px[y + r][x + c] = '1'

# "PONG" at 2x (each char 10 wide x 14 tall), centered-ish
text = "PONG"
x0 = 13
for i, ch in enumerate(text):
    big = []
    for row in FONT[ch]:
        wide = ''.join(c * 2 for c in row)
        big += [wide, wide]
    put(x0 + i * 12, 0, big)

# paddles (2 wide x 8 tall) + balls (2x2)
for y in range(3, 11):
    px[y][2] = px[y][3] = '1'
    px[y][68] = px[y][69] = '1'
for y in (6, 7):
    px[y][8] = px[y][9] = '1'
    px[y][62] = px[y][63] = '1'

LOGO = [''.join(r) for r in px]
for row in LOGO:                       # ASCII preview on stderr
    import sys
    print(row.replace('0', '.').replace('1', '#'), file=sys.stderr)

r = []
for i in range(126):
    j = i % 9
    s = LOGO[i // 9][j * 8:j * 8 + 8]
    b = 0
    for k in range(8):
        if s[k] == '1':
            b += 1 << k
    r.append(b)
assert len(r) == 126
r += [0, 0]
for i in range(4):
    off = i * 32
    print("defparam dpb_inst_0.INIT_RAM_{:02X} = 256'h".format(0x1C + i), end='')
    for j in range(31, -1, -1):
        print("{:02X}".format(r[off + j]), end='')
    print(';')
