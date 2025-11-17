#include "MemoryDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace memory {

/**
 * MemoryDialect 构造函数
 */
MemoryDialect::MemoryDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<MemoryDialect>()) {
  initialize();
}

/**
 * 注册所有内存操作
 */
void MemoryDialect::initialize() {
  addOperations<CreateMatrixOp, SetElementOp, GetElementOp, PrintMatrixOp>();
}

} // namespace memory