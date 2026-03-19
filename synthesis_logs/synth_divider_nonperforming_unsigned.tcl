set_param general.maxThreads 4
create_project -in_memory -part xc7a35tcpg236-1

read_verilog -sv /home/brendan/synthesis_workspace/Integer_dividers/divider_nonperforming_unsigned.sv

set xdc_file "/home/brendan/synthesis_workspace/Integer_dividers/synthesis_logs/clock_divider_nonperforming_unsigned.xdc"
set fp [open $xdc_file w]
puts $fp "create_clock -period 10.000 -name CLK \[get_ports CLK\]"
close $fp
read_xdc $xdc_file

synth_design -top divider_nonperforming_unsigned -part xc7a35tcpg236-1

report_utilization -file /home/brendan/synthesis_workspace/Integer_dividers/synthesis_logs/utilization_divider_nonperforming_unsigned.rpt
report_timing_summary -file /home/brendan/synthesis_workspace/Integer_dividers/synthesis_logs/timing_divider_nonperforming_unsigned.rpt
