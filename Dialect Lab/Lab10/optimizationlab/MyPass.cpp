#include "MyPass.h"
#include "MyPatterns.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace {
struct RemoveMyAddZeroPass
    : public PassWrapper<RemoveMyAddZeroPass, OperationPass<func::FuncOp>> {

    // 虚拟析构函数
    virtual ~RemoveMyAddZeroPass() = default;

    // 提供命令行参数名称
    StringRef getArgument() const final { return "remove-my-add-zero"; }
    
    // 提供 Pass 的描述
    StringRef getDescription() const final { return "Fold mydialect.addi with zero"; }

    void runOnOperation() override {
        func::FuncOp func = getOperation();
        MLIRContext *ctx = &getContext();

        RewritePatternSet patterns(ctx);
        patterns.add<RemoveAddZeroPattern>(ctx);

        // 应用优化模式
        if (failed(applyPatternsGreedily(func, std::move(patterns))))
            signalPassFailure();
    }
};
} // namespace

// Pass 的创建和注册函数
std::unique_ptr<Pass> mlir::createRemoveMyAddZeroPass() {
    return std::make_unique<RemoveMyAddZeroPass>();
}

void mlir::registerRemoveMyAddZeroPass() {
    PassRegistration<RemoveMyAddZeroPass>();
}