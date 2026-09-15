# key_debounce.v 源码说明

## 1. 实现的功能
按键消抖与边沿检测。对每个按键：两级同步消除亚稳态 → 变化沿触发防抖计时（稳定若干周期后才认可）→ 输出**短按单拍脉冲** `o_key_pulse` 和**长按标志** `o_key_hold`（按住超过阈值后保持有效）。

## 2. 模块
- `key_debounce`：顶层包装，用 `generate` 例化 KEY_NUM 个单键子模块。
- `key_debounce_one`：单按键消抖核心，功能=同步+消抖+脉冲+长按。

## 3. 接口
### key_debounce
| 方向 | 信号 | 说明 |
| :-- | :-- | :-- |
| 输入 | `i_clk`,`i_rst_n` | 时钟/复位 |
| 输入 | `i_key_in[KEY_NUM-1:0]` | 按键总线（默认低有效） |
| 输出 | `o_key_pulse` | 按下单拍脉冲总线 |
| 输出 | `o_key_hold` | 长按标志总线 |
| 参数 | `KEY_NUM`/`KEY_ACTIVE_LOW`/`DEBOUNCE_CNT`/`HOLD_CNT`/`CNT_WIDTH` | 数量/极性/消抖与长按阈值 |

### key_debounce_one
输入 `i_clk,i_rst_n,i_key`；输出 `o_pulse,o_hold`。

## 4. 代码与需求的对应
- 两级同步寄存器 `key_sync1_r/key_sync2_r` → 消除亚稳态。
- `pressed_w`（按极性换算的有效按下电平）、`press_rise_w/press_fall_w`（变化沿）→ 触发防抖计时。
- `pending_r` + `cnt_r` 计到 `DEBOUNCE_CNT` 才更新 `key_reg_r` → 消抖，对应"按键抖动误触发"风险防范。
- `o_pulse = key_reg_r & ~key_reg_ff_r` → 每次稳定按下产生一拍，供切换/加减用。
- `hold_cnt_r` 达 `HOLD_CNT` 置 `o_hold` → 对应"长按连加/连减、倒计时长按复位"。

## 关键代码详解

**（1）两级同步与极性换算**
```verilog
key_sync1_r <= i_key;
key_sync2_r <= key_sync1_r;
wire pressed_w = KEY_ACTIVE_LOW ? ~key_sync2_r : key_sync2_r;
```
- 外部按键先经两级寄存器同步，减少亚稳态。
- `pressed_w` 是"换算成高有效的按下电平"：低有效按键按下时输入为 0，取反后 `pressed_w=1`。后面所有逻辑都只看 `pressed_w`。

**（2）变化沿检测**
```verilog
press_ff_r  <= pressed_w;
wire press_rise_w = pressed_w & ~press_ff_r;   // 按下瞬间
wire press_fall_w = ~pressed_w & press_ff_r;   // 松开瞬间
```
- `press_ff_r` 是 `pressed_w` 打一拍；用"当前 & 上一拍取反"得到上升沿，反之得下降沿。任一变化沿都说明按键电平动了，需要重新防抖计时。

**（3）防抖计时**
```verilog
if (press_rise_w || press_fall_w) begin
    pending_r <= 1'b1; cnt_r <= 0;          // 一有变化就重新开始计时
end else if (pending_r) begin
    if (cnt_r >= DEBOUNCE_CNT-1) begin      // 连续稳定够久
        pending_r <= 0; key_reg_r <= pressed_w;  // 才认可新电平
    end else cnt_r <= cnt_r + 1;
end
```
- 关键思想：**只有电平连续稳定 `DEBOUNCE_CNT` 拍才认可**。抖动期间电平不断变化 → 反复进第一分支把计数清零，永远到不了阈值，从而滤掉抖动。
- 认可后把 `key_reg_r` 更新为稳定电平。

**（4）按下单拍脉冲**
```verilog
key_reg_ff_r <= key_reg_r;
o_pulse      <= key_reg_r & ~key_reg_ff_r;
```
- 在"稳定电平"的上升沿产生一拍 `o_pulse`（每次有效按下只发一次），供上层做"切换/加一"。
- 注意脉冲比 `key_reg_r` 生效晚 1 拍，所以测试里要留余量（见 tb 说明）。

**（5）长按标志**
```verilog
if (key_reg_r) begin
    if (hold_cnt_r >= HOLD_CNT-1) o_hold <= 1'b1;   // 按住够久→保持高
    else hold_cnt_r <= hold_cnt_r + 1;
end else begin hold_cnt_r <= 0; o_hold <= 1'b0; end
```
- 稳定按下期间累加 `hold_cnt_r`，达到 `HOLD_CNT` 后 `o_hold` 一直为 1（按住保持），松开清零。上层用它实现"长按连加/倒计时长按复位"。

## 疑问
- 无。说明：本设计最终只使用前 4 个按键（KEY1..4）；长按标志 `o_hold` 用于"编辑界面长按连加/连减"和"倒计时长按复位"。

## 待修改事项（统一处理）
- [已完成] `KEY_NUM` 由 6 改为 4（顶层 `i_key` 同步改为 `[3:0]`，板级封装去掉 `2'b11`）。
- 本文件其余逻辑无需修改。
