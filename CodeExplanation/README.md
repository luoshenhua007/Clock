# CodeExplanation 索引

本目录为源码导读：每个 `.v` 对应一个同名 `.md`，说明其功能、模块、接口及代码与需求的对应关系。**不参与验收**，仅供了解源码。

## RTL 源码（`Clock.srcs/sources_1/new/`）

| 文件 | 说明文档 | 作用 | 状态 |
| :-- | :-- | :-- | :-- |
| `top_digital_clock_board.v` | `top_digital_clock_board.md` | 板上顶层：上电复位 + 引脚接入（XDC 对象） | 最终使用 |
| `top_digital_clock.v` | `top_digital_clock.md` | 设计顶层：模式译码、状态、显示、LED | 最终使用 |
| `clk_div.v` | `clk_div.md` | 分频出 1Hz/2Hz 等节拍 | 最终使用 |
| `key_debounce.v` | `key_debounce.md` | 按键消抖 + 短按脉冲 + 长按 | 最终使用 |
| `rtc_counter.v` | `rtc_counter.md` | 实时时钟/日期（闰年、大小月、字段编辑） | 最终使用 |
| `alarm_clock.v` | `alarm_clock.md` | 3 组**独立**闹钟 + 二次提醒 FSM | 最终使用 |
| `countdown.v` | `countdown.md` | 倒计时 HH:MM:SS（启停/复位/完成） | 最终使用 |

## 仿真（`Clock.srcs/sim_1/new/`）

| 文件 | 说明文档 | 测试对象 |
| :-- | :-- | :-- |
| `tb_clk_div.v` | `tb_clk_div.md` | 分频节拍 |
| `tb_key_debounce.v` | `tb_key_debounce.md` | 消抖/短按/长按/复位 |
| `tb_rtc_counter.v` | `tb_rtc_counter.md` | 时间/日期进位、闰年、大小月、字段编辑 |
| `tb_alarm_clock.v` | `tb_alarm_clock.md` | 3 组独立闹钟：触发/解除/SNOOZE 解除/多组同响 |
| `tb_part1.v` | `tb_part1.md` | 集成：时间/日期显示 |
| `tb_part2.v` | `tb_part2.md` | 集成：时间/日期编辑 |
| `tb_part3.v` | `tb_part3.md` | 集成：闹钟/倒计时显示 |
| `tb_part4.v` | `tb_part4.md` | 集成：闹钟/倒计时编辑 + 开关锁存 |

> `tb_part1~4` 为顶层集成用例（验证组合功能），非基础模块回归；默认视为正确，保留记录。

## 已完成的统一修改（2026-09-15）

1. `key_debounce.v`：`KEY_NUM` 6→4；`top_digital_clock.v` 的 `i_key` 改 `[3:0]`；板级封装去掉 `2'b11`。
2. `alarm_clock.v`：改为 **3 组独立 FSM**，SNOOZE 可解除，**匹配即触发 + 已服务分钟锁存**；接口新增 `o_ring[2:0]`，删除 `o_ring_no/o_state`；`top_digital_clock.v` LED 改用 `o_ring[i]`。
3. 删除过时文件：`fsm_controller.v`、`seg_driver.v`、`alarm_led.v`、`tb_countdown.v`（及对应说明文档），并从 Vivado 工程移除。
4. `tb_alarm_clock.v` 已重写并回归通过；全部仿真（tb_clk_div / tb_key_debounce / tb_rtc_counter / tb_alarm_clock / tb_part1~4）通过；已生成新固件。

## 待确认/注意

1. 开关"拨下读到 1"为上板实测结论；换板需重新确认极性。
2. `tb_part1/2/4` 使用 `force`/层次引用做白盒断言，仅用于仿真。
3. tb 输出消息已统一为英文（`tb_rtc_counter` 为最后一批）。
