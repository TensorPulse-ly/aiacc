## Windows下Lab的实现

### 	1.编译工具链

​		Windows下使用Visual Studio的工具链来编译LLVM环境。

​		**第一步：安装Visual Studio**

​				1.下载 Visual Studio Community 2022

​				2.安装时选择 "Desktop development with C++" 工作负载

​				3.确保包含 CMake 工具

​		**第二步：下载和编译LLVM**

​			我这里的版本用的是llvm22.0

```cmd
REM 创建工作目录
mkdir C:\llvm-build
cd C:\llvm-build
REM 克隆 LLVM 项目（这会需要一些时间）
git clone https://github.com/llvm/llvm-project.git
cd llvm-project
REM 创建构建目录
mkdir build
cd build
```

​		**第三步：用 MSVC 配置和构建**

​		注意，cmd要用Developer Command Prompt for VS 2022，这样就会用cl来进行编译。

```cmd
REM 配置 CMake（只构建必要的组件以节省时间）
cmake -G "Visual Studio 17 2022" -A x64 ^
  -DLLVM_ENABLE_PROJECTS="mlir" ^
  -DLLVM_BUILD_EXAMPLES=OFF ^
  -DLLVM_BUILD_TESTS=OFF ^
  -DLLVM_ENABLE_ASSERTIONS=ON ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DLLVM_TARGETS_TO_BUILD="host" ^
  ..\llvm
REM 编译（这会花费 1-2 小时，取决于你的机器）
cmake --build . --config Release --target mlir-opt mlir-translate
REM 或者编译所有 MLIR 相关组件
cmake --build . --config Release --parallel 4
```

​		**第四步：测试新构建的 MLIR**

```cmd
REM 测试工具是否工作
.\Release\bin\mlir-opt.exe --version
```

### 	**2.Lab1**

​		简单起见，下面的lab的文件目录都是最简单的形式。例如

​	，实现Lab1，每个文件直接放在Lab1文件夹下。

​		simple-opt.cpp

```cpp
#include "SimpleDialect.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  
  registry.insert<simple::SimpleDialect>();
  
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Simple dialect test\n", registry));
}
```

​		SimpleDialect.cpp

```cpp
#include "SimpleDialect.h"
#include "mlir/IR/Builders.h"  // 用于构建 MLIR 结构

using namespace mlir;

namespace simple {

/**
 * SimpleDialect 构造函数
 * 
 * 参数：
 * - ctx: MLIR 上下文，管理所有 MLIR 相关的内存和状态
 * 
 * 基类构造函数参数：
 * - getDialectNamespace(): 返回 "simple" 字符串
 * - ctx: 传递上下文
 * - TypeID::get<SimpleDialect>(): 为这个 dialect 创建唯一标识符
 */
SimpleDialect::SimpleDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<SimpleDialect>()) {
  // 调用初始化方法注册所有操作
  initialize();
}

/**
 * 初始化方法
 * 向 dialect 注册所有包含的操作
 * 
 * addOperations<>() 是一个模板方法，可以一次注册多个操作类型
 * 目前我们只有一个 HelloOp 操作
 */
void SimpleDialect::initialize() {
  addOperations<HelloOp>();
}

} // namespace simple
```

​		SimpleDialect.h

```cpp
#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

// 包含 MLIR 核心头文件
#include "mlir/IR/Dialect.h"          // Dialect 基类
#include "mlir/IR/OpDefinition.h"     // Operation 定义相关
#include "mlir/IR/OpImplementation.h" // Operation 实现相关

namespace simple {

/**
 * SimpleDialect 类
 * 继承自 mlir::Dialect，管理整个 simple dialect 的生命周期
 */
class SimpleDialect : public mlir::Dialect {
public:
  // 构造函数：接受 MLIR 上下文作为参数
  explicit SimpleDialect(mlir::MLIRContext *ctx);
  
  // 静态方法：返回 dialect 的命名空间字符串
  // 这个字符串会成为所有操作的前缀（如 "simple.hello"）
  static llvm::StringRef getDialectNamespace() { return "simple"; }
  
  // 初始化方法：注册 dialect 包含的所有操作、类型等
  void initialize();
};

/**
 * HelloOp 类
 * 定义 "simple.hello" 操作
 * 
 * 模板参数说明：
 * - HelloOp: 操作类本身（CRTP 模式）
 * - mlir::OpTrait::ZeroOperands: 表示此操作不接受任何输入操作数
 * - mlir::OpTrait::ZeroResults: 表示此操作不产生任何结果
 */
class HelloOp : public mlir::Op<HelloOp, 
                                mlir::OpTrait::ZeroOperands, 
                                mlir::OpTrait::ZeroResults> {
public:
  // 使用基类的构造函数
  using Op::Op;
  
  // 静态方法：返回操作的完整名称
  // 格式为 "namespace.operation"
  static llvm::StringRef getOperationName() { 
    return "simple.hello"; 
  }
  
  // 构建方法：用于程序化创建此操作的实例
  // 由于我们的操作不需要任何参数，所以实现为空
  static void build(mlir::OpBuilder &, mlir::OperationState &state) {}
  
  // 返回此操作支持的属性名称列表
  // 我们的简单操作不需要任何属性
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  // 打印方法：定义操作如何在 MLIR 文本中显示
  // 我们只打印一个空格，保持简洁
  void print(mlir::OpAsmPrinter &p) {
    p << " ";
  }
  
  // 解析方法：定义如何从 MLIR 文本解析此操作
  // 我们的操作格式很简单，不需要解析任何额外内容
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    return mlir::success();
  }
};

} // namespace simple

#endif
```

​	**编译命令**

​	直接在cmd（用x64 Native Tools Command Prompt for VS 2022，因为刚才编译llvm的命令里有x64选项）里执行，注意，要先设置好你刚刚构建的llvm的路径。

```
首先设置你的LLVM的路径，例如set LLVM_DIR=D:\LLVM_MLIR_LAB_922\llvm-project\build
我的路径是D:\LLVM_MLIR_LAB_922\llvm-project\build  根据你的路径修改
```

```
cl /std:c++17 /MD ^
   /I"%LLVM_DIR%\Release\include" ^
   /I"%LLVM_DIR%\include" ^
   /I"%LLVM_DIR%\tools\mlir\include" ^
   /I"%LLVM_DIR%\..\llvm\include" ^
   /I"%LLVM_DIR%\..\mlir\include" ^
   /EHsc /wd4819 ^
   SimpleDialect.cpp simple-opt.cpp ^
   /link ^
   /LIBPATH:"%LLVM_DIR%\Release\lib" ^
   MLIROptLib.lib ^
   MLIRParser.lib ^
   MLIRAsmParser.lib ^
   MLIRBytecodeReader.lib ^
   MLIRBytecodeWriter.lib ^
   MLIRBytecodeOpInterface.lib ^
   MLIRDebug.lib ^
   MLIRObservers.lib ^
   MLIRIRDL.lib ^
   MLIRInferTypeOpInterface.lib ^
   MLIRRemarkStreamer.lib ^
   MLIRPluginsLib.lib ^
   MLIRIR.lib ^
   MLIRSupport.lib ^
   MLIRPass.lib ^
   LLVMCore.lib ^
   LLVMSupport.lib ^
   LLVMDemangle.lib ^
   LLVMRemarks.lib ^
   LLVMBitstreamReader.lib ^
   ntdll.lib ^
   /OUT:simple-opt.exe
```

### 		3.Lab2

​		simple-opt.cpp

```cpp
#include "SimpleDialect.h"
#include "SimplePass.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"      // func dialect
#include "mlir/Dialect/Arith/IR/Arith.h"       // arith dialect
#include "mlir/Pass/PassRegistry.h"            // Pass 注册

/**
 * simple-opt 主函数
 * 
 * 功能：
 * 1. 注册必要的 Dialect
 * 2. 注册自定义 Pass
 * 3. 提供 mlir-opt 兼容的命令行接口
 */
int main(int argc, char **argv) {
  // 创建 Dialect 注册表
  mlir::DialectRegistry registry;
  
  // 注册标准 Dialect
  registry.insert<mlir::func::FuncDialect>();   // 函数 dialect
  registry.insert<mlir::arith::ArithDialect>(); // 算术 dialect
  
  // 注册我们的自定义 Dialect
  registry.insert<simple::SimpleDialect>();
  
  // 注册我们的自定义 Pass
  // 使用 lambda 函数创建 Pass 实例
  mlir::registerPass([]() -> std::unique_ptr<mlir::Pass> {
    return simple::createSimpleToArithPass();
  });
  
  // 调用 MLIR 的标准主函数
  // 这会处理命令行参数、文件 I/O 和 Pass 执行
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Simple dialect test with passes\n", registry));
}
```

​		SimpleDialect.cpp

```cpp
#include "SimpleDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace simple {

/**
 * SimpleDialect 构造函数
 * 初始化包含多个操作的 Dialect
 */
SimpleDialect::SimpleDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<SimpleDialect>()) {
  initialize();
}

/**
 * 注册所有操作到 Dialect 中
 * 现在包含三个不同类型的操作
 */
void SimpleDialect::initialize() {
  addOperations<HelloOp, PrintOp, AddOp>();
}

} // namespace simple
```

​		SimpleDialect.h

```cpp
#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

// MLIR 核心头文件
#include "mlir/IR/Dialect.h"          // Dialect 基类
#include "mlir/IR/OpDefinition.h"     // Operation 定义
#include "mlir/IR/OpImplementation.h" // Operation 实现
#include "mlir/IR/Builders.h"         // IR 构建器
#include "mlir/IR/Operation.h"        // Operation 基础设施

namespace simple {

/**
 * SimpleDialect 类 - 扩展
 * 管理多个不同类型的操作
 */
class SimpleDialect : public mlir::Dialect {
public:
  explicit SimpleDialect(mlir::MLIRContext *ctx);
  static llvm::StringRef getDialectNamespace() { return "simple"; }
  void initialize();
};

/**
 * HelloOp - 基础操作（Lab 1 中的操作）
 * 特征：ZeroOperands + ZeroResults
 * 语法：simple.hello
 */
class HelloOp : public mlir::Op<HelloOp, 
                                mlir::OpTrait::ZeroOperands, 
                                mlir::OpTrait::ZeroResults> {
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
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    return mlir::success();
  }
};

/**
 * PrintOp - 带属性的操作
 * 特征：ZeroResults（只有属性，无操作数）
 * 语法：simple.print "message"
 * 
 * 这个操作演示了如何处理编译时属性
 */
class PrintOp : public mlir::Op<PrintOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.print"; }
  
  /**
   * 构建方法 - 用于程序化创建操作实例
   * 
   * @param builder: IR 构建器，用于创建 MLIR 结构
   * @param state: 操作状态，收集操作的所有信息
   * @param message: 要打印的消息字符串
   */
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state, 
                    llvm::StringRef message) {
    // 将字符串转换为 MLIR 属性并添加到操作中
    state.addAttribute("message", builder.getStringAttr(message));
  }
  
  /**
   * 声明此操作支持的属性名称
   * 返回静态数组，包含所有可能的属性名
   */
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    static llvm::StringRef attrNames[] = {"message"};
    return llvm::ArrayRef<llvm::StringRef>(attrNames);
  }
  
  /**
   * 打印方法 - 定义操作的文本表示
   * 格式：simple.print "message"
   */
  void print(mlir::OpAsmPrinter &p) {
    // 获取 message 属性并以引号包围的形式打印
    p << " \"" << (*this)->getAttr("message") << "\"";
  }
  
  /**
   * 解析方法 - 从文本解析操作
   * 需要解析引号包围的字符串
   */
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    std::string message;
    // 解析字符串字面量
    if (parser.parseString(&message))
      return mlir::failure();
    
    // 将解析的字符串添加为属性
    result.addAttribute("message", parser.getBuilder().getStringAttr(message));
    return mlir::success();
  }
};

/**
 * AddOp - 数学运算操作
 * 特征：SameOperandsAndResultType（输入输出类型相同）
 * 语法：%result = simple.add %lhs, %rhs : type
 * 
 * 这个操作演示了如何处理运行时数据流
 */
class AddOp : public mlir::Op<AddOp, mlir::OpTrait::SameOperandsAndResultType> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.add"; }
  
  /**
   * 构建方法 - 创建加法操作
   * 
   * @param builder: IR 构建器
   * @param state: 操作状态
   * @param lhs: 左操作数
   * @param rhs: 右操作数
   */
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value lhs, mlir::Value rhs) {
    // 添加两个操作数
    state.addOperands({lhs, rhs});
    // 结果类型与左操作数相同
    state.addTypes(lhs.getType());
  }
  
  /**
   * 此操作不需要属性
   */
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  /**
   * 打印方法 - 格式：%result = simple.add %lhs, %rhs : type
   */
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    auto results = this->getOperation()->getResults();
    p << " " << operands[0] << ", " << operands[1] 
      << " : " << results[0].getType();
  }
  
  /**
   * 解析方法 - 解析复杂的操作数和类型信息
   * 需要处理：操作数引用、类型标注、操作数解析
   */
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand lhs, rhs;
    mlir::Type type;
    
    // 按顺序解析：%lhs, %rhs : type
    if (parser.parseOperand(lhs) ||          // 解析第一个操作数
        parser.parseComma() ||               // 解析逗号
        parser.parseOperand(rhs) ||          // 解析第二个操作数
        parser.parseColon() ||               // 解析冒号
        parser.parseType(type))              // 解析类型
      return mlir::failure();
      
    // 将未解析的操作数转换为实际的 Value 对象
    if (parser.resolveOperands({lhs, rhs}, type, result.operands))
      return mlir::failure();
      
    // 添加结果类型
    result.addTypes(type);
    return mlir::success();
  }
};

} // namespace simple

#endif
```

​		SimplePass.h

```cpp
#ifndef SIMPLE_PASS_H
#define SIMPLE_PASS_H

#include "mlir/Pass/Pass.h"

namespace simple {

/**
 * 创建 Simple 到 Arith 的转换 Pass
 * 将 simple.add 转换为 arith.addi
 * 
 * @return 转换 Pass 的智能指针
 */
std::unique_ptr<mlir::Pass> createSimpleToArithPass();

} // namespace simple

#endif
```

​		SimplePass.cpp

```cpp
#include "SimplePass.h"
#include "SimpleDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Dialect/Arith/IR/Arith.h"

using namespace mlir;

namespace simple {

namespace {

/**
 * SimpleToArithPass - 将 Simple Dialect 操作转换为 Arith Dialect
 * 
 * 这个 Pass 演示了基本的操作转换模式：
 * 1. 查找目标操作
 * 2. 创建等价操作
 * 3. 替换使用关系
 * 4. 清理原操作
 */
struct SimpleToArithPass : public PassWrapper<SimpleToArithPass, OperationPass<ModuleOp>> {
  
  /**
   * 返回 Pass 的命令行参数名
   * 用户可以通过 --convert-simple-to-arith 调用此 Pass
   */
  StringRef getArgument() const final {
    return "convert-simple-to-arith";
  }

  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SimpleToArithPass)
  
  /**
   * 返回 Pass 的描述信息
   * 在帮助信息中显示
   */
  StringRef getDescription() const final {
    return "Convert simple dialect operations to arith dialect";
  }
  
  /**
   * Pass 的主要执行逻辑
   * 在整个模块上运行，查找并转换所有 simple.add 操作
   */
  void runOnOperation() override {
    // 第一步：收集所有需要转换的操作
    // 我们不能在遍历过程中直接修改 IR，因为这会影响迭代器
    SmallVector<AddOp, 4> addOps;
    
    // 使用 walk 方法遍历整个模块，查找 AddOp
    getOperation().walk([&](AddOp op) {
      addOps.push_back(op);
    });
    
    // 第二步：逐个转换收集到的操作
    for (auto op : addOps) {
      // 创建 IR 构建器，在原操作位置插入新操作
      OpBuilder builder(op);
      auto operands = op->getOperands();
      auto resultType = op->getResult(0).getType();
      
      // 方法一：使用 OperationState 手动构建操作
      // 这种方法提供了最大的控制权
      OperationState state(op.getLoc(), "arith.addi");
      state.addOperands({operands[0], operands[1]});
      state.addTypes(resultType);
      
      Operation *newOp = builder.create(state);
      
      // 方法二：使用类型化的操作构建器（注释掉的替代方案）
      // auto newOp = builder.create<mlir::arith::AddIOp>(
      //     op.getLoc(), operands[0], operands[1]);
      
      // 第三步：替换所有对原操作结果的使用
      // 这会自动更新所有引用这个结果的地方
      op->getResult(0).replaceAllUsesWith(newOp->getResult(0));
      
      // 第四步：删除原操作
      // 现在原操作不再被使用，可以安全删除
      op->erase();
      
      // 输出转换信息（可选，用于调试）
      llvm::outs() << "Converted simple.add to arith.addi\n";
    }
  }
};

} // namespace

/**
 * Pass 创建函数
 * 供外部调用以创建 Pass 实例
 */
std::unique_ptr<Pass> createSimpleToArithPass() {
  return std::make_unique<SimpleToArithPass>();
}

} // namespace simple
```

​	**编译命令**

```
cl /std:c++17 /MD ^
   /I"%LLVM_DIR%\Release\include" ^
   /I"%LLVM_DIR%\include" ^
   /I"%LLVM_DIR%\tools\mlir\include" ^
   /I"%LLVM_DIR%\..\llvm\include" ^
   /I"%LLVM_DIR%\..\mlir\include" ^
   /EHsc /wd4819 ^
   SimpleDialect.cpp SimplePass.cpp simple-opt.cpp ^
   /link ^
   /LIBPATH:"%LLVM_DIR%\Release\lib" ^
   MLIROptLib.lib ^
   MLIRParser.lib ^
   MLIRAsmParser.lib ^
   MLIRBytecodeReader.lib ^
   MLIRBytecodeWriter.lib ^
   MLIRBytecodeOpInterface.lib ^
   MLIRDebug.lib ^
   MLIRObservers.lib ^
   MLIRRemarkStreamer.lib ^
   MLIRPluginsLib.lib ^
   MLIRIRDL.lib ^
   MLIRUBDialect.lib ^
   MLIRFuncDialect.lib ^
   MLIRArithDialect.lib ^
   MLIRTensorDialect.lib ^
   MLIRMemRefDialect.lib ^
   MLIRFunctionInterfaces.lib ^
   MLIRCallInterfaces.lib ^
   MLIRCastInterfaces.lib ^
   MLIRControlFlowInterfaces.lib ^
   MLIRSideEffectInterfaces.lib ^
   MLIRShapedOpInterfaces.lib ^
   MLIRInferIntRangeInterface.lib ^
   MLIRInferIntRangeCommon.lib ^
   MLIRInferTypeOpInterface.lib ^
   MLIRAnalysis.lib ^
   MLIRIR.lib ^
   MLIRSupport.lib ^
   MLIRPass.lib ^
   MLIRTransforms.lib ^
   LLVMCore.lib ^
   LLVMSupport.lib ^
   LLVMDemangle.lib ^
   LLVMRemarks.lib ^
   LLVMBitstreamReader.lib ^
   ntdll.lib ^
   /OUT:simple-opt.exe
```

### **4.Lab4**

builtin-builder.cpp

```cpp
#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

int main() {
    // 创建MLIR上下文
    MLIRContext context;
    context.getOrLoadDialect<func::FuncDialect>();
    context.getOrLoadDialect<arith::ArithDialect>();
    
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
    llvm::outs() << "\n";
    
    return 0;
}
```

​		**编译命令**

```
cl /std:c++17 /MD ^
   /I"%LLVM_DIR%\Release\include" ^
   /I"%LLVM_DIR%\include" ^
   /I"%LLVM_DIR%\tools\mlir\include" ^
   /I"%LLVM_DIR%\..\llvm\include" ^
   /I"%LLVM_DIR%\..\mlir\include" ^
   /EHsc /wd4819 ^
   builtin-builder.cpp ^
   /link ^
   /LIBPATH:"%LLVM_DIR%\Release\lib" ^
   MLIRIR.lib MLIRSupport.lib MLIRFuncDialect.lib MLIRArithDialect.lib ^
   MLIRCallInterfaces.lib MLIRFunctionInterfaces.lib MLIRCastInterfaces.lib ^
   MLIRInferIntRangeInterface.lib MLIRInferIntRangeCommon.lib ^
   MLIRUBDialect.lib MLIRInferTypeOpInterface.lib MLIRBytecodeOpInterface.lib ^
   MLIRSideEffectInterfaces.lib MLIRControlFlowInterfaces.lib ^
   MLIRDataLayoutInterfaces.lib MLIRMemorySlotInterfaces.lib ^
   MLIRLoopLikeInterface.lib MLIRViewLikeInterface.lib ^
   MLIRDestinationStyleOpInterface.lib MLIRShapedOpInterfaces.lib ^
   MLIRParallelCombiningOpInterface.lib MLIRRuntimeVerifiableOpInterface.lib ^
   MLIRTilingInterface.lib MLIRValueBoundsOpInterface.lib ^
   MLIRSubsetOpInterface.lib MLIRVectorInterfaces.lib ^
   MLIRDialect.lib MLIRTransforms.lib MLIRPass.lib ^
   LLVMCore.lib LLVMSupport.lib LLVMDemangle.lib LLVMBinaryFormat.lib ^
   ntdll.lib ^
   /OUT:builtin-builder.exe
```

### 	5.Lab7

​	memory-opt.cpp

```cpp
#include "MemoryDialect.h"
#include "MemoryPass.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Pass/PassRegistry.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  
  // 标准 Dialect
  registry.insert<mlir::func::FuncDialect>();
  registry.insert<mlir::arith::ArithDialect>();
  registry.insert<mlir::memref::MemRefDialect>();
  
  // 自定义 Dialect
  registry.insert<memory::MemoryDialect>();
  
  // 注册自定义 Pass
  mlir::registerPass([]() -> std::unique_ptr<mlir::Pass> {
    return memory::createMemoryToMemRefPass();
  });
  
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Memory dialect test tool\n", registry));
}
```

​	MemoryDialect.cpp

```cpp
 #include "MemoryDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace memory {

MemoryDialect::MemoryDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<MemoryDialect>()) {
  initialize();
}

void MemoryDialect::initialize() {
  addOperations<CreateMatrixOp, SetElementOp, GetElementOp, PrintMatrixOp>();
}

} // namespace memory
```

​		MemoryDialect.h

```cpp
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
```

​		MemoryPass.cpp

```cpp
#include "MemoryPass.h"
#include "MemoryDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Arith/IR/Arith.h"

using namespace mlir;

namespace memory {

struct MemoryToMemRefPass : public PassWrapper<MemoryToMemRefPass, OperationPass<ModuleOp>> {
  
  StringRef getArgument() const final {
    return "convert-memory-to-memref";
  }
  
  StringRef getDescription() const final {
    return "Convert memory dialect operations to standard memref operations";
  }
  
  // 添加这个方法来声明依赖的dialect
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<memref::MemRefDialect>();
    registry.insert<arith::ArithDialect>();
  }
  
  void runOnOperation() override {
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
      
      auto resultType = llvm::cast<MemRefType>(op->getResult(0).getType());
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

std::unique_ptr<Pass> createMemoryToMemRefPass() {
  return std::make_unique<MemoryToMemRefPass>();
}

} // namespace memory
```

​		MemoryPass.h

```cpp
#ifndef MEMORY_PASS_H
#define MEMORY_PASS_H

#include "mlir/Pass/Pass.h"

namespace memory {

std::unique_ptr<mlir::Pass> createMemoryToMemRefPass();

} // namespace memory

#endif
```

​		**编译命令**

```
cl /std:c++17 /MD ^
   /I"%LLVM_DIR%\Release\include" ^
   /I"%LLVM_DIR%\include" ^
   /I"%LLVM_DIR%\tools\mlir\include" ^
   /I"%LLVM_DIR%\..\llvm\include" ^
   /I"%LLVM_DIR%\..\mlir\include" ^
   /EHsc /wd4819 ^
   MemoryDialect.cpp MemoryPass.cpp memory-opt.cpp ^
   /link ^
   /LIBPATH:"%LLVM_DIR%\Release\lib" ^
   MLIROptLib.lib ^
   MLIRParser.lib ^
   MLIRAsmParser.lib ^
   MLIRBytecodeReader.lib ^
   MLIRBytecodeWriter.lib ^
   MLIRBytecodeOpInterface.lib ^
   MLIRDebug.lib ^
   MLIRObservers.lib ^
   MLIRIRDL.lib ^
   MLIRInferTypeOpInterface.lib ^
   MLIRRemarkStreamer.lib ^
   MLIRPluginsLib.lib ^
   MLIRFuncDialect.lib ^
   MLIRArithDialect.lib ^
   MLIRMemRefDialect.lib ^
   MLIRUBDialect.lib ^
   MLIRComplexDialect.lib ^
   MLIRMemRefUtils.lib ^
   MLIRDialectUtils.lib ^
   MLIRMemorySlotInterfaces.lib ^
   MLIRShapedOpInterfaces.lib ^
   MLIRValueBoundsOpInterface.lib ^
   MLIRSideEffectInterfaces.lib ^
   MLIRControlFlowInterfaces.lib ^
   MLIRDataLayoutInterfaces.lib ^
   MLIRViewLikeInterface.lib ^
   MLIRSubsetOpInterface.lib ^
   MLIRDestinationStyleOpInterface.lib ^
   MLIRParallelCombiningOpInterface.lib ^
   MLIRRuntimeVerifiableOpInterface.lib ^
   MLIRLoopLikeInterface.lib ^
   MLIRCastInterfaces.lib ^
   MLIRCallInterfaces.lib ^
   MLIRFunctionInterfaces.lib ^
   MLIRInferIntRangeInterface.lib ^
   MLIRInferIntRangeCommon.lib ^
   MLIRTransforms.lib ^
   MLIRTransformUtils.lib ^
   MLIRArithUtils.lib ^
   MLIRIR.lib ^
   MLIRSupport.lib ^
   MLIRPass.lib ^
   MLIRAnalysis.lib ^
   LLVMCore.lib ^
   LLVMSupport.lib ^
   LLVMDemangle.lib ^
   LLVMRemarks.lib ^
   LLVMBitstreamReader.lib ^
   ntdll.lib ^
   /OUT:memory-opt.exe
```

### 6.Lab6

​	**for**

​		test_sum_loop.cpp

```cpp
#include <iostream>

// 声明将在 MLIR 中定义的 C 函数
extern "C" {
    int sum_loop_example(int n);
}

int main() {
    // 测试用例：计算 1 到 10 的和
    int n = 10;
    int expected_sum = 55; // 1+2+...+10 = 55

    int result = sum_loop_example(n);

    std::cout << "Testing sum_loop_example(" << n << ")" << std::endl;
    std::cout << "Result: " << result << std::endl;
    std::cout << "Expected: " << expected_sum << std::endl;

    if (result == expected_sum) {
        std::cout << "Test PASSED!" << std::endl;
    } else {
        std::cout << "Test FAILED!" << std::endl;
    }

    return 0;
}

```

​	**编译脚本**

​		complie_sum_loop.bat，创建这个文件后在cmd里执行。

```
@echo off
echo === Lab 6: SCF Dialect sum_loop 测试 (Windows) ===

REM 配置 MLIR 工具路径
set MLIR_BIN=D:\LLVM-offical\llvm-project\build\Debug\bin

REM ==========================
echo [1/3] Lowering sum_loop.mlir...
%MLIR_BIN%\mlir-opt sum_loop.mlir ^
  --convert-scf-to-cf ^
  --convert-arith-to-llvm ^
  --convert-func-to-llvm ^
  --convert-cf-to-llvm ^
  --reconcile-unrealized-casts ^
  -o sum_loop_llvm.mlir
if %errorlevel% neq 0 (
  echo ✗ sum_loop.mlir lowering failed
  exit /b 1
)

REM ==========================
echo [2/3] Translating sum_loop_llvm.mlir -> sum_loop.ll...
%MLIR_BIN%\mlir-translate sum_loop_llvm.mlir --mlir-to-llvmir -o sum_loop.ll
if %errorlevel% neq 0 (
  echo ✗ sum_loop.mlir translation failed
  exit /b 1
)

REM ==========================
echo [3/3] Building sum_loop test...
clang++ -O0 sum_loop.ll test_sum_loop.cpp -o test_sum_loop.exe
if %errorlevel% neq 0 (
  echo ✗ sum_loop test build failed
  exit /b 1
)

echo.
echo --- Running sum_loop test ---
test_sum_loop.exe
echo.
echo === Done! ===

```

​	**if**

​	test_if_else.cpp

```cpp
#include <iostream>

// 使用 extern "C" 来避免 C++ 名称修饰
extern "C" {
    int if_else_example(int a, int b);
}

int main() {
    // 测试用例 1: 5 < 10, 应该返回 5 + 10 = 15
    int result1 = if_else_example(5, 10);
    std::cout << "if_else_example(5, 10) -> " << result1 << std::endl;
    std::cout << "Expected: 15" << std::endl;
    std::cout << "--------------------" << std::endl;

    // 测试用例 2: 20 > 10, 应该返回 20 - 10 = 10
    int result2 = if_else_example(20, 10);
    std::cout << "if_else_example(20, 10) -> " << result2 << std::endl;
    std::cout << "Expected: 10" << std::endl;

    return 0;
}
```

​	**编译脚本**

​		complie_if_else.bat

```
@echo off
echo === Lab 6: SCF Dialect if_else 测试 (Windows) ===

REM 配置 MLIR 工具路径
set MLIR_BIN=D:\LLVM-offical\llvm-project\build\Debug\bin

REM ==========================
echo [1/3] Lowering if_else.mlir...
%MLIR_BIN%\mlir-opt if_else.mlir ^
  --convert-scf-to-cf ^
  --convert-arith-to-llvm ^
  --convert-func-to-llvm ^
  --convert-cf-to-llvm ^
  --reconcile-unrealized-casts ^
  -o if_else_llvm.mlir
if %errorlevel% neq 0 (
  echo ✗ if_else.mlir lowering failed
  exit /b 1
)

REM ==========================
echo [2/3] Translating if_else_llvm.mlir -> if_else.ll...
%MLIR_BIN%\mlir-translate if_else_llvm.mlir --mlir-to-llvmir -o if_else.ll
if %errorlevel% neq 0 (
  echo ✗ if_else.mlir translation failed
  exit /b 1
)

REM ==========================
echo [3/3] Building if_else test...
clang++ -O0 if_else.ll test_if_else.cpp -o test_if_else.exe
if %errorlevel% neq 0 (
  echo ✗ if_else test build failed
  exit /b 1
)

echo.
echo --- Running if_else test ---
test_if_else.exe
echo.
echo === Done! ===

```



### 		7.Lab10

​		my-opt.cpp

```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "MyPass.h"

int main(int argc, char **argv) {
    mlir::DialectRegistry registry;
    registry.insert<mlir::arith::ArithDialect, 
                    mlir::func::FuncDialect>();

    mlir::registerRemoveMyAddZeroPass();

    return mlir::asMainReturnCode(
        mlir::MlirOptMain(argc, argv, "My Pass Tool\n", registry));
}
```

​		MyPass.cpp

```cpp
#include "MyPass.h"
#include "MyPatterns.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

/// Pass类实现，继承自PassWrapper  
/// 注意：不能放在匿名namespace中，否则会导致TypeID问题
struct RemoveMyAddZeroPass
    : public PassWrapper<RemoveMyAddZeroPass, OperationPass<func::FuncOp>> {

  /// 虚析构函数，确保正确清理
  virtual ~RemoveMyAddZeroPass() = default;

  /// 返回Pass的命令行参数名
  StringRef getArgument() const final { 
    return "remove-my-add-zero"; 
  }
  
  /// 返回Pass的描述信息
  StringRef getDescription() const final { 
    return "Remove redundant add-zero operations (x+0=x)"; 
  }

  /// Pass的核心执行逻辑
  void runOnOperation() override {
    // 获取当前处理的函数
    func::FuncOp func = getOperation();
    MLIRContext *ctx = &getContext();
    
    llvm::outs() << "开始处理函数: " << func.getName() << "\n";

    // 创建Pattern集合并添加我们的优化Pattern
    RewritePatternSet patterns(ctx);
    patterns.add<RemoveAddZeroPattern>(ctx);

    // 应用Pattern进行优化
    // 使用贪婪算法反复应用Pattern直到没有更多匹配
    if (failed(applyPatternsGreedily(func, std::move(patterns)))) {
      llvm::outs() << "Pass执行失败\n";
      signalPassFailure();
    } else {
      llvm::outs() << "Pass执行完成\n";
    }
  }
};
 // anonymous namespace

/// 创建Pass实例的工厂函数
std::unique_ptr<Pass> mlir::createRemoveMyAddZeroPass() {
  return std::make_unique<RemoveMyAddZeroPass>();
}

/// 注册Pass到MLIR系统，使其能被命令行调用
void mlir::registerRemoveMyAddZeroPass() {
  PassRegistration<RemoveMyAddZeroPass>();
}
```

MyPass.h

```cpp
#ifndef MY_PASS_H
#define MY_PASS_H

#include <memory>

namespace mlir {
class Pass;

std::unique_ptr<Pass> createRemoveMyAddZeroPass();
void registerRemoveMyAddZeroPass();
}

#endif
```

MyPatterns.cpp

```cpp
#include "MyPatterns.h"
```

MyPatterns.h

```cpp
#ifndef MY_PATTERNS_H
#define MY_PATTERNS_H

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

struct RemoveAddZeroPattern : public mlir::OpRewritePattern<mlir::arith::AddIOp> {
  using OpRewritePattern<mlir::arith::AddIOp>::OpRewritePattern;

  mlir::LogicalResult matchAndRewrite(mlir::arith::AddIOp op,
                                mlir::PatternRewriter &rewriter) const override {
    mlir::Value lhs = op.getLhs();
    mlir::Value rhs = op.getRhs();

    auto isZeroConst = [](mlir::Value val) -> bool {
      if (auto cst = val.getDefiningOp<mlir::arith::ConstantOp>()) {
        if (auto attr = mlir::dyn_cast<mlir::IntegerAttr>(cst.getValue()))
          return attr.getValue().isZero();
      }
      return false;
    };

    if (isZeroConst(rhs)) {
      rewriter.replaceOp(op, lhs);
      return mlir::success();
    }

    if (isZeroConst(lhs)) {
      rewriter.replaceOp(op, rhs);
      return mlir::success();
    }

    return mlir::failure();
  }
};

#endif
```

**编译命令**

```
cl /std:c++17 /MD ^
   /I"%LLVM_DIR%\Release\include" ^
   /I"%LLVM_DIR%\include" ^
   /I"%LLVM_DIR%\tools\mlir\include" ^
   /I"%LLVM_DIR%\..\llvm\include" ^
   /I"%LLVM_DIR%\..\mlir\include" ^
   /EHsc /wd4819 ^
   my-opt.cpp MyPass.cpp MyPatterns.cpp ^
   /link ^
   /LIBPATH:"%LLVM_DIR%\Release\lib" ^
   MLIROptLib.lib ^
   MLIRMlirOptMain.lib ^
   MLIRParser.lib ^
   MLIRAsmParser.lib ^
   MLIRPass.lib ^
   MLIRRewrite.lib ^
   MLIRRewritePDL.lib ^
   MLIRTransforms.lib ^
   MLIRTransformUtils.lib ^
   MLIRFuncDialect.lib ^
   MLIRArithDialect.lib ^
   MLIRUBDialect.lib ^
   MLIRComplexDialect.lib ^
   MLIRIR.lib ^
   MLIRSupport.lib ^
   MLIRDialect.lib ^
   MLIRAnalysis.lib ^
   MLIRBytecodeReader.lib ^
   MLIRBytecodeWriter.lib ^
   MLIRBytecodeOpInterface.lib ^
   MLIRCallInterfaces.lib ^
   MLIRCastInterfaces.lib ^
   MLIRControlFlowInterfaces.lib ^
   MLIRDataLayoutInterfaces.lib ^
   MLIRFunctionInterfaces.lib ^
   MLIRInferIntRangeInterface.lib ^
   MLIRInferIntRangeCommon.lib ^
   MLIRInferTypeOpInterface.lib ^
   MLIRMemorySlotInterfaces.lib ^
   MLIRSideEffectInterfaces.lib ^
   MLIRLoopLikeInterface.lib ^
   MLIRViewLikeInterface.lib ^
   MLIRDestinationStyleOpInterface.lib ^
   MLIRParallelCombiningOpInterface.lib ^
   MLIRRuntimeVerifiableOpInterface.lib ^
   MLIRSubsetOpInterface.lib ^
   MLIRValueBoundsOpInterface.lib ^
   MLIRShapedOpInterfaces.lib ^
   MLIRTilingInterface.lib ^
   MLIRVectorInterfaces.lib ^
   MLIRMaskableOpInterface.lib ^
   MLIRMaskingOpInterface.lib ^
   MLIRPDLDialect.lib ^
   MLIRPDLInterpDialect.lib ^
   MLIRPDLToPDLInterp.lib ^
   MLIRIRDL.lib ^
   MLIRDebug.lib ^
   MLIRObservers.lib ^
   MLIRPluginsLib.lib ^
   MLIRRemarkStreamer.lib ^
   MLIRArithUtils.lib ^
   MLIRDialectUtils.lib ^
   LLVMCore.lib ^
   LLVMSupport.lib ^
   LLVMDemangle.lib ^
   LLVMBitstreamReader.lib ^
   LLVMRemarks.lib ^
   LLVMBitReader.lib ^
   LLVMBitWriter.lib ^
   ntdll.lib ^
   /OUT:my-opt.exe
```



### 备注

**由于llvm版本的不同，源码可能会有很少部分的修改。**使用llvm22.0版本的lab源码如上。

省略了部分不需要编译的lab