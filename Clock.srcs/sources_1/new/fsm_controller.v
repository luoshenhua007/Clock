`timescale 1ns / 1ps

// fsm_controller：界面模式与光标状态机。负责 MODE/SEL 两个按键带来的状态切换：
//   MODE：时间->日期->时间设置->日期设置->闹钟设置->倒计时，循环。
//   SEL ：在各设置界面内循环"修改位/对象"（时/分、年/月/日、闹钟组…、倒计时分/秒/退出）。
// 其余按键操作与数据/显示选通由顶层按 mode/cursor 组合逻辑完成。

module fsm_controller (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key_pulse,   // key_debounce 输出的单拍按下脉冲
    output reg  [2:0] o_mode,        // 0=时间 1=日期 2=时间设置 3=日期设置 4=闹钟设置 5=倒计时
    output reg  [3:0] o_cursor,      // 各界面内的位置（含义随模式不同）
    output reg        o_cnt_cfg      // 倒计时处于"设初值"状态（cursor<2）
);

    localparam M_TIME = 3'd0, M_DATE = 3'd1, M_SET_T = 3'd2,
               M_SET_D = 3'd3, M_ALM = 3'd4, M_CNT = 3'd5;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_mode   <= M_TIME;
            o_cursor <= 4'd0;
        end else begin
            if (i_key_pulse[0]) begin
                // MODE：切换到下一模式并复位光标
                o_mode   <= (o_mode == M_CNT) ? M_TIME : o_mode + 3'd1;
                o_cursor <= 4'd0;
            end else if (i_key_pulse[1]) begin
                // SEL：在各设置界面内推进修改位置
                case (o_mode)
                    M_SET_T: o_cursor <= (o_cursor == 4'd1) ? 4'd0 : o_cursor + 4'd1; // 时/分
                    M_SET_D: o_cursor <= (o_cursor == 4'd2) ? 4'd0 : o_cursor + 4'd1; // 年/月/日
                    M_ALM:   o_cursor <= (o_cursor == 4'd8) ? 4'd0 : o_cursor + 4'd1; // 3 组 x {时,分,使能}
                    M_CNT:   o_cursor <= (o_cursor == 4'd2) ? 4'd0 : o_cursor + 4'd1; // 分/秒/运行视图
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        o_cnt_cfg = (o_mode == M_CNT) && (o_cursor < 4'd2);
    end

endmodule
