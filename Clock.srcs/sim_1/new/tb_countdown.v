// tb_countdown：验证设定、计数递减/借位、暂停/继续、结束、复位、重新开始。
// 初值参数为 00:00，测试中显式设定所需初值。

`timescale 1ns / 1ps

module tb_countdown;

    reg clk = 0;
    reg rst_n = 0;
    reg flag = 0;
    reg set_en = 0;
    reg fld = 0;
    reg inc = 0;
    reg dec = 0;
    reg run = 0;
    reg reset = 0;

    wire [7:0] min, sec;
    wire done, running;

    countdown #(.INIT_MIN(8'h00), .INIT_SEC(8'h00)) u_cnt (
        .i_clk(clk), .i_rst_n(rst_n), .i_flag_1s(flag), .i_set_en(set_en),
        .i_fld(fld), .i_inc(inc), .i_dec(dec),
        .i_run(run), .i_reset(reset),
        .o_min(min), .o_sec(sec), .o_done(done), .o_running(running)
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

    task press_run;
        begin
            @(negedge clk); run = 1;
            @(negedge clk); run = 0;
        end
    endtask

    task press_reset;
        begin
            @(negedge clk); reset = 1;
            @(negedge clk); reset = 0;
        end
    endtask

    // 设定字段 +1/-1（退出设置后 cnt 同步为 cfg）
    task adj(input [1:0] f, input up);
        begin
            @(negedge clk); set_en = 1; fld = f;
            if (up) inc = 1; else dec = 1;
            @(negedge clk); inc = 0; dec = 0; set_en = 0;
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

        // ===== A: 设定初值 00:05 =====
        adj(1'b0, 1);                  // 分 00 -> 01
        adj(1'b0, 0);                  // 分 01 -> 00
        repeat (5) adj(1'b1, 1);       // 秒 +5
        chk("A1", min == 8'h00 && sec == 8'h05, "cfg 00:05");

        // ===== B: 开始递减 =====
        press_run;
        chk("B1", running == 1'b1, "start");
        pulse(1);
        chk("B2", min == 8'h00 && sec == 8'h04, "00:04 after 1s");

        // ===== C: 暂停 -> 冻结；继续 -> 恢复 =====
        press_run;
        chk("C1", running == 1'b0, "paused");
        pulse(3);
        chk("C2", min == 8'h00 && sec == 8'h04, "frozen while paused");
        press_run;
        pulse(2);
        chk("C3", min == 8'h00 && sec == 8'h02, "resumed to 00:02");

        // ===== D: 到 00:00 完成 =====
        pulse(2);
        chk("D1", done == 1'b1 && running == 1'b0, "done & stopped at 0");
        pulse(5);
        chk("D2", min == 8'h00 && sec == 8'h00 && done == 1'b1, "stays 00:00 done");

        // ===== E: 完成后按开始 -> 重新载入初值并开始 =====
        press_run;
        chk("E1", running == 1'b1 && done == 1'b0, "restart");
        chk("E2", min == 8'h00 && sec == 8'h05, "reloaded 00:05");
        pulse(6);
        chk("E3", done == 1'b1, "finished again");

        // ===== F: 复位到初值 =====
        press_reset;
        chk("F1", min == 8'h00 && sec == 8'h05, "reset reload cfg");
        chk("F2", done == 1'b0 && running == 1'b0, "reset stops & clears done");

        // ===== G: 借位 01:00 -> 00:59 =====
        adj(1'b0, 1);                  // 分 00 -> 01
        repeat (5) adj(1'b1, 0);       // 秒 05 减回 00
        chk("G0", min == 8'h01 && sec == 8'h00, "cfg 01:00");
        press_run;
        pulse(1);
        chk("G1", min == 8'h00 && sec == 8'h59, "borrow 01:00 -> 00:59");
        press_run;                     // 暂停
        pulse(60);
        chk("G2", min == 8'h00 && sec == 8'h59, "paused borrow case frozen");

        // ===== H: 分钟 99 <-> 00 回绕 =====
        adj(1'b0, 0);                  // 分 00 -> 99（经 01->00->99 需两次）
        adj(1'b0, 0);
        chk("H1", min == 8'h99, "min dec wrap to 99");
        adj(1'b0, 1);                  // 分 99 -> 00
        chk("H2", min == 8'h00, "min inc wrap to 00");
        // 秒多次 +1 必经过 59->00 回绕且无越界
        repeat (70) adj(1'b1, 1);
        chk("H3", sec >= 8'h00 && sec <= 8'h59, "sec stayed in range");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
