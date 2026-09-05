// tb_top_digital_clock：新交互集成仿真。
// 覆盖：时间/日期翻页、按 SEL 进入编辑、字段推进与 +/-、日期编辑期间时钟仍走。

`timescale 1ns / 1ps

module tb_top_digital_clock;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    wire [7:0] seg, sel;
    wire led;

    top_digital_clock #(.CLK_FREQ(CLK_FREQ), .DB_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT))
        u_dut (.i_clk(clk), .i_rst_n(rst_n), .i_key(key),
               .o_seg(seg), .o_sel(sel), .o_led(led));

    always #(CLK_PERIOD/2) clk = ~clk;
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

        // A: 默认时间页
        chk("A1", u_dut.view == 1'b0 && u_dut.editing == 1'b0, "default time view");
        chk("A2", u_dut.digit_d == {u_dut.hour, u_dut.min, u_dut.sec, 8'h00},
            "time display layout");

        // B: MODE -> 日期显示
        tap(0);
        chk("B1", u_dut.view == 1'b1, "switch to date view");
        chk("B2", u_dut.digit_d == {u_dut.year, u_dut.mon, u_dut.day}, "date layout");

        // C: 日期编辑（不暂停走时）
        tap(1);                          // 进入日期编辑
        chk("C1", u_dut.editing == 1'b1, "enter date edit");
        chk("C2", u_dut.rtc_date_ed == 1'b1, "rtc date-edit active");
        tap(2);                          // 年 +1
        chk("C3", u_dut.year == 16'h2027, "year inc in date edit");
        // 编辑期间时钟应继续走：等 ~1.5s 检查时间有前进
        cyc(DB_CNT);
        chk("C4", u_dut.hour == 8'h00 && u_dut.min == 8'h00, "time baseline");
        cyc(CLK_FREQ * 2);
        chk("C5", (u_dut.sec != 8'h00) || (u_dut.min != 8'h00) || (u_dut.hour != 8'h00),
            "clock keeps running while date editing");

        // D: 退出日期编辑回日期显示，再 MODE 回时间
        tap(0);                          // MODE：退出编辑并切到时间
        chk("D1", u_dut.view == 1'b0 && u_dut.editing == 1'b0, "back to time view");

        // E: 时间编辑（暂停走时）
        tap(1);                          // 进入时间编辑
        chk("E1", u_dut.rtc_set_en == 1'b1, "time edit active (paused)");
        chk("E2", u_dut.rtc_field == 3'd0, "cursor on hour");
        tap(2);                          // 时 +1
        chk("E3", u_dut.hour == 8'h01, "hour inc");
        tap(1);                          // -> 分
        chk("E4", u_dut.rtc_field == 3'd1, "cursor on minute");
        tap(3);                          // 分 -1 -> 59
        chk("E5", u_dut.min == 8'h59, "min wrap dec to 59");
        tap(1);                          // -> 秒
        chk("E6", u_dut.rtc_field == 3'd5, "cursor on second");
        begin : secchk
            reg [7:0] exp;
            exp = (u_dut.sec == 8'h59) ? 8'h00
                : (u_dut.sec[3:0] == 4'h9) ? {u_dut.sec[7:4] + 4'h1, 4'h0}
                : {u_dut.sec[7:4], u_dut.sec[3:0] + 4'h1};
            tap(2);
            chk("E7", u_dut.sec == exp, "sec inc (wrap ok)");
        end

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
