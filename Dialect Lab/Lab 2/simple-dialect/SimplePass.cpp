#include "SimplePass.h"
#include "SimpleDialect.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace simple {

namespace {

struct SimpleToArithPass : public PassWrapper<SimpleToArithPass, OperationPass<ModuleOp>> {
  
  StringRef getArgument() const final {
    return "convert-simple-to-arith";
  }
  
  StringRef getDescription() const final {
    return "Convert simple dialect operations to arith dialect";
  }
  
  void runOnOperation() override {
    // 收集所有需要替换的操作
    SmallVector<AddOp, 4> addOps;
    
    getOperation().walk([&](AddOp op) {
      addOps.push_back(op);
    });
    
    // 替换操作
    for (auto op : addOps) {
      OpBuilder builder(op);
      auto operands = op->getOperands();
      auto resultType = op->getResult(0).getType();
      
      // 创建 arith.addi
      OperationState state(op.getLoc(), "arith.addi");
      state.addOperands({operands[0], operands[1]});
      state.addTypes(resultType);
      
      Operation *newOp = builder.create(state);
      
      // 替换所有使用
      op->getResult(0).replaceAllUsesWith(newOp->getResult(0));
      
      // 删除原操作
      op->erase();
      
      llvm::outs() << "Converted simple.add to arith.addi\n";
    }
  }
};

} // namespace

std::unique_ptr<Pass> createSimpleToArithPass() {
  return std::make_unique<SimpleToArithPass>();
}

} // namespace simple
