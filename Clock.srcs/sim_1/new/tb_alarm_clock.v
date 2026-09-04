// tb_alarm_clock：验证 3 组闹钟设置/使能、到点提醒（5s）、解除、5s+10s 二次提醒流程。
// 时间由测试台驱动（当前时:分 + 秒使能），分钟跳变沿触发提醒。

`timescale 1ns / 1ps

module tb_alarm_clock;

    reg clk = 0;
    reg rst_n = 0;
    reg flag = 0;
    reg set_en = 0;
    reg [1:0] idx = 0;
    reg [1:0] fld = 0;
    reg inc = 0;
    reg dec = 0;
    reg [7:0] cur_h = 8'h00;
    reg [7:0] cur_m = 8'h00;
    reg ack = 0;

    wire [7:0] sel_h, sel_m;
    wire [2:0] en;
    wire ring;
    wire [1:0] ring_no;
    wire [1:0] st;

    alarm_clock u_alarm (
        .i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(flag), .i_set_en(set_en),
        .i_idx(idx), .i_fld(fld), .i_inc(inc), .i_dec(dec),
        .i_cur_hour(cur_h), .i_cur_min(cur_m), .i_ack(ack),
        .o_sel_hour(sel_h), .o_sel_min(sel_m), .o_en(en),
        .o_ring(ring), .o_ring_no(ring_no), .o_state(st)
    );

    always #5 clk = ~clk;
    integer fails = 0;

    task pulse(input integer n);
        integer c;
        begin
            @(negedge clk); flag = 1;
            for (c = 0; c < n; c = c + 1) @(posedge clk);
            @(negedge clk); flag = 0;
            @(negedge clk);
        end
    endtask

    // 设定当前时间并走 1 秒（产生一次分钟跳变沿检测）
    task go_to(input [7:0] h, m);
        begin
            @(negedge clk);
            cur_h = h; cur_m = m;
            pulse(1);
        end
    endtask

    task set_field(input [1:0] i, input [1:0] f, input up);
        begin
            @(negedge clk); set_en = 1; idx = i; fld = f;
            if (up) inc = 1; else dec = 1;
            @(negedge clk);
            inc = 0; dec = 0; set_en = 0; idx = 0; fld = 0;
        end
    endtask

    // 按下解除（与一次秒使能同拍）
    task press_ack;
        begin
            @(negedge clk); ack = 1; flag = 1;
            @(posedge clk);
            @(negedge clk); ack = 0; flag = 0;
            @(negedge clk);
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
        repeat (10) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(negedge clk);

        // ===== A: 闹钟 0 设置 08:00 并使能（默认即为 08:00）=====
        set_field(2'd0, 2'd2, 1);        // 使能开
        chk("A1", en[0] == 1'b1, "alarm0 enable on");
        chk("A2", sel_h == 8'h08 && sel_m == 8'h00, "alarm0 time 08:00");
        // 调整分 +1 -> 08:01 -> 再 -1 回 08:00
        set_field(2'd0, 2'd1, 1);
        chk("A3", sel_m == 8'h01, "alarm0 min inc to 01");
        set_field(2'd0, 2'd1, 0);
        chk("A4", sel_m == 8'h00, "alarm0 min dec back to 00");

        // 把"上一分钟"设定到 07:59，避免启动即误触发
        go_to(8'h07, 8'h59);
        chk("A5", ring == 1'b0, "no ring at 07:59");

        // ===== B: 到点 08:00 提醒，按解除立即停止 =====
        go_to(8'h08, 8'h00);
        chk("B1", ring == 1'b1, "ring at 08:00");
        chk("B2", ring_no == 2'd0, "ring alarm0");
        press_ack;
        chk("B3", ring == 1'b0, "ack dismisses ring");
        chk("B4", st == 2'd0, "state back to idle");

        // ===== C: 再次到点，不解除 -> 5s 响 -> 10s 静 -> 二次 5s 响 -> 自动结束 =====
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        chk("C1", ring == 1'b1, "ring again at 08:00");
        pulse(4);                       // 已响 5 拍（含开始）
        chk("C2", ring == 1'b1, "still ringing within 5s");
        pulse(1);                       // 第 5 秒结束 -> 静默
        chk("C3", ring == 1'b0, "ring stops after 5s");
        chk("C4", st == 2'd2, "entered snooze");
        pulse(9);
        chk("C5", ring == 1'b0, "snooze stays silent");
        pulse(1);                       // 10s 结束 -> 二次提醒
        chk("C6", ring == 1'b1, "second reminder rings");
        pulse(5);                       // 二次 5s 后自动结束
        chk("C7", ring == 1'b0, "auto end after second reminder");
        chk("C8", st == 2'd0, "state idle after cycle");

        // ===== D: 同一分钟不重复触发 =====
        pulse(3);                       // 仍在 08:00 分钟内
        chk("D1", ring == 1'b0, "no re-trigger same minute");

        // ===== E: 分钟后走开再回来，重新提醒 =====
        go_to(8'h08, 8'h01);
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        chk("E1", ring == 1'b1, "re-arm next minute cycle");
        press_ack;

        // ===== F: 关闭闹钟 0 不再提醒 =====
        set_field(2'd0, 2'd2, 0);       // 使能关
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        chk("F1", ring == 1'b0, "disabled alarm does not ring");

        // ===== G: 闹钟 2 默认 21:00，使能后到点提醒 =====
        set_field(2'd2, 2'd2, 1);
        go_to(8'h20, 8'h59);
        go_to(8'h21, 8'h00);
        chk("G1", ring == 1'b1 && ring_no == 2'd2, "alarm2 rings at 21:00");
        press_ack;

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
