`timescale 1ns / 1ps

// rtc_counter：实时时钟/日期。按 1Hz 使能脉冲走时；设置模式下可对指定字段 +1/-1。
// 日期支持闰年与大小月自动进位。时间/日期均以 BCD 存储。
// 调整字段编码：0=时 1=分 2=年 3=月 4=日。
// 所有状态寄存器用非阻塞赋值提交；字段递增/递减用函数完成。

module rtc_counter #(
    parameter [7:0]  INIT_SEC  = 8'h00,
    parameter [7:0]  INIT_MIN  = 8'h00,
    parameter [7:0]  INIT_HOUR = 8'h00,
    parameter [7:0]  INIT_DAY  = 8'h01,
    parameter [7:0]  INIT_MON  = 8'h01,
    parameter [15:0] INIT_YEAR = 16'h2026
)(
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_flag_1s,   // 秒使能（非时钟脚）
    input  wire         i_set_en,    // 设置模式：暂停走时，允许字段调整
    input  wire [2:0]   i_field,     // 0=时 1=分 2=年 3=月 4=日
    input  wire         i_inc,       // 字段 +1（单拍）
    input  wire         i_dec,       // 字段 -1（单拍）
    output wire [7:0]   o_hour,      // BCD 时分秒
    output wire [7:0]   o_minute,
    output wire [7:0]   o_second,
    output wire [15:0]  o_year,      // BCD 四位年
    output wire [7:0]   o_month,
    output wire [7:0]   o_day
);

    // ---- 状态寄存器（BCD 高/低半字节）----
    reg [3:0] s_t_r, s_u_r;           // 秒 十/个
    reg [3:0] m_t_r, m_u_r;           // 分
    reg [3:0] h_t_r, h_u_r;           // 时
    reg [3:0] y3_r, y2_r, y1_r, y0_r; // 年 4 位
    reg [3:0] mo_t_r, mo_u_r;         // 月
    reg [3:0] d_t_r, d_u_r;           // 日

    // ================= 组合函数 =================

    // 两位 BCD 字段 +1（不处理最高位回绕，由调用方处理）
    function automatic [7:0] bcd2_inc(input [3:0] hi, input [3:0] lo);
        begin bcd2_inc = (lo == 4'h9) ? {hi + 4'h1, 4'h0} : {hi, lo + 4'h1}; end
    endfunction

    // 两位 BCD 字段 -1（hi 不允许为 0 时调用，由调用方处理）
    function automatic [7:0] bcd2_dec(input [3:0] hi, input [3:0] lo);
        begin bcd2_dec = (lo == 4'h0) ? {hi - 4'h1, 4'h9} : {hi, lo - 4'h1}; end
    endfunction

    // 四位 BCD 年 +1（9999 回绕 0000）
    function automatic [15:0] bcd4_inc(input [15:0] v);
        begin
            bcd4_inc = v;
            if (v[3:0] == 4'h9) begin
                bcd4_inc[3:0] = 4'h0;
                if (v[7:4] == 4'h9) begin
                    bcd4_inc[7:4] = 4'h0;
                    if (v[11:8] == 4'h9) begin
                        bcd4_inc[11:8] = 4'h0;
                        bcd4_inc[15:12] = (v[15:12] == 4'h9) ? 4'h0 : v[15:12] + 4'h1;
                    end else
                        bcd4_inc[11:8] = v[11:8] + 4'h1;
                end else
                    bcd4_inc[7:4] = v[7:4] + 4'h1;
            end else
                bcd4_inc[3:0] = v[3:0] + 4'h1;
        end
    endfunction

    // 四位 BCD 年 -1（0000 回绕 9999）
    function automatic [15:0] bcd4_dec(input [15:0] v);
        begin
            bcd4_dec = v;
            if (v[3:0] == 4'h0) begin
                bcd4_dec[3:0] = 4'h9;
                if (v[7:4] == 4'h0) begin
                    bcd4_dec[7:4] = 4'h9;
                    if (v[11:8] == 4'h0) begin
                        bcd4_dec[11:8] = 4'h9;
                        bcd4_dec[15:12] = (v[15:12] == 4'h0) ? 4'h9 : v[15:12] - 4'h1;
                    end else
                        bcd4_dec[11:8] = v[11:8] - 4'h1;
                end else
                    bcd4_dec[7:4] = v[7:4] - 4'h1;
            end else
                bcd4_dec[3:0] = v[3:0] - 4'h1;
        end
    endfunction

    // 闰年：由 BCD 位直接推导，精确覆盖所有年份（含 2000/2100）
    //   Y%4 = (2*y1+y0) mod 4；世纪两位 (y3,y2)%4 = (2*y3+y2) mod 4。
    //   Y%100==0 <=> y1==0 && y0==0；Y%400==0 需再满足世纪两位被 4 整除。
    function automatic is_leap(input [3:0] y3, y2, y1, y0);
        reg [4:0] ymod4;
        reg [4:0] cmod4;
        begin
            ymod4 = (2 * y1 + y0) & 4'h3;
            cmod4 = (2 * y3 + y2) & 4'h3;
            is_leap = (ymod4 == 0) && ((y1 != 0) || (y0 != 0) || (cmod4 == 0));
        end
    endfunction

    // 当月最大天数，返回 BCD 十六进制值（28/29/30/31）
    function automatic [7:0] max_day(input [3:0] mo_t, mo_u, input leap);
        begin
            if (mo_t == 4'h0 && mo_u == 4'h2)               // 2 月
                max_day = leap ? 8'h29 : 8'h28;
            else if ((mo_t == 4'h0 && (mo_u == 4'h4 || mo_u == 4'h6 || mo_u == 4'h9))
                     || (mo_t == 4'h1 && mo_u == 4'h1))      // 4/6/9/11 月
                max_day = 8'h30;
            else
                max_day = 8'h31;
        end
    endfunction

    // 月 +1（12 回绕 1）
    function automatic [7:0] month_inc(input [3:0] mo_t, mo_u);
        begin
            if (mo_t == 4'h1 && mo_u == 4'h2)  month_inc = 8'h01;
            else if (mo_u == 4'h9)             month_inc = {mo_t + 4'h1, 4'h0};
            else                               month_inc = {mo_t, mo_u + 4'h1};
        end
    endfunction

    // 月 -1（1 回绕 12）
    function automatic [7:0] month_dec(input [3:0] mo_t, mo_u);
        begin
            if (mo_t == 4'h0 && mo_u == 4'h1)  month_dec = 8'h12;
            else if (mo_u == 4'h0)             month_dec = {mo_t - 4'h1, 4'h9};
            else                               month_dec = {mo_t, mo_u - 4'h1};
        end
    endfunction

    // ================= 组合状态 =================
    wire [7:0]  sec_bcd   = {s_t_r, s_u_r};
    wire [7:0]  min_bcd   = {m_t_r, m_u_r};
    wire [7:0]  hour_bcd  = {h_t_r, h_u_r};
    wire [7:0]  day_bcd   = {d_t_r, d_u_r};
    wire        leap_w    = is_leap(y3_r, y2_r, y1_r, y0_r);
    wire [7:0]  max_d_w   = max_day(mo_t_r, mo_u_r, leap_w);
    wire        midnight_w = (hour_bcd == 8'h23) && (min_bcd == 8'h59)
                             && (sec_bcd == 8'h59);

    // ================= 主时序逻辑 =================
    // 下一拍中间量（阻塞赋值，便于按序计算与日月年相互约束）
    reg [3:0]  s_t_n, s_u_n, m_t_n, m_u_n, h_t_n, h_u_n;
    reg [3:0]  y3_n, y2_n, y1_n, y0_n;
    reg [3:0]  mo_t_n, mo_u_n, d_t_n, d_u_n;
    reg [15:0] year_n;
    reg [7:0]  mon_n, day_n;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            s_t_r <= INIT_SEC[7:4];  s_u_r <= INIT_SEC[3:0];
            m_t_r <= INIT_MIN[7:4];  m_u_r <= INIT_MIN[3:0];
            h_t_r <= INIT_HOUR[7:4]; h_u_r <= INIT_HOUR[3:0];
            y3_r <= INIT_YEAR[15:12]; y2_r <= INIT_YEAR[11:8];
            y1_r <= INIT_YEAR[7:4];  y0_r <= INIT_YEAR[3:0];
            mo_t_r <= INIT_MON[7:4]; mo_u_r <= INIT_MON[3:0];
            d_t_r <= INIT_DAY[7:4];  d_u_r <= INIT_DAY[3:0];
        end else begin
            // ---- 计算下一拍：默认保持不变 ----
            {s_t_n, s_u_n} = {s_t_r, s_u_r};
            {m_t_n, m_u_n} = {m_t_r, m_u_r};
            {h_t_n, h_u_n} = {h_t_r, h_u_r};
            {y3_n, y2_n, y1_n, y0_n} = {y3_r, y2_r, y1_r, y0_r};
            {mo_t_n, mo_u_n} = {mo_t_r, mo_u_r};
            {d_t_n, d_u_n} = {d_t_r, d_u_r};

            if (i_set_en) begin
                // ===== 设置模式：字段调整（每拍至多一个操作）=====
                if (i_inc) begin
                    case (i_field)
                        3'd0: {h_t_n, h_u_n} = (hour_bcd == 8'h23) ? 8'h00
                                                                    : bcd2_inc(h_t_r, h_u_r);
                        3'd1: {m_t_n, m_u_n} = (min_bcd == 8'h59) ? 8'h00
                                                                    : bcd2_inc(m_t_r, m_u_r);
                        3'd2: {y3_n, y2_n, y1_n, y0_n} = bcd4_inc({y3_r, y2_r, y1_r, y0_r});
                        3'd3: {mo_t_n, mo_u_n} = month_inc(mo_t_r, mo_u_r);
                        3'd4: {d_t_n, d_u_n} = (day_bcd == max_d_w) ? 8'h01
                                                                      : bcd2_inc(d_t_r, d_u_r);
                        default: ;
                    endcase
                end else if (i_dec) begin
                    case (i_field)
                        3'd0: {h_t_n, h_u_n} = (hour_bcd == 8'h00) ? 8'h23
                                                                    : bcd2_dec(h_t_r, h_u_r);
                        3'd1: {m_t_n, m_u_n} = (min_bcd == 8'h00) ? 8'h59
                                                                    : bcd2_dec(m_t_r, m_u_r);
                        3'd2: {y3_n, y2_n, y1_n, y0_n} = bcd4_dec({y3_r, y2_r, y1_r, y0_r});
                        3'd3: {mo_t_n, mo_u_n} = month_dec(mo_t_r, mo_u_r);
                        3'd4: {d_t_n, d_u_n} = (day_bcd == 8'h01) ? max_d_w
                                                                    : bcd2_dec(d_t_r, d_u_r);
                        default: ;
                    endcase
                end

                // 年月调整后，日超出新月份天数时收缩（如 2/29->平年、31->30 天月）
                if (i_inc || i_dec) begin : clamp_day
                    reg [7:0] dm;
                    dm = max_day(mo_t_n, mo_u_n,
                                 is_leap(y3_n, y2_n, y1_n, y0_n));
                    if ({d_t_n, d_u_n} > dm)
                        {d_t_n, d_u_n} = dm;
                end
            end else if (i_flag_1s) begin
                // ===== 正常走时 =====
                if (sec_bcd == 8'h59) begin
                    {s_t_n, s_u_n} = 8'h00;
                    if (min_bcd == 8'h59) begin
                        {m_t_n, m_u_n} = 8'h00;
                        {h_t_n, h_u_n} = (hour_bcd == 8'h23) ? 8'h00
                                                              : bcd2_inc(h_t_r, h_u_r);
                    end else begin
                        {m_t_n, m_u_n} = bcd2_inc(m_t_r, m_u_r);
                    end
                end else begin
                    {s_t_n, s_u_n} = bcd2_inc(s_t_r, s_u_r);
                end

                // 日期进位：23:59:59 走完即跨天
                if (midnight_w) begin
                    if (day_bcd == max_d_w) begin
                        {d_t_n, d_u_n} = 8'h01;
                        if ({mo_t_r, mo_u_r} == 8'h12) begin
                            {mo_t_n, mo_u_n} = 8'h01;
                            {y3_n, y2_n, y1_n, y0_n} =
                                bcd4_inc({y3_r, y2_r, y1_r, y0_r});
                        end else begin
                            {mo_t_n, mo_u_n} = month_inc(mo_t_r, mo_u_r);
                        end
                    end else begin
                        {d_t_n, d_u_n} = bcd2_inc(d_t_r, d_u_r);
                    end
                end
            end

            // ---- 提交 ----
            s_t_r <= s_t_n;   s_u_r <= s_u_n;
            m_t_r <= m_t_n;   m_u_r <= m_u_n;
            h_t_r <= h_t_n;   h_u_r <= h_u_n;
            y3_r <= y3_n;     y2_r <= y2_n; y1_r <= y1_n; y0_r <= y0_n;
            mo_t_r <= mo_t_n; mo_u_r <= mo_u_n;
            d_t_r <= d_t_n;   d_u_r <= d_u_n;
        end
    end

    // 冗余状态（供阅读，实际以提交寄存器为准）
    // assign o_... 直接取自 *_r
    assign o_hour   = {h_t_r, h_u_r};
    assign o_minute = {m_t_r, m_u_r};
    assign o_second = {s_t_r, s_u_r};
    assign o_year   = {y3_r, y2_r, y1_r, y0_r};
    assign o_month  = {mo_t_r, mo_u_r};
    assign o_day    = {d_t_r, d_u_r};

endmodule
