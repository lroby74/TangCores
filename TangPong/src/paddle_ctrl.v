// Digital paddle control for PongTang.
// The original PONG used potentiometers (absolute position); with D-pads and
// sticks we move the paddle at constant velocity while held.
// vpos mapping (measured): higher vpos = lower on screen.
`default_nettype none

module paddle_ctrl #(
    parameter SPEED = 6,          // vpos steps per frame (~0.7 s full travel)
    parameter [7:0] INIT = 128
) (
    input  wire       clk,        // clk7m (game clock)
    input  wire       resetn,
    input  wire       vsync,      // frame tick from game
    input  wire       up,         // active-high, synchronous to clk
    input  wire       down,       // active-high, synchronous to clk
    output reg  [7:0] vpos = INIT
);

reg vsync_r;
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        vsync_r <= 0;
        vpos <= INIT;
    end else begin
        vsync_r <= vsync;
        if (vsync && !vsync_r) begin
            if (up && !down)
                vpos <= (vpos >= SPEED) ? vpos - SPEED : 8'd0;
            else if (down && !up)
                vpos <= (vpos <= 8'd255 - SPEED) ? vpos + SPEED : 8'd255;
        end
    end
end

endmodule
`default_nettype wire
