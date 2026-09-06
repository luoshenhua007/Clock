`timescale 1ns / 1ps

// top_digital_clock：电子表顶层（Part-1 显示 + Part-2 时间/日期编辑）。
// 模式由 SW4/SW3 电平决定（实测：拨下读到 1 → 用高电平译码）：
//   td_disp = SW4高 && SW3高    时间/日期·显示（默认，两开关均拨下）
//   td_edit = SW4高 && SW3低    时间/日期·编辑
//   ac_disp = SW4低 && SW3高    闹钟/倒计时·显示（Part-3）
//   ac_edit = SW4低 && SW3低    闹钟/倒计时·编辑（Part-4）
// 时间/日期显示页：KEY1 时间<->日期；KEY2 时间12/24h、日期年月日<->星期。
// 时间/日期编辑页：KEY1 循环 时/分/秒 或 年/月/日；KEY2/3 +/−（长按连加/连减）；
//   编辑界面强制 24h 与年月日；编辑时间暂停走秒，编辑日期不停表。

module top_digital_clock #(
    parameter CLK_FREQ = 50_000_000,
    parameter DB_CNT   = 1_000_000,
    parameter HOLD_CNT = 25_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key,          // [0]=KEY1 [1]=KEY2 [2]=KEY3 [3]=KEY4（低有效）
    input  wire       i_sw_group,     // SW4 电平
    input  wire       i_sw_edit,      // SW3 电平
    output wire [7:0] o_seg,
    output wire [7:0] o_sel,
    output wire       o_led
);

    wire flag_1s, flag_500hz, flag_2hz;
    wire [5:0] kp, kh;

    clk_div #(.CLK_FREQ(CLK_FREQ)) u_clk (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .o_flag_1s(flag_1s), .o_flag_500hz(flag_500hz), .o_flag_2hz(flag_2hz));

    key_debounce #(.DEBOUNCE_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT)) u_key (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_in(i_key),
        .o_key_pulse(kp), .o_key_hold(kh));

    // ---- 模式（开关电平译码）----
    wire td_disp =  i_sw_group &&  i_sw_edit;
    wire td_edit =  i_sw_group && !i_sw_edit;
    wire ac_disp = !i_sw_group &&  i_sw_edit;
    wire ac_edit = !i_sw_group && !i_sw_edit;

    // ---- 页面/编辑状态 ----
    reg view_time;        // 0=时间 1=日期
    reg fmt_12;           // 时间显示 12/24h
    reg date_week;        // 日期显示 年月日/星期
    reg [1:0] cursor;     // 编辑字段 0..2
    reg prev_edit;        // td_edit 上一拍（检测进入编辑沿）

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            prev_edit <= 1'b0;
        end else begin
            prev_edit <= td_edit;
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            view_time <= 1'b0;
            fmt_12    <= 1'b0;
            date_week <= 1'b0;
            cursor    <= 2'd0;
        end else if (td_edit) begin
            if (!prev_edit)
                cursor <= 2'd0;                       // 进入编辑：光标复位到字段0
            else if (kp[0])
                cursor <= (cursor == 2'd2) ? 2'd0 : cursor + 2'd1;
        end else if (td_disp) begin
            if (kp[0]) begin
                view_time <= ~view_time;
                date_week <= 1'b0;
            end else if (kp[1]) begin
                if (!view_time) fmt_12 <= ~fmt_12;
                else            date_week <= ~date_week;
            end
        end else begin
            // ac_disp / ac_edit：Part-3/4
        end
    end

    // ---- 实时时钟/日期 ----
    wire [7:0] hour, min, sec;
    wire [15:0] year;
    wire [7:0] mon, day;

    wire rtc_set_en  = td_edit && !view_time;   // 编辑时间（暂停走时）
    wire rtc_date_ed = td_edit &&  view_time;   // 编辑日期（不暂停）
    wire [2:0] rtc_field = (!view_time)
        ? ((cursor == 2'd0) ? 3'd0 : (cursor == 2'd1) ? 3'd1 : 3'd5)
        : ((cursor == 2'd0) ? 3'd2 : (cursor == 2'd1) ? 3'd3 : 3'd4);
    wire rtc_inc = rtc_inc_w && td_edit;
    wire rtc_dec = rtc_dec_w && td_edit;

    rtc_counter u_rtc (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(rtc_set_en), .i_date_edit(rtc_date_ed),
        .i_field(rtc_field), .i_inc(rtc_inc), .i_dec(rtc_dec),
        .o_hour(hour), .o_minute(min), .o_second(sec),
        .o_year(year), .o_month(mon), .o_day(day));

    // 长按连加/连减（编辑中按住 KEY2/KEY3）
    localparam REP_TH = (CLK_FREQ >= 8) ? CLK_FREQ / 8 : 1;
    reg [22:0] rep_cnt;
    wire hold_any = (kh[1] || kh[2]);
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
    wire rtc_inc_w = kp[1] || (kh[1] && rep_tick);   // KEY2 = +
    wire rtc_dec_w = kp[2] || (kh[2] && rep_tick);   // KEY3 = −

    // ---- 12h 换算（仅显示页使用）----
    integer hv12, v12;
    reg [3:0] h_t_d, h_u_d;
    reg       pm;
    always @(*) begin
        hv12 = hour[7:4]*10 + hour[3:0];
        pm   = (hv12 >= 12);
        v12  = (hv12 % 12 == 0) ? 12 : hv12 % 12;
        h_t_d = (v12 / 10) % 10;
        h_u_d = v12 % 10;
        if (!fmt_12) begin
            h_t_d = hour[7:4];
            h_u_d = hour[3:0];
        end
    end

    // ---- 星期（Zeller，周一=1..周日=7）----
    integer zy, zm, zd, zK, zJ, zh;
    reg [3:0] week_day;
    always @(*) begin
        zy = year[15:12]*1000 + year[11:8]*100 + year[7:4]*10 + year[3:0];
        zm = mon[7:4]*10 + mon[3:0];
        zd = day[7:4]*10 + day[3:0];
        if (zm < 3) begin zm = zm + 12; zy = zy - 1; end
        zK = zy % 100;
        zJ = zy / 100;
        zh = (zd + (13*(zm+1))/5 + zK + zK/4 + zJ/4 + 5*zJ) % 7;
        week_day = ((zh + 5) % 7) + 1;
    end

    // ---- 显示内容（pos7=左）----
    reg [31:0] digit_d;
    reg [7:0]  dp_d;
    reg [7:0]  blank_d;
    reg [7:0]  blink_g;                 // 编辑光标闪烁组
    wire [31:0] time_d = fmt_12 && !td_edit ? {h_t_d, h_u_d, min, sec, 8'h00}
                                            : {hour, min, sec, 8'h00};

    always @(*) begin
        digit_d = 32'h0;
        dp_d    = 8'h00;
        blank_d = 8'h00;
        blink_g = 8'h00;

        if (td_edit && view_time) begin          // 日期编辑（强制年月日）
            digit_d = {year, mon, day};
            dp_d    = 8'b0001_0100;              // 分隔点 pos4/pos2
            if      (cursor == 2'd0) blink_g = 8'b1111_0000; // 年
            else if (cursor == 2'd1) blink_g = 8'b0000_1100; // 月
            else                     blink_g = 8'b0000_0011; // 日
        end else if (td_edit && !view_time) begin // 时间编辑（强制 24h）
            digit_d = {hour, min, sec, 8'h00};
            blank_d = 8'b0000_0011;              // 第7/8位空
            dp_d    = 8'b0101_0000;
            if      (cursor == 2'd0) blink_g = 8'b1100_0000; // 时
            else if (cursor == 2'd1) blink_g = 8'b0011_0000; // 分
            else                     blink_g = 8'b0000_1100; // 秒
        end else if (view_time && date_week) begin
            digit_d = {week_day, 28'h0};
            blank_d = 8'h7F;
        end else if (view_time) begin
            digit_d = {year, mon, day};
            dp_d    = 8'b0001_0100;
        end else begin
            digit_d = time_d;
            blank_d = 8'b0000_0010;              // 第7位空
            if (!fmt_12) blank_d = blank_d | 8'b0000_0001; // 24h 第8位空
            dp_d    = 8'b0101_0000;
        end
    end

    // ---- 闪烁相位（2Hz 翻转）；长按连加期间常亮 ----
    reg blink_phase;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)      blink_phase <= 1'b0;
        else if (flag_2hz) blink_phase <= ~blink_phase;
    end
    wire blink_hold = kh[1] || kh[2];   // KEY2/KEY3 长按
    wire [7:0] blink_off = (td_edit && !blink_hold && !blink_phase) ? blink_g : 8'h00;
    wire [7:0] eff_blank = blank_d | blink_off;

    // ---- 8 位动态扫描（低点亮）----
    reg [15:0] scan_cnt;
    reg [2:0]  scan_pos;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            scan_cnt <= 16'd0;
            scan_pos <= 3'd0;
        end else if (scan_cnt >= 16'd49999) begin
            scan_cnt <= 16'd0;
            scan_pos <= (scan_pos == 3'd7) ? 3'd0 : scan_pos + 3'd1;
        end else
            scan_cnt <= scan_cnt + 16'd1;
    end

    wire [3:0] nib = digit_d[scan_pos*4 +: 4];
    reg [7:0] seg_code;
    always @(*) begin
        case (nib)
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
        sel_r = ~(8'd1 << scan_pos);
        if (scan_cnt >= (16'd49999 - 16'd4000))
            seg_out_r = 8'hFF;
        else if (eff_blank[scan_pos])
            seg_out_r = 8'hFF;
        else if (!td_edit && view_time == 1'b0 && !date_week && fmt_12 && scan_pos == 3'd0)
            seg_out_r = ~(pm ? 8'h73 : 8'h77);      // P / A
        else
            seg_out_r = ~(seg_code | (dp_d[scan_pos] ? 8'h80 : 8'h00));
    end

    assign o_seg = seg_out_r;
    assign o_sel = sel_r;
    assign o_led = 1'b0;

endmodule
