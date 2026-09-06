`timescale 1ns / 1ps

// countdown：倒计时（HH:MM:SS，上限 23:59:59）。
// 配置初值(h/m/s)与工作计数分离；i_set_en 设置模式（编辑字段 h/m/s），
// i_run 短按=启/停，i_reset=复位到初值；到 00:00:00 置 done 并停表。

module countdown #(
    parameter [7:0] INIT_H = 8'h00,
    parameter [7:0] INIT_M = 8'h01,
    parameter [7:0] INIT_S = 8'h00
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_flag_1s,
    input  wire       i_set_en,
    input  wire [1:0] i_field,      // 0=时 1=分 2=秒
    input  wire       i_inc,
    input  wire       i_dec,
    input  wire       i_run,
    input  wire       i_reset,
    output wire [7:0] o_h,
    output wire [7:0] o_m,
    output wire [7:0] o_s,
    output wire       o_done,
    output wire       o_running
);

    reg [7:0] ch_r, cm_r, cs_r;      // 配置
    reg [7:0] wh_r, wm_r, ws_r;      // 工作计数
    reg       run_r, done_r;

    function automatic [7:0] bcd2_inc(input [3:0] hi, input [3:0] lo);
        begin bcd2_inc = (lo == 4'h9) ? {hi + 4'h1, 4'h0} : {hi, lo + 4'h1}; end
    endfunction
    function automatic [7:0] bcd2_dec(input [3:0] hi, input [3:0] lo);
        begin bcd2_dec = (lo == 4'h0) ? {hi - 4'h1, 4'h9} : {hi, lo - 4'h1}; end
    endfunction

    wire zero_w = (wh_r == 8'h00) && (wm_r == 8'h00) && (ws_r == 8'h00);

    // 配置字段调整（小时 0..23，分/秒 0..59）
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            ch_r <= INIT_H; cm_r <= INIT_M; cs_r <= INIT_S;
            wh_r <= INIT_H; wm_r <= INIT_M; ws_r <= INIT_S;
            run_r <= 0; done_r <= 0;
        end else if (i_set_en) begin
            run_r <= 0; done_r <= 0;
            wh_r <= ch_r; wm_r <= cm_r; ws_r <= cs_r;
            if (i_field == 2'd0) begin
                if (i_inc) ch_r <= (ch_r == 8'h23) ? 8'h00 : bcd2_inc(ch_r[7:4], ch_r[3:0]);
                else if (i_dec) ch_r <= (ch_r == 8'h00) ? 8'h23 : bcd2_dec(ch_r[7:4], ch_r[3:0]);
            end else if (i_field == 2'd1) begin
                if (i_inc) cm_r <= (cm_r == 8'h59) ? 8'h00 : bcd2_inc(cm_r[7:4], cm_r[3:0]);
                else if (i_dec) cm_r <= (cm_r == 8'h00) ? 8'h59 : bcd2_dec(cm_r[7:4], cm_r[3:0]);
            end else begin
                if (i_inc) cs_r <= (cs_r == 8'h59) ? 8'h00 : bcd2_inc(cs_r[7:4], cs_r[3:0]);
                else if (i_dec) cs_r <= (cs_r == 8'h00) ? 8'h59 : bcd2_dec(cs_r[7:4], cs_r[3:0]);
            end
        end else begin
            if (i_reset) begin
                run_r <= 0; done_r <= 0;
                wh_r <= ch_r; wm_r <= cm_r; ws_r <= cs_r;
            end else if (i_run) begin
                if (done_r || zero_w) begin
                    run_r <= 1; done_r <= 0;
                    wh_r <= ch_r; wm_r <= cm_r; ws_r <= cs_r;
                end else
                    run_r <= ~run_r;
            end

            if (run_r && i_flag_1s) begin
                if (zero_w) begin
                    run_r <= 0; done_r <= 1;
                    // 显示还原为默认初值（不再停在 00.00.00）
                    wh_r <= ch_r; wm_r <= cm_r; ws_r <= cs_r;
                end else if (ws_r == 8'h00) begin
                    ws_r <= 8'h59;
                    if (wm_r == 8'h00) begin
                        wm_r <= 8'h59;
                        wh_r <= (wh_r == 8'h00) ? 8'h00 : bcd2_dec(wh_r[7:4], wh_r[3:0]);
                    end else
                        wm_r <= bcd2_dec(wm_r[7:4], wm_r[3:0]);
                end else
                    ws_r <= bcd2_dec(ws_r[7:4], ws_r[3:0]);   // BCD 自减（xx.x0 -> xx.09）
            end
        end
    end

    assign o_h = wh_r; assign o_m = wm_r; assign o_s = ws_r;
    assign o_done = done_r; assign o_running = run_r;

endmodule
