#include "SimpleDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace simple {

SimpleDialect::SimpleDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<SimpleDialect>()) {
  initialize();
}

void SimpleDialect::initialize() {
  addOperations<HelloOp, PrintOp, AddOp>();
}

} // namespace simple
