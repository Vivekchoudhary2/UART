## Basys 3 constraints for uart_top (transmitter + receiver)
## Port names must match the top module's ports exactly.

## Clock (100 MHz)
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Switches sw[7:0] = SW0 (LSB) ... SW7 (MSB)
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]

## Buttons
## confirm (transmit) = center button (btnC)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports confirm]
## rst = up button (btnU)
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports rst]

## USB-UART (names are from the FPGA's point of view, as in Digilent's master XDC)
## tx = RsTx : FPGA -> PC
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports tx]
## rx = RsRx : PC -> FPGA
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports rx]

## LEDs: received byte on LD0..LD7
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {rx_led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {rx_led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {rx_led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {rx_led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {rx_led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {rx_led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {rx_led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {rx_led[7]}]

## LEDs: status
## frame_err_led = LD13
set_property -dict { PACKAGE_PIN N3 IOSTANDARD LVCMOS33 } [get_ports frame_err_led]
## READY_LED (transmitter idle) = LD14
set_property -dict { PACKAGE_PIN P1 IOSTANDARD LVCMOS33 } [get_ports READY_LED]
## LED0 (transmitter busy) = LD15
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports {LED0[0]}]

## Configuration options
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
