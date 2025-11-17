@Jabari

# 1.MLIR语言参考

​	MLIR 是一种编译器中间表示，它结合了传统三地址 SSA（静态单赋值）结构和多面体循环优化的概念，能够同时高效表示和变换高层的数据流图与底层面向高性能并行计算系统的目标代码。MLIR 统一的设计支持多种形式表示：人类可读的文本格式（用于调试）、内存中的结构（用于分析和变换）、以及紧凑的序列化格式（用于存储和传输）。本文档重点描述的是文本格式。

## 	1.1高层结构

​	MLIR 的核心是基于图状的数据结构，图中的**节点称为 Operation（操作）**，**边称为 Value（值）**。操作被组织在块（Blocks）中，块又包含在区域（Regions）中，支持层级嵌套结构，比如Operation中可以包含Regions。

​	Module 是整个 IR 的最顶层容器，类似一个程序包，包含多个 Function。Function (func.func) 是 Module 中的一级操作（Operation），函数体本身是一个 Region。Region 是 Operation 中封装控制流的结构，它包含一个或多个 Block。Block 是 Region 内的线性指令序列（Operation列表），类似基本块。

​	MLIR 的操作能够表达从高层次（如函数定义、缓冲区操作）到底层（如算术指令、逻辑门）的各种计算概念，并且操作集可以无限扩展。

​	为了支持复杂的操作变换，MLIR 采用 Pass 框架，同时利用 Traits 和 Interfaces 抽象描述操作语义，使得变换可以更通用地适应不同操作。

​	下面是一个MLIR moudle的示例

```MLIR
// Compute A*B using an implementation of multiply kernel and print the
// result using a TensorFlow op. The dimensions of A and B are partially
// known. The shapes are assumed to match.

// 这里的 func.func 是 MLIR 中的一个 Function 操作。它是 Module 里的一个 Operation。这个函数体的大括号 { ... } 里面是一段 Region。
// 这个 Region 默认只有一个 Block，这个 Block 中依次包含了代码中的所有操作（如 %n = memref.dim ...、memref.alloc 等等）。
// Block 是一个操作的有序列表，没有显式名称时默认为匿名。
func.func @mul(%A: tensor<100x?xf32>, %B: tensor<?x50xf32>) -> (tensor<100x50xf32>) {
  // Compute the inner dimension of %A using the dim operation.
  %n = memref.dim %A, 1 : tensor<100x?xf32>

  // Allocate addressable "buffers" and copy tensors %A and %B into them.
  %A_m = memref.alloc(%n) : memref<100x?xf32>
  bufferization.materialize_in_destination %A in writable %A_m
      : (tensor<100x?xf32>, memref<100x?xf32>) -> ()

  %B_m = memref.alloc(%n) : memref<?x50xf32>
  bufferization.materialize_in_destination %B in writable %B_m
      : (tensor<?x50xf32>, memref<?x50xf32>) -> ()

  // Call function @multiply passing memrefs as arguments,
  // and getting returned the result of the multiplication.
  %C_m = call @multiply(%A_m, %B_m)
          : (memref<100x?xf32>, memref<?x50xf32>) -> (memref<100x50xf32>)

  memref.dealloc %A_m : memref<100x?xf32>
  memref.dealloc %B_m : memref<?x50xf32>

  // Load the buffer data into a higher level "tensor" value.
  %C = memref.tensor_load %C_m : memref<100x50xf32>
  memref.dealloc %C_m : memref<100x50xf32>

  // Call TensorFlow built-in function to print the result tensor.
  "tf.Print"(%C){message: "mul result"} : (tensor<100x50xf32>) -> (tensor<100x50xf32>)

  return %C : tensor<100x50xf32>
}

// A function that multiplies two memrefs and returns the result.

// 这是另一个 Function 操作，同理它也有一个 Region，包含一个 Block，Block 内顺序放置指令。
func.func @multiply(%A: memref<100x?xf32>, %B: memref<?x50xf32>)
          -> (memref<100x50xf32>)  {
  // Compute the inner dimension of %A.
  %n = memref.dim %A, 1 : memref<100x?xf32>

  // Allocate memory for the multiplication result.
  %C = memref.alloc() : memref<100x50xf32>

  // Multiplication loop nest.
  
  // region里的op可以嵌套其他op
  affine.for %i = 0 to 100 {
     affine.for %j = 0 to 50 {
        memref.store 0 to %C[%i, %j] : memref<100x50xf32>
        affine.for %k = 0 to %n {
           %a_v  = memref.load %A[%i, %k] : memref<100x?xf32>
           %b_v  = memref.load %B[%k, %j] : memref<?x50xf32>
           %prod = arith.mulf %a_v, %b_v : f32
           %c_v  = memref.load %C[%i, %j] : memref<100x50xf32>
           %sum  = arith.addf %c_v, %prod : f32
           memref.store %sum, %C[%i, %j] : memref<100x50xf32>
        }
     }
  }
  return %C : memref<100x50xf32>
}
```

​	层级关系示意图如下

```perl
Module
└── func.func @mul(...)              <-- Function 操作
    └── Region (函数体)               <-- 1 个 Region
        └── Block                   <-- 1 个 Block （无显式名）
            ├── %n = memref.dim ...  <-- Operation
            ├── %A_m = memref.alloc ... <-- Operation
            ├── bufferization.materialize_in_destination ...
            ├── %B_m = memref.alloc ...
            ├── bufferization.materialize_in_destination ...
            ├── %C_m = call @multiply(...)
            ├── memref.dealloc ...
            ├── memref.dealloc ...
            ├── %C = memref.tensor_load ...
            ├── memref.dealloc ...
            ├── "tf.Print"(...)
            └── return %C

└── func.func @multiply(...)         <-- 另一个 Function 操作
    └── Region (函数体)
        └── Block
            ├── %n = memref.dim ...
            ├── %C = memref.alloc ...
            ├── affine.for %i = 0 to 100 {
            │     └── Region
            │         └── Block
            │             ├── affine.for %j = 0 to 50 {
            │             │    └── Region
            │             │        └── Block
            │             │            ├── memref.store 0 to %C[%i, %j]
            │             │            ├── affine.for %k = 0 to %n {
            │             │            │    └── Region
            │             │            │        └── Block
            │             │            │            ├── memref.load %A[%i, %k]
            │             │            │            ├── memref.load %B[%k, %j]
            │             │            │            ├── arith.mulf ...
            │             │            │            ├── memref.load %C[%i, %j]
            │             │            │            ├── arith.addf ...
            │             │            │            └── memref.store ...
            │             │            └── }
            │             │
            │             └── }
            │
            └── return %C

```



## 	1.2方言Dialect

​	方言（Dialect）是你与 MLIR 生态系统交互和扩展的机制。它们允许定义新的操作（Operation）、属性（Attribute）和类型（Type）。比如 `Affine` 方言定义了循环相关的操作，而 `LLVM` 方言定义了底层 target 操作。每个方言都有唯一的名字，并作为前缀附加在它定义的属性、操作和类型上。例如，Affine 方言使用的命名空间就是：`affine`。例如在 IR 中看到的 `affine.for`、`affine.if`、`llvm.add` 这样的操作名，前缀就是 Dialect 的命名空间。MLIR 允许多个方言共存，哪怕是主仓库之外的自定义方言，也能在一个 module 中共存。某些 Pass 会生成和使用特定的方言。MLIR 提供了一个框架，用于在不同方言之间或内部进行转换。

​	MLIR 支持的一些方言包括：

​		Affine dialect （多维循环、嵌套控制结构）

​		Func dialect（函数、函数调用）

​		GPU dialect（GPU 并行结构）

​		LLVM dialect（兼容 LLVM 的目标指令）

​		SPIR-V dialect（OpenCL/Vulkan 的 SPIR-V 二进制）

​		Vector dialect（向量化操作）

## 	1.3Operation

​	MLIR 引入了一个统一的概念：Operation（操作），用于描述多个层次的抽象与计算。MLIR 中的操作是完全可扩展的（没有固定的操作列表），并具有特定应用语义。例如，MLIR 支持：与硬件无关的通用操作（target-independent operations）、Affine 操作（用于表达循环和数组访问等）】、与特定目标硬件相关的操作（如 GPU、CPU 指令）。

​	操作的内部表示形式非常简单：一个操作由一个唯一字符串标识（如 `"tf.scramble"`、`"foo_div"`）、可以有 0个或多个返回值、可以拥有一些 属性（properties）、有一个 属性字典（dictionary of attributes）、可以有 0个或多个 successor（分支跳转的目标块）、可以包含 0个或多个 Region（区域）。

​	例如

```
// An operation that produces two results.
// The results of %result can be accessed via the <name> `#` <opNo> syntax.

// "foo_div" 是操作名（字符串标识）	() 表示无操作数（operand）	: () -> (f32, i32) 表示函数类型，无输入，两个输出，类型分别为 f32 和 i32
// %result:2 表示操作有两个结果，可通过 %result#0、%result#1 访问
%result:2 = "foo_div"() : () -> (f32, i32)

// Pretty form that defines a unique name for each result.
// 给两个输出值分别起名为 %foo 和 %bar，便于后续引用
%foo, %bar = "foo_div"() : () -> (f32, i32)

// Invoke a TensorFlow function called tf.scramble with two inputs
// and an attribute "fruit" stored in properties.
// 操作名是 "tf.scramble"（来自 TensorFlow dialect）	参数是 %result#0 和 %bar，类型分别是 f32 和 i32
// <{fruit = "banana"}> 表示这个操作携带一个属性字典（dictionary property），属性名是 "fruit"，值是 "banana"	输出类型是 f32
%2 = "tf.scramble"(%result#0, %bar) <{fruit = "banana"}> : (f32, i32) -> f32

// Invoke an operation with some discardable attributes
%foo, %bar = "foo_div"() {some_attr = "value", other_attr = 42 : i64} : () -> (f32, i32)
```

​	除了上述通用语法，方言（Dialect）还可以注册自己定义的 operation，这样便支持更友好的自定义语法格式用于 IR 打印与解析。

## 	1.4block

​	MLIR 中 Block 的文法结构为：以 `^bb0`、`^bb1` 等形式命名、可以有形式如函数参数的“块参数”，如 `(%a: i64, %b: i1)`、包含一系列 Operation，按顺序执行、最后一个 Operation 通常是 Terminator（终结符），如 `cf.br` 或 `return`。

​	每个 Block 表示一个编译器的基本块，块中的操作按顺序执行，最后的 Terminator 操作用于实现块之间的控制流跳转。一个 block 的最后必须是 Terminator 操作。但如果某个 Region 只有一个 block，它可以通过在包裹它的 Operation 上设置 `NoTerminator` 特性来避免这个要求。例如顶层模块操作 `module` 就是一个带有这个 trait 的操作，其 block 可以不以终结操作结尾。也就是说多数 Region（比如函数体）要求每个 block 必须有一个明确的终结（如 `return`），但有些情况允许省略终结操作，例如 `module {}` 的 body 是一个 Region 只有一个 Block，而且定义它的 Operation带了 `NoTerminator` trait，这样就可以不写 Terminator Op！

​	MLIR 中的 Block 可以接受一组块参数，其写法像函数参数。这些参数的具体值由操作语义定义。一个 Region 的入口块（第一个 block）的参数，相当于该 Region 的参数；其他块的参数由控制流终结操作（如 `cf.br`）传递决定。

​	例如

```
func.func @simple(i64, i1) -> i64 {
// 入口块，接收函数参数 %a 和 %cond
^bb0(%a: i64, %cond: i1): 
  cf.cond_br %cond, ^bb1, ^bb2	// cf.cond_br：条件跳转	%cond 为真跳到 ^bb1，否则跳到 ^bb2

^bb1:
  cf.br ^bb3(%a: i64)    // 把 %a 传给 bb3

^bb2:
  %b = arith.addi %a, %a : i64
  cf.br ^bb3(%b: i64)    // 把 %b 传给 bb3

^bb3(%c: i64):		// 通过 block 参数 %c 接收上一个跳转传来的值
  cf.br ^bb4(%c, %a : i64, i64)		// 再次跳转，将 %c 和原始的 %a 一起传入

// ^bb4 中执行 %d + %e 返回
^bb4(%d : i64, %e : i64):
  %0 = arith.addi %d, %e : i64
  return %0 : i64
}
```

## 	1.5region

​	Region 是一个有序的 Block 列表。在 MLIR 中，一个 Region 就像是一个代码作用域，它内部可以包含一个或多个 `Block`（基本块），每个 Block 又包含多个 Operation。可以理解为 Region 是用来组织代码控制结构（比如函数体、循环体等）的一种容器。

​	MLIR定义了两种region：SSACFG regions: 有控制流（可跳转）、Graph regions: 无控制流（仅顺序执行）。操作中 Region 的种类由 `RegionKindInterface` 来描述，这是一个接口，可以让某个 Operation 声明它的 Region 是哪种类型。

​	Region 本身没有名字，也不能被直接引用，只有它包含的 Block 有名字。Region 必须被包含在一个 Operation 中，不能单独存在，也没有类型和属性。Region 的第一个 Block 被称为入口 Block（entry block），入口 Block 的参数等价于这个 Region 的参数，入口 Block 不能作为其他 Block 的跳转目标。

​	Region 提供程序的分层封装。不能跳转到另一个 Region 里的 Block。Region 自然形成了值的作用域：内部定义的值不能泄露到外部，内部 op 可以使用外部值（除非被限制）。例如

```mlir
// any_op 是一个有 Region 的 Operation	里面的 Region 使用外部的 %a		Region 内部定义的 %new_value 不能被外部访问
"any_op"(%a) ({
  %new_value = "another_op"(%a) : (i64) -> (i64)
}) : (i64) -> (i64)
```

​	SSACFG Region:在该类型的 Region 中，操作按顺序执行，每个操作的操作数在执行前已经有明确值，执行后保持不变。控制流通过 terminator 操作 传递。每个块的最后一个操作是终结操作，控制流从一个块传递到下一个块，直到遇到终结操作为止。终结操作可以指定多个后继块，控制流会传递到其中一个块。控制流总是从 Region 的入口块开始，而在该 Region 内，控制流可以通过多个块出口，不一定需要到达 Region 末尾。

​	Graph Region：图形区域在 MLIR 中用于表示没有控制流的并发语义，或用于建模通用的有向图数据结构。它的特点是：1.没有控制流，区域内的操作没有顺序约束，不需要指定操作的执行顺序。2.仅包含一个基本块：图形区域目前只能包含一个基本块（即入口块）。3.多个源-目标关系****：在图形区域中，值表示图形的边，连接一个源节点和多个目标节点。这些节点即为 MLIR 操作，而该区域内的所有值都是“可访问”的，并且所有操作可以访问这些值。4.操作顺序灵活：在图形区域中，非终结操作可以自由重排（例如，通过规范化）。与 SSACFG 区域 不同，图形区域中的操作没有严格的顺序要求。5.允许循环结构：图形区域内的单个块或块之间可以存在循环结构，适用于反馈回路或递归结构的表示。Region的第一个块的参数被视为区域的输入参数。例如

```
"test.graph_region"() ({ // A Graph region
  %1 = "op1"(%1, %3) : (i32, i32) -> (i32)  // 表示在 Graph 区域中的一个操作，它是一个节点，可以使用同一区域内其他定义的值（如 %1 和 %3）。
  %2 = "test.ssacfg_region"() ({	// 这是一个 SSACFG Region，表示有严格控制流的区域。
     %5 = "op2"(%1, %2, %3, %4) : (i32, i32, i32, i32) -> (i32) //使用了外部定义的 %1, %2, %3, %4。这些变量被传递到 op2 操作并产生结果 %5。
  }) : () -> (i32)
  %3 = "op2"(%1, %4) : (i32, i32) -> (i32)
  %4 = "op3"(%1) : (i32) -> (i32)
}) : () -> ()
```

## 	1.6type_system

​	MLIR中的每一个值都有一个由类型系统定义的类型。MLIR拥有一个 开放的类型系统，这意味着类型的定义并没有一个固定的列表，而是可以根据应用需求自由扩展，支持自定义类型。类型的语义可以根据不同的方言（dialects）进行扩展，以适应不同的应用需求。因此，MLIR允许方言定义任意数量的类型，且没有限制它们所表示的抽象。MLIR的类型系统包括以下几种类型：1.type-alias：类型别名，用来为现有类型定义一个新的名字。2.dialect-type：方言特定的类型，由某个特定方言定义，通常是某个方言的扩展类型。3.builtin-type：内建类型，MLIR自带的基础类型。

```
!avx_m128 = vector<4 x f32>		// !avx_m128 是一个类型别名，它代表了 vector<4 x f32> 类型。

// Using the original type.	使用原始类型
"foo"(%x) : vector<4 x f32> -> ()

// Using the type alias.	使用类型别名
"foo"(%x) : !avx_m128 -> ()
```

​	和 operation 一样，dialect（方言）也可以为类型系统添加自定义扩展。所有方言类型都以 `!` 开头，然后可以是两种形式：1.`opaque-dialect-type`：不透明格式，例如!tf<string>，这是标准格式，写作 `!方言名<内容>`。2.`pretty-dialect-type`：简洁格式（语法糖），例如!tf.string，写作  !方言名.类型名<内容>

```
dialect-type ::= `!` (opaque-dialect-type | pretty-dialect-type)
```

​	MLIR 提供一个内建的 `builtin` 方言，其中定义了一组可被其他方言直接使用的类型。例如

| 类型类别    | 示例                               | 描述                                                         |
| ----------- | ---------------------------------- | ------------------------------------------------------------ |
| 整数类型    | `i1`, `i8`, `i32`, `i64`           | 定长整数类型，`i1` 表示布尔值，`i32` 表示 32 位整数。        |
| 浮点类型    | `f16`, `f32`, `f64`, `bf16`        | 标准 IEEE 浮点类型，`f32` 是 32 位浮点，`bf16` 是 brain-float16。 |
| 张量类型    | `tensor<4xf32>`, `tensor<*xf32>`   | 表示不可变张量（Tensor），支持动态维度（`*`）。              |
| MemRef 类型 | `memref<4xf32>`, `memref<?x?xi32>` | 可变的内存引用类型，常用于 Lowering。                        |
| 向量类型    | `vector<4xf32>`, `vector<2x2xi16>` | SIMD 运算支持的向量类型。                                    |
| 函数类型    | `(i32, f32) -> f32`                | 表示一个函数类型，输入输出均为类型列表。                     |
| 索引类型    | `index`                            | 特殊整数类型，用于表示数组索引、loop 上限等。                |
| 元组类型    | `tuple<i32, f32>`                  | 一组类型的组合，用于多个值的聚合传递。                       |
| 无类型      | `none`                             | 表示无值（无结果）类型。                                     |
| Opaque 类型 | `!dialect_name<...>`               | 自定义方言中的类型（非 builtin 类型）由方言自行解析。        |

## 	1.7Attribute

​	属性是用于在操作中指定“常量数据”的机制，适用于不能使用变量的场合。每个操作都有一个“属性字典”，用来关联多个属性名与属性值。MLIR 的 builtin 方言提供了大量内建属性类型，如数组、字典、字符串等，除此之外，各个 dialect 还可以自定义自己的 attribute 值格式。

​	MLIR支持为属性值定义命名别名。属性别名是一种标识符，可以用来代替定义的属性，必须在使用前进行定义。别名不能包括  .(点),因为这是为方言属性保留的。例如

```
#map = affine_map<(d0) -> (d0 + 10)>

// 使用原始属性
%b = affine.apply affine_map<(d0) -> (d0 + 10)> (%a)

// 使用属性别名
%b = affine.apply #map(%a)
```

​	与Operation类似，方言可以定义自定义属性值。MLIR 中的 **Dialect Attribute** 是以 `#` 开头的自定义结构，文法规则如下

```
dialect-namespace ::= bare-id	// 方言命名空间必须是一个 bare-id。bare-id 通常是由字母、数字、下划线组成的无引号字符串，不允许特殊符号。

// 一个 dialect attribute 必须以 # 开头,然后是两种形式之一：opaque-dialect-attribute,pretty-dialect-attribute
dialect-attribute ::= `#` (opaque-dialect-attribute | pretty-dialect-attribute)

// 方言名（如 north_star）+ 属性体 <...>。例如#north_star<my_custom_text>、#mydialect<{a: 1, b: 2}>
opaque-dialect-attribute ::= dialect-namespace dialect-attribute-body

// dialect-namespace: 如 north_star	.：点号，连接命名空间与标识符	pretty-dialect-attribute-lead-ident: attribute 名
// dialect-attribute-body?: 可选 body		例如#north_star.DP<1,2>	mydialect.empty
pretty-dialect-attribute ::= dialect-namespace `.` pretty-dialect-attribute-lead-ident
                                              dialect-attribute-body?

// pretty attribute 名称必须以字母开头，后续可以是字母、数字、点、下划线。
pretty-dialect-attribute-lead-ident ::= `[A-Za-z][A-Za-z0-9._]*`

// attribute 的本体内容必须包裹在 < 与 > 中间。例如#north_star.DP<1, 2, 3>	#mydialect.foo<[{a = 1}, {b = 2}]>
dialect-attribute-body ::= `<` dialect-attribute-contents+ `>`

// 属性体中的合法内容的定义。它是递归的，支持嵌套结构。
// dialect-attribute-body	表示可以再嵌套一个带尖括号的 body
dialect-attribute-contents ::= dialect-attribute-body
                            | `(` dialect-attribute-contents+ `)`	// 圆括号包裹的内容，也可以嵌套
                            | `[` dialect-attribute-contents+ `]`	// 方括号包裹的内容，也可以嵌套
                            | `{` dialect-attribute-contents+ `}`	// 花括号包裹的内容，也可以嵌套
                            | [^\[<({\]>)}\0]+
 // 例如#foo.tensor<[[1, 2], [3, 4]]>
```

​	Builtin 方言定义了 MLIR 中最基础、最常用的一些属性值类型，它们可以跨方言直接使用，是构造 IR 时的基础构件。这些类型包括整数值、浮点值、属性字典、稠密多维数组等。

# 2.方言Dialect

## 	2.1自定义方言

​	从最基础的层面来说，在 MLIR 中定义一个方言（Dialect）就是继承 C++ 中的 `Dialect` 类。例如

```cpp
class MyDialect : public mlir::Dialect {
  ...
};

```

​	但是这种方式手工代码多、维护复杂，因此仅适用于底层场景。MLIR 提供了一种强大的声明式定义机制 —— TableGen，这是一种通用的语言，配套工具可用于维护领域特定（domain-specific）的信息。TableGen 是 MLIR/LLVM 提供的一种专用描述语言（DSL），它允许你通过类似配置的 `.td` 文件描述方言、操作、类型、属性等，适合描述“结构化”的静态信息，如操作有哪些参数、有哪些约束。它可以自动生成所有必须的模板化 C++ 代码，从而简化定义流程，同时它还提供一些额外的工具功能（比如自动生成文档、生成接口代码）。

​	通常建议将 Dialect 的定义放在一个单独的 `.td` 文件中，与属性、操作、类型等其他子组件分开，以建立良好的层级结构。这样也可以避免某些结构被不小心重复定义的问题。

```tablegen
// Include the definition of the necessary tablegen constructs for defining
// our dialect.

// DialectBase.td 是 MLIR 提供的一个公共头文件，定义了用于创建 Dialect 的基类、字段等,所有要写 Dialect 的 .td 文件都必须先 include 它。
include "mlir/IR/DialectBase.td"

// 自定义一个方言
def MyDialect : Dialect {
  // 简短的一句话描述这个 Dialect。
  let summary = "A short one line description of my dialect.";
  // 对这个方言的详细描述文档。
  let description = [{
    My dialect is a very important dialect. This section contains a much more
    detailed description that documents all of the important pieces of information
    to know about the document.
  }];

  // 设置方言的名称为 "my_dialect"。这是 Dialect 在 IR 中的 注册名（就是 IR 中看到的 my_dialect.add 这种前缀）。
  // 这个名字必须是合法的 MLIR Identifier（小写、带下划线）。
  let name = "my_dialect";

  // 设置方言及其所有组件（Op、Attr、Type）的 C++ 命名空间为 ::my_dialect。
  let cppNamespace = "::my_dialect";
}
```

​	下面介绍一些Dialect的信息。

 1. Initialization（初始化）

    每个 Dialect 都必须实现一个初始化函数，用于在构造时添加属性、操作、类型、附加接口等所有必要的初始化逻辑。

    该函数在每个 Dialect 中都必须定义，形式如下：

    ```cpp
    void MyDialect::initialize() {
      // 方言初始化逻辑应在此处定义。
    }
    ```

​    2. Documentation（文档说明）

​	`summary` 和 `description` 字段用于为 Dialect 提供用户文档。这些信息可用于自动生成 markdown 格式的文档。

​    3. Class Name

​	生成的 C++ 类名是你在 TableGen 中定义的 `def` 名字，但会把其中的下划线 `_` 去掉。如果你写的是 `def Foo_Dialect : Dialect {}`，那么生成的类就是 `FooDialect`，你写的是 `def MyDialect`，就生成 `MyDialect`（不变）。

​    4. C++ Namespace（命名空间）

​	Dialect 以及它的子组件（操作、类型、属性等）所处的 C++ 命名空间由 `cppNamespace` 字段指定。默认使用 dialect 名字为命名空间；如果不想放入任何命名空间，写成 `""`；想指定多层嵌套命名空间，用 `::` 分隔。例如

```
let cppNamespace = "my_dialect";      // 生成：namespace my_dialect { ... }
let cppNamespace = "A::B";            // 生成：namespace A { namespace B { ... } }
```

5. C++ Accessor Generation（访问器函数自动生成）

​	当为 Dialect 及其组件（属性、操作、类型等）生成访问器函数时，系统会自动：

​		给字段名添加前缀 `get` / `set`；

​		并将下划线风格（`snake_case`）转为驼峰风格（`camelCase`）：

​			函数名使用首字母大写的驼峰（`UpperCamelCase`）

​			参数名使用首字母小写的驼峰（`lowerCamelCase`）

例如

```tablegen
def MyOp : MyDialect_Op<"op"> {
  let arguments = (ins StrAttr:$value, StrAttr:$other_value);
}
```

生成的C++类访问器如下

```cpp
StringAttr MyOp::getValue();             // 访问 value
void MyOp::setValue(StringAttr);         // 设置 value

StringAttr MyOp::getOtherValue();        // 访问 other_value
void MyOp::setOtherValue(StringAttr);    // 设置 other_value
```

6.dependentDialects：依赖的 Dialect

​	MLIR 拥有庞大的生态系统，其中包含了许多具有不同功能的方言。在实际使用中，一个方言很常见地会复用另一个方言的组件。当一个方言依赖另一个方言的组件（即在构造或运行中依赖其他方言）时，这种依赖关系必须被显式地记录。这样可以确保当加载当前方言时，其所依赖的方言也一同被加载。
可以通过 dependentDialects 字段来记录依赖：

```tablegen
def MyDialect : Dialect {
  let dependentDialects = [
    "arith::ArithDialect",
    "func::FuncDialect"
  ];
}	// 这是在 TableGen 中声明当前方言依赖了 arith 和 func 这两个方言。这样，在运行时 MLIR 会自动初始化它们，防止用到它们的类型或操作时报错。
```

7. Extra Declarations（额外声明）

   TableGen 提供的 Dialect 声明机制会尽可能自动生成必要的逻辑和方法。但是，总有一些特殊情况无法覆盖。对于这些未涵盖的情况，可以使用 extraClassDeclaration字段。该字段内的内容会被原样复制到生成的 C++ 方言类中。也就是说你可以在 extraClassDeclaration 中加入 C++ 代码，比如额外的成员函数、接口注册等，它会直接加到 MyDialect类中。适合高级自定义，比如注册额外接口等。

8. hasConstantMaterializer：从 Attribute 生成常量

   这个字段用于根据 Attribute 值和 Type 类型，生成一个 constant 操作。这是在折叠操作（folding）时使用的：当某个操作可以被折叠为常量时，需要构造一个对应的常量操作。启用 `hasConstantMaterializer` 字段后，会要求你在 Dialect 中定义 `materializeConstant` 方法来实现这个行为：

   ```
   // 用于从给定的 Attribute 值生成一个常量操作（constant operation）。生成的常量操作应该具有指定的结果类型。
   // 这个方法应该使用提供的 builder 来构建操作，不能改变插入位置。
   // 生成的操作应该是“类常量操作（constant-like）”，也就是说它在语义上是一个常量，比如 arith.constant。
   // 如果成功，应该返回所生成的表示常量值的 Operation 对象。
   // 否则，在失败时应返回 nullptr。
   Operation *MyDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                             Type type, Location loc) {
     ...
   }
   ```

9. hasNonDefaultDestructor：自定义析构函数

   当方言类有自定义析构逻辑时（即 `~MyDialect()` 中需要执行特定代码），你应该启用 `hasNonDefaultDestructor` 字段。启用后，TableGen 只会生成析构函数的声明，而不自动生成定义。你需要在 `.cpp` 中实现这个析构函数。这个字段用得较少，一般在方言内部持有资源（如缓存、分配器等）时才需要。例如，你的方言加载时申请了内存池，析构时要释放。

  10.hasOperationAttrVerify

​	当某个 Operation 使用了一个以我们 dialect 命名空间为前缀的属性（例如 `my_dialect.xxx`）时，就会调用这个函数来验证它是否合法。

  11.hasRegionArgAttrVerify

​	这个用于验证：如果某个“region 的入口 block 的参数”上使用了一个以我们 dialect 命名空间为前缀的 attribute，会调用这个函数。

  12.hasRegionResultAttrVerify

​	这个用于验证：如果某个 region 的返回值上使用了本 dialect 的 discardable attribute(可丢弃属性)，就通过这个函数校验。

  13.Operation Interface Fallback（操作接口的回退机制）

​	有些方言（dialect）是开放的生态系统（比如它允许动态扩展 operation），因此不会注册所有可能的 operation。在这种情况下，如果某个 operation 没有注册 interface 的实现，仍然可以通过 dialect 来提供默认实现。这种机制叫做：操作接口的“回退”（fallback）机制。只要在 TableGen 中设定：

```
let hasOperationInterfaceFallback = 1;
```

就可以启用这个功能。这会要求 dialect 实现一个方法：

```cpp
void *MyDialect::getRegisteredInterfaceForOp(TypeID typeID, StringAttr opName);
```

当某个 operation 查询不到某个 interface 时，MLIR 会 fallback 到 dialect 的这个方法，让你提供一个“默认的实现”。

14. Default Attribute / Type Parsers and Printers（默认属性/类型的解析与打印）

    当你在 dialect 中注册了一个自定义的 Attribute 或 Type，通常需要手动实现以下方法：

    ```cpp
    Attribute Dialect::parseAttribute(DialectAsmParser &parser, Type type);
    void Dialect::printAttribute(Attribute attr, DialectAsmPrinter &printer);
    
    Type Dialect::parseType(DialectAsmParser &parser);
    void Dialect::printType(Type type, DialectAsmPrinter &printer);
    ```

    但是，如果定义的所有 Attribute / Type 都有 mnemonic（字符串标识，例如 `ns_tensor`），可以启用 默认的 parser 和 printer 自动生成。只要在 TableGen 中设置：

    ```tablegen
    let useDefaultAttributePrinterParser = 1;
    let useDefaultTypePrinterParser = 1;
    ```

    MLIR 就会根据这些 Attribute/Type 的 mnemonic 自动帮你生成解析和打印逻辑。

 15.Dialect-wide Canonicalization Patterns（Dialect 级别的规范化重写）

​	通常，canonicalization（规范化重写）是针对某个具体的 op 来定义的。但也有些情况，希望定义一个针对整个 dialect 的规范化重写模式，例如：你的重写逻辑是基于某个 trait 或 interface；多个 op 都实现了这个接口；不想在每个 op 上重复注册这些 rewrite pattern。此时，可以启用 dialect 级别的 canonicalizer，只需设置：

```tablegen
let hasCanonicalizer = 1;
```

然后实现如下方法：

```cpp
void MyDialect::getCanonicalizationPatterns(RewritePatternSet &results) const;
```

这个函数会在注册 Pass 或 pattern 时被调用。

## 2.2定义可扩展方言
