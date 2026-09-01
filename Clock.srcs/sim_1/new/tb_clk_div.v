// tb_clk_div：验证 clk_div 分频周期与脉冲个数。CLK_FREQ 缩小为 1000 以加速仿真，
// 复位在负沿释放、标志在负沿采样，保证与计数窗口严格对齐。

`timescale 1ns / 1ps

module tb_clk_div;

    localparam CLK_PERIOD = 10;    // 10ns
    localparam CLK_FREQ   = 1000;  // 测试用主频（1s = 1000 周期）
    localparam CNT_WIDTH  = 16;

    reg  clk;
    reg  rst_n;
    wire flag_1s;
    wire flag_500hz;
    wire flag_2hz;

    clk_div #(
        .CLK_FREQ  (CLK_FREQ),
        .CNT_WIDTH (CNT_WIDTH)
    ) u_clk_div (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .o_flag_1s  (flag_1s),
        .o_flag_500hz(flag_500hz),
        .o_flag_2hz (flag_2hz)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    integer cycles;
    integer cnt_1s;
    integer cnt_500hz;
    integer cnt_2hz;
    integer first_1s_cycle;
    integer first_500hz_cycle;
    integer first_2hz_cycle;

    initial begin
        clk  = 0;
        rst_n = 0;
        cycles = 0;
        cnt_1s = 0;
        cnt_500hz = 0;
        cnt_2hz = 0;
        first_1s_cycle = -1;
        first_500hz_cycle = -1;
        first_2hz_cycle = -1;

        // 复位期间运行若干周期
        repeat (10) @(posedge clk);

        // 负沿释放复位，保证下一个正沿为正常工作第 1 周期
        @(negedge clk);
        rst_n = 1;

        // 采样 5000 个周期（对应正常工作的 5000 个正沿）
        repeat (5000) begin
            @(negedge clk);
            cycles = cycles + 1;

            if (flag_1s) begin
                cnt_1s = cnt_1s + 1;
                if (first_1s_cycle < 0) first_1s_cycle = cycles;
            end
            if (flag_500hz) begin
                cnt_500hz = cnt_500hz + 1;
                if (first_500hz_cycle < 0) first_500hz_cycle = cycles;
            end
            if (flag_2hz) begin
                cnt_2hz = cnt_2hz + 1;
                if (first_2hz_cycle < 0) first_2hz_cycle = cycles;
            end
        end

        // ---- 校验 ----
        // 1Hz：周期 1000，首个在第 1000 周期，5000 周期内共 5 个
        if (cnt_1s != 5 || first_1s_cycle != CLK_FREQ)
            $error("FAIL: flag_1s count=%0d first=%0d, expect 5/%0d",
                   cnt_1s, first_1s_cycle, CLK_FREQ);
        else
            $display("PASS: flag_1s count=%0d first@%0d", cnt_1s, first_1s_cycle);

        // 500Hz：周期 2，首个在第 2 周期，5000 周期内共 2500 个
        if (cnt_500hz != 2500 || first_500hz_cycle != 2)
            $error("FAIL: flag_500hz count=%0d first=%0d, expect 2500/2",
                   cnt_500hz, first_500hz_cycle);
        else
            $display("PASS: flag_500hz count=%0d first@%0d", cnt_500hz, first_500hz_cycle);

        // 2Hz：周期 500，首个在第 500 周期，5000 周期内共 10 个
        if (cnt_2hz != 10 || first_2hz_cycle != 500)
            $error("FAIL: flag_2hz count=%0d first=%0d, expect 10/500",
                   cnt_2hz, first_2hz_cycle);
        else
            $display("PASS: flag_2hz count=%0d first@%0d", cnt_2hz, first_2hz_cycle);

        if (cnt_1s == 5 && cnt_500hz == 2500 && cnt_2hz == 10 &&
            first_1s_cycle == CLK_FREQ && first_500hz_cycle == 2 && first_2hz_cycle == 500)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
