// tb_part4：编辑态 SW4 锁存 + 闹钟/倒计时编辑。
// 覆盖：TD 编辑中拨 SW4 不影响（保持 TD 编辑）；退出后按 SW4 组显示；
// 闹钟编辑(时/分)；倒计时编辑(时/分/秒)。

`timescale 1ns / 1ps

module tb_part4;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    reg sw_group = 1;
    reg sw_edit = 1;
    wire [7:0] seg, sel;
    wire [3:0] led;

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
            if (!cond) begin fails = fails + 1; $display("FAIL[%0d]: %0s", t, msg); end
        end
    endtask

    initial begin
        cyc(10);
        @(negedge clk); rst_n = 1;
        cyc(20);

        chk("A1", u_dut.td_disp == 1'b1, "td display (both down)");

        // 进入 TD 编辑
        @(negedge clk); sw_edit = 0;
        cyc(20);
        chk("A2", u_dut.td_edit == 1'b1, "td edit");

        // 编辑中拨 SW4 到 AC 档：应仍为 TD 编辑（锁存）
        @(negedge clk); sw_group = 0;
        cyc(20);
        chk("A3", u_dut.td_edit == 1'b1, "SW4 ignored while editing (still td_edit)");
        chk("A4", u_dut.ac_edit == 1'b0, "not ac_edit during td edit");

        // 退出编辑（SW3 回显示）：此时按 SW4 档（AC 组）显示
        @(negedge clk); sw_edit = 1;
        cyc(20);
        chk("A5", u_dut.ac_disp == 1'b1, "after exit follows SW4=AC display");
        chk("A6", u_dut.ac_sel == 1'b0, "shows alarm1");

        // 闹钟编辑：时/分
        @(negedge clk); sw_edit = 0;
        cyc(20);
        chk("B1", u_dut.ac_edit == 1'b1, "ac edit");
        chk("B2", u_dut.alm_edit == 1'b1, "alarm edit active");
        chk("B3", u_dut.rtc_set_en == 1'b0, "alarm edit does not stop clock");
        chk("B4", u_dut.alm_fld == 2'd0, "cursor hour");
        tap(1);                                  // 时 +1
        chk("B5", u_dut.alm_h == 8'h09, "alarm hour inc 08->09");
        tap(0);                                  // -> 分
        chk("B6", u_dut.alm_fld == 2'd1, "cursor minute");
        tap(2);                                  // 分 -1 -> 59
        chk("B7", u_dut.alm_m == 8'h59, "alarm min dec wrap");

        // 切倒计时编辑：先退显示再选倒计时
        @(negedge clk); sw_edit = 1;
        cyc(20);
        tap(1);                                  // KEY2 -> countdown view
        @(negedge clk); sw_edit = 0;
        cyc(20);
        chk("C1", u_dut.ac_edit == 1'b1 && u_dut.ac_sel == 1'b1, "countdown edit");
        chk("C2", u_dut.cnt_set == 1'b1, "countdown config mode");
        chk("C3", u_dut.cnt_field == 2'd0, "cursor hour");
        tap(1);                                  // 时 +1
        chk("C4", u_dut.ch == 8'h01, "countdown hour inc");
        tap(0);                                  // -> 分
        tap(0);                                  // -> 秒
        chk("C5", u_dut.cnt_field == 2'd2, "cursor second");
        tap(2);                                  // 秒 -1 -> 59
        chk("C6", u_dut.cs == 8'h59, "countdown sec dec wrap");

        // 退出编辑应回到倒计时视图（不是无脑闹钟1）
        @(negedge clk); sw_edit = 1;
        cyc(20);
        chk("D1", u_dut.ac_disp == 1'b1 && u_dut.ac_sel == 1'b1, "exit returns countdown view");
        tap(0);                                  // KEY1：倒计时视图下应回闹钟1
        chk("D2", u_dut.ac_sel == 1'b0 && u_dut.alarm_idx == 2'd0, "KEY1 -> alarm1");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
