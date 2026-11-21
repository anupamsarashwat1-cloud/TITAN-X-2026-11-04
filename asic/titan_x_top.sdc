# SPDX-License-Identifier: Apache-2.0
# SMVDU-TITAN-X SoC — System-Level Design Constraints (SDC)

# -------------------------------------------------------------------------
# Clock Definitions
# -------------------------------------------------------------------------

# Core Clock: Target ~138.8 MHz (7.2 ns) for RISC-V cores and system interconnect
create_clock -name clk -period 7.2 [get_ports clk]

# PCIe PIPE Clock: 250 MHz (4.0 ns)
create_clock -name pipe_clk -period 4.0 [get_ports pipe_clk]

# Ethernet TX Clock: 125 MHz (8.0 ns) for Gigabit Ethernet
create_clock -name eth_tx_clk -period 8.0 [get_ports eth_tx_clk]

# Ethernet RX Clock: 125 MHz (8.0 ns) for Gigabit Ethernet
create_clock -name eth_rx_clk -period 8.0 [get_ports eth_rx_clk]

# USB ULPI Clock: 60 MHz (16.666 ns)
create_clock -name ulpi_clk -period 16.666 [get_ports ulpi_clk]

# MIPI CSI-2 RX Byte Clock: ~200 MHz (5.0 ns) High-Speed Byte Clock
create_clock -name mipi_rxbyteclkhs -period 5.0 [get_ports mipi_rxbyteclkhs]

# HDMI Pixel Clock: ~74.25 MHz (13.468 ns) for 720p60
create_clock -name hdmi_clk_pixel -period 13.468 [get_ports hdmi_clk_pixel]

# HDMI TMDS Clock: ~742.5 MHz (1.346 ns) for 10x 8b/10b encoding
create_clock -name hdmi_clk_tmds -period 1.346 [get_ports hdmi_clk_tmds]

# RTC Clock: 32.768 kHz (30517.578 ns) for Real-Time Clock
create_clock -name rtc_clk -period 30517.578 [get_ports rtc_clk]

# -------------------------------------------------------------------------
# Clock Uncertainty (Jitter & Margin)
# -------------------------------------------------------------------------
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

set_clock_uncertainty -setup 0.1 [get_clocks pipe_clk]
set_clock_uncertainty -setup 0.2 [get_clocks eth_tx_clk]
set_clock_uncertainty -setup 0.2 [get_clocks eth_rx_clk]
set_clock_uncertainty -setup 0.3 [get_clocks ulpi_clk]
set_clock_uncertainty -setup 0.1 [get_clocks mipi_rxbyteclkhs]
set_clock_uncertainty -setup 0.2 [get_clocks hdmi_clk_pixel]
set_clock_uncertainty -setup 0.05 [get_clocks hdmi_clk_tmds]

# -------------------------------------------------------------------------
# Clock Groups (Asynchronous Domains)
# -------------------------------------------------------------------------
# Set clock domains as asynchronous to prevent timing analysis across boundaries
# where explicit synchronizers are used in the RTL.
set_clock_groups -asynchronous \
    -group [get_clocks clk] \
    -group [get_clocks pipe_clk] \
    -group [get_clocks eth_tx_clk] \
    -group [get_clocks eth_rx_clk] \
    -group [get_clocks ulpi_clk] \
    -group [get_clocks mipi_rxbyteclkhs] \
    -group [get_clocks hdmi_clk_pixel] \
    -group [get_clocks hdmi_clk_tmds] \
    -group [get_clocks rtc_clk]

# -------------------------------------------------------------------------
# Generic I/O Constraints (Assume 20% of period for setup/hold budget)
# -------------------------------------------------------------------------
# Default System IO (relative to 'clk')
set_input_delay  -clock clk -max 1.5 [all_inputs]
set_input_delay  -clock clk -min 0.5 [all_inputs]

# Exclude clock ports from input delay constraints
remove_input_delay [get_ports clk]
remove_input_delay [get_ports pipe_clk]
remove_input_delay [get_ports eth_tx_clk]
remove_input_delay [get_ports eth_rx_clk]
remove_input_delay [get_ports ulpi_clk]
remove_input_delay [get_ports mipi_rxbyteclkhs]
remove_input_delay [get_ports hdmi_clk_pixel]
remove_input_delay [get_ports hdmi_clk_tmds]
remove_input_delay [get_ports rtc_clk]

# Default System Outputs
set_output_delay -clock clk -max 1.5 [all_outputs]
set_output_delay -clock clk -min 0.5 [all_outputs]

# -------------------------------------------------------------------------
# False Paths
# -------------------------------------------------------------------------
# Reset is considered asynchronous for setup/hold, handled by recovery/removal
set_false_path -from [get_ports rst_n]
