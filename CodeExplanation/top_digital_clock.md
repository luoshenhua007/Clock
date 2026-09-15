# top_digital_clock.v 源码说明

## 1. 实现的功能
设计顶层，把输入、模式、计数、显示、LED 全部整合。核心职责：
- 由 SW4/SW3 电平译码出 4 种模式（时间日期/闹钟倒计时 × 显示/编辑），并在编辑期间锁存组；
- 管理页面状态（时间/日期、12/24h、年月日/星期、闹钟1/2/3、倒计时）；
- 将 KEY 操作分发到 rtc/alarm/countdown；
- 完成显示排版（含 12h 换算、星期推算、闪烁光标、滚动圈、`-` 与编号）与 8 位动态扫描；
- 驱动 LED1..4。

## 2. 模块
- `top_digital_clock`：唯一模块，内含 `clk_div`、`key_debounce`、`rtc_counter`、`alarm_clock`、`countdown` 的例化，以及显示/扫描逻辑。

## 3. 接口
| 方向 | 信号 | 说明 |
| :-- | :-- | :-- |
| 输入 | `i_clk`,`i_rst_n` | 时钟/复位 |
| 输入 | `i_key[5:0]` | [0]=KEY1 [1]=KEY2 [2]=KEY3 [3]=KEY4（低有效） |
| 输入 | `i_sw_group` | SW4 电平（实测拨下读到 1） |
| 输入 | `i_sw_edit` | SW3 电平 |
| 输出 | `o_seg[7:0]` | 段码（含 dp） |
| 输出 | `o_sel[7:0]` | 位选 |
| 输出 | `o_led[3:0]` | LED1..3=闹钟，LED4=倒计时 |
| 参数 | `CLK_FREQ/DB_CNT/HOLD_CNT` | 主频/消抖/长按阈值 |

## 4. 代码与需求的对应
- **模式译码**：`editing_mode = ~i_sw_edit`；进入编辑沿锁存 `grp_l`；`eff_td = editing_mode ? grp_l : i_sw_group`；导出 `td_disp/td_edit/ac_disp/ac_edit` → 对应"两开关四模式、编辑中 SW4 无效"。
- **页面状态 always**：`in_edit` 时 KEY1 循环 `cursor`；`td_disp` 下 KEY1 时间↔日期、KEY2 12/24h 或 年月日↔星期；`ac_disp` 下 KEY1 切闹钟、KEY2 切倒计时 → 对应按键表。
- **rtc 控制**：`rtc_set_en=td_edit&&!view_time`（校时暂停）、`rtc_date_ed=td_edit&&view_time`（改日期不停表）、`rtc_field` 由 cursor 映射 → 对应"时间/日期编辑"。
- **长按连加**：`rep_cnt/rep_tick` + `kh[1]/kh[2]` 产生 +/− 重复脉冲 → 对应"长按连加/连减"。
- **闹钟控制**：`alm_edit` 时 `i_set_en` 编辑时/分；`alm_toggle` 在显示页切换使能；`i_ack=kp[3]` → 对应"闹钟设置/启停用/KEY4 解除"。
- **倒计时控制**：`cnt_run`（短按启停）、`cnt_reset`（`kh[2]` 上升沿长按复位）、`cnt_set/cnt_field/cnt_inc/cnt_dec`（编辑）→ 对应"倒计时设定/暂停/复位"。
- **LED**：`o_led[0..2]=alm_ring & 编号对应`，`o_led[3]=` 倒计时完成 5s 闪烁（`cnt5`）→ 对应"LED 分工"。
- **12h/星期**：`hv12/v12` 换算与 A/P；Zeller 计算 `week_day` → 对应"12/24h、星期显示"。
- **显示选通 always**：按模式选择 `digit_d/blank_d/dp_d/blink_g/seg_ovr`（时间、日期、星期、闹钟含 `-`/`----`、倒计时含滚动圈）→ 对应各显示格式。
- **扫描/段码**：`scan_cnt/scan_pos` 逐位扫描，`seg_code` 译码，输出覆盖逻辑处理 A/P、`-`、滚动圈，且换位前熄灭尾段防残影 → 对应"8 位显示、极性、防残影"。

## 关键代码详解

**（1）模式译码 + 编辑锁存（最易困惑处）**
```verilog
wire editing_mode = ~i_sw_edit;                 // SW3 处于编辑档
reg  grp_l; reg sw3_prev;
always @(posedge i_clk ...) begin
    sw3_prev <= i_sw_edit;
    if (i_sw_edit==0 && sw3_prev==1) grp_l <= i_sw_group; // 进入编辑那一刻锁存组
end
wire eff_td = editing_mode ? grp_l : i_sw_group;          // 编辑中组取锁存值
wire td_disp = ~editing_mode &  eff_td;  // 时间/日期·显示
wire td_edit =  editing_mode &  eff_td;  // 时间/日期·编辑
wire ac_disp = ~editing_mode & ~eff_td;  // 闹钟/倒计时·显示
wire ac_edit =  editing_mode & ~eff_td;  // 闹钟/倒计时·编辑
```
- 关键点：**编辑期间不直接用当前 SW4**，而是用进入编辑时锁存的 `grp_l`。这样"编辑中拨 SW4"不会切组；退出编辑（`editing_mode=0`）后又回到实时 `i_sw_group`，按当时档位显示。

**（2）按键语义按模式分派**
```verilog
if (in_edit) begin
    if (!prev_e) cursor <= 0;              // 刚进编辑：光标回 0
    else if (kp[0]) cursor <= (cursor>=cur_max)?0:cursor+1; // KEY1 循环字段
end else if (td_disp) begin
    if (kp[0]) {view_time<=~view_time; date_week<=0;}       // 时间/日期
    else if (kp[1]) fmt_12<=~fmt_12 或 date_week<=~date_week; // 12/24h 或 星期
end else if (ac_disp) begin
    if (kp[0]) 切闹钟/回闹钟1; else if (kp[1]) 切倒计时;
end
```
- `prev_e` 用来识别"进入编辑沿"，保证每次进入编辑光标从 0 开始。
- 不同模式下同一个 KEY 含义不同，就是靠这些分支实现"键位复用"。

**（3）长按连加/连减**
```verilog
localparam REP_TH = CLK_FREQ/8;      // 约 8Hz 重复
always @(posedge...) if (hold_any) 计数到 REP_TH 回零; else 清零;
wire rep_tick = hold_any && (rep_cnt>=REP_TH-1);
wire rtc_inc = td_edit && (kp[1] || (kh[1] && rep_tick)); // 短按一次 或 长按到点各加一
```
- 短按走 `kp[1]`（一次一加）；按住时 `kh[1]` 有效，每 `REP_TH` 个时钟产生一次 `rep_tick`，实现连续加。闪烁在长按期间被强制常亮（见闪烁段）。

**（4）显示选通（模式 → 8 位内容）**
```verilog
if (td_edit&&view_time) 日期+年/月/日闪烁
else if (td_edit) 时间(强制24h)+时/分/秒闪烁
else if (ac_edit&&!ac_sel) 闹钟编辑(时/分闪烁, 第7位'-', 第8位编号)
else if (ac_edit&&ac_sel) 倒计时编辑(时/分/秒闪烁)
else if (ac_disp&&!ac_sel) 闹钟显示(停用左4=----)
else if (ac_disp&&ac_sel) 倒计时显示(第8位滚动圈/'-')
else if (view_time&&date_week) 星期
else if (view_time) 日期
else 时间显示(12/24h + A/P)
```
- 该 always 输出 `digit_d/dp_d/blank_d/blink_g/seg_ovr` 五个量，供扫描/输出阶段使用。

**（5）扫描与输出覆盖优先级（关键！）**
```verilog
sel_r = ~(1<<scan_pos);                  // 位选低有效
if (换位尾段)          seg=全灭;          // 防残影
else if (eff_blank[pos]) seg=全灭;        // 熄灭/闪烁灭相
else if (seg_ovr[pos])   seg='-';         // 覆盖：闹钟的 - 与 ----
else if (ac倒计时 pos0)  seg=滚动圈/'-';
else if (td_disp时间 pos0 且12h) seg=A/P;
else                     seg=~(段码|dp);
```
- 顺序决定优先级：**熄灭 > 覆盖字符 > 滚动圈 > A/P > 正常译码**。这正是"闹钟编号不被 A/P 覆盖"、"停用闹钟显示 `----`"等细节的实现位置。

**（6）LED 与滚动圈**
```verilog
o_led[0..2] = (alm_ring && alm_rno==i) ? blk_ph : 0;  // 各闹钟独立闪
o_led[3]    = (cnt5!=0) ? blk_ph : 0;                 // 倒计时完成 5s
ring: cd_run && flag_1s 时 0→1→…→5→0 循环，对应第8位滚动圈
```

## 说明（原"疑问"）
- 开关"拨下读到 1"为上板**实测**结论，本设计据此译码；换板或改接线时需重新确认极性。

## 待修改事项（统一处理）
- [已完成] 随 `KEY_NUM` 改 4，本模块 `i_key` 位宽已由 `[5:0]` 改为 `[3:0]`。
- [已完成] 未例化的 `seg_driver/alarm_led/fsm_controller` 已从工程移除。
- [已完成] 闹钟改为三组独立响铃：LED 由 `o_ring[2:0]` 直接驱动。
