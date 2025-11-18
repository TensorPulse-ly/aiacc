#!/bin/bash

file1="sim_output/src.txt"
file2="sim_output/dst.txt"

# 检查文件是否存在
for file in "$file1" "$file2"; do
    if [ ! -f "$file" ]; then
        echo "错误：文件 $file 不存在"
        exit 1
    fi
done

echo "开始比较文件中的128位16进制数..."
echo "使用高效模式处理..."
echo "=========================================="

# 使用awk进行高效处理
awk '
function get_bits_to_compare(strb) {
    # strb值与比较位数的映射关系
    switch(strb) {
        case "0000": case "00": return 0
        case "0001": case "01": return 8
        case "0003": case "03": return 16
        case "0007": case "07": return 24
        case "000f": case "0f": return 32
        case "001f": case "1f": return 40
        case "003f": case "3f": return 48
        case "007f": case "7f": return 56
        case "00ff": case "ff": return 64
        case "01ff": case "1ff": return 72
        case "03ff": case "3ff": return 80
        case "07ff": case "7ff": return 88
        case "0fff": case "fff": return 96
        case "1fff": return 104
        case "3fff": return 112
        case "7fff": return 120
        case "ffff": return 128
        default: return -1
    }
}

BEGIN {
    total_lines = 0
    mismatch_count = 0
    skip_count = 0
    error_count = 0
    mlast1_count = 0
    normal_compare_count = 0
    print "开始处理..."
}

FNR == NR {
    # 处理第一个文件 (src.txt)
    if (match($0, /register_data\s*=\s*\[([0-9a-fA-F]{32})\]/, arr)) {
        src_hex[FNR] = arr[1]
    } else {
        src_hex[FNR] = "NOT_FOUND"
        printf "警告：第 %d 行无法从 %s 中提取register_data\n", FNR, ARGV[1] > "/dev/stderr"
    }
    next
}

{
    # 处理第二个文件 (dst.txt)
    line_num = FNR
    total_lines++
    
    # 每处理1000行输出进度
    if (line_num % 1000 == 0) {
        printf "已处理 %d 行...\n", line_num > "/dev/stderr"
    }
    
    # 提取hex2
    if (match($0, /r_memory_data\s*=\s*\[([0-9a-fA-F]{32})\]/, arr)) {
        hex2 = arr[1]
    } else {
        hex2 = "NOT_FOUND"
        printf "警告：第 %d 行无法从 %s 中提取r_memory_data\n", line_num, ARGV[2] > "/dev/stderr"
        next
    }
    
    if (src_hex[line_num] == "NOT_FOUND") {
        next
    }
    
    hex1 = src_hex[line_num]
    
    # 提取mlast和strb
    mlast = ""
    strb = ""
    if (match($0, /mlast\s*=\s*([0-9]+)/, arr)) {
        mlast = arr[1]
    }
    if (match($0, /strb=([0-9a-fA-F]+)/, arr)) {
        strb = arr[1]
    }
    
    # 根据mlast值决定比较策略
    if (mlast == "1") {
        mlast1_count++
        if (strb == "") {
            # mlast=1但没有strb，比较全部128位
            printf "警告：第 %d 行 mlast=1 但无法提取strb值，改为比较全部128位\n", line_num > "/dev/stderr"
            if (hex1 != hex2) {
                printf "❌ 第 %d 行不匹配 (mlast=1但无strb, 比较全部128位)：\n", line_num
                printf "   %s: register_data = [%s]\n", ARGV[1], hex1
                printf "   %s: r_memory_data = [%s]\n", ARGV[2], hex2
                mismatch_count++
            }
        } else {
            bits = get_bits_to_compare(strb)
            if (bits == -1) {
                # 错误的strb值
                printf "⚠️  第 %d 行出现错误的strb值: 0x%s\n", line_num, strb > "/dev/stderr"
                error_count++
            } else if (bits == 0) {
                # strb=0x00，跳过比较
                skip_count++
            } else {
                # 部分比较
                chars_to_compare = bits / 4
                start_pos = 32 - chars_to_compare + 1
                hex1_part = substr(hex1, start_pos)
                hex2_part = substr(hex2, start_pos)
                
                if (hex1_part != hex2_part) {
                    printf "❌ 第 %d 行不匹配 (mlast=1, strb=0x%s, 比较低%d位)：\n", line_num, strb, bits
                    printf "   %s: register_data = [%s] (低%d位: %s)\n", ARGV[1], hex1, bits, hex1_part
                    printf "   %s: r_memory_data = [%s] (低%d位: %s)\n", ARGV[2], hex2, bits, hex2_part
                    mismatch_count++
                }
            }
        }
    } else {
        # mlast不等于1或者没有mlast，比较全部128位
        normal_compare_count++
        if (hex1 != hex2) {
            printf "❌ 第 %d 行不匹配 (比较全部128位)：\n", line_num
            printf "   %s: register_data = [%s]\n", ARGV[1], hex1
            printf "   %s: r_memory_data = [%s]\n", ARGV[2], hex2
            mismatch_count++
        }
    }
}

END {
    print "=========================================="
    print "比较完成！"
    print "=========================================="
    print "比较结果统计："
    printf "✅ 总共处理行数: %d\n", total_lines
    printf "✅ 正常比较行数: %d (mlast≠1或无mlast)\n", normal_compare_count
    printf "✅ mlast=1行数: %d\n", mlast1_count
    printf "✅ 跳过比较行数: %d (strb=0x00)\n", skip_count
    if (error_count > 0) {
        printf "⚠️  错误strb值行数: %d\n", error_count
    }
    if (mismatch_count == 0) {
        print "✅ 所有有效比较都匹配"
        exit_code = 0
    } else {
        printf "❌ 发现 %d 行不匹配\n", mismatch_count
        exit_code = 1
    }
    exit exit_code
}' "$file1" "$file2"














#===========================================================================
#可以处理单速度太慢
#===========================================================================
# #!/bin/bash

# file1="sim_output/src.txt"
# file2="sim_output/dst.txt"

# # 检查文件是否存在
# for file in "$file1" "$file2"; do
#     if [ ! -f "$file" ]; then
#         echo "错误：文件 $file 不存在"
#         exit 1
#     fi
# done

# # 检查文件行数是否相同
# lines1=$(wc -l < "$file1")
# lines2=$(wc -l < "$file2")

# if [ $lines1 -ne $lines2 ]; then
#     echo "错误：文件行数不同，$file1: $lines1 行, $file2: $lines2 行"
#     exit 1
# fi

# echo "开始比较文件中的128位16进制数..."
# echo "总行数: $lines1"
# echo "=========================================="

# # 逐行比较
# mismatch_count=0
# total_lines=0
# skip_count=0
# error_count=0
# mlast1_count=0
# normal_compare_count=0

# # strb值与比较位数的映射关系
# declare -A strb_bits_map=(
#     ["0000"]=0
#     ["00"]=0
#     ["0001"]=8
#     ["01"]=8
#     ["0003"]=16
#     ["03"]=16
#     ["0007"]=24
#     ["07"]=24
#     ["000f"]=32
#     ["0f"]=32
#     ["001f"]=40
#     ["1f"]=40
#     ["003f"]=48
#     ["3f"]=48
#     ["007f"]=56
#     ["7f"]=56
#     ["00ff"]=64
#     ["ff"]=64
#     ["01ff"]=72
#     ["1ff"]=72
#     ["03ff"]=80
#     ["3ff"]=80
#     ["07ff"]=88
#     ["7ff"]=88
#     ["0fff"]=96
#     ["fff"]=96
#     ["1fff"]=104
#     ["3fff"]=112
#     ["7fff"]=120
#     ["ffff"]=128
# )

# for ((i=1; i<=lines1; i++)); do
#     # 每比较1000行输出进度
#     if [ $((i % 1000)) -eq 0 ]; then
#         echo "已处理 $i/$lines1 行..."
#     fi
    
#     # 读取当前行
#     line1=$(sed -n "${i}p" "$file1")
#     line2=$(sed -n "${i}p" "$file2")
    
#     # 从src.txt提取register_data后面的16进制数（在方括号内）
#     hex1=$(echo "$line1" | grep -oP 'register_data\s*=\s*\[\K[0-9a-fA-F]+(?=\])')
    
#     # 从dst.txt提取r_memory_data后面的16进制数（在方括号内）、strb值和mlast值
#     hex2=$(echo "$line2" | grep -oP 'r_memory_data\s*=\s*\[\K[0-9a-fA-F]+(?=\])')
#     strb=$(echo "$line2" | grep -oP 'strb=([0-9a-fA-F]+)' | cut -d= -f2)
#     mlast=$(echo "$line2" | grep -oP 'mlast\s*=\s*(\d+)' | cut -d= -f2 | tr -d ' ')
    
#     # 检查是否成功提取到必要的数据
#     if [ -z "$hex1" ]; then
#         echo "警告：第 $i 行无法从 $file1 中提取register_data的16进制数"
#         echo "       行内容: $line1"
#         continue
#     fi
    
#     if [ -z "$hex2" ]; then
#         echo "警告：第 $i 行无法从 $file2 中提取r_memory_data的16进制数"
#         echo "       行内容: $line2"
#         continue
#     fi
    
#     # 检查16进制数长度是否为32（128位）
#     if [ ${#hex1} -ne 32 ]; then
#         echo "警告：第 $i 行 $file1 的16进制数长度不是32位: $hex1 (长度: ${#hex1})"
#     fi
    
#     if [ ${#hex2} -ne 32 ]; then
#         echo "警告：第 $i 行 $file2 的16进制数长度不是32位: $hex2 (长度: ${#hex2})"
#     fi
    
#     total_lines=$((total_lines + 1))
    
#     # 检查mlast值
#     if [ "$mlast" = "1" ]; then
#         # mlast等于1，需要检查strb并进行部分比较
#         mlast1_count=$((mlast1_count + 1))
        
#         if [ -z "$strb" ]; then
#             echo "警告：第 $i 行 mlast=1 但无法提取strb值，改为比较全部128位"
#             echo "       行内容: $line2"
#             # 没有strb但mlast=1，比较全部128位
#             if [ "$hex1" != "$hex2" ]; then
#                 echo "❌ 第 $i 行不匹配 (mlast=1但无strb, 比较全部128位)："
#                 echo "   $file1: register_data = [$hex1]"
#                 echo "   $file2: r_memory_data = [$hex2]"
#                 mismatch_count=$((mismatch_count + 1))
#             fi
#         elif [ -n "${strb_bits_map[$strb]}" ]; then
#             bits_to_compare=${strb_bits_map[$strb]}
            
#             if [ $bits_to_compare -eq 0 ]; then
#                 # strb=0x00，所有位都无效，跳过比较
#                 skip_count=$((skip_count + 1))
#             else
#                 # 计算需要比较的字符数（每个16进制字符代表4位）
#                 chars_to_compare=$((bits_to_compare / 4))
#                 # 从字符串末尾开始取指定长度的字符
#                 start_pos=$((32 - chars_to_compare))
                
#                 hex1_part="${hex1:$start_pos:$chars_to_compare}"
#                 hex2_part="${hex2:$start_pos:$chars_to_compare}"
                
#                 if [ "$hex1_part" != "$hex2_part" ]; then
#                     echo "❌ 第 $i 行不匹配 (mlast=1, strb=0x$strb, 比较低${bits_to_compare}位)："
#                     echo "   $file1: register_data = [$hex1] (低${bits_to_compare}位: $hex1_part)"
#                     echo "   $file2: r_memory_data = [$hex2] (低${bits_to_compare}位: $hex2_part)"
#                     mismatch_count=$((mismatch_count + 1))
#                 fi
#             fi
#         else
#             # 其他strb值，报错
#             echo "⚠️  第 $i 行出现错误的strb值: 0x$strb"
#             echo "   $file2 行内容: $line2"
#             error_count=$((error_count + 1))
#         fi
#     else
#         # mlast不等于1或者没有mlast，比较全部128位
#         normal_compare_count=$((normal_compare_count + 1))
#         if [ "$hex1" != "$hex2" ]; then
#             echo "❌ 第 $i 行不匹配 (比较全部128位)："
#             echo "   $file1: register_data = [$hex1]"
#             echo "   $file2: r_memory_data = [$hex2]"
#             mismatch_count=$((mismatch_count + 1))
#         fi
#     fi
# done

# echo "=========================================="
# echo "比较完成！"
# echo "=========================================="
# echo "比较结果统计："
# echo "✅ 总共处理行数: $total_lines"
# echo "✅ 正常比较行数: $normal_compare_count (mlast≠1或无mlast)"
# echo "✅ mlast=1行数: $mlast1_count"
# echo "✅ 跳过比较行数: $skip_count (strb=0x00)"
# if [ $error_count -gt 0 ]; then
#     echo "⚠️  错误strb值行数: $error_count"
# fi
# if [ $mismatch_count -eq 0 ]; then
#     echo "✅ 所有有效比较都匹配"
#     exit 0
# else
#     echo "❌ 发现 $mismatch_count 行不匹配"
#     exit 1
# fi