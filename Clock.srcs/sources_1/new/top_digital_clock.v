`timescale 1ns / 1ps

// top_digital_clock：多功能电子表顶层。例化分频/消抖/状态机/计数/闹钟/倒计时/扫描/提醒，
// 完成 6 键到各子模块的操作译码与六位数码管内容选通、光标闪烁。
// 显示位序：digits[5..0] 左→右。
//   TIME/SET_T: 时时 分分 秒秒；DATE/SET_D: 年年(低2) 月月 日日；
//   ALM:        选中闹钟 时时 分分（使能时小数点亮）；CNT: 分分 秒秒。

module top_digital_clock #(
    parameter CLK_FREQ = 50_000_000, // 主频（仿真可缩小）
    parameter DB_CNT   = 1_000_000,  // 消抖周期（默认 20ms@50M）
    parameter HOLD_CNT = 25_000_000, // 长按阈值（默认 0.5s@50M）
    parameter DEMO     = 0           // 1 = 固定显示 12345678（调试用，需改为 0）
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

    // 各模式 8 位布局：nibble7..0 = 位 SEL0..SEL7（左→右）
    //   位选/熄灭/闪烁掩码的 bit n 与 nibble n 对应同一支数码管。
    //   TIME/SET_T: HH MM SS 于左 6 位（SEL0..5），SEL6/7 熄灭
    //   DATE/SET_D: YYYY MM DD 占满 8 位
    //   ALM:        编号 SEL0 | 空 SEL1 | 时 SEL2..3 | 分 SEL4..5 | 空 SEL6..7
    //   CNT:        MM SS 于左 4 位（SEL0..3），SEL4..7 熄灭
    wire [31:0] time_d = {hour, min, sec, 8'h00};
    wire [31:0] date_d = {year, mon, day};
    wire [31:0] alm_d  = {4'd1 + {2'b00, alm_idx}, 4'h0, alm_h, alm_m, 8'h00};
    wire [31:0] cnt_d  = {cnt_min, cnt_sec, 16'h0000};

    reg [7:0]  base_blank;
    always @(*) begin
        digit_d = 32'h0;
        blank_d = 8'h00;
        dp_d    = 8'h00;
        blink_b = 8'h00;
        if (DEMO) begin
            digit_d = 32'h1234_5678;     // 调试：固定内容，验证显示链路
        end else case (mode)
            M_TIME, M_SET_T: begin
                digit_d = time_d;
                blank_d = 8'b0000_0011;      // 熄灭最右两位
                dp_d    = 8'b0101_0000;      // 冒号点：时个位后/分个位后 (pos6,pos4)
                if (mode == M_SET_T) begin
                    if (cursor == 4'd0) blink_b = 8'b1100_0000; // 时
                    else               blink_b = 8'b0011_0000; // 分
                end
            end
            M_DATE, M_SET_D: begin
                digit_d = date_d;
                if (mode == M_SET_D) begin
                    if (cursor == 4'd0) blink_b = 8'b1111_0000;      // 年 SEL0..3
                    else if (cursor == 4'd1) blink_b = 8'b0000_1100; // 月 SEL4..5
                    else blink_b = 8'b0000_0011;                     // 日 SEL6..7
                end
            end
            M_ALM: begin
                digit_d = alm_d;
                blank_d = 8'b0100_0011;      // 熄灭 SEL1、SEL6、SEL7
                if (alm_en[alm_idx]) dp_d = 8'b0001_0000;  // 使能点（SEL4）
                case (alm_cmod_c)
                    2'd0: blink_b = 8'b0011_0000;          // 时 SEL2..3
                    2'd1: blink_b = 8'b0000_1100;          // 分 SEL4..5
                    default: blink_b = 8'b0011_1100;       // 使能编辑
                endcase
            end
            M_CNT: begin
                digit_d = cnt_d;
                blank_d = 8'b0000_1111;      // 熄灭右 4 位 SEL4..7
                dp_d    = 8'b0010_0000;      // 分:秒 分隔点（SEL5）
                if (cnt_cfg) begin
                    if (cursor == 4'd0) blink_b = 8'b1100_0000; // 分 SEL0..1
                    else               blink_b = 8'b0011_0000; // 秒 SEL2..3
                end
            end
            default: ;
        endcase
    end

    // 闪烁节拍低时熄灭光标区（有效设置状态下）
    wire [7:0] blink_off = (flag_2hz) ? 8'h00 : blink_b;
    wire [7:0] eff_blank = blank_d | blink_off;

    // ===== 数码管动态扫描（内联）=====
    // 段码低电平点亮（共阳，自检确认）；每位点亮约 0.5ms@50M。
    reg [15:0] scan_cnt;
    reg [2:0]  scan_pos;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            scan_cnt <= 16'd0;
            scan_pos <= 3'd0;
        end else if (scan_cnt >= 16'd49999) begin
            scan_cnt <= 16'd0;
            scan_pos <= (scan_pos == 3'd7) ? 3'd0 : scan_pos + 3'd1;
        end else begin
            scan_cnt <= scan_cnt + 16'd1;
        end
    end

    wire [3:0] scan_nib = digit_d[scan_pos*4 +: 4];

    reg [7:0] seg_code;   // 亮=1：{dp=0,g..a}
    always @(*) begin
        case (scan_nib)
            4'h0: seg_code = 8'h3F; 4'h1: seg_code = 8'h06;
            4'h2: seg_code = 8'h5B; 4'h3: seg_code = 8'h4F;
            4'h4: seg_code = 8'h66; 4'h5: seg_code = 8'h6D;
            4'h6: seg_code = 8'h7D; 4'h7: seg_code = 8'h07;
            4'h8: seg_code = 8'h7F; 4'h9: seg_code = 8'h6F;
            4'hA: seg_code = 8'h77; 4'hB: seg_code = 8'h7C;
            4'hC: seg_code = 8'h39; 4'hD: seg_code = 8'h5E;
            4'hE: seg_code = 8'h79; 4'hF: seg_code = 8'h71;
            default: seg_code = 8'h00;
        endcase
    end

    reg [7:0] seg_out_r;
    reg [7:0] sel_r;
    always @(*) begin
        sel_r = ~(8'd1 << scan_pos);   // 位选低有效：输出低的那位点亮
        // 换位前熄灭尾段（防残影串扰）
        if (scan_cnt >= (16'd49999 - 16'd4000))
            seg_out_r = 8'hFF;
        else if (eff_blank[scan_pos])
            seg_out_r = 8'hFF;                    // 熄灭（共阳：全高）
        else
            seg_out_r = ~(seg_code | (dp_d[scan_pos] ? 8'h80 : 8'h00));
    end
    assign o_seg = seg_out_r;
    assign o_sel = sel_r;

    // 防止未用端口告警：key_hold 暂供后续长按连加扩展
    wire _unused = &key_hold;

endmodule
