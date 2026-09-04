`timescale 1ns / 1ps

// seg_driver：六位数码管动态扫描。每来一个 500Hz 使能脉冲切换一位，
// 段码/位选同时输出；支持逐位小数点和整位熄灭（闪烁/空白）。

module seg_driver (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_flag_500hz,  // 扫描节拍
    input  wire [23:0] i_digit,       // 6 位 BCD（位序：下标 5..0 = 显示左→右）
    input  wire [5:0]  i_dp,          // 各位小数点（1=亮）
    input  wire [5:0]  i_blank,       // 各位熄灭（1=灭）
    output reg  [7:0]  o_seg,         // {dp,g,f,e,d,c,b,a}，亮为 1
    output reg  [5:0]  o_sel          // 位选，1 有效（可参数化取反）
);

    parameter SEL_ACTIVE_LOW = 0;     // 1 = 位选低有效

    reg [2:0] pos_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            pos_r <= 3'd0;
        else if (i_flag_500hz)
            pos_r <= (pos_r == 3'd5) ? 3'd0 : pos_r + 3'd1;
    end

    wire [3:0] dig_w = i_digit[pos_r*4 +: 4];

    // 共阴 7 段（亮为 1）：seg {dp,g,f,e,d,c,b,a}
    reg [7:0] code_r;
    always @(*) begin
        case (dig_w)
            4'h0: code_r = 8'h3F; 4'h1: code_r = 8'h06;
            4'h2: code_r = 8'h5B; 4'h3: code_r = 8'h4F;
            4'h4: code_r = 8'h66; 4'h5: code_r = 8'h6D;
            4'h6: code_r = 8'h7D; 4'h7: code_r = 8'h07;
            4'h8: code_r = 8'h7F; 4'h9: code_r = 8'h6F;
            4'hA: code_r = 8'h77; 4'hB: code_r = 8'h7C;
            4'hC: code_r = 8'h39; 4'hD: code_r = 8'h5E;
            4'hE: code_r = 8'h79; 4'hF: code_r = 8'h71;
            default: code_r = 8'h00;
        endcase
    end

    always @(*) begin
        o_sel = SEL_ACTIVE_LOW ? ~(6'd1 << pos_r) : (6'd1 << pos_r);
        if (i_blank[pos_r])
            o_seg = 8'h00;
        else
            o_seg = code_r | (i_dp[pos_r] ? 8'h80 : 8'h00);
    end

endmodule
