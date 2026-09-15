# tb_part4.v 源码说明

## 1. 实现的功能
集成测试之四：验证【编辑态 SW4 锁存】与【闹钟/倒计时 · 编辑】。

## 2. 模块
- `tb_part4`：Testbench，例化 `top_digital_clock`。

## 3. 接口/激励
- 在编辑过程中拨动 SW4，检验模式是否保持；退出编辑后按 SW4 档位显示。

## 4. 测试内容与对应需求
- 时间/日期编辑中把 SW4 拨到闹钟档：应**仍为时间/日期编辑**（锁存）；退出后按 SW4=闹钟档显示，且默认闹钟1。
- 闹钟编辑：字段时/分循环、KEY2 时 +1（08→09）、KEY3 分 −1 回绕；编辑不影响走时。
- 切到倒计时编辑：字段时/分/秒、时 +1、秒 −1 回绕；退出编辑应回到倒计时视图（保持所选对象），KEY1 回闹钟1。
- 对应需求：编辑中 SW4 无效、闹钟/倒计时编辑、返回保持所选对象。

## 关键代码详解

**（1）编辑中拨 SW4 应无效（锁存）**
```verilog
@(negedge clk); sw_edit = 0; cyc(20);   // 进入 TD 编辑
@(negedge clk); sw_group = 0; cyc(20);  // 编辑中拨 SW4 到 AC 档
chk("A3", u_dut.td_edit==1, "SW4 ignored while editing");
```
- 因为顶层在"进入编辑沿"锁存了组，编辑中再改 SW4 不改变 `eff_td`，仍停留在时间/日期编辑。

**（2）退出后按 SW4 档位显示**
```verilog
@(negedge clk); sw_edit = 1; cyc(20);
chk("A5", u_dut.ac_disp==1, "after exit follows SW4=AC display");
```

**（3）闹钟/倒计时编辑与返回保持所选**
```verilog
tap(1); chk("B5", u_dut.alm_h==8'h09, "alarm hour inc 08->09");
...
chk("D1", u_dut.ac_disp && u_dut.ac_sel, "exit returns countdown view");
```
- 编辑闹钟字段用 KEY1/KEY2/KEY3；退出编辑后断言仍显示倒计时（保持所选对象），KEY1 再回闹钟1。

## 疑问
- 断言同样使用层次引用读取 DUT 内部信号。

## 待修改事项（统一处理）
- 集成用例，保留；已随 i_key 位宽改为 [3:0] 同步，无需其他修改。
