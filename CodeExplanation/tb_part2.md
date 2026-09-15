# tb_part2.v 源码说明

## 1. 实现的功能
集成测试之二：验证【时间/日期 · 编辑】模式——字段循环、+/−、编辑时间暂停、编辑日期不停表。

## 2. 模块
- `tb_part2`：Testbench，例化 `top_digital_clock`，两开关置于"时间/日期·编辑"。

## 3. 接口/激励
- 与 tb_part1 相同的时钟/按键激励框架。
- KEY1 切字段、KEY2=+、KEY3=−。

## 4. 测试内容与对应需求
- 进入编辑：`rtc_set_en=1` 暂停走秒；KEY1 时→分→秒；KEY2 时 +1；KEY3 分 −1 回绕 59。
- 编辑时间期间等待 1 秒，秒保持不变。
- 退出编辑回显示；切到日期页再进入编辑：`rtc_date_ed=1` 且 `rtc_set_en=0`（不停表）；年 +1、月 −1 回绕。
- 对应需求：时间/日期设置、编辑不影响计时。

## 关键代码详解

**（1）模式切换**
```verilog
@(negedge clk); sw_edit = 0; cyc(20);   // 拨到编辑档
```
- 顶层用开关**电平**决定模式，所以在负沿改变开关并等几拍，让模式译码稳定。

**（2）字段与 +/- 的对应**
```verilog
tap(0);   // KEY1 切字段
tap(1);   // KEY2 = +
tap(2);   // KEY3 = −
chk("A5", u_dut.rtc_field == 3'd1, "cursor minute");
```
- 关键：编辑态下 KEY1 是"切字段"、KEY2 是"+"、KEY3 是"−"，与显示态不同，测试里必须按这个映射。

**（3）验证"编辑时间暂停、编辑日期不停"**
```verilog
cyc(CLK_FREQ);                          // 时间编辑中等约 1 秒
chk("A8", u_dut.sec == 8'h00, "seconds frozen during time edit");
...
chk("B4", u_dut.rtc_set_en == 1'b0, "clock NOT stopped in date edit");
```
- 通过等一个秒周期看秒是否变化，来证明"只有编辑时间暂停走时"。

## 疑问
- 通过层次引用读取 DUT 内部信号（`td_edit/rtc_field` 等）做断言。

## 待修改事项（统一处理）
- 集成用例，保留；已随 i_key 位宽改为 [3:0] 同步，无需其他修改。
