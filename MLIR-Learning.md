Writing by Jabari


以此视频教程为例https://www.bilibili.com/video/BV1JCZzYFEEJ/?share_source=copy_web&vd_source=4d9d633c1e01e9c9b929fe8311e2ad5b

github地址https://github.com/violetDelia/MLIR-Tutorial

mlir官方文档https://mlir.llvm.org/

llvm项目地址https://github.com/llvm/llvm-project

# 拉取项目地址

https://github.com/violetDelia/MLIR-Tutorial/blob/main/readme.md

## 构建命令：

1. 拉包：`git clone https://github.com/violetDelia/MLIR-Tutorial.git`
2. 拉取第三方库：`git submodule update --init --recursive`
3. build：cd `./MLIR-Tutorial && cmake . -G Ninja -B build`
4. 编译：cd build && ninja CH-2 [编译/测试命令]

​	需要用到cmake、ninja、gcc等工具，需要注意的是，gcc编译器的版本不能太低，不然会出现编译不通过的情况。

​	cmake下载地址https://cmake.org/download/

​	ninja下载地址https://github.com/ninja-build/ninja/releases/latest

​	gcc下载地址https://winlibs.com/

​	注意下载完成后一定要配置到系统环境变量中！

​	vscode中推荐使用clangd插件。

# 第一章.自定义方言

​	方言的定义：在 MLIR（Multi - Level Intermediate Representation）中，方言（Dialect）是一种用于描述特定领域或语言子集的结构。定义方言可以使 MLIR 适应不同的应用场景，如特定的编程语言、硬件描述、深度学习框架等。

​	通常使用TableGen语法进行方言的定义，包括方言名称、操作（ops）、类型（Types）等。

​	如开头链接中的项目为例。

​	在2-define_dialect\include\Dialect\NorthStar\IR\NorthStarDialect.td文件中的代码。见代码注释。

​	需要注意的是在 MLIR 的 TableGen 语法中，`let` 关键字用于配置和自定义类、方言、操作等实体的属性。它的作用是覆盖或设置基类中定义的默认属性值

```TableGen
//定义自己的方言，继承自Dialect，这里的Dialect是MLIR的基础方言定义。在MLIR-Tutorial\third_party\llvm-project\mlir\include\mlir\IR\DialectBase.td
//定义的语法是let，用于覆盖基类中的属性和方法。
def NorthStar_Dialect : Dialect{
  // 方言的名字
  let name = "north_star";

  // 方言的概述
  let summary = "summary of NorthStar Dialect";

  // 方言的详细描述
  let description = "description of NorthStar Dialect";

  // 方言的依赖
  // 方言依赖（Dependent Dialects） 指的是一个方言在功能上依赖于其他方言的特性。当你定义一个方言时，通过指定依赖关系，可以确保该方言能够正确使用其他方言定义的类型、操作或属性。
  // 这里依赖的是TensorDialect，TensorDialect是MLIR的一个内置方言，提供了对张量类型和操作的支持。
  let dependentDialects = ["::mlir::tensor::TensorDialect"];

  // 用于生成比较标准的属性管理的代码 [4-7]
  // discardableAttrs 的作用
  // 这个选项用于指定哪些属性在操作（Operation）被转换或优化时可以被安全地丢弃。在 MLIR 的编译流程中，某些属性可能只在特定阶段有用，后续阶段可以忽略它们。
  // (ins) 的含义
  // (ins) 是一个 TableGen 语法，表示 "无参数"。在这里，它意味着没有定义可丢弃的属性。也就是说，该方言中的所有属性都被视为不可丢弃，在转换过程中会被保留。
  let discardableAttrs = (ins);

  // 生成代码在C++代码中的命名空间
  // 一般为::mlir::dialect_name
  let cppNamespace = "::mlir::north_star";

  // 额外的声明.
  // 在 MLIR 的 TableGen 方言定义中，extraClassDeclaration 选项允许你向自动生成的 C++ 类添加额外的声明。这是一种扩展生成代码的机制，用于添加 TableGen 本身不直接支持的自定义功能。
  // 这段代码的作用是：
  // 1.向生成的 NorthStarDialect C++ 类添加一个静态成员函数 sayHello()。
  // 2.这个函数不会由 TableGen 自动实现，需要你手动在 C++ 代码中提供实现。
  let extraClassDeclaration = [{
    static void sayHello();
  }];

  // 规范化的声明. [14]
  // 0表示没有规范化的声明，1表示有规范化的声明。
  let hasConstantMaterializer = 0;

  // 是否生成默认的析构函数
  // 0表示生成，1表示不生成。
  let hasNonDefaultDestructor = 1;

  // 操作数的属性检验 [7]
  let hasOperationAttrVerify = 0;

  // RegionArg的属性检验 [7]
  let hasRegionArgAttrVerify = 0;

  // RegionResult的属性检验 [7]
  let hasRegionResultAttrVerify = 0;

  // [6]
  let hasOperationInterfaceFallback = 0;

  // 使用MLIR默认的属性解析输出.
  // 0为不使用，1为使用
  let useDefaultAttributePrinterParser = 0;

  // 使用MLIR默认的类型解析输出.
  let useDefaultTypePrinterParser = 0;

  // 是否有规范化patten[14].
  let hasCanonicalizer = 0;

  // 是否是可扩展的方言.
  let isExtensible = 0;

  // Whether inherent Attributes defined in ODS will be stored as Properties.
  let usePropertiesForAttributes = 1;

}
```

​	定义完方言后使用cmake代码将TableGen文件编译为C++文件。代码如下，地址在2-define_dialect\include\Dialect\NorthStar\IR\CMakeLists.txt

```cmake
set(LLVM_TARGET_DEFINITIONS NorthStarDialect.td)		#设置TableGen源文件，LLVM_TARGET_DEFINITIONS 是 LLVM/MLIR 的 CMake 变量，用于指定 TableGen 的输入文件，NorthStarDialect.td是定义的方言文件
# 生成NorthStar Dialect 的声明
#	mlir_tablegen 是 MLIR 提供的 CMake 宏，用于调用 TableGen 工具。
#	--gen-dialect-decls 是 TableGen 的参数，指示生成 C++ 头文件声明（如类定义、方法签名）。
#	-dialect=north_star 指定要处理的方言名称。
#	生成的 NorthStarDialect.h.inc 会被包含在最终的 C++ 头文件中。
mlir_tablegen(NorthStarDialect.h.inc --gen-dialect-decls -dialect=north_star)
# 生成NorthStar Dialect 的实现
#	--gen-dialect-defs 指示生成 C++ 方法的实现代码。
#	生成的 NorthStarDialect.cpp.inc 会被包含在最终的 C++ 实现文件中。
mlir_tablegen(NorthStarDialect.cpp.inc --gen-dialect-defs -dialect=north_star)

# 将生成的命令们定义为为target
#	add_public_tablegen_target 是 LLVM 提供的宏，用于创建一个公共的 TableGen 构建目标。
#	这个目标负责将 TableGen 描述文件（.td）编译为 C++ 代码（.h.inc和.cpp.inc），并确保这些生成的文件在项目的其他部分被正确依赖和使用。
add_public_tablegen_target(NorthStarDialectIncGen${ch_num})
```

​	上面代码中的.inc作用：

​	在 MLIR 项目中，`.inc` 是一种**约定俗成的文件扩展名**，通常表示 “包含文件”（**Include File**）。这些文件不是独立的完整源文件，而是用于**被其他 C++ 文件包含**的代码片段，类似于头文件（`.h`），但有特定的用途：

**为什么使用 `.inc` 文件？**

1. **代码生成的模块化**：
   - MLIR 使用 TableGen 自动生成大量代码（如操作定义、类型系统）。这些生成的代码被分割成`.inc`文件，便于管理和维护。
   - 例如，`NorthStarDialect.h.inc` 包含由 TableGen 生成的方言类声明，而`NorthStarDialect.cpp.inc` 包含对应的实现。
2. **避免重复定义**：
   - `.inc` 文件通常不包含头文件保护（如`#ifndef DIALECT_NORTH_STAR`），因为它们会被包含在其他已经有保护的文件中。
3. **与项目结构解耦**：
   - 生成的`.inc`文件通常放在构建目录（如`build/include/`），而不是源码目录，保持源码树的整洁。

​	上述代码实现后，在终端使用命令cd build/进入build目录，然后输入命令ninja NorthStarDialectIncGen2编译文件，编译后可以得到C++代码的头文件和源文件，头文件路径为build\2-define_dialect\include\Dialect\NorthStar\IR\NorthStarDialect.h.inc	源文件路径为build\2-define_dialect\include\Dialect\NorthStar\IR\NorthStarDialect.cpp.inc

​	头文件代码如下,头文件（通常是`.h`或`.h.inc`）的核心作用是**声明函数、类和类型**，为 C++ 代码提供接口定义。

```cpp
/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* Dialect Declarations                                                       *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|* From: NorthStarDialect.td                                                  *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

namespace mlir {			//这是 MLIR 框架的顶级命名空间，所有 MLIR 核心库和官方方言都位于此命名空间下。
namespace north_star {		//这是你自定义方言的专属命名空间，用于隔离该方言内的所有类、函数和类型。

class NorthStarDialect : public ::mlir::Dialect {
  explicit NorthStarDialect(::mlir::MLIRContext *context);		//构造函数声明

  void initialize();		//初始化方法声明
  friend class ::mlir::MLIRContext;
public:
  ~NorthStarDialect() override;		//析构函数，标记为override确保正确覆盖基类虚函数
  static constexpr ::llvm::StringLiteral getDialectNamespace() {
    return ::llvm::StringLiteral("north_star");
  }

    static void sayHello();		//NorthStarDialect.td文件里的自定义函数
  };
} // namespace north_star
} // namespace mlir
MLIR_DECLARE_EXPLICIT_TYPE_ID(::mlir::north_star::NorthStarDialect)		//这是 MLIR 为方言类声明唯一类型 ID 的宏，用于运行时类型识别和注册。

```

​	头文件中定义的函数在源文件中实现，源文件代码如下：

```cpp
/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* Dialect Definitions                                                        *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|* From: NorthStarDialect.td                                                  *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

MLIR_DEFINE_EXPLICIT_TYPE_ID(::mlir::north_star::NorthStarDialect)
namespace mlir {
namespace north_star {

//类外实现构造函数
//声明函数，表明这是 NorthStarDialect 类的构造函数。参数类型为 MLIR 上下文的指针::mlir::MLIRContext *context
//调用基类 mlir::Dialect 的构造函数进行初始化。	getDialectNamespace()：返回方言的命名空间字符串（在 .td 文件中定义，如 "north_star"）。		context：传递 MLIR 上下文指针。	::mlir::TypeID::get<NorthStarDialect>()：获取方言的唯一类型 ID，用于运行时类型识别。
NorthStarDialect::NorthStarDialect(::mlir::MLIRContext *context)
    : ::mlir::Dialect(getDialectNamespace(), context, ::mlir::TypeID::get<NorthStarDialect>())
    
     {
  getContext()->loadDialect<::mlir::tensor::TensorDialect>();		//加载依赖方言、这个依赖是在NorthStarDialect.td文件中定义的依赖
  initialize();		//调用初始化方法
}
} // namespace north_star
} // namespace mlir

```

​	头文件和源文件编译完成后，我们要去实现。用于实现的文件路径为：

​	头文件：2-define_dialect\include\Dialect\NorthStar\IR\NorthStarDialect.h

​	源文件：2-define_dialect\src\Dialect\NorthStar\IR\NorthStarDialect.cpp

​	头文件代码如下

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.

#ifndef DIALECT_NORTH_STAR_H
#define DIALECT_NORTH_STAR_H
#include "mlir/Dialect/Tensor/IR/Tensor.h"		//引入 MLIR 的 Tensor 方言支持，对应.td文件中的dependentDialects。
#include "mlir/IR/MLIRContext.h"			//引入 MLIR 上下文相关的定义，用于方言初始化。
#include "Dialect/NorthStar/IR/NorthStarDialect.h.inc"		//通过#include引入 TableGen 生成的.inc文件（而非直接编写 C++ 代码）。

#endif  // DIALECT_NORTH_STAR_H
```

​	源文件代码如下

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#include "Dialect/NorthStar/IR/NorthStarDialect.h"		//引入之前定义的头文件（包含方言类声明）

#include "llvm/Support/raw_ostream.h"				   //引入 LLVM 的输出流支持，用于日志输出
#define FIX
#include "Dialect/NorthStar/IR/NorthStarDialect.cpp.inc"
#undef FIX

namespace mlir::north_star {
// 实现方言的初始化方法
void NorthStarDialect::initialize() {
  llvm::outs() << "initializing " << getDialectNamespace() << "\n";		//getDialectNamespace()返回方言的命名空间字符串
}

// 实现方言的析构函数
NorthStarDialect::~NorthStarDialect() {
  llvm::outs() << "destroying " << getDialectNamespace() << "\n";
}

// 实现在extraClassDeclaration 声明当中生命的方法。即自定义方法的实现
void NorthStarDialect::sayHello() {
  llvm::outs() << "Hello in " << getDialectNamespace() << "\n";
}

}  // namespace mlir::north_star

```

​	下面这段 CMake 代码是 MLIR 项目中用于构建方言库的标准配置，路径为2-define_dialect\src\Dialect\NorthStar\IR\CMakeLists.txt

```cmake
#add_mlir_dialect_library：MLIR 提供的 CMake 宏，用于创建方言库
#MLIRNorthStarDialect${ch_num}：目标库名称，${ch_num}是变量（如版本号）
add_mlir_dialect_library(MLIRNorthStarDialect${ch_num}
    NorthStarDialect.cpp		#源文件，包含方言实现代码

    DEPENDS		#依赖管理,指定构建依赖关系
    NorthStarDialectIncGen${ch_num}		#TableGen 生成目标（来自之前的add_public_tablegen_target）

    LINK_LIBS PUBLIC		#指定需要链接的公共库
    MLIRIR		#MLIR 核心库，提供基础类型和操作
    MLIRTensorDialect		#Tensor 方言库，对应.td中的dependentDialects
)


```

​	在main函数中实现

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#include "Dialect/NorthStar/IR/NorthStarDialect.h"		//自定义方言的主头文件
#include "mlir/IR/DialectRegistry.h"				   //MLIR 的方言注册器，用于管理可用方言
#include "mlir/IR/MLIRContext.h"					  //MLIR 的核心上下文，所有操作都在上下文中执行

void CH2() {
  // 初始化方言注册器
  mlir::DialectRegistry registry;
  // 初始化上下文环境
  mlir::MLIRContext context(registry);
  // 加载/注册方言
  auto dialect = context.getOrLoadDialect<mlir::north_star::NorthStarDialect>();		//getOrLoadDialect<...>()模板方法，用于获取指定方言的实例。如果方言尚未加载，则自动加载并注册。

  // 调用方言中的方法
  dialect->sayHello();
}

int main() { CH2(); }
```

​	

```cmake
set(ch_num 2)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
include_directories(${CMAKE_CURRENT_BINARY_DIR}/include)
add_subdirectory(include)
add_subdirectory(src)
add_executable(CH-${ch_num} "main.cpp")
target_link_libraries(CH-${ch_num} MLIRNorthStarDialect${ch_num})		#将CH-2可执行文件与MLIRNorthStarDialect2库链接起来

```

​	然后在终端输入命令ninja CH-2进行编译，编译后在构建目录下会生成 `CH-2` 可执行文件，路径为build\2-define_dialect\CH-2.exe，运行该文件后，终端输出

initializing north_star
Hello in north_star
destroying north_star

​	这样就完成了方言的注册、加载以及初始化。

# 第二章.内建type及自定义type

## 	2.1**内建Type**	

​	MLIR提供了一系列内建类型，这些是 MLIR 的核心组成部分，用于描述张量、标量、内存、函数等抽象结构。文件路径为third_party\llvm-project\mlir\include\mlir\IR\BuiltinTypes.td，下面列举部分内建类型。一些常用内建类型可以看链接视频。

​	1.标量类型

| 类型             | 描述                                                         |
| ---------------- | ------------------------------------------------------------ |
| iN               | 整型（例如i32，i64，i1），其中N是位宽                        |
| f16,f32,f64,bf16 | 浮点类型（半精度、单精度、双精度、bfloat）                   |
| index            | 表示索引类型，用于数组索引等，取决于系统，32位系统则是32位无符号整数，64位系统则是64位无符号整数。 |
| complex<T>       | 复数类型，例如complex<f64>                                   |

​	2.容器类型

​	Tensor：用于表示不可变的张量数据

| tensor<2x3xf32> | 2x3的float32张量 |
| --------------- | ---------------- |
| tensor<?x?xi32> | 动态张量的类型   |

​	MemRef：表示内存引用，常用于buffer

| memref<4x4xi8> | 4x4的i8 buffer         |
| -------------- | ---------------------- |
| memref<?xf32>  | 动态大小的float buffer |

​	3.结构类型

| tuple<i32,f32,tensor<2xf64>> | 元组类型，表示多个值组合                                     |
| ---------------------------- | ------------------------------------------------------------ |
| (i32,f32) -> (f32)           | 函数类型，表示输入输出的类型，接受i32和f32参数，并返回一个f32类型的值 |

​	4.其他类型

| NoneType   | 表示无值，如Python的None和C++的void           |
| ---------- | --------------------------------------------- |
| OpaqueType | 用于 dialect 定义自己的特殊类型，外部无法识别 |

## 	2.2自定义Type

​	首先要编写自定义type的tablegen文件，可以先仿造llvm项目里的BuiltinTypes.td文件中的代码来创建一个基类，路径为third_party\llvm-project\mlir\include\mlir\IR\BuiltinTypes.td

```tablegen
class Builtin_Type<string name, string typeMnemonic, list<Trait> traits = [],
                   string baseCppClass = "::mlir::Type">    
    : TypeDef<Builtin_Dialect, name, traits, baseCppClass> {
  let mnemonic = ?;
  let typeName = "builtin." # typeMnemonic;
}   //类型名称 name、类型助记符 typeMnemonic、类型特性列表 traits（默认为空列表），以及 C++ 基类名 baseCppClass（默认为 ::mlir::Type）。
```

​	然后修改为自己要定义的Type的信息

```tablegen
class NorthStar_Type<string name, string typeMnemonic, list<Trait> traits = [],
                   string baseCppClass = "::mlir::Type">    
    : TypeDef<Builtin_Dialect, name, traits, baseCppClass> {
  let mnemonic = typeMnemonic;
  //tablegen语法中#有连接字符串的作用
  let typeName = dialect.name # "." # typeMnemonic;
}
```

​	mlir内建的tensor无法表示其内存层次的信息，现在定义一个tensor类型，让其可以表示内存层次的信息。

```Tablegen
def NorthStar_TensorType : 
  //定义NorthStar_TensorType，继承自基类NorthStar_Type，其参数为：name为NSTensor，typeMnemonic为ns_tensor，list为空列表
NorthStar_Type<"NSTensor","ns_tensor",[]>{
  // 概述
  let summary = " the summary of north-star tensor type";

  // 详细描述
  let description = "description of north-star tensor type";

  // 参数
  let parameters = (ins
    ArrayRefParameter<"int64_t">:$shape,		//张量的形状
    "Type":$elementType,		//张量元素的类型
    "int64_t":$device_id		//内存设备的信息
  );

  // 是否生成StorageClass, 无特殊情况，建议设为ture
  // 在 MLIR 的 TableGen 定义中，let genStorageClass = 1; 这一行的作用是指示 MLIR 自动生成与类型相关的存储类（Storage Class）。
  // 作用为：存储类型的参数（如张量的形状、元素类型）、实现类型的唯一性检查（通过 TypeStorage 基类）、提供类型的属性访问方法
  // 例如，对于 NorthStar_TensorType，其存储类会保存 shape、elementType 和 device_id 三个参数。
  let genStorageClass = 1;
  
  // 在 MLIR 的 TableGen 定义中，let hasStorageCustomConstructor = 0; 这一设置控制着存储类（Storage Class）的构造方式。
  // 表示是否生成StorageClass默认的构造函数，0表示生成，1表示不生成，手动构造
  let hasStorageCustomConstructor = 0;

  // 额外的builder 声明
  // 只有两个参数，device默认为0 
  let builders = [
    TypeBuilder<(ins 
        "::mlir::ArrayRef<int64_t>":$shape,
        "::mlir::Type":$elementType),[{
      return $_get(elementType.getContext(), shape, elementType, 0);
    }]>
  ];

  let hasCustomAssemblyFormat = 1;		//是否使用mlir默认的Format函数序列化Type，0为使用
     //assemblyFormat 在 MLIR TableGen 中的作用是：自动生成操作或类型的文本格式（assembly）的 parse() 和 print() 函数，你就不需要手动写 C++ 代码来	    //解析或打印 IR 了。
  //let assemblyFormat = "`<`$shape`,`$elementType`,`$device_id`>`";	

  // 不跳过默认的builder函数
  let skipDefaultBuilders = 0;

  // 是否生成类型检验的函数声明
  let genVerifyDecl = 1;

  // extraClassDeclaration 用来插入额外的 C++ 代码声明，扩展类型类。这里注释了多条 using 声明和一个 clone 函数,这在第五章时会用到
  let extraClassDeclaration = [{
    // using TensorType::clone;
    // using ShapedType::Trait<NSTensorType>::getElementTypeBitWidth;
    // using ShapedType::Trait<NSTensorType>::getRank;
    // using ShapedType::Trait<NSTensorType>::getNumElements;
    // using ShapedType::Trait<NSTensorType>::isDynamicDim;
    // using ShapedType::Trait<NSTensorType>::hasStaticShape;
    // using ShapedType::Trait<NSTensorType>::getNumDynamicDims;
    // using ShapedType::Trait<NSTensorType>::getDimSize;
    // using ShapedType::Trait<NSTensorType>::getDynamicDimIndex;
    // NSTensorType clone(::mlir::Type elementType) {
    //   return ::llvm::cast<NSTensorType>(cloneWith(getShape(), elementType));
    // }
  }];
}
```

​	定义完成后，将代码生成。路径为3-define_type\include\Dialect\NorthStar\IR\CMakeLists.txt

```cmake
set(LLVM_TARGET_DEFINITIONS NorthStarTypes.td)		#设置 LLVM_TARGET_DEFINITIONS，告诉 mlir_tablegen 工具接下来要处理哪个 TableGen 文件。
# 生成NorthStar Dialect 的声明
mlir_tablegen(NorthStarDialect.h.inc --gen-dialect-decls -dialect=north_star)
# 生成NorthStar Dialect 的实现
mlir_tablegen(NorthStarDialect.cpp.inc --gen-dialect-defs -dialect=north_star)
# 生成NorthStar Type 的声明
mlir_tablegen(NorthStarTypes.h.inc -gen-typedef-decls -dialect=north_star)
# 生成NorthStar Type 的实现
mlir_tablegen(NorthStarTypes.cpp.inc -gen-typedef-defs -dialect=north_star)
# 将生成的命令们定义为为target
add_public_tablegen_target(NorthStarDialectIncGen${ch_num})

```

​	生成的头文件为，路径为build\3-define_type\include\Dialect\NorthStar\IR\NorthStarTypes.h.inc

```cpp
/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* TypeDef Declarations                                                       *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

#ifdef GET_TYPEDEF_CLASSES
#undef GET_TYPEDEF_CLASSES


namespace mlir {
class AsmParser;
class AsmPrinter;
} // namespace mlir
namespace mlir {
namespace north_star {
class NSTensorType;
namespace detail {
struct NSTensorTypeStorage;		//类型数据的实际存储结构,是由tablegen文件中 let genStorageClass = 1; 自动生成的！
} // namespace detail
    
 //class NSTensorType
 //  : public ::mlir::Type::TypeBase<
 //    NSTensorType,          // 当前类型类名
 //    ::mlir::Type,          // 基类，所有 Type 的基类
 //    detail::NSTensorTypeStorage>  // 存储结构（下一节解释）
 // NSTensorType 是一个 MLIR 类型类（TypeBase）,继承了 mlir::Type 的所有功能，类型的参数数据（shape, elementType, device_id）由      NSTensorTypeStorage 存储
class NSTensorType : public ::mlir::Type::TypeBase<NSTensorType, ::mlir::Type, detail::NSTensorTypeStorage> {
public:
  using Base::Base;
  // using TensorType::clone;
  // using ShapedType::Trait<NSTensorType>::getElementTypeBitWidth;
  // using ShapedType::Trait<NSTensorType>::getRank;
  // using ShapedType::Trait<NSTensorType>::getNumElements;
  // using ShapedType::Trait<NSTensorType>::isDynamicDim;
  // using ShapedType::Trait<NSTensorType>::hasStaticShape;
  // using ShapedType::Trait<NSTensorType>::getNumDynamicDims;
  // using ShapedType::Trait<NSTensorType>::getDimSize;
  // using ShapedType::Trait<NSTensorType>::getDynamicDimIndex;
  // NSTensorType clone(::mlir::Type elementType) {
  //   return ::llvm::cast<NSTensorType>(cloneWith(getShape(), elementType));
  // }
  static constexpr ::llvm::StringLiteral name = "north_star.ns_tensor";		//为类型定义了一个编译期的字符串常量，用来唯一标识这个类型。
  static constexpr ::llvm::StringLiteral dialectName = "north_star";		//为这个类型声明所属的 Dialect（方言）名称
  using Base::getChecked;
  //默认builder的get方法
  static NSTensorType get(::mlir::MLIRContext *context, ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id);
  //默认builder的getcheck方法
  static NSTensorType getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError, ::mlir::MLIRContext *context, ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id);
  //额外builder的get方法
  static NSTensorType get(::mlir::MLIRContext *context, ::mlir::ArrayRef<int64_t> shape, ::mlir::Type elementType);
  //额外builder的getcheck方法
  static NSTensorType getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError, ::mlir::MLIRContext *context, ::mlir::ArrayRef<int64_t> shape, ::mlir::Type elementType);
  //参数校验函数，由tablegen文件中  let genVerifyDecl = 1; 生成
  static ::llvm::LogicalResult verify(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError, ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id);
  static constexpr ::llvm::StringLiteral getMnemonic() {
    return {"ns_tensor"};
  }

  //parse() 和 print()	需要在源文件中自己实现
  //负责将类型和 IR 文本互相转换，由tablegen文件中  let genVerifyDecl = 1; 生成
  static ::mlir::Type parse(::mlir::AsmParser &odsParser);
  void print(::mlir::AsmPrinter &odsPrinter) const;
  ::llvm::ArrayRef<int64_t> getShape() const;
  Type getElementType() const;
  int64_t getDeviceId() const;
};
} // namespace north_star
} // namespace mlir
MLIR_DECLARE_EXPLICIT_TYPE_ID(::mlir::north_star::NSTensorType)

#endif  // GET_TYPEDEF_CLASSES


```

​	下面代码是由 TableGen 根据类型定义自动生成的，负责定义和实现自定义的 MLIR 类型 `NSTensorType` 及其相关辅助函数。路径为build\3-define_type\include\Dialect\NorthStar\IR\NorthStarTypes.cpp.inc

```cpp
/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* TypeDef Definitions                                                        *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

#ifdef GET_TYPEDEF_LIST
#undef GET_TYPEDEF_LIST

::mlir::north_star::NSTensorType

#endif  // GET_TYPEDEF_LIST

#ifdef GET_TYPEDEF_CLASSES
#undef GET_TYPEDEF_CLASSES

    
//generatedTypeParser,这是一个类型解析的辅助函数。它用 KeywordSwitch 根据解析到的类型名（mnemonic）分发调用对应类型的 parse() 函数。如果匹配到 NSTensorType 的 mnemonic（比如 "ns_tensor"），就调用 NSTensorType::parse()。如果找不到对应类型，返回 nullopt 表示解析失败，由调用方处理错误。
static ::mlir::OptionalParseResult generatedTypeParser(::mlir::AsmParser &parser, ::llvm::StringRef *mnemonic, ::mlir::Type &value) {
  return ::mlir::AsmParser::KeywordSwitch<::mlir::OptionalParseResult>(parser)
    .Case(::mlir::north_star::NSTensorType::getMnemonic(), [&](llvm::StringRef, llvm::SMLoc) {
      value = ::mlir::north_star::NSTensorType::parse(parser);
      return ::mlir::success(!!value);
    })
    .Default([&](llvm::StringRef keyword, llvm::SMLoc) {
      *mnemonic = keyword;
      return std::nullopt;
    });
}

//generatedTypePrinter,这是类型打印的辅助函数。使用 TypeSwitch 对传入的 Type 进行动态类型匹配。如果是 NSTensorType，先打印它的 mnemonic（比如 "ns_tensor"），然后调用该类型实例的 print() 方法打印参数内容。不支持的类型返回失败。
static ::llvm::LogicalResult generatedTypePrinter(::mlir::Type def, ::mlir::AsmPrinter &printer) {
  return ::llvm::TypeSwitch<::mlir::Type, ::llvm::LogicalResult>(def)    .Case<::mlir::north_star::NSTensorType>([&](auto t) {
      printer << ::mlir::north_star::NSTensorType::getMnemonic();
t.print(printer);
      return ::mlir::success();
    })
    .Default([](auto) { return ::mlir::failure(); });
}

namespace mlir {
namespace north_star {
namespace detail {
////NSTensorTypeStorage 结构体,NSTensorType 类型的 存储类，继承自 mlir::TypeStorage。用于持有类型的“参数”数据：shape、elementType、device_id。
struct NSTensorTypeStorage : public ::mlir::TypeStorage {
  using KeyTy = std::tuple<::llvm::ArrayRef<int64_t>, Type, int64_t>;
  NSTensorTypeStorage(::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id) : shape(std::move(shape)), elementType(std::move(elementType)), device_id(std::move(device_id)) {}

  KeyTy getAsKey() const {
    return KeyTy(shape, elementType, device_id);
  }

  bool operator==(const KeyTy &tblgenKey) const {
    return (shape == std::get<0>(tblgenKey)) && (elementType == std::get<1>(tblgenKey)) && (device_id == std::get<2>(tblgenKey));
  }

  static ::llvm::hash_code hashKey(const KeyTy &tblgenKey) {
    return ::llvm::hash_combine(std::get<0>(tblgenKey), std::get<1>(tblgenKey), std::get<2>(tblgenKey));
  }

  static NSTensorTypeStorage *construct(::mlir::TypeStorageAllocator &allocator, KeyTy &&tblgenKey) {
    auto shape = std::move(std::get<0>(tblgenKey));
    auto elementType = std::move(std::get<1>(tblgenKey));
    auto device_id = std::move(std::get<2>(tblgenKey));
    shape = allocator.copyInto(shape);
    return new (allocator.allocate<NSTensorTypeStorage>()) NSTensorTypeStorage(std::move(shape), std::move(elementType), std::move(device_id));
  }

  ::llvm::ArrayRef<int64_t> shape;
  Type elementType;
  int64_t device_id;
};
} // namespace detail
//  //NSTensorType 的静态工厂方法实现,内部调用 Base::get()，由 MLIR 的 TypeBase 模板类实现，利用 NSTensorTypeStorage 进行唯一性缓存和返回类型实例。同理，getChecked 会先调用你实现的 verify 函数做合法性校验。
NSTensorType NSTensorType::get(::mlir::MLIRContext *context, ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id) {
  return Base::get(context, std::move(shape), std::move(elementType), std::move(device_id));
}

NSTensorType NSTensorType::getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError, ::mlir::MLIRContext *context, ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id) {
  return Base::getChecked(emitError, context, shape, elementType, device_id);
}

NSTensorType NSTensorType::get(::mlir::MLIRContext *context, ::mlir::ArrayRef<int64_t> shape, ::mlir::Type elementType) {
  return Base::get(elementType.getContext(), shape, elementType, 0);
}

NSTensorType NSTensorType::getChecked(::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError, ::mlir::MLIRContext *context, ::mlir::ArrayRef<int64_t> shape, ::mlir::Type elementType) {
  return Base::getChecked(emitError, elementType.getContext(), shape, elementType, 0);
}

//访问类型参数的接口实现
::llvm::ArrayRef<int64_t> NSTensorType::getShape() const {
  return getImpl()->shape;
}

Type NSTensorType::getElementType() const {
  return getImpl()->elementType;
}

int64_t NSTensorType::getDeviceId() const {
  return getImpl()->device_id;
}

} // namespace north_star
} // namespace mlir
MLIR_DEFINE_EXPLICIT_TYPE_ID(::mlir::north_star::NSTensorType)
namespace mlir {
namespace north_star {

/// Parse a type registered to this dialect.
::mlir::Type NorthStarDialect::parseType(::mlir::DialectAsmParser &parser) const {
  ::llvm::SMLoc typeLoc = parser.getCurrentLocation();
  ::llvm::StringRef mnemonic;
  ::mlir::Type genType;
  auto parseResult = generatedTypeParser(parser, &mnemonic, genType);
  if (parseResult.has_value())
    return genType;
  
  parser.emitError(typeLoc) << "unknown  type `"
      << mnemonic << "` in dialect `" << getNamespace() << "`";
  return {};
}
/// Print a type registered to this dialect.
void NorthStarDialect::printType(::mlir::Type type,
                    ::mlir::DialectAsmPrinter &printer) const {
  if (::mlir::succeeded(generatedTypePrinter(type, printer)))
    return;
  
}
} // namespace north_star
} // namespace mlir

#endif  // GET_TYPEDEF_CLASSES


```

​	下面代码是自定义的 `NSTensorType` 类型的核心 C++ 实现，配合 TableGen 自动生成的声明和存储类，完成 MLIR 类型的解析、打印和验证功能。路径为3-define_type\src\Dialect\NorthStar\IR\NorthStarTypes.cpp

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#include "Dialect/NorthStar/IR/NorthStarTypes.h"

#include "Dialect/NorthStar/IR/NorthStarDialect.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/LogicalResult.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Support/LLVM.h"
#define FIX
#define GET_TYPEDEF_CLASSES
#include "Dialect/NorthStar/IR/NorthStarTypes.cpp.inc"

namespace mlir::north_star {

//这是 Dialect 中注册自定义类型的函数。
void NorthStarDialect::registerType() {
  llvm::outs() << "register " << getDialectNamespace() << "  Type\n";
  addTypes<		//addTypes 是 MLIR 方言接口，用来批量注册类型。
#define GET_TYPEDEF_LIST
#include "Dialect/NorthStar/IR/NorthStarTypes.cpp.inc"
      >();
}

//这是类型参数校验函数，在调用 getChecked 时会自动被调用。
::llvm::LogicalResult NSTensorType::verify(
    ::llvm::function_ref<::mlir::InFlightDiagnostic()> emitError,
    ::llvm::ArrayRef<int64_t> shape, Type elementType, int64_t device_id) {
  if (device_id < 0) {		//device_id 不能小于0。
    return emitError() << " Invalid device id";
  }
  if (!elementType.isIntOrFloat()) {		//elementType 必须是整型或浮点型。
    return emitError() << " Invalid element type ";		//不符合条件时通过 emitError() 输出错误，返回失败。
  }
  return llvm::success();
}

//这是类型文本解析函数。
Type NSTensorType::parse(AsmParser &parser) {
  if (parser.parseLess()) return Type();		//先读入符号 <

  SmallVector<int64_t, 4> dimensions;	//定义一个容器 dimensions，用来存储解析出来的维度信息。使用 SmallVector 是 LLVM/MLIR 的高效动态数组模板。
    
  //调用 MLIR 解析器的 parseDimensionList，从文本读取维度列表。
  //参数说明：dimensions：解析结果存入此数组。allowDynamic=true：允许维度为动态大小（用 ? 或 -1 表示）。withTrailingX=true：维度之间用 x 分隔，如 3x4x?x.
  if (parser.parseDimensionList(dimensions, /*allowDynamic=*/true,
                                /*withTrailingX=*/true))
    return Type();	//解析失败时返回空类型 Type()。
  // Parse the element type.
  auto typeLoc = parser.getCurrentLocation();
  Type elementType;		//定义一个变量，准备存储解析出来的元素类型。
  if (parser.parseType(elementType)) return Type();		//解析一个 MLIR 类型文本，存入 elementType。失败时返回空类型 Type()。
  // Check that array is formed from allowed types.
  if (parser.parseComma()) return Type();		//期望读取逗号 , 分隔符。失败返回空类型。
  int device_id = 0;		//  int device_id = 0;
  if (parser.parseInteger(device_id))		//先解析一个整数，赋值给 device_id。
    if (parser.parseGreater()) return Type();		//如果解析整数失败，接着尝试解析结束符 >，失败就返回空类型。
  //调用 MLIR 提供的 getChecked 工厂方法构造类型实例。传入当前上下文、刚解析出来的参数：dimensions、elementType、device_id。getChecked 内部会调用你实现的 verify() 函数，确保参数合法。成功返回类型实例，失败返回空类型。
  return parser.getChecked<NSTensorType>(parser.getContext(), dimensions,
                                         elementType, device_id);
}

//这是类型打印函数。
void NSTensorType::print(AsmPrinter &printer) const {
  printer << "<";
  for (int64_t dim : getShape()) {
    if (dim < 0) {
      printer << "?" << 'x';
    } else {
      printer << dim << 'x';
    }
  }
  printer.printType(getElementType());
  printer << ",";
  printer << getDeviceId();
  printer << ">";
}
}  // namespace mlir::north_star

#undef FIX

```

​	main文件，路径为3-define_type\main.cpp

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#include <cstddef>

#include "Dialect/NorthStar/IR/NorthStarDialect.h"
#include "Dialect/NorthStar/IR/NorthStarTypes.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/GPU/IR/GPUDialect.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Support/LLVM.h"

//测试方言能否正常注册
void CH2() {
  // 初始化方言注册器
  mlir::DialectRegistry registry;
  // 初始化上下文环境
  mlir::MLIRContext context(registry);
  // 加载/注册方言
  auto dialect = context.getOrLoadDialect<mlir::north_star::NorthStarDialect>();
  // 调用方言中的方法
  dialect->sayHello();
}

//内建类型
void typeBrief() {
  // 文件定义：llvm-project/mlir/include/mlir/IR/BuiltinTypes.td
  auto context = new mlir::MLIRContext;

  // 浮点数，每种位宽和标准定义一个
  auto f32 = mlir::Float32Type::get(context);
  llvm::outs() << "F32类型 :\t";
  f32.dump();

  auto bf16 = mlir::BFloat16Type::get(context);
  llvm::outs() << "BF16类型 :\t";
  bf16.dump();

  // Index 类型，机器相关的整数类型
  auto index = mlir::IndexType::get(context);
  llvm::outs() << "Index 类型 :\t";
  index.dump();

  // 整数类型, 参数: 位宽&&有无符号
  auto i32 = mlir::IntegerType::get(context, 32);
  llvm::outs() << "I32 类型 :\t";
  i32.dump();
  auto ui16 = mlir::IntegerType::get(context, 16, mlir::IntegerType::Unsigned);
  llvm::outs() << "UI16 类型 :\t";
  ui16.dump();

  // 张量类型,表示的是数据，不会有内存的布局信息。
  auto static_tensor = mlir::RankedTensorType::get({1, 2, 3}, f32);
  llvm::outs() << "静态F32 张量类型 :\t";
  static_tensor.dump();
  // 动态张量
  auto dynamic_tensor =
      mlir::RankedTensorType::get({mlir::ShapedType::kDynamic, 2, 3}, f32);
  llvm::outs() << "动态F32 张量类型 :\t";
  dynamic_tensor.dump();

  // Memref类型：表示内存
  auto basic_memref = mlir::MemRefType::get({1, 2, 3}, f32);
  llvm::outs() << "静态F32 内存类型 :\t";
  basic_memref.dump();
  // 带有布局信息的内存

  auto stride_layout_memref = mlir::MemRefType::get(
      {1, 2, 3}, f32, mlir::StridedLayoutAttr::get(context, 1, {6, 3, 1}));
  llvm::outs() << "连续附带布局信息的 F32 内存类型 :\t";
  stride_layout_memref.dump();
  // 使用affine 表示布局信息的内存
  auto affine_memref = mlir::MemRefType::get(
      {1, 2, 3}, f32,
      mlir::StridedLayoutAttr::get(context, 1, {6, 3, 1}).getAffineMap());
  llvm::outs() << "连续附带 affine 布局信息的 F32 内存类型 :\t";
  affine_memref.dump();
  // 动态连续附带 affine 布局信息的内存
  auto dynamic_affine_memref =
      mlir::MemRefType::get({mlir::ShapedType::kDynamic, 2, 3}, f32,
                            mlir::StridedLayoutAttr::get(
                                context, 1, {mlir::ShapedType::kDynamic, 3, 1})
                                .getAffineMap());
  llvm::outs() << "连续附带 affine 布局信息的动态 F32 内存类型 :\t";
  dynamic_affine_memref.dump();
  // 具有内存层级信息的内存
  auto L1_memref =
      mlir::MemRefType::get({mlir::ShapedType::kDynamic, 2, 3}, f32,
                            mlir::StridedLayoutAttr::get(
                                context, 1, {mlir::ShapedType::kDynamic, 3, 1})
                                .getAffineMap(),
                            1);
  llvm::outs() << "处于L1层级的 F32 内存类型 :\t";
  L1_memref.dump();
  // gpu 私有内存层级的内存
  context->getOrLoadDialect<mlir::gpu::GPUDialect>();
  auto gpu_memref =
      mlir::MemRefType::get({mlir::ShapedType::kDynamic, 2, 3}, f32,
                            mlir::StridedLayoutAttr::get(
                                context, 1, {mlir::ShapedType::kDynamic, 3, 1})
                                .getAffineMap(),
                            mlir::gpu::AddressSpaceAttr::get(
                                context, mlir::gpu::AddressSpace::Private));
  llvm::outs() << "连续附带 affine 布局信息的动态 F32 Gpu Private内存类型 :\t";
  gpu_memref.dump();

  // 向量类型,定长的一段内存
  auto vector_type = mlir::VectorType::get(3, f32);
  llvm::outs() << "F32 1D向量类型 :\t";
  vector_type.dump();

  auto vector_2D_type = mlir::VectorType::get({3, 3}, f32);
  llvm::outs() << "F32 2D向量类型 :\t";
  vector_2D_type.dump();
  delete context;
}

//注册并加载自定义方言。
void CH3() {
  typeBrief();
  // 初始化方言注册器
  mlir::DialectRegistry registry;
  // 初始化上下文环境
  mlir::MLIRContext context(registry);
  // 加载/注册方言
  auto dialect = context.getOrLoadDialect<mlir::north_star::NorthStarDialect>();
  // 调用方言中的方法
  dialect->sayHello();
  // 静态 NSTensor
  mlir::north_star::NSTensorType ns_tensor =
      mlir::north_star::NSTensorType::get(&context, {1, 2, 3},
                                          mlir::Float32Type::get(&context), 3);
  llvm::outs() << "North Star Tensor 类型 :\t";
  ns_tensor.dump();
  // 动态 NSTensor
  mlir::north_star::NSTensorType dy_ns_tensor =
      mlir::north_star::NSTensorType::get(&context,
                                          {mlir::ShapedType::kDynamic, 2, 3},
                                          mlir::Float32Type::get(&context), 3);
  llvm::outs() << "动态 North Star Tensor 类型 :\t";
  dy_ns_tensor.dump();
}

int main() { CH3(); }
```

# 第三章.内建Attribute及自定义Attribute

## 3.1内建Attribute

​	在 **MLIR**（Multi-Level Intermediate Representation）中，**Attribute（属性）** 是一种 **不可变（immutable）** 的、用来描述附加信息的数据结构。简单的说，在 MLIR 中，**Attribute 就是“不可变的常量数据”**，比如数字、字符串、布尔值、数组、名字等等，用来给操作（operation）添加信息。

​	例如

```tablegen
%a = arith.constant 42 : i32	//这条语句表示给变量 %a 赋值一个常量 42。42 是一个 Attribute，类型是 IntegerAttr，意思是整数属性
```

```tablegen
%b = arith.constant dense<[1.0, 2.0]> : tensor<2xf32>	//这里的 [1.0, 2.0] 是一个数组型属性。它表示一个固定的数组常量
```

​	MLIR 提供了一系列 内建属性 类型，文件路径为third_party\llvm-project\mlir\include\mlir\IR\BuiltinAttributes.td

​	一些常用的attribute如下

| 名称                 | C++ 类型                   | 示例                           | 说明                               |
| -------------------- | -------------------------- | ------------------------------ | ---------------------------------- |
| `BoolAttr`           | `mlir::BoolAttr`           | `true`                         | 布尔值属性                         |
| `IntegerAttr`        | `mlir::IntegerAttr`        | `42 : i32`                     | 整数属性，携带类型信息             |
| `FloatAttr`          | `mlir::FloatAttr`          | `3.14 : f32`                   | 浮点属性                           |
| `StringAttr`         | `mlir::StringAttr`         | `"hello"`                      | 字符串属性                         |
| `ArrayAttr`          | `mlir::ArrayAttr`          | `[42, "hello"]`                | 属性列表                           |
| `DenseElementsAttr`  | `mlir::DenseElementsAttr`  | `[1, 2, 3] : tensor<3xi32>`    | 稠密张量常量                       |
| `SparseElementsAttr` | `mlir::SparseElementsAttr` | -                              | 稀疏张量常量                       |
| `SymbolRefAttr`      | `mlir::SymbolRefAttr`      | `@func`                        | 引用另一个符号（函数、变量）       |
| `TypeAttr`           | `mlir::TypeAttr`           | `i32`                          | 用来存储类型                       |
| `UnitAttr`           | `mlir::UnitAttr`           | `unit`                         | 空属性，用于表示 flag              |
| `DictionaryAttr`     | `mlir::DictionaryAttr`     | `{name = "value"}`             | 键值对结构                         |
| `OpaqueAttr`         | `mlir::OpaqueAttr`         | -                              | 不可解析但可转发的属性             |
| `AffineMapAttr`      | `mlir::AffineMapAttr`      | `affine_map<(d0) -> (d0 * 2)>` | Affine Map 属性                    |
| `AffineExprAttr`     | `mlir::AffineExprAttr`     | `affine<d0 + 2>`               | Affine 表达式属性                  |
| `ElementsAttr`       | `mlir::ElementsAttr`       | 父类                           | 所有 `Dense/Sparse` 元素属性的基类 |
| `FlatSymbolRefAttr`  | `mlir::FlatSymbolRefAttr`  | `@func`                        | 一种简化版本的 SymbolRefAttr       |

​	内建属性的基类：代码定义了这段定义了一个 TableGen 类模板，继承类AttrDef，名字叫 `Builtin_Attr`，它有4个参数。

```tablegen
// Base class for Builtin dialect attributes.
class Builtin_Attr<string name, string attrMnemonic, list<Trait> traits = [],
                   string baseCppClass = "::mlir::Attribute">
    : AttrDef<Builtin_Dialect, name, traits, baseCppClass> {
  let mnemonic = ?;
  let attrName = "builtin." # attrMnemonic;
}
```

| 参数名         | 类型          | 说明                                                  |
| -------------- | ------------- | ----------------------------------------------------- |
| `name`         | `string`      | 这个属性在 C++ 中的类名，比如 `"BoolAttr"`            |
| `attrMnemonic` | `string`      | 用于 `.mlir` IR 文本语法中显示的关键字，比如 `"bool"` |
| `traits`       | `list<Trait>` | 该属性支持的 trait（如接口或校验逻辑）默认是空列表    |
| `baseCppClass` | `string`      | 指定该属性的 C++ 基类，默认是 `mlir::Attribute`       |

## 3.2自定义Attribute

​	编写tablegen的文件，路径为4-define_attribute\include\Dialect\NorthStar\IR\NorthStarAttrs.td

```tablegen
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#ifndef DIALECT_NORTH_STAR_ATTRS_TD
#define DIALECT_NORTH_STAR_ATTRS_TD

include "mlir/IR/EnumAttr.td"
include "Dialect/NorthStar/IR/NorthStarEunms.td"


class NorthStar_Attr<string name, string attrMnemonic, list<Trait> traits = [],
                   string baseCppClass = "::mlir::Attribute">
    : AttrDef<NorthStar_Dialect, name, traits, baseCppClass> {
  let mnemonic = attrMnemonic;
  let attrName = dialect.name # "." # attrMnemonic;
  let genStorageClass = 1;		//自动生成 Storage 类
  let hasStorageCustomConstructor = 0;		//不自定义 Storage 构造函数（用默认的）
  let skipDefaultBuilders = 0;	 //生成默认的builders
  let genVerifyDecl = 0;		//不生成 verify() 方法声明
}

//自定义 Attribute 实体
def NorthStar_DataParallelism: NorthStar_Attr<"DataParallelism", "DP", []>{
  let parameters = (ins "int64_t":$DP_nums);
  let assemblyFormat = [{
    `<`
      `DP` `=` $DP_nums
    `>`
  }];
}

#endif //DIALECT_NORTH_STAR_ATTRS_TD
```

​	然后通过cmake文件让 MLIR 的 TableGen 工具自动生成 NorthStar 方言相关的 C++ 文件

```cmake
set(LLVM_TARGET_DEFINITIONS NorthStarAttrs.td)
# 生成NorthStar Dialect 的声明
mlir_tablegen(NorthStarDialect.h.inc --gen-dialect-decls -dialect=north_star)
# 生成NorthStar Dialect 的实现
mlir_tablegen(NorthStarDialect.cpp.inc --gen-dialect-defs -dialect=north_star)
# 生成NorthStar Type 的声明
mlir_tablegen(NorthStarTypes.h.inc -gen-typedef-decls -dialect=north_star)
# 生成NorthStar Type 的实现
mlir_tablegen(NorthStarTypes.cpp.inc -gen-typedef-defs -dialect=north_star)
# 生成NorthStar Attr 的声明
mlir_tablegen(NorthStarAttrs.h.inc -gen-attrdef-decls -dialect=north_star)
# 生成NorthStar Attr 的实现
mlir_tablegen(NorthStarAttrs.cpp.inc -gen-attrdef-defs -dialect=north_star)
# 将生成的命令们定义为为target
add_public_tablegen_target(NorthStarDialectIncGen${ch_num})
```

​	生成后的声明和实现分别在build\4-define_attribute\include\Dialect\NorthStar\IR\NorthStarAttrs.h.inc和build\4-define_attribute\include\Dialect\NorthStar\IR\NorthStarAttrs.cpp.inc中。

# 第四章.自定义Operation

​	先看一下5-define_operation\include\Dialect\NorthStar\IR\NorthStarTypes.td，这个是我们自定义类型的tablegen文件。新加了一个NorthStar_BufferType类型。

```tablegen
// 定义 BufferType，继承 NorthStar_Type，C++ 名称 "Buffer"，缩写 "buffer"。
def NorthStar_BufferType : NorthStar_Type<"Buffer","buffer",[]>{
  let summary = " the summary of north-star buffer type";	// 简要描述和详细描述。

  let description = "description of north-star buffer type";

  // 构造参数只有一个:ArrayRefParameter<"int64_t">:$devices：一个设备ID数组，表示 Buffer 绑定的多个设备。
  let parameters = (ins 
    ArrayRefParameter<"int64_t">:$devices
  );

  let genStorageClass = 1;	//生成 Storage 类，不自定义构造。
  let hasStorageCustomConstructor = 0;

  let assemblyFormat = "`<`$devices`>`";	//assembly 格式定义，打印和解析时格式是 <devices>，例如 <0,1,2> 表示设备0、1、2。

  let skipDefaultBuilders = 0;		// 不跳过默认构造器。

  let genVerifyDecl = 1;		// 生成 verify 声明。
}
```

​	然后是6-define_interface\include\Dialect\NorthStar\IR\NorthStarConstraints.td，这是对类型的约束。

```
// 定义了一个名为 AnyNSTensor 的类型约束（def是 TableGen 定义关键字）。继承于 Type<...>，表示这是一个类型约束的定义。
// And<[ ... ]>：表示多个条件的逻辑“与”，所有条件必须同时满足。CPred<"条件表达式">：用 C++ 表达式作为谓词断言，返回 true 或 false，$_self 是当前类型对象的占位符。
// ::mlir::isa<::mlir::north_star::NSTensorType>($_self)	这是调用 LLVM/MLIR 的 isa<T>(obj) 模板函数，判断 $_self 是否是 NSTensorType 类型或其子类。
// ::mlir::cast<::mlir::north_star::NSTensorType>($_self).getShape().size() > 0		cast首先将 $_self 强制转换（cast）为 NSTensorType。	然后调用 getShape() 方法，返回形状（shape）信息，一般是维度列表。	.size() > 0 表示该张量类型必须有非空的 shape，至少有一个维度。

def AnyNSTensor : Type<And<[CPred<"::mlir::isa<::mlir::north_star::NSTensorType>($_self)">,
                            CPred<"::mlir::cast<::mlir::north_star::NSTensorType>($_self).getShape().size() > 0">]>>;


// 与上面注释类似
def AnyBuffer  : Type<And<[CPred<"::mlir::isa<::mlir::north_star::BufferType>($_self)">,
                            CPred<"::mlir::cast<::mlir::north_star::BufferType>($_self).getDevices().size() > 0">]>>;
```

​	自定义op的tablegen文件路径在5-define_operation\include\Dialect\NorthStar\IR\NorthStarOps.td

```tablegen
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#ifndef DIALECT_NORTH_STAR_OPS_TD
#define DIALECT_NORTH_STAR_OPS_TD

include "Dialect/NorthStar/IR/NorthStarAttrs.td"


// 自定义op基类，继承自 Op
// 该类定义了op的基本属性和行为
// mnemonic 是操作符的名字（如 "add"）
class NorthStar_Op<string mnemonic, list<Trait> traits = []>
    : Op<NorthStar_Dialect, mnemonic, traits> {
  // 拼接字符串用于文档注释，例如 "north_star::AddOp op"
  let summary = cppNamespace#opName#"op";

  let description = "$_name op";
}

// 单目op
// mnemonic,操作名称（如 "exp"）    OperandType：输入类型（如 AnyNSTensor）
// resultType：默认与输入类型相同   traits：支持附加特性（比如 NoSideEffect）   attributes：额外参数，例如 axis。
class NorthStar_UnaryOp<string mnemonic,Type OperandType, Type resultType = OperandType,list<Trait> traits = [], dag attributes = (ins)>:
    NorthStar_Op<mnemonic, traits#[]>{
    // 表示操作有一个输入 input，类型是 OperandType；同时拼接上额外的 attributes。
    let arguments = !con((ins
        OperandType:$input),
        attributes
        );

    // 表示操作有一个输出 result，类型是 resultType。
    let results = (outs
        resultType:$result);
}

//双目op
class NorthStar_BinaryOp<string mnemonic,Type OperandType, Type resultType = OperandType,list<Trait> traits = [], dag attributes = (ins)>:
    NorthStar_Op<mnemonic, traits#[]>{
    // 表示操作有两个输入 lhs(左操作数) 和 rhs(右操作数)，类型都是 OperandType；同时拼接上额外的 attributes。
    let arguments = !con((ins
        OperandType:$lhs,
        OperandType:$rhs),
        attributes
        );

    let results = (outs
        resultType:$result);
}

// 常量操作     接收一个 ElementsAttr 类型的属性作为值；输出一个 AnyNSTensor 类型结果。
def NorthStar_ConstOp : NorthStar_Op<"const",[]>{
    let arguments = (ins
        ElementsAttr:$value);
    let results = (outs
        AnyNSTensor:$result);
}

def NorthStar_SoftmaxOp : NorthStar_UnaryOp<"softmax",AnyNSTensor, AnyNSTensor, [], (ins I64Attr:$axis)>{
    let hasVerifier = 1;    // cpp 文件中实现 verify() 方法。
    let builders = [
        OpBuilder<(ins "::mlir::Value":$input, "int64_t":$axis) , 
            [{
                $_state.addOperands(input);
                $_state.getOrAddProperties<Properties>().axis = $_builder.getIntegerAttr(odsBuilder.getIntegerType(64,true), axis);
                $_state.addTypes(input.getType());
            }]>

    ];
}

// 一元指数操作 接收一个 AnyNSTensor，返回同类型；
def NorthStar_ExpOp : NorthStar_UnaryOp<"exp",AnyNSTensor>{
    let builders = [
        OpBuilder<(ins "::mlir::Value":$input) , 
            [{
                $_state.addOperands(input);
                $_state.addTypes(input.getType());
            }]>
    ];
}

// 四则运算
def NorthStar_AddOp : NorthStar_BinaryOp<"add",AnyNSTensor>;
def NorthStar_SubOp : NorthStar_BinaryOp<"sub",AnyNSTensor>;
def NorthStar_MulOp : NorthStar_BinaryOp<"mul",AnyNSTensor>;
def NorthStar_DivOp : NorthStar_BinaryOp<"div",AnyNSTensor>;


def NorthStar_AllToAllOp : NorthStar_Op<"all_to_all",[]>{
    let arguments = (ins
        AnyBuffer:$input,
        AnyBuffer:$output
    );
}

// 接收若干个 Tensor，返回一个 Buffer
def NorthStar_BufferOp : NorthStar_Op<"buffer",[]>{
    let description = "将 多个device_id 的tensor 组合成 一个 buffer";
    let arguments = (ins
        Variadic<AnyNSTensor>:$tensors		//输入是多个AnyNSTensor类型的张量
    );
    let results = (outs
        AnyBuffer:$result);
    let hasVerifier = 1;
    
    // <(ins "::mlir::ValueRange":$tensors),[{ ... }]> 指明了构造函数的参数：输入参数是一个类型为 ::mlir::ValueRange 的变量，名字是 $tensors。       // ValueRange是MLIR 中表示一组 Value（操作的输入张量）的类型，可以看成张量的数组或序列。后面大括号里的 { ... } 是构造器的具体实现代码。
    // $_state.addOperands(tensors)；$_state 是一个内置变量，表示“正在构造的操作状态”（OperationState 对象）。addOperands(tensors) 是把输入的       // $tensors（多个张量）作为操作的操作数（Operands）加入当前操作。这一步把所有传入的张量“绑定”给操作，操作的输入就确定了。
    // ::llvm::SmallVector<int64_t> devices;定义了一个空的 SmallVector<int64_t> 容器，命名为 devices。SmallVector 是 LLVM 提供的类似动态数组的     // 容器。这个容器用来存储每个输入张量对应的设备编号（device_id）。
    // for (auto tensor : tensors) { ... }	遍历所有输入张量 $tensors。auto tensor 是循环变量，表示当前遍历的单个张量（类型是 mlir::Value）。
    // auto tensor_type = llvm::cast<::mlir::north_star::NSTensorType>(tensor.getType());
    // tensor.getType()：获得当前张量的类型，类型是 mlir::Type。
    // llvm::cast<...>(...)：安全地将类型转换为特定子类型 NSTensorType，这是 NorthStar 方言自定义的张量类型。
    // 这里断言输入的每个张量的类型都是 NSTensorType，否则会报错。
    // devices.push_back(tensor_type.getDeviceId());从 NSTensorType 中获取设备ID（getDeviceId() 返回一个 int64_t）。把这个设备ID加入 devices       // 容器，收集所有输入张量对应的设备ID。
    // $_state.addTypes(::mlir::north_star::BufferType::get($_state.getContext(), devices));
    // 构造一个 BufferType，它是 NorthStar 方言中表示设备 buffer 的类型。
    // 调用静态方法 BufferType::get：传入当前操作的上下文（$_state.getContext()）	传入刚刚收集的设备ID列表（devices）
    // 把生成的 BufferType 类型加入到当前操作的结果类型列表中（这个操作只有一个结果）。
    let builders = [
        OpBuilder<(ins "::mlir::ValueRange":$tensors) , 
            [{
                $_state.addOperands(tensors);
                ::llvm::SmallVector<int64_t> devices;
                for (auto tensor : tensors) {
                    auto tensor_type =
                        llvm::cast<::mlir::north_star::NSTensorType>(tensor.getType());
                    devices.push_back(tensor_type.getDeviceId());
                }
                $_state.addTypes(::mlir::north_star::BufferType::get($_state.getContext(), devices));
            }]>
    ];
}

def NorthStar_GetTensorOp: NorthStar_Op<"get_tensor",[]>{
    let description = "从buffer中取出指定device_id的tensor";
    let arguments = (ins
        AnyBuffer:$buffer,
        I64Attr:$device_id
    );
    let results = (outs
        AnyNSTensor:$result);
    let hasVerifier = 1;
}

// 通用打印操作；   输入可以是任何类型；
def NorthStar_PrintOp: NorthStar_Op<"print",[]>{
    let arguments = (ins
        AnyType:$input
    );
}


#endif // INCLUDE_LLCOMPILER_DIALECT_NorthStar_IR_LLHOPS_TD_

```

# 第五章.自定义Interface

## 5.1内建Interface	

​	在 **MLIR（Multi-Level Intermediate Representation）** 中，`Interface` 是一种 **可插拔的机制**，用于给 **类型（Type）**、**属性（Attribute）** 或 **操作（Operation）** 增加一组统一的功能或行为约定。它的核心作用是 **通过抽象定义一组方法，让多个类实现相同的接口，从而实现行为上的统一和灵活扩展**，这和 C++ 的虚函数或 Java 的接口类似，但在 MLIR 中更灵活、表意更强，并且支持 TableGen 自动生成代码。

​	MLIR中一些常用内建Interface如下。

​	Type Interfaces（类型接口）

| 接口名                       | 用途说明                                                     |
| ---------------------------- | ------------------------------------------------------------ |
| `ShapedTypeInterface`        | 表示具有“形状”的类型（如 Tensor、MemRef），提供维度、元素类型、动态维度等接口 |
| `MemRefElementTypeInterface` | 表示可以作为 MemRef 元素的类型（例如整数、浮点类型等）       |
| `TypedTypeInterface`         | 表示带有类型的类型，用于支持 `getElementType()` 等操作       |
| `SubElementTypeInterface`    | 支持对子类型进行递归访问与替换，用于分析或转换嵌套类型结构   |

​	Attribute Interfaces（属性接口）

| 接口名                      | 用途说明                                                   |
| --------------------------- | ---------------------------------------------------------- |
| `TypedAttrInterface`        | 表示拥有类型的 Attribute（如 DenseElementsAttr）           |
| `ElementsAttrInterface`     | 表示元素型 Attribute，支持以多种方式遍历元素值             |
| `MemRefLayoutAttrInterface` | 表示可用作 MemRef layout 的属性（支持 stride/offset 表达） |

​	Operation Interfaces（操作接口）

| 接口名                    | 用途说明                                                     |
| ------------------------- | ------------------------------------------------------------ |
| `InferTypeOpInterface`    | 支持根据操作输入自动推导输出类型                             |
| `MemoryEffectOpInterface` | 表示操作对内存的读写影响                                     |
| `RegionBranchOpInterface` | 用于表示操作中包含的控制流区域（如 if、while）               |
| `LoopLikeOpInterface`     | 表示类似于 for/while 的循环操作，暴露 loop 结构              |
| `CallOpInterface`         | 用于表示调用函数/操作的接口（如 call）                       |
| `ViewLikeOpInterface`     | 表示行为类似 view 的操作（形状更改但不复制数据）             |
| `ControlFlowInterfaces`   | 包括 `BranchOpInterface`、`BranchOpInterface`, 提供控制流跳转相关接口 |

## 	5.2自定义Interface

​	首先看一下BuiltinTypeInteface.td文件，路径为third_party\llvm-project\mlir\include\mlir\IR\BuiltinTypeInterfaces.td

```tablegen
//===- BuiltinTypeInterfaces.td - Builtin type interfaces --*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains definitions for type interfaces that closely interact with
// attributes, types, and operations in the builtin dialect.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_IR_BUILTINTYPEINTERFACES_TD_
#define MLIR_IR_BUILTINTYPEINTERFACES_TD_

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// MemRefElementTypeInterface
//===----------------------------------------------------------------------===//

def MemRefElementTypeInterface : TypeInterface<"MemRefElementTypeInterface"> {
  let cppNamespace = "::mlir";
  let description = [{
    Indication that this type can be used as element in memref types.

    Implementing this interface establishes a contract between this type and the
    memref type indicating that this type can be used as element of ranked or
    unranked memrefs. The type is expected to:

      - model an entity stored in memory;
      - have non-zero size.

    For example, scalar values such as integers can implement this interface,
    but indicator types such as `void` or `unit` should not.

    The interface currently has no methods and is used by types to opt into
    being memref elements. This may change in the future, in particular to
    require types to provide their size or alignment given a data layout.
  }];
}

//===----------------------------------------------------------------------===//
// ShapedType
//===----------------------------------------------------------------------===//

def ShapedTypeInterface : TypeInterface<"ShapedType"> {
  let cppNamespace = "::mlir";
  let description = [{
    This interface provides a common API for interacting with multi-dimensional
    container types. These types contain a shape and an element type.

    A shape is a list of sizes corresponding to the dimensions of the container.
    If the number of dimensions in the shape is unknown, the shape is "unranked".
    If the number of dimensions is known, the shape "ranked". The sizes of the
    dimensions of the shape must be positive, or kDynamic (in which case the
    size of the dimension is dynamic, or not statically known).
  }];
  let methods = [
    InterfaceMethod<[{
      Returns a clone of this type with the given shape and element type.

      If no shape is provided, the shape of this type is used. In that case, if
      this type is unranked, so is the resulting type.

      If a shape is provided, the resulting type is always ranked, even if this
      type is unranked.
    }],
    "::mlir::ShapedType", "cloneWith", (ins
      "::std::optional<::llvm::ArrayRef<int64_t>>":$shape,
      "::mlir::Type":$elementType
    )>,

    InterfaceMethod<[{
      Returns the element type of this shaped type.
    }],
    "::mlir::Type", "getElementType">,

    InterfaceMethod<[{
      Returns if this type is ranked, i.e. it has a known number of dimensions.
    }],
    "bool", "hasRank">,

    InterfaceMethod<[{
      Returns the shape of this type if it is ranked, otherwise asserts.
    }],
    "::llvm::ArrayRef<int64_t>", "getShape">,
  ];
  let extraClassDeclaration = [{
    /// 定义一个常量 kDynamic，用来表示“动态维度”的标记值，使用 int64_t 最小值来标识。
    static constexpr int64_t kDynamic =
        std::numeric_limits<int64_t>::min();

    /// Whether the given dimension size indicates a dynamic dimension.
    /// 判断某个维度值 dValue 是否是动态维度（即是否等于 kDynamic）。
    static constexpr bool isDynamic(int64_t dValue) {
      return dValue == kDynamic;
    }

    /// Whether the given shape has any size that indicates a dynamic dimension.
    /// 判断一个形状（数组）中是否包含至少一个动态维度。
    static bool isDynamicShape(ArrayRef<int64_t> dSizes) {
      return any_of(dSizes, [](int64_t dSize) { return isDynamic(dSize); });
    }

    /// Return the number of elements present in the given shape.
    /// 计算一个静态形状（所有维度均为常量）中的总元素个数，函数声明未定义，定义在 C++ 中。
    static int64_t getNumElements(ArrayRef<int64_t> shape);

    /// Return a clone of this type with the given new shape and element type.
    /// The returned type is ranked, even if this type is unranked.
    /// 基于新的 shape 和 elementType 生成一个副本（克隆），即使当前类型是 unranked，生成的类型也会是 ranked。
    auto clone(::llvm::ArrayRef<int64_t> shape, Type elementType) {
      return cloneWith(shape, elementType);
    }

    /// Return a clone of this type with the given new shape. The returned type
    /// is ranked, even if this type is unranked.
    /// 基于新的 shape 克隆当前类型，elementType 保持不变。返回类型同样是 ranked。
    auto clone(::llvm::ArrayRef<int64_t> shape) {
      return cloneWith(shape, getElementType());
    }
  }];

  let extraSharedClassDeclaration = [{
    /// Return a clone of this type with the given new element type. The
    /// returned type is ranked if and only if this type is ranked. In that
    /// case, the returned type has the same shape as this type.
    /// 基于新的 elementType 克隆当前类型。如果当前是 ranked，则保留形状；否则就不指定形状。
    auto clone(::mlir::Type elementType) {
      return $_type.cloneWith(/*shape=*/std::nullopt, elementType);
    }

    /// If an element type is an integer or a float, return its width. Otherwise,
    /// abort.
    /// 获取当前类型中元素类型（整型或浮点型）的位宽（bit 数）。若不是整数或浮点类型会报错。
    unsigned getElementTypeBitWidth() const {
      return $_type.getElementType().getIntOrFloatBitWidth();
    }

    /// If this is a ranked type, return the rank. Otherwise, abort.
    /// 获取当前类型的秩（rank），即维度个数。若是 unranked 会触发断言。
    int64_t getRank() const {
      assert($_type.hasRank() && "cannot query rank of unranked shaped type");
      return $_type.getShape().size();
    }

    /// If it has static shape, return the number of elements. Otherwise, abort.
    /// 返回总元素个数，但仅限 static shape。如果有动态维度则会断言失败。
    int64_t getNumElements() const {
      assert(hasStaticShape() && "cannot get element count of dynamic shaped type");
      return ::mlir::ShapedType::getNumElements($_type.getShape());
    }

    /// Returns true if this dimension has a dynamic size (for ranked types);
    /// aborts for unranked types.
    /// 判断指定维度是否为动态大小。要求当前是 ranked 类型。
    bool isDynamicDim(unsigned idx) const {
      assert(idx < getRank() && "invalid index for shaped type");
      return ::mlir::ShapedType::isDynamic($_type.getShape()[idx]);
    }

    /// Returns if this type has a static shape, i.e. if the type is ranked and
    /// all dimensions have known size (>= 0).
    /// 判断是否为静态形状，即要求是 ranked 且所有维度都不是动态。
    bool hasStaticShape() const {
      return $_type.hasRank() &&
             !::mlir::ShapedType::isDynamicShape($_type.getShape());
    }

    /// Returns if this type has a static shape and the shape is equal to
    /// `shape` return true.
    /// 不仅判断是否是静态形状，还要和给定 shape 完全一致。
    bool hasStaticShape(::llvm::ArrayRef<int64_t> shape) const {
      return hasStaticShape() && $_type.getShape() == shape;
    }

    /// If this is a ranked type, return the number of dimensions with dynamic
    /// size. Otherwise, abort.
    /// 统计当前类型中有多少个维度是动态的。要求是 ranked 类型。
    int64_t getNumDynamicDims() const {
      return llvm::count_if($_type.getShape(), ::mlir::ShapedType::isDynamic);
    }

    /// If this is ranked type, return the size of the specified dimension.
    /// Otherwise, abort.
    /// 获取第 idx 个维度的大小（不论是否是动态），需确保类型为 ranked 且索引合法。
    int64_t getDimSize(unsigned idx) const {
      assert(idx < getRank() && "invalid index for shaped type");
      return $_type.getShape()[idx];
    }

    /// Returns the position of the dynamic dimension relative to just the dynamic
    /// dimensions, given its `index` within the shape.
    /// 给定某个动态维度的索引 index，计算它在所有动态维度中的相对编号。
    /// 比如 shape 为 [2, ?, 5, ?]，其中 index 为 3（对应第二个 ?），它是所有动态维度中的第 2 个（返回 1）。
    unsigned getDynamicDimIndex(unsigned index) const {
      assert(index < getRank() && "invalid index");
      assert(::mlir::ShapedType::isDynamic(getDimSize(index)) && "invalid index");
      return llvm::count_if($_type.getShape().take_front(index),
                            ::mlir::ShapedType::isDynamic);
    }
  }];
}

#endif // MLIR_IR_BUILTINTYPEINTERFACES_TD_

```

​	然后是在NorthStarTypes.td(路径为6-define_interface\include\Dialect\NorthStar\IR\NorthStarTypes.td)中添加额外成员函数声明。

```tablegen
/// 这里挂接了ShapedTypeInterface，即[ShapedTypeInterface]
def NorthStar_TensorType : NorthStar_Type<"NSTensor","ns_tensor",[ShapedTypeInterface],"::mlir::TensorType">{
  // 概述
  let summary = " the summary of north-star tensor type";

  // 方言的详细描述
  let description = "description of north-star tensor type";

  // 参数
  let parameters = (ins
    ArrayRefParameter<"int64_t">:$shape,
    "Type":$elementType,
    "int64_t":$device_id
  );

  // 是否生成StorageClass, 无特殊情况，建议设为ture
  let genStorageClass = 1;
  
  // 不建议改动
  let hasStorageCustomConstructor = 0;

  // 额外的builder 声明
  let builders = [
    TypeBuilder<(ins 
        "::mlir::ArrayRef<int64_t>":$shape,
        "::mlir::Type":$elementType),[{
      return $_get(elementType.getContext(), shape, elementType, 0);
    }]>
  ];

  let hasCustomAssemblyFormat = 1;
  // let assemblyFormat = "`<`$shape`,`$elementType`,`$device_id`>`";

  // 跳过默认的builder函数
  let skipDefaultBuilders = 0;

  // 是否生成类型检验的函数声明
  let genVerifyDecl = 1;
  
  /// 挂接了 ShapedType::Trait<T> 中的多个常用函数，这允许在 NSTensorType 实例上直接调用
  /// 例如NSTensorType ty = ...;
  /// ty.getRank();               // from ShapedType
  /// ty.getElementType();        // 来自接口或继承
  /// ty.getNumElements();
  let extraClassDeclaration = [{
  	/// 把 ShapedType::Trait<NSTensorType> 中的 getElementTypeBitWidth() 函数“引入”为 NSTensorType 的成员函数。获取元素类型的位宽
    using ::mlir::ShapedType::Trait<NSTensorType>::getElementTypeBitWidth;
    /// 返回张量的秩（rank），也就是 shape.size() 的值。
    using ::mlir::ShapedType::Trait<NSTensorType>::getRank;
    /// 返回元素个数。只对所有维度静态的 tensor 有意义（否则返回 std::nullopt）
    using ::mlir::ShapedType::Trait<NSTensorType>::getNumElements;
    /// 判断某个维度是不是动态维度（即该维度是 -1）
    using ::mlir::ShapedType::Trait<NSTensorType>::isDynamicDim;
    /// 判断所有维度是否都是静态的（即没有 -1）
    using ::mlir::ShapedType::Trait<NSTensorType>::hasStaticShape;
    /// 返回多少个维度是动态的（也就是 -1 的个数）
    using ::mlir::ShapedType::Trait<NSTensorType>::getNumDynamicDims;
    /// 获取指定维度的大小（可能是正整数或 -1）
    using ::mlir::ShapedType::Trait<NSTensorType>::getDimSize;
    /// 获取在某个维度是第几个“动态维度”。比如第 2 维是 -1，它可能是动态维度的第一个。
    using ::mlir::ShapedType::Trait<NSTensorType>::getDynamicDimIndex;

    /// 自定义的 clone() 方法族
    /// 克隆一个新的类型，可以选择替换 shape 和 elementType。如果 shape 是空的，就保留当前 shape。
    ::mlir::ShapedType cloneWith(::std::optional<::llvm::ArrayRef<int64_t>> shape, ::mlir::Type type){
        if(shape)
          return mlir::north_star::NSTensorType::get(getContext(), *shape, type);
        return mlir::north_star::NSTensorType::get(getContext(), getShape(), type);
    }
    /// 克隆当前类型，但替换 shape 和 device_id，elementType 保持不变。
    NSTensorType clone(::mlir::ArrayRef<int64_t> shape,int64_t device_id) const {
      return NSTensorType::get(getContext(), shape, getElementType(),device_id);
    }
    /// 克隆当前类型，替换 shape 和 elementType，device_id 保持不变
    NSTensorType clone(::mlir::ArrayRef<int64_t> shape, ::mlir::Type elementType) const {
      return NSTensorType::get(getContext(), shape, elementType,getDeviceId());
    }
    /// 只替换 shape，其他字段保持不变。
    NSTensorType clone(::mlir::ArrayRef<int64_t> shape) const {
      return NSTensorType::get(getContext(), shape, getElementType(),getDeviceId());
    }
    /// 只替换 elementType。
    NSTensorType clone(::mlir::Type elementType) const {
      return NSTensorType::get(getContext(), getShape(), elementType,getDeviceId());
    }
    /// 完全克隆自己（拷贝构造）。
    NSTensorType clone() const {
      return NSTensorType::get(getContext(), getShape(), getElementType(),getDeviceId());
    }
    }];
}
```

​		

​	下面是自定义Interface的tablegen文件，路径为6-define_interface\include\Interfaces\DistributeParallelismInterfaces.td

```
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distribute under the License is distribute on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
#ifndef INTERFACES_DISTRIBUTE_PARALLELISM_INTERFACES_TD
#define INTERFACES_DISTRIBUTE_PARALLELISM_INTERFACES_TD
include "mlir/IR/Interfaces.td"

// 定义一个属性接口，名为DistributeParallelAttr
def DistributeParallelAttr: AttrInterface<"DistributeParallelAttr">{
  let description = "Properties related to distribute parallelism";
  let cppNamespace = "::mlir";
  let methods = [];		// 空数组，表示此接口目前没有任何定义的方法，仅作为一个基础标识符接口使用。
  let extraClassDeclaration = "";		// 空数组，表示此接口目前没有任何定义的方法，仅作为一个基础标识符接口使用。
  let extraSharedClassDeclaration = "";	// 空数组，表示此接口目前没有任何定义的方法，仅作为一个基础标识符接口使用。
}

// 定义继承自 DistributeParallelAttr 的属性接口 DataParallelAttr,通过[DistributeParallelAttr]指定
def DataParallelAttr: AttrInterface<"DataParallelAttr",[DistributeParallelAttr]>{
  let description = "Properties related to distribute parallelism";
  let cppNamespace = "::mlir";
  
  // 定义了两个接口方法:
  // 1.getDPNums()：返回类型是 int64_t。注释说明是“DP 数量”，即数据并行的数量。
  // 2.getDevices():返回类型是 ::llvm::ArrayRef<int64_t>，即一组整数设备编号。注释说明是“设备编号”，表示参与并行计算的设备列表。
  // 这两个方法要求实现这个接口的 Attribute 类必须提供这两个成员函数。
  let methods = [
    InterfaceMethod<[{
      DP 数量.
    }],
    "int64_t", "getDPNums">,

    InterfaceMethod<[{
      设备编号.
    }],
    "::llvm::ArrayRef<int64_t>", "getDevices">,
  ];
  let extraClassDeclaration = "";
  let extraSharedClassDeclaration = "";
}

// 定义支持数据并行的操作接口
def SupportedDataParallelismOp: OpInterface<"SupportedDataParallelismOp">{
  let description = "Properties related to data parallelism";
  let cppNamespace = "::mlir";
  let methods = [
    InterfaceMethod<
      /*desc=*/        "进行数据并行的变换",
      /*returnType=*/  "::mlir::LogicalResult",
      /*methodName=*/  "applyDataParallelism",
      /*args=*/        (ins "::mlir::DistributeParallelAttr":$attr),
      /*methodBody=*/  "",
      /*defaultImpl=*/ [{
      return llvm::failure();
      }]
      >,
      InterfaceMethod<
      /*desc=*/        "进行数据并行的变换",
      /*returnType=*/  "bool",
      /*methodName=*/  "supportedDataParallelism",
      /*args=*/        (ins),
      /*methodBody=*/  "",
      /*defaultImpl=*/ [{
      Operation* op = $_op.getOperation();
      if (op->getNumOperands() == 0) return true;
      auto base_type = op->getOperand(0).getType();
      if (!isa<mlir::ShapedType>(base_type)) return false;
      for (auto operand : op->getOperands()) {
        if (operand.getType() != base_type) return false;
      }
      return true;
      }]
      >
      ];
  let extraClassDeclaration = "";
  let extraSharedClassDeclaration = "";
}

// 定义通用的分布式并行操作接口 DistributeParallelOp
def DistributeParallelOp:OpInterface<"DistributeParallelOp">{
  let description = "Properties related to distribute parallelism";
  let cppNamespace = "::mlir";
  let methods = [];
  let extraClassDeclaration = "";
  
  // 在 extraSharedClassDeclaration 中定义了两个 C++ 成员函数：
  // 1.	applyDistributeParallelism(const ::mlir::DistributeParallelAttr attr)：
  // 	该方法判断传入的 attr 是不是 DataParallelAttr。如果是，则判断该操作是否支持 SupportedDataParallelismOp 接口。
  // 	若支持，则调用 applyDataParallelism 完成转换。如果不是 DataParallelAttr 类型，触发错误 llvm_unreachable。最后返回失败。
  // 2.	supportedDistributeParallelism()：
  //	判断当前操作是否支持数据并行。通过尝试转换成 SupportedDataParallelismOp，调用它的接口方法。不支持则触发错误 llvm_unreachable。返回 false。
  let extraSharedClassDeclaration = [{
    // 实现并行变换
    ::mlir::LogicalResult applyDistributeParallelism(const ::mlir::DistributeParallelAttr attr){
      if (isa<mlir::DataParallelAttr>(attr)) {
        if (!isa<mlir::SupportedDataParallelismOp>($_op.getOperation())) return ::llvm::failure();
        return dyn_cast<mlir::SupportedDataParallelismOp>($_op.getOperation()).applyDataParallelism(attr);
      } else {
        llvm_unreachable("unsupported parallel type!");
      }
      return ::llvm::failure();
    };

    bool supportedDistributeParallelism(){
      if (isa<mlir::SupportedDataParallelismOp>($_op.getOperation())){
        return dyn_cast<mlir::SupportedDataParallelismOp>($_op.getOperation()).supportedDataParallelism();
      }else{
        llvm_unreachable("unsupported parallel type!");
      }
      return false;
    }
  }];
}

#endif // INTERFACES_DISTRIBUTE_PARALLELISM_INTERFACES_TD
```

​	使用mlir_tablegen工具生成c++文件

```cmake
set(LLVM_TARGET_DEFINITIONS DistributeParallelismInterfaces.td)
mlir_tablegen(DistributeParallelismOpInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(DistributeParallelismOpInterfaces.cpp.inc -gen-op-interface-defs)
mlir_tablegen(DistributeParallelismAttrInterfaces.h.inc -gen-attr-interface-decls)
mlir_tablegen(DistributeParallelismAttrInterfaces.cpp.inc -gen-attr-interface-defs)
add_public_tablegen_target(MLIRDistributeParallelismInterfacesIncGen${ch_num})


```

​	通过main函数验证 `NSTensorType` 类型支持 `ShapedTypeInterface`，验证 `DataParallelismAttr` 属性支持接口，最后构建完整模块并执行遍历应用接口方法 `applyDistributeParallelism()`。下面代码为main文件中的CH6部分。

```cpp
void CH6() {
  // 初始化方言注册器
  mlir::DialectRegistry registry;
  // 初始化上下文环境
  mlir::MLIRContext context(registry);
  // 加载/注册方言
  context.getOrLoadDialect<mlir::north_star::NorthStarDialect>();
  context.getOrLoadDialect<mlir::func::FuncDialect>();
  // shaped type interface
  auto f32 = mlir::Float32Type::get(&context);		//创建一个 f32 类型（浮点数类型）。
  auto dim = mlir::ShapedType::kDynamic;
  auto shape = mlir::SmallVector<int64_t>({dim, dim, 24});		//使用 kDynamic 表示前两个维度为动态维度（-1）。第三个维度是静态的 24。
  auto tensor_type =
      mlir::north_star::NSTensorType::get(&context, shape, f32, 0);		//创建tensor_type，传入shape，elementtype f32,device_id 0三个参数
  
    //将tensor_type转为shaped_type类型。用于调用 .clone()、.getNumElements()、.getShape() 等通用接口方法。
  auto shaped_type = mlir::cast<mlir::ShapedType>(tensor_type);
  
  //dump() 是调试用方法，会把类型信息打印到 llvm::outs()。这里分别打印 NSTensorType 自身和转换为 ShapedType 后的信息。
  llvm::outs() << "NSTensorType: \t";
  tensor_type.dump();
  llvm::outs() << "Shaped Type Interface:\t";
  shaped_type.dump();
 
  //测试 ShapedTypeInterface 中的 clone(ElementType) 方法。会保持 shape/device 不变，仅替换元素类型为f32。
  auto cloned_type = shaped_type.clone(f32);
  llvm::outs() << "Cloned Shaped Type Interface:\t";
  cloned_type.dump();
  
  // Attr interface
  //创建一个自定义的 DataParallelismAttr，表示并行度为 2。
  auto dp_attr = mlir::north_star::DataParallelismAttr::get(&context, 2);
  
  // getAbstractAttribute().getName()：属性注册时的名字。hasInterface(...)：检查这个属性是否注册了某个接口，这里检查的是DistributeParallelAttr
  // DistributeParallelAttr::getInterfaceID()：接口 ID，全局唯一的标识符。这段语句输出为north_star.DP has mlir::DataParallelAttr interface: 1
  llvm::outs() << dp_attr.getAbstractAttribute().getName()
               << " has mlir::DataParallelAttr interface: "
               << dp_attr.getAbstractAttribute().hasInterface(
                      mlir::DistributeParallelAttr::getInterfaceID())
               << "\n";
  // 这为上面检测接口方法的另一种写法。
  llvm::outs()
      << dp_attr.getAbstractAttribute().getName()
      << " has mlir::DataParallelAttr interface: "
      << dp_attr.hasPromiseOrImplementsInterface<mlir::DataParallelAttr>()
      << "\n";

  // 调用自定义的函数 getModule() 构造一个模块，包含：
  // 一个名为 "main" 的函数（func.func)
  // 函数参数/返回值是 NSTensorType<?x?x24xf32, 0>
  // 函数上挂了 dp_attr 属性
  // 函数体中有两个 SoftmaxOp 和一个 func.return
  // 输出结果为
  // "builtin.module"() <{sym_name = "NorthStar"}> ({
  // "func.func"() <{function_type = (!north_star.ns_tensor<128x128x24xf32,0>) -> !north_star.ns_tensor<128x128x24xf32,0>, sym_name =    /////"main"}> ({
  // ^bb0(%arg0: !north_star.ns_tensor<128x128x24xf32,0>):
  // %0 = "north_star.softmax"(%arg0) <{axis = 1 : si64}> : (!north_star.ns_tensor<128x128x24xf32,0>) -> /////!north_star.ns_tensor<128x128x24xf32,0>
  // %1 = "north_star.softmax"(%0) <{axis = 1 : si64}> : (!north_star.ns_tensor<128x128x24xf32,0>) -> /////!north_star.ns_tensor<128x128x24xf32,0>
  // "func.return"(%1) : (!north_star.ns_tensor<128x128x24xf32,0>) -> ()
  // }) {dp_attr = #north_star.DP<DP = 2 : 0, 1>} : () -> ()
  // }) : () -> ()
  mlir::OpBuilder builder(&context);
  auto loc = builder.getUnknownLoc();
  auto module = getModule(builder);
  module->dump();
  //遍历整个 module，找到所有 func::FuncOp
  module->walk([](mlir::func::FuncOp func) {
    // 如果这个函数拥有名为 "dp_attr" 的 Attribute，并且它实现了接口 DistributeParallelAttr，则继续
    if (auto dp_attr = llvm::dyn_cast_or_null<mlir::DistributeParallelAttr>(
            func->getAttr(KDPAttrName))) {
      // 遍历这个函数体内的操作，找出实现了接口 DistributeParallelOp 的 Op
      func->walk([&](mlir::Operation* op) {
        if (auto dis_op =
                llvm::dyn_cast_or_null<mlir::DistributeParallelOp>(op)) {
          // 调用接口方法 applyDistributeParallelism：这是在 InterfaceMethod 中定义的方法。如果返回 success()，说明成功“变换”。然后删除这个 op
          if (dis_op.applyDistributeParallelism(dp_attr).succeeded()) {
            llvm::outs() << "Apply DataParallelism to " << op->getName()
                         << "\n";
            op->erase();
          };
        }
      });
    }
  });
  module->dump();
}
int main() { CH6(); }
```

# 第六章.IR结构和基本数据结构

​	MLIR 中的 IR（Intermediate Representation，中间表示）结构是整个编译器基础的核心。

​	MLIR 的 IR 是一个树状结构（多层嵌套），如下图所示：

```
ModuleOp
 └── Region(s)
      └── Block(s)
           └── Operation(s)
                └── Region(s) (可嵌套)

```

​	1.ModuleOp：顶层容器，相当于程序的“根”，它是一个特殊的 Operation，代表一个程序模块，可以包含多个 Region。

​	2.Region：是一个控制流区域，包含一个或多个 Block，Operation 可以携带 Region，用来表示作用域、函数体、循环体等。

​	3.Block：是一组顺序执行的操作集合（Operation），拥有自己的参数（Block Argument）和 terminator（控制流终结指令，如 return）。

​	4.Operation：最基本的执行单位，可以是计算、调用、内存操作等。

​	例如

```
module {		//ModuleOp，是 MLIR IR 的顶层操作。		{ : 表示 module 包含一个 Region。这个 Region 会包含 Block，Block 中是顺序执行的操作。
  func @main() -> i32 {		//func : 声明一个函数。MLIR 标准方言中的 FuncOp。		@main : 函数的符号名称，等价于 llvm::Function::Name。									() : 函数参数为空（没有输入参数）。	-> i32 : 函数返回类型是一个 i32。		{: 函数体，是 FuncOp 的 Region。
    %0 = constant 42 : i32		//%0: 这个是一个 SSA 值的名称，表示这个操作的结果被命名为 %0。	constant: 是一个操作,表示创建一个常量值。
    return %0 : i32		// 返回%0，返回类型为i32
  }		// 函数体结束
}		// 模块结束
```

​	MLIR 的 IR 实际上由以下六种基本元素组成：

| 元素         | 说明                       |
| ------------ | -------------------------- |
| 1. Operation | 操作（基本执行单元）       |
| 2. Region    | 区域（控制流域）           |
| 3. Block     | 块（指令集合）             |
| 4. Value     | SSA 值（操作的输入和输出） |
| 5. Type      | 类型（Value 的类型）       |
| 6. Attribute | 属性（编译时常量元数据）   |

​	1.Operation : MLIR 的所有执行语义都通过 `Operation` 表达。比如操作名：如 `std.addf`, `func.return`, `mydialect.softmax`	操作数：输入值（Value）			      结果：输出值（Value）	类型：操作数和结果都有类型（Type）	属性（Attributes）：附加信息，如 axis, name, shape 等	匿名/命			      名 Region	（Location）源代码映射信息

​	2.Region ： Region 是一个控制流作用域,包含一个或多个 Block,一个 Operation 可以有多个 Region（如 `func`, `if`, `while`）。

​	3.Block ：Block 是一个 顺序执行的指令列表，并带有 SSA 参数和一个 terminator。Block 内容有Block 参数（参数是 Value）、Operation 序列（中间指令）、			Terminator Operation（最后一条必须是终止指令）

​	4.Value（SSA 值）：所有操作的输入和输出都是 `Value`。Value 是一个 **SSA 值**（Single Static Assignment），只定义一次，可以使用多次。
# 第七章.Pass的运行与定义

​	Pass是MLIR 中的核心概念之一：它是 MLIR 构建编译器最重要的模块单位之一，和 Rewrite Pattern 配合使用，承担整个 IR 优化与转换的核心职责。

​	Pass 是对 MLIR IR 进行遍历、分析、重写、优化的一段封装逻辑。可以把 Pass 看作“操作 IR 的程序函数”。

​	Pass的一些作用如下

| 作用                | 举例                                     |
| ------------------- | ---------------------------------------- |
| IR 优化             | 消除死代码、常量折叠、算子融合           |
| IR 转换             | 将 High-Level IR 转为 Low-Level IR       |
| Dialect Lowering    | 将自定义方言转为 linalg、LLVM IR         |
| 分析                | 比如内存分析、依赖分析、设备 placement   |
| Debug/打印/检测用途 | 比如打印所有 tensor 类型，验证 IR 合法性 |

​	Pass 的基本分类：

| 类型                      | 示例类名     | 作用单位                           |
| ------------------------- | ------------ | ---------------------------------- |
| `OperationPass<ModuleOp>` | 模块级别     | 处理整个 `module`                  |
| `OperationPass<FuncOp>`   | 函数级别     | 处理 `func.func @main()`           |
| `OperationPass<Block>`    | 基本块级     | 比较少用                           |
| `FunctionLikePass`        | 兼容函数接口 | 可以作用在所有 FunctionLike 操作上 |

​	Pass 的生命周期：1.注册 Pass（名字/标志）2.遍历 IR（Operation、Block）3.应用 Rewrite Pattern 或分析逻辑 4.修改 IR 或记录分析信息 5.可选：打印输出或报错验证

​	MLIR中定义Pass的基础模版文件为third_party\llvm-project\mlir\include\mlir\Pass\PassBase.td，下面是部分代码

```tablegen
//===-- PassBase.td - Base pass definition file ------------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains definitions for defining pass registration and other
// mechanisms.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_PASS_PASSBASE
#define MLIR_PASS_PASSBASE

//===----------------------------------------------------------------------===//
// Options
//===----------------------------------------------------------------------===//

// 这是一段 TableGen 类定义，用于在 .td 文件中描述 Pass 支持的命令行参数。
// 例如Option<"enableSoftmax", "enable-softmax", "bool", "true", "启用 softmax">;会被 MLIR 的 mlir-tblgen 工具转换为 C++ Pass 类中的如下成员
// ::mlir::Pass::Option<bool> enableSoftmax{
//	 *this, "enable-softmax",
//	 llvm::cl::desc("启用 softmax"),
//	 llvm::cl::init(true)
// };
class Option<string varName, string arg, string valueType, string default,
             string desc, string additionalFlags = ""> {
  // The name for the C++ option variable.
  string cppName = varName;		// C++ 中变量名

  // The command line argument to use for this option.
  string argument = arg;		// 命令行参数名（用户传入）

  // The C++ type of the option.
  string type = valueType;		// 	参数类型（C++ 类型）

  // The default value of the option. "" corresponds to no default.
  string defaultValue = default;

  // A description for this option.
  string description = desc;	// 命令行参数描述

  // A set of additional flags to pass along to the option constructor.
  string additionalOptFlags = additionalFlags;		// 	附加属性
}

class ListOption<string varName, string arg, string valueType,		// ListOption 表示参数是一个列表 继承自 Option，但默认 default=""
                 string desc, string additionalFlags = "">
  : Option<varName, arg, valueType, /*default=*/"", desc, additionalFlags> {}

//===----------------------------------------------------------------------===//
// Statistics
//===----------------------------------------------------------------------===//
// 用于定义统计指标，比如：操作数融合次数、成功优化次数等。
class Statistic<string varName, string statName, string desc> {
  // The C++ variable name for the statistic.
  string cppName = varName;

  // The displayed name of the statistic, similar to the argument of an option.
  string name = statName;

  // The description of the statistic.
  string description = desc;
}

//===----------------------------------------------------------------------===//
// Pass
//===----------------------------------------------------------------------===//

class PassBase<string passArg, string base> {		// Pass 的基础描述类，其他具体的 OperationPass 或 InterfacePass 会从此继承。
  // The command line argument of the pass.
  string argument = passArg;		// passArg 命令行中用于开启此 Pass 的参数

  // The C++ base class for the pass.		// Pass 所继承的 C++ 基类
  string baseClass = base;

  // A short 1-line summary of the pass.
  string summary = "";

  // A human readable description of the pass.
  string description = "";

  // A C++ constructor call to create an instance of this pass.
  // If empty, the default constructor declarations and definitions
  // 'createPassName()' and 'createPassName(const PassNameOptions &options)'
  // will be generated and the former will be used for the pass instantiation.
  // 构造器代码片段。如果不写，会自动生成形如createMyPass()	createMyPass(const MyPassOptions&)	的构造函数
  code constructor = "";

  // A list of dialects this pass may produce entities in.
  list<string> dependentDialects = [];		// Pass 依赖的 Dialect

  // A set of options provided by this pass.
  list<Option> options = [];		// Pass 支持的命令行参数, 填入上面定义的 Option 实例

  // A set of statistics provided by this pass.
  list<Statistic> statistics = [];		// Pass 提供的统计指标。
}

// This class represents an mlir::OperationPass.
// Pass 类（OperationPass 封装）
// 例如Tablegen中Pass<"my-opt", "func::FuncOp">， 相当于C++中	class MyOptPass : public mlir::OperationPass<mlir::func::FuncOp> { ... };
class Pass<string passArg, string operation = "">
  : PassBase<passArg, "::mlir::OperationPass<" # operation # ">">;

// This class represents an mlir::InterfacePass.
// 表示一个实现了某个 Pass Interface 的 Pass。
class InterfacePass<string passArg, string interface>
  : PassBase<passArg, "::mlir::InterfacePass<" # interface # ">">;

#endif // MLIR_PASS_PASSBASE

```

​	定义两个Pass，文件为Passes.td，路径为8-define_pass\include\Dialect\NorthStar\Transforms\Passes.td

```tablegen
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
//

#ifndef DIALECT_NORTH_STAR_TRANSFORMS_PASSES_TD
#define DIALECT_NORTH_STAR_TRANSFORMS_PASSES_TD
include "mlir/Pass/PassBase.td"

// 定义一个名为 MarkDistributeParallelParametersPass 的 Operation Pass，适用于 mlir::ModuleOp。
def MarkDistributeParallelParametersPass : Pass<"mark-distribute-parallel-parameters","::mlir::ModuleOp"> {
  let summary = "标记全局并行参数";
  let description = [{
    "标记全局并行参数。";
  }];
  
  // 此 Pass 需要用到的 Dialect，会自动向 MLIRContext 注册。NorthStar 是自定义方言，tensor 是内建 dialect。
  let dependentDialects = [
    "::mlir::north_star::NorthStarDialect",
    "::mlir::tensor::TensorDialect"
  ];
  
  // 定义两个参数选项,可通过命令行传入	注册了这个 Pass 后，可以像这样在命令行运行mlir-opt --my-pass --DP=4 --TP=2 input.mlir
  let options = [
    Option<"DPNums", "DP", "std::int64_t", /*default=*/"1", "DPNums des">,
    Option<"TPNums", "TP", "std::int64_t", /*default=*/"1", "TPNums des">
  ];
  
  // 定义一个运行时统计项
  let statistics = [
    Statistic<"EPNums", "ep-nums", "Number of EP">
  ];
}

def ApplyDistributeTransformPass : Pass<"apply-distribute-transform","::mlir::func::FuncOp"> {
  let summary = "根据标记的并行参数进行变换";
  let description = [{
    "根据标记的并行参数进行变换。"
  }];
  let dependentDialects = [
    "::mlir::north_star::NorthStarDialect",
    "::mlir::tensor::TensorDialect"
  ];
  let constructor = "mlir::north_star::createApplyDistributeTransformPass()";
}


#endif  // DIALECT_NORTH_STAR_TRANSFORMS_PASSES_TD
```

​	`MarkDistributeParallelParametersPass` 的C++ 实现部分，路径为8-define_pass\src\Dialect\NorthStar\Transforms\MarkDistributeParallelParameters.cpp

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
//
#include <memory>

#include "Dialect/NorthStar/IR/NorthStarAttrs.h"
#include "Dialect/NorthStar/IR/NorthStarDialect.h"
#include "Dialect/NorthStar/Transforms/Passes.h"
#include "Utils/Key.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
namespace mlir::north_star {
#define GEN_PASS_DEF_MARKDISTRIBUTEPARALLELPARAMETERSPASS
#include "Dialect/NorthStar/Transforms/Passes.h.inc"

}  // namespace mlir::north_star
using namespace ::mlir;
using namespace ::mlir::north_star;

// 继承自 TableGen 生成的基类模板 MarkDistributeParallelParametersPassBase,在文件build\8-define_pass\include\Dialect\NorthStar\Transforms\Passes.h.inc中
struct MarkDistributeParallelParametersPass
    : ::mlir::north_star::impl::MarkDistributeParallelParametersPassBase<
          MarkDistributeParallelParametersPass> {
  using MarkDistributeParallelParametersPassBase<
      MarkDistributeParallelParametersPass>::
      MarkDistributeParallelParametersPassBase;
  void runOnOperation() override;	// 重写 runOnOperation()，这是 Pass 的执行入口。
};

void MarkDistributeParallelParametersPass::runOnOperation() {
  llvm::outs() << "run in: " << getPassName() << "\n";	// 调用当前 Pass 基类的成员函数，返回 StringRef，是当前 Pass 名称字符串
  auto module = getOperation();		// PassBase 提供的成员函数，返回当前被处理的操作指针，类型为 Operation *。
  llvm::outs() << "root op: " << module->getName() << "\n";		// module->	解引用指针，访问指针指向的对象成员。	getName()	Operation 的成员函数，返回操作名称
  llvm::outs() << "DPNums: " << DPNums << "\n";		// 输出选项成员变量 DPNums
  llvm::outs() << "TPNums: " << TPNums << "\n";		// 输出选项成员变量 TPNums
  llvm::outs() << "EPNums: " << EPNums << "\n";		// 输出统计成员变量 EPNums

  if (TPNums != 1) llvm::errs() << "TPNums not supported currently!\n";
  if (DPNums != 1) {
    // 创建 DataParallelismAttr	DataParallelismAttr::get(&getContext(), DPNums);调用静态成员函数生成属性对象。&getContext()	取当前 Pass 所属 MLIRContext 的地址。	DPNums	传入数据并行度参数值。
    auto dp_attr = DataParallelismAttr::get(&getContext(), DPNums);
    // 遍历 Module 中所有函数并设置属性	将数据并行度属性附加给所有函数。
    module->walk([&dp_attr](func::FuncOp op) {
      op->setAttr(KDPAttrName, dp_attr);		// 给函数操作 op 设置属性。
    });
  }
  llvm::outs() << "run out: " << getPassName() << "\n\n";
}

```

​	ApplyDistributeTransformPass的C++ 实现部分，路径为8-define_pass\src\Dialect\NorthStar\Transforms\ApplyDistributeTransform.cpp

```cpp
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
//

#include "Dialect/NorthStar/IR/NorthStarDialect.h"
#include "Dialect/NorthStar/Transforms/Passes.h"
#include "Interfaces/DistributeParallelismInterfaces.h"
#include "Utils/Key.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
namespace mlir::north_star {
#define GEN_PASS_DEF_APPLYDISTRIBUTETRANSFORMPASS
#include "Dialect/NorthStar/Transforms/Passes.h.inc"

}  // namespace mlir::north_star
using namespace ::mlir;
using namespace ::mlir::north_star;

struct ApplyDistributeTransformPass
    : ::mlir::north_star::impl::ApplyDistributeTransformPassBase<
          ApplyDistributeTransformPass> {
  using ApplyDistributeTransformPassBase<
      ApplyDistributeTransformPass>::ApplyDistributeTransformPassBase;
  void runOnOperation() override;
};

void ApplyDistributeTransformPass::runOnOperation() {
  llvm::outs() << "run in: " << getPassName() << "\n";
  auto func = getOperation();
  llvm::outs() << "root op: " << func->getName() << "\n";
  auto dp_attr = llvm::dyn_cast_or_null<mlir::DistributeParallelAttr>(
      func->getAttr(KDPAttrName));	// 将通用 Attribute 转换为具体类型 DistributeParallelAttr，如果失败返回 nullptr。
  if (!dp_attr) llvm_unreachable("error!");		// 如果没有 dp 属性，就中断运行并输出 "error!"。
  func->walk([&](mlir::Operation* op) {		//  遍历当前函数中的每个 Operation
    // 判断DistributeParallelOp是否实现了 DistributeParallelismInterface 的 Op。表示当前操作是否“支持数据并行调度”
    if (auto dis_op = llvm::dyn_cast_or_null<mlir::DistributeParallelOp>(op)) {
      // 如果当前操作 dis_op 能够在 dp_attr 数据并行属性下，成功应用并行转换,那么就打印重写成功的操作名称
      if (dis_op.applyDistributeParallelism(dp_attr).succeeded()) {
        llvm::outs() << "Apply DataParallelism to " << op->getName() << "\n";
        op->erase();	// 删除原始操作
      };
    }
  });
  llvm::outs() << "run out: " << getPassName() << "\n\n";
}

std::unique_ptr<::mlir::Pass>
mlir::north_star::createApplyDistributeTransformPass() {
  return std::make_unique<ApplyDistributeTransformPass>();
}
```

​	下面是main文件CH-8部分	

```cpp
void CH8() {  // 初始化方言注册器
  mlir::DialectRegistry registry;
  // 初始化上下文环境
  mlir::MLIRContext context(registry);
  // 加载/注册方言
  context.getOrLoadDialect<mlir::north_star::NorthStarDialect>();
  context.getOrLoadDialect<mlir::func::FuncDialect>();
  mlir::OpBuilder builder(&context);		// OpBuilder：构建 MLIR IR 的类
  auto loc = builder.getUnknownLoc();		// getUnknownLoc()：创建一个无源代码位置信息的 Location，可以传给 IR 创建函数。
  auto module = getModule(builder);			// getModule（）自定义的方法，里面有两个串行的softmaxOp
  mlir::PassManager pm(&context);		// 创建 PassManager	PassManager 是 MLIR 的 Pass 调度器，会按照添加顺序运行所有 Pass。
  mlir::north_star::MarkDistributeParallelParametersPassOptions
      mark_distribute_parallel_option{.DPNums = 3, .TPNums = 1};		// 构造分布式标记 Pass 的参数对象
  pm.addPass(mlir::north_star::createMarkDistributeParallelParametersPass(
      mark_distribute_parallel_option));		//  添加 MarkDistributeParallelParametersPass
  pm.addNestedPass<mlir::func::FuncOp>(
      mlir::north_star::createApplyDistributeTransformPass());		// 添加 ApplyDistributeTransformPass
  module->dump();		// module->dump();
  if (pm.run(module).failed()) {		// 执行 PassManager	pm.run() 开始运行所有注册的 pass	如果任何一个 pass signalPassFailure()，这里就会报错
    llvm::outs() << "run pass error!\n";
  };
  llvm::outs() << "after pass:\n";
  module->dump();		// 打印变换后的 IR
}
```



# 第八章.Rewrite Pattern

​	Rewrite Pattern 是 MLIR 中的一种机制，用于匹配某些 Operation（操作）模式，并将其替换成等价或优化后的新模式。

​	重写模式提供了以下用途

| 用途                         | 举例说明                                     |
| ---------------------------- | -------------------------------------------- |
| 算子融合                   | 把连续的 `add -> mul` 合并为一个 `fma` 操作  |
| 优化图转换                 | 将 inefficient 的实现替换为 efficient 的实现 |
| Canonicalization（规范化） | 比如 `x + 0 -> x`，`x * 1 -> x`              |
| Dialect 转换               | 将 `TF.add` 转为 `linalg.add`                |

​	在 C++ 中，重写模式是通过继承以下基类来定义的：

```cpp
struct RewritePattern : public mlir::RewritePattern {
  RewritePattern(StringRef rootOpName, PatternBenefit benefit, MLIRContext *context);
  
  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rewriter) const override;
};
```

​	关键字段解释

| 字段 / 方法       | 含义                                                         |
| ----------------- | ------------------------------------------------------------ |
| `rootOpName`      | 指定要匹配的 op 类型，比如 `"mydialect.add"`                 |
| `benefit`         | 一个整数值，表示该 pattern 的应用优先级（值越大越优先）      |
| `matchAndRewrite` | 重写逻辑的核心函数，成功时返回 success()，失败返回 failure() |
| `PatternRewriter` | 提供修改 IR 的 API，例如 `replaceOp()`、`create()`、`eraseOp()` 等 |

下面是DeviceRegionFusion.cpp文件，路径为9-rewrite_pattern\src\Dialect\NorthStar\Transforms\DeviceRegionFusion.cpp

```c++
//    Copyright 2025 时光丶人爱

//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.
//
#include <cstdint>
#include <memory>

#include "Dialect/NorthStar/IR/NorthStarAttrs.h"
#include "Dialect/NorthStar/IR/NorthStarDialect.h"
#include "Dialect/NorthStar/IR/NorthStarOps.h"
#include "Dialect/NorthStar/IR/NorthStarTypes.h"
#include "Dialect/NorthStar/Transforms/Passes.h"
#include "Interfaces/DistributeParallelismInterfaces.h"
#include "Utils/Key.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/LogicalResult.h"
#include "llvm/Support/ScopedPrinter.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
namespace mlir::north_star {
#define GEN_PASS_DEF_DEVICEREGIONFUSIONPASS
#include "Dialect/NorthStar/Transforms/Passes.h.inc"

}  // namespace mlir::north_star
using namespace ::mlir;
using namespace ::mlir::north_star;

namespace {

namespace {

// 根据多个操作 ops 的名称和输入 shape 生成融合函数名
// llvm::SmallString<4>	LLVM 提供的高效小字符串容器，4 是初始容量，自动扩展
// getFusionName	函数名，生成用于 fusion 的 operation name
// mlir::ArrayRef<::mlir::Operation*> ops	参数类型是一个轻量不可变数组视图，元素是 Operation*，表示多个 MLIR 操作的指针
static inline llvm::SmallString<4> getFusionName(
    mlir::ArrayRef<::mlir::Operation*> ops) {
  llvm::SmallString<4> name;		//定义一个llvm::SmallString ，名字为name
  for (auto op : ops) {		// 遍历所有操作
    name.append(op->getName().stripDialect()); // name.append(...)	往 name 字符串中添加一段字符串	op->getName() 获取操作名	.stripDialect() 去除操作名中的 dialect 前缀如 "north_star.buffer_cast" → "buffer_cast"
    name.append("_");	// 添加下划线分隔符
    for (auto type : op->getOperandTypes()) {		//	getOperandTypes()	获取所有操作输入值的类型
      if (auto shaped = llvm::dyn_cast_or_null<ShapedType>(type)) {		//判断是否是ShapedType
        for (auto index : llvm::index_range(0, shaped.getRank())) {		//shaped.getRank() 获取张量维度个数		llvm::index_range(a, b)	相当于 Python 的 range(a, b)，这里是从 0 到 rank-1
          if (shaped.isDynamicDim(index)) {		//  判断维度是否动态
            name.append("d_");
          } else {
            name.append(llvm::to_string(shaped.getDimSize(index)));		//静态维度直接转为字符串拼接进 name
            name.append("_");
          }
        }
      }
    }
  }
  return name;		// 最终返回构造好的 name
}

// 这个函数的作用是:   从传入的 MLIR 操作列表 ops 中，获取最后一个操作的第一个返回值类型，尝试将它转换为自定义类型 NSTensorType，然后提取该类型的 device_id。
// 返回值为int，表示device_id		getDeviceid是函数名		mlir::ArrayRef<::mlir::Operation*> ops	参数是一个不可变引用数组，内部元素是 MLIR 操作指针 Operation*。表示要分析的一批 IR 操作
static inline int getDeviceid(mlir::ArrayRef<::mlir::Operation*> ops) {
  // ops.back() 获取 ops 中的最后一个操作		->getResultTypes() 获取该操作的返回类型列表		.front() 获取返回类型列表中的第一个类型
  // 定义一个tensor，将最后一个操作的第一个类型转换为NSTensorType然后赋值给tensor		llvm::cast_or_null<T> LLVM 中的安全转换工具。尝试将指针转换为 T 类型，如果为空或类型不对，则返回空指针
  if (auto tensor = llvm::cast_or_null<north_star::NSTensorType>(
          ops.back()->getResultTypes().front())) {
    return tensor.getDeviceId();		//如果类型转换成功，那么调用 NSTensorType 上定义的成员函数 getDeviceId()，返回这个 tensor 绑定的设备编号
  }
  llvm_unreachable("");		// LLVM 提供的宏，表示这个代码逻辑“不可能执行到”这里；如果真的执行到这里，就会直接 abort()
  return -1;
}

    
// llvm::MapVector<Value, std::pair<Operation*, int>>	返回值是一个有序映射容器：Key = Value（SSA 值，代表外部输入）	Value = pair<Operation*, int>：指明该 Value 来自哪个 op、是它的第几个 operand
static inline llvm::MapVector<Value, std::pair<Operation*, int>>
getFusionInputs(mlir::ArrayRef<::mlir::Operation*> ops) {
  // SetVector是 MLIR 提供的容器，既像 set（无重复），又像 vector（保持顺序）	op_set 用来存储当前的融合区域中所有操作
  mlir::SetVector<Operation*> op_set(ops.begin(), ops.end());
  // 初始化结果容器	res	记录所有外部输入
  llvm::MapVector<Value, std::pair<Operation*, int>> res;

  // 双层遍历操作和其输入值
  // for (auto op : ops)	遍历所有操作		llvm::enumerate(container)	LLVM 提供的工具函数，用于对容器进行索引 + 元素的并行遍历。
  for (auto op : ops) {
    for (auto [index, operand] : llvm::enumerate(op->getOperands())) {
      if (isa<BlockArgument>(operand))		// 判断 SSA 值是不是 block 的参数，比如函数参数 / block 入口
        res[operand] = std::make_pair(nullptr, 0);	//说明这个输入不来自 op，而是来自“函数/块的输入”，没有来源操作，因此 op = nullptr，index = 0
      if (op_set.contains(operand.getDefiningOp())) continue;	//判断是否是内部定义的 SSA 值	如果是，则continue跳过
      res[operand] = std::make_pair(op, index);		//否则记录外部输入到res
    }
  }
  return res;		// 返回结果
}

static inline llvm::MapVector<Value, std::pair<Operation*, int>>
getFusionOutputs(mlir::ArrayRef<::mlir::Operation*> ops) {
  mlir::SetVector<Operation*> op_set(ops.begin(), ops.end());
  llvm::MapVector<Value, std::pair<Operation*, int>> outs;
  for (auto op : ops) {
    for (auto [index, res] : llvm::enumerate(op->getResults())) {
      for (auto user : res.getUsers()) {
        if (op_set.contains(user)) continue;
        outs[res] = std::make_pair(op, index);
        break;
      }
    }
  }
  return outs;
}
}  // namespace
    
// FusionOps 函数名，表明它的作用是“融合操作”		::mlir::RewriterBase& rewriter  MLIR 中所有 IR 修改器的基类，支持操作替换、插入等。	::mlir::Location loc	表示代码位置信息（比如文件、行号等），用于诊断与调试。
void FusionOps(::mlir::RewriterBase& rewriter,
               mlir::ArrayRef<::mlir::Operation*> ops, ::mlir::Location loc) {
  if (ops.size() == 0) return;		// 如果操作列表为空，直接返回
  auto context = rewriter.getContext();		// 获取上下文
  auto insert_point = rewriter.saveInsertionPoint();	// 保存当前插入点（rewriter 当前插入 IR 的位置），方便稍后恢复。
  auto name = getFusionName(ops);	// 调用自定义的 getFusionName 函数，为这批 ops 生成一个融合函数名
  auto device_id = getDeviceid(ops);	// 提取这些操作的 device_id
  name.append(llvm::to_string(device_id));	// 转换为字符串追加到 name 后面
  auto inputs_map = getFusionInputs(ops);	// 提取 ops 所需的所有输入值，以及来源信息（哪个 op、哪个 operand index）。
  auto outputs_map = getFusionOutputs(ops);	// 提取所有这些 ops 的输出，和它们的写出位置（用于替换 call 后的结果）。
  llvm::SmallVector<Value> inputs_val;	// 融合函数的所有输入值
  llvm::SmallVector<Value> output_val;	// 融合函数的所有输出值
  llvm::SmallVector<Type> outputs_type;	// 所有输入值的类型
  llvm::SmallVector<Type> inputs_type;	// 所有输出值的类型
  for (auto [key, val] : inputs_map) {	// 遍历输入inputs_map
    inputs_val.push_back(key);	// 将输入的键key存入inputs_val
    inputs_type.push_back(key.getType());	// 将输入的类型存入inputs_type
  }
  for (auto [key, val] : outputs_map) {		// 遍历输出outputs_map
    outputs_type.push_back(key.getType());	// 对输出值取出类型放入 outputs_type
  }
  
  // 在 MLIR 中，rewriter 是操作 IR（插入/替换/删除操作）的工具类，而 insertion point 是它插入新操作（比如 create<func::FuncOp>）的位置。MLIR 的插入点就是指定我们往哪段 IR 代码中添加新 Operation。
  // (*ops.begin()) 取的是 ops 中第一个 op		.getParentOp()：得到这个 Operation 所在的上层Operation
  rewriter.setInsertionPoint((*ops.begin())->getParentOp());
  // 创建一个函数定义 func.func		名字为 name	类型为 FunctionType(inputs -> outputs)		插入点就是上一步设置的位置。
  auto kernel = rewriter.create<func::FuncOp>(
      loc, name, FunctionType::get(context, inputs_type, outputs_type));
  kernel->setAttr(KDeviceFunc, UnitAttr::get(context));		// ->setAttr(...) 是 MLIR 的通用 API，用于给任何 Operation 设置属性
  auto block = kernel.addEntryBlock();	// entry block 是一个函数的第一个 Block，相当于函数的“函数体”开头。这句的作用是在函数的 Region 中创建一个 Block，这个 block 被插入到函数的 region 中作为第一个 block
  std::map<Operation*, Operation*> op_map;	// 定义了一个映射 op_map：记录原始操作 → 克隆操作的映射关系。
  for (auto op : ops) {		// 遍历想融合的所有操作
    auto clone_op = op->clone();	// 深拷贝一份 op，但 operand 是指向原始 IR 的。
    block->push_back(clone_op);		// 把克隆的操作放入 block（即 func entry block）。
    op_map[op] = clone_op;		// 记录映射：原始 → 克隆。
    for (auto [index, operand] : llvm::enumerate(op->getOperands())) {		// 枚举当前操作的每一个输入值（operand），并带上 index。
      if (isa<BlockArgument>(operand)) continue;	// 如果这个输入值是 block argument 就跳过
      if (op_map.contains(operand.getDefiningOp())) {	// op_map.contains(...) 判断 map 中是否存在对应的键		operand.getDefiningOp()是 mlir::Value 的成员函数。它返回定义这个值的操作指针，类型是 Operation*。如果是块参数（BlockArgument），则返回 nullptr
        // op_map[op]->setOperand(index, value)	表示设置某个输入参数（operand） 这句作用是给克隆操作的第 index 个输入设置新的值（来自对应的克隆操作输出）
        op_map[op]->setOperand(
            index,
            // getResult 返回该操作的第n个输出	这里的n是由llvm::cast_or_null<OpResult>(operand).getResultNumber()得到
            op_map[operand.getDefiningOp()]->getResult(
                llvm::cast_or_null<OpResult>(operand).getResultNumber()));	// 将operand转换成 OpResult，然后获取它是所属操作的第几个输出
      }
    }
  }
  for (auto [key, val] : outputs_map) {		// outputs_map 中的每一项是 key: Value, val: (Operation *, int)
    output_val.push_back(op_map[val.first]->getResult(val.second));		//val.first 是某个操作（在 kernel block 中）	val.second 是该操作的第几个结果（如 getResult(0)）	op_map[val.first] → 拿到对应 clone 后的操作	.getResult(val.second) → 拿到该 clone 操作的某个结果	push_back(...) → 加入输出值列表 output_val
  }
    
  // 将 block 参数作为 operand 设置给 kernel 中的 op
  for (auto [index, key] : llvm::enumerate(inputs_map)) {	// inputs_map 是一个列表，每个元素是 (op, operand_index)		llvm::enumerate(...)：遍历时自动加上 index（当前是第几个）
    op_map[key.second.first]->setOperand(key.second.second,		
                                         block->getArgument(index));	// block->getArgument(index)：拿到该 block 的第 index 个参数（即 kernel 的输入）	op_map[key.second.first]：这个 op 是 clone 后的版本		.setOperand(...)：设置该 op 的第 key.second.second 个 operand
  }

  // 在 block 尾部插入 return
  rewriter.setInsertionPointToEnd(block);
  rewriter.create<func::ReturnOp>(loc, output_val);
  // 恢复插入点 & 创建 call	把 IR 构造的插入点恢复到调用点	创建一个 func::CallOp，调用你刚刚创建的 kernel 函数
  rewriter.setInsertionPoint(insert_point.getBlock(), insert_point.getPoint());
  auto call = rewriter.create<func::CallOp>(loc, kernel, inputs_val);
  // 替换原 op 的输出
  for (auto [index, key] : llvm::enumerate(outputs_map)) {
    rewriter.replaceAllUsesWith(key.first, call->getResult(index));
  }
  return;
}

    
// 这是一个继承自 OpRewritePattern<BufferCastOp> 的模式重写类，表示这个 pattern 只作用于 BufferCastOp。
struct BufferCastOpDeviceRegionFusion
    : public OpRewritePattern<::mlir::north_star::BufferCastOp> {
  using OpRewritePattern::OpRewritePattern;		// 表示我们要使用父类 OpRewritePattern 的构造函数。
  // 这是 MLIR 中重写规则必须实现的接口之一，用于模式匹配 + 替换。	::mlir::north_star::BufferCastOp op：当前被匹配到的 BufferCastOp 实例。
  // PatternRewriter& rewriter：MLIR 提供的重写工具，可以插入、替换、删除操作。
  virtual LogicalResult matchAndRewrite(::mlir::north_star::BufferCastOp op,
                                        PatternRewriter& rewriter) const {
    llvm::outs() << "match:" << getDebugName() << "\n";	// getDebugName() 是 MLIR 提供的一个 helper 函数，用于获取当前 Pattern 的调试名字。
    auto loc = op->getLoc();	// 获取当前操作的源代码位置信息
    // SetVector 是一个结合了 std::set 和 std::vector 特性的容器。	它能保证元素是唯一的（就像 std::set）。	它保持元素的插入顺序（就像 std::vector）。		op_list是一个二维列表，其中的每个元素都是一个 SetVector<Operation*>
    llvm::SmallVector<llvm::SetVector<Operation*>> op_list;
    for (auto res : op->getResults()) {
      rewriter.setInsertionPointAfterValue(res);	// 设置插入点。之后的操作（rewriter.create）会在这个结果值之后插入。
      llvm::SetVector<Operation*> ops;
      for (auto use : res.getUsers()) {		// res.getUsers()：获取所有使用这个结果的操作（Use）。
        addops(ops, use);		// 遍历每一个 use 调用 addops，这个函数是自定义的，通常递归添加有关联的操作
      }
      if (ops.size() != 0) op_list.push_back(ops);	// 如果有找到使用者，就把这个 ops 集合加入到 op_list。
    }
    if (op_list.size() == 0) return llvm::failure();	// 如果没有找到任何可融合的使用者，说明不匹配，终止 Pattern 应用。
    for (auto ops : op_list) {
      FusionOps(rewriter, ops.takeVector(), loc);		// 遍历收集到的操作集合，调用自定义的 FusionOps() 函数去融合它们。ops.takeVector()：把 SetVector 转成普通的 std::vector，并清空原 SetVector
    }
    return llvm::success();
  }

  void addops(llvm::SetVector<Operation*>& ops, Operation* op) const {
    if (!isa<DistributeParallelOp>(op)) return;		// 检查 op 是否是 DistributeParallelOp 类型的操作
    ops.insert(op);		// insert 是 SetVector 提供的一个方法，用于向容器中插入一个新的元素（op）。
    for (auto user : op->getUsers()) {		//遍历所有 op 的用户操作。对于每一个用户操作 user，执行循环体内的代码。
      addops(ops, user);	// 递归调用
    }
  }
};

struct BufferCastOpFold
    : public OpRewritePattern<::mlir::north_star::BufferCastOp> {
  using OpRewritePattern::OpRewritePattern;

  virtual LogicalResult match(::mlir::north_star::BufferCastOp op) const {
    llvm::outs() << "match:" << getDebugName() << "\n";
    Operation* above_cast = nullptr;	// 用于存储第一个操作 operand 的定义操作。如果多个操作的 operand 来自相同的定义操作，那么我们可以折叠它们。
    for (auto [index, operand] : llvm::enumerate(op->getOperands())) {		// 这段代码遍历 BufferCastOp 的所有操作数（operands）
      if (isa<BlockArgument>(operand)) return llvm::failure();	// 检查 operand 是否是一个 BlockArgument	如果是，说明该操作数是一个区块参数，它不能作为折叠条件的一部分。此时返回 llvm::failure()，表示当前操作不能进行折叠。
      if (!above_cast) {
        above_cast = operand.getDefiningOp();	// 如果 above_cast 为空，则将当前操作数的定义操作 operand.getDefiningOp() 赋值给 above_cast。
      } else {
        if (operand.getDefiningOp() != above_cast) return llvm::failure();	// 判断当前操作数的定义操作是否与之前的 above_cast 相同。如果不相同，说明不能进行折叠，返回 llvm::failure()。
      }
      if (operand.getType() != above_cast->getResult(index).getType())
        return llvm::failure();	// 检查当前操作数的类型是否与 above_cast 操作的结果类型一致。如果不一致，说明不能进行折叠，返回 llvm::failure()。
      if (!above_cast->getResult(index).hasOneUse()) return llvm::failure();	// 检查 above_cast 的结果是否仅被一个操作使用。如果结果被多个操作使用，则不应折叠，返回 llvm::failure()
    }
    return llvm::success();		// 以上所有检查都通过，说明当前 BufferCastOp 可以进行折叠，返回 llvm::success()，表示匹配成功。
  }

  // rewrite: 这个方法是用来对匹配到的操作进行实际重写的。
  virtual void rewrite(::mlir::north_star::BufferCastOp op,
                       PatternRewriter& rewriter) const {
    Operation* above_cast = op->getOperand(0).getDefiningOp();	// above_cast: 获取当前 op 操作的第一个操作数的定义操作（即它的源操作）。这是要被折叠的操作。
    for (auto [index, res] : llvm::enumerate(op->getResults())) {	// 遍历 op 的所有结果，将 op 的每个结果替换为 above_cast 对应操作数的值。
      rewriter.replaceAllUsesWith(res, above_cast->getOperand(index)); // replaceAllUsesWith(res, above_cast->getOperand(index)): 用 above_cast 的操作数替换 op 结果 res 的所有使用。
    }
    rewriter.eraseOp(op);	//删除当前操作 op。
    rewriter.eraseOp(above_cast);	// rewriter.eraseOp(above_cast): 删除 above_cast 操作，因为它的结果已经被替换，所以不再需要。
    llvm::outs() << "match:" << getDebugName() << "\n";
  }
};
}  // namespace

// populateDeviceRegionFusionPatterns，表示 “填充设备区域融合模式”。
void ::mlir::north_star::populateDeviceRegionFusionPatterns(
    RewritePatternSet& patterns) {
  auto context = patterns.getContext();		// 获取 patterns 的上下文对象（MLIRContext*），用于构造 Pattern。
  patterns.addWithLabel<BufferCastOpDeviceRegionFusion>(	// 向 patterns 中添加一个 label 为 "BufferCastOpDeviceRegionFusion" 的模式。	使用的是 addWithLabel<PatternClass> 模板函数：	BufferCastOpDeviceRegionFusion 是自定义的重写模式类，继承自 OpRewritePattern<BufferCastOp>。StringRef(...)：模式名称，调试或分析用；context：模式构造时所需的 MLIRContext*；100：该模式的优先级（benefit），值越大越优先被匹配。
      StringRef("BufferCastOpDeviceRegionFusion"), context, 100);
};

// 注册函数，把某个重写规则加入 canonicalization 模式集合中。	populateBufferCastOpCanonicalizationPatterns：表示用于将 BufferCastOp 折叠（fold）成更简单结构。		canonicalization（规范化）将某个操作变换成更“标准”、更简洁、更容易优化的形式。
void ::mlir::north_star::populateBufferCastOpCanonicalizationPatterns(
    RewritePatternSet& patterns) {
  auto context = patterns.getContext();
  patterns.addWithLabel<BufferCastOpFold>(StringRef("BufferCastOpFold"),
                                          context, 2);
}

struct DeviceRegionFusionPass
    : ::mlir::north_star::impl::DeviceRegionFusionPassBase<
          DeviceRegionFusionPass> {
  using DeviceRegionFusionPassBase<
      DeviceRegionFusionPass>::DeviceRegionFusionPassBase;
  void runOnOperation() override;
};

void DeviceRegionFusionPass::runOnOperation() {
  llvm::outs() << "run in: " << getPassName() << "\n";
  auto module = getOperation();		// getOperation() 是获取当前 pass 处理的 IR 根节点
  llvm::outs() << "root op: " << module->getName() << "\n";

  RewritePatternSet buffer_cast_patterns(&getContext());	// 创建一个用于存储模式的容器。
  ::mlir::north_star::populateBufferCastOpCanonicalizationPatterns(
      buffer_cast_patterns);
  GreedyRewriteConfig buffer_cast_config;		// 创建贪婪重写的配置。
  buffer_cast_config.maxIterations = 10;		// maxIterations = 10：最多运行 10 轮（避免死循环）。
  buffer_cast_config.useTopDownTraversal = true;	// topDown = true：从上往下匹配 IR 中的操作。
  
  // applyPatternsAndFoldGreedily 是 MLIR（Multi-Level IR）中的重写 API 之一,，它的作用可以简单总结为：反复应用 RewritePattern，直到无法再优化为止，同时尝试进行 constant folding 和 canonicalization。
  // applyPatternsAndFoldGreedily() 会在整个 IR 上应用注册的重写规则：能匹配就重写；能折叠（如常量传播）就折叠；会尝试多轮（最多10轮）。如果出现错误（failed），则调用 signalPassFailure()，告诉 pass manager：这个 pass 执行失败。
  if (failed(applyPatternsAndFoldGreedily(
          getOperation(),
          FrozenRewritePatternSet(std::move(buffer_cast_patterns)),
          buffer_cast_config)))
    signalPassFailure();

  // 创建一个新规则集合；将你自定义的 DeviceRegionFusion（操作融合规则）注册进去，比如 BufferCastOpDeviceRegionFusion。
  RewritePatternSet patterns(&getContext());
  ::mlir::north_star::populateDeviceRegionFusionPatterns(patterns);
  
  // 又进行一次 贪婪模式匹配	如果匹配到了，可以重写或融合。	changed 会告诉你是否真的有 IR 被修改。
  GreedyRewriteConfig config;
  bool changed;
  if (failed(applyPatternsAndFoldGreedily(
          getOperation(), FrozenRewritePatternSet(std::move(patterns)), config,
          &changed)))
    signalPassFailure();
  llvm::outs() << "region has changed: " << changed << "\n";
  llvm::outs() << "run out: " << getPassName() << "\n\n";
}

```

# 第九章.Pass管理器

​	Pass 管理器是 MLIR 中用于组织、调度、运行多个 Pass 的统一入口。就像一个流程调度器，它维护着 Pass 的运行队列，控制它们按顺序、按作用对象一层层地运行在 MLIR IR 上。

​	PassManager 的主要作用有

| 功能                                                 | 说明                                                         |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| 注册多个 Pass，按顺序组织运行                        | `PassManager` 可以依次添加多个 Pass，按顺序执行，每个 Pass 对 IR 做不同优化或转换处理。 |
| 根据 IR 层级结构（Module/Func/Region）进行调度       | 可通过 `nest<OpType>()` 针对不同层级的 Operation（如 ModuleOp、FuncOp）注册不同的 Pass。 |
| 支持嵌套 Pass（如 Module 内部的 Func 内的 Block）    | `PassManager` 支持嵌套 Pass，在 Module 层中嵌套函数层 Pass，甚至更深层的 Region/Block。 |
| 提供 API 手动添加 Pass                               | 使用 `addPass(...)`、`nest<T>()` 等 API，用户可以自由构建 Pass Pipeline。 |
| 支持调试、打印 IR（IR Dump）                         | 可启用 IR 打印功能，如 `enableIRPrinting()`，在每个 Pass 前后输出 IR 便于调试。 |
| 允许控制 Pass 是否循环运行直到收敛（pass iteration） | 通过 `applyPatternsAndFoldGreedily()` 等函数，Pass 可以重复运行直到 IR 不再变化，达到优化收敛。 |

​	MLIR 的 Pass 是按 IR 层级分层组织的，例如：

```
ModuleOp
└── FuncOp
    └── Block

```

​	于是可以建立如下嵌套 Pass 管理器结构：

```cpp
PassManager pm(context);                    // 顶层 ModuleOp
pm.addPass(createCanonicalizerPass());     // 对整个 Module 做一次 canonicalize

OpPassManager &funcPM = pm.nest<func::FuncOp>(); // 针对每个函数的 Pass
funcPM.addPass(createCSEPass());           // 每个函数做一次公共子表达式消除
funcPM.addPass(createMyCustomPass());      // 每个函数执行你的自定义逻辑

```

PassManager使用过程一般分为：

​	1.构造阶段

```cpp
mlir::PassManager pm(context);
```

​	2.添加 Pass（支持嵌套）

```cpp
pm.addPass(...);          // Module 级 Pass
pm.nest<func::FuncOp>().addPass(...);  // 函数级

```

​	3.应用到 IR

```cpp
LogicalResult result = pm.run(module);  // module 是一个 mlir::ModuleOp
```

​	 PassManager 例子

```cpp
void runMyPipeline(ModuleOp module, MLIRContext &context) {
  PassManager pm(&context);
  
  // Enable printing IR before/after each pass
  pm.enableIRPrinting();

  // 添加一个 Module 级 Pass
  pm.addPass(mlir::createCanonicalizerPass());

  // 嵌套到 FuncOp，每个函数内部也跑 CSE 和你的 Pass
  auto &funcPM = pm.nest<func::FuncOp>();
  funcPM.addPass(mlir::createCSEPass());
  funcPM.addPass(std::make_unique<MyPass>());

  // 运行 Pass 管理器
  if (failed(pm.run(module))) {
    llvm::errs() << "Pipeline failed\n";
  }
}

```

​	Pipeline 是 MLIR Pass 系统中的一个关键概念，它是构建编译器优化流程的 逻辑组织单位。它是是一组按照顺序组合在一起的 Pass 集合，可以作为一个整体执行，表示一条完整的编译优化流程。比如一个优化过程包括上面的3个Pass，canonicalize → cse → bufferize。这个顺序就是一个 Pipeline。

# 第十章.常量折叠和规范化

​		常量折叠：一种编译期优化技术，它会在编译时将运算中涉及到的常量值表达式进行求值，并将其替换为计算结果，以减少运行时的计算成本。它是一种静态求值技术，本质上是“提前做运算”。

​		例如	%1 = add %a, 0	可以规范化为	%1 = %a

| 特征                       | 说明                              |
| -------------------------- | --------------------------------- |
| 输入值必须是静态已知常量   | 比如 `2 + 3`, `[1, 2] + [3, 4]`   |
| 替换为一个更简单的 IR 表达 | 用结果 `5` 或 `[4, 6]` 替换原操作 |
| 不改变语义                 | 表达式含义相同，仅提前求值        |
| 本质是“值替换”             | 从操作变成值（`Op` → `Attr`）     |

​		MLIR 中通过 Op::fold() 方法来支持常量折叠，返回类型是 OpFoldResult（可能是一个 Attribute、也可能是 Value）。

​		例如

```cpp
OpFoldResult ConstOp::fold(FoldAdaptor adaptor) {
  return getValueAttr();  // 直接返回常量值
}
```

​		规范化：是一种基于等价变换的结构优化技术，其目标是将多个等价但形式不同的 IR 转换为统一、简洁、可优化性强的标准结构。它不做具体的“计算”，而是做语义保持下的结构重写。

| 特征                             | 说明                            |
| -------------------------------- | ------------------------------- |
| 保持语义不变                     | 输入输出一致，但形式不同        |
| 改变的是 IR 的“形态”             | 不改变结果，仅改变表达方式      |
| 目标是“统一形式”                 | 简化 pattern 匹配、更好调度优化 |
| 通常用于优化 pipeline 的早期阶段 | 提前清理低效结构                |

​	下面是NorthStarCanonicalize.cpp文件，路径为14-fold_and_canonicalization\src\Dialect\NorthStar\IR\**NorthStarCanonicalize.cpp

```cpp
//    Copyright 2025 时光丶人爱
//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at

//        http://www.apache.org/licenses/LICENSE-2.0

//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.

#include "Dialect/NorthStar/IR/NorthStarOps.h"
#include "Dialect/NorthStar/IR/NorthStarTypes.h"
#include "llvm/ADT/StringRef.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/OpDefinition.h"

#define __USE_hasCanonicalizeMethod__ false

namespace mlir::north_star {

#if __USE_hasCanonicalizeMethod__

LogicalResult BufferCastOp::canonicalize(BufferCastOp op,
                                         PatternRewriter &rewriter) {
  // patterns and rewrites go here.
  Operation *above_cast = nullptr;
  for (auto [index, operand] : llvm::enumerate(op->getOperands())) {		// 遍历 op 的所有操作数，使用结构化绑定得到索引和操作数。
    if (isa<BlockArgument>(operand)) return llvm::failure();		// 如果操作数是块参数，返回失败，不规范化。
    if (!above_cast) {		// 检查指针 above_cast 是否为空。为空时执行下面语句
      above_cast = operand.getDefiningOp();		// ：第一次时，保存定义当前操作数的操作。operand.getDefiningOp()：获取定义该操作数的操作，即得到上层操作。
    } else {
      if (operand.getDefiningOp() != above_cast) return llvm::failure();		// 判断当前 operand 的定义操作是否和 above_cast 不同。如果不同，返回失败。
    }
    if (operand.getType() != above_cast->getResult(index).getType())		// 判断操作数类型与对应结果类型是否一致，不一致失败。
      return llvm::failure();
    if (!above_cast->getResult(index).hasOneUse()) return llvm::failure();	// 判断上层操作第 index 个结果是否只有一个使用。如果不是只有一个使用，返回失败。
  }
  above_cast = op->getOperand(0).getDefiningOp();
  for (auto [index, res] : llvm::enumerate(op->getResults())) {		// 遍历当前操作的结果。
    rewriter.replaceAllUsesWith(res, above_cast->getOperand(index));	// 用 above_cast 的对应输入替换当前结果的所有用法。
  }
  rewriter.eraseOp(op);		// 删除当前操作。
  rewriter.eraseOp(above_cast);		// 删除 above_cast 操作。
  return llvm::success();		// 成功返回。
}

#else

namespace {
struct BufferCastOpFold
    : public OpRewritePattern< ::mlir::north_star::BufferCastOp> {		// 定义 BufferCastOpFold 结构体，继承自模板类 OpRewritePattern 专门匹配 BufferCastOp。
  using OpRewritePattern::OpRewritePattern;		// 继承父类构造函数。

  // match函数判断是否满足重写条件。判断方法与上面一致
  virtual LogicalResult match(::mlir::north_star::BufferCastOp op) const {
    Operation *above_cast = nullptr;
    for (auto [index, operand] : llvm::enumerate(op->getOperands())) {
      if (isa<BlockArgument>(operand)) return llvm::failure();
      if (!above_cast) {
        above_cast = operand.getDefiningOp();
      } else {
        if (operand.getDefiningOp() != above_cast) return llvm::failure();
      }
      if (operand.getType() != above_cast->getResult(index).getType())
        return llvm::failure();
      if (!above_cast->getResult(index).hasOneUse()) return llvm::failure();
    }
    return llvm::success();
  }

  // rewrite 虚函数 执行重写操作。	当前待重写的 BufferCastOp。
  virtual void rewrite(::mlir::north_star::BufferCastOp op,
                       PatternRewriter &rewriter) const {
    Operation *above_cast = op->getOperand(0).getDefiningOp();	// 取第一个操作数 op->getOperand(0)。
    for (auto [index, res] : llvm::enumerate(op->getResults())) {
      rewriter.replaceAllUsesWith(res, above_cast->getOperand(index));		// 使用 rewriter.replaceAllUsesWith() 替换当前结果 res 的所有用法为：above_cast 的第 index 个操作数
    }	
    rewriter.eraseOp(op);		// 删除当前操作 op。
    rewriter.eraseOp(above_cast);			// 删除上层操作 above_cast。
  }
};
}  // namespace

void mlir::north_star::BufferCastOp::getCanonicalizationPatterns(
    ::mlir::RewritePatternSet &results, ::mlir::MLIRContext *context) {
  results.addWithLabel<BufferCastOpFold>(StringRef("BufferCastOpFold"),
                                         context);
}

#endif
#undef __USE_hasCanonicalizeMethod__

//isSplatZero函数，意思是是否全0展开	Type elemType：张量元素的类型。	DenseElementsAttr val：张量的密集元素属性，代表实际的数据。
namespace {
static bool isSplatZero(Type elemType, DenseElementsAttr val) {
  if (llvm::isa<FloatType>(elemType)) {		// 判断elemType是否为浮点类型。
    // val：确认val不是空。	val.isSplat()：检查val是否是“splat”，即所有元素是否都相同。	val.getSplatValue<APFloat>()：获取splat值，强制类型为APFloat（LLVM任意精度浮点）。		.isZero()：判断splat值是否是0。		满足val存在且所有元素相同且这个相同的值是浮点0时，返回true。
    return val && val.isSplat() && val.getSplatValue<APFloat>().isZero();
  }
  if (llvm::isa<IntegerType>(elemType)) {	// 判断elemType是否为整数类型。
    return val && val.isSplat() && val.getSplatValue<APInt>().isZero();
  }
  return false;		// 如果既不是浮点类型，也不是整数类型，或者不满足上述条件，返回false。
}

// 与第一个函数结构相同，判断是否为“全一展开”，即所有元素相同且值为1。
static bool isSplatOne(Type elemType, DenseElementsAttr val) {
  if (llvm::isa<FloatType>(elemType)) {
    return val && val.isSplat() &&
           (val.getSplatValue<APFloat>().convertToDouble() == 1);		// 取得splat浮点值，调用convertToDouble()转换成double类型。
  }
  if (llvm::isa<IntegerType>(elemType)) {		// 判断元素类型是否整数。
    return val && val.isSplat() && val.getSplatValue<APInt>().isAllOnes();		// 判断整数类型的splat值是否是“全1位”，即二进制所有位都是1。
  }
  return false;
}		// 这两个函数是判断张量元素的特殊值模式：是否全是0，或者是否全是1（浮点1或整数全1位）。这种判断可以帮助编译器做优化，比如跳过全零计算，或用更快的方式处理全一的情况。

// DenseElementsAttr：这是函数的返回值类型，表示一个稠密元素张量常量,是 MLIR 中用来表示常量张量的属性对象。
// returnTy：操作返回的类型，形状类型（ShapedType）
// function_ref<APInt(llvm::APInt, llvm::APInt)> int_calculate：这是一个函数引用，接受两个 APInt 并返回一个 APInt，用于整数类型的二元计算逻辑（例如加法、乘法）。		function_ref<APFloat(llvm::APFloat, llvm::APFloat)> float_calculate：浮点数的二元计算逻辑（比如浮点加减乘除）。
DenseElementsAttr splatDenseBinaryFolder(
    DenseElementsAttr lhs, DenseElementsAttr rhs, ShapedType returnTy,
    function_ref<APInt(llvm::APInt, llvm::APInt)> int_calculate,
    function_ref<APFloat(llvm::APFloat, llvm::APFloat)> float_calculate) {
  if (rhs && lhs && rhs.isSplat() && lhs.isSplat()) {	//检查lhs和rhs是否非空，是否是一个全值相同的常量张量
    auto lhs_ele_type = llvm::cast<ShapedType>(lhs.getType()).getElementType(); // 把 lhs.getType() 显式地转为 ShapedType，再使用 ShapedType 的方法.getElementType()获取张量的元素类型
    auto rhs_ele_type = llvm::cast<ShapedType>(rhs.getType()).getElementType();
    if (lhs_ele_type != rhs_ele_type) return {};	// 若左右两个张量元素类型不一致，则无法计算，直接返回空。
    if (llvm::isa<IntegerType>(lhs_ele_type)) {		// 判断 lhs 的元素类型是不是整数
      APInt l = lhs.getSplatValue<APInt>();		// lhs.getSplatValue<APInt>()：获取 lhs 中唯一的那个值（所有元素都相同），类型为 APInt。
      APInt r = rhs.getSplatValue<APInt>();
      auto result = int_calculate(l, r);		// 将两个 APInt 输入给用户传入的计算函数
      return DenseElementsAttr::get(returnTy, result);		// 构造新的张量属性，其中所有元素都是 result。
    }
    if (llvm::isa<FloatType>(lhs_ele_type)) {		// 与整数分支完全一样，只是类型换成 APFloat，函数也从 int_calculate 换成 float_calculate。
      APFloat l = lhs.getSplatValue<APFloat>();
      APFloat r = rhs.getSplatValue<APFloat>();
      auto result = float_calculate(l, r);
      return DenseElementsAttr::get(returnTy, result);
    }
  }
  return {};
}
}  // namespace

    
// ConstOp 的常量折叠逻辑。
// FoldAdaptor 提供访问操作数对应的常量属性。比如：adaptor.getLhs() = DenseElementsAttr 	if %lhs is constant
// OpFoldResult 是折叠返回类型，允许返回 Attribute 或 Value，MLIR 会处理成 Value 或 Attr 替代原始 add。
OpFoldResult ConstOp::fold(FoldAdaptor adaptor) { return getValueAttr(); }

OpFoldResult AddOp::fold(FoldAdaptor adaptor) {
  auto res_type = getType();
  if (!isa<NSTensorType>(res_type)) return {};	// 这里要求返回值是 NSTensorType，否则拒绝折叠。意思是仅对 NorthStar 自定义张量类型启用该优化。
  if (isa<ShapedType>(res_type)) {		// 检查 res_type 是否是 MLIR 里的张量/形状类型（如 tensor<4xf32>）
    auto lhs_type = llvm::dyn_cast<ShapedType>(getLhs().getType());		// 把 lhs, rhs, result 的类型都转成 ShapedType，方便获取 getElementType()。
    auto rhs_type = llvm::dyn_cast<ShapedType>(getRhs().getType());
    auto result_type = llvm::dyn_cast<ShapedType>(getType());
    // 只支持对 整数、index、float 类型 的元素进行常量折叠。
    if (!lhs_type.getElementType().isIntOrIndexOrFloat() ||
        !rhs_type.getElementType().isIntOrIndexOrFloat())
      return {};
    // 获取常量属性
    auto lhs_attr =
        llvm::dyn_cast_if_present<DenseElementsAttr>(adaptor.getLhs());
    auto rhs_attr =
        llvm::dyn_cast_if_present<DenseElementsAttr>(adaptor.getRhs());
    
    // 常量折叠优化规则	1：add(x, 0) → x		2：add(0, x) → x
    // add(x, 0) -> x
    if (lhs_type == result_type &&
        isSplatZero(result_type.getElementType(), rhs_attr))		//如果 rhs 是全 0（比如 dense<0.0>），并且类型相同（不需要 cast），那么直接返回左边。实现了“加 0 优化”。
      return getLhs();
    // add(0, x) -> x
    if (rhs_type == result_type &&
        isSplatZero(result_type.getElementType(), lhs_attr))
      return getRhs();
    if (!lhs_attr || !rhs_attr) return {};		// 如果有一个不是常量，直接返回
      
    // 执行数值折叠	splatDenseBinaryFolder 是刚才定义的函数
    return splatDenseBinaryFolder(
        lhs_attr, rhs_attr, result_type,
        [](const APInt &a, const APInt &b) { return a + b; },
        [](const APFloat &a, const APFloat &b) { return a + b; });
  }
  return {};
}
}  // namespace mlir::north_star

```



