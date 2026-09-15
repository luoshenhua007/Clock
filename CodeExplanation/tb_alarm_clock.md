# tb_alarm_clock.v 源码说明

## 1. 实现的功能
对 `alarm_clock` 的仿真测试：闹钟设置/使能、到点响铃、解除、5s+10s 二次提醒、同分钟不重复、关闭不响。

## 2. 模块
- `tb_alarm_clock`：Testbench，例化 `alarm_clock`（DUT）。

## 3. 接口/激励
- 手动驱动当前时:分与秒使能；用 `go_to` 制造分钟跳变；`press_ack`/`hold` 模拟解除。

## 4. 测试内容与对应需求
- 使能闹钟并把时间设到当前；到点 `ring=1`、编号正确。
- 解除后回 IDLE；不解除则 5s→停 10s→再 5s→自动结束。
- 同一分钟不重复触发；关闭闹钟不响。
- 对应需求：3 组闹钟、LED 提醒、解除、二次提醒。

## 关键代码详解

**（1）制造"分钟跳变沿"**
```verilog
task go_to(h,m); @(negedge clk); cur_h=h; cur_m=m; pulse(1); endtask
```
- 闹钟只在"时:分发生变化"的那一拍触发。所以先设 07:59 走一秒，再设 08:00 走一秒，就制造出"进入新一分钟"的沿。

**（2）脉冲推进秒**
```verilog
task pulse(n); @(negedge clk) flag=1; repeat(n)@(posedge clk); @(negedge clk) flag=0; endtask
```
- 每个正沿=1 秒；用 `pulse(5)` 走完响铃 5s，`pulse(10)` 走完静默 10s。

**（3）解除与断言**
```verilog
task press_ack; @(negedge clk) ack=1,flag=1; @(posedge clk); @(negedge clk) ack=0,flag=0; endtask
chk("C6", ring==1, "second reminder rings");
```
- 解除键与一次秒使能同拍给出，确保 DUT 在正沿采到 `ack`；随后断言 `ring` 状态验证流程。

## 说明（原"疑问"）
- 解除采用边沿即时响应（无需等秒节拍）。
- 本 tb 的 `chk()` 仅在失败时打印 `FAIL`，成功不打印，因此通过时只看到末尾 `ALL TESTS PASSED`。

## 待修改事项（统一处理）
- [已完成] 已随 `alarm_clock.v` 重写：验证匹配即触发、SNOOZE 可解除、多组同时响铃、二次提醒时序；回归通过。
- [已完成] 已增加关键状态打印方式：失败打印 `FAIL`、成功末尾 `ALL TESTS PASSED`。
