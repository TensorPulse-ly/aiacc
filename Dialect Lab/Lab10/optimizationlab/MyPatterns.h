#ifndef MY_PATTERNS_H
#define MY_PATTERNS_H

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

// 使用标准的 arith.addi 操作，避免自定义操作的复杂性
struct RemoveAddZeroPattern : public mlir::OpRewritePattern<mlir::arith::AddIOp> {
  using OpRewritePattern<mlir::arith::AddIOp>::OpRewritePattern;

  mlir::LogicalResult matchAndRewrite(mlir::arith::AddIOp op,
                                mlir::PatternRewriter &rewriter) const override {
    // 获取操作数
    mlir::Value lhs = op.getLhs();
    mlir::Value rhs = op.getRhs();

    // 检查是否为零常量的辅助函数
    auto isZeroConst = [](mlir::Value val) -> bool {
      if (auto cst = val.getDefiningOp<mlir::arith::ConstantOp>()) {
        if (auto attr = mlir::dyn_cast<mlir::IntegerAttr>(cst.getValue()))
          return attr.getValue().isZero();
      }
      return false;
    };

    // 如果右操作数是 0，替换为左操作数
    if (isZeroConst(rhs)) {
      rewriter.replaceOp(op, lhs);
      return mlir::success();
    }

    // 如果左操作数是 0，替换为右操作数
    if (isZeroConst(lhs)) {
      rewriter.replaceOp(op, rhs);
      return mlir::success();
    }

    // 没有匹配，返回失败
    return mlir::failure();
  }
};

#endif // MY_PATTERNS_H