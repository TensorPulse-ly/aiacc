

参考链接[编译器开发](https://www.sophgo.com/curriculum/description.html?category_id=9)

# @Jabari

# 1.TPU-MLIR基础

## 	1.1简介

​	TPU-MLIR是算能深度学习处理器的编译器工程。它是基于MLIR设计的AI编译器。支持任何能导出为ONNX模型的框架，如PyTorch/TensorFlow/TFLite/Caffe等。支持算能全系列芯片，如CV18XX/BM1684X等。支持F32/F16/BF15/INT8等量化类型。

## 	1.2分层设计

​	TPU-MLIR将网络模型抽象成两层处理：一是TOP层，二是TPU层。TOP层是与芯片无关层，它包括图优化、量化、推理等等，TPU层是与芯片相关层，它包括权重重排、算子切分、地址分配、推理等。

​	TPU-MLIR还实现了推理功能，该功能是后续转换正确性验证的基础。转化的过程中，首先要把原模型提取成TOP层，然后将其转换为TPU层，最后再生成目标代码。![image-20250731112924506](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250731112924506.png)

​	如上图所示，先将模型框架转化为ONNX模型框架，ONNX提供了丰富的算子和一些基础数据类型，通过多个node来定义计算图。每个node定义了输入、输出、类型和属性等。这和MLIR中的operation有点类似。

​	Top Dialect接近于原始计算图，Op的定义与ONNX和PyTorch近似，表示高层的抽象计算，与具体硬件无关。

​	一、Translation。原模型到Top层的转换称为前段转换，主要使用Python语言来实现的，代码位置为./tpu-mlir/python/transform。该过程还包括一些优化操作，包括ONNX原生的优化操作还有自己编写的优化操作。转换的过程会生成一下中间文件，例如resnet18.onnx这个onnx模型，转化路径为 resnet18.onnx→resnet18_opt.onnx→final_opt.onnx→resnet18_origin.mlir	这个路径的第一步是借助ONNX原生的simplifier对模型本身的结构进行简化，第二步是借助OnnxOpt.py文件，路径为./tpu-mlir/python/transform/OnnxOpt.py，第三步是借助OnnxConverter.py文件，路径为./tpu-mlir/python/transform/OnnxConverter.py。

​	二、canonicalize。包含算子融合，计算化简等，它是MLIR原生的Pass，在用tablegen定义Op时要显示的对它进行声明，声明变量为hasCanonicalizer。代码位置为tpu-mlir/lib/Dialect/Top/Canonicalize。

​	三、lowering部分。lowering也就是降低，将较高级的IR转换成较低级的IR，也就是将TOP层降低到TPU层。TPU Dialect是用于表示TPU芯片的Kernel库，与具体的设备有关，TPU Dialect可以表示内存分配，软件流水，计算和数据读写并行等与最终指令生成相关的信息。代码位置为./tpu-mlir/lib/Conversion/TopToTpu

​	四、LayerGroup + AddressAssign。在lowering后就到了TPU层，TPU层会进行最核心的优化操作LayerGroup和AddressAssign。LayerGroup可以理解为算子融合，将多个算子看成一个算子来进行操作。算子在芯片上进行运算的流程是先把数据从内存搬移到计算单元，然后再将计算结果返回内存，该过程如果是串行的话就会造成很大的时间延迟。例如一个LayerGroup部分是将三个算子看成一个算子来计算，那么计算结果返回的则是三个算子的结果，可以减轻时间延迟。AddressAssign是地址分配的优化，例如一个tensor的生命周期结束后，那么可以其释放内存从而加载后续的tensor。代码位置为./tpu-mlir/lib/Dialect/Tpu/Transforms

​	五、Code Generation。调用相关芯片的后端生成机码。文件./tpu-mlir/lib/Dialect/Tup/Interfaces根据不同芯片进行了对应的实现，每个子目录下都包含着该芯片型号对应的每个算子的代码生成机制。文件./tpu-mlir/lib/Backend记录了不同芯片规格，需要根据芯片规格来进行相对应的接口实现。

​	六、Calibration + Quantization。当使用int8量化时会涉及到Calibration即校准。将高位数据映射到低位数据上提供运行效率，会伴随一定的信息损失，从而导致部分精度损失。某些算子不适合int8量化，这是可以采用混合精度量化，也就是部分算子使用int8量化，部分算子使用浮点型量化。

​	七、Correctness Check。TPU-MLIR提供对TOP和TUP Dialect的Inference。通过比较对应数据的相似性来确定整个转化/编译过程的正确性。同时由于可以比较每个中间tensor的结果，开发者可以快速定位错误点。![image-20250801083743998](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250801083743998.png)

cos_sim为容忍度。

## 	1.3量化

### 	量化概述

# 2.TPU-MLIR实战

## 	2.1 Pattern Rewriting Framework

​		Pattern Rewriting贯穿了整个MLIR，对IR进行变换基本都需要用到Pattern Rewriting。整个Pattern Rewriting框架可以分为三个部分，分别是Pattern Definition、Pattern Rewriting、Pattern Application。

​		Pattern Definition：所有的Pattern都继承自RewritePattern。主要成员有：1.PatternBenefit。它是 MLIR 中 RewritePattern 框架里用于控制多个重写规则（pattern）优先级的机制之一。取值为0到65k，通过优先级来让MLIR判定优先执行那个Pattern。2.Root Operation Name。助记词，代表Pattern要应用到的Op的名称。3.Match和Rewrite。match的返回值是一个LogicalResult，也就是success或failure，它用于判断是否满足使用条件。当匹配成功时会对IR进行更改，也就是Rewrite部分，它是对IR逻辑改写的实现。这两个方法也可以实现在一个方法中，matchAndRewrite。4.Application Recursion。如果一个Pattern被转换后的转换结果又被相同的Pattern匹配到，其结果的结果可能又被匹配到，出现递归的情况。Application Recursion就是用来防止无限循环的。

​	当定义工作完成后，可以使用Create方法来构造Pattern。

![image-20250802005322511](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802005322511.png)

​	Pattern Rewriter：Rewriter在每一个rewriter或matchAndRewrite方法中都需要被提供，它就是rewrite方法用来与pattern Application driver进行协调的工具。对于IR的变换都要通过rewriter来实现，常用的rewriter接口有eraseOp、replaceOp、replaceOPWithNewOp等，用于消除和替换当前的op。

​	Pattern Application：在定义好所有的Pattern后，就需要把所有会用到的Pattern输送给driver来应用这些Pattern。Driver是通过PatternSet的形式来接收所有的Pattern，所以需要先将创建好的pattern添加到其中。![image-20250802013930091](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802013930091.png)

## 	2.2Dialect Conversion

​	从一个Dialect转化到另一个Dialect的过程称为Conversion。MLIR提供了一个Dialect的Conversion框架，本质上就是将一系列在目标Dialect上非法的算子转化为合法的算子。

```cpp
//保留未被标位illegal的operations，尽可能多的对其他operation合法化，这样即使原IR中存在一些未知的算子也能进行转换工作
mlir::applyPartialConversion(operation,target,patterns)
//通过部分转换并记录operation转换是否成功，确定哪些operation可合法化
mlir::applyAnalysisConversion(...)
// 转换所有operation，转换后的IR中只存在已知的算子
mlir::applyFullConversion(...)
```

​	Dialect Conversion主要需要三个组件：1.Conversion Target   2.Rewrite Patterns 3.Type Conversion

​	Conversion Target：用于明确转换过程中哪些算子和Dialect是合法的，可以标记为合法、动态、非法三种action。动态是指某些算子只有在部分实例中是合法的。可以通过继承ConversionTarget类创建一个自定义MyTarget，在其构造函数中包含各种Dialect和Op是否合法的信息，也可以在ConversionTarget的实例中通过add系列的functions添加合法与非法的Dialect和Op。

```cpp
struct MyTarget : public ConversionTarget{
	#Legal
	addLegalDialect<LLVMDialect>();		//合法的Dialect
	addLegalOp<arith::ConstantOp>;		//合法的Op
	
	#Dynamic
	addDynamicallyLegalDialect<AffineDialect>([](operation *op) {...});		//动态的Dialect
	addDynamicallyLegalOp<func::ReturnOp>([](func::ReturnOp op) {...});		//动态的Op
	markUnknownOpDynamicallyLegal([]{Operation *op} {...});
	
	#illegal
	addIllegalDialect<GPUDialect>();	//非法的Dialect
	addIllegalOp<cf::BranchOp,cf::CondBranchOp>();	//非法的Op
}
```

​	也可以通过markOpRecursivelyLegal来将整个区域及某个Op中嵌套的所有算子定义为合法。

```cpp
ConversionTarget &target = ... ;
target.markkOpRecursivelyLegal<MyOp>();
```

​	Rewrite Patterns:定义完合法与非法算子后，就需要合法化Patterns来将非法算子转为合法算子。Rewrite Pattern适用于实现将非法算子转换为合法算子的转换逻辑。Dialect Conversion框架会自动根据所提供的patterns生成一个转换图，用于合法化从而简化整个改写的流程。例如A中的Op0可以转换为B中的Op0，B中的Op0可以转换为C中的Op0，conversion框架就会自动检测a中的Op0可以合法化为c中的Op0，而不用经过中间的算子转换。Rewrite Pattern中还有一个子类ConversionPattern，对于Rewrite Pattern它多了一个operands的输入参数，用于记录那些被重映射的操作数。

```cpp
struct MyConversionPattern : public ConversionPattern{
	virtual LogicalResult
	matchAndRewrite(operation *op, ArrayRef<Value> operands, ConversionPatternRewriter &rewriter) const;
}
```

​	Type Converter：当存在type转换时，则需要TypeConverter来定义type在与pattern交互时的转换方式，这是一个可选的组件。只有在执行到ConversionPattern时才会用到。重映射的操作数需要与Type Converter规定的一致。如果没有提供Type Converter则这些操作数的type需要与原操作数相匹配，否则Pattern的应用会在调用matchAndRewrite时失败。Type Converter由两个方面，一是Conversion，单纯定义type的转换。二是Materialization，是生成了一个新的算子，在新算子中添加新的type。其包括Source Materialization：target type→source type，Target Materialization：source type→ target type。

​	转换样例![image-20250802035226414](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802035226414.png)

​	总结：OpRewritePattern主要专注于Op级别的重写与转换，更使用于对局部Op的改写。Dialect Conversion主要用于不同Dialect间的转换，可以跨越多个Op和Dialect。本质上通过OpRewritePattern也能够实现大部分Op在不同Dialect间的转换。

## 	2.3前端转换

​	前段转换是初步的模型转换工作，也就是将原始模型转为TOP模型，不包含算子优化部分。转换后会得到一个初始的MLIR文件和存放权重的npz文件。

​	TPU-MLIR中前端转换可以分为五个步骤：1.前提	2.输入	3.初始化Converter	4.填充MLIR文本	5.输出

​	![image-20250802063019874](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802063019874.png)

​	前提：模型转换本质就是对模型中的算子进行转换，因此需要先在相应的td文件中对每个Op进行定义，TPU-MLIR中TUP层算子定义位于TopOps.td文件中。

​	输入：通过model_transform.py接口输入原始模型以及预处理参数。实例如下。

| --model_name    | 指定模型名称                                     |
| --------------- | ------------------------------------------------ |
| --model_def     | 指定模型定义文件                                 |
| --input_shapes  | 指定输入的shape，可以支持多输入情况              |
| --test_input    | 指定输入文件用于验证，不指定则不会进行正确性检验 |
| -test_result    | 指定检验后的输出文件                             |
| --mean和--scale | 对原模型的参数处理后的结果                       |
| -mlir           | 指定输出的mlir文件名称和路径                     |

​	初始化Converter：load_onnx_model用于加载模型，它会检验输入数量、保存input的名称、保存中间层的输出shape、保存tensor以及保存输出名称等操作。init_MLIRImporter主要用来初始化MLIR文本，这个文本只包含了一个module以及main functionOp，只提供了一个大概的框架。

​	填充MLIR文本：通过遍历整个原模型加上上一步获得的MLIR信息，便可在初始的MLIR文本中按照原模型的结构逐一插入算子，生成完整的MLIR模型。

​	输出：最后会生成一个origin.mlir文本文件以及将模型的权重文件保存为npz格式。

## 	2.4Lowering in TPU-MLIR

​	MLIR的Dialect Conversion是指IR在不同的Dialect之间进行转化的过程，而lowering就是从high-level dialect到low-level dialect的dialect conversion。

​	TPU-MLIR中的lowering就是将与芯片无关层的MLIR模型转换到与芯片相关层。Top层的算子可以分为F32与INT8两种。Top层的F32算子可以被直接转换为Tpu层的F32/F16/BF16算子，如果要转换为INT8算子，则需要经过校准量化。Top层的INT8算子只能直接转换为Tpu层的INT8算子。![image-20250802065610380](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802065610380.png)

​	另外，有的算子量化会导致严重的精度损失，这时就需要显式插入Quantize Table来指定不需要量化的算子。这就导致需要混合精度运算，前后算子的类型可能不同，为了运算精度相同，TPU-MLIR会在算子间插入CastOp对算子的输出类型进行转换![image-20250802065601067](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250802065601067.png)

​	TopToTpu的具体实现分为定义、Patterns实现、Pass实现。	定义：Tpu Dialect和算子的定义在/tpu-mlir/include/tpu-mlir/Dialect/Tpu/IR/TpuOps.td文件中，Pass的定义为/tpu-mlir/include/tpu-mlir/Conversion/Passes.td文件中。

​	Patterns实现：由OpRewritePattern派生出TopLowering类来定义算子的matchAndRewrite逻辑。类中还定义了一系列虚函数，用来将算子进行不同模式的lowering到特定芯片上。对于不同芯片，例如BM1684X，需要在LoweringBM1684X头文件中声明每一个支持的Op的Lowering Pattern类以及Lowering接口函数。接口的具体实现位于tpu-mlir/lib/Conversion/TopToTpu/BM1684X文件夹中。tpu-mlir/lib/Conversion/TopToTpu/LoweringBM1684X.cpp文件实现了将所有Op的Lowering Pattern添加到RewritePatternSet中。

​	Pass实现：首先在target中定义合法的以及非法的Dialect和Op，转换时会保留合法的Op转换非法的Op。然后根据芯片和算子的量化类型添加相应的重写pattern。最后通过转换接口遍历Top层模型，并将相应的Pattern应用。

## 	2.5添加新算子

​	第一步：定义算子。MLIR中可以直接使用tablegen工具完成定义工作。TPU-MLIR的Top层算子定义在tpu-mlir/include/tpu_mlir/Dialect/Top/IR/TopOps.td中，Tpu层的算子定义在tpu-mlir/include/tpu_mlir/Dialect/Tpu/IR/TpuOps.td中。这些算子将在编译器build时注册在相应的Dialect下的inc文件中，它包含了算子对应的cpp类。

​	第二步：接口实现。在Top Dialect中需要为新定义的算子实现inference、getFLOPS、shape_inference接口，分别实现算子的推理功能、计算浮点运算量、推理算子输出功能。需要在tpu-mlir/lib/Dialect/Top/Interfaces/OpName.cpp定义新的cpp文件，用来存放这些接口,OpName取决与算子名称。在Tpu Dialect中需要为每个Tpu算子实现inference接口，FLOPs和shape信息从Top Dialect中获取。

​	第三步：实现codegen逻辑。TPU算子最终会被用于不同芯片的代码生成，所以Dialect中的算子要对每个芯片实现接口，接口的实现位于tpu-mlir/lib/Dialect/Tpu/Interfaces文件夹下。

​	第四步：Lowering实现。例如BM1684X，需要在tpu-mlir/include/Conversion/TopToTpu/LoweringBM1684X.h中对算子的转换pattern进行注册，然后在tpu-mlir\lib\Conversion\TopToTpu\BM1684X文件夹下创建op对应的cpp文件，实现lowering到不同模式的接口。最后在tpu-mlir\lib\Conversion\TopToTpu\LoweringBM1684X.cpp文件中将算子的pattern添加到patternset中。

​	以上就是添加新算子的完整过程。

## 	2.6TPU-MLIR常用操作

​	获取算子/操作数：

```cpp
//在拥有Operation *op时
ValueRange values = op->getOperands();	//获取输入操作数
ValueRange values = op->getResults();	//获取输出操作数
Value value = values[idx];	//获取values中的值

//在拥有Value value时
Operation *op = value.getDefiningOp();	//获取输出为value的通用定义的Opeartion指针
ConvOp conv_op = dyn_cast<top::ConvOp>(op);		//通过dyn_cast将其转换为具体类型的算子，如conv_op
ConvOp conv_op = value.getDefiningOp<top::ConvOp>(op);		//将上面两步合为一步

//在拥有具体算子，如ConvOp conv_op时
Operation *op = conv_op.getOperation();		//获取定义的Operation指针
ValueRange input_values = conv_op->getOperands();	//获取输入操作数
ValueRange input_values = conv_op->getResults();	//获取输出操作数
```

​	获取Type与其中元素

```cpp
//在拥有Operation *op时
reulst_type_range result_types = op->getResultTypes();		//获取输出操作数的type
operand_type_range operand_types = op->getOperandTypes();	//获取输入操作数的type
Type operandType = operand_types[idx];	//获取其中某一个操作数的type

//在拥有Value value时
Type type = value.getType();	//获取操作数对应type

//在拥有ConvOp conv_op时
Type type = op.getType();		//获取操作数type

//基于value，op获取的type
type elem_type = type.getElementType();		//获取其中元素的数据类型
//type的类型是RankedTensorType时，可以使用cast对其进行转换，如果不能确定是RankedTensorType时，可以通过dyn_cast
RankedTensorType rt_type = type.cast<RankedTensorType>();
ArrayRef<int64_t> shapes = rt_type.getShape();	//通过getShape接口获取具体shape
```

​	Attribubute获取与设置

```cpp
//对于简单类型的属性，如bool、uint64_t等直接采用getter访问器进行获取
bool do_relu = conv_op.getDoRelu();
uint64_t pad_value = conv_op.getPadValue();

//解析浮点值时，得到的是一个llvm::APFloat类型，是任意精度的浮点数
llvm::APFloat relu_limit = conv_op.getReluLimit();

//ArrayAttr这种复杂类型，对于其获取已经封装成了一个接口即位于moudle.h中的getI64Array函数
i64_array_t kernel_shape = moudle::getI64Array(conv_op.getKernelShape());

//为op设置属性
//第一种方法：通过具体算子的setAttr接口来设置。
//第一个参数是td文件中定义的属性名，第二个参数是builder或rewriter的getBoolAttr接口转换得到的Bool值
conv_op.setAttr("do_relu",builder.getBoolAttr(true));	//或rewrite.getBoolAttr(true)
//第二种方法：采用getNamedAttr接口来实现属性名和属性值的绑定，并返回一个NamedAttribute对象
NamedAttribute do_relu_attr = builder.getNamedAttr("do_relu",rewriter.getBoolAttr(true));
```

​	对于一个算子的创建分为一下几步：

​	1.设置插入点，让mlir知道这个算子在模型中的插入位置

```
rewriter.setInsertionPointAfter(op) / .setInsertionPointAfterValue(value);
```

​	2.准备输出type，通常是RankedTensorType，包含了shape以及元素类型

```
Type new_type = RankedTensorType::get(new_shape,new_elem_type);
```

​	3.准备Attribute列表，其中每一条都是绑定好属性名和属性值的NamedAttribute对象

```cpp
std::vector<NamedAttribute> attrs;
NamedAttribute do_relu_attr = builder.getNamedAttr("do_relu", rewriter.getBoolAttr(true));
attrs.push_back(do_relu_attr);
```

​	4.准备Loc，也就是该算子的名称

```cpp
NameLoc new_loc = NameLoc::get("new_conv");
```

​	5.准备Operands，也就是输入操作数

```
ValueRange operands = {input_value,weight_value,bias_value};
```

​	6.创建，准备好了上述元素，就可以通过rewriter的create接口来创建一个具体的算子

```cpp
tpu::ConvOp new_conv_op = rewriter.create<tpu::ConvOp>(new_loc,new_type,operands,attrs);
```

​	Op的替换

```cpp
//通过replaceOp把一个算子替换成另一个算子
rewriter.replaceOp(conv_op,new_conv_op.getOutput());
//或者使用replaceAllUsesWith来将算子的所有使用者交给另一个算子实现替换
conv_op.getResult().replaceAllUsesWith(new_conv_op.getOutput());

//可以通过replaceOpWithNewOp接口来达到创建新算子并替换的效果
rewriter.replaceOpWithNewOp<tpu::ConvOp>(conv_op,new_conv_op,operands,attrs);

//最后通过erase接口来删除算子，释放内存
conv_op.erase();
```

## 	2.7TPU原理

​	TPU基本架构：一个完整的TPU包含了多个Lane，每个Lane包含Local memory 和 Execution Units（EUs），前者用于存储要运算的数据，后者是TPU上的最小计算单元。整体的TPU memory由System memory 和 local memory组成，前者的主要部分是global memory，local memory是一组static RAM。

​	TPU指令：GDMA数据搬运指令，用于system memory和local memory间或system memory内的数据传输。BDC指令，用于驱动执行单元在Lane上做计算工作。HAU指令，用于不适合并行加速的计算，如NMS，SORT。

​	Local memory物理组成：由多个Static RAM组成的，每个SRAM称为一个bank。此外将SRAM每个都分成多个部分，所有SRAM拆分后的小部分纵向组成Lane。每个Lane只能访问自己那部分的local memory，这使得单个Lane中的执行单元EU只能处理自己local memory上的那部分张量。一旦调用BDC指令，所有Lane上的执行单元EU将对各自Lane的相同位置执行同样的运算。这就是TPU加速运算的方式。

​	TPU可以同时处理的数据个数取决于每个Lane上的执行单元数。它与EU Bytes（指的是每个Lane一次处理的数据的大小）和数据类型有关。![image-20250803084202586](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250803084202586.png)

​	Local memory地址分配![image-20250803084324807](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250803084324807.png)

## 	2.8TPU层优化

​	TPU层的优化操作即是对算子的LayerGroup以及在global memory上分配地址。 

​	每个算子都需要经历将输入从global memory 运输到local memory 运算，然后将输出搬运会global memory。如果每个算子都是这样串行方式去进行运算，那么就会导致效率低下。LayerGroup就是做一个算子融合的操作，将多个算子融合到一起，这样就可以将第一个算子的输入从global memory运输到local memory，之后进行运算，直到Group的最后一个计算结束将其输出搬运会global memory，这样就省去了中间算子搬运输入输出的耗时。LayerGroup分为三步，一是搜索分组切割点，二是分配TimeStep，三是分配存储空间。

​	AddressAssign是为权重和每个算子的输入输出以4k对齐方式分配Gmem地址。地址分配首先遍历所有的WeightOp，依次分配地址。之后再分配算子的Input和Output地址，这里会根据生命周期尽可能的复用内存空间。例如某时刻tensor0的生命周期已经结束，tensor1开始自己的生命周期且tensor1占用的空间小于tensor0，此时就可以复用。