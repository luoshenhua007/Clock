// tb_part1：验证时间/日期显示页：KEY1 切换、KEY2 12/24h 与 星期、weekday=4(2026-01-01 周四)。

`timescale 1ns / 1ps

module tb_part1;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    reg sw_group = 1;      // 两开关均“上”= 时间/日期·显示（实测）
    reg sw_edit = 1;
    wire [7:0] seg, sel;
    wire led;

    top_digital_clock #(.CLK_FREQ(CLK_FREQ), .DB_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT))
        u_dut (.i_clk(clk), .i_rst_n(rst_n), .i_key(key),
               .i_sw_group(sw_group), .i_sw_edit(sw_edit),
               .o_seg(seg), .o_sel(sel), .o_led(led));

    always #5 clk = ~clk;
    integer fails = 0;
    integer c;

    task cyc(input integer n);
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge clk); end
    endtask

    task tap(input integer k);
        begin
            @(negedge clk); key = key & ~(6'b1 << k);
            cyc(DB_CNT + 10);
            @(negedge clk); key = 6'b111111;
            cyc(DB_CNT + 10);
        end
    endtask

    task chk(input [7:0] t, input cond, input [8*64:0] msg);
        begin
            if (!cond) begin
                fails = fails + 1;
                $display("FAIL[%0d]: %0s", t, msg);
            end
        end
    endtask

    // 让时间快速走到 13:34:56 以检查 12h 换算（直接改寄存器初值不便，改用 flag 快进）
    // 采用直接强制内部寄存器快速设到 13:34:56
    initial begin
        cyc(10);
        @(negedge clk); rst_n = 1;
        cyc(20);

        force u_dut.u_rtc.h_t_r = 4'h1;
        force u_dut.u_rtc.h_u_r = 4'h3;
        force u_dut.u_rtc.m_t_r = 4'h3;
        force u_dut.u_rtc.m_u_r = 4'h4;
        force u_dut.u_rtc.s_t_r = 4'h5;
        force u_dut.u_rtc.s_u_r = 4'h6;
        cyc(5);
        release u_dut.u_rtc.h_t_r; release u_dut.u_rtc.h_u_r;
        release u_dut.u_rtc.m_t_r; release u_dut.u_rtc.m_u_r;
        release u_dut.u_rtc.s_t_r; release u_dut.u_rtc.s_u_r;
        cyc(5);

        chk("A1", u_dut.view_time == 1'b0, "default time view");
        chk("A2", u_dut.fmt_12 == 1'b0, "default 24h");
        // 24h: 13:34:56
        chk("A3", u_dut.hour == 8'h13 && u_dut.min == 8'h34 && u_dut.sec == 8'h56,
            "24h time regs");
        // KEY1 -> 日期页
        tap(0);
        chk("B1", u_dut.view_time == 1'b1, "time->date");
        chk("B2", u_dut.week_day == 4'd4, "2026-01-01 is Thursday(4)");
        // KEY2 -> 星期显示
        tap(1);
        chk("C1", u_dut.date_week == 1'b1, "date->week view");
        chk("C2", u_dut.digit_d[31:28] == 4'd4, "week digit 4 on first tube");
        // 切回时间，KEY2 -> 12h
        tap(0);                       // -> time
        tap(1);                       // 12h
        chk("D1", u_dut.fmt_12 == 1'b1, "fmt 12h");
        chk("D2", u_dut.h_t_d == 0 && u_dut.h_u_d == 1, "13h->01(12h)");
        chk("D3", u_dut.pm == 1'b1, "13h is PM");
        // 12:34:56 应 PM + P
        // 检查 pos0 使用 P 覆盖逻辑：直接看 seg 由显示层处理，这里仅验证换算字段

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
