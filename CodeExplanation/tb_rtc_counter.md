# tb_rtc_counter.v 源码说明

## 1. 实现的功能
对 `rtc_counter` 的仿真测试：时间/日期进位、月末/年末、平闰年与大小月、字段增减与日收缩。

## 2. 模块
- `tb_rtc_counter`：Testbench，例化多个不同初值的 `rtc_counter`（各自独立 flag）。

## 3. 接口/激励
- 每个 DUT 用独立 `flag_1s`，避免场景间相互推进；用 `run_seconds` 快进；`adj_up/adj_dn` 做字段调整。

## 4. 测试内容与对应需求
- A：23:59:58 +2s → 00:00:00 且 1/31 进到 2/1。
- B：2026 平年 2/28 +2s → 3/1。
- C：2024 闰年 2/28 → 2/29 →（满一天）3/1。
- D：2000 闰年 2/28 → 2/29 → 3/1。
- E：2100 非闰世纪 2/28 → 3/1。
- F：字段增减（时/分回绕、月/年回绕、日收缩 31→30、闰年 2/29→平年 2/28）。
- 对应需求：时间计数、日期闰年/大小月、时间/日期设置。

## 关键代码详解

**（1）每个 DUT 独立节拍**
```verilog
rtc_counter u_midnight(... .i_flag_1s(f_mid) ...);
rtc_counter u_feb26 (... .i_flag_1s(f_feb) ...);
run_seconds(1, 2);  // 只推进 u_midnight
```
- 早期版本让所有 DUT 共用一根 flag，前面的用例会顺带推进后面的 DUT，导致期望值全错。改为**每个场景独立 flag**，只在测该场景时推进它。

**（2）快进函数**
```verilog
task run_seconds(sel, n);
    @(negedge clk); 按 sel 把对应 flag 拉高;
    repeat(n) @(posedge clk);   // n 个正沿 = n 秒
    @(negedge clk); flag=0;
endtask
```
- 用"拉高 flag 跨 n 个正沿"模拟 n 秒，比真实等 50M 拍快得多；日期跨天用 `n=86400` 快进一天。

**（3）字段调整与断言**
```verilog
task adj_up(f); @(negedge clk) set_en=1,inc=1; @(negedge clk) 撤销; endtask
chk_date("A2", 2026,02,01, yr, mo, da);   // 断言日期
```
- 在负沿给激励、下一个负沿撤销，保证 DUT 在中间的正沿看到稳定的单拍信号；断言直接比较输出与期望。

## 说明（原"疑问"）
- 日期快进用 86400 秒脉冲，仿真时间较长但可接受。
- 断言通过打印 `PASS`、失败打印 `FAIL`；全部通过时输出 `ALL TESTS PASSED`。

## 待修改事项（统一处理）
- [已完成] 中文 `$display` 消息已改为英文。
- 本文件仿真逻辑无功能问题。
