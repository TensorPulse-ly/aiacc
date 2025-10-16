#include "mlir/Dialect/Arithmetic/IR/ArithmeticOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "MemoryDialect.h"
#include "MemoryPass.h"

int main(int argc, char **argv) {
  // Register Dialect
  mlir::DialectRegistry registry;

  // Standard Dialects - 修正类名
  registry.insert<mlir::func::FuncDialect>();
  registry.insert<mlir::arith::ArithmeticDialect>();    // 正确的类名！
  registry.insert<mlir::memref::MemRefDialect>();

  // Our custom Dialect
  registry.insert<memory::MemoryDialect>();

  // Register custom Pass
  mlir::registerPass([]() -> std::unique_ptr<mlir::Pass> {
    return memory::createMemoryToMemRefPass();
  });

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Memory dialect test tool\n", registry));
}