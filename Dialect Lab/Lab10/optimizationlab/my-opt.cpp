#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "MyPass.h"

int main(int argc, char **argv) {
    mlir::DialectRegistry registry;

    // 只注册标准方言
    registry.insert<mlir::arith::ArithDialect, 
                    mlir::func::FuncDialect>();

    // 注册我们的自定义 Pass
    mlir::registerRemoveMyAddZeroPass();

    return mlir::asMainReturnCode(
        mlir::MlirOptMain(argc, argv, "My Pass Tool\n", registry));
}