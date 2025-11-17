#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arithmetic/IR/Arithmetic.h"  // 注意：LLVM 15 中是 Arithmetic 不是 Arith
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

int main() {
    // 创建MLIR上下文
    MLIRContext context;
    context.getOrLoadDialect<func::FuncDialect>();
    context.getOrLoadDialect<arith::ArithmeticDialect>();  // 注意：使用 ArithmeticDialect
    
    // 创建模块
    OpBuilder builder(&context);
    auto module = ModuleOp::create(builder.getUnknownLoc());
    
    // 在模块内创建函数
    builder.setInsertionPointToEnd(module.getBody());
    
    // 定义函数类型：(f32, f32) -> f32
    auto funcType = builder.getFunctionType({builder.getF32Type(), builder.getF32Type()}, 
                                           builder.getF32Type());
    
    // 创建函数
    auto func = builder.create<func::FuncOp>(builder.getUnknownLoc(), "add", funcType);
    
    // 创建函数体
    Block* entryBlock = func.addEntryBlock();
    builder.setInsertionPointToStart(entryBlock);
    
    // 获取参数
    auto arg0 = entryBlock->getArgument(0);
    auto arg1 = entryBlock->getArgument(1);
    
    // 创建加法操作
    auto sum = builder.create<arith::AddFOp>(builder.getUnknownLoc(), arg0, arg1);
    
    // 创建返回操作
    builder.create<func::ReturnOp>(builder.getUnknownLoc(), sum.getResult());
    
    // 打印生成的IR
    module.print(llvm::outs());
    
    return 0;
}