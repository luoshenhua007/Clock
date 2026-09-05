`timescale 1ns / 1ps

// alarm_led：LED 提醒输出。闹钟响铃期间按 2Hz 闪烁（持续时长由 alarm_clock 控制）；
// 倒计时结束时检测 done 上升沿启动内部 5s 闪烁；两者取其或。

module alarm_led (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_flag_1s,     // 秒节拍（5s 计时）
    input  wire i_flag_2hz,    // 闪烁节拍
    input  wire i_alarm_ring,  // 闹钟响铃中
    input  wire i_cnt_done,    // 倒计时结束
    output reg  o_led
);

    localparam CNT_5S = 5;

    reg       done_d1_r;
    reg       cnt5_r;          // 倒计时结束 5s 闪烁使能
    reg [2:0] cnt_r;

    // 2Hz 方波：每来一个 flag_2hz 脉冲翻转一次（约 1Hz 亮/灭）
    reg blk_ph;
    wire blk_out;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            blk_ph <= 1'b0;
        else if (i_flag_2hz)
            blk_ph <= ~blk_ph;
    end
    assign blk_out = blk_ph;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            done_d1_r <= 1'b0;
            cnt5_r    <= 1'b0;
            cnt_r     <= 3'd0;
            o_led     <= 1'b0;
        end else begin
            done_d1_r <= i_cnt_done;
            // done 上升沿 -> 启动 5s 闪烁
            if (i_cnt_done && !done_d1_r) begin
                cnt5_r <= 1'b1;
                cnt_r  <= 3'd0;
            end
            if (cnt5_r && i_flag_1s) begin
                if (cnt_r >= CNT_5S - 1) begin
                    cnt5_r <= 1'b0;
                    cnt_r  <= 3'd0;
                end else begin
                    cnt_r <= cnt_r + 3'd1;
                end
            end
            o_led <= (i_alarm_ring || cnt5_r) ? blk_out : 1'b0;
        end
    end

endmodule
