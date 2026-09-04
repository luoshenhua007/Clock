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
    output wire [5:0] o_sel,
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

    // ---- 显示内容选通 ----
    reg [23:0] digit_d;
    reg [5:0]  blank_d;
    reg [5:0]  dp_d;

    wire [23:0] time_d = {hour, min, sec};
    wire [23:0] date_d = {year[7:4], year[3:0], mon, day};
    wire [23:0] alm_d  = {alm_h, alm_m, 8'h00};
    wire [23:0] cnt_d  = {cnt_min, cnt_sec, 8'h00};

    // 各模式实际显示所需的位选光带（熄灭末两位或闪烁位）
    reg [5:0] blink_b;
    always @(*) begin
        digit_d = 24'h0;
        blank_d = 6'h00;
        dp_d    = 6'h00;
        blink_b = 6'h00;
        case (mode)
            M_TIME, M_SET_T: begin
                digit_d = time_d;
                dp_d    = 6'b010100;      // 时:分 与 分:秒 之间的分隔点
                if (mode == M_SET_T) begin
                    if (cursor == 4'd0) blink_b = 6'b110000; // 时
                    else               blink_b = 6'b001100; // 分
                end
            end
            M_DATE, M_SET_D: begin
                digit_d = date_d;
                if (mode == M_SET_D) begin
                    if (cursor == 4'd0) blink_b = 6'b110000; // 年
                    else if (cursor == 4'd1) blink_b = 6'b001100; // 月
                    else blink_b = 6'b000011;              // 日
                end
            end
            M_ALM: begin
                digit_d = alm_d;
                blank_d = 6'b000011;         // 只显示选中的时/分四位数
                if (alm_en[alm_idx]) dp_d = 6'b000100;   // 使能指示点（分钟十位）
                case (alm_cmod_c)
                    2'd0: blink_b = 6'b110000;           // 时
                    2'd1: blink_b = 6'b001100;           // 分
                    default: blink_b = 6'b111100;        // 使能编辑
                endcase
            end
            M_CNT: begin
                digit_d = cnt_d;
                blank_d = 6'b000011;
                if (cnt_cfg) begin
                    if (cursor == 4'd0) blink_b = 6'b110000; // 分
                    else               blink_b = 6'b001100; // 秒
                end
            end
            default: ;
        endcase
    end

    // 闪烁节拍低时熄灭光标区（有效设置状态下）
    wire [5:0] blink_off = (flag_2hz) ? 6'h00 : blink_b;

    wire [23:0] disp_digit = digit_d;
    wire [5:0]  disp_blank = blank_d | blink_off;
    wire [5:0]  disp_dp    = dp_d;

    seg_driver u_seg (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_500hz(flag_500hz),
        .i_digit(disp_digit), .i_dp(disp_dp), .i_blank(disp_blank),
        .o_seg(o_seg), .o_sel(o_sel));

    // 防止未用端口告警：key_hold 暂供后续长按连加扩展
    wire _unused = &key_hold;

endmodule
