`timescale 1ns / 1ps

// top_digital_clock_board：板上顶层封装。
// - 上电复位
// - KEY1..KEY4 = btn[3:0]（低有效）；SW4=sw_group、SW3=sw_edit（电平，拨上=1）
//   物理映射：KEY1=E3, KEY2=G4, KEY3=P19, KEY4=R19; SW4=N15, SW3=R17

module top_digital_clock_board (
    input  wire       sys_clk,
    input  wire [3:0] btn,           // KEY1..KEY4（低有效）
    input  wire       sw_group,      // SW4：1=闹钟/倒计时组
    input  wire       sw_edit,       // SW3：1=编辑
    output wire [7:0] seg,
    output wire [7:0] sel,
    output wire [3:0] led           // LED1..3=闹钟，LED4=倒计时（高点亮）
);

    reg [21:0] rst_cnt;
    wire rst_n = &rst_cnt;
    always @(posedge sys_clk) begin
        if (!rst_n) rst_cnt <= rst_cnt + 22'd1;
    end

    top_digital_clock u_clock (
        .i_clk  (sys_clk),
        .i_rst_n(rst_n),
        .i_key  ({2'b11, btn[3], btn[2], btn[1], btn[0]}),
        .i_sw_group(sw_group),
        .i_sw_edit (sw_edit),
        .o_seg  (seg),
        .o_sel  (sel),
        .o_led  (led)
    );

endmodule
