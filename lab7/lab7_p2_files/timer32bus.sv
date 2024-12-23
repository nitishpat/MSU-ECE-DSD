`timescale 1ns / 1ps
module timer32bus (
    clk,
    reset,
    din,
    dout,
    wren,
    rden,
    addr
);

    input clk, reset, wren, rden;
    input [31:0] din;
    output [31:0] dout;
    // 24 bit address
    input [23:0] addr;

    // 20-bit decode, compare against addr[23:4]
    parameter TMR1_RANGE = 20'h9250A;
    parameter TMR2_RANGE = 20'h3C74D;

endmodule
