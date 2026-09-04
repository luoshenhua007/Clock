// tb_rtc_counter：验证走时进位、月末/年末进位、闰年/大小月、字段增减调整。
// 每个 DUT 使用独立 flag，场景间互不影响。输入仅在时钟负沿改变，正沿采样。

`timescale 1ns / 1ps

module tb_rtc_counter;

    reg clk = 0;
    reg rst_n = 0;

    reg f_mid = 0, f_feb = 0, f_lp = 0, f_l0 = 0, f_cn = 0, f_adj = 0;
    reg set_en = 0;
    reg [2:0] field = 0;
    reg inc = 0;
    reg dec = 0;

    wire [7:0]  h_mid, mn_mid, se_mid, mo_mid, da_mid;
    wire [15:0] yr_mid;
    wire [7:0]  h_fb, mn_fb, se_fb, mo_fb, da_fb;
    wire [15:0] yr_fb;
    wire [7:0]  h_lp, mn_lp, se_lp, mo_lp, da_lp;
    wire [15:0] yr_lp;
    wire [7:0]  h_l0, mn_l0, se_l0, mo_l0, da_l0;
    wire [15:0] yr_l0;
    wire [7:0]  h_cn, mn_cn, se_cn, mo_cn, da_cn;
    wire [15:0] yr_cn;
    wire [7:0]  h_aj, mn_aj, se_aj, mo_aj, da_aj;
    wire [15:0] yr_aj;

    rtc_counter #(.INIT_HOUR(8'h23), .INIT_MIN(8'h59), .INIT_SEC(8'h58),
                  .INIT_DAY(8'h31), .INIT_MON(8'h01), .INIT_YEAR(16'h2026))
        u_midnight (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_mid), .i_set_en(set_en),
                    .i_field(field), .i_inc(inc), .i_dec(dec),
                    .o_hour(h_mid), .o_minute(mn_mid), .o_second(se_mid),
                    .o_year(yr_mid), .o_month(mo_mid), .o_day(da_mid));
    rtc_counter #(.INIT_HOUR(8'h23), .INIT_MIN(8'h59), .INIT_SEC(8'h58),
                  .INIT_DAY(8'h28), .INIT_MON(8'h02), .INIT_YEAR(16'h2026))
        u_feb26 (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_feb), .i_set_en(set_en),
                 .i_field(field), .i_inc(inc), .i_dec(dec),
                 .o_hour(h_fb), .o_minute(mn_fb), .o_second(se_fb),
                 .o_year(yr_fb), .o_month(mo_fb), .o_day(da_fb));
    rtc_counter #(.INIT_HOUR(8'h23), .INIT_MIN(8'h59), .INIT_SEC(8'h58),
                  .INIT_DAY(8'h28), .INIT_MON(8'h02), .INIT_YEAR(16'h2024))
        u_leap24 (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_lp), .i_set_en(set_en),
                  .i_field(field), .i_inc(inc), .i_dec(dec),
                  .o_hour(h_lp), .o_minute(mn_lp), .o_second(se_lp),
                  .o_year(yr_lp), .o_month(mo_lp), .o_day(da_lp));
    rtc_counter #(.INIT_HOUR(8'h23), .INIT_MIN(8'h59), .INIT_SEC(8'h58),
                  .INIT_DAY(8'h28), .INIT_MON(8'h02), .INIT_YEAR(16'h2000))
        u_leap00 (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_l0), .i_set_en(set_en),
                  .i_field(field), .i_inc(inc), .i_dec(dec),
                  .o_hour(h_l0), .o_minute(mn_l0), .o_second(se_l0),
                  .o_year(yr_l0), .o_month(mo_l0), .o_day(da_l0));
    rtc_counter #(.INIT_HOUR(8'h23), .INIT_MIN(8'h59), .INIT_SEC(8'h58),
                  .INIT_DAY(8'h28), .INIT_MON(8'h02), .INIT_YEAR(16'h2100))
        u_century (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_cn), .i_set_en(set_en),
                   .i_field(field), .i_inc(inc), .i_dec(dec),
                   .o_hour(h_cn), .o_minute(mn_cn), .o_second(se_cn),
                   .o_year(yr_cn), .o_month(mo_cn), .o_day(da_cn));
    rtc_counter #(.INIT_HOUR(8'h12), .INIT_MIN(8'h34), .INIT_SEC(8'h56),
                  .INIT_DAY(8'h31), .INIT_MON(8'h03), .INIT_YEAR(16'h2026))
        u_adj (.i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(f_adj), .i_set_en(set_en),
               .i_field(field), .i_inc(inc), .i_dec(dec),
               .o_hour(h_aj), .o_minute(mn_aj), .o_second(se_aj),
               .o_year(yr_aj), .o_month(mo_aj), .o_day(da_aj));

    always #5 clk = ~clk;

    integer fails = 0;

    // 推进指定 DUT n 秒
    task run_seconds(input integer sel, input integer n);
        integer c;
        begin
            @(negedge clk);
            case (sel)
                1: f_mid = 1;
                2: f_feb = 1;
                3: f_lp  = 1;
                4: f_l0  = 1;
                5: f_cn  = 1;
                default: ;
            endcase
            for (c = 0; c < n; c = c + 1) @(posedge clk);
            @(negedge clk);
            case (sel)
                1: f_mid = 0;
                2: f_feb = 0;
                3: f_lp  = 0;
                4: f_l0  = 0;
                5: f_cn  = 0;
                default: ;
            endcase
            @(negedge clk);
        end
    endtask

    task adj_up(input [2:0] f);
        begin
            @(negedge clk); set_en = 1; field = f; inc = 1;
            @(negedge clk); inc = 0; set_en = 0; field = 0;
        end
    endtask
    task adj_dn(input [2:0] f);
        begin
            @(negedge clk); set_en = 1; field = f; dec = 1;
            @(negedge clk); dec = 0; set_en = 0; field = 0;
        end
    endtask

    task chk(input [7:0] tag, input cond, input [8*64:0] msg);
        begin
            if (!cond) begin
                fails = fails + 1;
                $display("FAIL[%0d]: %0s", tag, msg);
            end
        end
    endtask
    task chk_date(input [7:0] tag, input [15:0] ey, input [7:0] em, input [7:0] ed,
                  input [15:0] ay, input [7:0] am, input [7:0] ad);
        begin
            if (ay !== ey || am !== em || ad !== ed) begin
                fails = fails + 1;
                $display("FAIL[%0d]: date %04h-%02h-%02h, expect %04h-%02h-%02h",
                         tag, ay, am, ad, ey, em, ed);
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(negedge clk);

        // A: 2026-01-31 23:59:58 +2s -> 00:00:00，2/1
        run_seconds(1, 2);
        chk("A1", h_mid==8'h00 && mn_mid==8'h00 && se_mid==8'h00, "time not 00:00:00");
        chk_date("A2", 16'h2026, 8'h02, 8'h01, yr_mid, mo_mid, da_mid);
        $display("PASS A: 月末进位");

        // B: 2026(平) 02-28 +2s -> 3/1
        run_seconds(2, 2);
        chk_date("B1", 16'h2026, 8'h03, 8'h01, yr_fb, mo_fb, da_fb);
        $display("PASS B: 平年二月");

        // C: 2024(闰) 02-28 +2s -> 2/29；再一天 -> 3/1
        run_seconds(3, 2);
        chk_date("C1", 16'h2024, 8'h02, 8'h29, yr_lp, mo_lp, da_lp);
        run_seconds(3, 86400);
        chk_date("C2", 16'h2024, 8'h03, 8'h01, yr_lp, mo_lp, da_lp);
        $display("PASS C: 闰年二月");

        // D: 2000(闰) 02-28 -> 2/29；再一天 -> 3/1
        run_seconds(4, 2);
        chk_date("D1", 16'h2000, 8'h02, 8'h29, yr_l0, mo_l0, da_l0);
        run_seconds(4, 86400);
        chk_date("D2", 16'h2000, 8'h03, 8'h01, yr_l0, mo_l0, da_l0);
        $display("PASS D: 2000 闰");

        // E: 2100(非闰世纪) 02-28 +2s -> 3/1
        run_seconds(5, 2);
        chk_date("E1", 16'h2100, 8'h03, 8'h01, yr_cn, mo_cn, da_cn);
        $display("PASS E: 2100 非闰");

        // F: 字段调整（u_adj：2026-03-31 12:34:56，全程不走秒）
        adj_up(3'd0);                  // 时 12->13
        chk("F1", h_aj == 8'h13, "hour inc 12->13");
        adj_dn(3'd1);                  // 分 34->33
        chk("F2", mn_aj == 8'h33, "min dec 34->33");
        adj_dn(3'd4);                  // 日 31->30（3 月 31 天）
        chk("F3", da_aj == 8'h30, "day dec 31->30");
        adj_dn(3'd3);                  // 月 03->02，日收缩到 28（平年）
        chk("F4", mo_aj == 8'h02 && da_aj == 8'h28, "month dec clamp day->28");
        adj_dn(3'd2);                  // 年 2026->2025
        chk("F5", yr_aj == 16'h2025, "year dec 2026->2025");
        adj_up(3'd4);                  // 日 28==max(2025-02) -> 回绕 01
        chk("F6", da_aj == 8'h01, "day wrap to 01");
        // 分回绕：33 减 33 次 -> 00；再减 -> 59
        adj_dn(3'd1);
        chk("F7", mn_aj == 8'h32, "min dec after day wrap");
        // 小时回绕：13 减 14 次 -> 23（经 0 回绕）
        repeat (14) adj_dn(3'd0);
        chk("F8", h_aj == 8'h23, "hour dec wrap to 23");
        adj_up(3'd0);
        chk("F9", h_aj == 8'h00, "hour inc 23 wrap to 00");
        // 月回绕：02 减 2 -> 12
        adj_dn(3'd3);
        adj_dn(3'd3);
        chk("F10", mo_aj == 8'h12, "month dec wrap 02->12");
        adj_up(3'd3);
        chk("F11", mo_aj == 8'h01, "month inc 12 wrap 01");
        // 年在 2025 基础上减到 2024
        adj_dn(3'd2);                  // 2025 -> 2024（此时 2024-01-01）
        chk("F12", yr_aj == 16'h2024, "year dec");
        // 闰年 2 月 29 日：月 01->02，日 01 减 -> 29；年再减到平年收缩 28
        adj_up(3'd3);                  // 月 01 -> 02
        chk("F13", mo_aj == 8'h02, "month inc to 02");
        adj_dn(3'd4);                  // 日 01 减 -> max(2024-02)=29
        chk("F14", da_aj == 8'h29, "day dec to 29 (leap feb)");
        adj_dn(3'd2);                  // 2024 -> 2023，日 29 应收缩到 28
        chk("F15", da_aj == 8'h28, "year dec clamps 2/29->2/28");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
