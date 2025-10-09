#include <stdio.h>
#include <stdint.h>

//==============================================================================
// 整数转换DPI-C函数 - 用于验证int_to_int模块
//==============================================================================
uint32_t dpi_int_to_int_convert(
    uint32_t in_data,
    uint8_t src_prec,    // 0=16bit, 1=32bit
    uint8_t dst_prec,    // 0=16bit, 1=32bit  
    uint8_t src_signed,  // 0=unsigned, 1=signed
    uint8_t dst_signed,  // 0=unsigned, 1=signed
    uint8_t src_pos,     // 0=low, 1=high (for 16bit src)
    uint8_t dst_pos      // 0=low, 1=high (for 16bit dst)
) {
    // 子字并行模式检测 (16bit → 16bit)
    int subword_parallel = (src_prec == 0) && (dst_prec == 0);
    
    if (subword_parallel) {
        // 子字并行模式：同时处理高低16位
        uint16_t src_low = in_data & 0xFFFF;
        uint16_t src_high = (in_data >> 16) & 0xFFFF;
        uint16_t dst_low, dst_high;
        
        // 转换低16位
        if (src_signed) {
            if (dst_signed) {
                // 有符号16位到有符号16位
                dst_low = (int16_t)src_low;
            } else {
                // 有符号16位到无符号16位
                if ((int16_t)src_low < 0) dst_low = 0;
                else if (src_low > 0xFFFF) dst_low = 0xFFFF;
                else dst_low = src_low;
            }
        } else {
            if (dst_signed) {
                // 无符号16位到有符号16位
                if (src_low > 0x7FFF) dst_low = 0x7FFF;
                else dst_low = src_low;
            } else {
                // 无符号16位到无符号16位
                dst_low = src_low;
            }
        }
        
        // 转换高16位
        if (src_signed) {
            if (dst_signed) {
                // 有符号16位到有符号16位
                dst_high = (int16_t)src_high;
            } else {
                // 有符号16位到无符号16位
                if ((int16_t)src_high < 0) dst_high = 0;
                else if (src_high > 0xFFFF) dst_high = 0xFFFF;
                else dst_high = src_high;
            }
        } else {
            if (dst_signed) {
                // 无符号16位到有符号16位
                if (src_high > 0x7FFF) dst_high = 0x7FFF;
                else dst_high = src_high;
            } else {
                // 无符号16位到无符号16位
                dst_high = src_high;
            }
        }
        
        // 组合结果
        return ((uint32_t)dst_high << 16) | dst_low;
    }
    
    // 提取源数据
    uint32_t src_data;
    if (src_prec == 0) { // 16bit source
        uint16_t src_16 = (src_pos == 0) ? (in_data & 0xFFFF) : ((in_data >> 16) & 0xFFFF);
        
        // 扩展到32位
        if (src_signed) {
            // 符号扩展
            src_data = (int16_t)src_16;
        } else {
            // 零扩展
            src_data = src_16;
        }
    } else { // 32bit source
        src_data = in_data;
    }
    
    // 目标转换
    uint32_t result;
    if (dst_prec == 1) { // 32bit destination
        if (dst_signed) {
            // 目标有符号
            if (src_signed) {
                // 有符号到有符号
                result = (int32_t)src_data;
            } else {
                // 无符号到有符号
                if (src_data > 0x7FFFFFFF) result = 0x7FFFFFFF;
                else result = src_data;
            }
        } else {
            // 目标无符号
            if (src_signed) {
                // 有符号到无符号
                if ((int32_t)src_data < 0) result = 0;
                else result = src_data;
            } else {
                // 无符号到无符号
                result = src_data;
            }
        }
    } else { // 16bit destination
        uint16_t dst_16;
        
        if (dst_signed) {
            // 目标有符号16位
            if (src_signed) {
                // 有符号到有符号
                int32_t signed_src = (int32_t)src_data;
                if (signed_src > 32767) dst_16 = 0x7FFF;
                else if (signed_src < -32768) dst_16 = 0x8000;
                else dst_16 = signed_src & 0xFFFF;
            } else {
                // 无符号到有符号
                if (src_data > 32767) dst_16 = 0x7FFF;
                else dst_16 = src_data & 0xFFFF;
            }
        } else {
            // 目标无符号16位
            if (src_signed) {
                // 有符号到无符号
                if ((int32_t)src_data < 0) dst_16 = 0;
                else if (src_data > 65535) dst_16 = 0xFFFF;
                else dst_16 = src_data & 0xFFFF;
            } else {
                // 无符号到无符号
                if (src_data > 65535) dst_16 = 0xFFFF;
                else dst_16 = src_data & 0xFFFF;
            }
        }
        
        // 根据目标位置组装结果
        if (dst_pos == 0) {
            // 低位 - 保持高位不变
            result = (uint32_t)dst_16;
        } else {
            // 高位 - 保持低位不变  
            result = (uint32_t)dst_16 << 16;
        }
    }
    
    return result;
}
