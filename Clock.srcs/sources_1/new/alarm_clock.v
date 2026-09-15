`timescale 1ns / 1ps

// alarm_clock：3 组独立闹钟（时/分 + 使能）。
// 触发：匹配即触发（不再依赖分钟跳变沿），用"已服务分钟"served_hm 防同一分钟重复；
// 提醒：每组独立 FSM  IDLE -> RING1(5s) -> SNOOZE(10s) -> RING2(5s) -> IDLE；
// 解除键边沿：RING1/RING2/SNOOZE 任意状态均立即回 IDLE（含静默期取消二次提醒）。
// 输出 o_ring[2:0] 为三组独立响铃，可直接驱动 3 个 LED。
// 字段调整：i_fld 0=时 1=分 2=使能。

module alarm_clock #(
    parameter [7:0] INIT_H0 = 8'h08, parameter [7:0] INIT_M0 = 8'h00,
    parameter [7:0] INIT_H1 = 8'h08, parameter [7:0] INIT_M1 = 8'h30,
    parameter [7:0] INIT_H2 = 8'h21, parameter [7:0] INIT_M2 = 8'h00
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        i_flag_1s,
    input  wire        i_set_en,
    input  wire [1:0]  i_idx,
    input  wire [1:0]  i_fld,
    input  wire        i_inc,
    input  wire        i_dec,
    input  wire [7:0]  i_cur_hour,
    input  wire [7:0]  i_cur_min,
    input  wire        i_ack,
    output reg  [7:0]  o_sel_hour,
    output reg  [7:0]  o_sel_min,
    output wire [2:0]  o_en,
    output wire [2:0]  o_ring          // 三组独立响铃
);

    localparam RING_CNT = 5, SNOOZE_CNT = 10;

    reg [7:0] h_r [0:2];
    reg [7:0] m_r [0:2];
    reg       en_r[0:2];
    reg [1:0] st_r[0:2];        // 0 idle 1 ring1 2 snooze 3 ring2
    reg [3:0] cnt_r[0:2];
    reg [2:0] ring_r;
    reg [15:0] served_hm_r[0:2]; // 已服务分钟
    reg       ack_d1_r;

    integer i;
    wire [15:0] cur_hm_w = {i_cur_hour, i_cur_min};

    function automatic [7:0] bcd2_inc(input [3:0] hi, input [3:0] lo);
        begin bcd2_inc = (lo == 4'h9) ? {hi + 4'h1, 4'h0} : {hi, lo + 4'h1}; end
    endfunction
    function automatic [7:0] bcd2_dec(input [3:0] hi, input [3:0] lo);
        begin bcd2_dec = (lo == 4'h0) ? {hi - 4'h1, 4'h9} : {hi, lo - 4'h1}; end
    endfunction

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            h_r[0] <= INIT_H0; m_r[0] <= INIT_M0;
            h_r[1] <= INIT_H1; m_r[1] <= INIT_M1;
            h_r[2] <= INIT_H2; m_r[2] <= INIT_M2;
            en_r[0] <= 0; en_r[1] <= 0; en_r[2] <= 0;
            ring_r  <= 3'b000;
            ack_d1_r<= 1'b0;
            for (i = 0; i < 3; i = i + 1) begin
                st_r[i] <= 2'd0; cnt_r[i] <= 4'd0; served_hm_r[i] <= 16'hffff;
            end
        end else begin
            ack_d1_r <= i_ack;

            // ---- 字段/使能调整 ----
            if (i_set_en && (i_inc || i_dec)) begin
                if (i_fld == 2'd2) begin
                    if (i_inc) en_r[i_idx] <= 1'b1; else en_r[i_idx] <= 1'b0;
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

            // ---- 三组独立提醒 FSM ----
            for (i = 0; i < 3; i = i + 1) begin
                if (i_set_en || !en_r[i]) begin
                    st_r[i] <= 2'd0; cnt_r[i] <= 4'd0; ring_r[i] <= 1'b0;
                end else if (i_ack && !ack_d1_r) begin
                    // 解除：任意状态（含 SNOOZE）立即回 IDLE
                    st_r[i] <= 2'd0; cnt_r[i] <= 4'd0; ring_r[i] <= 1'b0;
                end else begin
                    // 匹配检测：每个时钟都判断（不受秒节拍限制，避免整点晚 1 秒）
                    if (cur_hm_w != served_hm_r[i]) begin
                        served_hm_r[i] <= 16'hffff;           // 离开该分钟后清标志
                        if ((h_r[i] == i_cur_hour) && (m_r[i] == i_cur_min)) begin
                            st_r[i] <= 2'd1; ring_r[i] <= 1'b1; cnt_r[i] <= 4'd0;
                            served_hm_r[i] <= cur_hm_w;       // 锁存已服务分钟
                        end else begin
                            st_r[i] <= 2'd0; ring_r[i] <= 1'b0; cnt_r[i] <= 4'd0;
                        end
                    end else if (i_flag_1s) begin
                        case (st_r[i])
                            2'd1: begin
                                if (cnt_r[i] >= RING_CNT - 1) begin
                                    st_r[i] <= 2'd2; ring_r[i] <= 1'b0; cnt_r[i] <= 4'd0;
                                end else cnt_r[i] <= cnt_r[i] + 1'b1;
                            end
                            2'd2: begin
                                if (cnt_r[i] >= SNOOZE_CNT - 1) begin
                                    st_r[i] <= 2'd3; ring_r[i] <= 1'b1; cnt_r[i] <= 4'd0;
                                end else cnt_r[i] <= cnt_r[i] + 1'b1;
                            end
                            2'd3: begin
                                if (cnt_r[i] >= RING_CNT - 1) begin
                                    st_r[i] <= 2'd0; ring_r[i] <= 1'b0; cnt_r[i] <= 4'd0;
                                end else cnt_r[i] <= cnt_r[i] + 1'b1;
                            end
                            default: st_r[i] <= 2'd0;
                        endcase
                    end
                end
            end
        end
    end

    // 选中闹钟时间（显示用）
    always @(*) begin
        case (i_idx)
            2'd0: begin o_sel_hour = h_r[0]; o_sel_min = m_r[0]; end
            2'd1: begin o_sel_hour = h_r[1]; o_sel_min = m_r[1]; end
            default: begin o_sel_hour = h_r[2]; o_sel_min = m_r[2]; end
        endcase
    end

    assign o_en   = {en_r[2], en_r[1], en_r[0]};
    assign o_ring = ring_r;

endmodule
