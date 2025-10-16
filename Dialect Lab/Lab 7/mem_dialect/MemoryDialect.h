#ifndef MEMORY_DIALECT_H
#define MEMORY_DIALECT_H

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"

namespace memory {

/**
 * MemoryDialect 类
 * 管理内存相关的操作
 */
class MemoryDialect : public mlir::Dialect {
public:
  explicit MemoryDialect(mlir::MLIRContext *ctx);
  static llvm::StringRef getDialectNamespace() { return "memory"; }
  void initialize();
};

/**
 * CreateMatrixOp - 创建矩阵操作
 * 语法：%matrix = memory.create_matrix rows, cols : memref<RxCxf32>
 */
class CreateMatrixOp : public mlir::Op<CreateMatrixOp, mlir::OpTrait::OneResult> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.create_matrix"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value rows, mlir::Value cols) {
    auto f32Type = builder.getF32Type();
    auto memrefType = mlir::MemRefType::get({-1, -1}, f32Type);
    
    state.addOperands({rows, cols});
    state.addTypes(memrefType);
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    auto results = this->getOperation()->getResults();
    p << " " << operands[0] << ", " << operands[1] 
      << " : " << results[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand rows, cols;
    mlir::Type resultType;
    
    if (parser.parseOperand(rows) ||
        parser.parseComma() ||
        parser.parseOperand(cols) ||
        parser.parseColon() ||
        parser.parseType(resultType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    if (parser.resolveOperands({rows, cols}, indexType, result.operands))
      return mlir::failure();
    
    result.addTypes(resultType);
    return mlir::success();
  }
};

/**
 * SetElementOp - 设置矩阵元素操作
 * 语法：memory.set %matrix[%i, %j] = %value : memref<RxCxf32>
 */
class SetElementOp : public mlir::Op<SetElementOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.set"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref, mlir::ValueRange indices, mlir::Value value) {
    state.addOperands({memref});
    state.addOperands(indices);
    state.addOperands({value});
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    p << " " << operands[0] << "["
      << operands[1] << ", " << operands[2] << "] = " 
      << operands[3] << " : " << operands[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref, i, j, value;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseLSquare() ||
        parser.parseOperand(i) ||
        parser.parseComma() ||
        parser.parseOperand(j) ||
        parser.parseRSquare() ||
        parser.parseEqual() ||
        parser.parseOperand(value) ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    auto f32Type = parser.getBuilder().getF32Type();
    
    if (parser.resolveOperand(memref, memrefType, result.operands) ||
        parser.resolveOperands({i, j}, indexType, result.operands) ||
        parser.resolveOperand(value, f32Type, result.operands))
      return mlir::failure();
    
    return mlir::success();
  }
};

/**
 * GetElementOp - 获取矩阵元素操作
 * 语法：%value = memory.get %matrix[%i, %j] : memref<RxCxf32>
 */
class GetElementOp : public mlir::Op<GetElementOp, mlir::OpTrait::OneResult> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.get"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref, mlir::ValueRange indices) {
    state.addOperands({memref});
    state.addOperands(indices);
    state.addTypes(builder.getF32Type());
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    p << " " << operands[0] << "["
      << operands[1] << ", " << operands[2] << "] : " 
      << operands[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref, i, j;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseLSquare() ||
        parser.parseOperand(i) ||
        parser.parseComma() ||
        parser.parseOperand(j) ||
        parser.parseRSquare() ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    
    if (parser.resolveOperand(memref, memrefType, result.operands) ||
        parser.resolveOperands({i, j}, indexType, result.operands))
      return mlir::failure();
    
    result.addTypes(parser.getBuilder().getF32Type());
    return mlir::success();
  }
};

/**
 * PrintMatrixOp - 打印矩阵操作
 * 语法：memory.print %matrix : memref<RxCxf32>
 */
class PrintMatrixOp : public mlir::Op<PrintMatrixOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.print"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref) {
    state.addOperands({memref});
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    p << " " << this->getOperation()->getOperand(0) 
      << " : " << this->getOperation()->getOperand(0).getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    if (parser.resolveOperand(memref, memrefType, result.operands))
      return mlir::failure();
    
    return mlir::success();
  }
};

} // namespace memory

#endif