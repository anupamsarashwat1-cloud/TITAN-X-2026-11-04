# SPDX-License-Identifier: Apache-2.0
# SMVDU-TITAN-X SoC — Xilinx Vivado Physical & Timing Constraints (XDC)
# Target Architecture: Xilinx 7-Series / UltraScale+ (Kintex-7 KC705 / Artix-7 AC701)

################################################################################
# 1. PRIMARY CLOCKS & TIMING
################################################################################
# Differential 100 MHz Onboard Crystal Oscillator
create_clock -period 10.000 -name sys_clk_p -waveform {0.000 5.000} [get_ports sys_clk_p]

# Clock Groups / Asynchronous Clock Domains
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk_p] \
    -group [get_clocks -include_generated_clocks -filter {NAME =~ *tck*}]

################################################################################
# 2. FALSE PATHS (Static Controls & Displays)
################################################################################
set_false_path -from [get_ports cpu_reset_n]
set_false_path -from [get_ports jtag_trst_n]
set_false_path -to [get_ports {led_*}]
set_false_path -from [get_ports {gpio_ext[*]}]
set_false_path -to [get_ports {gpio_ext[*]}]

################################################################################
# 3. PIN ASSIGNMENTS & I/O STANDARDS (Kintex-7 KC705 Default Template)
################################################################################

# Differential System Clock (100MHz)
set_property PACKAGE_PIN AD12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_n]

# Active-Low CPU Reset Push-Button
set_property PACKAGE_PIN AB7  [get_ports cpu_reset_n]
set_property IOSTANDARD LVCMOS15 [get_ports cpu_reset_n]
set_property PULLUP true [get_ports cpu_reset_n]

# UART 0 (USB-to-UART Bridge)
set_property PACKAGE_PIN M19 [get_ports uart0_rx]
set_property IOSTANDARD LVCMOS25 [get_ports uart0_rx]
set_property PACKAGE_PIN K24 [get_ports uart0_tx]
set_property IOSTANDARD LVCMOS25 [get_ports uart0_tx]

# JTAG Debug Interface
set_property PACKAGE_PIN R23 [get_ports jtag_tck]
set_property IOSTANDARD LVCMOS25 [get_ports jtag_tck]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets jtag_tck]
set_property PACKAGE_PIN N24 [get_ports jtag_tms]
set_property IOSTANDARD LVCMOS25 [get_ports jtag_tms]
set_property PACKAGE_PIN P23 [get_ports jtag_tdi]
set_property IOSTANDARD LVCMOS25 [get_ports jtag_tdi]
set_property PACKAGE_PIN R24 [get_ports jtag_tdo]
set_property IOSTANDARD LVCMOS25 [get_ports jtag_tdo]
set_property PACKAGE_PIN T24 [get_ports jtag_trst_n]
set_property IOSTANDARD LVCMOS25 [get_ports jtag_trst_n]

# Diagnostic & Status LEDs
set_property PACKAGE_PIN AB8  [get_ports led_heartbeat]
set_property IOSTANDARD LVCMOS15 [get_ports led_heartbeat]
set_property PACKAGE_PIN AA8  [get_ports {led_core_run[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led_core_run[0]}]
set_property PACKAGE_PIN AC9  [get_ports {led_core_run[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led_core_run[1]}]
set_property PACKAGE_PIN AB9  [get_ports {led_core_run[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led_core_run[2]}]
set_property PACKAGE_PIN AE26 [get_ports {led_core_run[3]}]
set_property IOSTANDARD LVCMOS25 [get_ports {led_core_run[3]}]
set_property PACKAGE_PIN G19  [get_ports led_rot_pass]
set_property IOSTANDARD LVCMOS25 [get_ports led_rot_pass]
set_property PACKAGE_PIN E18  [get_ports led_panic]
set_property IOSTANDARD LVCMOS25 [get_ports led_panic]

# I2C Master Interface
set_property PACKAGE_PIN K21 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_scl]
set_property PACKAGE_PIN L21 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS25 [get_ports i2c_sda]

# SPI Master Interface (SD Card)
set_property PACKAGE_PIN AB22 [get_ports spi_sclk]
set_property IOSTANDARD LVCMOS25 [get_ports spi_sclk]
set_property PACKAGE_PIN AC22 [get_ports spi_cs_n]
set_property IOSTANDARD LVCMOS25 [get_ports spi_cs_n]
set_property PACKAGE_PIN AC20 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS25 [get_ports spi_mosi]
set_property PACKAGE_PIN AC21 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS25 [get_ports spi_miso]

# CAN Controller Interface
set_property PACKAGE_PIN AF24 [get_ports can_tx]
set_property IOSTANDARD LVCMOS25 [get_ports can_tx]
set_property PACKAGE_PIN AF25 [get_ports can_rx]
set_property IOSTANDARD LVCMOS25 [get_ports can_rx]

# HDMI Video Output (TMDS 3.3V)
set_property PACKAGE_PIN C24 [get_ports hdmi_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_clk_p]
set_property PACKAGE_PIN B24 [get_ports hdmi_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_clk_n]
set_property PACKAGE_PIN B23 [get_ports {hdmi_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_p[0]}]
set_property PACKAGE_PIN A23 [get_ports {hdmi_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_n[0]}]
set_property PACKAGE_PIN E23 [get_ports {hdmi_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_p[1]}]
set_property PACKAGE_PIN D23 [get_ports {hdmi_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_n[1]}]
set_property PACKAGE_PIN F25 [get_ports {hdmi_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_p[2]}]
set_property PACKAGE_PIN E25 [get_ports {hdmi_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_data_n[2]}]

# User GPIO (PMOD Header J52)
set_property PACKAGE_PIN Y23  [get_ports {gpio_ext[0]}]
set_property PACKAGE_PIN Y24  [get_ports {gpio_ext[1]}]
set_property PACKAGE_PIN AA22 [get_ports {gpio_ext[2]}]
set_property PACKAGE_PIN AA23 [get_ports {gpio_ext[3]}]
set_property PACKAGE_PIN AA24 [get_ports {gpio_ext[4]}]
set_property PACKAGE_PIN AB24 [get_ports {gpio_ext[5]}]
set_property PACKAGE_PIN W23  [get_ports {gpio_ext[6]}]
set_property PACKAGE_PIN W24  [get_ports {gpio_ext[7]}]
set_property IOSTANDARD LVCMOS25 [get_ports {gpio_ext[*]}]

# Configuration Voltage & Bank Constraints
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
