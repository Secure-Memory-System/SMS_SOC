# -------------------------------------------------------------------------
# Full SoC Comprehensive Analysis to CSV (Excel용)
# -------------------------------------------------------------------------

set output_file "Full_SoC_Analysis.csv"
set fp [open $output_file w]

# 1. 엑셀 헤더 작성 (쉼표로 구분)
puts $fp "Project,Device,LUT_Used,LUT_Util_%,FF_Used,FF_Util_%,WNS_ns,TNS_ns,WHS_ns,Total_Power_W,Max_Congestion_%,Worst_Logic_Level"

# 2. 데이터 수집 시작
puts "Gathering System-wide data..."

# A. 리소스 요약 파싱
set util_str [report_utilization -return_string -quiet]
set lut_u "-"; set lut_p "-"; set ff_u "-"; set ff_p "-"
regexp {Slice LUTs\s*\|\s*(\d+)\s*\|[^\|]*\|[^\|]*\|\s*([\d\.]+)} $util_str -> lut_u lut_p
regexp {Slice Registers\s*\|\s*(\d+)\s*\|[^\|]*\|[^\|]*\|\s*([\d\.]+)} $util_str -> ff_u ff_p

# B. 타이밍 요약 파싱 (WNS, TNS, WHS)
set timing_str [report_timing_summary -return_string -quiet]
set wns "0.000"; set tns "0.000"; set whs "0.000"
regexp {WNS\(ns\)\s*\|\s*TNS\(ns\)\s*\|.*?\n\s*(-?[\d\.]+)\s*\|\s*(-?[\d\.]+)} $timing_str -> wns tns
regexp {WHS\(ns\)\s*\|\s*THS\(ns\)\s*\|.*?\n\s*(-?[\d\.]+)} $timing_str -> whs

# C. 소비전력 파싱
set power_str [report_power -return_string -quiet]
set total_p "-"
regexp {Total On-Chip Power \(W\)\s*\|\s*([\d\.]+)} $power_str -> total_p

# D. 배선 혼잡도 파싱
set congestion_str [report_design_analysis -congestion -return_string -quiet]
set max_cong "0"
regexp {(\d+)%$} $congestion_str -> max_cong

# E. 최악 경로의 로직 레벨 파싱
set worst_path [get_timing_paths -max_paths 1]
set logic_lvl "0"
if {$worst_path != ""} {
    set logic_lvl [get_property LOGIC_LEVELS $worst_path]
}

# 3. CSV 파일에 데이터 쓰기
set proj_name [get_projects]
set device_name [get_property PART [current_project]]

puts $fp "$proj_name,$device_name,$lut_u,$lut_p,$ff_u,$ff_p,$wns,$tns,$whs,$total_p,$max_cong,$logic_lvl"

close $fp
puts "=============================================================="
puts " SoC 종합 분석 완료! 엑셀에서 결과를 확인하세요."
puts " 경로: [file normalize $output_file]"
puts "=============================================================="