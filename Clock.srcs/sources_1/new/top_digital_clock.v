`timescale 1ns / 1ps

// top_digital_clock：多功能电子表顶层。例化分频/消抖/状态机/计数/闹钟/倒计时/扫描/提醒，
// 完成 6 键到各子模块的操作译码与六位数码管内容选通、光标闪烁。
// 显示位序：digits[5..0] 左→右。
//   TIME/SET_T: 时时 分分 秒秒；DATE/SET_D: 年年(低2) 月月 日日；
//   ALM:        选中闹钟 时时 分分（使能时小数点亮）；CNT: 分分 秒秒。

module top_digital_clock #(
    parameter CLK_FREQ = 50_000_000, // 主频（仿真可缩小）
    parameter DB_CNT   = 1_000_000,  // 消抖周期（默认 20ms@50M）
    parameter HOLD_CNT = 25_000_000  // 长按阈值（默认 0.5s@50M）
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key,         // 物理按键（低有效）
    output wire [7:0] o_seg,
    output wire [7:0] o_sel,
    output wire       o_led
);

    localparam M_TIME=0, M_DATE=1, M_SET_T=2, M_SET_D=3, M_ALM=4, M_CNT=5;

    // ---- 分频/消抖 ----
    wire flag_1s, flag_500hz, flag_2hz;
    wire [5:0] key_pulse, key_hold;

    clk_div #(.CLK_FREQ(CLK_FREQ)) u_clk (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .o_flag_1s(flag_1s), .o_flag_500hz(flag_500hz), .o_flag_2hz(flag_2hz));

    key_debounce #(.DEBOUNCE_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT)) u_key (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_in(i_key),
        .o_key_pulse(key_pulse), .o_key_hold(key_hold));

    // ---- 状态机 ----
    wire [2:0] mode;
    wire [3:0] cursor;
    wire       cnt_cfg;
    fsm_controller u_fsm (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_pulse(key_pulse),
        .o_mode(mode), .o_cursor(cursor), .o_cnt_cfg(cnt_cfg));

    // ---- 实时时钟/日期 ----
    wire [7:0] hour, min, sec;
    wire [15:0] year;
    wire [7:0] mon, day;
    wire rtc_set_en = (mode == M_SET_T) || (mode == M_SET_D);
    wire [2:0] rtc_field =
        (mode == M_SET_T) ? cursor[2:0]
        : (cursor == 4'd0) ? 3'd2 : (cursor == 4'd1) ? 3'd3 : 3'd4;
    wire rtc_inc = key_pulse[2] && rtc_set_en;
    wire rtc_dec = key_pulse[3] && rtc_set_en;

    rtc_counter u_rtc (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(rtc_set_en), .i_field(rtc_field), .i_inc(rtc_inc), .i_dec(rtc_dec),
        .o_hour(hour), .o_minute(min), .o_second(sec),
        .o_year(year), .o_month(mon), .o_day(day));

    // ---- 闹钟 ----
    wire [7:0] alm_h, alm_m;
    wire [2:0] alm_en;
    wire       ring;
    wire [1:0] ring_no;

    // 光标 -> 闹钟编号 / 组内字段（组 = 每 3 个光标对应一个闹钟：时/分/使能）
    reg [1:0] alm_idx_c;
    reg [1:0] alm_cmod_c;
    always @(*) begin
        if      (cursor <= 4'd2) begin alm_idx_c = 2'd0; alm_cmod_c = cursor[1:0]; end
        else if (cursor <= 4'd5) begin alm_idx_c = 2'd1; alm_cmod_c = cursor - 4'd3; end
        else                     begin alm_idx_c = 2'd2; alm_cmod_c = cursor - 4'd6; end
    end
    wire [1:0] alm_idx = alm_idx_c;
    wire [1:0] alm_fld = (alm_cmod_c == 2'd2) ? 2'd2 : alm_cmod_c;
    wire alm_set_en = (mode == M_ALM);
    wire alm_inc = key_pulse[2] && alm_set_en;
    wire alm_dec = key_pulse[3] && alm_set_en;

    alarm_clock u_alarm (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(alm_set_en), .i_idx(alm_idx), .i_fld(alm_fld),
        .i_inc(alm_inc), .i_dec(alm_dec),
        .i_cur_hour(hour), .i_cur_min(min), .i_ack(key_pulse[4]),
        .o_sel_hour(alm_h), .o_sel_min(alm_m), .o_en(alm_en),
        .o_ring(ring), .o_ring_no(ring_no), .o_state());

    // ---- 倒计时 ----
    wire [7:0] cnt_min, cnt_sec;
    wire cnt_done, cnt_running;
    wire cnt_set_en = cnt_cfg;
    wire cnt_inc = key_pulse[2] && cnt_cfg;
    wire cnt_dec = key_pulse[3] && cnt_cfg;
    wire cnt_run = key_pulse[4] && (mode == M_CNT) && !cnt_cfg;
    wire cnt_reset = key_pulse[5] && (mode == M_CNT);

    countdown u_cnt (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(cnt_set_en), .i_fld(cursor[0]), .i_inc(cnt_inc), .i_dec(cnt_dec),
        .i_run(cnt_run), .i_reset(cnt_reset),
        .o_min(cnt_min), .o_sec(cnt_sec), .o_done(cnt_done), .o_running(cnt_running));

    // ---- 提醒 LED ----
    alarm_led u_led (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s), .i_flag_2hz(flag_2hz),
        .i_alarm_ring(ring), .i_cnt_done(cnt_done), .o_led(o_led));

    // ---- 显示内容选通（8 位，nibble7=SEL0 最左）----
    reg [31:0] digit_d;
    reg [7:0]  blank_d;
    reg [7:0]  dp_d;
    reg [7:0]  blink_b;

    // 各模式 8 位布局：nibble 7..0 = SEL0..SEL7
    //   TIME/SET_T: HH MM SS 于 SEL0..5（SEL6/7 熄灭）
    //   DATE/SET_D: YYYY MM DD 占满 8 位
    //   ALM:        编号 SEL0 | 空 SEL1 | 时 SEL2..3 | 分 SEL4..5
    //   CNT:        空 SEL0..1 | 分 SEL2..3 | 秒 SEL4..5
    wire [31:0] time_d = {hour, min, sec, 8'h00};
    wire [31:0] date_d = {year, mon, day};
    wire [31:0] alm_d  = {4'd1 + {2'b00, alm_idx}, 4'h0, alm_h, alm_m, 8'h00};
    wire [31:0] cnt_d  = {8'h00, cnt_min, cnt_sec, 8'h00};

    reg [7:0]  base_blank;
    always @(*) begin
        digit_d = 32'h0;
        blank_d = 8'h00;
        dp_d    = 8'h00;
        blink_b = 8'h00;
        case (mode)
            M_TIME, M_SET_T: begin
                digit_d = time_d;
                blank_d = 8'b1100_0000;      // 熄灭 SEL6/7
                dp_d    = 8'b0001_0100;      // 时:分、分:秒 分隔点（SEL2/SEL4）
                if (mode == M_SET_T) begin
                    if (cursor == 4'd0) blink_b = 8'b0000_0011; // 时 SEL0..1
                    else               blink_b = 8'b0000_1100; // 分 SEL2..3
                end
            end
            M_DATE, M_SET_D: begin
                digit_d = date_d;
                if (mode == M_SET_D) begin
                    if (cursor == 4'd0) blink_b = 8'b0000_1111;      // 年 SEL0..3
                    else if (cursor == 4'd1) blink_b = 8'b0011_0000; // 月 SEL4..5
                    else blink_b = 8'b1100_0000;                     // 日 SEL6..7
                end
            end
            M_ALM: begin
                digit_d = alm_d;
                blank_d = 8'b1010_0010;      // 熄灭 SEL1、SEL6、SEL7
                if (alm_en[alm_idx]) dp_d = 8'b0000_1000;  // 使能点（SEL3）
                case (alm_cmod_c)
                    2'd0: blink_b = 8'b0000_1100;          // 时 SEL2..3
                    2'd1: blink_b = 8'b0011_0000;          // 分 SEL4..5
                    default: blink_b = 8'b0011_1100;       // 使能编辑
                endcase
            end
            M_CNT: begin
                digit_d = cnt_d;
                blank_d = 8'b1100_0011;      // 熄灭 SEL0/1/6/7
                dp_d    = 8'b0001_0000;      // 分:秒 分隔点（SEL4）
                if (cnt_cfg) begin
                    if (cursor == 4'd0) blink_b = 8'b0000_1100; // 分 SEL2..3
                    else               blink_b = 8'b0011_0000; // 秒 SEL4..5
                end
            end
            default: ;
        endcase
    end

    // 闪烁节拍低时熄灭光标区（有效设置状态下）
    wire [7:0] blink_off = (flag_2hz) ? 8'h00 : blink_b;

    wire [31:0] disp_digit = digit_d;
    wire [7:0]  disp_blank = blank_d | blink_off;
    wire [7:0]  disp_dp    = dp_d;

    seg_driver #(.SEG_ACTIVE_LOW(1)) u_seg (   // 共阳：段码低点亮
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_500hz(flag_500hz),
        .i_digit(disp_digit), .i_dp(disp_dp), .i_blank(disp_blank),
        .o_seg(o_seg), .o_sel(o_sel));

    // 防止未用端口告警：key_hold 暂供后续长按连加扩展
    wire _unused = &key_hold;

endmodule
