// tb_alarm_clock：验证 3 组独立闹钟：匹配即触发、5s/10s 二次提醒、
// SNOOZE 可解除、多组同时刻可同时响铃。

`timescale 1ns / 1ps

module tb_alarm_clock;

    reg clk = 0, rst_n = 0, flag = 0, set_en = 0, ack = 0;
    reg [1:0] idx = 0, fld = 0;
    reg inc = 0, dec = 0;
    reg [7:0] cur_h = 0, cur_m = 0;
    wire [7:0] sel_h, sel_m;
    wire [2:0] en, ring;

    alarm_clock u_alarm (
        .i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(flag), .i_set_en(set_en),
        .i_idx(idx), .i_fld(fld), .i_inc(inc), .i_dec(dec),
        .i_cur_hour(cur_h), .i_cur_min(cur_m), .i_ack(ack),
        .o_sel_hour(sel_h), .o_sel_min(sel_m), .o_en(en), .o_ring(ring));

    always #5 clk = ~clk;
    integer fails = 0;

    task cyc(input integer n); integer c; begin for (c=0;c<n;c=c+1) @(posedge clk); end endtask

    task pulse(input integer n);
        integer c;
        begin
            @(negedge clk); flag = 1;
            for (c=0;c<n;c=c+1) @(posedge clk);
            @(negedge clk); flag = 0; @(negedge clk);
        end
    endtask

    task go_to(input [7:0] h, m);
        begin @(negedge clk); cur_h=h; cur_m=m; pulse(1); end
    endtask

    task setf(input [1:0] i, input [1:0] f, input up);
        begin
            @(negedge clk); set_en=1; idx=i; fld=f; if(up) inc=1; else dec=1;
            @(negedge clk); inc=0; dec=0; set_en=0; idx=0; fld=0;
        end
    endtask

    task press_ack;
        begin @(negedge clk); ack=1; @(negedge clk); ack=0; @(negedge clk); end
    endtask

    task chk(input [7:0] t, input cond, input [8*64:0] msg);
        begin if(!cond) begin fails=fails+1; $display("FAIL[%0d]: %0s", t, msg); end end
    endtask

    initial begin
        cyc(10); @(negedge clk); rst_n = 1; cyc(10);

        // 启用闹钟0（默认 08:00）
        setf(2'd0, 2'd2, 1);
        chk("A1", en[0]==1'b1, "alarm0 enabled");

        // 到点前不响；到点立即响（匹配即触发）
        go_to(8'h07, 8'h59);
        chk("A2", ring==3'b000, "no ring before time");
        // 只把时间设到 08:00、不给秒使能，也应立即响（证明不依赖秒节拍）
        @(negedge clk); cur_h = 8'h08; cur_m = 8'h00; cyc(4);
        chk("A3", ring[0]==1'b1, "ring immediately at 08:00 (no flag)");

        // 解除
        press_ack;
        chk("A4", ring[0]==1'b0, "ack dismisses");

        // 不解除：响5s -> 静默10s -> 再响5s -> 自动结束
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        chk("B1", ring[0]==1'b1, "ring again");
        pulse(5);
        chk("B2", ring[0]==1'b0, "silent after 5s");
        pulse(10);
        chk("B3", ring[0]==1'b1, "second reminder");
        pulse(5);
        chk("B4", ring[0]==1'b0, "auto end");

        // SNOOZE 期间按解除 -> 不再二次提醒
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        pulse(5);                       // 进入 snooze
        chk("C1", ring[0]==1'b0, "in snooze");
        press_ack;                      // 静默期解除
        pulse(10);
        chk("C2", ring[0]==1'b0, "ack in snooze cancels 2nd reminder");

        // 多组同时刻：启用闹钟1并把分钟 30->00（小时仍 08），两组应同时响
        repeat (30) setf(2'd1, 2'd1, 0);
        setf(2'd1, 2'd2, 1);            // 使能闹钟1
        go_to(8'h07, 8'h59);
        go_to(8'h08, 8'h00);
        chk("D1", ring[0]==1'b1 && ring[1]==1'b1, "two alarms ring simultaneously");
        press_ack;
        chk("D2", ring==3'b000, "ack clears all");

        if (fails==0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
