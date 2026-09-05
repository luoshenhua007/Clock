## top_digital_clock.xdc - HX7A75A 开发板管脚约束
## 顶层：top_digital_clock_board
## 时钟 50MHz；按键/开关低有效；数码管共阳（段码低点亮）、位选低有效（低者点亮）；
## LED 高电平点亮。

## 时钟
set_property PACKAGE_PIN Y18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

## 按键（低有效）：MODE / SEL / 加 / 减
set_property PACKAGE_PIN E3  [get_ports {btn[0]}]
set_property PACKAGE_PIN G4  [get_ports {btn[1]}]
set_property PACKAGE_PIN P19 [get_ports {btn[2]}]
set_property PACKAGE_PIN R19 [get_ports {btn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[*]}]

## 开关（低有效触发）：SW1 = 启动/暂停/解除，SW2 = 复位
set_property PACKAGE_PIN N14 [get_ports sw1]
set_property PACKAGE_PIN P16 [get_ports sw2]
set_property IOSTANDARD LVCMOS33 [get_ports {sw1 sw2}]

## 数码管段码（共阳，低点亮）：seg[0]=a seg[1]=b seg[2]=c seg[3]=d
##                        seg[4]=e seg[5]=f seg[6]=g seg[7]=dp
set_property PACKAGE_PIN AB18 [get_ports {seg[0]}]
set_property PACKAGE_PIN U17  [get_ports {seg[1]}]
set_property PACKAGE_PIN U18  [get_ports {seg[2]}]
set_property PACKAGE_PIN P14  [get_ports {seg[3]}]
set_property PACKAGE_PIN R14  [get_ports {seg[4]}]
set_property PACKAGE_PIN R18  [get_ports {seg[5]}]
set_property PACKAGE_PIN T18  [get_ports {seg[6]}]
set_property PACKAGE_PIN N17  [get_ports {seg[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

## 数码管位选（低有效）：o_sel[0] 接最左管（实测左右映射）
set_property PACKAGE_PIN AA18 [get_ports {sel[0]}]
set_property PACKAGE_PIN W17  [get_ports {sel[1]}]
set_property PACKAGE_PIN V17  [get_ports {sel[2]}]
set_property PACKAGE_PIN AB20 [get_ports {sel[3]}]
set_property PACKAGE_PIN AA19 [get_ports {sel[4]}]
set_property PACKAGE_PIN V19  [get_ports {sel[5]}]
set_property PACKAGE_PIN V18  [get_ports {sel[6]}]
set_property PACKAGE_PIN Y19  [get_ports {sel[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sel[*]}]

## 提醒 LED（高点亮）
set_property PACKAGE_PIN AA6 [get_ports led]
set_property IOSTANDARD LVCMOS33 [get_ports led]
