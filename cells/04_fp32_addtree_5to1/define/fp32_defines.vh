`ifndef FP32_DEFINES_VH
`define FP32_DEFINES_VH

// 引用全局定义
`include "../../global_defines.v"

// 对齐阶段参数
`define GUARD_BITS 6 // G, R, S bits

// 对齐后的尾数宽度 (隐藏位 + 尾数 + GRS)
`define ALIGNED_MANT_WIDTH (1+ `FP32_MANT_WIDTH + `GUARD_BITS)// 1代表隐藏位

`define FULL_SUM_WIDTH 31

`define NORM_IN_WIDTH `FULL_SUM_WIDTH 

`endif
