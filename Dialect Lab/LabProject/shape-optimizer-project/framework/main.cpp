/**
 * main.cpp - 最简版本
 */

#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Pass/PassRegistry.h"

// 只注册必要的Dialects
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"

// 我们的Pass
#include "ShapeOptimizerPass.h"

using namespace mlir;

int main(int argc, char **argv) {
    // 最简化的注册 - 避免死锁
    DialectRegistry registry;
    registry.insert<func::FuncDialect>();
    registry.insert<arith::ArithDialect>();
    registry.insert<tensor::TensorDialect>();
    
    // 只注册我们的Pass
    PassRegistration<ShapeComputeOptimizerPass>();
    
    return asMainReturnCode(
        MlirOptMain(argc, argv, "Shape Optimizer\n", registry));
}