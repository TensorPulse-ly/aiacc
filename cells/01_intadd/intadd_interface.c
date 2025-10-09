#include <stdint.h>
#include <stdio.h>

void add32_128bit(
    unsigned long long src0_high, unsigned long long src0_low,
    unsigned long long src1_high, unsigned long long src1_low,
    int sign_s0, int sign_s1,
    unsigned long long* dst_high, unsigned long long* dst_low,
    unsigned long long* st_high, unsigned long long* st_low
) {
    uint32_t a[4], b[4], res[4];
    int i;
    // 拆分输入
    a[0] = (uint32_t)(src0_low);
    a[1] = (uint32_t)(src0_low >> 32);
    a[2] = (uint32_t)(src0_high);
    a[3] = (uint32_t)(src0_high >> 32);
    b[0] = (uint32_t)(src1_low);
    b[1] = (uint32_t)(src1_low >> 32);
    b[2] = (uint32_t)(src1_high);
    b[3] = (uint32_t)(src1_high >> 32);

    // 初始化状态寄存器
    *st_high = 0;
    *st_low = 0;

    for (i = 0; i < 4; ++i) {
        // 独立符号扩展
        int64_t s0 = sign_s0 ? (int32_t)a[i] : (uint64_t)a[i];
        int64_t s1 = sign_s1 ? (int32_t)b[i] : (uint64_t)b[i];
        int64_t sum = s0 + s1;
        
        // 处理溢出
        if (sign_s0 || sign_s1) {
            if ((s0 > 0 && s1 > 0 && sum < 0) || 
                (s0 < 0 && s1 < 0 && sum >= 0)) {
                res[i] = 0x7FFFFFFF; // 饱和处理
            } else {
                res[i] = (uint32_t)sum;
            }
        } else {
            res[i] = (uint32_t)sum;
        }
        
        // 精确的32位比较逻辑
        int gt = 0, eq = 0, ls = 0;
        if (sign_s0 || sign_s1) {
            // 有符号比较使用32位直接比较
            int32_t signed_a = (int32_t)a[i];
            int32_t signed_b = (int32_t)b[i];
            if (signed_a > signed_b) gt = 1;
            else if (signed_a < signed_b) ls = 1;
            else eq = 1;
        } else {
            // 无符号比较
            if (a[i] > b[i]) gt = 1;
            else if (a[i] < b[i]) ls = 1;
            else eq = 1;
        }
        
        // 状态位设置 - 严格按组放置
        uint64_t status_bits = 0;
        status_bits |= ((uint64_t)gt << 2);
        status_bits |= ((uint64_t)eq << 1);
        status_bits |= ((uint64_t)ls << 0);
        
        // 根据组号放置状态位
        switch(i) {
            case 0: *st_low  |= (status_bits << 0);  break;  // 位2:0
            case 1: *st_low  |= (status_bits << 32); break;  // 位34:32
            case 2: *st_high |= (status_bits << 0);  break;  // 位66:64
            case 3: *st_high |= (status_bits << 32); break;  // 位98:96
        }
    }
    
    // 拼回128位结果
    *dst_low  = ((uint64_t)res[1] << 32) | res[0];
    *dst_high = ((uint64_t)res[3] << 32) | res[2];
}

// add8_128bit 适配当前的add8.v实现
// 更直接的位操作实现，确保精确匹配Verilog行为
// 8位加法接口函数 - 完全匹配Verilog行为的实现
extern void add8_128bit(
    unsigned long long src0_high, unsigned long long src0_low,
    unsigned long long src1_high, unsigned long long src1_low,
    unsigned long long src2_high, unsigned long long src2_low,
    int sign_s0, int sign_s1, int sign_s2,
    unsigned long long* dst0_high, unsigned long long* dst0_low,
    unsigned long long* dst1_high, unsigned long long* dst1_low,
    unsigned long long* st_high, unsigned long long* st_low
) {
    // add8模块不产生状态信息，设置状态寄存器为0
    *st_high = 0;
    *st_low = 0;
    // 初始化输出结果
    *dst0_low = 0;
    *dst0_high = 0;
    *dst1_low = 0;
    *dst1_high = 0;
    
    // 处理32个4位块
    for (int i = 0; i < 32; ++i) {
        // 从128位输入中提取32组4位值 - 完全匹配Verilog的位索引
        uint8_t u0 = 0, u1 = 0, u2 = 0;
        
        if (i < 16) {
            // 低64位 (bits 63-0)
            u0 = (src0_low >> (i*4)) & 0x0F;
            u1 = (src1_low >> (i*4)) & 0x0F;
            u2 = (src2_low >> (i*4)) & 0x0F;
        } else {
            // 高64位 (bits 127-64)
            u0 = (src0_high >> ((i-16)*4)) & 0x0F;
            u1 = (src1_high >> ((i-16)*4)) & 0x0F;
            u2 = (src2_high >> ((i-16)*4)) & 0x0F;
        }
        
        // 将u2和u1连接成8位值
        uint8_t concat_val = (u2 << 4) | u1;
        
        // 为s0_val创建9位有符号值，精确模拟Verilog的位操作
        int16_t s0_val;  // 使用16位来存储9位值
        if (sign_s0) {
            // 有符号: {s0_signed[7], s0_signed}，其中s0_signed = {{4{u0[3]}}, u0}
            // 精确实现Verilog的{{4{u0[3]}}, u0}位操作
            uint8_t s0_signed = (u0 & 0x8) ? (u0 | 0xF0) : u0; // 符号扩展到8位
            // 转换为有符号8位并提升到16位，保持符号位
            s0_val = (int16_t)(int8_t)s0_signed;
        } else {
            // 无符号: {1'b0, s0_unsigned}，其中s0_unsigned = {4'b0000, u0}
            s0_val = u0;  // 低4位为u0，其余为0
        }
        
        // 为add_val创建9位有符号值，精确模拟Verilog的位操作
        int16_t add_val;
        if (sign_s2) {
            // 有符号: {val_signed[7], val_signed}，其中val_signed = {concat_val[7], concat_val[6:0]}
            // 在Verilog中，这实际上就是保持concat_val不变并进行符号扩展
            add_val = (int16_t)(int8_t)concat_val;
        } else {
            // 无符号: {1'b0, val_unsigned}，其中val_unsigned = concat_val
            add_val = concat_val;  // 直接使用8位值
        }
        
        // 计算有符号和，使用16位精度
        int16_t sum_signed = s0_val + add_val;
        
        // 处理溢出或下溢 - 精确匹配Verilog的条件
        uint8_t sum_clipped;
        if ((s0_val > 0) && (add_val > 0) && (sum_signed < 0)) {
            // 正溢出
            sum_clipped = 0xFF;
        } else if ((s0_val < 0) && (add_val < 0) && (sum_signed < -128)) {
            // 负溢出
            sum_clipped = 0xFF;
        } else {
            // 无溢出，直接取低8位
            sum_clipped = sum_signed & 0xFF;
        }
        
        // 提取低4位和高4位
        uint8_t low_4bits = sum_clipped & 0x0F;
        uint8_t high_4bits = (sum_clipped >> 4) & 0x0F;
        
        // 将结果写回对应的位置
        if (i < 16) {
            // 写入低64位
            *dst0_low |= (unsigned long long)low_4bits << (i*4);
            *dst1_low |= (unsigned long long)high_4bits << (i*4);
        } else {
            // 写入高64位
            *dst0_high |= (unsigned long long)low_4bits << ((i-16)*4);
            *dst1_high |= (unsigned long long)high_4bits << ((i-16)*4);
        }
    }
}
