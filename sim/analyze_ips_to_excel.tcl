# -------------------------------------------------------------------------
# SoC Custom IP Analysis to CSV (Excel용)
# -------------------------------------------------------------------------

set output_file "SoC_IP_Analysis.csv"
set fp [open $output_file w]

# 1. 엑셀 헤더 작성 (쉼표로 칸 구분)
puts $fp "IP_Module,LUT_Used,FF_Used,WNS_ns,Max_Logic_Level"

# 2. 모든 IP 모듈 가져오기
set all_cells [get_cells -hierarchical -filter {IS_PRIMITIVE == 0}]

foreach cell $all_cells {
    puts "Analyzing: $cell"

    # --- A. 리소스 추출 ---
    set util_str [report_utilization -cells $cell -return_string -quiet]
    set lut "-"
    set ff "-"
    # 정규표현식으로 숫자만 추출
    if {[regexp {Slice LUTs\s*\|\s*(\d+)} $util_str -> match]} { set lut $match }
    if {[regexp {Slice Registers\s*\|\s*(\d+)} $util_str -> match]} { set ff $match }

    # --- B. 타이밍(WNS) 추출 ---
    # 해당 IP의 가장 느린 경로(Worst Path)의 Slack 값을 가져옴
    set wns "N/A"
    set paths [get_timing_paths -from [get_cells $cell/*] -max_paths 1 -quiet]
    if {$paths != ""} {
        set wns [get_property SLACK $paths]
    }

    # --- C. 로직 레벨 추출 ---
    set logic_lvl "0"
    if {$paths != ""} {
        set logic_lvl [get_property LOGIC_LEVELS $paths]
    }

    # 3. CSV 파일에 한 줄로 쓰기
    puts $fp "$cell,$lut,$ff,$wns,$logic_lvl"
}

close $fp
puts "=============================================================="
puts " 분석 완료! 엑셀(CSV) 파일이 생성되었습니다."
puts " 경로: [file normalize $output_file]"
puts "=============================================================="