#include "MemoryPass.h"
#include "MemoryDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Arithmetic/IR/ArithmeticOps.h"

using namespace mlir;

namespace memory {

namespace {

struct MemoryToMemRefPass : public PassWrapper<MemoryToMemRefPass, OperationPass<ModuleOp>> {
  
  StringRef getArgument() const final {
    return "convert-memory-to-memref";
  }
  
  StringRef getDescription() const final {
    return "Convert memory dialect operations to standard memref operations";
  }
  
  void runOnOperation() override {
    // 收集需要转换的操作
    SmallVector<CreateMatrixOp, 4> createOps;
    SmallVector<SetElementOp, 4> setOps;  
    SmallVector<GetElementOp, 4> getOps;
    SmallVector<PrintMatrixOp, 4> printOps;
    
    getOperation().walk([&](Operation *op) {
      if (auto createOp = dyn_cast<CreateMatrixOp>(op))
        createOps.push_back(createOp);
      else if (auto setOp = dyn_cast<SetElementOp>(op))
        setOps.push_back(setOp);
      else if (auto getOp = dyn_cast<GetElementOp>(op))
        getOps.push_back(getOp);
      else if (auto printOp = dyn_cast<PrintMatrixOp>(op))
        printOps.push_back(printOp);
    });
    
    // 转换 CreateMatrixOp -> memref.alloc
    for (auto op : createOps) {
      OpBuilder builder(op);
      
      auto resultType = op->getResult(0).getType().cast<MemRefType>();
      auto operands = op->getOperands();
      
      auto allocOp = builder.create<memref::AllocOp>(
          op.getLoc(), resultType, operands);
      
      op->getResult(0).replaceAllUsesWith(allocOp.getResult());
      op->erase();
      
      llvm::outs() << "Converted memory.create_matrix to memref.alloc\n";
    }
    
    // 转换 SetElementOp -> memref.store
    for (auto op : setOps) {
      OpBuilder builder(op);
      auto operands = op->getOperands();
      
      Value memref = operands[0];
      Value i = operands[1]; 
      Value j = operands[2];
      Value value = operands[3];
      
      builder.create<memref::StoreOp>(
          op.getLoc(), value, memref, ValueRange{i, j});
      
      op->erase();
      llvm::outs() << "Converted memory.set to memref.store\n";
    }
    
    // 转换 GetElementOp -> memref.load
    for (auto op : getOps) {
      OpBuilder builder(op);
      auto operands = op->getOperands();
      
      Value memref = operands[0];
      Value i = operands[1];
      Value j = operands[2];
      
      auto loadOp = builder.create<memref::LoadOp>(
          op.getLoc(), memref, ValueRange{i, j});
      
      op->getResult(0).replaceAllUsesWith(loadOp.getResult());
      op->erase();
      
      llvm::outs() << "Converted memory.get to memref.load\n";
    }
    
    // 删除 PrintMatrixOp
    for (auto op : printOps) {
      llvm::outs() << "Removed memory.print (debug operation)\n";
      op->erase();
    }
  }
};

} // namespace

std::unique_ptr<Pass> createMemoryToMemRefPass() {
  return std::make_unique<MemoryToMemRefPass>();
}

} // namespace memory