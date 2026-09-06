`timescale 1ns / 1ps

// top_digital_clock：电子表顶层（Part-1 显示 / Part-2 时间日期编辑 / Part-3 闹钟倒计时显示）。
// 模式由 SW4/SW3 电平决定（实测拨下=1）：
//   td_disp = 1,1   时间/日期·显示（默认两开关均拨下）
//   td_edit = 1,0   时间/日期·编辑
//   ac_disp = 0,1   闹钟/倒计时·显示
//   ac_edit = 0,0   闹钟/倒计时·编辑（Part-4）
// 时间/日期显示：KEY1 时间<->日期；KEY2 12/24h、年月日<->星期。
// 时间/日期编辑：KEY1 循环字段，KEY2=+ / KEY3=−（长按连加/连减）。
// 闹钟/倒计时显示：KEY1 切闹钟1/2/3（倒计时视图下先回闹钟1）；KEY2 显示倒计时；
//   KEY3 闹钟=启/停用当前、倒计时=启/停（长按=复位）；KEY4 解除全部闹钟。
// LED1/2/3=闹钟1/2/3，LED4=倒计时结束。

module top_digital_clock #(
    parameter CLK_FREQ = 50_000_000,
    parameter DB_CNT   = 1_000_000,
    parameter HOLD_CNT = 25_000_000
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key,          // [0]=KEY1 [1]=KEY2 [2]=KEY3 [3]=KEY4（低有效）
    input  wire       i_sw_group,     // SW4
    input  wire       i_sw_edit,      // SW3
    output wire [7:0] o_seg,
    output wire [7:0] o_sel,
    output wire [3:0] o_led           // LED1..3=闹钟，LED4=倒计时
);

    wire flag_1s, flag_500hz, flag_2hz;
    wire [5:0] kp, kh;

    clk_div #(.CLK_FREQ(CLK_FREQ)) u_clk (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .o_flag_1s(flag_1s), .o_flag_500hz(flag_500hz), .o_flag_2hz(flag_2hz));

    key_debounce #(.DEBOUNCE_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT)) u_key (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_key_in(i_key),
        .o_key_pulse(kp), .o_key_hold(kh));

    // ---- 模式（编辑中 SW4 被锁存，仅退出编辑后按 SW4 档位生效）----
    wire editing_mode = ~i_sw_edit;                 // SW3=编辑档
    reg  grp_l;                                     // 进入编辑时锁存的组(1=时间/日期)
    reg  sw3_prev;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin sw3_prev <= 1'b1; grp_l <= 1'b1; end
        else begin
            sw3_prev <= i_sw_edit;
            if (i_sw_edit == 1'b0 && sw3_prev == 1'b1)   // 进入编辑瞬间
                grp_l <= i_sw_group;
        end
    end
    wire eff_td = editing_mode ? grp_l : i_sw_group;    // 编辑中组来自锁存
    wire td_disp = !editing_mode &&  eff_td;
    wire td_edit =  editing_mode &&  eff_td;
    wire ac_disp = !editing_mode && !eff_td;
    wire ac_edit =  editing_mode && !eff_td;

    // ---- 页面状态 ----
    reg view_time;
    reg fmt_12;
    reg date_week;
    reg [1:0] cursor;
    reg ac_sel;           // 0=闹钟 1=倒计时
    reg [1:0] alarm_idx;  // 0..2
    reg prev_ac;

    wire in_edit = td_edit || ac_edit;
    reg prev_e;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) prev_e <= 1'b0;
        else          prev_e <= in_edit;
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin prev_ac <= 1'b0; end
        else          prev_ac <= ac_disp;
    end

    // 编辑字段范围：TD 3 字段；闹钟 2；倒计时 3
    wire [1:0] cur_max = (ac_edit && !ac_sel) ? 2'd1 : 2'd2;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            view_time <= 1'b0; fmt_12 <= 1'b0; date_week <= 1'b0;
            cursor    <= 2'd0; ac_sel <= 1'b0; alarm_idx <= 2'd0;
        end else if (in_edit) begin
            if (!prev_e) cursor <= 2'd0;
            else if (kp[0])
                cursor <= (cursor >= cur_max) ? 2'd0 : cursor + 2'd1;
        end else if (td_disp) begin
            if (kp[0]) begin view_time <= ~view_time; date_week <= 1'b0; end
            else if (kp[1]) begin
                if (!view_time) fmt_12 <= ~fmt_12;
                else            date_week <= ~date_week;
            end
        end else if (ac_disp) begin
            // 保持此前所选（闹钟1/2/3 或倒计时），仅上电复位为闹钟1
            if (kp[0]) begin
                if (ac_sel) begin ac_sel <= 1'b0; alarm_idx <= 2'd0; end
                else         alarm_idx <= (alarm_idx == 2'd2) ? 2'd0 : alarm_idx + 2'd1;
            end else if (kp[1]) begin
                ac_sel <= 1'b1;
            end
        end
    end

    // ---- 实时时钟/日期 ----
    wire [7:0] hour, min, sec;
    wire [15:0] year;
    wire [7:0] mon, day;

    wire rtc_set_en  = td_edit && !view_time;
    wire rtc_date_ed = td_edit &&  view_time;
    wire [2:0] rtc_field = (!view_time)
        ? ((cursor == 2'd0) ? 3'd0 : (cursor == 2'd1) ? 3'd1 : 3'd5)
        : ((cursor == 2'd0) ? 3'd2 : (cursor == 2'd1) ? 3'd3 : 3'd4);

    reg prev_inc, prev_dec;
    wire hold_any = kh[1] || kh[2];
    localparam REP_TH = (CLK_FREQ >= 8) ? CLK_FREQ / 8 : 1;
    reg [22:0] rep_cnt;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) rep_cnt <= 23'd0;
        else if (hold_any) begin
            if (rep_cnt >= REP_TH[22:0] - 23'd1) rep_cnt <= 23'd0;
            else rep_cnt <= rep_cnt + 23'd1;
        end else rep_cnt <= 23'd0;
    end
    wire rep_tick = hold_any && (rep_cnt >= REP_TH[22:0] - 23'd1);
    wire rtc_inc = (td_edit && (kp[1] || (kh[1] && rep_tick)));
    wire rtc_dec = (td_edit && (kp[2] || (kh[2] && rep_tick)));

    rtc_counter u_rtc (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(rtc_set_en), .i_date_edit(rtc_date_ed),
        .i_field(rtc_field), .i_inc(rtc_inc), .i_dec(rtc_dec),
        .o_hour(hour), .o_minute(min), .o_second(sec),
        .o_year(year), .o_month(mon), .o_day(day));

    // ---- 闹钟 ----
    wire [7:0] alm_h, alm_m;
    wire [2:0] alm_en;
    wire       alm_ring;
    wire [1:0] alm_rno;
    wire alm_edit    = ac_edit && !ac_sel;              // 闹钟编辑（时/分）
    wire alm_toggle  = ac_disp && !ac_sel && kp[2];     // KEY3 启停用当前闹钟
    wire [1:0] alm_fld = alm_edit ? cursor[1:0] : 2'd2; // 编辑取字段，否则使能位
    wire alm_set = alm_edit || alm_toggle;
    wire alm_up  = alm_edit ? (kp[1] || (kh[1] && rep_tick))
                            : (alm_toggle && !alm_en[alarm_idx]);
    wire alm_dn  = alm_edit ? (kp[2] || (kh[2] && rep_tick))
                            : (alm_toggle &&  alm_en[alarm_idx]);

    alarm_clock u_alarm (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(alm_set), .i_idx(alarm_idx), .i_fld(alm_fld),
        .i_inc(alm_up), .i_dec(alm_dn),
        .i_cur_hour(hour), .i_cur_min(min), .i_ack(kp[3]),
        .o_sel_hour(alm_h), .o_sel_min(alm_m), .o_en(alm_en),
        .o_ring(alm_ring), .o_ring_no(alm_rno), .o_state());

    // ---- 倒计时 ----
    wire [7:0] ch, cm, cs;
    wire cd_done, cd_run;
    wire cnt_edit  = ac_edit && ac_sel;               // 倒计时编辑（时/分/秒）
    wire cnt_run   = ac_disp && ac_sel && kp[2];
    wire cnt_set   = cnt_edit;
    wire [1:0] cnt_field = cursor[1:0];
    wire cnt_inc   = cnt_edit && (kp[1] || (kh[1] && rep_tick));
    wire cnt_dec   = cnt_edit && (kp[2] || (kh[2] && rep_tick));
    reg  kh2_d;
    wire kh2_rise = kh[2] && !kh2_d;
    wire cnt_reset = ac_disp && ac_sel && kh2_rise;   // 长按复位（KEY3）
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) kh2_d <= 1'b0;
        else          kh2_d <= kh[2];
    end

    countdown #(.INIT_H(8'h00), .INIT_M(8'h01), .INIT_S(8'h00)) u_cnt (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_flag_1s(flag_1s),
        .i_set_en(cnt_set), .i_field(cnt_field), .i_inc(cnt_inc), .i_dec(cnt_dec),
        .i_run(cnt_run), .i_reset(cnt_reset),
        .o_h(ch), .o_m(cm), .o_s(cs),
        .o_done(cd_done), .o_running(cd_run));

    // ---- LED：闹钟各自闪烁 + 倒计时结束 5s ----
    reg blk_ph;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) blk_ph <= 1'b0;
        else if (flag_2hz) blk_ph <= ~blk_ph;
    end
    reg d1; reg [2:0] cnt5;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin d1 <= 0; cnt5 <= 0; end
        else begin
            d1 <= cd_done;
            if (cd_done && !d1) cnt5 <= 3'd5;
            else if (cnt5 != 0 && flag_1s) cnt5 <= cnt5 - 3'd1;
        end
    end
    assign o_led[0] = (alm_ring && alm_rno == 2'd0) ? blk_ph : 1'b0;
    assign o_led[1] = (alm_ring && alm_rno == 2'd1) ? blk_ph : 1'b0;
    assign o_led[2] = (alm_ring && alm_rno == 2'd2) ? blk_ph : 1'b0;
    assign o_led[3] = (cnt5 != 0) ? blk_ph : 1'b0;

    // ---- 12h / 星期换算 ----
    integer hv12, v12;
    reg [3:0] h_t_d, h_u_d;
    reg pm;
    always @(*) begin
        hv12 = hour[7:4]*10 + hour[3:0];
        pm = (hv12 >= 12);
        v12 = (hv12 % 12 == 0) ? 12 : hv12 % 12;
        h_t_d = (v12 / 10) % 10; h_u_d = v12 % 10;
        if (!fmt_12) begin h_t_d = hour[7:4]; h_u_d = hour[3:0]; end
    end
    integer zy, zm, zd, zK, zJ, zh;
    reg [3:0] week_day;
    always @(*) begin
        zy = year[15:12]*1000 + year[11:8]*100 + year[7:4]*10 + year[3:0];
        zm = mon[7:4]*10 + mon[3:0];
        zd = day[7:4]*10 + day[3:0];
        if (zm < 3) begin zm = zm + 12; zy = zy - 1; end
        zK = zy % 100; zJ = zy / 100;
        zh = (zd + (13*(zm+1))/5 + zK + zK/4 + zJ/4 + 5*zJ) % 7;
        week_day = ((zh + 5) % 7) + 1;
    end

    // ---- 显示内容 ----
    wire [7:0] alm_en_c = alm_en;
    wire [31:0] time_d = fmt_12 && !td_edit ? {h_t_d, h_u_d, min, sec, 8'h00}
                                            : {hour, min, sec, 8'h00};
    reg [31:0] digit_d;
    reg [7:0]  dp_d;
    reg [7:0]  blank_d;
    reg [7:0]  blink_g;
    reg [7:0]  seg_ovr;               // 覆盖字符（- / 熄灭）; 0=无
    wire [3:0] alm_no = alarm_idx + 2'd1;

    always @(*) begin
        digit_d = 32'h0; dp_d = 8'h00; blank_d = 8'h00; blink_g = 8'h00; seg_ovr = 8'h00;

        if (td_edit && view_time) begin
            digit_d = {year, mon, day};
            dp_d = 8'b0001_0100;
            if      (cursor == 2'd0) blink_g = 8'b1111_0000;
            else if (cursor == 2'd1) blink_g = 8'b0000_1100;
            else                     blink_g = 8'b0000_0011;
        end else if (td_edit) begin
            digit_d = {hour, min, sec, 8'h00};
            blank_d = 8'b0000_0011; dp_d = 8'b0101_0000;
            if      (cursor == 2'd0) blink_g = 8'b1100_0000;
            else if (cursor == 2'd1) blink_g = 8'b0011_0000;
            else                     blink_g = 8'b0000_1100;
        end else if (ac_edit && !ac_sel) begin
            // 闹钟编辑：HH.MM、第7位常驻 '-'、第8位编号，字段闪烁（时/分）
            digit_d = {alm_h, alm_m, 8'h00, 4'h0, alm_no};
            blank_d = 8'b0000_1100;
            dp_d    = 8'b0100_0000;
            seg_ovr = 8'b0000_0010;
            if      (cursor == 2'd0) blink_g = 8'b1100_0000; // 时
            else                     blink_g = 8'b0011_0000; // 分
        end else if (ac_edit && ac_sel) begin
            // 倒计时编辑：HH:MM:SS，字段闪烁（时/分/秒）
            digit_d = {ch, cm, cs, 8'h00};
            blank_d = 8'b0000_0011; dp_d = 8'b0101_0000;
            if      (cursor == 2'd0) blink_g = 8'b1100_0000; // 时
            else if (cursor == 2'd1) blink_g = 8'b0011_0000; // 分
            else                     blink_g = 8'b0000_1100; // 秒
        end else if (ac_disp && !ac_sel) begin
            // 闹钟：左4 HH.MM；5~6空；第7位常驻 '-'；第8位编号
            digit_d = {alm_h, alm_m, 8'h00, 4'h0, alm_no};
            blank_d = 8'b0000_1100;             // pos3,pos2 空
            dp_d    = 8'b0100_0000;             // pos6 分隔点
            if (!alm_en_c[alarm_idx])
                seg_ovr = 8'b1111_0010;         // 停用：左4 + 第7位 '-'（覆盖）
            else
                seg_ovr = 8'b0000_0010;         // 仅第7位常驻 '-'
        end else if (ac_disp && ac_sel) begin
            // 倒计时：左6 HH:MM:SS，第7位空；第8位 运行中=滚动圈，否则 '-'
            digit_d = {ch, cm, cs, 8'h00};
            blank_d = 8'b0000_0010; dp_d = 8'b0101_0000;
        end else if (view_time && date_week) begin
            digit_d = {week_day, 28'h0};
            blank_d = 8'h7F;
        end else if (view_time) begin
            digit_d = {year, mon, day};
            dp_d = 8'b0001_0100;
        end else begin
            digit_d = time_d;
            blank_d = 8'b0000_0010;
            if (!fmt_12) blank_d = blank_d | 8'b0000_0001;
            dp_d = 8'b0101_0000;
        end
    end

    wire [7:0] blink_off = (in_edit && !hold_any && !blk_ph) ? blink_g : 8'h00;
    wire [7:0] eff_blank = blank_d | blink_off;

    // ---- 扫描 ----
    reg [15:0] scan_cnt;
    reg [2:0]  scan_pos;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin scan_cnt <= 16'd0; scan_pos <= 3'd0; end
        else if (scan_cnt >= 16'd49999) begin
            scan_cnt <= 16'd0;
            scan_pos <= (scan_pos == 3'd7) ? 3'd0 : scan_pos + 3'd1;
        end else scan_cnt <= scan_cnt + 16'd1;
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

    // 倒计时滚动圈：每秒点亮外圈下一条（a→b→c→d→e→f，顺时针）
    reg [2:0] ring;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) ring <= 3'd0;
        else if (cd_run && flag_1s) ring <= (ring == 3'd5) ? 3'd0 : ring + 3'd1;
        else if (!cd_run) ring <= 3'd0;
    end
    reg [7:0] ring_code;              // 亮=1
    always @(*) begin
        case (ring)
            3'd0: ring_code = 8'h01;
            3'd1: ring_code = 8'h02;
            3'd2: ring_code = 8'h04;
            3'd3: ring_code = 8'h08;
            3'd4: ring_code = 8'h10;
            default: ring_code = 8'h20;
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
        else if (seg_ovr[scan_pos])
            seg_out_r = ~8'h40;                      // '-'（中间横）低点亮
        else if (ac_disp && ac_sel && scan_pos == 3'd0)
            seg_out_r = cd_run ? ~ring_code : ~8'h40; // 运行=滚动圈，否则 '-'
        else if (td_disp && !view_time && !date_week && fmt_12 && scan_pos == 3'd0)
            seg_out_r = ~(pm ? 8'h73 : 8'h77);      // 仅时间显示页的第8位 A/P
        else
            seg_out_r = ~(seg_code | (dp_d[scan_pos] ? 8'h80 : 8'h00));
    end

    assign o_seg = seg_out_r;
    assign o_sel = sel_r;

endmodule
