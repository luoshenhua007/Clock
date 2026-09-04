`timescale 1ns / 1ps

// alarm_clock：闹钟管理。存储 3 组闹钟（BCD 时/分 + 使能位），到点提醒。
// 提醒状态机：IDLE -> ALARM_1(5s, 可按解除) -> SNOOZE(10s) -> ALARM_2(5s) -> IDLE。
// 仅在分钟跳变沿（该分钟首秒）检测匹配，避免同一分钟重复触发。
// 字段调整：i_fld 0=时 1=分 2=使能开关切换。

module alarm_clock #(
    parameter [7:0] INIT_H0 = 8'h08, parameter [7:0] INIT_M0 = 8'h00,
    parameter [7:0] INIT_H1 = 8'h08, parameter [7:0] INIT_M1 = 8'h30,
    parameter [7:0] INIT_H2 = 8'h21, parameter [7:0] INIT_M2 = 8'h00
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_flag_1s,       // 秒使能
    input  wire        i_set_en,        // 设置模式（不响铃）
    input  wire [1:0]  i_idx,           // 0..2 选中闹钟
    input  wire [1:0]  i_fld,           // 0=时 1=分 2=使能切换
    input  wire        i_inc,
    input  wire        i_dec,
    input  wire [7:0]  i_cur_hour,      // 当前时间 BCD
    input  wire [7:0]  i_cur_min,
    input  wire        i_ack,           // 解除键（单拍）
    output reg  [7:0]  o_sel_hour,     // 选中闹钟时间（设置界面显示）
    output reg  [7:0]  o_sel_min,
    output wire [2:0]  o_en,            // 3 组闹钟使能
    output reg         o_ring,          // 提醒中（LED 闪烁使能）
    output reg  [1:0]  o_ring_no,       // 当前响铃闹钟编号
    output reg  [1:0]  o_state          // 状态（调试/观察）
);

    localparam S_IDLE = 2'd0, S_ALARM1 = 2'd1, S_SNOOZE = 2'd2, S_ALARM2 = 2'd3;
    localparam RING_CNT = 5;            // 5s
    localparam SNOOZE_CNT = 10;         // 10s

    // ---- 闹钟寄存器 ----
    reg [7:0] h_r [0:2];
    reg [7:0] m_r [0:2];
    reg       en_r [0:2];

    // ---- 提醒状态机 ----
    reg [3:0] cnt_r;
    reg [15:0] prev_hm_r;
    reg [1:0] state_r;

    function automatic [7:0] bcd2_inc(input [3:0] hi, input [3:0] lo);
        begin bcd2_inc = (lo == 4'h9) ? {hi + 4'h1, 4'h0} : {hi, lo + 4'h1}; end
    endfunction
    function automatic [7:0] bcd2_dec(input [3:0] hi, input [3:0] lo);
        begin bcd2_dec = (lo == 4'h0) ? {hi - 4'h1, 4'h9} : {hi, lo - 4'h1}; end
    endfunction

    // 选中闹钟的匹配情况
    wire match0 = en_r[0] && (h_r[0] == i_cur_hour) && (m_r[0] == i_cur_min);
    wire match1 = en_r[1] && (h_r[1] == i_cur_hour) && (m_r[1] == i_cur_min);
    wire match2 = en_r[2] && (h_r[2] == i_cur_hour) && (m_r[2] == i_cur_min);
    wire any_match_w = match0 || match1 || match2;
    wire [1:0] first_no_w = match0 ? 2'd0 : (match1 ? 2'd1 : 2'd2);
    wire [7:0] cur_hm_w = {i_cur_hour, i_cur_min};
    wire min_tick_w = (cur_hm_w != prev_hm_r);  // 分钟跳变沿

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_r  <= S_IDLE;
            cnt_r    <= 4'd0;
            prev_hm_r<= 16'hffff;
            o_ring   <= 1'b0;
            o_ring_no<= 2'd0;
            o_state  <= S_IDLE;
        end else if (i_set_en) begin
            state_r  <= S_IDLE;
            cnt_r    <= 4'd0;
            o_ring   <= 1'b0;
            o_state  <= S_IDLE;
        end else if (i_flag_1s) begin
            // 记录上一秒的时:分，用于分钟跳变沿检测
            prev_hm_r <= cur_hm_w;

            case (state_r)
                S_IDLE: begin
                    if (min_tick_w && any_match_w) begin
                        state_r   <= S_ALARM1;
                        o_ring    <= 1'b1;
                        o_ring_no <= first_no_w;
                        o_state   <= S_ALARM1;
                        cnt_r     <= 4'd0;
                    end
                end
                S_ALARM1: begin
                    if (i_ack) begin
                        state_r <= S_IDLE; o_ring <= 1'b0; o_state <= S_IDLE; cnt_r <= 0;
                    end else if (cnt_r >= RING_CNT - 1) begin
                        state_r <= S_SNOOZE; o_ring <= 1'b0; o_state <= S_SNOOZE; cnt_r <= 0;
                    end else begin
                        cnt_r <= cnt_r + 1'b1;
                    end
                end
                S_SNOOZE: begin
                    if (cnt_r >= SNOOZE_CNT - 1) begin
                        state_r <= S_ALARM2; o_ring <= 1'b1; o_state <= S_ALARM2; cnt_r <= 0;
                    end else begin
                        cnt_r <= cnt_r + 1'b1;
                    end
                end
                S_ALARM2: begin
                    if (i_ack) begin
                        state_r <= S_IDLE; o_ring <= 1'b0; o_state <= S_IDLE; cnt_r <= 0;
                    end else if (cnt_r >= RING_CNT - 1) begin
                        state_r <= S_IDLE; o_ring <= 1'b0; o_state <= S_IDLE; cnt_r <= 0;
                    end else begin
                        cnt_r <= cnt_r + 1'b1;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end

    // ---- 闹钟时间设置 ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            h_r[0] <= INIT_H0; m_r[0] <= INIT_M0;
            h_r[1] <= INIT_H1; m_r[1] <= INIT_M1;
            h_r[2] <= INIT_H2; m_r[2] <= INIT_M2;
            en_r[0] <= 0; en_r[1] <= 0; en_r[2] <= 0;
        end else if (i_set_en && (i_inc || i_dec)) begin
            if (i_fld == 2'd2) begin
                // 使能切换：+ 开 / - 关
                if (i_inc) en_r[i_idx] <= 1'b1;
                else       en_r[i_idx] <= 1'b0;
            end else if (i_fld == 2'd0) begin
                if (i_inc) h_r[i_idx] <= (h_r[i_idx] == 8'h23) ? 8'h00
                                   : bcd2_inc(h_r[i_idx][7:4], h_r[i_idx][3:0]);
                else       h_r[i_idx] <= (h_r[i_idx] == 8'h00) ? 8'h23
                                   : bcd2_dec(h_r[i_idx][7:4], h_r[i_idx][3:0]);
            end else begin
                if (i_inc) m_r[i_idx] <= (m_r[i_idx] == 8'h59) ? 8'h00
                                   : bcd2_inc(m_r[i_idx][7:4], m_r[i_idx][3:0]);
                else       m_r[i_idx] <= (m_r[i_idx] == 8'h00) ? 8'h59
                                   : bcd2_dec(m_r[i_idx][7:4], m_r[i_idx][3:0]);
            end
        end
    end

    // ---- 输出 ----
    always @(*) begin
        case (i_idx)
            2'd0: begin o_sel_hour = h_r[0]; o_sel_min = m_r[0]; end
            2'd1: begin o_sel_hour = h_r[1]; o_sel_min = m_r[1]; end
            default: begin o_sel_hour = h_r[2]; o_sel_min = m_r[2]; end
        endcase
    end
    assign o_en = {en_r[2], en_r[1], en_r[0]};

endmodule
