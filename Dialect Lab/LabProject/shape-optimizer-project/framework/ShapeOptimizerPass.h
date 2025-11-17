/**
 * ShapeOptimizerPass.h - 学生实现骨架
 * 
 * 在这个文件中实现你的形状计算优化Pass
 * 
 * 实现提示：
 * 1. 从简单的算术折叠开始（arith.addi, arith.muli等）
 * 2. 然后实现张量形状推导（tensor.empty）
 * 3. 最后处理控制流优化（scf.if）
 */

#ifndef SHAPE_OPTIMIZER_PASS_H
#define SHAPE_OPTIMIZER_PASS_H

#include "mlir/Pass/Pass.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Builders.h"

// Dialect headers
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"

// Utilities
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include <optional>

namespace mlir {

class ShapeComputeOptimizerPass : public PassWrapper<ShapeComputeOptimizerPass, OperationPass<ModuleOp>> {
public:
    // Required for LLVM 20.x
    MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ShapeComputeOptimizerPass)
    
    StringRef getArgument() const final { 
        return "shape-optimizer"; 
    }
    
    StringRef getDescription() const final { 
        return "Optimize ML shape computations by folding constants and deriving static shapes"; 
    }

    void runOnOperation() override {
        ModuleOp module = getOperation();
        
        // TODO: 删除这个占位实现，开始你的优化逻辑
        llvm::outs() << "ShapeOptimizerPass: 请实现优化逻辑！\n";
        
        // 步骤提示：
        // 1. 收集模块中的所有常量
        // 2. 实现算术常量折叠
        // 3. 推导静态张量形状
        // 4. 简化控制流
        // 5. 更新函数签名
        
        // Phase 1: 收集常量
        // DenseMap<Value, Attribute> constantMap;
        // collectConstants(module, constantMap);
        
        // Phase 2: 算术折叠（迭代进行，直到没有更多优化）
        // bool changed = true;
        // while (changed) {
        //     changed = foldArithmeticOperations(module, constantMap);
        //     if (changed) {
        //         constantMap.clear();
        //         collectConstants(module, constantMap);
        //     }
        // }
        
        // Phase 3: 静态形状推导
        // propagateStaticShapes(module, constantMap);
        
        // Phase 4: 控制流简化
        // simplifyControlFlow(module, constantMap);
    }

private:
    // TODO: 实现这些辅助方法
    
    /**
     * 收集模块中的所有常量
     * 提示：使用 module->walk() 遍历所有 arith::ConstantOp
     */
    void collectConstants(ModuleOp module, DenseMap<Value, Attribute> &constantMap) {
        // TODO: 实现常量收集
        // 提示：
        // module->walk([&](arith::ConstantOp constOp) {
        //     constantMap[constOp.getResult()] = constOp.getValue();
        // });
    }
    
    /**
     * 折叠算术运算
     * 返回：是否有任何更改
     */
    bool foldArithmeticOperations(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        // TODO: 实现算术折叠
        // 需要处理：arith::AddIOp, arith::MulIOp, arith::SubIOp, arith::DivSIOp
        
        // 提示代码结构：
        // SmallVector<Operation*, 4> toErase;
        // 
        // module->walk([&](arith::AddIOp addOp) {
        //     auto lhsConst = getConstantIntValue(addOp.getLhs(), constantMap);
        //     auto rhsConst = getConstantIntValue(addOp.getRhs(), constantMap);
        //     
        //     if (lhsConst && rhsConst) {
        //         // 创建新的常量，替换原操作
        //         // ...
        //         toErase.push_back(addOp);
        //     }
        // });
        // 
        // // 删除已优化的操作
        // for (Operation *op : toErase) {
        //     op->erase();
        // }
        // 
        // return !toErase.empty();
        
        return false; // 暂时返回false
    }
    
    /**
     * 推导静态张量形状
     */
    void propagateStaticShapes(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        // TODO: 实现静态形状推导
        // 主要处理：tensor::EmptyOp
        
        // 提示：
        // 1. 遍历所有 tensor::EmptyOp
        // 2. 检查其动态维度是否都是常量
        // 3. 如果是，创建静态形状的新tensor类型
        // 4. 替换原操作
    }
    
    /**
     * 简化控制流
     */
    void simplifyControlFlow(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        // TODO: 实现控制流简化
        // 主要处理：scf::IfOp with constant conditions
        
        // 提示：
        // 1. 遍历所有 scf::IfOp
        // 2. 检查条件是否为常量布尔值
        // 3. 如果是，选择对应分支，移除if操作
    }
    
    // 辅助方法（可以直接提供给学生）
    
    /**
     * 从常量映射中获取整数值
     */
    std::optional<int64_t> getConstantIntValue(Value value, const DenseMap<Value, Attribute> &constantMap) {
        auto it = constantMap.find(value);
        if (it == constantMap.end()) 
            return std::nullopt;
        
        if (auto intAttr = llvm::dyn_cast<IntegerAttr>(it->second)) {
            return intAttr.getValue().getSExtValue();
        }
        return std::nullopt;
    }
    
    /**
     * 从常量映射中获取布尔值
     */
    std::optional<bool> getConstantBoolValue(Value value, const DenseMap<Value, Attribute> &constantMap) {
        auto it = constantMap.find(value);
        if (it == constantMap.end()) 
            return std::nullopt;
        
        if (auto boolAttr = llvm::dyn_cast<BoolAttr>(it->second)) {
            return boolAttr.getValue();
        }
        
        if (auto intAttr = llvm::dyn_cast<IntegerAttr>(it->second)) {
            if (intAttr.getType().isInteger(1)) {
                return intAttr.getValue().getBoolValue();
            }
        }
        
        return std::nullopt;
    }
    
    /**
     * 创建整数常量
     */
    arith::ConstantOp createIntConstant(OpBuilder &builder, Location loc, int64_t value, Type type) {
        auto attr = IntegerAttr::get(type, value);
        return builder.create<arith::ConstantOp>(loc, attr);
    }
};

} // namespace mlir

#endif // SHAPE_OPTIMIZER_PASS_H