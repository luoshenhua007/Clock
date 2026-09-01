// tb_key_debounce：验证单按键消抖/脉冲/长按。DEBOUNCE_CNT、HOLD_CNT 缩小以加速，
// 输入驱动与采样避开时钟边沿，经负沿监测器统计脉冲总数，覆盖短按(含抖动)/释放/长按/复位。

`timescale 1ns / 1ps

module tb_key_debounce;

    localparam CLK_PERIOD    = 10;
    localparam DEBOUNCE_CNT  = 8;
    localparam HOLD_CNT      = 30;
    localparam KEY_ACTIVE_LOW = 1;

    reg  clk;
    reg  rst_n;
    reg  key;
    wire pulse;
    wire hold;

    // 按下脉冲计数器：在时钟负沿采样 pulse（此时正沿 NBA 已稳定，
    // 避免与模块在同一正沿更新 o_pulse 产生读旧值竞争）
    reg [7:0] pulse_total;

    key_debounce_one #(
        .KEY_ACTIVE_LOW (KEY_ACTIVE_LOW),
        .DEBOUNCE_CNT   (DEBOUNCE_CNT),
        .HOLD_CNT       (HOLD_CNT),
        .CNT_WIDTH      (8)
    ) u_key_debounce_one (
        .i_clk   (clk),
        .i_rst_n (rst_n),
        .i_key   (key),
        .o_pulse (pulse),
        .o_hold  (hold)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n)
            pulse_total <= 8'd0;
        else if (pulse)
            pulse_total <= pulse_total + 8'd1;
    end

    // 等待 n 个完整时钟周期，并在时钟上沿后 1/4 周期处返回
    // （远离正/负沿，驱动输入与采样输出均避开边沿竞争）
    task wait_cycles(input integer n);
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(posedge clk);
            #(CLK_PERIOD/4);
        end
    endtask

    // 模拟按键抖动：按下/释放过程附近快速翻转，最终稳定到 level
    task bounce_key(input integer level);
        integer b;
        begin
            for (b = 0; b < 3; b = b + 1) begin
                key = level;
                wait_cycles(1);
                key = ~level;
                wait_cycles(1);
            end
            key = level;
        end
    endtask

    initial begin
        clk  = 0;
        rst_n = 0;
        key  = 1; // 低有效：空闲为高

        // ---- 场景1：带抖动的短按 ----
        wait_cycles(10);
        rst_n = 1;
        wait_cycles(5);

        if (pulse_total !== 8'd0)
            $error("FAIL: pulse_total not 0 after reset");

        // 时序参考（相对最后一次按键变化）：
        //   同步 2 拍 + 变化沿检测 1 拍 + 消抖 8 拍 -> key_reg 约 11 拍后生效；
        //   pulse 比 key_reg 再晚 1 拍，监测器再晚 1 拍计数 -> 约 13~14 拍；
        //   hold 在 key_reg 生效约 29 拍后拉高 -> 约 40~41 拍。
        // 因此采样等待统一使用「DEBOUNCE_CNT + 8」= 16 拍抓脉冲并留有余量。

        bounce_key(0);                          // 按下（含抖动）
        wait_cycles(DEBOUNCE_CNT + 8);          // 等待消抖完成并捕获脉冲
        if (pulse_total !== 8'd1)
            $error("FAIL: after short press pulse_total=%0d, expect 1", pulse_total);
        else
            $display("PASS: short press -> 1 pulse");
        if (hold !== 1'b0)
            $error("FAIL: hold asserted during short press");
        else
            $display("PASS: hold stays 0 during short press");

        // 继续按住一小段（总按住时间仍 < 41 拍），确认不会误判长按
        wait_cycles(10);
        if (hold !== 1'b0)
            $error("FAIL: hold asserted before HOLD_CNT");
        else
            $display("PASS: no hold before HOLD_CNT");

        bounce_key(1);                          // 释放（含抖动）
        wait_cycles(DEBOUNCE_CNT + 8);
        if (pulse_total !== 8'd1)
            $error("FAIL: extra pulse on release, pulse_total=%0d", pulse_total);
        else
            $display("PASS: no pulse on release");
        if (hold !== 1'b0)
            $error("FAIL: hold not cleared after release");
        else
            $display("PASS: hold cleared after release");

        // ---- 场景2：长按 ----
        key = 0;
        wait_cycles(DEBOUNCE_CNT + 8);          // 16 拍：捕获按下脉冲
        if (pulse_total !== 8'd2)
            $error("FAIL: after long press start pulse_total=%0d, expect 2", pulse_total);
        else
            $display("PASS: long press -> 1 pulse");

        wait_cycles(HOLD_CNT + 2);              // 16+32=48 拍，已超过约 41 拍阈值
        if (hold !== 1'b1)
            $error("FAIL: hold not asserted after HOLD_CNT");
        else
            $display("PASS: hold asserted after long press");

        wait_cycles(5);                         // 按住期间 hold 应保持
        if (hold !== 1'b1)
            $error("FAIL: hold dropped while key still down");

        key = 1;                                // 释放
        wait_cycles(DEBOUNCE_CNT + 8);
        if (hold !== 1'b0)
            $error("FAIL: hold not cleared after long-press release");
        else
            $display("PASS: hold cleared after long-press release");
        if (pulse_total !== 8'd2)
            $error("FAIL: extra pulse after long-press release");

        // ---- 场景3：复位清零 ----
        rst_n = 0;
        wait_cycles(5);
        if (pulse_total !== 8'd0 || hold !== 1'b0 || pulse !== 1'b0)
            $error("FAIL: reset does not clear outputs");
        else
            $display("PASS: reset clears outputs");
        rst_n = 1;

        if (pulse_total === 8'd0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
