`timescale 1ns / 1ps

// top_digital_clock_board：板上顶层封装。
// - 产生上电复位（计数器延时后释放 i_rst_n）
// - 将 4 个按键 + 2 个开关按固定顺序接入 top_digital_clock 的 i_key[5:0]
//   顺序：KEY0=MODE KEY1=SEL KEY2=+ KEY3=- KEY4=SW1(启动/解除) KEY5=SW2(复位)
// 按键/开关均低电平触发（开关拨下=按下一次）。

module top_digital_clock_board (
    input  wire       sys_clk,       // 50MHz, Y18
    input  wire [3:0] btn,           // btn[0]~btn[3] = MODE/SEL/+/-
    input  wire       sw1,           // 启动/暂停/解除
    input  wire       sw2,           // 复位
    output wire [7:0] seg,           // 共阳段码（低点亮） a..g,dp
    output wire [7:0] sel,           // 位选（高有效）
    output wire       led            // 提醒 LED（高点亮）
);

    reg [21:0] rst_cnt;
    wire rst_n = &rst_cnt;           // 上电计数满后复位释放（约 84ms@50M）

    always @(posedge sys_clk) begin
        if (!rst_n)
            rst_cnt <= rst_cnt + 22'd1;
    end

    top_digital_clock u_clock (
        .i_clk  (sys_clk),
        .i_rst_n(rst_n),
        .i_key  ({sw2, sw1, btn[3], btn[2], btn[1], btn[0]}),
        .o_seg  (seg),
        .o_sel  (sel),
        .o_led  (led)
    );

endmodule
