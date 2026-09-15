# tb_part1.v 源码说明

## 1. 实现的功能
集成测试之一：验证【时间/日期 · 显示】模式——时间/日期切换、12/24h 切换、年月日/星期切换、星期计算。

## 2. 模块
- `tb_part1`：Testbench，例化顶层 `top_digital_clock`（DUT），两开关默认置为"时间/日期·显示"。

## 3. 接口/激励
- 小参数 `CLK_FREQ=1000`、`DB_CNT=8`、`HOLD_CNT=30`；`tap` 模拟按键。
- 用 `force/release` 直接设置 RTC 内部寄存器到 13:34:56 便于校验换算。

## 4. 测试内容与对应需求
- 默认时间页、24h 数字；KEY1 切到日期；日期 2026-01-01 星期应为 4（周四）。
- KEY2 在日期页切到"星期"视图；回到时间页 KEY2 切 12h，校验 13h→显示 01 且 PM。
- 对应需求：时间/日期显示、12/24h、星期显示。

## 关键代码详解

**（1）按键任务**
```verilog
task tap(k); @(negedge clk) key = key & ~(1<<k);
    cyc(DB_CNT+10); @(negedge clk) key = 6'b111111; cyc(DB_CNT+10); endtask
```
- 在负沿把某位按键拉低（按下），等够消抖时间，再在负沿释放。这样 DUT 能稳定地产生一次脉冲。

**（2）白盒置值**
```verilog
force u_dut.u_rtc.h_t_r = 4'h1; ...   // 直接改 RTC 内部寄存器
release u_dut.u_rtc.h_t_r; ...
```
- 为了快速构造 13:34:56 这种时间，直接 `force` 内部 BCD 寄存器（层次引用），省去快进几万秒；验证换算逻辑后 `release` 恢复。

**（3）层次断言**
```verilog
chk("B2", u_dut.week_day == 4'd4, "2026-01-01 is Thursday(4)");
```
- 直接读 DUT 内部信号（`view_time/fmt_12/week_day` 等）做判断，属白盒测试。

## 疑问
- 依赖 `force` 内部寄存器，属白盒测试。

## 待修改事项（统一处理）
- 集成用例，保留；已随 i_key 位宽改为 [3:0] 同步，无需其他修改。
