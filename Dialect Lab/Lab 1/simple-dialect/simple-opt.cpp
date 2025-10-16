#include "SimpleDialect.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  registry.insert<simple::SimpleDialect>();
  
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Simple dialect test\n", registry));
}
