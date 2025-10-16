#ifndef MY_PASS_H
#define MY_PASS_H

#include <memory>

namespace mlir {
class Pass; // 前向声明

// 创建 Pass 的函数
std::unique_ptr<Pass> createRemoveMyAddZeroPass();

// 用于在 my-opt 主程序中注册 Pass 的函数
void registerRemoveMyAddZeroPass();
} // namespace mlir

#endif // MY_PASS_H