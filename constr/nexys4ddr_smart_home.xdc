## ============================================================================
## nexys4ddr_smart_home.xdc : pin constraints for smart_home_top
## Board : Digilent Nexys 4 DDR (xc7a100tcsg324-1)
## Pin numbers taken from Digilent's official Nexys-4-DDR-Master.xdc
## ============================================================================

## 100 MHz clock
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Reset button (active low)
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports cpu_resetn]

## Switches  (SW8 / SW9 sit in a 1.8 V bank)
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS18 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS18 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## RGB LEDs
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports led16_b]
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports led16_g]
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports led16_r]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports led17_b]
set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 } [get_ports led17_g]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports led17_r]

## 7-segment display (seg[0] = CA ... seg[6] = CG)
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports dp]
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {an[7]}]

## Push buttons
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports btnc]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports btnu]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports btnl]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports btnr]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports btnd]

## USB-UART bridge (names are from the FPGA's point of view)
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports uart_rxd]   ;# UART_TXD_IN  (PC -> FPGA)
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports uart_txd]   ;# UART_RXD_OUT (FPGA -> PC)

## ADT7420 on-board temperature sensor (I2C, address 0x4B)
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 PULLUP true } [get_ports tmp_scl]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 PULLUP true } [get_ports tmp_sda]

## Pmod JA : external sensors (used when SW14 = 1)
##   JA1 PIR OUT   JA2 LDR module DO   JA3 MQ-2 DO (active low)   JA4 door reed switch to GND
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {ja[0]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports {ja[1]}]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 PULLUP   true } [get_ports {ja[2]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 PULLUP   true } [get_ports {ja[3]}]

## Pmod JB : actuator outputs (drive loads through a MOSFET / relay module, never directly)
##   JB1 fan PWM   JB2 light relay   JB3 siren / buzzer   JB4 gas valve (1 = close)
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports {jb[0]}]
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports {jb[1]}]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports {jb[2]}]
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports {jb[3]}]

## Mono audio output (siren)
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports aud_pwm]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports aud_sd]

## Configuration
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Asynchronous human-speed inputs are synchronised inside the design
set_false_path -from [get_ports {sw[*] btnc btnu btnd btnl btnr cpu_resetn uart_rxd ja[*] tmp_sda tmp_scl}]

## Telemetry character table: {kind, idx} -> rom_*_r is sampled only in the
## second cycle of the T_PREP state (clock enable rom_ce), i.e. a 2-cycle path.
set_multicycle_path 2 -setup -from [get_cells -hier -filter {NAME =~ *u_tel/idx_reg*}]  -to [get_cells -hier -filter {NAME =~ *u_tel/rom_*_r_reg*}]
set_multicycle_path 1 -hold  -from [get_cells -hier -filter {NAME =~ *u_tel/idx_reg*}]  -to [get_cells -hier -filter {NAME =~ *u_tel/rom_*_r_reg*}]
set_multicycle_path 2 -setup -from [get_cells -hier -filter {NAME =~ *u_tel/kind_reg*}] -to [get_cells -hier -filter {NAME =~ *u_tel/rom_*_r_reg*}]
set_multicycle_path 1 -hold  -from [get_cells -hier -filter {NAME =~ *u_tel/kind_reg*}] -to [get_cells -hier -filter {NAME =~ *u_tel/rom_*_r_reg*}]
