# top_digital_clock_board.v 源码说明

## 1. 实现的功能
板级顶层封装（供管脚约束）。产生上电复位，并把板上的 KEY1..4、SW4、SW3 接入设计顶层，输出段码/位选/4 路 LED。

## 2. 模块
- `top_digital_clock_board`：唯一模块，内部例化 `top_digital_clock`。

## 3. 接口
| 方向 | 信号 | 说明 |
| :-- | :-- | :-- |
| 输入 | `sys_clk` | 50MHz（Y18） |
| 输入 | `btn[3:0]` | KEY1..4（E3/G4/P19/R19，低有效） |
| 输入 | `sw_group` | SW4（N15） |
| 输入 | `sw_edit` | SW3（R17） |
| 输出 | `seg[7:0]`,`sel[7:0]` | 数码管段码/位选 |
| 输出 | `led[3:0]` | LED1..4 |

## 4. 代码与需求的对应
- `rst_cnt` 计数满后 `rst_n` 释放 → 上电复位（约 84ms@50M）。
- 例化 `top_digital_clock` 并把 `{2'b11, btn[3],btn[2],btn[1],btn[0]}` 接到 `i_key` → 使 KEY1 对应 `i_key[0]`，符合顶层键位约定。
- 直接透传 `sw_group/sw_edit` → 对应"开关按电平使用"。
- 该模块是 XDC 约束的对象（端口名与 `top_digital_clock.xdc` 一致）。

## 关键代码详解

**（1）上电复位**
```verilog
reg [21:0] rst_cnt;
wire rst_n = &rst_cnt;              // 计数未满时 rst_n=0
always @(posedge sys_clk)
    if (!rst_n) rst_cnt <= rst_cnt + 1;
```
- 上电后计数器从 0 递增，`&rst_cnt` 只有全 1 时才为 1；在此之前 `rst_n=0` 保持复位，约 84ms（2^22/50M）后释放，保证内部寄存器进入确定初值。

**（2）按键拼接**
```verilog
.i_key({2'b11, btn[3], btn[2], btn[1], btn[0]})
```
- 顶层 `i_key[0..3]` 对应 KEY1..4；高位补 1（不按下）。

## 说明（原"疑问"）
- 未使用的高位按键补 `2'b11`：按键低有效，`1` 表示未按下，保证多余通道不触发。
- 上电复位：无专用复位键，用计数器延时产生 `rst_n`，让所有子模块从确定初值启动。

## 待修改事项（统一处理）
- [已完成] 随 `KEY_NUM` 改 4，本模块 `i_key` 拼接已去掉 `2'b11`，直接接 `btn[3:0]`。
