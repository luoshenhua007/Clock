`timescale 1ns / 1ps

// fsm_controller：时间/日期两页显示 + 编辑子状态。
//   KEY0(MODE)：退出编辑并切换 时间<->日期 显示页。
//   KEY1(SEL) ：显示页按一次进入该页编辑；编辑中按一次推进字段（0..2 循环）。
// 编辑字段：时间页 0=时 1=分 2=秒；日期页 0=年 1=月 2=日。

module fsm_controller (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire [5:0] i_key_pulse,
    output reg        o_view,        // 0=时间显示 1=日期显示
    output reg        o_edit,        // 处于编辑状态
    output reg  [1:0] o_cursor
);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_view   <= 1'b0;
            o_edit   <= 1'b0;
            o_cursor <= 2'd0;
        end else if (i_key_pulse[0]) begin
            // MODE：退出编辑并切换页面
            o_view   <= ~o_view;
            o_edit   <= 1'b0;
            o_cursor <= 2'd0;
        end else if (i_key_pulse[1]) begin
            if (o_edit)
                o_cursor <= (o_cursor == 2'd2) ? 2'd0 : o_cursor + 2'd1;
            else begin
                o_edit   <= 1'b1;
                o_cursor <= 2'd0;
            end
        end
    end

endmodule
