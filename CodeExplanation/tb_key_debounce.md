# tb_key_debounce.v 源码说明

## 1. 实现的功能
对 `key_debounce_one` 的仿真测试：覆盖短按（含抖动）、释放、长按、复位。

## 2. 模块
- `tb_key_debounce`：Testbench，例化 `key_debounce_one`（DUT）。

## 3. 接口/激励
- 小参数：`DEBOUNCE_CNT=8`、`HOLD_CNT=30`、低有效。
- 用 `bounce_key` 模拟抖动；用负沿计数监测器统计脉冲。

## 4. 测试内容与对应需求
- 短按（含抖动）只产生 1 个单拍脉冲、未超阈值时 hold=0。
- 释放不产生额外脉冲、hold 清零。
- 长按超过阈值 hold 拉高，按住保持，释放恢复。
- 复位清零输出。
- 对应需求：按键可靠输入、长按连加/复位基础。

## 关键代码详解

**（1）边沿安全的激励/采样**
```verilog
task wait_cycles(n); for(...) @(posedge clk); #(CLK_PERIOD/4); endtask
```
- 每个任务在"正沿后 1/4 周期"返回，远离正/负沿，避免驱动与采样时与 DUT 更新抢同一时刻。

**（2）脉冲计数用负沿**
```verilog
always @(negedge clk or negedge rst_n)
    if (!rst_n) pulse_total <= 0; else if (pulse) pulse_total <= pulse_total+1;
```
- `o_pulse` 在正沿产生；若也在正沿读会读到旧值。负沿读时脉冲值已稳定，能可靠计数。单拍脉冲 → 每按一次加 1，可同时验证"只有一个脉冲"。

**（3）为什么等待要留余量**
```verilog
wait_cycles(DEBOUNCE_CNT + 8);
```
- 按键变化到脉冲出现要经过：同步 2 拍 + 变化沿检测 1 拍 + 消抖 8 拍 + 脉冲寄存器 1 拍 + 监测器再 1 拍。等待必须大于这个总和，否则会误判"没脉冲"。这也是调这个 tb 时的经验。

## 说明（原"疑问"）
- 采样避开边沿、给脉冲/长按留足周期余量，避免仿真竞争误判。

## 待修改事项（统一处理）
- 仿真逻辑已确认，无问题；本文件暂无待修改项。
