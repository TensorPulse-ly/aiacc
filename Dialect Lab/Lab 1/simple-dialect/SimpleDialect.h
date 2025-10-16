#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"

namespace simple {

class SimpleDialect : public mlir::Dialect {
public:
  explicit SimpleDialect(mlir::MLIRContext *ctx);
  static llvm::StringRef getDialectNamespace() { return "simple"; }
  void initialize();
};

class HelloOp : public mlir::Op<HelloOp, mlir::OpTrait::ZeroOperands, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.hello"; }
  static void build(mlir::OpBuilder &, mlir::OperationState &state) {}
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  // 添加打印方法
  void print(mlir::OpAsmPrinter &p) {
    p << " ";
  }
  
  // 添加解析方法
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, mlir::OperationState &result) {
    return mlir::success();
  }
};

} // namespace simple

#endif
