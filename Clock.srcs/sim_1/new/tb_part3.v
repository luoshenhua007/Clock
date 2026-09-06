// tb_part3：闹钟/倒计时·显示页。
// SW4低(上)+SW3高(下)=ac_disp。KEY1 切闹钟1/2/3；KEY3 启停用闹钟；
// KEY2 显示倒计时；KEY3 启/停倒计时；默认 00:01:00。

`timescale 1ns / 1ps

module tb_part3;

    localparam CLK_PERIOD = 10;
    localparam CLK_FREQ   = 1000;
    localparam DB_CNT     = 8;
    localparam HOLD_CNT   = 30;

    reg clk = 0;
    reg rst_n = 0;
    reg [5:0] key = 6'b111111;
    reg sw_group = 0;      // ac 组
    reg sw_edit = 1;       // 显示
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

        chk("A1", u_dut.ac_disp == 1'b1, "ac display mode");
        chk("A2", u_dut.ac_sel == 1'b0 && u_dut.alarm_idx == 2'd0, "alarm1 view");
        chk("A3", u_dut.alm_en[0] == 1'b0, "alarm1 default off");

        // KEY3 启用闹钟1
        tap(2);
        chk("A4", u_dut.alm_en[0] == 1'b1, "alarm1 enabled");
        tap(2);
        chk("A5", u_dut.alm_en[0] == 1'b0, "alarm1 disabled again");

        // KEY1 -> 闹钟2
        tap(0);
        chk("B1", u_dut.alarm_idx == 2'd1, "alarm2 view");

        // KEY2 -> 倒计时视图（默认 00:01:00）
        tap(1);
        chk("C1", u_dut.ac_sel == 1'b1, "countdown view");
        chk("C2", u_dut.ch == 8'h00 && u_dut.cm == 8'h01 && u_dut.cs == 8'h00,
            "countdown init 00:01:00");

        // KEY3 启动；快进 ~1.2s 应减少 1 秒
        tap(2);
        chk("C3", u_dut.cd_run == 1'b1, "countdown running");
        cyc(CLK_FREQ);
        chk("C4", u_dut.cm == 8'h00 && u_dut.cs == 8'h59, "counted down 1s");

        // KEY3 暂停
        tap(2);
        chk("D1", u_dut.cd_run == 1'b0, "countdown paused");
        cyc(CLK_FREQ);
        chk("D2", u_dut.cm == 8'h00 && u_dut.cs == 8'h59, "paused frozen");

        if (fails == 0) $display("ALL TESTS PASSED");
        else $display("%0d TEST(S) FAILED", fails);
        $finish;
    end

endmodule
