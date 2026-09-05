`timescale 1ns / 1ps

// seg_driver：八位数码管动态扫描。每来一个 500Hz 使能脉冲切换一位。
// 段码位序 bit0=a .. bit6=g, bit7=dp（内部"亮=1"），可整体取反（共阳极板）。
// 位选/段码极性通过参数适配硬件。blank=1 熄灭该位（含 dp）。

module seg_driver #(
    parameter SEL_ACTIVE_LOW = 0,   // 1 = 位选低有效
    parameter SEG_ACTIVE_LOW = 0,   // 1 = 共阳极，段码低电平点亮（取反输出）
    parameter SCAN_DIV       = 25_000  // 每位点亮时长（clk 周期），约 0.5ms@50M
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_flag_500hz, // 保留端口（扫描改用内部计时器）
    input  wire [31:0] i_digit,      // 8 位 BCD，nibble7=位0（最左）
    input  wire [7:0]  i_dp,         // bit n = 位 n 的小数点
    input  wire [7:0]  i_blank,      // bit n = 熄灭位 n
    output reg  [7:0]  o_seg,
    output reg  [7:0]  o_sel
);

    reg [2:0] pos_r;
    reg [14:0] cnt_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            pos_r <= 3'd0;
            cnt_r <= 15'd0;
        end else if (cnt_r >= SCAN_DIV[14:0] - 15'd1) begin
            cnt_r <= 15'd0;
            pos_r <= (pos_r == 3'd7) ? 3'd0 : pos_r + 3'd1;
        end else begin
            cnt_r <= cnt_r + 15'd1;
        end
    end

    wire [3:0] dig_w = i_digit[pos_r*4 +: 4];

    reg [7:0] code_r;               // 内部亮=1：{dp=0,g..a}
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
        o_sel = SEL_ACTIVE_LOW ? ~(8'd1 << pos_r) : (8'd1 << pos_r);
        if (i_blank[pos_r])
            o_seg = SEG_ACTIVE_LOW ? 8'hFF : 8'h00;
        else if (SEG_ACTIVE_LOW)
            o_seg = ~(code_r | (i_dp[pos_r] ? 8'h80 : 8'h00));
        else
            o_seg = code_r | (i_dp[pos_r] ? 8'h80 : 8'h00);
    end

endmodule
