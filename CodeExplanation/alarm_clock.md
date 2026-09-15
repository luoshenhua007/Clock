# alarm_clock.v 源码说明

## 1. 实现的功能
管理 3 组闹钟（每组 时/分 + 使能）。到点（当前时间时:分匹配）触发提醒，**匹配检测每个时钟都做、不受秒节拍限制，整点当拍即响**；每组各有一套独立状态机：IDLE → 响铃 5s（可解除）→ 静默 10s → 再响 5s → IDLE，因此多组可同时响铃。解除键**边沿即时响应**（不必等秒节拍）。

## 2. 模块
- `alarm_clock`：唯一模块，功能=闹钟存储、比较、使能、提醒状态机、字段调整。

## 3. 接口
| 方向 | 信号 | 说明 |
| :-- | :-- | :-- |
| 输入 | `i_clk`,`i_rst_n` | 时钟/复位 |
| 输入 | `i_flag_1s` | 秒使能（计时/触发节拍） |
| 输入 | `i_set_en` | 设置模式（调整字段，暂停响铃） |
| 输入 | `i_idx[1:0]` | 选中闹钟 0..2 |
| 输入 | `i_fld[1:0]` | 0=时 1=分 2=使能切换 |
| 输入 | `i_inc`,`i_dec` | 字段增减 |
| 输入 | `i_cur_hour`,`i_cur_min` | 当前时间（比较用） |
| 输入 | `i_ack` | 解除键（脉冲/电平，内部取边沿） |
| 输出 | `o_sel_hour/o_sel_min` | 选中闹钟时间（显示用） |
| 输出 | `o_en[2:0]` | 3 组使能 |
| 输出 | `o_ring[2:0]` | 各组响铃中（每位对应一组闹钟，可同时为 1） |

## 4. 代码与需求的对应
- 存储数组 `h_r[0:2]/m_r[0:2]/en_r[0:2]` → 3 组闹钟与使能。
- 每组维护 `served_hm_r`（已服务分钟）：`cur_hm != served_hm_r` 时立即比较时:分是否相等，相等即触发并锁存当前分钟 → 对应"到点提醒、同分钟不重复、整点当拍即响"。
- 状态常量 `S_IDLE/S_ALARM1/S_SNOOZE/S_ALARM2` 与 `RING_CNT=5`、`SNOOZE_CNT=10` → 对应"响 5s→停 10s→再响 5s 自动解除"。
- `i_ack` 边沿检测（`ack_d1_r`）在 ALARM1/2 即时回 IDLE → 对应"按解除键立即解除"。
- 调整段：按 `i_fld` 改 时/分 或切换使能 → 对应"闹钟设置界面"。
- 输出 `o_en/o_sel_*` → 供显示"编号 + HH.MM / 停用 ----"。

## 关键代码详解

**（1）匹配即触发 + 已服务分钟锁存**
```verilog
wire cur_hm_w = {i_cur_hour, i_cur_min};
if (cur_hm_w != served_hm_r[i]) begin
    served_hm_r[i] <= 16'hffff;                        // 离开该分钟先清标志
    if (en_r[i] && (h_r[i]==i_cur_hour) && (m_r[i]==i_cur_min)) begin
        st_r[i] <= 2'd1; ring_r[i] <= 1'b1;
        served_hm_r[i] <= cur_hm_w;                    // 锁存本分钟，防重复
    end
end
```
- 匹配检测**每个时钟周期都执行**（不受 `i_flag_1s` 门控）：RTC 时间一跳到 08:00:00，下一拍即触发，不再晚 1 秒。
- `served_hm_r` 记录"已处理过的时:分"：同一分钟内不再重复触发；离开该分钟后清为 `ffff`，下次再匹配才触发。

**（2）解除键即时（不等秒节拍）**
```verilog
ack_d1_r <= i_ack;
if (i_ack && !ack_d1_r && (state_r==S_ALARM1 || state_r==S_ALARM2)) begin
    state_r <= S_IDLE; o_ring <= 0; ...
end else if (i_flag_1s) begin ... end
```
- `ack_d1_r` 是 `i_ack` 打一拍，`i_ack & ~ack_d1_r` 就是**按下沿**。该分支在**每个时钟周期**都判断（不放在 `i_flag_1s` 里），因此按下解除键立即生效，不受 1s 节拍限制。

**（3）每组独立的二次提醒状态机**
```verilog
st_r[i]==1: if (cnt_r[i] >= RING_CNT-1)   → 2, ring=0   // 响 5s
st_r[i]==2: if (cnt_r[i] >= SNOOZE_CNT-1) → 3, ring=1   // 静默 10s
st_r[i]==3: if (cnt_r[i] >= RING_CNT-1)   → 0, ring=0   // 再响 5s
```
- 3 组闹钟各有一个 `st_r[i]`/`cnt_r[i]`/`ring_r[i]`，互不影响：多组同一分钟到点会**同时**各自响铃（LED1/2/3 同时闪）。
- `cnt_r[i]` 只在 `i_flag_1s` 加一，`RING_CNT=5`、`SNOOZE_CNT=10` → 实现"响 5s→停 10s→再响 5s→结束"。
- 解除键按下（`i_ack` 上升沿）在任意状态（含 SNOOZE）都立即把该组状态清零。

**（4）使能/时间设置**
```verilog
if (i_set_en && (i_inc||i_dec)) begin
    if (i_fld==2) en_r[i_idx] <= i_inc ? 1 : 0;      // 开/关
    else if (i_fld==0) 时 ±1（23/00 回绕）
    else 分 ±1（59/00 回绕）
end
```
- 对应"闹钟设置/启停用"；顶层在显示页用 `i_fld=2` 切换使能，在编辑页用 `i_fld=0/1` 改时间。

## 疑问 / 待修改事项（统一处理）
- [已完成] SNOOZE 期间按解除也立即回 IDLE（取消二次提醒）。
- [已完成] 改为 3 组独立 FSM，可同时响铃；输出 `o_ring[2:0]` 分别驱动 LED1/2/3。
- [已完成] 改为"匹配即触发 + 已服务分钟锁存"，消除 1 秒滞后与沿依赖。
- 接口变化：删除 `o_ring_no/o_state`，新增 `o_ring[2:0]`；顶层 LED 相应改为 `o_ring[i]`。
- 对应 `tb_alarm_clock.v` 已重写并回归通过（含 SNOOZE 解除、多组同时响铃）。
