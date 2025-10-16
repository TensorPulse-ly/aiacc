# @Jabari

# TopOps.td文件算子总结。

## 1.定义Top Dialect

### 	1.1定义Dialect

​	定义Top Dialect，在MLIR中用top标识该方言，CPP命名空间为::tpu_mlir::top

```tablegen
def Top_Dialect : Dialect {
  let name = "top";
  let summary = "A topdialect for the TPU_MLIR specification";
  let cppNamespace = "::tpu_mlir::top";
}
```

### 	1.2定义通用的属性类型

​	继承自AttrDef，绑定到Top_Dialect

```tablegen
class Top_Attr<string attrName, string attrMnemonic, list<Trait> traits = []>
    : AttrDef<Top_Dialect, attrName, traits> {
  let mnemonic = attrMnemonic;
}
```

### 	1.3定义字符串类型枚举属性的模板

```tablegen
class AnyStrAttrOf<list<string> cases> : StringBasedAttr<
  CPred<!foldl(
      "$_self.cast<StringAttr>().getValue() == \"" # !head(cases) # "\"",
      !foreach(case, !tail(cases),
               "$_self.cast<StringAttr>().getValue() == \"" # case # "\""),
      prev, cur, prev # " || " # cur)>,
  "string attribute whose value is " #
    !foldl(/*init*/!head(cases), /*list*/!tail(cases),
           prev, cur, prev # ", or " # cur)>;
```

### 	1.4定义Top Types

​	定义一个类型 AnyTensorOrNone，它表示一个值的类型可以是任意张量（AnyTensor）或空类型（NoneType）。

```tablegen
def AnyTensorOrNone: AnyTypeOf<[AnyTensor, NoneType]>;
```

## 2.Top Op

### 	2.1定义TopBaseOp类

​	定义一个TopBaseOp类，它是所有TOP操作的基类。它继承自Op类，并指定了Top_Dialect作为其方言。没有定义输入，表示其不接受任何输入。

```tablegen
class Top_BaseOp<string mnemonic, list<Trait> traits = []> :
    Op<Top_Dialect, mnemonic, traits> ;
// 定义了一个具体操作 Top_NoneOp，继承自 Top_BaseOp，助记符为 "None"。
def Top_NoneOp : Top_BaseOp<"None"> {
  let summary = "none operator";

  // description 说明这是一个返回 NoneType 的操作。
  let description = [{
    A none Op to return a NoneType.
  }];
  // 操作的输出是一个 NoneType 类型
  let results = (outs NoneType);
}
```

### 	2.2WeightOp

​	**定义：**Top_WeightOp 是 TPU-MLIR 的 top 方言中的一个操作（Operation），用于加载和处理神经网络模型的权重数据（如卷积核、偏置、全连接层权重）。它支持从外部 .npz 文件或内联字节数据（inline_bytes）加载权重，并提供灵活的配置和优化功能，适配 TPU 硬件的低精度计算、内存对齐和分布式执行需求。

​	**功能：**

​		1.权重加载：支持两种加载方式，一是从.npz文件加载，二是通过 inline_bytes 属性直接解析字节字符串，生成权重张量。

​		2.量化与格式转换：支持多种数据类型，包括浮点（FP32、FP16、BF16）、整数（INT8、INT32）和 TPU 特定的 8 位浮点格式（f8e4m3, f8e5m2）。提供缩放（scale）、有符号/无符号（is_signed）和零保护（zero_guard）等配置，优化量化过程。

​		3.内存优化：支持存储模式（store_mode：1N, 2N, 4N），确保权重数据与 TPU 的内存对齐要求一致。支持权重压缩（do_compress），减少存储空间和传输开销。

​		4.分布式计算：支持权重分割（allow_split 和 split 方法），将大型权重张量分割为多个小张量，适配 TPU 的多核并行。

​	**输入与输出：**无输入，输出是一个任意维度的张量。

​	**属性：**

| 属性名       | 类型                        | 描述                                               |
| ------------ | --------------------------- | -------------------------------------------------- |
| scale        | OptionalAttr<F64ArrayAttr>  | 缩放因子数组，用于量化或数据标准化。               |
| store_mode   | OptionalAttr<StoreModeAttr> | 存储模式（1N, 2N, 4N），指定内存对齐方式。         |
| allow_split  | OptionalAttr<I64ArrayAttr>  | 指定可分割的轴，支持分布式计算或内存优化。         |
| do_compress  | OptionalAttr<BoolAttr>      | 是否压缩权重数据，减少存储空间。                   |
| bias0, bias1 | OptionalAttr<I64Attr>       | 量化偏移参数，可能用于神经网络虚拟量化（NNVLC）。  |
| is_signed    | OptionalAttr<BoolAttr>      | 指定权重数据是有符号（true）还是无符号（false）。  |
| zero_guard   | OptionalAttr<BoolAttr>      | 是否启用零保护，防止量化或压缩中的数值异常。       |
| inline_bytes | OptionalAttr<StrAttr>       | 字节字符串（例如 base64 编码），存储内联权重数据。 |

### 	2.3InputOp

​	**定义：**InputOp操作，用于处理输入数据。"Input"，在 MLIR IR 中表示为 "top.Input"。继承自 Top_BaseOp，并实现 ShapeInterface 接口，表示支持形状推导。

​	**功能：**

​		1.加载输入：从运行时输入张量（input）获取数据，通常是模型的原始输入（如图像、视频）。

​		2.预处理：支持图像预处理操作，如调整大小（resize_dims）、归一化（scale, mean）、填充（pad_value, pad_type）。支持保持宽高比（keep_aspect_ratio, keep_ratio_mode）和特定像素格式（pixel_format, yuv_type）。

​		3.硬件适配：属性如 aligned 和 channel_format 确保输入数据适配 TPU 的内存对齐和数据布局要求。customization_format 支持融合预处理，优化 TPU 的输入处理流程。

​		4.形状推导：实现 ShapeInterface，支持动态推导输出张量的形状（基于 shape_tensor 和预处理参数）。

​	**输入和输出：**输入为张量，类型为 AnyRankedTensor。输出为处理后的输入张量，可能经过预处理（如缩放、归一化、填充）。

​	**属性：**

| 属性名               | 类型                                 | 描述                                                    |
| -------------------- | ------------------------------------ | ------------------------------------------------------- |
| shape_tensor         | OptionalAttr<I64ArrayAttr>           | 指定输入张量的形状（如果影响输出形状）。                |
| do_preprocess        | DefaultValuedAttr<BoolAttr, "false"> | 是否需要预处理，默认 false。                            |
| pixel_format         | OptionalAttr<PixelFormatAttr>        | 像素格式（如 RGB、YUV），用于图像输入。                 |
| channel_format       | OptionalAttr<ChannelFormatAttr>      | 通道格式（如 NCHW、NHWC），定义数据布局。               |
| resize_dims          | OptionalAttr<I64ArrayAttr>           | 目标尺寸，用于调整输入张量的大小（例如 [224, 224]）。   |
| keep_aspect_ratio    | OptionalAttr<BoolAttr>               | 是否保持宽高比（调整大小时）。                          |
| keep_ratio_mode      | OptionalAttr<StrAttr>                | 保持宽高比的模式（如 "letterbox" 或 "crop"）。          |
| pad_value            | OptionalAttr<I64Attr>                | 填充值，用于补齐输入数据。                              |
| pad_type             | OptionalAttr<PadModeAttr>            | 填充类型（如 "constant"、"reflect"）。                  |
| scale                | OptionalAttr<F64ArrayAttr>           | 缩放因子，用于归一化输入数据（例如 [1.0/255.0]）。      |
| mean                 | OptionalAttr<F64ArrayAttr>           | 均值，用于归一化（例如 [0.485, 0.456, 0.406]）。        |
| customization_format | OptionalAttr<StrAttr>                | 自定义格式，用于融合预处理（Fused Preprocess）。        |
| aligned              | OptionalAttr<BoolAttr>               | 是否对齐数据，适配硬件内存要求。                        |
| yuv_type             | OptionalAttr<StrAttr>                | YUV 文件的类型（例如 "NV12"、"YUV420"），用于视频输入。 |

### 	**2.4TupleOp与UnTupleOp**

​	两个比较简单的Op。TupleOp用于将多个输入张量组合为一个元组输出。其输入为可变数量的任意张量，输出为一个张量，表示打包后的元组。UnTupleOp用于将元组数据拆分为多个输出张量。其输入为可变数量的任意张量，通常是一个元组类型的张量，输出为可变数量的张量，表示解包后的单独张量。

### 	2.5Top_Op

​	Top_Op 是 top 方言中用于表示功能性操作的模板，不是具体操作。区别于基础操作（如 Top_WeightOp 用于加载权重，Top_InputOp 用于输入处理）。

​	默认traits有：

​		DeclareOpInterfaceMethods<InferenceInterface>：声明推理接口方法，可能是与模型推理相关的功能（如前向传播）。

​		DeclareOpInterfaceMethods<FlopsInterface>：声明浮点运算计数接口，用于计算操作的计算复杂度（FLOPs）。

​		DeclareOpInterfaceMethods<ShapeInterface>：声明形状推导接口，支持动态推导操作的输出张量形状。

```tablegen
// 这里!listconcat是 TableGen 语言中的一个内置指令（operator），用于将多个列表（通常是特质列表或其他序列）合并为一个单一的列表。
class Top_Op<string mnemonic, list<Trait> traits = []> :
    Top_BaseOp<mnemonic, !listconcat(traits,
       [DeclareOpInterfaceMethods<InferenceInterface>,
        DeclareOpInterfaceMethods<FlopsInterface>,
        DeclareOpInterfaceMethods<ShapeInterface>])>;
```

### 	2.6BatchNormOp

​	**定义：**在一个四维输入tensor上执行批标准化(Batch Normalization)。关于批标准化的更多细节可以参考论文《[Batch Normalization: Accelerating Deep Network Training by Reducing Internal Covariate Shift](https://arxiv.org/abs/1502.03167) 》。具体计算公式为
$$
output = \frac{input - \mathrm{E}[input]}{\sqrt{variance + \epsilon}} \cdot \gamma + \beta
$$
​	**功能：**

​		1.实现批归一化，标准化 4D 输入张量 [N, C, H, W]，沿通道维（C）计算均值和方差。

​		2.支持 ReLU 融合（do_relu 和 SupportFuseRelu），优化计算效率。

​	**输入和输出：**

​		1.张量输入

| 输入名称  | 类型            | 描述                                                         | 可能的形状和数据类型                                         |
| --------- | --------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| $input    | AnyTensor       | 输入张量，通常表示 mini-batch 的激活数据，沿通道维（C）进行标准化。 | 4D 张量 [N, C, H, W]，如 [32, 64, 224, 224]，数据类型通常为 f32 或量化类型（如 i8）。 |
| $mean     | AnyTensor       | 通道维（C）的均值张量，用于标准化计算的均值。                | 1D 张量 [C]，如 [64]，数据类型通常为 f32。                   |
| $variance | AnyTensor       | 通道维（C）的方差张量，量化每个 mini-batch 在通道维上的分散程度。 | 1D 张量 [C]，如 [64]，数据类型通常为 f32。                   |
| $gamma    | AnyTensorOrNone | 可选的缩放因子张量，控制标准化后的幅度，是可学习的参数。     | 1D 张量 [C]，如 [64]，数据类型通常为 f32；若为 None，则不应用缩放。 |
| $beta     | AnyTensorOrNone | 可选的偏移因子张量，控制标准化的偏移，是可学习的参数。       | 1D 张量 [C]，如 [64]，数据类型通常为 f32；若为 None，则不应用偏移。 |

​		2.属性输入

| 属性名称   | 类型     | 默认值 | 描述                                                     | 可能的取值范围/备注                             |
| ---------- | -------- | ------ | -------------------------------------------------------- | ----------------------------------------------- |
| epsilon    | F64Attr  | 1e-05  | 防止除零的小值，用于标准化计算中的分母，避免数值不稳定。 | 浮点数，通常为正小数（如 $10^{-5}$`10^{-5}`）。 |
| do_relu    | BoolAttr | false  | 控制是否在批归一化计算后应用 ReLU 激活函数。             | true 或 false。                                 |
| relu_limit | F64Attr  | -1.0   | ReLU 激活的上界限制，-1.0 表示无上界，仅受 ReLU 影响。   | 浮点数，-1.0（无上界）或正数（如 6.0）。        |

​		3.输出：单个张量（output），类型为 AnyTensor，通常与输入形状相同。

​	**Traits:**

| 特质名称                                      | 类型            | 描述                                                         |
| --------------------------------------------- | --------------- | ------------------------------------------------------------ |
| SupportFuseRelu                               | Trait           | 支持将 ReLU 激活函数融合到批归一化操作中，优化计算和内存效率。 |
| DeclareOpInterfaceMethods<InferenceInterface> | Interface Trait | 声明推理接口方法，支持批归一化的前向传播逻辑。               |
| DeclareOpInterfaceMethods<FlopsInterface>     | Interface Trait | 声明浮点运算计数接口，计算批归一化操作的计算复杂度（FLOPs）。 |
| DeclareOpInterfaceMethods<ShapeInterface>     | Interface Trait | 声明形状推导接口，推导输出张量的形状。                       |

### 	2.7CastOp

​	**定义：**Top_CastOp 是 top 方言中的类型转换操作，广泛用于神经网络的量化流程。它继承自Top_Op,包含三个接口特质。助记符："Cast"，在 MLIR IR 中表示为 "top.Cast"。

​	**功能：**

​		Top_CastOp 实现类型转换（Cast），支持以下两种转换：

​			1.将 quant::UniformQuantizedType（量化类型）转换为浮点类型（如 f32）。

​			2.将浮点类型（如 f32）转换为 quant::UniformQuantizedType（量化类型）。

​	**输入与输出：**输入为张量，可能是浮点类型或张量类型。round_mode是用来控制从高精度到低精度的舍入方式。输出为转换后的张量，形状与输入相同，数据类型根据目标类型（浮点或量化）确定。

​	**Traits：**

### 	2.8DtypeCastOp

​		**定义：**Top_DtypeCastOp 的操作，继承自 Top_Op 模板类。Top_DtypeCastOp 是类型转换操作，专注于 F32 到 F16 的降精度转换。常用于模型优化，降低推理时的内存和计算需求。

​		**功能：**将 F32（32 位浮点，单精度）转换为 F16（16 位浮点，半精度）。转换过程通常涉及：截断 F32 的尾数部分（从 23 位到 10 位）。调整指数和符号位。可能应用舍入（取决于硬件或编译器实现）。

​		**输入与输出：**输入为张量，数据类型为F32。输出也为张量，数据类型为F16。

​		**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.9ConcatOp

​	**定义：**Top_ConcatOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_ConcatOp 实现张量拼接（Concatenation），沿指定维度（axis）将多个输入张量连接成一个输出张量。要求所有输入张量（除拼接维度外）具有相同形状，或部分输入为空。

​	**输入与输出：**输入为可变数量的张量，任意维度张量，形状除 axis 外一致，如 [N, C1, H, W] 和 [N, C2, H, W] 拼接成 [N, C1+C2, H, W]。

​				属性

| 属性名称   | 类型          | 默认值             | 描述                               | 可能的取值范围/备注                                          |
| ---------- | ------------- | ------------------ | ---------------------------------- | ------------------------------------------------------------ |
| axis       | SI32Attr      | 1                  | 指定拼接的维度。                   | 整数，范围为 [0, rank-1]（张量维度数减 1）。                 |
| do_relu    | BoolAttr      | false              | 控制是否在拼接后应用 ReLU 激活。   | true 或 false。                                              |
| relu_limit | F64Attr       | -1.0               | ReLU 激活的上界，-1.0 表示无上界。 | 浮点数，-1.0（无上界）或正数（如 6.0）。                     |
| round_mode | RoundModeAttr | "HalfAwayFromZero" | 控制从高精度到低精度的舍入方式。   | 可能的取值包括 "HalfAwayFromZero"（四舍五入）、"Floor"（向下取整）等。 |

​			输出为拼接后的张量，形状为输入张量在 axis 维度上相加，如 [N, C1+C2, H, W]，数据类型与输入一致。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

​	**示例：**

```mlir
%output = "top.Concat"(%input1, %input2, %input3) {
  axis = 1 : i32,
  do_relu = true,
  relu_limit = 6.0 : f64,
  round_mode = "HalfAwayFromZero"
} : (tensor<32x64x224x224xf32>, tensor<32x32x224x224xf32>, tensor<32x16x224x224xf32>) -> tensor<32x112x224x224xf32>
```

### 	**2.10RequantIntOp**

​	**定义：** Top_RequantIntOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_RequantIntOp 实现从 32 位、16 位或 8 位整数数据到 int8 或 uint8 的重新量化（Requantization）。使用整数乘法因子（multiplier）和右移位数（rshift）执行固定点量化。

​	**输入与输出：**输入为张量，数据类型为int32、int16 或 int8。输出为重新量化后的张量，形状与输入相同。属性如下

| 属性名称   | 类型            | 默认值             | 描述                               | 可能的取值范围/备注                                          |
| ---------- | --------------- | ------------------ | ---------------------------------- | ------------------------------------------------------------ |
| multiplier | I64ArrayAttr    | (无默认值)         | 整数乘法因子数组，用于固定点量化。 | 整数数组，长度与 rq_axis 维度相关。                          |
| rshift     | I64ArrayAttr    | (无默认值)         | 右移位数数组，控制量化值的位移。   | 整数数组，长度与 rq_axis 维度相关。                          |
| quant_mode | RequantModeAttr | (无默认值)         | 量化模式，定义重新量化的方法。     | 特定枚举值（如 "PerTensor", "PerAxis"），取决于 MLIR 定义。  |
| round_mode | RoundModeAttr   | "HalfAwayFromZero" | 控制从高精度到低精度的舍入方式。   | 可能的取值包括 "HalfAwayFromZero"（四舍五入）、"Floor"（向下取整）等。 |
| rq_axis    | SI32Attr        | 1                  | 重新量化沿此轴应用。               | 整数，范围为 [0, rank-1]（张量维度数减 1）。                 |
| fuse_rq    | BoolAttr        | false              | 是否与前序操作融合。               | true 或 false。                                              |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.11RequantFpOp

​	**定义：**Top_RequantFpOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_RequantFpOp 实现从浮点数据（float32/float16/float8）到 int8、uint8 或 fp8 的重新量化。使用缩放因子（scale）和偏移量（offset）执行线性量化。数学公式是将输入浮点值乘以 scale，加上 offset，然后应用 round 函数（受 round_mode 和 first_round_mode 控制）。实际计算可能涉及两次舍入：首次（first_round_mode）应用于缩放结果，第二次（round_mode）应用于最终值。

​	**输入与输出：**输入张量，数据类型为 float32、float16 或 float8。输出为重新量化的张量，数据类型为 int8、uint8 。属性有

| 属性名称         | 类型            | 默认值             | 描述                             | 可能的取值范围/备注                                          |
| ---------------- | --------------- | ------------------ | -------------------------------- | ------------------------------------------------------------ |
| scale            | F64ArrayAttr    | (无默认值)         | 缩放因子数组，用于量化计算。     | 浮点数数组，长度与量化维度相关。                             |
| offset           | F64ArrayAttr    | (无默认值)         | 偏移量数组，调整量化值。         | 浮点数数组，长度与量化维度相关。                             |
| quant_mode       | RequantModeAttr | (无默认值)         | 量化模式，定义重新量化的方法。   | 特定枚举值（如 "PerTensor", "PerAxis"），取决于 MLIR 定义。  |
| round_mode       | RoundModeAttr   | "HalfAwayFromZero" | 控制从高精度到低精度的舍入方式。 | 可能的取值包括 "HalfAwayFromZero"（四舍五入）、"Floor"（向下取整）等。 |
| first_round_mode | RoundModeAttr   | "HalfUp"           | 首次舍入模式，应用于缩放值。     | 可能的取值包括 "HalfUp"（向上舍入）、"HalfAwayFromZero" 等。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.12PackOp和UnpackOp

​	**定义：**这两个Op均继承自Top_Op模版类。用于实现张量打包和解包。

​	**功能：**

​		PackOp：是一个“堆叠”操作，类似于 PyTorch 的 torch.stack。将多个张量沿新维度打包，输出张量新增一个轴，其大小等于输入张量数量（values_count）。注意与ConcatOp的区别，ConcatOp是将多个张量沿现有维度连接，扩展该维度的长度，相当于在 axis 轴上“串联”数据。

​		UnpackOp：Top_UnpackOp 实现张量解包（Unpacking），沿指定维度（axis）将一个输入张量拆分为多个输出张量。输出张量数量等于输入张量在 axis 维度的长度，每个输出张量是该维度上的一部分。

​	**输入与输出：**

​		PackOp：输入为可变数量的张量。输出为一个张量。属性有

| 属性名称     | 类型     | 默认值     | 描述                   | 可能的取值范围/备注                    |
| ------------ | -------- | ---------- | ---------------------- | -------------------------------------- |
| axis         | SI32Attr | (无默认值) | 指定打包的维度。       | 整数，范围为 [0, rank]（张量维度数）。 |
| values_count | I64Attr  | (无默认值) | 表示被打包的张量数量。 | 正整数，等于 $inputs 的数量。          |

​		UnpackOp：输入为一个张量。输出为解包后的输出张量列表，数量由 input 在 axis 维度的长度决定。属性

| 属性名称 | 类型     | 默认值     | 描述             | 可能的取值范围/备注                          |
| -------- | -------- | ---------- | ---------------- | -------------------------------------------- |
| axis     | SI32Attr | (无默认值) | 指定解包的维度。 | 整数，范围为 [0, rank-1]（张量维度数减 1）。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

​	**示例：**

​		PackOp：

```mlir
%output = "top.Pack"(%input1, %input2, %input3) {
  axis = 0 : i32,
  values_count = 3 : i64
} : (tensor<224x224xf32>, tensor<224x224xf32>, tensor<224x224xf32>) -> tensor<3x224x224xf32>
```

​		UnpackOp：

```mlir
%output1, %output2, %output3 = "top.Unpack"(%input) {
  axis = 0 : i32
} : (tensor<3x224x224xf32>) -> (tensor<224x224xf32>, tensor<224x224xf32>, tensor<224x224xf32>)
```

### 	2.13ConvOp

​	**定义：**Top_ConvOp 操作，继承自 Top_Op 模板类。它是一个卷积操作器，设计用于对输入张量执行卷积操作。输出通过可学习权重（滤波器）和可选偏置计算，遵循卷积的数学公式，包含核大小、步幅、填充和膨胀等参数。

​	**功能：**Top_ConvOp 实现二维卷积操作，将输入张量 (N, C_in, H_in, W_in) 转换为输出张量 (N, C_out, H_out, W_out)。使用可学习权重（filter）和可选偏置（bias）执行卷积，支持参数如核大小、步幅、填充和膨胀。核心卷积操作，广泛用于 CNN 模型。

​	**参数：**

​		输入：

| 输入名称 | 类型            | 描述               |
| -------- | --------------- | ------------------ |
| $input   | AnyTensor       | 输入特征图张量     |
| $filter  | AnyTensor       | 卷积核（权重）张量 |
| $bias    | AnyTensorOrNone | 偏置张量           |

​		输出：卷积后的输出特征图张量，类型为AnyTensor。

​		属性：属性表格

| 属性名称           | 类型            | 描述                       |
| ------------------ | --------------- | -------------------------- |
| kernel_shape       | I64ArrayAttr    | 卷积核大小。               |
| strides            | I64ArrayAttr    | 步幅。                     |
| pads               | I64ArrayAttr    | 填充量（上、左、下、右）。 |
| group              | I64Attr         | 分组数。                   |
| dilations          | I64ArrayAttr    | 膨胀率。                   |
| do_relu            | BoolAttr        | 是否应用 ReLU。            |
| relu_limit         | F64Attr         | ReLU 上限。                |
| dynweight_reorderd | BoolAttr        | 是否动态重排序权重。       |
| weight_is_coeff    | I64Attr         | 权重是否为系数。           |
| do_winograd        | BoolAttr        | 是否使用 Winograd 算法。   |
| auto_pad           | AutoPadModeAttr | 自动填充模式。             |
| in_int4_scale      | F64Attr         | INT4 输入缩放因子。        |
| in_int4_zp         | F64Attr         | INT4 输入零点。            |
| out_int8_scale     | F64Attr         | INT8 输出缩放因子。        |
| out_int8_zp        | F64Attr         | INT8 输出零点。            |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。同时还有SupportFuseRelu：支持 ReLU 融合。InferenceInterface：包括 backward_weight 支持反向传播。

### 	**2.14CorrelationOp**

​	**定义：** Top_CorrelationOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_CorrelationOp 实现了一种自定义的相关性计算，适用于立体匹配或光流估计等任务。根据 max_disp 对 left_feature 和 right_feature 进行切片。对切片结果进行逐元素乘法。沿通道维度（dim=1）进行均值归约。将结果拼接为输出张量。

​	**参数：**输入是可变数量的张量，一般包括left_feature 和 right_feature。输出是张量，类型是AnyTensor。属性有

| 属性名称   | 类型    | 默认值 | 描述                             | 可能的取值范围/备注              |
| ---------- | ------- | ------ | -------------------------------- | -------------------------------- |
| max_disp   | I64Attr | 0      | 最大位移次数，也是输出通道数 C。 | 正整数，影响切片次数和输出维度。 |
| num_groups | I64Attr | 1      | 批次分组数。                     | 正整数，默认 1（无分组）。       |

​	**Tairts：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.15PoolOp

​	**定义：**这是一个模板类，继承 Top_Op,mnemonic 参数定义具体池化操作（如 MaxPool 或 AvgPool）。

​	**功能：**执行池化操作，通过滑动窗口处理输入张量，支持最大或平均池化。

​	**参数：**输入与输出均为AnyTensor。属性

| 属性名称          | 类型            | 默认值             | 描述                         | 可能的取值范围/备注               |
| ----------------- | --------------- | ------------------ | ---------------------------- | --------------------------------- |
| kernel_shape      | I64ArrayAttr    | (必须指定)         | 池化窗口大小。               | 数组，如 [3, 3] 表示 3x3 窗口。   |
| strides           | I64ArrayAttr    | (必须指定)         | 滑动窗口步幅。               | 数组，如 [1, 1]。                 |
| pads              | I64ArrayAttr    | (必须指定)         | 填充量（上、左、下、右）。   | 数组，如 [1, 1, 1, 1]。           |
| ceil_mode         | BoolAttr        | (可选，默认 false) | 是否使用上取整计算输出大小。 | true 或 false。                   |
| auto_pad          | AutoPadModeAttr | (可选，默认无)     | 自动填充模式。               | "SAME_UPPER", "VALID" 等。        |
| is_adaptive       | BoolAttr        | false              | 是否为自适应池化。           | true 或 false。                   |
| keepdims          | BoolAttr        | true               | 是否保留输入维度。           | true 或 false。                   |
| pad_value         | I64Attr         | 0                  | 填充值。                     | 整数，默认 0。                    |
| count_include_pad | BoolAttr        | false              | 是否包含填充值在池化计数中。 | true 或 false。                   |
| do_relu           | BoolAttr        | false              | 是否应用 ReLU 激活。         | true 或 false。                   |
| relu_limit        | F64Attr         | -1.0               | ReLU 上限。                  | 浮点数，-1.0 表示无上限。         |
| round_mode        | RoundModeAttr   | "HalfAwayFromZero" | 舍入模式。                   | "HalfAwayFromZero", "HalfUp" 等。 |
| first_round_mode  | RoundModeAttr   | "HalfAwayFromZero" | 初始舍入模式。               | "HalfAwayFromZero", "HalfUp" 等。 |

​	**Tairts：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。并包含 SupportFuseRelu 特性。

### 	2.16PoolOp实例化

​	平均池化与最大池化，这两个Op是PoolOp的实例化。

```tablegen
def Top_AvgPoolOp:Top_PoolOp<"AvgPool">;
def Top_MaxPoolOp:Top_PoolOp<"MaxPool">;
```

​	**AdaptiveAvgPoolOp：**PoolOp的实例化，重定义 arguments，添加 output_size 属性，替代 kernel_shape、strides 等。执行自适应平均池化，根据指定 output_size 动态调整窗口大小，计算窗口内平均值。移除 kernel_shape 和 strides，通过 output_size 直接指定输出尺寸，自动计算窗口和步幅。

​	**MaxPoolWithMaskOp：**PoolOp的实例化，执行最大池化，同时生成掩码 (mask)，记录每个输出位置的最大值来源索引。

​	**PoolMaskOp：**执行池化操作并应用缩放因子 scale，生成池化掩码。

### 	2.17Depth2Space

​	**定义：**深度转空间操作, 继承 Top_Op。

​	**功能：**Top_Depth2SpaceOp 将输入张量的深度（通道）维度重新分配到空间维度（高度和宽度），实现像素重排。根据 is_inversed 参数选择标准变换或逆变换。支持两种通道顺序：DCR（深度-列-行）和 CRD（列-行-深度），以及 NCHW/NHWC 格式。可选交换高度和宽度维度。

​	**参数：**输入张量，形状 (N, C, H, W)。输出为张量，形状根据 block_h、block_w 和 is_inversed 变化。属性

| 属性名称    | 类型     | 默认值     | 描述                     | 可能的取值范围/备注 |
| ----------- | -------- | ---------- | ------------------------ | ------------------- |
| block_h     | I64Attr  | (必须指定) | 块高度，用于空间重排。   | 正整数，如 2。      |
| block_w     | I64Attr  | (必须指定) | 块宽度，用于空间重排。   | 正整数，如 2。      |
| is_CRD      | BoolAttr | (必须指定) | 是否使用列-行-深度格式。 | true 或 false。     |
| is_inversed | BoolAttr | (必须指定) | 是否执行逆变换。         | true 或 false。     |
| in_is_NCHW  | BoolAttr | true       | 输入是否为 NCHW 格式。   | true 或 false。     |
| out_is_NCHW | BoolAttr | true       | 输出是否为 NCHW 格式。   | true 或 false。     |
| swap_cr     | BoolAttr | false      | 是否交换输出高度和宽度。 | true 或 false。     |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.18AddOp

​	**定义：**加法操作,继承 Top_Op。

​	**功能：**Top_AddOp 进行输入张量 input1 和 input2 的逐元素加法。支持广播机制：若某一维度大小为 1，则根据需要进行广播。可选应用 ReLU 激活和缩放系数调整。支持标量与张量加法。

​	**参数：**输入为可变数量的张量，至少为两个。输出为相加后得到的张量。属性

| 属性名称   | 类型         | 默认值         | 描述                   | 可能的取值范围/备注         |
| ---------- | ------------ | -------------- | ---------------------- | --------------------------- |
| do_relu    | BoolAttr     | false          | 是否应用 ReLU 激活。   | true 或 false。             |
| relu_limit | F64Attr      | -1.0           | ReLU 上限。            | 浮点数，-1.0 表示无上限。   |
| coeff      | F64ArrayAttr | (可选，默认无) | 加法输出缩放系数数组。 | 浮点数数组，如 [1.0, 2.0]。 |
| is_scalar  | BoolAttr     | false          | 是否为标量加法。       | true 或 false。             |

​	**Tairts：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。同时还有SupportFuseRelu支持融合 ReLU, SupportConstant常量折叠,ScalarProducer与ScalarConsumer。ScalarProducer表示该操作能够生成标量输出。一个操作如果带有 ScalarProducer 特质，意味着它可以将张量或复杂输入处理后生成一个标量值（例如一个单一的浮点数或整数）。ScalarConsumer表示该操作能够接受标量作为输入。一个操作如果带有 ScalarConsumer 特质，意味着它能够接受标量作为输入，并将其广播或应用到张量操作中。

### 	2.19SubOp

​	**定义：**Top_SubOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_SubOp 进行输入张量 input1 和 input2 的逐元素减法。支持广播机制：若某一维度大小为 1，则根据需要进行广播。可选应用 ReLU 激活、反向减法顺序和缩放系数调整。支持标量与张量减法。

​	**参数：**输入为可变数量的张量，至少为两个。输出为张量。属性

| 属性名称   | 类型         | 默认值         | 描述                     | 可能的取值范围/备注         |
| ---------- | ------------ | -------------- | ------------------------ | --------------------------- |
| is_reverse | BoolAttr     | false          | 是否以反向顺序执行减法。 | true 或 false。             |
| do_relu    | BoolAttr     | false          | 是否应用 ReLU 激活。     | true 或 false。             |
| relu_limit | F64Attr      | -1.0           | ReLU 上限。              | 浮点数，-1.0 表示无上限。   |
| coeff      | F64ArrayAttr | (可选，默认无) | 减法输出缩放系数数组。   | 浮点数数组，如 [1.0, 2.0]。 |
| is_scalar  | BoolAttr     | false          | 是否为标量减法。         | true 或 false。             |

​	**Traits：**与AddOp相同。

### 	2.20MulOp

​	**定义：**Top_MulOp 操作，继承自 Top_Op 模板类。

​	**功能：**Top_MulOp 进行输入张量 input1 和 input2 的逐元素乘法。默认输入为张量，支持标量与张量乘法（通过 is_scalar）。可选应用 ReLU 激活。

​	**参数：**输入为可变数量的张量，至少为两个。输出为单一张量。属性

| 属性名称   | 类型     | 默认值 | 描述                 | 可能的取值范围/备注       |
| ---------- | -------- | ------ | -------------------- | ------------------------- |
| do_relu    | BoolAttr | false  | 是否应用 ReLU 激活。 | true 或 false。           |
| relu_limit | F64Attr  | -1.0   | ReLU 上限。          | 浮点数，-1.0 表示无上限。 |
| is_scalar  | BoolAttr | false  | 是否为标量乘法。     | true 或 false。           |

​	**Traits：**与AddOp相同。

### 	2.21MinOp

​	**定义：**最小值操作，继承自 Top_Op 模板类。

​	**功能：**Top_MinOp 进行多个输入张量的逐元素最小值计算。所有输入和输出的数据类型必须一致。不支持广播，输入张量形状必须匹配。

​	**参数：**输入为可变数量的张量，至少一个，形状和数据类型必须匹配。输出为张量，形状与输入一致。无属性。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。支持常量折叠 (SupportConstant)。

### 	2.22MaxOp

​	与MinOp相同，只不过是最大值操作。

### 	2.23与常量相关Op

​	与常量相关的Op有AddConstOp、SubConstOp、MulConstOp、MinConstOp、MaxConstOp、DivConstOp。

​	**AddConstOp：**进行输入张量与一个常数值 const_val 的逐元素加法。Traits有：SupportFuseRelu，支持融合 ReLU 激活。SupportPermuteMove，支持维度置换优化。ScalarProducer，可生成标量输出。ScalarConsumer，可接受标量输入。

​	**SubConstOp：**对输入张量与常数值 const_val 进行逐元素减法，可选择反向顺序。Traits有：SupportFuseRelu，支持融合 ReLU 激活。ScalarProducer，可生成标量输出。ScalarConsumer，可接受标量输入。

​	**MulConstOp：**对输入张量逐元素乘以常数值 const_val。Traits同AddConstOp。

​	**MinConstOp：**对输入张量与常数值 const_val 进行逐元素最小值比较。Traits有：ScalarProducer，可生成标量输出。ScalarConsumer，可接受标量输入。

​	**MaxConstOp：**对输入张量与常数值 const_val 进行逐元素最大值比较。Traits与MinConstOp相同。

​	**DivConstOp：**对输入张量逐元素除以常数值 const_val，可选择反向顺序。Traits与MinConstOp相同。

### 	**2.24BinaryShiftOp**

​	**定义：**带移位操作的二元运算。继承自Top_Op。

​	**功能：**Tpu_BinaryShiftOp 在两个输入张量上执行二元运算（加、减或其他），并应用移位操作。支持量化数据处理，包含饱和和舍入机制。

​	**参数：**输入为两个张量，输出为一个张量。属性

| 属性名称   | 类型            | 默认值             | 描述                         | 可能的取值范围/备注               |
| ---------- | --------------- | ------------------ | ---------------------------- | --------------------------------- |
| shift      | SI32Attr        | (必须指定)         | 移位值，应用于量化数据。     | 整数（如 -2 或 2）。              |
| mode       | BinaryShiftAttr | (必须指定)         | 二元运算类型（加、减等）。   | 枚举值（如 "add", "sub"）。       |
| is_reverse | BoolAttr        | false              | 是否反向减法。               | true 或 false。                   |
| saturation | BoolAttr        | true               | 是否饱和处理，限制输出范围。 | true 或 false。                   |
| round_mode | RoundModeAttr   | "HalfAwayFromZero" | 舍入模式。                   | 枚举值（如 "HalfAwayFromZero"）。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.25RopeOp

​	**定义：**Tpu_RopeOp 操作，继承自 Top_Op 模板类。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**多输入张量复杂运算，支持移位和饱和。

​	**参数：**输入为3个张量，输出为1个张量。属性

| 属性名称            | 类型          | 默认值             | 描述                       | 可能的取值范围/备注               |
| ------------------- | ------------- | ------------------ | -------------------------- | --------------------------------- |
| is_permute_optimize | BoolAttr      | false              | 是否应用置换优化。         | true 或 false。                   |
| mul1_round_mode     | RoundModeAttr | "HalfAwayFromZero" | 第一个乘法的舍入模式。     | 枚举值（如 "HalfAwayFromZero"）。 |
| mul2_round_mode     | RoundModeAttr | "HalfAwayFromZero" | 第二个乘法的舍入模式。     | 枚举值（如 "HalfAwayFromZero"）。 |
| add_round_mode      | RoundModeAttr | "HalfAwayFromZero" | 加法的舍入模式。           | 枚举值（如 "HalfAwayFromZero"）。 |
| mul1_shift          | SI32Attr      | 0                  | 第一个乘法结果的移位位数。 | 整数（如 -2 或 2）。              |
| mul2_shift          | SI32Attr      | 0                  | 第二个乘法结果的移位位数。 | 整数（如 -2 或 2）。              |
| add_shift           | SI32Attr      | 0                  | 加法结果的移位位数。       | 整数（如 -2 或 2）。              |
| mul1_saturation     | BoolAttr      | true               | 是否对第一个乘法输出饱和。 | true 或 false。                   |
| mul2_saturation     | BoolAttr      | true               | 是否对第二个乘法输出饱和。 | true 或 false。                   |
| add_saturation      | BoolAttr      | true               | 是否对加法输出饱和。       | true 或 false。                   |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.25BinaryConstShiftOp

​	与BinaryShiftOp类似，Tpu_BinaryConstShiftOp在输入张量上执行二元运算，并应用移位操作。区别是BinaryConstShiftOp使用常量缩放因子和移位值来调整输入张量的值。即输入有一个为标量。

### 	2.26NormalizeOp

​	**定义：**Top_NormalizeOp 操作，继承自 Top_Op 模板类。助记符："Normalize"，在 MLIR IR 中表示为 "top.Normalize"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**对输入张量进行归一化，基于指定维度计算均值 Mu，并应用缩放 scale。

​	**参数：**输入为input（单张量）、scale（权重张量）。输出为一个张量。属性

| 属性名称       | 类型     | 默认值 | 描述                   | 可能的取值范围/备注 |
| -------------- | -------- | ------ | ---------------------- | ------------------- |
| across_spatial | BoolAttr | false  | 是否跨空间维度归一化。 | true 或 false。     |
| channel_shared | BoolAttr | true   | 是否共享通道缩放权重。 | true 或 false。     |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.27ReciprocalOp

​	**定义：**Top_ReciprocalOp 操作，继承自 Top_Op 模板类。助记符："Reciprocal"，在 MLIR IR 中表示为 "top.Reciprocal"。支持融合 ReLU (SupportFuseRelu)。

​	**功能：**Top_ReciprocalOp 将一个常数值 const_val 除以输入张量 input 的每个元素。支持可选 ReLU 激活，适用于逆运算场景。

​	**参数：**输入是一个张量，输出也是一个张量。属性

| 属性名称   | 类型     | 默认值 | 描述                 | 可能的取值范围/备注       |
| ---------- | -------- | ------ | -------------------- | ------------------------- |
| const_val  | F64Attr  | 1.0    | 除法常数值。         | 浮点数（正、负或零）。    |
| do_relu    | BoolAttr | false  | 是否应用 ReLU 激活。 | true 或 false。           |
| relu_limit | F64Attr  | -1.0   | ReLU 上限。          | 浮点数，-1.0 表示无上限。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。支持融合 ReLU (SupportFuseRelu)。

### 	2.28MatMulOp

​	**定义：**Top_MatMulOp 操作，继承自 Top_Op 模板类。助记符："MatMul"，在 MLIR IR 中表示为 "top.MatMul"。支持融合 ReLU (SupportFuseRelu)。

​	**功能：**执行两个输入张量之间的二维矩阵乘法，可选添加偏置，并支持转置、量化及 ReLU 激活。

​	**参数：**输入为input（第一张量）、right（第二张量）、bias（可选偏置张量）。输出为张量。属性

| 属性名称         | 类型     | 默认值 | 描述                       | 可能的取值范围/备注       |
| ---------------- | -------- | ------ | -------------------------- | ------------------------- |
| right_transpose  | BoolAttr | false  | 是否转置 right。           | true 或 false。           |
| left_transpose   | BoolAttr | false  | 是否转置 input。           | true 或 false。           |
| output_transpose | BoolAttr | false  | 是否转置 output。          | true 或 false。           |
| hdim_is_batch    | BoolAttr | false  | input 第一维度是否为批次。 | true 或 false。           |
| keep_dims        | BoolAttr | true   | 是否保持维度。             | true 或 false。           |
| do_relu          | BoolAttr | false  | 是否应用 ReLU 激活。       | true 或 false。           |
| relu_limit       | F64Attr  | -1.0   | ReLU 上限。                | 浮点数，-1.0 表示无上限。 |
| weight_bits      | I64Attr  | (可选) | 权重大小量化位宽。         | 整数（如 4 或 8）。       |
| in_int4_scale    | F64Attr  | (可选) | 4 位输入量化缩放因子。     | 浮点数。                  |
| in_int4_zp       | F64Attr  | (可选) | 4 位输入量化零点。         | 浮点数。                  |
| out_int8_scale   | F64Attr  | (可选) | 8 位输出量化缩放因子。     | 浮点数。                  |
| out_int8_zp      | F64Attr  | (可选) | 8 位输出量化零点。         | 浮点数。                  |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。支持融合 ReLU (SupportFuseRelu)。

### 	2.29A16MatMulOp

​	**定义：**Top_A16MatMulOp 操作，继承自 Top_Op 模板类。助记符："A16MatMul"，在 MLIR IR 中表示为 "top.A16MatMul"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_A16MatMulOp 是一种专为大语言模型（LLM）线性层设计的矩阵乘法，支持 8 位权重 (w8a16) 或 4 位权重 (w4a16) 与 16 位激活 (a16) 的量化计算。权重以 int8 存储，结合 f16 通道级量化缩放因子。

​	**参数：**输入

| 输入名称 | 类型            | 描述               |
| -------- | --------------- | ------------------ |
| $input   | AnyTensor       | 输入激活张量       |
| $weight  | AnyTensor       | 量化权重张量       |
| $scale   | AnyTensor       | 通道级缩放因子张量 |
| $zp      | AnyTensor       | 零点张量           |
| $bias    | AnyTensorOrNone | 可选偏置张量       |

​		输出为矩阵乘法后的输出张量。属性

| 属性名称        | 类型     | 默认值 | 描述                         | 可能的取值范围/备注 |
| --------------- | -------- | ------ | ---------------------------- | ------------------- |
| right_transpose | BoolAttr | false  | 是否转置 weight。            | true 或 false。     |
| q_group_size    | I64Attr  | 128    | 量化分组大小。               | 整数（如 128）。    |
| weight_bits     | I64Attr  | 8      | 权重大小量化位宽（4 或 8）。 | 整数（4 或 8）。    |

​	**Triats：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.30AttentionOp

​	**定义：**Top_AttentionOp 的操作，继承自 Top_Op 模板类。助记符："Attention"，在 MLIR IR 中表示为 "top.Attention"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_AttentionOp 实现多头注意力机制，基于查询 (Q)、键 (K) 和值 (V) 计算注意力分数，生成输出表示。支持掩码 (mask) 和偏置项，适用于 Transformer 模型。

​	**参数：**输入

| 输入名称        | 类型            | 描述           |
| --------------- | --------------- | -------------- |
| $input          | AnyTensor       | 输入特征图张量 |
| $keys           | AnyTensor       | 键张量         |
| $values         | AnyTensor       | 值张量         |
| $queries_weight | AnyTensor       | 查询权重张量   |
| $queries_bias   | AnyTensorOrNone | 查询偏置张量   |
| $keys_weight    | AnyTensor       | 键权重张量     |
| $keys_bias      | AnyTensorOrNone | 键偏置张量     |
| $values_weight  | AnyTensor       | 值权重张量     |
| $values_bias    | AnyTensorOrNone | 值偏置张量     |
| $out_weight     | AnyTensor       | 输出权重张量   |
| $out_bias       | AnyTensorOrNone | 输出偏置张量   |
| $mask           | AnyTensorOrNone | 掩码张量       |

​	输出为注意力机制的输出张量。

​	属性

| 属性名称    | 类型         | 默认值     | 描述                               |
| ----------- | ------------ | ---------- | ---------------------------------- |
| scale       | F64Attr      | (必须指定) | 注意力分数的缩放因子。             |
| head        | I64Attr      | (必须指定) | 注意力头的数量。                   |
| dim         | I64Attr      | 0          | 输入特征或 Q/K/V 向量尺寸。        |
| scale_param | F64ArrayAttr | {1.0}      | 注意力分数的附加缩放参数。         |
| zp_param    | I64ArrayAttr | {0}        | 量化零点参数。                     |
| has_bias    | I64Attr      | 0          | 是否包含偏置项（0 = 无，1 = 有）。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.31PermuteOp

​	**定义：**Top_PermuteOp 操作，继承自 Top_Op 模板类。助记符："Permute"，在 MLIR IR 中表示为 "top.Permute"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**改变tensor布局, 变化tensor数据维度的顺序, 将输入的tensor按照order给定的顺序重新布局

​	**参数：**输入为一个张量。输出为一个张量。属性为一个数组，order，指定重新布局顺序。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.32TransposeOp

​	**定义：** Top_TransposeOp 操作，继承自 Top_Op 模板类。助记符："Transpose"，在 MLIR IR 中表示为 "top.Transpose"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_TransposeOp 对输入张量执行二维转置，交换指定的两个维度（dim0 和 dim1）。

​	**参数：**输入为张量。输出为转置后的输入张量。属性

| 属性名称 | 类型     | 默认值     | 描述                       | 可能的取值范围/备注                      |
| -------- | -------- | ---------- | -------------------------- | ---------------------------------------- |
| dim0     | SI32Attr | (必须指定) | 输入张量的第一个维度索引。 | 整数（0 到输入维度数-1）。               |
| dim1     | SI32Attr | (必须指定) | 输入张量的第二个维度索引。 | 整数（0 到输入维度数-1），与 dim0 不同。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.33ShuffleChannelOp

​	**定义：**Top_ShuffleChannelOp 操作，继承自 Top_Op 模板类。助记符："ShuffleChannel"，在 MLIR IR 中表示为 "top.ShuffleChannel"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_ShuffleChannelOp 对输入张量的通道维度 (C) 进行洗牌（Shuffle），通过将通道分成若干组并重新排列，保持其他维度 (N, H, W) 不变。调整通道维度内的数据顺序，提升特征多样性。

​	**参数：**输入为张量，输出为通道洗牌后的张量，形状与输入一致。属性group是指定将通道分成多少组进行洗牌。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.34ReluOp

​	**定义：**Top_ReluOp 操作，继承自 Top_Op 模板类。助记符："Relu"，在 MLIR IR 中表示为 "top.Relu"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**tensor中每个元素执行ReLU函数, 如果极限为零, 则不使用上限

​	**参数：**输入为张量，输出为应用ReLU后的张量。属性relu_limit是ReLU 上限值。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.35ListOp

​	**定义：**Top_ListOp 的操作，继承自 Top_Op 模板类。Top_ListOp 的操作，继承自 Top_Op 模板类。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_ListOp 将多个输入张量（input1, input2, ..., inputN）构造为一个列表类型的输出张量，模拟 PyTorch 的 prim::ListConstruct 行为。

​	**参数：**输入为可变数量的张量，输出为包含所有输入的列表张量。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.36ReShapeOp

​	**定义：**Top_ReshapeOp 操作，继承自 Top_Op 模板类。助记符："Reshape"，在 MLIR IR 中表示为 "top.Reshape"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_ReshapeOp 将输入张量重塑为指定形状，保持数据值和类型不变，仅调整维度结构。支持任意秩张量重塑，可通过 shape 属性或 shapeT 张量指定目标形状。

​	**参数：**输入为input（单张量）、shapeT（可选形状张量）、shape（可选形状数组）、flatten_start_dim（展平起始维度）。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.37ViewOp

​	**定义：**Top_ViewOp 的操作，继承自 Top_Op 模板类。助记符："View"，在 MLIR IR 中表示为 "top.View"。无额外特质，依赖基础 Top_Op 功能。

​	**功能：**Top_ViewOp 实现 PyTorch aten::view 的功能，通过指定 shape 参数改变输入张量的形状，而不改变底层数据。视图操作通常是轻量级的，仅调整内存布局的视图，而不复制数据。

​	**参数：**输入为input（单张量）、shapeT（可选形状张量）、shape（可选形状数组）、flatten_start_dim（展平起始维度）。

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.38FlattenOp

​	**定义：**Top_FlattenOp 的操作，继承自 Top_Op 模板类。助记符："Flatten"，在 MLIR IR 中表示为 "top.Flatten"。助记符："Flatten"，在 MLIR IR 中表示为 "top.Flatten"。映射 PyTorch aten::flatten 或 ONNX 的展平操作。

​	**功能：**Top_FlattenOp 将输入张量中指定范围的维度（从 start_dim 到 end_dim）展平为单一维度，减少张量的维度数，同时保持数据值不变。

​	**参数：**输入为input（单张量）、start_dim 和 end_dim（维度范围）。输出为output（展平后的张量）。属性

| 属性名称  | 类型    | 默认值 | 描述             |
| --------- | ------- | ------ | ---------------- |
| start_dim | I64Attr | 0      | 展平的起始维度。 |
| end_dim   | I64Attr | -1     | 展平的结束维度。 |

​	**Traits：**继承自Top_Op,自带InferenceInterface，FlopsInterface。ShapeInterface接口。

### 	2.39FAttentionOp 

​	**功能：**Top_FAttentionOp 实现 Flash Attention 机制，执行二维矩阵乘法，优化注意力计算的内存和计算效率。与传统注意力不同，它允许 queries、keys 和 values 均为激活张量，而非像 FULLY_CONNECTED 那样将权重作为属性。这是高效 Transformer 实现的优化版本，特别适用于大批量数据。

​	**参数：**输入

| 输入名称 | 类型            | 描述           |
| -------- | --------------- | -------------- |
| $queries | AnyTensor       | 查询张量       |
| $keys    | AnyTensor       | 键张量         |
| $values  | AnyTensor       | 值张量         |
| $mask    | AnyTensorOrNone | 可选掩码张量   |
| $buffer  | AnyTensorOrNone | 可选缓冲区张量 |

​		属性

| 属性名称 | 类型    | 默认值     | 描述                   |
| -------- | ------- | ---------- | ---------------------- |
| scale    | F64Attr | (必须指定) | 注意力分数的缩放因子。 |
| batch    | I64Attr | (必须指定) | 批次大小。             |
| q_head   | I64Attr | (必须指定) | 查询头的数量。         |
| kv_head  | I64Attr | (必须指定) | 键值头的数量。         |
| dim      | I64Attr | (必须指定) | 每个头的维度大小。     |
| mq       | I64Attr | (必须指定) | 查询序列长度。         |
| mk       | I64Attr | (必须指定) | 键值序列长度。         |

​		输出为注意力计算的输出张量。

### 	2.40ReverseOp

​	**功能：**Top_ReverseOp 沿指定维度 (axis) 反转输入张量的元素顺序，保持其他维度不变。这是数据预处理或特征调整中的常用操作，例如时间序列反转或图像翻转。

​	**参数：**输入为一个张量，输出为反转后的输入张量。属性axis为指定反转的维度。

​	**示例：**输入

```
[[[1, 2, 3, 4],
  [5, 6, 7, 8],
  [9, 10, 11, 12]],
 [[13, 14, 15, 16],
  [17, 18, 19, 20],
  [21, 22, 23, 24]]]
```

​		输出（反转第1维）

```
[[[9, 10, 11, 12],
  [5, 6, 7, 8],
  [1, 2, 3, 4]],
 [[21, 22, 23, 24],
  [17, 18, 19, 20],
  [13, 14, 15, 16]]]
```

### 	2.41SigmoidOp

​	**功能：**Top_SigmoidOp 实现 Sigmoid 激活函数的扩展版本，输出为 scale * Sigmoid(input) + bias，并支持可选的对数形式 (log = true)。这是神经网络中非线性激活的一种变体，适用于需要缩放和偏移的场景。

​	**参数：**输入输出均为张量。属性

| 属性名称   | 类型          | 默认值             | 描述                     |
| ---------- | ------------- | ------------------ | ------------------------ |
| scale      | F64Attr       | 1.0                | Sigmoid 输出的缩放因子。 |
| bias       | F64Attr       | 0.0                | 加到结果上的偏移量。     |
| log        | BoolAttr      | false              | 是否应用对数。           |
| round_mode | RoundModeAttr | "HalfAwayFromZero" | 精度转换时的舍入模式。   |

### 	2.42SignOp

​	**功能：**对输入张量逐元素计算符号值：若输入 > 0，则输出 1。若输入 < 0，则输出 -1。若输入 = 0，则输出 0。这是数据预处理或特征提取中的常用操作，用于确定数值方向。

​	**参数：**输入为张量，输出为符号计算后的张量。无属性。

​	**示例：**输入

```
[[-1.5, 0.0],
 [2.0, -0.5]]
```

​	输出

```
[[-1, 0],
 [1, -1]]
```

### 	2.43SoftsignOp

​	**功能：**Softsign 是一种**激活函数**（activation function），属于非线性函数族，用来把输入张量的值映射到一个有限范围（-1 到 1 之间），并且映射是平滑的。数学公式是：
$$
y = \frac{x}{1 + |x|}
$$
​	**参数：**输入是任意类型、任意维度的张量。输出是形状与输入相同，元素值经过 Softsign 公式计算的张量。无属性。

​	**示例：**输入张量为：
$$
input = [-2.0, -1.0, 0.0, 1.0, 2.0]
$$
​		对应输出为：
$$
output = \left[\frac{-2}{1+2}, \frac{-1}{1+1}, \frac{0}{1+0}, \frac{1}{1+1}, \frac{2}{1+2}\right] = [-0.6667, -0.5, 0, 0.5, 0.6667]
$$

### 	2.44SizeOp

​	**功能：**Size 算子用于获取输入张量的形状信息，类似于 PyTorch 中的 `aten::size` 操作，返回张量每个维度的大小。根据输入张量，输出该张量的尺寸（即各维度的长度）。如果指定了 `axis` 参数，则只返回对应维度的大小；否则返回整个形状向量。

​	**参数：**输入为任意形状和类型的张量。输出为形状张量。如果指定 `axis`，则输出为标量张量。属性axis表示指定获取哪个维度的大小，如果不指定，则返回整个张量的所有维度大小。

​	**示例：**

```
# 假设 input 张量形状为 [2, 3, 4]
# 示例1：不指定 axis，输出为所有维度大小
output = [2, 3, 4]
# 示例2：指定 axis=1，输出该维度大小
axis = 1
output = [3]
```

### 	2.45ArangeOp

​	**功能：**根据给定的起始值、终止值和步长，生成一个一维序列张量，包含从 `start` 开始，按照 `step` 递增，直到小于 `end` 的所有数值。

​	**参数：**输入

| 参数名 | 类型              | 是否可选 | 说明                     | 默认值 |
| ------ | ----------------- | -------- | ------------------------ | ------ |
| start  | AnyTensor 或 None | 是       | 序列起始值               | 0      |
| end    | AnyTensor         | 否       | 序列的上限（不包含该值） | 无     |
| step   | AnyTensor 或 None | 是       | 序列步长                 | 1      |

​		输出为生成的等差序列张量。

​	**示例：**

```
# 示例1：只给定 end，默认 start=0，step=1
start = None
end = 5
step = None
output = [0, 1, 2, 3, 4]
# 示例2：指定 start=2，end=7，默认 step=1
start = 2
end = 7
step = None
output = [2, 3, 4, 5, 6]
# 示例3：指定 start=1，end=5，step=2
start = 1
end = 5
step = 2
output = [1, 3]

```

### 	2.46RandnLikeOp

​	**功能：**根据输入张量的形状，创建一个同形状的张量，并用从指定正态分布中采样的随机值填充。

​	**参数：**输入

| 参数名     | 类型      | 是否必需 | 说明                               |
| ---------- | --------- | -------- | ---------------------------------- |
| input      | AnyTensor | 是       | 用于确定输出张量形状的输入张量     |
| randn_data | AnyTensor | 是       | 正态分布的特征参数（如均值、方差） |

​		输出与 `input` 形状相同，元素为符合指定正态分布的随机值组成的张量。

​	**示例：**

```
# 输入张量，形状为 [2, 3]
input = [
  [1.0, 2.0, 3.0],
  [4.0, 5.0, 6.0]
]
# randn_data 指定标准正态分布参数（均值0，方差1）
# 输出张量，形状同 input，随机采样值（示例）
output = [
  [0.12, -1.05, 0.88],
  [-0.56, 0.45, -0.33]
]
```

### 	2.47RangeOp

​	**功能：**Range 算子生成一个在指定区间内均匀间隔的数值序列，类似于 ONNX 的 Range 操作。根据起始值 `start`、终止值 `limit` 和间隔 `delta` 生成一个一维序列，包含从 `start` 开始，按 `delta` 增加，直到小于 `limit` 的所有值。

​	**参数：**输入参数

| 参数名 | 类型              | 是否可选 | 说明                     | 默认值 |
| ------ | ----------------- | -------- | ------------------------ | ------ |
| start  | AnyTensor 或 None | 是       | 序列起始值               | 0      |
| limit  | AnyTensor         | 否       | 序列的上限（不包含该值） | 无     |
| delta  | AnyTensor 或 None | 是       | 步长                     | 无     |

​		输出是生成的序列张量。

​	**示例：**

```
# 假设 limit = 5
# 示例1：默认 start=0，delta=1
start = None
limit = 5
delta = None
output = [0, 1, 2, 3, 4]
# 示例2：start=1，limit=6，delta=2
start = 1
limit = 6
delta = 2
output = [1, 3, 5]
# 示例3：start=0，limit=5，delta=1.5
start = 0
limit = 5
delta = 1.5
output = [0, 1.5, 3.0, 4.5]
```

### 	2.48ConstantFillOp

​	**功能：**生成与输入张量形状相同的张量，所有元素填充为指定常数。

​	**参数：**输入参数

| 参数名 | 类型      | 是否必需 | 说明                           |
| ------ | --------- | -------- | ------------------------------ |
| input  | AnyTensor | 是       | 用于确定输出张量形状的输入张量 |
| value  | F64Attr   | 是       | 用于填充输出张量的常数值       |

​		输出为同输入张量形状，元素全为 `value`。

​	**示例：**

```
# 输入张量形状为 [2, 3]
input = [
  [x, x, x],
  [x, x, x]
]
# value = 5.0
output = [
  [5.0, 5.0, 5.0],
  [5.0, 5.0, 5.0]
]
```

### 	2.49SiLUOp

​	**功能：**SiLU 是一种平滑激活函数，用以避免 ReLU 函数的梯度消失问题。对输入张量的每个元素计算：output = input * Sigmoid(input)

​	**参数：**输入为张量，输出为形状同输入，元素为 SiLU 激活结果的张量。

​	**示例：**

```
input = [-1, 0, 1]
output = [ -1 * sigmoid(-1), 0 * sigmoid(0), 1 * sigmoid(1) ]
       ≈ [ -0.2689, 0, 0.7311 ]
```

### 	2.50GELUOp

​	**功能：**GELU 是一种基于概率统计的平滑激活函数，用高斯误差函数调制输入。计算公式：
$$
Y = 0.5 \times input \times \left(1 + \text{erf}\left(\frac{input}{\sqrt{2}}\right)\right)
$$
​	**参数：**输入参数

| 参数名      | 类型          | 是否必需 | 说明                                                     | 默认值             |
| ----------- | ------------- | -------- | -------------------------------------------------------- | ------------------ |
| input       | AnyTensor     | 是       | 输入张量                                                 |                    |
| round_mode  | RoundModeAttr | 否       | 从高精度转低精度时的舍入方式                             | "HalfAwayFromZero" |
| approx_mode | GELUModeAttr  | 否       | 近似计算模式：normal（精确）、tanh（加速）、sigm（加速） | "normal"           |

​		输出为形状同输入，元素为 GELU 激活值的张量。

​	**示例：**

```
input = [0, 1]
output = [
  0.5 * 0 * (1 + erf(0/√2)) = 0,
  0.5 * 1 * (1 + erf(1/√2)) ≈ 0.8413
]
```

### 	2.51SplitOp

​	**功能：**将输入张量拆分成多个张量列表。按指定轴将输入张量均匀或按给定尺寸拆分成多个子张量。

​	**参数：**输入参数

| 参数名     | 类型      | 是否必需 | 说明                                   |
| ---------- | --------- | -------- | -------------------------------------- |
| input      | AnyTensor | 是       | 输入张量                               |
| axis       | SI32Attr  | 是       | 拆分的维度轴                           |
| num        | I64Attr   | 是       | 拆分份数                               |
| split_size | Optional  | 否       | 指定拆分尺寸（可选，不均匀拆分时使用） |

​		输出为拆分得到的多个张量。

​	**示例：**

```
#  4×6 的张量
input_tensor = np.array([
    [ 1,  2,  3,  4,  5,  6],
    [ 7,  8,  9, 10, 11, 12],
    [13, 14, 15, 16, 17, 18],
    [19, 20, 21, 22, 23, 24]
])
axis = 1
num = 3
split_size = None  # 均匀拆分
output_0:		
 [[ 1  2]
  [ 7  8]
  [13 14]
  [19 20]]
output_1,out_put2
```



### 	2.52SliceOp

​	**功能：**对输入张量进行切片操作，按指定起始、结束、步长以及轴，从输入张量切出子张量。

​	**参数：**输入参数

| 参数名               | 类型                  | 是否必需 | 说明                   |
| -------------------- | --------------------- | -------- | ---------------------- |
| input                | AnyTensor             | 是       | 输入张量               |
| offsetT              | AnyTensor 或 None     | 否       | 各轴起始索引张量       |
| endsT                | AnyTensor 或 None     | 否       | 各轴结束索引张量       |
| stepsT               | AnyTensor 或 None     | 否       | 各轴步长张量           |
| offset               | I64ArrayAttr          | 是       | 各轴起始索引列表       |
| steps                | I64ArrayAttr          | 是       | 各轴步长列表           |
| ends                 | I64ArrayAttr          | 是       | 各轴结束索引列表       |
| axes                 | I64ArrayAttr (默认{}) | 否       | 指定要切片的轴         |
| hasparamConvert_axes | I64ArrayAttr (默认{}) | 否       | 指定轴是否需要参数转换 |

​		输出为切片后的张量。

​	**示例：**

```
# 二维 Slice
input_2d = np.array([
    [1,  2,  3,  4],
    [5,  6,  7,  8],
    [9, 10, 11, 12]
])
offset = [0, 1]  # 行从0，列从1
ends = [2, 4]    # 行到2，列到4（不含）
steps = [1, 2]   # 行步长1，列步长2
output_2d = input_2d[offset[0]:ends[0]:steps[0],
                     offset[1]:ends[1]:steps[1]]
print(output_2d)
# [[ 2  4]
#  [ 6  8]]
```

### 	2.53StridedSliceOp

​	**功能：**该算子在输入张量上执行带有步长的切片操作，可以选择性地控制开始位置、结束位置以及切片步长，并支持通过掩码参数来省略部分维度信息、添加新维度或删除维度。

​	**参数：**

| 参数名           | 类型      | 说明                   |
| ---------------- | --------- | ---------------------- |
| input            | AnyTensor | 输入张量               |
| starts           | AnyTensor | 每个维度的起始索引     |
| ends             | AnyTensor | 每个维度的结束索引     |
| strides          | AnyTensor | 每个维度的步长         |
| begin_mask       | I64Attr   | 忽略起始索引的掩码     |
| end_mask         | I64Attr   | 忽略结束索引的掩码     |
| ellipsis_mask    | I64Attr   | 自动补全中间维度的掩码 |
| new_axis_mask    | I64Attr   | 增加新维度的掩码       |
| shrink_axis_mask | I64Attr   | 删除维度的掩码         |
| output           | AnyTensor | 输出张量               |

### 	2.54SliceAxisOp

​	**功能：**该算子在输入张量的指定单一轴上执行切片操作，可以指定起始索引、结束索引和步长，其它轴保持不变。

​	**参数：**

| 参数名 | 类型            | 说明                 |
| ------ | --------------- | -------------------- |
| input  | AnyTensor       | 输入张量             |
| axis   | AnyTensor       | 需要切片的轴         |
| start  | AnyTensor       | 起始索引             |
| step   | AnyTensorOrNone | 步长（可选，默认 1） |
| end    | AnyTensor       | 结束索引             |
| output | AnyTensor       | 输出张量             |

​	**示例：**

```
import numpy as np
# 输入张量
input_tensor = np.array([[1, 2, 3, 4],
                         [5, 6, 7, 8],
                         [9, 10, 11, 12]])
# 在 axis=1 上切片，start=1, end=4, step=2
output = input_tensor[:, 1:4:2]
# 结果：[[ 2  4],
#        [ 6  8],
#        [10 12]]
```

### 	2.55SoftmaxOp

​	**功能：**该算子对输入张量在指定轴上计算 Softmax 值，将值归一化为概率分布，并可选择在对数空间计算结果（log 模式）。

​	**参数：**

| 参数名     | 类型          | 说明              |
| ---------- | ------------- | ----------------- |
| input      | AnyTensor     | 输入张量          |
| axis       | SI32Attr      | 执行 softmax 的轴 |
| log        | BoolAttr      | 是否输出 log 形式 |
| beta       | F64Attr       | 缩放因子          |
| round_mode | RoundModeAttr | 数值舍入方式      |
| output     | AnyTensor     | 输出张量          |

​	**示例：**

```
import numpy as np
# 输入张量
input_tensor = np.array([[1.0, 2.0, 3.0],
                         [1.0, 2.0, 4.0]])
# axis=1, beta=1.0
exp_vals = np.exp(input_tensor)
output = exp_vals / np.sum(exp_vals, axis=1, keepdims=True)
# 结果：
# [[0.09003057 0.24472847 0.66524096],
#  [0.04201007 0.11419520 0.84379473]]
```

### 	2.56SoftplusOp

​	**功能：**Softplus 操作，一种平滑的 ReLU 激活函数近似。将输入张量的每个元素通过 $\ln(\exp(x) + 1)$ 进行非线性变换，输出连续且可微，常用于替代 ReLU 函数以避免梯度消失问题。

​	**参数：**

| 参数名 | 类型      | 说明     |
| ------ | --------- | -------- |
| input  | AnyTensor | 输入张量 |
| output | AnyTensor | 输出张量 |

​	**示例：**

```
import numpy as np
input_tensor = np.array([-1.0, 0.0, 1.0, 2.0])
output = np.log(np.exp(input_tensor) + 1)
print(output)
# [0.31326169 0.69314718 1.31326169 2.12692801]
```

### 	2.57FloorOp

​	**功能：**Floor 操作，对输入张量的每个元素执行向下取整，常用于取整或离散化处理。

​	**参数：**

| 参数名 | 类型      | 说明     |
| ------ | --------- | -------- |
| input  | AnyTensor | 输入张量 |
| output | AnyTensor | 输出张量 |

​	**示例：**

```
import numpy as np
input_tensor = np.array([1.7, -1.3, 0.0, 3.9])
output = np.floor(input_tensor)
print(output)
# [ 1. -2.  0.  3.]
```

### 	2.60TopKOp

​	**功能：**从输入张量的指定轴上，选择前 K 个最大或最小的元素及其对应的索引。实现排序和筛选，常用于神经网络中获取最大概率、最大值等。支持动态指定 K，选择最大或最小，并控制输出是否排序。

​	**参数：**

| 参数名               | 类型            | 说明         |
| -------------------- | --------------- | ------------ |
| input                | AnyTensor       | 输入张量     |
| axis                 | I64Attr         | 操作轴       |
| K                    | I64Attr         | 取多少元素   |
| largest              | BoolAttr        | 是否取最大值 |
| sorted               | BoolAttr        | 是否排序输出 |
| kT                   | Optional        | 动态 K       |
| replace_topk_indices | BoolAttr        | 是否替换索引 |
| values               | AnyTensorOrNone | 输出值       |
| indices              | AnyTensorOrNone | 输出索引     |

​	**示例：**

```
input = [
  [1, 5, 2, 4],
  [3, 8, 6, 7]
]
K=2，axis=1，largest=True，sorted=True
输出值 = [
  [5, 4],
  [8, 7]
]
输出索引 = [
  [1, 3],
  [1, 3]
]
```

### 	2.61TriluOp

​	**功能：**返回输入张量的上三角或下三角部分。提取矩阵或张量的上三角或下三角区域，常用于矩阵分解、线性代数计算。支持指定对角线偏移位置。

​	**参数：**

| 参数名   | 类型      | 说明                             |
| -------- | --------- | -------------------------------- |
| input    | AnyTensor | 输入张量                         |
| upper    | SI32Attr  | 是否返回上三角（1）或下三角（0） |
| diagonal | SI32Attr  | 对角线偏移                       |
| output   | AnyTensor | 输出张量                         |

​	**示例：**

```
输入：
[
  [1, 2, 3],
  [4, 5, 6],
  [7, 8, 9]
]
上三角（upper=1, diagonal=0）：
[
  [1, 2, 3],
  [0, 5, 6],
  [0, 0, 9]
]
下三角（upper=0, diagonal=-1）：
[
  [0, 0, 0],
  [4, 0, 0],
  [7, 8, 0]
]

```

### 	2.62NonZeroOp

​	**功能：**返回输入张量中非零元素的索引，按行优先顺序排列。

​	**参数：**

| 名称  | 类型             | 说明               |
| ----- | ---------------- | ------------------ |
| input | AnyTensor        | 输入张量           |
| order | NonZeroOrderAttr | 返回索引的顺序属性 |

​	**示例：**

```
input = [
  [0, 2, 0],
  [3, 0, 4]
]
output = [
  [0, 1, 1],  # 非零元素的行索引
  [1, 0, 2]   # 非零元素的列索引
]
输出的每一列表示一个非零元素的坐标，第一行是对应的行号，第二行是对应的列号。
```

### 	2.63LeakyReluOp

​	**功能：**LeakyRelu是一个激活函数，对小于0的元素乘以alpha，对大于等于0的元素不变。对输入张量元素逐个应用LeakyRelu函数。

​	**参数：**

| 名称       | 类型                                     | 说明                 |
| ---------- | ---------------------------------------- | -------------------- |
| input      | AnyTensor                                | 输入张量             |
| alpha      | F64Attr                                  | 负半轴的缩放因子     |
| round_mode | RoundModeAttr（默认 "HalfAwayFromZero"） | 精度转换时的舍入方式 |

​	**示例：**

```
输入 = [-2.0, -1.0, 0.0, 1.0, 2.0]
alpha = 0.1
输出 = [-0.2, -0.1, 0.0, 1.0, 2.0]
```

### 	2.64UpsampleOp

​	**功能：**对输入张量进行最近邻上采样。将输入张量按照指定的高度和宽度缩放因子放大。

​	**参数：**

| 名称       | 类型                   | 说明                       |
| ---------- | ---------------------- | -------------------------- |
| input      | AnyTensor              | 输入张量                   |
| scale_h    | I64Attr                | 高度缩放倍数               |
| scale_w    | I64Attr                | 宽度缩放倍数               |
| do_relu    | BoolAttr（默认 false） | 是否在上采样后应用ReLU激活 |
| relu_limit | F64Attr（默认 -1.0）   | ReLU的上限，-1表示无上限   |

​	**示例：**

```
输入 = [
  [1, 2],
  [3, 4]
]
scale_h = 2
scale_w = 2
输出 = [
  [1, 1, 2, 2],
  [1, 1, 2, 2],
  [3, 3, 4, 4],
  [3, 3, 4, 4]
]
```

### 	2.65MaxUnpoolOp

​	**功能：**根据最大池化的掩码对输入进行最大反池化操作。将池化后的张量根据掩码还原到更大尺寸。

​	**参数：**

| 名称    | 类型      | 说明                 |
| ------- | --------- | -------------------- |
| input   | AnyTensor | 池化后的张量         |
| mask    | AnyTensor | 最大值的位置掩码张量 |
| scale_h | I64Attr   | 高度缩放倍数         |
| scale_w | I64Attr   | 宽度缩放倍数         |

​	**示例：**

```
输入 = [
  [5, 6],
  [7, 8]
]
mask = [
  [1, 3],
  [4, 7]
]
scale_h = 2
scale_w = 2
输出 = [
  [0, 5, 0, 6],
  [0, 0, 0, 8],
  [7, 0, 0, 0],
  [0, 0, 0, 0]
]
```

### 	2.66LogOp

​	**功能：**计算输入张量每个元素的自然对数。

​	**参数：**

| 名称   | 类型      | 说明                           |
| ------ | --------- | ------------------------------ |
| input  | AnyTensor | 输入张量                       |
| output | AnyTensor | 输出张量，为输入张量元素取对数 |

​	**示例：**

```
输入 = [1.0, 2.7183, 7.389]
输出 = [0.0, 1.0, 2.0]
```

### 	2.67LogBOp

​	**功能：**计算输入张量以指定底数的对数。

​	**参数：**

| 名称  | 类型      | 说明       |
| ----- | --------- | ---------- |
| input | AnyTensor | 输入张量   |
| base  | I64Attr   | 对数的底数 |

​	**示例：**

```
输入 = [1, 8, 64]
base = 2
输出 = [0, 3, 6]
```

### 	2.68LRNOp

​	**功能：**局部响应归一化（Local Response Normalization），对输入的局部区域进行归一化，局部区域定义为跨通道的区域。

​	**参数：**

| 参数名 | 说明                       | 类型      | 默认值 |
| ------ | -------------------------- | --------- | ------ |
| input  | 输入张量                   | AnyTensor | —      |
| size   | 归一化时考虑的邻近通道数量 | I64Attr   | —      |
| alpha  | 缩放因子                   | F64Attr   | 0.0001 |
| beta   | 缩放因子                   | F64Attr   | 0.75   |
| bias   | 防止分母为0而加的浮点数    | F64Attr   | 1.0    |

### 	2.69ExpOp

​	**功能：**计算输入张量中每个元素的指数函数值。

​	**参数：**

| 参数名 | 说明     | 类型      | 默认值         |
| ------ | -------- | --------- | -------------- |
| input  | 输入张量 | AnyTensor | —              |
| output | 输出张量 | AnyTensor | 输入张量取指数 |

​	**示例：**

```
input = [[0, 1], [2, 3]]
output = [
  [exp(0), exp(1)],
  [exp(2), exp(3)]
]
# output = [[1.0, 2.718], [7.389, 20.085]]
```

### 	2.70ExpandOp

​	**功能：**按照给定的形状和广播规则扩展输入张量。

​	**参数：**

| 参数名 | 说明               | 类型         | 默认值 |
| ------ | ------------------ | ------------ | ------ |
| input  | 输入张量           | AnyTensor    | —      |
| shape  | 目标形状数组       | I64ArrayAttr | {}     |
| shapeT | 可选的动态形状张量 | Optional     | None   |
| output | 输出张量           | AnyTensor    | —      |

​	**示例：**

```
input = [[1, 2, 3]]  # shape (1,3)
# 扩展到 shape = (3,3)
output = [
  [1, 2, 3],
  [1, 2, 3],
  [1, 2, 3],
]
```

### 	2.71与三角函数有关的Op

​	CosOp：计算输入张量每个元素的余弦值。

​	CoshOp：计算输入张量中每个元素的双曲余弦值（Cosh）。

​	SinOp：计算输入张量中每个元素的正弦值。

​	SinhOp：计算输入张量中每个元素的双曲正弦值（Sinh）。

​	ArctanhOp：计算输入张量中每个元素的反双曲正切值（Arctanh）。

​	ArccosOp：计算输入张量中每个元素的反余弦值（Arccos）。

​	TanOp：计算输入张量中每个元素的正切值。

​	TanhOp：计算输入张量中每个元素的双曲正切值（Tanh）。

### 	2.72MishOp

​	**功能：**计算输入张量的Mish激活函数，逐元素计算。Mish(x)=x×tanh(ln(1+ex))

​	**参数：**

| 参数名 | 说明     | 类型      | 默认值                   |
| ------ | -------- | --------- | ------------------------ |
| input  | 输入张量 | AnyTensor | —                        |
| output | 输出张量 | AnyTensor | 输入张量经过Mish激活函数 |

​	**示例：**

```
import numpy as np
input = np.array([-2.0, 0.0, 2.0])
output = input * np.tanh(np.log1p(np.exp(input)))
# output ≈ [-0.252, 0.0, 1.943]
```

### 	2.73DivOp

​	**功能：**执行按元素的二元除法，可选择是否反转除法顺序，支持ReLU激活。特质有ScalarProducer与ScalarConsumer。

​	**参数：**

| 参数名     | 说明                                    | 类型     | 默认值 |
| ---------- | --------------------------------------- | -------- | ------ |
| inputs     | 输入张量数组                            | Variadic | —      |
| is_reverse | 是否执行反向除法（divisor / inputs[i]） | BoolAttr | false  |
| do_relu    | 是否在计算后执行ReLU激活                | BoolAttr | false  |
| relu_limit | ReLU激活上限（-1表示无上限）            | F64Attr  | -1.0   |
| is_scalar  | 是否与标量执行除法操作                  | BoolAttr | false  |

​	**示例：**

```
import numpy as np
input = np.array([4.0, 8.0, 16.0])
divisor = 2.0
# is_reverse = False
output = input / divisor  # [2.0, 4.0, 8.0]
# is_reverse = True
output_reverse = divisor / input  # [0.5, 0.25, 0.125]
```

### 	2.74SqueezeOp

​	**功能：**对输入tensor进行指定维度的裁剪并返回裁剪后的tensor

​	**参数：**

| 参数名    | 说明                   | 类型         | 默认值                              |
| --------- | ---------------------- | ------------ | ----------------------------------- |
| input     | 输入张量               | AnyTensor    | —                                   |
| axes      | 需要去除的维度索引列表 | I64ArrayAttr | 0代表第一个维度, -1代表最后一个维度 |
| is_scalar | 是否为标量操作         | BoolAttr     | false                               |
| output    | 输出张量               | AnyTensor    | —                                   |

​	**示例：**

```
%133 = "top.Squeeze"(%132) {axes = [-1]} : (tensor<1x255x20x20xf32) -> tensor<1x255x20xf32> loc(#loc278)
```

​	**2.75UnSqueezeOp**

​	与SqueezeOp类似，该算子通过指定的轴对输入的形状进行扩展（增加维度）。

### 	2.76ClipOp

​	**功能：**该操作限制给定的输入在某个范围内。输出计算规则如下：如果 input[i] < min，则 output[i] = min；如果 min <= input[i] <= max，则 output[i] = input[i]；如果 input[i] > max，则 output[i] = max。

​	**参数：**

| 参数名 | 类型      | 说明             |
| ------ | --------- | ---------------- |
| inputs | AnyTensor | 输入张量         |
| min    | F64Attr   | 元素允许的最小值 |
| max    | F64Attr   | 元素允许的最大值 |

| 输出名 | 类型      | 说明                 |
| ------ | --------- | -------------------- |
| output | AnyTensor | 限制范围后的输出张量 |

​	**示例：**

```
%3 = "top.Clip"(%0) {max = 1%: f64,min = 2%: f64} : (tensor<1x3x32x32xf32>) -> tensor<1x3x32x32xf32> loc("Clip")
```

### 	2.77Yuv2rgbFormulaOp

​	**功能：**将YUV格式的输入张量按指定公式转换为RGB格式输出。数学公式：R = Y + 1.402 × (V - 128)；G = Y - 0.344136 × (U - 128) - 0.714136 × (V - 128)；B = Y + 1.772 × (U - 128)

​	**参数：**

| 参数名       | 类型                                    | 说明                         |
| ------------ | --------------------------------------- | ---------------------------- |
| YUV          | AnyTensor                               | 输入的YUV张量                |
| src_format   | UI32Attr                                | 输入YUV数据的源格式          |
| dst_format   | UI32Attr                                | 输出RGB数据的目标格式        |
| image_format | ImageOutFormatAttr                      | YUV数据处理方式及RGB输出格式 |
| formula_mode | Yuv2rgbFormulaAttr                      | 转换公式模式                 |
| round_mode   | RoundModeAttr (默认 "HalfAwayFromZero") | 舍入方式                     |

| 输出名 | 类型      | 说明            |
| ------ | --------- | --------------- |
| output | AnyTensor | 转换后的RGB张量 |

### 	2.78DeconvOp

​	**功能：**根据给定参数对输入进行反卷积计算，生成输出张量。

​	**参数：**

| 参数名             | 类型                 | 说明             |
| ------------------ | -------------------- | ---------------- |
| input              | AnyTensor            | 输入张量         |
| filter             | AnyTensor            | 卷积核权重       |
| bias               | AnyTensorOrNone      | 可选偏置         |
| kernel_shape       | I64ArrayAttr         | 卷积核尺寸       |
| strides            | I64ArrayAttr         | 步幅             |
| pads               | I64ArrayAttr         | 填充             |
| group              | I64Attr (默认1)      | 分组数           |
| dilations          | OptionalAttr         | 卷积核点间距     |
| output_padding     | OptionalAttr         | 输出填充         |
| dynweight_reorderd | BoolAttr (默认false) | 是否动态重排权重 |
| do_relu            | BoolAttr (默认false) | 是否执行ReLU     |
| relu_limit         | F64Attr (默认-1.0)   | ReLU激活上限     |

| 输出名 | 类型      | 说明           |
| ------ | --------- | -------------- |
| output | AnyTensor | 反卷积结果张量 |

### 	2.79ScaleOp

​	**功能：**Y = X * S + B，其中 X/Y 的形状是 [n, c, h, w]，S/B 的形状是 [1, c, 1, 1]。对输入张量执行逐通道缩放和加偏置的运算，可选地在结果上应用 ReLU 激活。

​	**参数：**

| 参数名     | 类型      | 说明                                 |
| ---------- | --------- | ------------------------------------ |
| input      | AnyTensor | 输入张量                             |
| scale      | AnyTensor | 缩放因子（形状 [1, c, 1, 1]）        |
| bias       | AnyTensor | 偏置（形状 [1, c, 1, 1]）            |
| do_relu    | BoolAttr  | 是否应用 ReLU 激活                   |
| relu_limit | F64Attr   | ReLU 的最大限制值（-1.0 表示无上限） |
| output     | AnyTensor | 输出张量                             |

​	**示例：**

```
# 输入张量 (n=1, c=3, h=2, w=2)
X = tensor([[
    [[1, 2],
     [3, 4]],
    [[5, 6],
     [7, 8]],
    [[9, 10],
     [11, 12]]
]]
# 缩放因子 scale 和偏置 bias
S = tensor[[[[2]], [[0.5]], [[1]]]]
B = tensor[[[[0]], [[1]], [[-1]]]]
# Scale 运算
Y = X * S + B
Y = tensor([[[[ 2.0000,  4.0000],
          [ 6.0000,  8.0000]],
         [[ 3.5000,  4.0000],
          [ 4.5000,  5.0000]],
         [[ 8.0000,  9.0000],
          [10.0000, 11.0000]]]])
```

### 	2.80GRUOp

​	**功能：**执行 RNN GRU 操作。实现门控循环单元（GRU）的前向计算，支持单向或双向，并支持自定义初始隐藏状态。

​	**参数：**

| 参数名              | 类型            | 说明               |
| ------------------- | --------------- | ------------------ |
| input               | AnyTensor       | 输入张量           |
| filter              | AnyTensor       | 输入权重           |
| recurrence          | AnyTensor       | 隐藏状态权重       |
| bias                | AnyTensorOrNone | 偏置向量           |
| initial_h           | AnyTensorOrNone | 初始隐藏状态       |
| hidden_size         | I64Attr         | GRU 单元数         |
| bidirectional       | BoolAttr        | 是否双向           |
| linear_before_reset | BoolAttr        | 是否先线性变换     |
| batch_first         | BoolAttr        | batch 维是否在最前 |
| Y                   | AnyTensorOrNone | 输出序列           |
| Y_h                 | AnyTensorOrNone | 最后隐藏状态       |

### 	2.81LSTMOp

​	**功能：**执行 RNN LSTM 操作。实现长短期记忆（LSTM）的前向计算，支持双向和自定义初始状态。

​	**参数：**

| 参数名        | 类型            | 说明               |
| ------------- | --------------- | ------------------ |
| input         | AnyTensor       | 输入张量           |
| filter        | AnyTensor       | 输入权重           |
| recurrence    | AnyTensor       | 隐藏状态权重       |
| bias          | AnyTensorOrNone | 偏置               |
| initial_h     | AnyTensorOrNone | 初始隐藏状态       |
| initial_c     | AnyTensorOrNone | 初始细胞状态       |
| cont          | AnyTensorOrNone | 控制权重或上下文   |
| hidden_size   | I64Attr         | 单元数             |
| bidirectional | BoolAttr        | 是否双向           |
| batch_first   | BoolAttr        | batch 维是否在最前 |
| Y             | AnyTensorOrNone | 输出序列           |
| Y_h           | AnyTensorOrNone | 最后隐藏状态       |
| Y_c           | AnyTensorOrNone | 最后细胞状态       |

### 	2.81NmsOp

 	**功能：**onnx nms，用于根据置信度分数选择最相关的边界框，从而去除冗余的重叠边界框。执行非极大值抑制（NMS），过滤掉高重叠度的候选框。

​	**参数：**

| 参数名           | 类型      | 说明                     |
| ---------------- | --------- | ------------------------ |
| inputs           | Variadic  | 输入张量（框坐标与分数） |
| center_point_box | I64Attr   | 是否用中心点定义框       |
| max_output_size  | I64Attr   | 最大输出框数             |
| output           | AnyTensor | 过滤后的框索引           |

### 	2.82MatchTemplateOp

​	**功能：**执行 opencv MatchTemplate 操作。执行模板匹配，计算模板在输入图像不同位置的匹配分数。

​	**参数：**

| 参数名 | 类型                  | 说明     |
| ------ | --------------------- | -------- |
| input  | AnyTensor             | 输入图像 |
| match  | AnyTensor             | 模板图像 |
| mode   | MatchTemplateModeAttr | 匹配模式 |
| output | AnyTensor             | 匹配结果 |

### 	2.83GatherOp

​	**功能：**Gather 操作会根据指定的 `axis`（维度）和 `indices`（索引）从输入张量中抽取元素，形成一个新的输出张量。如果 `keepdims = true`，输出张量会在被抽取的维度保留其维度数，只是该维度长度可能变化。如果 `keepdims = false`，输出张量会移除被抽取的维度。`axis` 决定在哪个维度进行索引抽取。`is_scalar` 决定运算是否按标量模式处理。

​	**参数：**

| 名称      | 类型      | 方向 | 说明                                    |
| --------- | --------- | ---- | --------------------------------------- |
| input     | AnyTensor | 输入 | 输入张量                                |
| indices   | AnyTensor | 输入 | 要从输入张量中收集的元素索引            |
| keepdims  | BoolAttr  | 属性 | 是否保留输入张量的维度数（默认 `true`） |
| axis      | SI32Attr  | 属性 | 指定在哪个维度进行索引（默认 `0`）      |
| is_scalar | BoolAttr  | 属性 | 是否按标量模式执行（默认 `false`）      |
| output    | AnyTensor | 输出 | 抽取后的张量                            |

### 	2.84GatherElementsOp

​	**功能：**在给定轴上执行 GatherElements 操作。GatherElements 操作会在指定的 `axis` 上，根据 `indices` 张量的值，从 `input` 张量中按元素位置收集数据，生成一个与 `indices` 形状相同的输出张量。

​	**参数：**

| 名称    | 类型      | 方向 | 说明                         |
| ------- | --------- | ---- | ---------------------------- |
| input   | AnyTensor | 输入 | 输入张量                     |
| indices | AnyTensor | 输入 | 元素索引张量                 |
| axis    | I64Attr   | 属性 | 索引所作用的维度（默认 `2`） |
| output  | AnyTensor | 输出 | 按 `indices` 收集后的张量    |

### 	2.85TileOp

​	**功能：**对给定张量执行 Tile 操作。该算子通过沿每个维度复制输入张量，扩展张量的大小，实现张量的重复排列。输出张量的形状由输入张量各维度大小与对应的复制次数相乘决定。元素值通过输入张量索引对原始维度大小取模得到，从而实现循环复制的效果。

​	**参数：**

| 参数名 | 类型         | 说明                     | 是否必需 | 默认值 |
| ------ | ------------ | ------------------------ | -------- | ------ |
| input  | AnyTensor    | 输入张量                 | 是       | 无     |
| tileT  | Optional     | 复制次数张量（每个维度） | 否       | 无     |
| tile   | OptionalAttr | 复制次数数组（每个维度） | 否       | 无     |
| output | AnyTensor    | 输出张量                 | 是       | 无     |

### 	2.86RepeatOp

​	**功能：**该算子实现对输入张量的重复扩展，按照 repeats 张量中指定的重复次数，将输入张量在每个维度上进行扩展。输出张量的维度是输入维度乘以对应的重复次数。索引映射规则保证重复内容循环排列。

​	**参数：**

| 参数名  | 类型      | 说明                   | 是否必需 | 默认值 |
| ------- | --------- | ---------------------- | -------- | ------ |
| input   | AnyTensor | 输入张量               | 是       | 无     |
| repeats | AnyTensor | 每个维度的重复次数张量 | 是       | 无     |
| output  | AnyTensor | 输出张量               | 是       | 无     |

### 	2.87AbsOp

​	**功能：**该算子对输入张量的每个元素执行绝对值运算，输出与输入形状相同的张量，元素值为输入对应元素的绝对值。

​	**参数：**

| 参数名 | 类型      | 说明     | 必需 | 默认值 |
| ------ | --------- | -------- | ---- | ------ |
| input  | AnyTensor | 输入张量 | 是   | 无     |
| output | AnyTensor | 输出张量 | 是   | 无     |

### 	2.88ModOp

​	**功能：**该算子对输入的两个或多个张量对应元素执行模（余数）运算，输出结果与输入形状一致。

​	**参数：**

| 参数名 | 类型      | 说明         | 必需 | 默认值 |
| ------ | --------- | ------------ | ---- | ------ |
| inputs | Variadic  | 输入张量列表 | 是   | 无     |
| output | AnyTensor | 输出张量     | 是   | 无     |

### 	2.89PReluOp

​	**功能：**该算子实现PReLU激活，输入元素小于0时乘以可学习的斜率参数，大于等于0时保持原值，支持负斜率自适应调整。

​	**参数：**

| 参数名 | 类型      | 说明               | 必需 | 默认值 |
| ------ | --------- | ------------------ | ---- | ------ |
| input  | AnyTensor | 输入张量           | 是   | 无     |
| slope  | AnyTensor | 负区间斜率参数张量 | 是   | 无     |
| output | AnyTensor | 输出张量           | 是   | 无     |

### 	2.90InterpOp

​	**功能：**对输入张量执行线性上采样操作。该算子基于给定的缩放比例或目标形状，对输入张量进行线性插值上采样，改变其空间尺寸，支持多种插值和坐标模式。

​	**参数：**

| 参数名       | 类型                | 说明         | 必需 | 默认值 |
| ------------ | ------------------- | ------------ | ---- | ------ |
| input        | AnyTensor           | 输入张量     | 是   | 无     |
| target_shape | AnyTensorOrNone     | 目标输出形状 | 否   | 无     |
| mode         | InterpModeAttr      | 插值模式     | 是   | 无     |
| coord_mode   | InterpCoordModeAttr | 坐标模式     | 是   | 无     |
| scale_h      | DefaultValuedAttr   | 高度缩放比例 | 否   | -1.0   |
| scale_w      | DefaultValuedAttr   | 宽度缩放比例 | 否   | -1.0   |
| output       | AnyTensor           | 输出张量     | 是   | 无     |

### 	2.91MeshGridOp

​	**功能：**PyTorch 中的 mesh grid 操作。该算子生成坐标网格张量，基于输入的向量生成二维坐标矩阵，广泛用于图像处理、坐标变换等领域。

​	**参数：**

| 参数名     | 类型     | 说明         | 必需 | 默认值 |
| ---------- | -------- | ------------ | ---- | ------ |
| inputs     | Variadic | 输入张量序列 | 是   | 无     |
| is_reverse | BoolAttr | 是否反向减法 | 是   | 无     |
| outputs    | Variadic | 输出张量序列 | 是   | 无     |

### 	2.92GridSamplerOp

​	**功能：**GridSampler算子用于基于一个输入张量和一个流场（grid），进行空间采样操作。流场网格指定了采样点的位置，算子根据这些位置从输入张量中采样相应的像素值，生成新的输出张量。它常用于空间变换（如仿射变换、透视变换）和图像重采样场景。

​	**参数：**

| 参数名        | 类型      | 说明                                            |
| ------------- | --------- | ----------------------------------------------- |
| input         | AnyTensor | 输入张量                                        |
| grid          | AnyTensor | 流场网格张量，定义采样像素位置                  |
| mode          | I64Attr   | 二元操作模式                                    |
| padding_mode  | I64Attr   | 填充模式，0=“zeros”，1=“border”，2=“reflection” |
| align_corners | BoolAttr  | 是否对齐角点                                    |

### 	2.93ReduceOp

​	**功能：**计算输入张量在指定轴上的均值、最大值、乘积或求和等归约操作。用户可指定多个轴来同时归约，也可以选择是否保留维度，方便后续的张量操作和形状管理。

​	**参数：**

| 参数名    | 类型           | 说明                                |
| --------- | -------------- | ----------------------------------- |
| input     | AnyTensor      | 输入张量                            |
| axes      | I64ArrayAttr   | 需要归约的轴集合                    |
| keepdims  | BoolAttr       | 是否保留归约轴维度                  |
| mode      | ReduceModeAttr | 归约模式（sum, mean, max, product） |
| is_scalar | BoolAttr       | 是否执行标量归约操作                |

### 	2.94ArgOp

​	**功能：**计算输入张量在指定轴上元素的最小值或最大值的索引。方便定位极值位置。支持保留维度，且可控制遇到多个极值时选取第一个还是最后一个索引。

​	**参数：**输入参数

| 参数名            | 类型        | 说明                           |
| ----------------- | ----------- | ------------------------------ |
| input             | AnyTensor   | 输入张量                       |
| axis              | I64Attr     | 计算索引的轴                   |
| keepdims          | BoolAttr    | 是否保留维度                   |
| mode              | ArgModeAttr | 计算类型（最大索引或最小索引） |
| select_last_index | BoolAttr    | 多个极值时是否选最后一个索引   |

​	输出参数

| 参数名  | 类型            | 说明                      |
| ------- | --------------- | ------------------------- |
| indices | AnyTensor       | 计算得到的最大/最小值索引 |
| values  | AnyTensorOrNone | （可选）对应的极值        |

### 	2.95PowOp

​	**功能：**Top_PowOp 用于对输入的张量执行逐元素的指数运算，将张量中的每一个元素提升到指定的幂次。此操作支持浮点指数，广泛用于非线性变换、特征放大缩小等场景。输入和输出张量形状一致，输出每个元素为对应输入元素的幂值。

​	**参数：**

| 参数名   | 类型      | 说明                                     | 是否必须 | 默认值 |
| -------- | --------- | ---------------------------------------- | -------- | ------ |
| input    | AnyTensor | 输入张量，元素为待求幂的值               | 是       | 无     |
| exponent | F64Attr   | 幂指数，标量浮点数，指定幂的数值         | 是       | 无     |
| output   | AnyTensor | 输出张量，元素为输入对应元素的幂次计算值 | 是       | 无     |

​	**示例：**

```mlir
%input = tensor<[2.0, 3.0, 4.0]> : tensor<3xf32>
%output = "top.pow"(%input) { exponent = 3.0 } : (tensor<3xf32>) -> tensor<3xf32>
```

### 	2.96Pow2Op 

​	**功能：**Top_Pow2Op 用于计算给定常数值底数对输入张量元素的指数幂，输出与输入形状相同。常用于固定底数的指数运算。

​	**参数：**

| 参数名    | 类型      | 说明                         | 是否必须 | 默认值 |
| --------- | --------- | ---------------------------- | -------- | ------ |
| const_val | F64Attr   | 指定的常数底数值             | 是       | 无     |
| input     | AnyTensor | 输入张量，元素为指数         | 是       | 无     |
| output    | AnyTensor | 输出张量，元素为底数的幂结果 | 是       | 无     |

​	**示例：**输出就是[9.0,27.0,81.0]

```mlir
%input = tensor<[2.0, 3.0, 4.0]> : tensor<3xf32>
%output = "top.pow2"(3.0, %input) : (f64, tensor<3xf32>) -> tensor<3xf32>
```

### 	2.97Pow3Op

​	**功能：**Top_Pow3Op 用于逐元素计算两个输入张量的幂运算。输出张量形状同输入张量相同。该操作支持动态变化的指数值。

​	**参数：**

| 参数名 | 类型      | 说明                             | 是否必须 | 默认值 |
| ------ | --------- | -------------------------------- | -------- | ------ |
| inputs | Variadic  | 两个输入张量，分别作为底数和指数 | 是       | 无     |
| output | AnyTensor | 输出张量，对应元素为底数的指数幂 | 是       | 无     |

​	**示例：**输出为[8.0,9.0,4.0]

```mlir
%input1 = tensor<[2.0, 3.0, 4.0]> : tensor<3xf32>
%input2 = tensor<[3.0, 2.0, 1.0]> : tensor<3xf32>
%output = "top.pow3"(%input1, %input2) : (tensor<3xf32>, tensor<3xf32>) -> tensor<3xf32>
```

### 	2.98SqrtOp

​	**功能：**Top_SqrtOp 对输入张量的每个元素计算平方根，输出张量形状与输入相同。

​	**参数：**

| 参数名 | 类型      | 说明                         | 是否必须 | 默认值 |
| ------ | --------- | ---------------------------- | -------- | ------ |
| input  | AnyTensor | 输入张量                     | 是       | 无     |
| output | AnyTensor | 输出张量，元素为输入的平方根 | 是       | 无     |

​	**示例：**

```mlir
%input = tensor<[4.0, 9.0, 16.0]> : tensor<3xf32>
%output = "top.sqrt"(%input) : (tensor<3xf32>) -> tensor<3xf32>
// 输出： [2.0, 3.0, 4.0]
```

### 	2.99WhereOp

​	**功能：**根据条件张量 `cond`，从两个张量 `tbrn`（true branch）和 `fbrn`（false branch）中选择元素，输出由条件决定对应位置元素组成的新张量。

​	**参数：**

| 参数名      | 类型              | 说明                     | 是否必须 | 默认值 |
| ----------- | ----------------- | ------------------------ | -------- | ------ |
| cond        | AnyTensor         | 条件张量                 | 是       | 无     |
| tbrn        | AnyTensor 或 None | 条件为真时选择的张量     | 否       | 无     |
| fbrn        | AnyTensor 或 None | 条件为假时选择的张量     | 否       | 无     |
| x_is_const  | BoolAttr          | tbrn是否为常量           | 否       | false  |
| y_is_const  | BoolAttr          | fbrn是否为常量           | 否       | false  |
| x_const_val | F64Attr           | tbrn为常量时使用的常数值 | 否       | 0.0    |
| y_const_val | F64Attr           | fbrn为常量时使用的常数值 | 否       | 0.0    |
| output      | AnyTensor         | 输出张量                 | 是       | 无     |

​	**示例：**

```mlir
%cond = tensor<[1, 0, 1]> : tensor<3xi1>
%t = tensor<[10, 20, 30]> : tensor<3xi32>
%f = tensor<[100, 200, 300]> : tensor<3xi32>
%out = "top.where"(%cond, %t, %f) : (tensor<3xi1>, tensor<3xi32>, tensor<3xi32>) -> tensor<3xi32>
// 输出： [10, 200, 30]
```

### 	2.100MaskedFillOp

​	**功能：**根据条件张量 `cond`，将输入张量 `brn` 中满足条件的元素替换为指定常数值 `const_val`，支持掩码反转。公式为

~~~tablegen
```math
                     brn                if inversed and cond=0
            output = brn + const_val    if inversed and cond!=0
                     brn + const_val    if !inversed and cond!=0
                     brn                if !inversed and cond=0
```
~~~

​	**参数：**

| 参数名    | 类型      | 说明             | 是否必须 | 默认值 |
| --------- | --------- | ---------------- | -------- | ------ |
| cond      | AnyTensor | 条件张量         | 是       | 无     |
| brn       | AnyTensor | 输入张量         | 是       | 无     |
| inversed  | BoolAttr  | 掩码是否反转     | 是       | 无     |
| const_val | F64Attr   | 用于填充的常数值 | 是       | 无     |
| output    | AnyTensor | 输出张量         | 是       | 无     |

​	**示例：**

```
%cond = tensor<[0, 1, 0]> : tensor<3xi1>
%brn = tensor<[1.0, 2.0, 3.0]> : tensor<3xf32>
%out = "top.masked_fill"(%cond, %brn, false, 100.0) : (tensor<3xi1>, tensor<3xf32>, bool, f64) -> tensor<3xf32>
// 输出：[1.0, 102.0, 3.0]

%cond = tensor<[1, 0, 1]> : tensor<3xi1>
%brn = tensor<[5.0, 6.0, 7.0]> : tensor<3xf32>
%out = "top.masked_fill"(%cond, %brn, true, -50.0) : (tensor<3xi1>, tensor<3xf32>, bool, f64) -> tensor<3xf32>
// 输出：[ -45.0, 6.0, -43.0 ]
```

### 	2.101CompareOp

​	**功能：**对输入张量 `lhs` 和 `rhs` 逐元素进行比较操作，返回一个布尔（或二值）张量。公式如下，其中mode是比较模式，可以是等于、不等于、小于、小于等于、大于、大于等于等多种比较模式。

```
    ```math
            output[i] = 1 if lhs[i] mode rhs[i] is true
                        0 otherwise
```
```

​	**参数：**

| 参数名 | 类型            | 说明                 | 是否必须 | 默认值 |
| ------ | --------------- | -------------------- | -------- | ------ |
| lhs    | AnyTensor       | 左操作数张量         | 是       | 无     |
| rhs    | AnyTensor       | 右操作数张量         | 是       | 无     |
| mode   | CompareModeAttr | 比较模式             | 是       | 无     |
| output | AnyTensor       | 结果张量，元素为0或1 | 是       | 无     |

​	**示例：**

```mlir
%lhs = tensor<[1, 2, 3]> : tensor<3xi32>
%rhs = tensor<[2, 2, 1]> : tensor<3xi32>
%out = "top.compare"(%lhs, %rhs) { mode = "LessThan" } : (tensor<3xi32>, tensor<3xi32>) -> tensor<3xi1>
// 输出: [1, 0, 0]
```

### 	2.102CompareConstOp

​	**功能：**该算子执行输入张量与一个常数值之间的逐元素比较操作。根据指定的比较模式（如等于、不等于、小于等），对输入张量的每个元素与常数进行比较，结果是一个元素为0或1的张量，表示每个比较结果的真假。同时支持反转结果（掩码反转）和标量/张量两种模式。

​	**参数：**

| 参数名    | 类型                 | 说明                                                         |
| --------- | -------------------- | ------------------------------------------------------------ |
| input     | AnyTensor            | 输入张量，待比较的张量                                       |
| mode      | CompareModeAttr      | 比较模式，支持等于、非等于、小于、小于等于、大于、大于等于等 |
| const_val | F64Attr              | 用于比较的常数值                                             |
| inversed  | BoolAttr             | 是否反转比较结果（掩码反转）                                 |
| is_scalar | BoolAttr (默认false) | 是否以标量方式处理（与张量不同）                             |
| output    | AnyTensor            | 逐元素比较结果的张量，元素值为0或1                           |

​	**示例：**

```
# 示例1：判断输入是否大于3，未反转
input = [2, 3, 4, 5]
const_val = 3
mode = GreaterThan
inversed = False
output = [0, 0, 1, 1]

# 示例2：判断输入是否等于2，反转掩码
input = [2, 3, 2, 4]
const_val = 2
mode = Equal
inversed = True
output = [0, 1, 0, 1]  # 因为反转，等于2位置为0，不等于2位置为1
```

### 	2.103ErfOp

​	**功能：**对输入张量的每个元素应用误差函数计算，输出同形状张量。该函数能将输入的实数值映射到[-1,1]区间内，反映累计正态分布的概率值。

​	**参数：**

| 参数名 | 类型      | 说明             |
| ------ | --------- | ---------------- |
| input  | AnyTensor | 输入张量         |
| output | AnyTensor | 误差函数计算结果 |

### 	2.104HardSigmoidOp

​	**功能：**对输入张量的每个元素执行计算：先乘以系数 `alpha`，加上偏置 `beta`，然后取最大值0和最小值1，限制输出在0~1区间内。公式为 output[i] = min(max(alpha * input[i] + beta, 0), 1)

​	**参数：**

| 参数名 | 类型      | 说明               |
| ------ | --------- | ------------------ |
| input  | AnyTensor | 输入张量           |
| alpha  | F64Attr   | 线性函数的斜率系数 |
| beta   | F64Attr   | 线性函数的偏置     |
| output | AnyTensor | 激活后的输出张量   |

### 	2.105HardSwishOp

​	**功能：**该算子实现 HardSwish 激活函数，是 Swish 激活函数的高效近似。对输入张量的每个元素执行计算：输入值乘以 HardSigmoid，实现非线性激活。该函数常用于轻量级神经网络。公式为output[i] = input[i] * min(max(1/6 * input[i] + 0.5, 0), 1)

​	**参数：**

| 参数名 | 类型      | 说明             |
| ------ | --------- | ---------------- |
| input  | AnyTensor | 输入张量         |
| output | AnyTensor | 激活后的输出张量 |

### 	2.106SwishOp

​	**功能：**该算子实现 Swish 激活函数，定义为输入乘以其经过 Sigmoid 激活函数缩放后的值。Swish 是一种自门控激活函数，性能优于ReLU等传统激活。公式为output[i] = input[i] * sigmoid(input[i] * beta)

​	**参数：**

| 参数名     | 类型                                  | 说明                        |
| ---------- | ------------------------------------- | --------------------------- |
| input      | AnyTensor                             | 输入张量                    |
| beta       | F64Attr                               | 控制 Sigmoid 输入的缩放因子 |
| round_mode | RoundModeAttr（默认HalfAwayFromZero） | 精度转换时的舍入模式        |
| output     | AnyTensor                             | 激活后的输出张量            |

### 	2.107PriorBoxOp

​	**功能：**该算子用于多框检测（MultiBox）方法中，生成先验框（Prior Boxes），即在特征图每个位置生成多个固定尺寸和长宽比的锚框，用于目标检测任务。先验框作为候选框，用于后续与真实框的匹配和回归。

​	**参数：**

| 参数名                   | 类型                | 说明                       |
| ------------------------ | ------------------- | -------------------------- |
| inputs                   | Variadic            | 输入张量（特征图等）       |
| min_size                 | F64ArrayAttr        | 先验框的最小尺寸列表       |
| max_size                 | F64ArrayAttr        | 先验框的最大尺寸列表       |
| aspect_ratios            | F64ArrayAttr        | 先验框的长宽比列表         |
| variance                 | F64ArrayAttr        | 训练时用于调整预测框的方差 |
| clip                     | BoolAttr (默认true) | 是否将先验框裁剪到图像边界 |
| step_h                   | F64Attr             | 纵向步长                   |
| step_w                   | F64Attr             | 横向步长                   |
| img_h                    | I64Attr             | 输入图像高度               |
| img_w                    | I64Attr             | 输入图像宽度               |
| offset                   | F64Attr (默认0.5)   | 先验框相对位置的偏移       |
| num_priors               | I64Attr             | 每个位置生成的先验框数量   |
| use_default_aspect_ratio | BoolAttr (默认true) | 是否使用默认长宽比1.0      |

### 	2.108DetectionOutputOp

​	**功能：**该算子接收预测的边界框、类别置信度等信息，经过置信度阈值筛选和非极大值抑制（NMS），最终输出检测结果。适用于目标检测后处理步骤。

​	**参数：**

| 参数名                     | 类型                        | 说明                                     |
| -------------------------- | --------------------------- | ---------------------------------------- |
| inputs                     | Variadic                    | 输入张量，通常包含边界框预测和类别置信度 |
| num_classes                | I64Attr                     | 类别总数（包含背景类别）                 |
| background_label_id        | I64Attr (默认0)             | 背景类别的ID                             |
| nms_threshold              | F64Attr                     | 非极大值抑制阈值                         |
| top_k                      | I64Attr                     | 最大考虑检测数量                         |
| code_type                  | DetectionOutputCodeTypeAttr | 边界框编码类型                           |
| keep_top_k                 | I64Attr                     | NMS后保留的最大检测数                    |
| confidence_threshold       | F64Attr                     | 置信度阈值                               |
| share_location             | BoolAttr (默认true)         | 是否不同类别共享边界框位置               |
| variance_encoded_in_target | F64Attr (默认0)             | 是否编码了方差                           |
| eta                        | F64Attr (默认1)             | NMS置信度调整参数                        |

### 	2.109YoloDetectionOp

​	**功能：**该算子在特征图上执行YOLO检测。将预测的边界框、类别分数和目标置信度通过阈值过滤和非极大值抑制得到最终检测结果。

​	**参数：**

| 参数名        | 类型                 | 说明                         |
| ------------- | -------------------- | ---------------------------- |
| inputs        | Variadic             | 输入张量，包含YOLO特征图预测 |
| net_input_h   | I64Attr              | 输入图片高度                 |
| net_input_w   | I64Attr              | 输入图片宽度                 |
| nms_threshold | F64Attr              | 非极大值抑制阈值             |
| obj_threshold | F64Attr              | 目标置信度阈值               |
| keep_topk     | I64Attr              | 保留检测的最大数量           |
| anchors       | F64ArrayAttr         | 锚框尺寸列表                 |
| version       | YoloVersionAttr      | YOLO模型版本                 |
| class_num     | I64Attr (默认80)     | 类别数量                     |
| num_boxes     | I64Attr (默认3)      | 每个网格预测的框数量         |
| agnostic_nms  | BoolAttr (默认false) | 是否类别无关的NMS            |

### 	2.110QuantizeLinearOp

​	**功能：**该算子对输入张量进行线性量化，将实数转换为量化整数值，通过缩放和偏置实现。常用于模型量化以减少模型大小和提高推理效率。

​	**参数：**

| 参数名       | 类型            | 说明               |
| ------------ | --------------- | ------------------ |
| input        | AnyTensor       | 输入张量           |
| y_scale      | F64ArrayAttr    | 每个通道的缩放比例 |
| y_zero_point | I32ArrayAttr    | 每个通道的零点偏置 |
| axis         | I64Attr (默认1) | 缩放和零点所在的轴 |

### 	2.111LayerNormOp

​	**功能：**实现层归一化（Layer Normalization），对输入张量指定维度的数据进行均值方差归一化，再进行缩放和平移。广泛用于深度学习模型的正则化和加速收敛。

​	**参数：**

| 参数名           | 类型            | 说明             |
| ---------------- | --------------- | ---------------- |
| input            | AnyTensor       | 输入张量         |
| weight           | AnyTensorOrNone | 缩放权重张量     |
| bias             | AnyTensorOrNone | 偏置张量         |
| normalized_shape | I64ArrayAttr    | 归一化维度的形状 |
| axis             | SI32Attr        | 归一化维度索引   |
| eps              | F64Attr         | 防止除零的小常数 |

### 	2.112IndexPutOp 

​	**功能：**更新输入张量中指定索引位置的元素为新值。根据 `accumulate` 标志，可以选择直接替换还是累加更新。

​	**参数：**

| 参数名     | 类型                 | 说明               |
| ---------- | -------------------- | ------------------ |
| input      | AnyTensor            | 输入张量           |
| indices    | AnyTensor            | 需要更新的元素索引 |
| values     | AnyTensor            | 更新的新值         |
| accumulate | BoolAttr (默认false) | 是否累加更新       |

### 	2.113InstanceNormOp

​	**功能：**对输入张量的每个样本和通道，计算均值和方差后归一化，并通过可学习的 `weight` 和 `bias` 缩放平移。

​	**参数：**

| 参数名 | 类型            | 说明             |
| ------ | --------------- | ---------------- |
| input  | AnyTensor       | 输入张量         |
| weight | AnyTensorOrNone | 缩放权重         |
| bias   | AnyTensorOrNone | 偏置             |
| eps    | F64Attr         | 防止除零的小常数 |

### 	2.114GroupNormOp

​	**功能：**分组归一化，将通道划分成多个组，在组内进行归一化，适合小批量训练。计算每组内的均值和方差，对组内元素归一化，通过 `weight` 和 `bias` 缩放平移。

​	**参数：**

| 参数名     | 类型            | 说明           |
| ---------- | --------------- | -------------- |
| input      | AnyTensor       | 输入张量       |
| weight     | AnyTensorOrNone | 缩放权重       |
| bias       | AnyTensorOrNone | 偏置           |
| num_groups | I64Attr         | 分组数         |
| eps        | F64Attr         | 防止除零小常数 |

### 	2.115PixelNormOp

​	**功能：**沿通道维度对像素进行归一化，常用于生成模型的特征规范化。对每个像素位置计算所有通道的平方和平均后开根号（加上 `eps` 防止除零）。使用 `weight` 和 `bias` 缩放平移输入值。

​	**参数：**

| 参数名 | 类型            | 说明           |
| ------ | --------------- | -------------- |
| input  | AnyTensor       | 输入张量       |
| weight | AnyTensorOrNone | 缩放权重       |
| bias   | AnyTensorOrNone | 偏置           |
| eps    | F64Attr         | 防止除零小常数 |

### 	2.116ProposalOp

​	**功能：**生成候选边界框（proposal），主要用于目标检测RPN阶段，通过anchor回归和置信度筛选，得到候选框。

​	**参数：**

| 参数名             | 类型     | 说明              |
| ------------------ | -------- | ----------------- |
| inputs             | Variadic | 输入张量          |
| net_input_h        | I64Attr  | 网络输入高度      |
| net_input_w        | I64Attr  | 网络输入宽度      |
| feat_stride        | I64Attr  | 特征图步长        |
| anchor_base_size   | I64Attr  | anchor基准大小    |
| rpn_obj_threshold  | F64Attr  | 目标置信度阈值    |
| rpn_nms_threshold  | F64Attr  | NMS阈值           |
| rpn_nms_post_top_n | I64Attr  | NMS后保留候选框数 |

### 	2.117ROIPoolingOp

​	**功能：**对输入张量中指定ROI区域执行最大池化操作，输出固定大小的特征图。

​	**参数：**

| 参数名        | 类型      | 输入/输出 | 说明             |
| ------------- | --------- | --------- | ---------------- |
| inputs        | Variadic  | 输入      | 输入张量集合     |
| pooled_h      | I64Attr   | 属性      | 池化输出的高度   |
| pooled_w      | I64Attr   | 属性      | 池化输出的宽度   |
| spatial_scale | F64Attr   | 属性      | ROI坐标缩放比例  |
| output        | AnyTensor | 输出      | 池化后的输出张量 |

### 	2.118DequantizeLinearOp

​	**功能：**对量化的输入张量执行线性反量化，将其恢复到浮点表示。

​	**参数：**

| 参数名       | 类型         | 输入/输出 | 说明               |
| ------------ | ------------ | --------- | ------------------ |
| input        | AnyTensor    | 输入      | 量化输入张量       |
| x_scale      | F64ArrayAttr | 属性      | 缩放系数数组       |
| x_zero_point | I32ArrayAttr | 属性      | 零点数组           |
| axis         | I64Attr      | 属性      | 操作维度           |
| output       | AnyTensor    | 输出      | 反量化后的输出张量 |

### 	2.119FrcnDetectionOp

​	**功能：**输出检测到的类别及其对应的边界框，并根据指定阈值过滤结果。

​	**参数：**

| 参数名        | 类型     | 说明             |
| ------------- | -------- | ---------------- |
| inputs        | Variadic | 输入张量         |
| class_num     | I64Attr  | 检测类别数量     |
| obj_threshold | F64Attr  | 目标置信度阈值   |
| nms_threshold | F64Attr  | 非极大值抑制阈值 |
| keep_topk     | I64Attr  | 保留的top-k数量  |

### 	2.120CopyOp

​	**功能：**将输入张量复制到指定形状和步长的输出张量。

​	**参数：**

| 参数名        | 类型         | 说明         |
| ------------- | ------------ | ------------ |
| input         | AnyTensor    | 输入张量     |
| shape         | I64ArrayAttr | 输出张量形状 |
| input_stride  | I64ArrayAttr | 输入张量步长 |
| output_stride | I64ArrayAttr | 输出张量步长 |

### 	2.121CscOp

​	**功能：**对模型输入执行颜色空间转换操作。

​	**参数：**

| 参数名        | 类型      | 说明                 |
| ------------- | --------- | -------------------- |
| input         | AnyTensor | 输入张量             |
| pixel_format  | StrAttr   | 像素格式类型（必需） |
| aligned       | BoolAttr  | 是否对齐             |
| y_align       | I64Attr   | Y通道宽度对齐        |
| w_align       | I64Attr   | UV通道宽度对齐       |
| channel_align | I64Attr   | 通道对齐             |

### 	2.122LutOp

​	**功能：**根据查找表（索引范围0-255）对输入元素进行映射。

​	**参数：**

| 参数名 | 类型      | 说明       |
| ------ | --------- | ---------- |
| input  | AnyTensor | 输入张量   |
| table  | AnyTensor | 查找表张量 |

### 	2.123ScaleLutOp

​	**功能：**对输入张量执行缩放操作，计算公式为 y = input * scale + bias。

​	**参数：**

| 参数名 | 类型         | 说明             |
| ------ | ------------ | ---------------- |
| input  | AnyTensor    | 输入张量         |
| scale  | F64ArrayAttr | 每通道缩放比例   |
| bias   | F64ArrayAttr | 每通道偏置       |
| sign   | BoolAttr     | 输出是否为有符号 |

### 	2.124SwapChannelOp

​	**功能：**交换输入张量的通道，通常用于RGB与BGR的互换。

​	**参数：**

| 参数名        | 类型         | 说明               |
| ------------- | ------------ | ------------------ |
| input         | AnyTensor    | 输入张量           |
| channel_order | I64ArrayAttr | 通道交换的顺序数组 |

### 	2.125SwapDimInnerOp

​	**功能：**根据指定的偏移量拆分维度，并交换拆分的前后两部分。

​	**参数：**

| 参数名 | 类型         | 说明         |
| ------ | ------------ | ------------ |
| input  | AnyTensor    | 输入张量     |
| offset | I64ArrayAttr | 拆分位置数组 |

### 	2.126ScatterElementsOp

​	**功能：**ScatterElements 操作接受三个输入：data、updates 和 indices，这些输入具有相同的秩 r >= 1，以及一个可选属性 axis，用于标识 data 的一个轴（默认是最外层轴，即 axis 0）。该操作的输出是通过创建输入 data 的副本，然后在由 indices 指定的特定索引位置处更新其值为 updates 指定的值来生成的。其输出形状与 data 的形状相同。

​	**参数：**

| 参数名       | 类型      | 说明               |
| ------------ | --------- | ------------------ |
| input        | AnyTensor | 输入张量           |
| indices      | AnyTensor | 更新位置索引张量   |
| updates      | AnyTensor | 更新值张量         |
| axis         | I64Attr   | 更新的轴，默认0    |
| reduction    | I64Attr   | 规约方式（可选）   |
| nc_can_split | BoolAttr  | 是否可拆分（可选） |

### 	2.127ScatterNDOp

​	**功能：**ScatterND 操作通过创建输入数据（input_data）的副本，然后在由 indices 指定的特定索引位置更新为 updates 指定的值来生成输出。

​	**参数：**

| 参数名称   | 类型      | 是否必需 | 默认值 | 描述                                                         |
| ---------- | --------- | -------- | ------ | ------------------------------------------------------------ |
| input_data | AnyTensor | 是       | 无     | 输入张量（data），要被更新的源数据。                         |
| indices    | AnyTensor | 是       | 无     | 索引张量，秩 q >= 1，指定更新位置的坐标。最后一维表示坐标维度。 |
| updates    | AnyTensor | 是       | 无     | 更新值张量，秩为 q + r - indices_shape[-1] - 1，提供要散布的值。 |
| reduction  | I32Attr   | 否       | 0      | 减少模式：0（无，默认替换）、1（加法）、2（减法）、3（最大值）、4（最小值）、5（乘法）。 |
| output     | AnyTensor | -        | -      | 输出张量，形状与 input_data 相同。                           |

### 	2.128RoiAlignOp

​	**功能：**Top_RoiAlignOp 是一种用于目标检测（如 Faster R-CNN）的区域池化操作。它从输入特征图（4 维张量，形状 [batch, height, width, channels]）中，根据给定的 RoIs（感兴趣区域，格式为 [x1, y1, x2, y2]）提取固定大小的特征图。每个 RoI 被缩放到输入特征图的尺度（通过 spatial_scale），然后划分为 output_height × output_width 的网格，在每个网格内使用双线性插值（通过 sampling_ratio 控制采样点）计算特征值。align_corners 决定是否对齐角点，mode 可能用于特定实现（但描述中未明确其在池化中的作用）。输出张量的形状为 [num_rois, output_height, output_width, channels]。

​	**参数：**

| 参数名称       | 类型             | 是否必需 | 默认值 | 描述                                                         |
| -------------- | ---------------- | -------- | ------ | ------------------------------------------------------------ |
| input          | AnyTensor        | 是       | 无     | 输入张量（4 维，[batch, height, width, channels]）。         |
| rois           | AnyTensor        | 是       | 无     | 感兴趣区域，形状 [num_rois, 4]，格式为 [[x1, y1, x2, y2], ...]。 |
| mode           | RoiAlignModeAttr | 是       | 无     | 比较类型（等于、不等于、小于等，具体作用需参考实现）。       |
| output_height  | I64Attr          | 是       | 无     | 输出特征图的高度。                                           |
| output_width   | I64Attr          | 是       | 无     | 输出特征图的宽度。                                           |
| sampling_ratio | I64Attr          | 是       | 无     | 每个网格在高度和宽度方向的采样点数。                         |
| spatial_scale  | F64Attr          | 是       | 无     | 将 RoI 坐标映射到输入特征图尺度的缩放因子。                  |
| align_corners  | BoolAttr         | 是       | 无     | 是否对齐输入和输出的角点。                                   |
| output         | AnyTensor        | -        | -      | 输出张量，形状 [num_rois, output_height, output_width, channels]。 |

### 	2.129RoiExtractorOp

​	**功能：**Top_RoiExtractorOp 是一个用于目标检测（如特征金字塔网络 FPN）的区域池化操作，类似于 RoiAlign，但支持多层特征图（feature pyramid）。它从多个输入特征图（inputs，通常是不同尺度的特征图）中，根据 rois 和 target_lvls 提取固定大小的特征图。target_lvls 指定每个 RoI 对应的特征图层级。每个 RoI 经过缩放（spatial_scale）、网格划分（output_height × output_width），并通过双线性插值（sampling_ratio）计算特征值。align_corners 控制角点对齐，mode 可能用于特定实现（未明确）。输出形状为 [num_rois, output_height, output_width, channels]。

​	**参数：**

| 参数名称       | 类型                            | 是否必需 | 默认值 | 描述                                                         |
| -------------- | ------------------------------- | -------- | ------ | ------------------------------------------------------------ |
| inputs         | Variadic<anytensor></anytensor> | 是       | 无     | 输入张量（多个 4 维特征图，[batch, height, width, channels]）。 |
| rois           | AnyTensor                       | 是       | 无     | 感兴趣区域，形状 [num_rois, 4]，格式 [[x1, y1, x2, y2], ...]。 |
| target_lvls    | AnyTensor                       | 是       | 无     | 一维张量，形状 [num_rois]，指定每个 RoI 对应的特征图层级索引。 |
| mode           | RoiAlignModeAttr                | 是       | 无     | 比较类型（等于、不等于等，具体作用视实现）。                 |
| num_levels     | I64Attr                         | 是       | 无     | 特征金字塔的层数。                                           |
| output_height  | I64Attr                         | 是       | 无     | 输出特征图的高度。                                           |
| output_width   | I64Attr                         | 是       | 无     | 输出特征图的宽度。                                           |
| sampling_ratio | I64Attr                         | 是       | 无     | 每个网格在高度和宽度方向的采样点数。                         |
| spatial_scales | F64ArrayAttr                    | 是       | 无     | 每个特征图层级的缩放因子数组。                               |
| align_corners  | BoolAttr                        | 是       | 无     | 是否对齐输入和输出的角点。                                   |
| is_static      | BoolAttr                        | 是       | 无     | 操作是否具有静态形状。                                       |
| output         | AnyTensor                       | -        | -      | 输出张量，形状 [num_rois, output_height, output_width, channels]。 |

### 	2.130PreprocessOp

​	**功能：**Top_PreprocessOp 是一个图像预处理操作，将输入张量（通常是图像数据）进行一系列转换，包括通道重排（channel_order，如 RGB 到 BGR）、切片（resize_dims 调整大小）、缩放（scale 乘以缩放因子）和减去均值（mean 归一化）。它常用于神经网络输入预处理，整合多个步骤为一个操作。quant_mode 和 customization_format 可能用于特定量化或数据格式，sign 控制输出是否为有符号类型。

​	**参数：**

| 参数名称             | 类型         | 是否必需 | 默认值 | 描述                                             |
| -------------------- | ------------ | -------- | ------ | ------------------------------------------------ |
| input                | AnyTensor    | 是       | 无     | 输入张量（通常为图像数据）。                     |
| quant_mode           | StrAttr      | 是       | 无     | 量化模式（如 int8、fp32）。                      |
| customization_format | StrAttr      | 是       | 无     | 输入数据的自定义格式（如 RGB、YUV）。            |
| channel_order        | StrAttr      | 是       | 无     | 颜色通道顺序（如 RGB、BGR）。                    |
| resize_dims          | I64ArrayAttr | 是       | 无     | 调整后的张量维度（如 [height, width]）。         |
| scale                | F64ArrayAttr | 是       | 无     | 每个通道的缩放因子。                             |
| mean                 | F64ArrayAttr | 是       | 无     | 每个通道的均值，用于归一化。                     |
| sign                 | BoolAttr     | 否       | true   | 输出是否为有符号类型。                           |
| output               | AnyTensor    | -        | -      | 输出张量，经过重排、切片、缩放和减均值后的结果。 |

### 	2.131MeanStdScaleOp

​	**功能：**Top_MeanStdScaleOp 是图像预处理操作，针对输入张量（通常是图像）进行归一化（减均值，除以标准差）、缩放（乘以 scale）、添加零点偏移（zero_points），并支持调整大小（resize_dims）和通道重排（channel_order）。它常用于神经网络输入的标准化和量化（如 int8 量化）。quant_mode 和 rounding_mode 控制量化细节，sign 决定输出数据类型。

​	**参数：**

| 参数名称             | 类型         | 是否必需 | 默认值 | 描述                                       |
| -------------------- | ------------ | -------- | ------ | ------------------------------------------ |
| input                | AnyTensor    | 是       | 无     | 输入张量（通常为图像数据）。               |
| quant_mode           | StrAttr      | 是       | 无     | 量化模式（如 int8、fp32）。                |
| customization_format | StrAttr      | 是       | 无     | 输入数据的自定义格式（如 RGB、YUV）。      |
| channel_order        | StrAttr      | 是       | 无     | 颜色通道顺序（如 RGB、BGR）。              |
| sign                 | BoolAttr     | 否       | true   | 输出是否为有符号类型。                     |
| scale                | F64ArrayAttr | 是       | 无     | 每个通道的缩放因子。                       |
| std                  | F64ArrayAttr | 是       | 无     | 每个通道的标准差。                         |
| mean                 | F64ArrayAttr | 是       | 无     | 每个通道的均值，用于归一化。               |
| zero_points          | F64ArrayAttr | 是       | 无     | 每个通道的零点偏移。                       |
| resize_dims          | I64ArrayAttr | 是       | 无     | 调整后的张量维度（如 [height, width]）。   |
| rounding_mode        | StrAttr      | 是       | 无     | 量化时的舍入方式（如 round、floor）。      |
| output               | AnyTensor    | -        | -      | 输出张量，经过归一化、缩放、偏移后的结果。 |

### 	2.132DepackRawOp

​	**功能：**DepackRaw 用于原始图像的后处理，先移除填充（如果之前有填充），然后将每个通道解包为 2x2 图像块。

​	**参数：**

| 参数名称      | 类型         | 是否必需 | 默认值 | 描述                                   |
| ------------- | ------------ | -------- | ------ | -------------------------------------- |
| input         | AnyTensor    | 是       | 无     | 输入张量（通常为原始图像数据）。       |
| padding_h     | I64Attr      | 是       | 无     | 填充的高度。                           |
| padding_w     | I64Attr      | 是       | 无     | 填充的宽度。                           |
| white_level   | F64Attr      | 是       | 无     | 图像的最大白值（用于归一化）。         |
| black_level   | F64Attr      | 是       | 无     | 图像的最小黑值（用于归一化）。         |
| channel_order | I64ArrayAttr | 是       | 无     | 颜色通道顺序（如 RGGB）。              |
| output        | AnyTensor    | -        | -      | 输出张量，经过移除填充和解包后的结果。 |

### 	2.133Mmap2RgbmapOp

​	**功能：**Top_Mmap2RgbmapOp 是一个图像信号处理（ISP）操作，用于将输入张量（可能是内存映射的原始数据）转换为 RGB 格式的图像映射。描述较简略，可能是占位符或特定于硬件的转换操作，具体功能依赖实现，可能涉及颜色空间转换或格式调整。

​	**参数：**

| 参数名称 | 类型      | 是否必需 | 默认值 | 描述                                  |
| -------- | --------- | -------- | ------ | ------------------------------------- |
| input    | AnyTensor | 是       | 无     | 输入张量（可能是原始图像数据）。      |
| output   | AnyTensor | -        | -      | 输出张量，转换为 RGB 格式的图像映射。 |

### 	2.134RetinaFaceDetectionOp

​	**功能：**Top_RetinaFaceDetectionOp 是用于 RetinaFace 目标检测的后处理操作。它接收多个输入特征图（inputs），执行检测（生成边界框和置信度），过滤低于 confidence_threshold 的框，然后应用非极大值抑制（NMS，nms_threshold）去除重叠框，最后保留最多 keep_topk 个框。输出是检测到的边界框和分数。

​	**参数：**

| 参数名称             | 类型                            | 是否必需 | 默认值 | 描述                                         |
| -------------------- | ------------------------------- | -------- | ------ | -------------------------------------------- |
| inputs               | Variadic<anytensor></anytensor> | 是       | 无     | 输入张量（多个特征图，包含边界框和置信度）。 |
| nms_threshold        | F64Attr                         | 是       | 无     | NMS 阈值，用于去除重叠边界框。               |
| confidence_threshold | F64Attr                         | 是       | 无     | 分类置信度阈值，过滤低置信度框。             |
| keep_topk            | I64Attr                         | 是       | 无     | NMS 后保留的最大边界框数量。                 |
| output               | AnyTensor                       | -        | -      | 输出张量，包含最终的边界框和分数。           |

### 	2.135EluOp

​	**功能：**Top_EluOp 是指数线性单元（Exponential Linear Unit）激活函数的操作，按元素应用于输入张量。对于正值，直接返回原值；对于负值或零，返回 alpha 乘以 (e^x - 1)。它常用于神经网络中作为激活函数，帮助缓解梯度消失问题，并允许负值以保持均值接近零。输出形状与输入相同。

​	**参数：**

| 参数名称 | 类型      | 是否必需 | 默认值 | 描述                             |
| -------- | --------- | -------- | ------ | -------------------------------- |
| input    | AnyTensor | 是       | 无     | 输入张量，要应用 Elu 的数据。    |
| alpha    | F64Attr   | 是       | 无     | 负值区域的缩放因子，通常为 1.0。 |
| output   | AnyTensor | -        | -      | 输出张量，形状与 input 相同。    |

### 	2.136YieldOp

​	**功能：**Top_YieldOp 是一个终止操作，用于在子图（如 IfOp 或 LoopOp 的分支）中返回多个值（operands）。它不产生新结果，而是将 operands 作为子图的输出传递回父操作。常用于控制流操作中，确保子图正确返回值。该操作是 TPU-MLIR 特定的辅助工具，帮助管理子图的输出。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                               |
| -------- | ------------------------------- | -------- | ------ | ---------------------------------- |
| operands | Variadic<anytensor></anytensor> | 是       | 无     | 要返回的操作数（可变数量的张量）。 |

### 	2.137IfOp

​	**功能：**Top_IfOp 是一个条件分支操作，根据条件张量 cond（布尔值或张量）选择执行 then_branch 或 else_branch 子图。每个分支是一个区域（region），可以包含多个操作，并通过 Yield 返回值。输出是所选分支的 Yield 值，形状和数量由分支决定。该操作常用于动态控制流，如根据条件选择不同计算路径。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                                    |
| -------- | ------------------------------- | -------- | ------ | --------------------------------------- |
| cond     | AnyTensor                       | 是       | 无     | 条件张量（布尔类型，决定分支）。        |
| output   | Variadic<anytensor></anytensor> | -        | -      | 输出张量，可变数量，由分支 Yield 决定。 |

### 	2.138LoopOp

​	**功能：**Top_LoopOp 是一个通用循环操作，支持 while、for、do-while 等模式。通过 M 指定最大迭代次数（可选），cond 指定终止条件（可选），v_initial 提供初始循环变量。body 子图接收迭代号、条件和循环变量，计算新条件、新变量和扫描输出。输出包括最终循环变量和所有迭代的扫描输出连接（scan_outputs）。常用于 RNN 或迭代计算，支持动态循环。

​	**参数：**

| 参数名称                 | 类型                                       | 是否必需 | 默认值 | 描述                                   |
| ------------------------ | ------------------------------------------ | -------- | ------ | -------------------------------------- |
| M                        | AnyTypeOf<[AnyTensor, NoneType]>           | 否       | 无     | 最大行程计数（可选，tensor 或 none）。 |
| cond                     | AnyTypeOf<[AnyTensor, NoneType]>           | 否       | 无     | 初始条件（可选，tensor 或 none）。     |
| v_initial                | Variadic<AnyTypeOf<[AnyTensor, NoneType]>> | 是       | 无     | 初始循环携带变量（可变数量）。         |
| v_final_and_scan_outputs | Variadic<AnyTypeOf<[AnyTensor, NoneType]>> | -        | -      | 输出：最终变量 + 扫描输出。            |

### 	2.139ShapeOp

​	**功能：**Top_ShapeOp 返回输入张量的形状作为一维整数张量（例如，输入形状 [3,4,5] 输出 [3,4,5]）。支持可选切片参数（start, end, step）来提取形状的子集。常用于元数据操作，如动态形状处理或调试。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                             |
| -------- | ------------------------------- | -------- | ------ | -------------------------------- |
| input    | AnyTensor                       | 是       | 无     | 输入张量，要获取形状的数据。     |
| start    | OptionalAttr<i64attr></i64attr> | 否       | 无     | 形状切片的起始索引。             |
| end      | OptionalAttr<i64attr></i64attr> | 否       | 无     | 形状切片的结束索引。             |
| step     | OptionalAttr<i64attr></i64attr> | 否       | 无     | 形状切片的步长。                 |
| output   | AnyTensor                       | -        | -      | 输出张量，一维整数张量表示形状。 |

​	**示例：**

```
%output = "top.Shape"(%input) {start = 1 : i64, end = 3 : i64, step = 1 : i64} : (tensor<3x4x5x6xf32>) -> tensor<2xi64>  
```

### 	2.140GatherNDOp

​	**功能：**Top_GatherNDOp 从输入张量 input 中根据 indices 指定的多维索引位置收集值，生成输出张量。它是 ScatterND 的逆操作，indices 的最后一维定义输入张量的坐标，输出形状由 indices 的形状（除最后一维）和 input 的剩余维度决定。batch_dims 指定批次维度，允许对批次数据进行统一操作。常用于提取特定位置的张量值，如在神经网络中选择特定特征。

​	**参数：**

| 参数名称    | 类型                            | 是否必需 | 默认值 | 描述                                             |
| ----------- | ------------------------------- | -------- | ------ | ------------------------------------------------ |
| input       | AnyTensor                       | 是       | 无     | 输入张量，要从中收集数据的源张量。               |
| indices     | AnyTensor                       | 是       | 无     | 索引张量，指定收集的元素位置。最后一维表示坐标。 |
| indice_dims | OptionalAttr<i64attr></i64attr> | 否       | 无     | 索引张量的维度数。                               |
| batch_dims  | I64Attr                         | 否       | 0      | 输入张量的批次维度数。                           |
| output      | AnyTensor                       | -        | -      | 输出张量，形状由 indices 和 input 决定。         |

### 	2.141DeformConv2DOp

​	**功能：**Top_DeformConv2DOp 是可变形卷积操作，允许卷积核根据 offset 动态调整采样位置，mask 控制采样权重。相比标准卷积，它更灵活，能适应几何变化（如目标检测中的非规则形状）。输入经过卷积（filter, bias），输出形状由公式计算，group 和 deform_group 支持分组卷积，do_relu 可应用 ReLU 激活。

​	**参数：**

| 参数名称     | 类型                                      | 是否必需 | 默认值 | 描述                                                         |
| ------------ | ----------------------------------------- | -------- | ------ | ------------------------------------------------------------ |
| input        | AnyTensor                                 | 是       | 无     | 输入张量，形状 [N, C_in, H_in, W_in]。                       |
| filter       | AnyTensor                                 | 是       | 无     | 卷积核权重，形状 [out_channels, in_channels/groups, kernel_size[0], kernel_size[1]]。 |
| offset       | AnyTensor                                 | 是       | 无     | 可学习偏移，形状 [N, 2×offset_groups×kernel_size[0]×kernel_size[1], H_out, W_out]。 |
| mask         | AnyTensorOrNone                           | 否       | 无     | 可学习掩码，形状 [N, offset_groups×kernel_size[0]×kernel_size[1], H_out, W_out]。 |
| bias         | AnyTensorOrNone                           | 否       | 无     | 可学习偏置，形状 [out_channels]。                            |
| kernel_shape | I64ArrayAttr                              | 是       | 无     | 卷积核大小，如 [3,3]。                                       |
| strides      | I64ArrayAttr                              | 是       | 无     | 步幅，如 [1,1]。                                             |
| pads         | I64ArrayAttr                              | 是       | 无     | 填充，[top, left, bottom, right]。                           |
| group        | I64Attr                                   | 否       | 1      | 分组卷积的组数。                                             |
| deform_group | I64Attr                                   | 否       | 1      | 可变形卷积的组数。                                           |
| use_mask     | BoolAttr                                  | 否       | false  | 是否使用掩码。                                               |
| dilations    | OptionalAttr<i64arrayattr></i64arrayattr> | 否       | 无     | 膨胀率，如 [1,1]。                                           |
| do_relu      | BoolAttr                                  | 否       | false  | 是否应用 ReLU 激活。                                         |
| relu_limit   | F64Attr                                   | 否       | -1.0   | ReLU 上限，-1.0 表示无上限。                                 |
| output       | AnyTensor                                 | -        | -      | 输出张量，形状 [N, C_out, H_out, W_out]。                    |

### 	2.142CustomOp

​	**功能：**Top_CustomOp 是一个通用操作，允许用户定义自定义计算逻辑，通过 name 指定操作类型，params 提供参数。输入和输出张量数量可变，具体行为由实现决定。常用于扩展 TPU-MLIR，支持特定硬件或自定义算法。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                     |
| -------- | ------------------------------- | -------- | ------ | ------------------------ |
| inputs   | Variadic<anytensor></anytensor> | 是       | 无     | 输入张量，可变数量。     |
| name     | StrAttr                         | 是       | 无     | 自定义操作的名称。       |
| params   | DictArrayAttr                   | 是       | 无     | 参数字典，定义操作行为。 |
| outputs  | Variadic<anytensor></anytensor> | -        | -      | 输出张量，可变数量。     |

### 	2.143ScaleDotProductAttentionOp

​	**功能：**Top_ScaleDotProductAttentionOp 实现 Transformer 的缩放点积注意力机制。计算查询（Q）与键（K）的点积，缩放后通过 softmax 得到注意力权重（可选加 mask），再与值（V）相乘得到输出。dropout_p 控制注意力权重的丢弃，is_causal 用于序列模型（如语言模型）确保只关注前序数据，scale 可自定义缩放因子（默认 1/sqrt(d_k)）。常用于 Transformer 模型。

​	**参数：**

| 参数名称  | 类型            | 是否必需 | 默认值 | 描述                                         |
| --------- | --------------- | -------- | ------ | -------------------------------------------- |
| query     | AnyTensor       | 是       | 无     | 查询张量，形状 [batch, seq_len, d_k]。       |
| key       | AnyTensor       | 是       | 无     | 键张量，形状 [batch, seq_len, d_k]。         |
| value     | AnyTensor       | 是       | 无     | 值张量，形状 [batch, seq_len, d_v]。         |
| mask      | AnyTensorOrNone | 否       | 无     | 注意力掩码，形状 [batch, seq_len, seq_len]。 |
| dropout_p | F64Attr         | 否       | 0.0    | 注意力权重的丢弃概率。                       |
| is_causal | BoolAttr        | 否       | false  | 是否为因果注意力（只关注前序）。             |
| scale     | F64Attr         | 否       | 0.0    | 缩放因子，默认 1/sqrt(d_k)。                 |
| output    | AnyTensor       | -        | -      | 输出张量，形状 [batch, seq_len, d_v]。       |

### 	2.144CeilOp

​	**功能：**Top_CeilOp 对输入张量的每个元素应用向上取整（ceiling）操作，返回形状相同的张量。常用于量化、离散化或确保整数输出。

​	**参数：**

| 参数名称 | 类型      | 是否必需 | 默认值 | 描述                                            |
| -------- | --------- | -------- | ------ | ----------------------------------------------- |
| input    | AnyTensor | 是       | 无     | 输入张量，要取整的数据。                        |
| output   | AnyTensor | -        | -      | 输出张量，形状与 input 相同，每个元素向上取整。 |

### 	2.145RMSNormOp

​	**功能：**RMSNorm 操作是层归一化（LayerNorm）的简化版本，仅对张量的最后一个维度进行归一化。Top_RMSNormOp 对输入张量的最后一个维度应用均方根（RMS）归一化。计算最后一个维度的平方均值，加 eps 确保数值稳定性，然后用输入值除以该均方根，并乘以 gamma 进行缩放。这是层归一化的轻量替代方案，常用于 Transformer 模型以稳定训练。输出形状与输入相同。

​	**参数：**

| 参数名称 | 类型            | 是否必需 | 默认值 | 描述                                                     |
| -------- | --------------- | -------- | ------ | -------------------------------------------------------- |
| input    | AnyTensor       | 是       | 无     | 输入张量，需归一化的数据。                               |
| gamma    | AnyTensorOrNone | 否       | 无     | 可学习的缩放因子（通常为最后一个维度大小的张量，可选）。 |
| eps      | F64Attr         | 是       | 无     | 防止除以零的小常数。                                     |
| output   | AnyTensor       | -        | -      | 输出张量，形状与 input 相同。                            |

### 	2.146RemainderOp

​	**功能：**Top_RemainderOp 对两个输入张量逐元素进行除法，计算余数。第一个张量（x）除以第二个张量（y），取商的向下取整（floor），然后计算 x - y * floor_quo。输出形状与输入张量广播后一致，常用于数值处理或周期性计算。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                               |
| -------- | ------------------------------- | -------- | ------ | ---------------------------------- |
| inputs   | Variadic<anytensor></anytensor> | 是       | 无     | 输入张量，至少两个，用于计算余数。 |
| output   | AnyTensor                       | -        | -      | 输出张量，形状与输入广播后一致。   |

### 	2.147CumSumOp

​	**功能：**Top_CumSumOp 沿指定维度（axis）计算输入张量的累积和。每个输出元素是输入从开头到当前位置的和。dim 张量（可选）可动态指定维度，优先级高于 axis 属性。输出形状与输入相同，常用于序列处理或时间序列分析。公式为output[i] = \sum{j=0, i}input[j]

​	**参数：**

| 参数名称 | 类型            | 是否必需 | 默认值 | 描述                                      |
| -------- | --------------- | -------- | ------ | ----------------------------------------- |
| input    | AnyTensor       | 是       | 无     | 输入张量，需计算累积和。                  |
| dim      | AnyTensorOrNone | 否       | 无     | 动态指定计算累积和的维度（优先于 axis）。 |
| axis     | I64Attr         | 是       | 无     | 计算累积和的维度。                        |
| output   | AnyTensor       | -        | -      | 输出张量，形状与 input 相同。             |

### 	2.148RoundOp

​	**功能：**Round 操作对输入张量逐元素四舍五入到最近的整数。对于 0.5 的情况，向最近的偶数整数取整。若输入为整数、+0、-0、NaN 或无穷大，返回原值。输出张量形状和类型与输入相同。

​	**参数：**

| 参数名称 | 类型      | 是否必需 | 默认值 | 描述                                          |
| -------- | --------- | -------- | ------ | --------------------------------------------- |
| input    | AnyTensor | 是       | 无     | 输入张量，需四舍五入的数据。                  |
| output   | AnyTensor | -        | -      | 输出张量，形状与 input 相同，逐元素四舍五入。 |

### 	2.149BatchNormTrainOp

​	**功能：**Top_BatchNormTrainOp 是一种批归一化操作，用于训练阶段。针对 4 维输入（[N, C, H, W]），它按通道计算批次均值和方差，归一化后乘以 gamma 并加 beta。还输出更新后的均值、方差、逆标准差和运行均值/方差，用于推理。do_relu 可应用 ReLU 激活，relu_limit 控制上限。常用于深度网络以减少内部协变量偏移。	**参数：**

| 参数名称     | 类型            | 是否必需 | 默认值 | 描述                          |
| ------------ | --------------- | -------- | ------ | ----------------------------- |
| input        | AnyTensor       | 是       | 无     | 输入张量，形状 [N, C, H, W]。 |
| mean         | AnyTensor       | 是       | 无     | 每个通道的均值，形状 [C]。    |
| var          | AnyTensor       | 是       | 无     | 每个通道的方差，形状 [C]。    |
| gamma        | AnyTensorOrNone | 否       | 无     | 可学习缩放因子，形状 [C]。    |
| beta         | AnyTensorOrNone | 否       | 无     | 可学习偏移因子，形状 [C]。    |
| epsilon      | F64Attr         | 否       | 1e-05  | 防止除以零的小常数。          |
| momentum     | F64Attr         | 否       | 0.1    | 更新运行均值和方差的动量。    |
| do_relu      | BoolAttr        | 否       | false  | 是否应用 ReLU 激活。          |
| relu_limit   | F64Attr         | 否       | -1.0   | ReLU 上限，-1.0 表示无上限。  |
| output       | AnyTensor       | -        | -      | 输出张量，形状 [N, C, H, W]。 |
| mean_out     | AnyTensor       | -        | -      | 更新后的均值，形状 [C]。      |
| saved_invstd | AnyTensor       | -        | -      | 逆标准差，形状 [C]。          |
| running_mean | AnyTensor       | -        | -      | 运行均值，形状 [C]。          |
| running_var  | AnyTensor       | -        | -      | 运行方差，形状 [C]。          |

### 	2.150BatchNormBwdOp

​	**功能：**Top_BatchNormBwdOp 是批归一化的反向传播操作，用于训练阶段。基于输出梯度 grad_out 和输入 input，计算输入梯度 grad_in，以及可选的权重梯度 weight_grad 和偏置梯度 bias_grad。它使用保存的均值 saved_mean 和逆标准差 saved_invstd 来计算梯度传播，支持 epsilon 确保稳定性。常用于深度网络的反向传播，以更新参数。

​	**参数：**

| 参数名称     | 类型            | 是否必需 | 默认值 | 描述                     |
| ------------ | --------------- | -------- | ------ | ------------------------ |
| grad_out     | AnyTensor       | 是       | 无     | 输出梯度张量。           |
| input        | AnyTensor       | 是       | 无     | 输入张量。               |
| weight_opt   | AnyTensorOrNone | 否       | 无     | 最优权重缩放（可选）。   |
| saved_mean   | AnyTensorOrNone | 否       | 无     | 保存的均值（可选）。     |
| saved_invstd | AnyTensorOrNone | 否       | 无     | 保存的逆标准差（可选）。 |
| epsilon      | F64Attr         | 否       | 1e-05  | 防止除以零的小常数。     |
| grad_in      | AnyTensor       | -        | -      | 输入梯度张量。           |
| weight_grad  | AnyTensorOrNone | -        | -      | 权重梯度（可选）。       |
| bias_grad    | AnyTensorOrNone | -        | -      | 偏置梯度（可选）。       |

### 	2.151LayerNormTrainOp

​	**功能：**Top_LayerNormTrainOp 是层归一化的训练操作，对指定维度（从 axis 开始的 normalized_shape）计算均值和方差，进行归一化，然后乘以 weight 加 bias。输出包括归一化结果、计算的均值和方差，用于后续反向传播。常用于 Transformer 等模型以稳定激活值。

​	**参数：**

| 参数名称         | 类型            | 是否必需 | 默认值 | 描述                 |
| ---------------- | --------------- | -------- | ------ | -------------------- |
| input            | AnyTensor       | 是       | 无     | 输入张量。           |
| weight           | AnyTensorOrNone | 否       | 无     | 权重张量（可选）。   |
| bias             | AnyTensorOrNone | 否       | 无     | 偏置张量（可选）。   |
| normalized_shape | I64ArrayAttr    | 是       | 无     | 需归一化的形状。     |
| axis             | SI32Attr        | 是       | 无     | 开始归一化的维度。   |
| eps              | F64Attr         | 是       | 无     | 防止除以零的小常数。 |
| output           | AnyTensor       | -        | -      | 归一化输出张量。     |
| mean             | AnyTensor       | -        | -      | 计算的均值。         |
| variance         | AnyTensor       | -        | -      | 计算的方差。         |

### 	2.152LayerNormBwdOp

​	**功能：**Top_LayerNormBwdOp 是层归一化的反向传播操作。基于输出梯度 grad_out、输入 input、均值 mean 和方差 variance，计算输入梯度 grad_input，以及可选的权重梯度 grad_weight 和偏置梯度 grad_bias。常用于训练中更新参数，支持指定归一化形状。

​	**参数：**

| 参数名称         | 类型            | 是否必需 | 默认值 | 描述               |
| ---------------- | --------------- | -------- | ------ | ------------------ |
| grad_out         | AnyTensor       | 是       | 无     | 输出梯度张量。     |
| input            | AnyTensor       | 是       | 无     | 输入张量。         |
| mean             | AnyTensor       | 是       | 无     | 保存的均值。       |
| variance         | AnyTensor       | 是       | 无     | 保存的方差。       |
| weight           | AnyTensorOrNone | 否       | 无     | 权重张量（可选）。 |
| bias             | AnyTensorOrNone | 否       | 无     | 偏置张量（可选）。 |
| normalized_shape | I64ArrayAttr    | 是       | 无     | 归一化的形状。     |
| grad_input       | AnyTensorOrNone | -        | -      | 输入梯度（可选）。 |
| grad_weight      | AnyTensorOrNone | -        | -      | 权重梯度（可选）。 |
| grad_bias        | AnyTensorOrNone | -        | -      | 偏置梯度（可选）。 |

### 	2.153EmbDenseBwdOp

​	**功能：**Top_EmbDenseBwdOp 是嵌入层密集反向传播操作。将输出梯度 grad_output 根据索引 indices 映射回嵌入权重空间，输出是梯度的子集。常用于词嵌入或稀疏梯度更新，支持指定嵌入权重总数。

​	**参数：**

| 参数名称    | 类型      | 是否必需 | 默认值 | 描述             |
| ----------- | --------- | -------- | ------ | ---------------- |
| grad_output | AnyTensor | 是       | 无     | 输出梯度张量。   |
| indices     | AnyTensor | 是       | 无     | 索引张量。       |
| num_weights | SI32Attr  | 是       | 无     | 嵌入权重的总数。 |
| output      | AnyTensor | -        | -      | 输出梯度子集。   |

### 	2.154WeightReorderOp

​	**功能：**Top_WeightReorderOp 对输入权重张量进行重排，根据 reorder_mode 指定方式（如排序或特定模式）。常用于优化硬件布局或数据对齐，输出形状与输入相同。

​	**参数：**

| 参数名称     | 类型      | 是否必需 | 默认值 | 描述               |
| ------------ | --------- | -------- | ------ | ------------------ |
| input        | AnyTensor | 是       | 无     | 输入张量（权重）。 |
| reorder_mode | I64Attr   | 否       | 0      | 重排模式。         |
| output       | AnyTensor | -        | -      | 重排后的输出张量。 |

### 	2.155SoftmaxBwdOp

​	**功能：**Top_SoftmaxBwdOp 是 softmax 操作的反向传播，计算输入梯度 grad_input。它基于输出梯度 grad_output 和 softmax 前向输出 output，沿指定维度 dim 计算梯度，用于训练中更新参数。常用于分类任务的反向传播。

​	**参数：**

| 参数名称    | 类型            | 是否必需 | 默认值 | 描述                                   |
| ----------- | --------------- | -------- | ------ | -------------------------------------- |
| grad_output | AnyTensor       | 是       | 无     | 输出梯度张量。                         |
| output      | AnyTensor       | 是       | 无     | Softmax 前向输出张量。                 |
| dim         | SI32Attr        | 是       | 无     | 计算维度的索引（0 表示行，1 表示列）。 |
| grad_input  | AnyRankedTensor | -        | -      | 输入梯度张量，形状与输入相同。         |

### 	2.156ConvBwdWeightOp

​	**功能：**Top_ConvBwdWeightOp 计算卷积操作中权重的梯度，用于训练阶段。它基于输入张量 input 和输出梯度 grad_output，结合转置梯度 gradout_transpose，计算权重梯度，支持分组卷积（groups）、填充、步幅和膨胀率。输出是权重梯度，常用于卷积神经网络的优化。

​	**参数：**

| 参数名称          | 类型         | 是否必需 | 默认值 | 描述                     |
| ----------------- | ------------ | -------- | ------ | ------------------------ |
| input             | AnyTensor    | 是       | 无     | 输入张量。               |
| gradout           | AnyTensor    | 是       | 无     | 输出梯度张量。           |
| gradout_transpose | AnyTensor    | 是       | 无     | 输出梯度的转置。         |
| groups            | I64Attr      | 是       | 无     | 分组卷积的组数。         |
| input_shape       | I64ArrayAttr | 是       | 无     | 输入张量的形状。         |
| grad_out_shape    | I64ArrayAttr | 是       | 无     | 输出梯度的形状。         |
| kernel_shape      | I64ArrayAttr | 是       | 无     | 卷积核大小。             |
| stride            | I64ArrayAttr | 是       | 无     | 步幅。                   |
| dilations         | I64ArrayAttr | 是       | 无     | 膨胀率。                 |
| padding           | I64ArrayAttr | 是       | 无     | 填充（上、左、下、右）。 |
| grad_bias_enable  | BoolAttr     | 是       | 无     | 是否计算偏置梯度。       |
| output            | AnyTensor    | -        | -      | 权重梯度张量。           |

### 	2.157VarianceOp

​	**功能：**Top_VarianceOp 沿指定维度 reduce_list 计算输入张量的方差。correction 调整无偏估计，keep_dims 决定是否保留缩减维度。输出是方差值，常用于统计分析或归一化。

​	**参数：**

| 参数名称    | 类型         | 是否必需 | 默认值 | 描述                        |
| ----------- | ------------ | -------- | ------ | --------------------------- |
| input       | AnyTensor    | 是       | 无     | 输入张量。                  |
| reduce_list | I64ArrayAttr | 是       | 无     | 计算方差的维度列表。        |
| correction  | F64Attr      | 是       | 无     | 校正因子（通常为 0 或 1）。 |
| keep_dims   | BoolAttr     | 否       | false  | 是否保留缩减维度。          |
| output      | AnyTensor    | -        | -      | 输出张量（方差值）。        |

### 	2.158RsqrtOp

​	**功能：**Top_RsqrtOp 对输入张量的每个元素计算逆平方根（1/sqrt(input)）。输出形状与输入相同，常用于归一化或激活函数的计算（如 RMSProp 优化器）。

​	**参数：**

| 参数名称 | 类型      | 是否必需 | 默认值 | 描述                       |
| -------- | --------- | -------- | ------ | -------------------------- |
| input    | AnyTensor | 是       | 无     | 输入张量。                 |
| output   | AnyTensor | -        | -      | 输出张量，形状与输入相同。 |

### 	2.159SortOp

​	**功能：**Top_SortOp 沿指定维度 axis 对输入张量排序，输出排序后的值（可选）和索引。descending 决定是升序（false）还是降序（true）。常用于排序任务或数据预处理。

​	**参数：**

| 参数名称   | 类型            | 是否必需 | 默认值 | 描述                 |
| ---------- | --------------- | -------- | ------ | -------------------- |
| input      | AnyTensor       | 是       | 无     | 输入张量。           |
| axis       | I64Attr         | 是       | 无     | 排序的维度。         |
| descending | BoolAttr        | 否       | true   | 是否降序排序。       |
| values     | AnyTensorOrNone | -        | -      | 排序后的值（可选）。 |
| indices    | AnyTensor       | -        | -      | 排序后的索引。       |

### 	2.160MeanRstdOp

​	**功能：**Top_MeanRstdOp 用于批归一化训练，计算输入张量的均值（mean）、逆标准差（rstd = 1/sqrt(var + eps)）、更新后的运行均值和运行方差，以及缩放后的权重和偏置。它结合动量（momentum）更新运行统计值，常用于训练中稳定网络激活值，并输出用于后续计算的值。

​	**参数：**

| 参数名称            | 类型      | 是否必需 | 默认值 | 描述                 |
| ------------------- | --------- | -------- | ------ | -------------------- |
| input               | AnyTensor | 是       | 无     | 输入张量。           |
| running_mean        | AnyTensor | 是       | 无     | 当前运行均值。       |
| running_var         | AnyTensor | 是       | 无     | 当前运行方差。       |
| weight              | AnyTensor | 是       | 无     | 权重张量。           |
| bias                | AnyTensor | 是       | 无     | 偏置张量。           |
| eps                 | F64Attr   | 是       | 无     | 防止除以零的小常数。 |
| momentum            | F64Attr   | 是       | 无     | 更新运行统计的动量。 |
| mean                | AnyTensor | -        | -      | 计算的均值。         |
| rstd                | AnyTensor | -        | -      | 逆标准差。           |
| running_mean_update | AnyTensor | -        | -      | 更新后的运行均值。   |
| running_var_update  | AnyTensor | -        | -      | 更新后的运行方差。   |
| scale               | AnyTensor | -        | -      | 缩放后的权重。       |
| bias_new            | AnyTensor | -        | -      | 更新后的偏置。       |

### 	2.161GroupNormTrainOp

​	**功能：**Top_GroupNormTrainOp 是组归一化操作，将通道分成组（num_groups），对每组计算均值和标准差，进行归一化，然后乘以 weight 加 bias。输出包括归一化结果、均值和逆标准差，用于训练。常用于批次大小小的场景，作为批归一化的替代。

​	**参数：**

| 参数名称   | 类型            | 是否必需 | 默认值 | 描述                 |
| ---------- | --------------- | -------- | ------ | -------------------- |
| input      | AnyTensor       | 是       | 无     | 输入张量。           |
| weight     | AnyTensorOrNone | 否       | 无     | 权重张量（可选）。   |
| bias       | AnyTensorOrNone | 否       | 无     | 偏置张量（可选）。   |
| num_groups | I64Attr         | 是       | 无     | 组数。               |
| eps        | F64Attr         | 是       | 无     | 防止除以零的小常数。 |
| output     | AnyTensor       | -        | -      | 归一化输出张量。     |
| mean       | AnyTensor       | -        | -      | 计算的均值。         |
| rstd       | AnyTensor       | -        | -      | 逆标准差。           |

### 	2.162LogicalAndOp

​	**功能：**Top_LogicalAndOp 对两个输入张量逐元素进行逻辑与操作（AND），输出布尔张量。形状广播后一致，常用于掩码操作或条件过滤。

​	**参数：**

| 参数名称 | 类型                            | 是否必需 | 默认值 | 描述                 |
| -------- | ------------------------------- | -------- | ------ | -------------------- |
| inputs   | Variadic<anytensor></anytensor> | 是       | 无     | 输入张量，至少两个。 |
| output   | AnyTensor                       | -        | -      | 输出布尔张量。       |

### 	2.163ConvbwdOp

​	**功能：**Top_ConvbwdOp 是卷积的反向传播操作，计算输入梯度 grad_input、权重梯度 grad_weight 和偏置梯度 grad_bias。基于输出梯度 grad_out、输入 input 和核 kernel，支持分组、填充、步幅和膨胀率。常用于 CNN 训练的反向传播。

​	**参数：**

| 参数名称           | 类型            | 是否必需 | 默认值 | 描述                     |
| ------------------ | --------------- | -------- | ------ | ------------------------ |
| grad_out           | AnyTensor       | 是       | 无     | 输出梯度张量。           |
| input              | AnyTensor       | 是       | 无     | 输入张量。               |
| kernel             | AnyTensor       | 是       | 无     | 卷积核。                 |
| groups             | I64Attr         | 是       | 无     | 分组卷积的组数。         |
| input_shape        | I64ArrayAttr    | 是       | 无     | 输入形状。               |
| grad_out_shape     | I64ArrayAttr    | 是       | 无     | 输出梯度形状。           |
| kernel_shape       | I64ArrayAttr    | 是       | 无     | 卷积核大小。             |
| stride             | I64ArrayAttr    | 是       | 无     | 步幅。                   |
| dilations          | I64ArrayAttr    | 是       | 无     | 膨胀率。                 |
| padding            | I64ArrayAttr    | 是       | 无     | 填充（上、左、下、右）。 |
| inserts            | I64ArrayAttr    | 是       | 无     | 梯度计算选择。           |
| grad_input_enable  | BoolAttr        | 是       | 无     | 是否计算输入梯度。       |
| grad_weight_enable | BoolAttr        | 是       | 无     | 是否计算权重梯度。       |
| grad_bias_enable   | BoolAttr        | 是       | 无     | 是否计算偏置梯度。       |
| grad_input         | AnyTensorOrNone | -        | -      | 输入梯度（可选）。       |
| grad_weight        | AnyTensorOrNone | -        | -      | 权重梯度（可选）。       |
| grad_bias          | AnyTensorOrNone | -        | -      | 偏置梯度（可选）。       |

### 	2.164MaskRCNNRPNGetBboxesOp

 	**功能：**Top_MaskRCNNRPNGetBboxesOp 是 Mask R-CNN 中 RPN 的边界框生成操作。从多级类别得分和边界框预测中过滤高置信度锚框，调整边界框，应用 NMS 去除重叠，输出最终边界框列表。支持多级特征金字塔，常用于目标检测的提案生成阶段。

​	**参数：**

| 参数名称                   | 类型      | 是否必需 | 默认值 | 描述                    |
| -------------------------- | --------- | -------- | ------ | ----------------------- |
| cls_scores_0               | AnyTensor | 是       | 无     | 类别得分0。             |
| cls_scores_1               | AnyTensor | 是       | 无     | 类别得分1。             |
| cls_scores_2               | AnyTensor | 是       | 无     | 类别得分2。             |
| cls_scores_3               | AnyTensor | 是       | 无     | 类别得分3。             |
| cls_scores_4               | AnyTensor | 是       | 无     | 类别得分4。             |
| bbox_preds_0               | AnyTensor | 是       | 无     | 边界框预测0。           |
| bbox_preds_1               | AnyTensor | 是       | 无     | 边界框预测1。           |
| bbox_preds_2               | AnyTensor | 是       | 无     | 边界框预测2。           |
| bbox_preds_3               | AnyTensor | 是       | 无     | 边界框预测3。           |
| bbox_preds_4               | AnyTensor | 是       | 无     | 边界框预测4。           |
| max_shape                  | AnyTensor | 是       | 无     | 输出边界框的最大维度。  |
| mlvl_anchors_0             | AnyTensor | 是       | 无     | 多级锚0。               |
| mlvl_anchors_1             | AnyTensor | 是       | 无     | 多级锚1。               |
| mlvl_anchors_2             | AnyTensor | 是       | 无     | 多级锚2。               |
| mlvl_anchors_3             | AnyTensor | 是       | 无     | 多级锚3。               |
| mlvl_anchors_4             | AnyTensor | 是       | 无     | 多级锚4。               |
| delta2bbox_mean_0          | F64Attr   | 是       | 无     | 边界框增量均值0。       |
| delta2bbox_mean_1          | F64Attr   | 是       | 无     | 边界框增量均值1。       |
| delta2bbox_mean_2          | F64Attr   | 是       | 无     | 边界框增量均值2。       |
| delta2bbox_mean_3          | F64Attr   | 是       | 无     | 边界框增量均值3。       |
| delta2bbox_std_0           | F64Attr   | 是       | 无     | 边界框增量标准差0。     |
| delta2bbox_std_1           | F64Attr   | 是       | 无     | 边界框增量标准差1。     |
| delta2bbox_std_2           | F64Attr   | 是       | 无     | 边界框增量标准差2。     |
| delta2bbox_std_3           | F64Attr   | 是       | 无     | 边界框增量标准差3。     |
| delta2bbox_max_scalar_c    | F64Attr   | 是       | 无     | 标量值。                |
| iou_threshold              | F64Attr   | 是       | 无     | NMS 的 IoU 阈值。       |
| conf_threshold             | F64Attr   | 是       | 无     | 置信度阈值。            |
| MAX_LENGTH_STATIC_STRECHED | I64Attr   | 是       | 无     | 输出列表的最大长度。    |
| NUM_INDEXES                | I64Attr   | 是       | 无     | 索引数。                |
| NUM_CLASSES                | I64Attr   | 是       | 无     | 类别数。                |
| CHANNEL_RPN_BBOXES         | I64Attr   | 是       | 无     | 边界框预测通道数。      |
| CHANNEL_RPN_SCORES         | I64Attr   | 是       | 无     | 得分预测通道数。        |
| NMS_PRE                    | I64Attr   | 是       | 无     | NMS 前提案数。          |
| HARDWARE_FACTOR_TOPK       | I64Attr   | 是       | 无     | 保留的顶级提案数。      |
| NMS_MAX_LENGTH             | I64Attr   | 是       | 无     | NMS 后最大边界框数。    |
| TOPK_ONNX_NMS              | I64Attr   | 是       | 无     | ONNX NMS 的顶级提案数。 |
| H_RPN_DYN_MAX              | I64Attr   | 是       | 无     | 动态 RPN 输出最大高度。 |
| W_RPN_DYN_MAX              | I64Attr   | 是       | 无     | 动态 RPN 输出最大宽度。 |
| MAX_PER_IMG                | I64Attr   | 是       | 无     | 每图像最大提案数。      |
| result_list                | AnyTensor | -        | -      | 最终边界框列表。        |

### 	2.165MaskRCNNBboxPoolerOp

​	**功能：**Top_MaskRCNNBboxPoolerOp 是 Mask R-CNN 中的边界框池化操作，从多级特征图中根据 ROIs 提取固定大小的特征，使用 ROIAlign 进行池化。输出池化特征和 ROIs，常用于边界框分支的特征提取。

​	**参数：**

| 参数名称         | 类型      | 是否必需 | 默认值 | 描述           |
| ---------------- | --------- | -------- | ------ | -------------- |
| ptr_feat0        | AnyTensor | 是       | 无     | 特征图级别 0。 |
| ptr_feat1        | AnyTensor | 是       | 无     | 特征图级别 1。 |
| ptr_feat2        | AnyTensor | 是       | 无     | 特征图级别 2。 |
| ptr_feat3        | AnyTensor | 是       | 无     | 特征图级别 3。 |
| rois_multi_batch | AnyTensor | 是       | 无     | 多批次 ROIs。  |
| ROI_NUM_LEVELS   | I64Attr   | 是       | 无     | ROI 级别数。   |
| ROI_H            | I64Attr   | 是       | 无     | ROI 池化高度。 |
| ROI_W            | I64Attr   | 是       | 无     | ROI 池化宽度。 |
| CHANNEL_ROI      | I64Attr   | 是       | 无     | ROI 通道数。   |
| ROI_SLICE        | I64Attr   | 是       | 无     | ROI 切片数。   |
| ROI_PH           | I64Attr   | 是       | 无     | ROI 填充高度。 |
| ROI_PW           | I64Attr   | 是       | 无     | ROI 填充宽度。 |
| ROI_LEN          | I64Attr   | 是       | 无     | ROI 长度。     |
| result_res       | AnyTensor | -        | -      | 池化结果。     |
| result_rois      | AnyTensor | -        | -      | 输出 ROIs。    |

### 	2.166MaskRCNNGetBboxBOp

​	**功能：**Top_MaskRCNNGetBboxBOp 是 Mask R-CNN bbox 头部的最终边界框处理。解码 ROIs 和边界框预测，过滤低置信度，应用 NMS 去除重叠，输出检测边界框和标签。常用于目标检测的边界框精炼。

​	**参数：**

| 参数名称                | 类型      | 是否必需 | 默认值 | 描述                     |
| ----------------------- | --------- | -------- | ------ | ------------------------ |
| ptr_rois                | AnyTensor | 是       | 无     | ROIs 指针。              |
| ptr_bbox                | AnyTensor | 是       | 无     | 边界框预测指针。         |
| ptr_score               | AnyTensor | 是       | 无     | 分数指针。               |
| max_val                 | AnyTensor | 是       | 无     | 最大值。                 |
| scale_factor            | AnyTensor | 是       | 无     | 缩放因子。               |
| threshold_score_eq      | F64Attr   | 是       | 无     | 置信度阈值。             |
| wh_ratio_log            | F64Attr   | 是       | 无     | 宽高比对数因子。         |
| nms_iou_thr             | F64Attr   | 是       | 无     | NMS IoU 阈值。           |
| delta2bbox_means        | F64Attr   | 是       | 无     | 边界框回归均值。         |
| delta2bbox_stds_0       | F64Attr   | 是       | 无     | 边界框标准差0。          |
| delta2bbox_stds_1       | F64Attr   | 是       | 无     | 边界框标准差1。          |
| NUM_INDEXES             | I64Attr   | 是       | 无     | 索引数。                 |
| NUM_CLASSES             | I64Attr   | 是       | 无     | 类别数。                 |
| TOPK_ONNX_NMS           | I64Attr   | 是       | 无     | ONNX NMS 数量。          |
| NUM_CLASSES_getBboxB    | I64Attr   | 是       | 无     | 此步骤的类别数。         |
| MAX_NMS_LENGTH_GetBboxB | I64Attr   | 是       | 无     | NMS 后最大长度。         |
| MAX_PER_IMG             | I64Attr   | 是       | 无     | 每图像最大检测数。       |
| MAX_PER_IMG_GetBboxB    | I64Attr   | 是       | 无     | 最终每图像最大边界框数。 |
| result_det_bboxes       | AnyTensor | -        | -      | 检测边界框。             |
| result_det_labels       | AnyTensor | -        | -      | 检测标签。               |

### 	2.167MaskRCNNMaskPoolerOp

​	**功能：**Top_MaskRCNNMaskPoolerOp 是 Mask R-CNN 中的掩码池化操作，从多级特征图中根据检测边界框和标签提取固定大小的掩码特征，使用 ROIAlign 进行池化。输出池化特征，常用于掩码分支的特征提取。

​	**参数：**

| 参数名称               | 类型      | 是否必需 | 默认值 | 描述               |
| ---------------------- | --------- | -------- | ------ | ------------------ |
| x_0                    | AnyTensor | 是       | 无     | 特征级别 0。       |
| x_1                    | AnyTensor | 是       | 无     | 特征级别 1。       |
| x_2                    | AnyTensor | 是       | 无     | 特征级别 2。       |
| x_3                    | AnyTensor | 是       | 无     | 特征级别 3。       |
| det_bboxes_multi_batch | AnyTensor | 是       | 无     | 多批次检测边界框。 |
| det_labels_multi_batch | AnyTensor | 是       | 无     | 多批次检测标签。   |
| scale_factor           | AnyTensor | 是       | 无     | 缩放因子。         |
| ROI_NUM_LEVELS         | I64Attr   | 是       | 无     | ROI 级别数。       |
| ROI_H                  | I64Attr   | 是       | 无     | ROI 高度。         |
| ROI_W                  | I64Attr   | 是       | 无     | ROI 宽度。         |
| CHANNEL_ROI            | I64Attr   | 是       | 无     | ROI 通道数。       |
| ROI_SLICE              | I64Attr   | 是       | 无     | ROI 切片数。       |
| ROI_PH                 | I64Attr   | 是       | 无     | ROI 填充高度。     |
| ROI_PW                 | I64Attr   | 是       | 无     | ROI 填充宽度。     |
| ROI_LEN                | I64Attr   | 是       | 无     | ROI 长度。         |
| result_res             | AnyTensor | -        | -      | 池化结果。         |

### 	2.168MaxPoolingIndicesBwdOp

​	**功能：**Top_MaxPoolingIndicesBwdOp 是最大池化的反向传播操作，将输出梯度 grad_output 根据最大值索引 indices 映射回输入空间，计算输入梯度 grad_input。支持填充、步幅和膨胀率，常用于 CNN 训练的反向传播。

​	**参数：**

| 参数名称     | 类型         | 是否必需 | 默认值 | 描述                     |
| ------------ | ------------ | -------- | ------ | ------------------------ |
| grad_output  | AnyTensor    | 是       | 无     | 输出梯度张量。           |
| indices      | AnyTensor    | 是       | 无     | 最大值索引。             |
| kernel_shape | I64ArrayAttr | 是       | 无     | 池化核大小。             |
| strides      | I64ArrayAttr | 是       | 无     | 步幅。                   |
| pads         | I64ArrayAttr | 是       | 无     | 填充（上、左、下、右）。 |
| dilations    | I64ArrayAttr | 是       | 无     | 膨胀率。                 |
| input_shape  | I64ArrayAttr | 是       | 无     | 输入形状。               |
| grad_input   | AnyTensor    | -        | -      | 输入梯度张量。           |