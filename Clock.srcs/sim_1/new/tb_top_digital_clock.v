// tb_top_digital_clock：顶层集成仿真。
// 以 CLK_FREQ=1000 缩小主频（1s=1000 周期），DB_CNT/HOLD_CNT 缩小以加速按键。
// 覆盖：模式切换、时间/日期设置增减、闹钟使能与到点响铃/解除、倒计时设定与运行。
// 校验通过层次引用读取顶层内部信号（u_dut.*）。

`timescale 1ns / 1ps

module tb_top_digital_clock;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    wire [7:0] seg;
    wire [5:0] sel;
    wire led;

    top_digital_clock #(
        .CLK_FREQ(CLK_FREQ), .DB_CNT(DB_CNT), .HOLD_CNT(HOLD_CNT)
    ) u_dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_key(key),
        .o_seg(seg), .o_sel(sel), .o_led(led)
    );

    always #(CLK_PERIOD/2) clk = ~clk;
    integer fails = 0;
    integer c;

    // 等待一个 posedge 周期
    task cyc(input integer n);
        integer c;
        begin for (c = 0; c < n; c = c + 1) @(posedge clk); end
    endtask

    // 短按一次按键 k（0..5），包含消抖等待与复位等待
    task tap(input integer k);
        integer c;
        begin
            @(negedge clk); key = key & ~(6'b1 << k);
            cyc(DB_CNT + 10);
            @(negedge clk); key = 6'b111111;
            cyc(DB_CNT + 10);
        end
    endtask

    // 按住按键 k 至少 n 个周期（跨越多秒使能，供闹钟解除等场景）
    task hold_key(input integer k, input integer n);
        begin
            @(negedge clk); key = key & ~(6'b1 << k);
            cyc(n);
            @(negedge clk); key = 6'b111111;
            cyc(DB_CNT + 10);
        end
    endtask

    // 循环等待直到条件成立或超时（maxcyc 周期）
    task wait_until(input cond, input integer maxcyc);
        integer c;
        begin
            c = 0;
            while (!cond && c < maxcyc) begin
                @(posedge clk);
                c = c + 1;
            end
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

    initial begin
        cyc(10);
        @(negedge clk); rst_n = 1;
        cyc(20);

        // ===== A: 时间模式默认 00:00，MODE 循环到日期模式 =====
        chk("A1", u_dut.mode == 3'd0, "default mode TIME");
        chk("A2", u_dut.hour == 8'h00 && u_dut.min == 8'h00, "rtc starts 00:00");

        tap(0);                        // TIME -> DATE
        chk("B1", u_dut.mode == 3'd1, "MODE to DATE");
        chk("B2", u_dut.mon == 8'h01 && u_dut.day == 8'h01 && u_dut.year == 16'h2026,
            "default date 2026-01-01");

        // ===== C: 时间设置（SET_T）：时 +1/-1 =====
        tap(0);                        // DATE -> SET_T
        chk("C1", u_dut.mode == 3'd2, "MODE to SET_T");
        chk("C2", u_dut.rtc_set_en == 1'b1, "rtc in set mode");
        tap(2);                        // 时 +1 (hour 00->01)
        chk("C3", u_dut.hour == 8'h01, "hour inc in SET_T");
        tap(3);                        // 时 -1
        chk("C4", u_dut.hour == 8'h00, "hour dec in SET_T");

        // ===== D: 日期设置（SET_D）：年 +1 =====
        tap(0);                        // SET_T -> SET_D
        chk("D1", u_dut.mode == 3'd3, "MODE to SET_D");
        tap(2);                        // 年 +1 (cursor0 = 年)
        chk("D2", u_dut.year == 16'h2027, "year inc in SET_D");
        tap(3);                        // 年 -1 复原
        chk("D3", u_dut.year == 16'h2026, "year dec restore");

        // ===== E: 闹钟设置：alarm0 调到 00:00 并使能 =====
        tap(0);                        // SET_D -> ALM
        chk("E1", u_dut.mode == 3'd4, "MODE to ALM");
        // cursor0 = alarm0 时（默认 08），按 - 8 次到 00
        repeat (8) tap(3);
        chk("E2", u_dut.alm_h == 8'h00, "alarm0 hour set 00");
        tap(1);                        // SEL -> alarm0 分
        tap(1);                        // SEL -> alarm0 使能编辑
        chk("E3", u_dut.alm_idx == 2'd0 && u_dut.alm_fld == 2'd2, "alarm0 enable edit");
        tap(2);                        // 使能开
        chk("E4", u_dut.alm_en[0] == 1'b1, "alarm0 enabled");

        // ===== F: 回到时间并设到 23:59 以触发 00:00 闹钟 =====
        tap(0);                        // ALM -> CNT
        tap(0);                        // CNT -> TIME
        chk("F1", u_dut.mode == 3'd0, "back to TIME");
        tap(0);                        // -> DATE
        tap(0);                        // -> SET_T
        // 时：0 减 1 -> 23
        tap(3);
        chk("F2", u_dut.hour == 8'h23, "hour 23 in SET_T");
        tap(1);                        // SEL -> 分
        // 分 0 -> 59
        repeat (59) tap(2);
        chk("F3", u_dut.min == 8'h59, "min 59 in SET_T");
        tap(0);                        // SET_T -> SET_D
        tap(0);                        // SET_D -> ALM
        tap(0);                        // ALM -> CNT
        tap(0);                        // CNT -> TIME

        // 快进等待到 00:00 闹钟响（内联实时采样，勿用 task 形参传条件）
        c = 0;
        while (!u_dut.ring && c < 200 * CLK_FREQ) begin
            @(posedge clk);
            c = c + 1;
        end
        chk("F4", u_dut.ring == 1'b1, "alarm rings at 00:00");

        // 按住 KEY4（解除）跨越多秒，确保落在闹钟 FSM 的秒节拍上
        hold_key(4, CLK_FREQ * 2);
        chk("F5", u_dut.ring == 1'b0, "ack dismisses ring");
        tap(0); tap(0); tap(0); tap(0); // -> DATE, SET_T, SET_D, ALM
        tap(0);                        // -> CNT
        chk("G1", u_dut.mode == 3'd5, "MODE to CNT");

        // ===== G: 倒计时：设初值 00:03，运行到 done =====
        // cursor0=分（初值 1）：先 -1 到 0；SEL->秒；秒 +3；SEL->运行视图
        tap(3);                        // 分 1->0
        tap(1);                        // SEL -> 秒
        tap(2); tap(2); tap(2);        // 秒 0->3
        chk("G2", u_dut.cnt_cfg == 1'b1, "cnt in config");
        tap(1);                        // -> 运行视图
        chk("G3", u_dut.cnt_cfg == 1'b0, "cnt config exit");
        tap(4);                        // 开始
        chk("G4", u_dut.cnt_running == 1'b1, "countdown running");
        c = 0;
        while (!u_dut.cnt_done && c < 8 * CLK_FREQ) begin
            @(posedge clk);
            c = c + 1;
        end
        chk("G5", u_dut.cnt_done == 1'b1, "countdown done");
        tap(5);                        // reset
        chk("G6", u_dut.cnt_done == 1'b0, "countdown reset clears done");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
