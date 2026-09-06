// tb_part2：验证时间/日期编辑页（SW4高+SW3低）。
// 覆盖：进入编辑、光标循环(时/分/秒、年/月/日)、+/− 生效、编辑时间暂停秒、编辑日期不停表。

`timescale 1ns / 1ps

module tb_part2;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    reg sw_group = 1;      // SW4 高(拨下)：时间/日期组
    reg sw_edit = 0;       // SW3 低(拨上)：编辑
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

    initial begin
        cyc(10);
        @(negedge clk); rst_n = 1;
        cyc(20);

        // 时间编辑：初值 00:00:00（KEY1=切字段，KEY2=+，KEY3=−）
        chk("A1", u_dut.td_edit == 1'b1, "td_edit mode");
        chk("A2", u_dut.rtc_set_en == 1'b1, "time edit pauses clock");
        chk("A3", u_dut.rtc_field == 3'd0, "cursor hour");
        tap(1);                          // KEY2 + ：时 +1
        chk("A4", u_dut.hour == 8'h01, "hour inc");
        tap(0);                          // KEY1 -> 分
        chk("A5", u_dut.rtc_field == 3'd1, "cursor minute");
        tap(2);                          // KEY3 − ：分 -1 -> 59
        chk("A6", u_dut.min == 8'h59, "min dec wrap");
        tap(0);                          // KEY1 -> 秒
        chk("A7", u_dut.rtc_field == 3'd5, "cursor second");
        // 编辑时间时走时暂停：等 ~1.2s 秒不变
        cyc(CLK_FREQ);
        chk("A8", u_dut.sec == 8'h00, "seconds frozen during time edit");

        // 退出编辑(回到显示)：SW3 置高
        @(negedge clk); sw_edit = 1;
        cyc(20);
        chk("B1", u_dut.td_disp == 1'b1, "back to display");
        tap(0);                          // 时间 -> 日期页
        chk("B2", u_dut.view_time == 1'b1, "view date");
        @(negedge clk); sw_edit = 0;     // 进入日期编辑
        cyc(20);
        chk("B3", u_dut.rtc_date_ed == 1'b1, "date edit active");
        chk("B4", u_dut.rtc_set_en == 1'b0, "clock NOT stopped in date edit");
        chk("B5", u_dut.rtc_field == 3'd2, "cursor year");
        tap(1);                          // 年 +1
        chk("B6", u_dut.year == 16'h2027, "year inc");
        tap(0);                          // -> 月
        tap(2);                          // 月 −1: 01->12 wrap
        chk("B7", u_dut.mon == 8'h12, "month dec wrap");
        tap(0);                          // -> 日
        chk("B8", u_dut.rtc_field == 3'd4, "cursor day");
        // 日期编辑期间时钟应走
        chk("B9", u_dut.rtc_set_en == 1'b0, "clock keeps running");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
