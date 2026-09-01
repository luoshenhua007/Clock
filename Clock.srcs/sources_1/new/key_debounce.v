`timescale 1ns / 1ps

// key_debounce：按键消抖与边沿检测。对每个按键进行两级同步、防抖计时，
// 输出单拍按下脉冲 o_key_pulse 与长按标志 o_key_hold（阈值参数可配置）。
// key_debounce_one 为单按键子模块，本模块通过 generate 例化 KEY_NUM 个。

module key_debounce #(
    parameter KEY_NUM        = 6,
    parameter KEY_ACTIVE_LOW = 1,
    parameter DEBOUNCE_CNT   = 1_000_000,
    parameter HOLD_CNT       = 25_000_000,
    parameter CNT_WIDTH      = 32
)(
    input  wire              i_clk,
    input  wire              i_rst_n,
    input  wire [KEY_NUM-1:0] i_key_in,
    output wire [KEY_NUM-1:0] o_key_pulse,
    output wire [KEY_NUM-1:0] o_key_hold
);

    genvar g;

    generate
        for (g = 0; g < KEY_NUM; g = g + 1) begin : GEN_KEY
            key_debounce_one #(
                .KEY_ACTIVE_LOW (KEY_ACTIVE_LOW),
                .DEBOUNCE_CNT   (DEBOUNCE_CNT),
                .HOLD_CNT       (HOLD_CNT),
                .CNT_WIDTH      (CNT_WIDTH)
            ) u_key_debounce_one (
                .i_clk      (i_clk),
                .i_rst_n    (i_rst_n),
                .i_key      (i_key_in[g]),
                .o_pulse    (o_key_pulse[g]),
                .o_hold     (o_key_hold[g])
            );
        end
    endgenerate

endmodule

// 单按键消抖子模块：两级同步 + 防抖 + 按下脉冲 + 长按标志。
module key_debounce_one #(
    parameter KEY_ACTIVE_LOW = 1,
    parameter DEBOUNCE_CNT   = 1_000_000,
    parameter HOLD_CNT       = 25_000_000,
    parameter CNT_WIDTH      = 32
)(
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_key,
    output reg  o_pulse,
    output reg  o_hold
);

    // 两级同步，消除亚稳态
    reg key_sync1_r;
    reg key_sync2_r;

    // 消抖后的稳定有效电平与防抖状态
    reg              key_reg_r;   // 稳定后的"有效按下"电平
    reg              pending_r;   // 正处于防抖计时中
    reg [CNT_WIDTH-1:0] cnt_r;    // 防抖计数器
    reg [CNT_WIDTH-1:0] hold_cnt_r; // 长按计时器
    reg              key_reg_ff_r;// 用于边沿检测
    reg              press_ff_r;  // 原始有效电平打拍，用于变化沿检测

    // 组合：原始"有效按下"电平（已同步）
    wire pressed_w = KEY_ACTIVE_LOW ? ~key_sync2_r : key_sync2_r;
    // 组合：原始有效电平上升沿（按下瞬间）
    wire press_rise_w = pressed_w & ~press_ff_r;
    // 组合：原始有效电平下降沿（松开瞬间）
    wire press_fall_w = ~pressed_w & press_ff_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            key_sync1_r  <= 1'b1;
            key_sync2_r  <= 1'b1;
            press_ff_r   <= 1'b0;
            key_reg_r    <= 1'b0;
            key_reg_ff_r <= 1'b0;
            pending_r    <= 1'b0;
            cnt_r        <= {CNT_WIDTH{1'b0}};
            hold_cnt_r   <= {CNT_WIDTH{1'b0}};
            o_pulse      <= 1'b0;
            o_hold       <= 1'b0;
        end else begin
            // 同步输入（低有效按键默认高电平）
            key_sync1_r <= i_key;
            key_sync2_r <= key_sync1_r;
            press_ff_r  <= pressed_w;

            // 防抖：输入变化沿启动计时，稳定 DEBOUNCE_CNT 周期后认可
            if (press_rise_w || press_fall_w) begin
                pending_r <= 1'b1;
                cnt_r     <= {CNT_WIDTH{1'b0}};
            end else if (pending_r) begin
                if (cnt_r >= DEBOUNCE_CNT[CNT_WIDTH-1:0] - 1'b1) begin
                    pending_r <= 1'b0;
                    cnt_r     <= {CNT_WIDTH{1'b0}};
                    key_reg_r <= pressed_w;
                end else begin
                    cnt_r <= cnt_r + 1'b1;
                end
            end

            // 单拍按下脉冲：稳定电平的上升沿
            key_reg_ff_r <= key_reg_r;
            o_pulse      <= key_reg_r & ~key_reg_ff_r;

            // 长按标志：稳定按下持续 HOLD_CNT 后拉高，按住期间保持
            if (key_reg_r) begin
                if (hold_cnt_r >= HOLD_CNT[CNT_WIDTH-1:0] - 1'b1) begin
                    hold_cnt_r <= hold_cnt_r;
                    o_hold     <= 1'b1;
                end else begin
                    hold_cnt_r <= hold_cnt_r + 1'b1;
                    o_hold     <= 1'b0;
                end
            end else begin
                hold_cnt_r <= {CNT_WIDTH{1'b0}};
                o_hold     <= 1'b0;
            end
        end
    end

endmodule
