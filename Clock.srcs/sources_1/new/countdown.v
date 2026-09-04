`timescale 1ns / 1ps

// countdown：倒计时模块。可在设置界面设定起始时间（分:秒，BCD），
// 运行后每秒递减至 00:00 并置完成标志。支持开始/暂停切换与复位重载。
// 字段调整：i_fld 0=分 1=秒（0~99 / 0~59）。

module countdown #(
    parameter [7:0] INIT_MIN = 8'h01,
    parameter [7:0] INIT_SEC = 8'h00
)(
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_flag_1s,    // 秒使能
    input  wire       i_set_en,     // 设置模式：同步初值并允许调整
    input  wire       i_fld,        // 0=分 1=秒
    input  wire       i_inc,
    input  wire       i_dec,
    input  wire       i_run,        // 开始/暂停切换（单拍）
    input  wire       i_reset,      // 复位到设定初值并停止（单拍）
    output wire [7:0] o_min,        // 当前倒计时 BCD
    output wire [7:0] o_sec,
    output wire       o_done,       // 已到 00:00
    output wire       o_running     // 运行中
);

    reg [7:0] cfg_min_r;   // 设定初值
    reg [7:0] cfg_sec_r;
    reg [7:0] cnt_min_r;   // 工作计数
    reg [7:0] cnt_sec_r;
    reg       run_r;
    reg       done_r;
    reg       set_d1_r;    // i_set_en 打拍，用于退出设置时同步初值

    wire cnt_zero_w = (cnt_min_r == 8'h00) && (cnt_sec_r == 8'h00);

    function automatic [7:0] bcd2_inc(input [3:0] hi, input [3:0] lo);
        begin bcd2_inc = (lo == 4'h9) ? {hi + 4'h1, 4'h0} : {hi, lo + 4'h1}; end
    endfunction
    function automatic [7:0] bcd2_dec(input [3:0] hi, input [3:0] lo);
        begin bcd2_dec = (lo == 4'h0) ? {hi - 4'h1, 4'h9} : {hi, lo - 4'h1}; end
    endfunction

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cfg_min_r <= INIT_MIN;
            cfg_sec_r <= INIT_SEC;
            cnt_min_r <= INIT_MIN;
            cnt_sec_r <= INIT_SEC;
            run_r     <= 1'b0;
            done_r    <= 1'b0;
            set_d1_r  <= 1'b0;
        end else begin
            set_d1_r <= i_set_en;

            if (i_set_en) begin
                // 设置模式：不运行，工作计数随时与初值同步
                run_r  <= 1'b0;
                done_r <= 1'b0;
                cnt_min_r <= cfg_min_r;
                cnt_sec_r <= cfg_sec_r;
                if (i_fld == 1'b0) begin
                    if (i_inc) cfg_min_r <= (cfg_min_r == 8'h99) ? 8'h00
                                       : bcd2_inc(cfg_min_r[7:4], cfg_min_r[3:0]);
                    else if (i_dec) cfg_min_r <= (cfg_min_r == 8'h00) ? 8'h99
                                       : bcd2_dec(cfg_min_r[7:4], cfg_min_r[3:0]);
                end else begin
                    if (i_inc) cfg_sec_r <= (cfg_sec_r == 8'h59) ? 8'h00
                                       : bcd2_inc(cfg_sec_r[7:4], cfg_sec_r[3:0]);
                    else if (i_dec) cfg_sec_r <= (cfg_sec_r == 8'h00) ? 8'h59
                                       : bcd2_dec(cfg_sec_r[7:4], cfg_sec_r[3:0]);
                end
            end else begin
                // 退出设置模式（下降沿）：把初值载入工作计数
                if (set_d1_r) begin
                    cnt_min_r <= cfg_min_r;
                    cnt_sec_r <= cfg_sec_r;
                    run_r <= 1'b0;
                    done_r <= 1'b0;
                end

                // 控制输入（优先复位）
                if (i_reset) begin
                    run_r     <= 1'b0;
                    done_r    <= 1'b0;
                    cnt_min_r <= cfg_min_r;
                    cnt_sec_r <= cfg_sec_r;
                end else if (i_run) begin
                    if (done_r || cnt_zero_w) begin      // 结束/未开始 -> 重新开始
                        run_r     <= 1'b1;
                        done_r    <= 1'b0;
                        cnt_min_r <= cfg_min_r;
                        cnt_sec_r <= cfg_sec_r;
                    end else begin                        // 暂停/继续切换
                        run_r <= ~run_r;
                    end
                end

                // 每秒递减
                if (run_r && i_flag_1s) begin
                    if (cnt_zero_w) begin                 // 已是 00:00
                        run_r  <= 1'b0;
                        done_r <= 1'b1;
                    end else if (cnt_min_r == 8'h00 && cnt_sec_r == 8'h01) begin
                        cnt_sec_r <= 8'h00;               // 00:01 -> 00:00 立即完成
                        run_r     <= 1'b0;
                        done_r    <= 1'b1;
                    end else if (cnt_sec_r == 8'h00) begin   // 借位
                        cnt_sec_r <= 8'h59;
                        if (cnt_min_r != 8'h00)
                            cnt_min_r <= bcd2_dec(cnt_min_r[7:4], cnt_min_r[3:0]);
                    end else begin
                        cnt_sec_r <= cnt_sec_r - 8'h01;
                    end
                end
            end
        end
    end

    assign o_min     = cnt_min_r;
    assign o_sec     = cnt_sec_r;
    assign o_done    = done_r;
    assign o_running = run_r;

endmodule
