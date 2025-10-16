#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Operation.h"

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
  
  void print(mlir::OpAsmPrinter &p) {
    p << " ";
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, mlir::OperationState &result) {
    return mlir::success();
  }
};

class PrintOp : public mlir::Op<PrintOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.print"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state, 
                    llvm::StringRef message) {
    state.addAttribute("message", builder.getStringAttr(message));
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    static llvm::StringRef attrNames[] = {"message"};
    return llvm::ArrayRef<llvm::StringRef>(attrNames);
  }
  
  void print(mlir::OpAsmPrinter &p) {
    p << " \"" << (*this)->getAttr("message") << "\"";
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, mlir::OperationState &result) {
    std::string message;
    if (parser.parseString(&message))
      return mlir::failure();
    result.addAttribute("message", parser.getBuilder().getStringAttr(message));
    return mlir::success();
  }
};

class AddOp : public mlir::Op<AddOp, mlir::OpTrait::SameOperandsAndResultType> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.add"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value lhs, mlir::Value rhs) {
    state.addOperands({lhs, rhs});
    state.addTypes(lhs.getType());
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    auto results = this->getOperation()->getResults();
    p << " " << operands[0] << ", " << operands[1] << " : " << results[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand lhs, rhs;
    mlir::Type type;
    
    if (parser.parseOperand(lhs) ||
        parser.parseComma() ||
        parser.parseOperand(rhs) ||
        parser.parseColon() ||
        parser.parseType(type))
      return mlir::failure();
      
    if (parser.resolveOperands({lhs, rhs}, type, result.operands))
      return mlir::failure();
      
    result.addTypes(type);
    return mlir::success();
  }
};

} // namespace simple

#endif
