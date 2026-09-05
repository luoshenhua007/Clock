`timescale 1ns / 1ps

// top_digital_clock：电子表顶层（时间/日期显示+编辑）。
// 交互：KEY0 切换 时间/日期；在显示页按 KEY1 进入编辑，KEY1 在编辑内推进字段；
//       KEY2/KEY3 = +/− 修改；时间编辑时暂停走时，日期编辑/显示时时钟照走。
// 显示 8 位：时间=HH MM SS（分隔点），日期=YYYY MM DD。位选低有效、段码低点亮。
// 扫描每位约 0.5ms，换位前熄灭尾段防残影。

module top_digital_clock #(
    parameter CLK_FREQ = 50_000_000,
    parameter DB_CNT   = 1_000_000,
    parameter HOLD_CNT = 25_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key,         // 按键（低有效）：0=MODE 1=SEL 2=+ 3=- 4/5 预留
    output wire [7:0] o_seg,
    output wire [7:0] o_sel,
    output wire       o_led
);

    wire flag_1s, flag_500hz, flag_2hz;
    wire [5:0] key_pulse;
    wire [5:0] key_hold;

    clk_div #(.CLK_FREQ(CLK_FREQ)) u_clk (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .o_flag_1s(flag_1s), .o_flag_500hz(flag_500hz), .o_flag_2hz(flag_2hz));

    key_debounce #(.DEBOUNCE_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT)) u_key (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_in(i_key),
        .o_key_pulse(key_pulse), .o_key_hold(key_hold));

    wire        view;                // 0=时间 1=日期
    wire        editing;
    wire [1:0]  cursor;
    fsm_controller u_fsm (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_pulse(key_pulse),
        .o_view(view), .o_edit(editing), .o_cursor(cursor));

    // ---- 实时时钟/日期 ----
    wire [7:0] hour, min, sec;
    wire [15:0] year;
    wire [7:0] mon, day;

    // 长按自动连加/连减（按住超过长按阈值后约 8Hz 重复）
    localparam REP_TH = (CLK_FREQ >= 8) ? CLK_FREQ / 8 : 1;
    reg [22:0] rep_cnt;
    wire hold_any = editing && (key_hold[2] || key_hold[3]);
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rep_cnt <= 23'd0;
        else if (hold_any) begin
            if (rep_cnt >= REP_TH[22:0] - 23'd1)
                rep_cnt <= 23'd0;
            else
                rep_cnt <= rep_cnt + 23'd1;
        end else
            rep_cnt <= 23'd0;
    end
    wire rep_tick = hold_any && (rep_cnt >= REP_TH[22:0] - 23'd1);

    wire rtc_set_en   =  editing && !view;   // 时间编辑（暂停走时）
    wire rtc_date_ed  =  editing &&  view;   // 日期编辑（不暂停）
    wire [2:0] rtc_field = (!view)
        ? ((cursor == 2'd0) ? 3'd0 : (cursor == 2'd1) ? 3'd1 : 3'd5)
        : ((cursor == 2'd0) ? 3'd2 : (cursor == 2'd1) ? 3'd3 : 3'd4);
    wire rtc_inc = editing && (key_pulse[2] || (key_hold[2] && rep_tick));
    wire rtc_dec = editing && (key_pulse[3] || (key_hold[3] && rep_tick));

    rtc_counter u_rtc (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(rtc_set_en), .i_date_edit(rtc_date_ed),
        .i_field(rtc_field), .i_inc(rtc_inc), .i_dec(rtc_dec),
        .o_hour(hour), .o_minute(min), .o_second(sec),
        .o_year(year), .o_month(mon), .o_day(day));

    // ---- 显示内容选通（8 位，pos7=左）----
    reg [31:0] digit_d;
    reg [7:0]  blank_d;
    reg [7:0]  dp_d;
    reg [7:0]  blink_b;

    always @(*) begin
        digit_d = 32'h0;
        blank_d = 8'h00;
        dp_d    = 8'h00;
        blink_b = 8'h00;
        if (!view) begin                      // 时间页
            digit_d = {hour, min, sec, 8'h00};
            blank_d = 8'b0000_0011;           // 最右 2 位熄灭
            dp_d    = 8'b0101_0000;           // 冒号点 pos6/pos4
            if (editing) begin
                if      (cursor == 2'd0) blink_b = 8'b1100_0000; // 时
                else if (cursor == 2'd1) blink_b = 8'b0011_0000; // 分
                else                    blink_b = 8'b0000_1100; // 秒
            end
        end else begin                        // 日期页
            digit_d = {year, mon, day};
            if (editing) begin
                if      (cursor == 2'd0) blink_b = 8'b1111_0000; // 年
                else if (cursor == 2'd1) blink_b = 8'b0000_1100; // 月
                else                    blink_b = 8'b0000_0011; // 日
            end
        end
    end

    // 闪烁相位（flag_2hz 脉冲翻转）；长按连加期间保持常亮不闪
    wire hold_active = editing && (key_hold[2] || key_hold[3]);
    reg blink_phase;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)      blink_phase <= 1'b0;
        else if (flag_2hz) blink_phase <= ~blink_phase;
    end
    wire [7:0] blink_off = (hold_active || blink_phase) ? 8'h00 : blink_b;
    wire [7:0] eff_blank = blank_d | blink_off;

    // ---- 动态扫描（内联）----
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
    reg [7:0] seg_code;
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
        sel_r = ~(8'd1 << scan_pos);          // 位选低有效
        if (scan_cnt >= (16'd49999 - 16'd4000))
            seg_out_r = 8'hFF;                // 换位前熄灭尾段
        else if (eff_blank[scan_pos])
            seg_out_r = 8'hFF;                // 熄灭
        else
            seg_out_r = ~(seg_code | (dp_d[scan_pos] ? 8'h80 : 8'h00));
    end

    assign o_seg = seg_out_r;
    assign o_sel = sel_r;
    assign o_led = 1'b0;

endmodule
