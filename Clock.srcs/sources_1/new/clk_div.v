`timescale 1ns / 1ps

// clk_div：分频模块，由全局时钟计数产生 1Hz/500Hz/2Hz 单拍使能脉冲（非时钟脚）。
// 参数 CLK_FREQ 可配置主频，便于移植与仿真加速。

module clk_div #(
    parameter CLK_FREQ  = 50_000_000,
    parameter CNT_WIDTH = 32
)(
    input  wire             i_clk,
    input  wire             i_rst_n,
    output reg              o_flag_1s,
    output reg              o_flag_500hz,
    output reg              o_flag_2hz
);

    // 计数阈值（到达后回零并产生一拍脉冲）
    localparam CNT_1S    = CLK_FREQ - 1;
    localparam CNT_500HZ = CLK_FREQ / 500 - 1;
    localparam CNT_2HZ   = CLK_FREQ / 2 - 1;

    reg [CNT_WIDTH-1:0] cnt_1s_r;
    reg [CNT_WIDTH-1:0] cnt_500hz_r;
    reg [CNT_WIDTH-1:0] cnt_2hz_r;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cnt_1s_r    <= {CNT_WIDTH{1'b0}};
            cnt_500hz_r <= {CNT_WIDTH{1'b0}};
            cnt_2hz_r   <= {CNT_WIDTH{1'b0}};
            o_flag_1s   <= 1'b0;
            o_flag_500hz<= 1'b0;
            o_flag_2hz  <= 1'b0;
        end else begin
            // 1Hz 使能脉冲
            if (cnt_1s_r >= CNT_1S) begin
                cnt_1s_r  <= {CNT_WIDTH{1'b0}};
                o_flag_1s <= 1'b1;
            end else begin
                cnt_1s_r  <= cnt_1s_r + 1'b1;
                o_flag_1s <= 1'b0;
            end

            // 500Hz 使能脉冲
            if (cnt_500hz_r >= CNT_500HZ) begin
                cnt_500hz_r <= {CNT_WIDTH{1'b0}};
                o_flag_500hz<= 1'b1;
            end else begin
                cnt_500hz_r <= cnt_500hz_r + 1'b1;
                o_flag_500hz<= 1'b0;
            end

            // 2Hz 使能脉冲
            if (cnt_2hz_r >= CNT_2HZ) begin
                cnt_2hz_r <= {CNT_WIDTH{1'b0}};
                o_flag_2hz<= 1'b1;
            end else begin
                cnt_2hz_r <= cnt_2hz_r + 1'b1;
                o_flag_2hz<= 1'b0;
            end
        end
    end

endmodule
