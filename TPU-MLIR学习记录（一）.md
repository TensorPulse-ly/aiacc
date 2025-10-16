# 关于 TPU-MLIR 源码阅读（一）

@Juno

本次关于 TPU-MLIR 的源码阅读是基于在运行代码的过程中所涉及的文件的阅读，这次我们先对如下代码中的所涉及的文件进行解析。如下代码是在 TPU-MLIR 中完成模型转换的示例代码，实现的功能是将 onnx 模型变成 mlir 的模型。

```
$ model_transform \
    --model_name yolov5s \
    --model_def ../yolov5s.onnx \
    --input_shapes [[1,3,640,640]] \
    --mean 0.0,0.0,0.0 \
    --scale 0.0039216,0.0039216,0.0039216 \
    --keep_aspect_ratio \
    --pixel_format rgb \
    --output_names 350,498,646 \
    --test_input ../image/dog.jpg \
    --test_result yolov5s_top_outputs.npz \
    --mlir yolov5s.mlir
```

运行完这个代码，我从日志中发现这段代码明显使用了四个文件，分别为：

- model_transform.py：主要入口文件，包括命令行参数解析（--model_name, --input_shapes 等），ONNX 模型加载与预处理，MLIR 生成和优化流程，验证测试的执行逻辑；
- tpuc-opt.cpp：MLIR 的优化部分。
- model_runner.py：模型执行的逻辑，包括 ONNX/MLIR 模型的加载和执行，输入/输出处理，NPZ 文件生成逻辑。
- npz_tool.py：包含结果比较算法。

## 1.model_transform.py

### 一、main 函数

#### 功能概述

main 函数是模型转换和验证的总入口，负责：

- 解析命令行参数
- 判断是否为 QAT（量化感知训练）模型并做特殊处理
- 根据模型类型选择合适的 Transformer 工具
- 执行模型转换（如 ONNX→MLIR）
- 可选地进行推理验证（如精度对比）
- 处理量化表的对齐与导出
- 清理中间文件

#### 主要流程

- 日志初始化：输出 TPU-MLIR 版本信息。
- 参数解析：使用 argparse 解析大量命令行参数，支持多种模型类型和转换选项。
- QAT 量化模型处理：

  - 创建 FakeQuantNodelProcessor，判断模型是否为 QAT。
  - 如果是 QAT，先做 QAT 相关的模型处理（如去除 FakeQuant 节点），并替换模型路径。
- 选择模型转换工具：调用 get_model_transform(args)，根据模型类型（onnx/caffe/tflite/torch/mlir/maskrcnn）实例化对应的 Transformer。
- 模型转换：调用 tool.model_transform(...)，执行模型转换（如 onnx→mlir）。
- 推理验证（可选）：如果设置了输入和输出，调用 tool.model_validate(...)，对转换前后模型做推理并比对精度。
- QAT 量化表对齐与导出：如果是 QAT，调用 align_final_opt 和 align_canonicalize，对齐量化表与实际模型节点名。
- 记录和清理

  - 保存转换过程中的文件记录。
  - 非 debug 模式下清理中间文件。

### 二、main 函数的调用函数

#### 1. FakeQuantNodelProcessor 相关

- 功能：判断并处理 QAT 量化模型，去除 FakeQuant 节点，生成量化表。
- 主要方法：

  - process_model()：对 QAT onnx 模型做后处理，生成 _qat.onnx。_
  - align_final_opt()、align_canonicalize()：对齐量化表与实际模型节点名。

#### 2. get_model_transform(args)

- 功能：根据模型类型（onnx/caffe/tflite/torch/mlir/maskrcnn）实例化对应的 Transformer 工具。
- 逻辑：

  - 判断模型后缀，选择合适的 Transformer 子类（如 OnnxTransformer、CaffeTransformer 等）。
  - 每个 Transformer 封装了模型转换、推理、验证等功能。

#### 3. tool.model_transform(...)

- 功能：执行模型转换（如 onnx→mlir）。
- 逻辑：

  - 生成 origin mlir（如 onnx→mlir）。
  - 调用 mlir 优化工具（如 mlir_opt_for_top）做结构优化和后处理。
  - 记录转换过程和文件。

#### 4. tool.model_validate(...)

- 功能：对转换前后模型做推理并比对精度。
- 逻辑：

  - 加载输入数据（npz/jpg/npy）。
  - 调用原始模型和 mlir 模型分别推理，保存输出。
  - 调用 f32_blobs_compare 对比输出精度。
  - 记录推理过程和文件。

#### 5. tool.file_recorder.dump()、tool.cleanup()

- 功能：记录转换过程中的文件，清理中间文件。

### 三、基础功能函数

#### 1. ModelTransformer 及其子类

##### ModelTransformer

- 功能：模型转换的基类，定义了转换、推理、验证等通用接口。
- 主要方法：

  - model_transform：模型转换主流程。
  - model_validate：推理验证主流程。
  - origin_inference：原始模型推理（抽象方法，由子类实现）。

##### 子类（OnnxTransformer、CaffeTransformer、TFLiteTransformer、TorchTransformer、MlirTransformer、MaskRCNNTransformer）

- 功能：针对不同模型格式实现具体的转换和推理逻辑。
- 主要方法：

  - origin_inference：调用对应的推理后端（如 onnx_inference、caffe_inference 等）。

#### 2. ensure_batch_size

- 功能：保证输入张量的 batch size 满足要求（如自动扩展）。
- 逻辑：如果 batch size 不足，则重复填充。

#### 3. model_mlir

- 功能：生成原始 mlir 文件。
- 逻辑：调用 converter 的 generate_mlir 方法。

#### 4. model_transform

- 功能：模型转换主流程。
- 逻辑：

  - 生成 origin mlir。
  - 调用 mlir 优化工具做结构优化。
  - 记录转换过程和文件。

#### 5. model_validate

- 功能：推理验证主流程。
- 逻辑：

  - 加载输入数据。
  - 分别调用原始模型和 mlir 模型推理。
  - 对比输出精度。
  - 记录推理过程和文件。

## 2.BaseConverter.py

### 一、整体定位

该文件定义了一个名为 BaseConverter 的基类，主要用于张量（tensor）、操作数（operand）、形状（shape）等在模型转换过程中的管理。它为后续的具体转换器（如 ONNX、Caffe、TensorFlow 转 MLIR 等）提供了基础的数据结构和通用方法。

### 二、主要成员变量

```python
def __init__(_self_, _no_save_: bool = False):
        _self_.operands = dict()
        _self_.tensors = dict()
        _self_.shapes = dict()
        _self_.input_names = list()
        _self_.output_names = list()
        _self_.no_save = _no_save_ _# do not save intermediate files in disk_
```

- self.operands：字典，保存操作数（operand）的名称与对象的映射。
- self.tensors：字典，保存权重（weight）或常量张量的名称与 numpy 数组的映射。
- self.shapes：字典，保存张量名称与其 shape（list）的映射。
- self.input_names / self.output_names：输入、输出张量的名称列表。
- self.no_save：布尔值，是否不保存中间文件。

### 三、主要方法功能梳理

#### 1. 形状相关

```python
def addShape(self, name, shape):
        if len(shape) == 0:
            shape = [1]
        if isinstance(shape, tuple):
            shape = list(shape)
        elif not isinstance(shape, list):
            raise KeyError("{}:{} unknown shape".format(name, shape))
        if name in self.shapes:
            if self.shapes[name] != shape:
                raise KeyError("shape {} conflict {} vs {}".format(name, self.shapes[name], shape))
        self.shapes[name] = shape

    def getShape(self, name):
        if name not in self.shapes:
            raise KeyError("shape {} not found".format(name))
        return self.shapes[name]

    def setShape(self, name, shape):
```

- addShape(name, shape):添加 shape 信息，支持 tuple、list，若已存在则检查一致性。
- getShape(name):获取指定名称的 shape，不存在则报错。
- setShape(name, shape):修改已存在的 shape，不存在则报错。

#### 2.操作数相关

```python
def addOperand(self, name, op):
        if name in self.operands:
            if self.operands[name] != op:
                raise KeyError("operand {} conflict".format(name))
            return
        self.operands[name] = op

    def getOperand(self, name):
        if name not in self.operands:
            raise KeyError("operand {} not found".format(name))
        return self.operands[name]

    def getOp(self, name):
        if self.isWeight(name):
            return self.getWeightOp(name)
        return self.getOperand(name)
```

- addOperand(name, op):添加操作数，若已存在则检查一致性。
- getOperand(name):获取操作数对象，不存在则报错。
- getOp(name):如果是权重，返回权重操作数，否则返回普通操作数。

#### 3. 权重/张量相关

```python
def addWeight(_self_, _name_, _data_: np.ndarray):
        _if_ not isinstance(_data_, np.ndarray):
            _raise_ KeyError("tensor data must be a numpy array")
        _if_ _data_.dtype != np.float32:
            _data_ = _data_.astype(np.float32)
        _if_ _name_ in _self_.tensors:
            _if_ np.all(_self_.tensors[_name_] == _data_):
                _return_
            _raise_ KeyError("tensor {} conflict".format(_name_))
        _if_ len(_data_.shape) == 0:
            _data_ = _data_.reshape([1])
        _# all weight convert to f32._
        _self_.tensors[_name_] = _data_
        _self_.addShape(_name_, _data_.shape)

    def isWeight(_self_, _name_):
        _if_ _name_ in _self_.tensors:
            _return_ True
        _return_ False

    def getWeight(_self_, _name_):
        _if_ _name_ not in _self_.tensors:
            _raise_ KeyError("No {} tensor in model".format(_name_))
        _return_ _self_.tensors[_name_]
        
    def getWeightOp(_self_, _name_, _shape_: list = []):
        _if_ _name_ not in _self_.tensors:
            _raise_ KeyError("Should addWeight first:{}!!!".format(_name_))
        old_shape = _self_.getShape(_name_)
        _if_ _shape_ and old_shape != _shape_:
            _assert_ (np.prod(old_shape) == np.prod(_shape_))
            old_shape = _shape_
        ori_type = str(_self_.tensors[_name_].dtype)
        type_dict = {
            'int8': "INT8",
            'uint8': "UINT8",
            'float32': "F32",
            'int32': "INT32",
            'int16': "INT16",
            'uint16': "UINT16",
        }
        _if_ ori_type not in type_dict:
            _raise_ KeyError("type {} not implemented".format(ori_type))
        op = _self_.mlir.create_weight_op(_name_, old_shape, type_dict[ori_type])
        _self_.addOperand(_name_, op)
        _return_ op
```

- addWeight(name, data):添加权重张量，要求为 numpy 数组，自动转为 float32，shape 也会同步添加。
- isWeight(name):判断是否为权重（即是否在 tensors 字典中）。
- getWeight(name):获取权重张量，不存在则报错。
- getWeightOp(name, shape=[]):获取权重的操作数对象（通常用于 MLIR），必要时会 reshape，类型映射到 MLIR 支持的类型。

```python
def isScalar(_self_, _name_):
        _if_ not _self_.isWeight(_name_): _return_ False
        _if_ np.prod(_self_.getShape(_name_)) == 1: _return_ True
        w = _self_.getWeight(_name_)
        _return_ np.all(w == w.flatten()[0])

    def isScalar_(_self_, _name_, _x_):
        _assert_ (isinstance(_x_, (int, float)))
        _if_ not _self_.isWeight(_name_): _return_ False
        _if_ np.prod(_self_.getShape(_name_)) == 1: _return_ True
        w = _self_.getWeight(_name_)
        _return_ np.all(w == _x_)

    def getScalar(_self_, _name_):
        _if_ not _self_.isScalar(_name_):
            _raise_ RuntimeError("Not Scalar")
        _return_ _self_.getWeight(_name_).flatten()[0]
```

- isScalar(name):判断是否为标量（shape 乘积为 1，且所有值相等）。
- isScalar_(name, x):判断是否为值为 x 的标量。
- getScalar(name):获取标量的值。

#### 4. 其他

```python
def generate_mlir(_self_, _mlir_file_: str):
        _raise_ NotImplementedError('generate_mlir')
        
    def WeightToNpz(_self_, _weight_file_):
        tensor_npz = {}
        _for_ name _in_ _self_.tensors:
            _if_ name in _self_.operands:
                tensor_npz[name] = _self_.tensors[name]
        np.savez(_weight_file_, **tensor_npz)
```

- generate_mlir(mlir_file):生成 MLIR 文件的接口，基类未实现，需子类实现。
- WeightToNpz(weight_file):将所有权重（且已添加为操作数的）保存为 npz 文件。

---

### 四、典型的使用流程（举例说明）

假设现在要把一个深度学习模型（比如 ONNX、Caffe、TensorFlow）转换成 MLIR 格式，大致会经历以下几个步骤：

#### 步骤一：收集和注册模型信息

- 读取模型文件，遍历每一层（layer）或每个节点（node）。
- 对于每个输入、输出、权重、常量等，调用如下方法注册到 converter 里：
- addShape(name, shape)：记录每个张量的形状（比如 [1, 3, 224, 224]）。
- addWeight(name, data)：记录每个权重的具体数值（numpy 数组），比如卷积的权重。
- addOperand(name, op)：记录每个操作数（比如某一层的输出）。

#### 步骤二：在转换过程中随时查询

- 需要用到某个张量/权重/操作数时，调用 getShape(name)/getWeight(name)/getOperand(name)这些方法保证你能随时拿到你需要的数据。

#### 步骤三：判断和处理特殊情况

- 比如有些权重其实是“标量”（只有一个数），可以用 isScalar(name)/getScalar(name)判断和获取。

#### 步骤四：生成 MLIR 文件

- 当所有信息都收集好后，调用 generate_mlir(mlir_file)（子类实现）来生成最终的 MLIR 文件。

#### 步骤五：保存权重

- 如果需要把权重单独保存成 npz 文件，调用 WeightToNpz(weight_file)。

## 3.deploy_qat.py

### 一、整体定位

本文件主要用于处理 QAT（Quantization Aware Training，量化感知训练）后的 ONNX 模型，对模型中的 FakeQuant 节点进行处理、裁剪、参数提取、表格导出等操作，为后续的部署和推理做准备。核心类为 FakeQuantNodelProcessor，它负责识别、处理、移除 QAT 相关节点，并生成量化表（calitable、qtable）等。下面是阅读这个文件的代码的简化版的结构。

```
FakeQuantNodelProcessor
    |
    |-- process_model()
            |-- prepare_params()
            |-- remove_fake_pad_op()
            |-- 遍历节点
                    |-- deal_with_weight_fakequant()
                    |-- clip_weight()
                    |-- parse_qparams()
                    |-- deal_with_activation_fakequant()
            |-- 移除节点
            |-- onnx.shape_inference.infer_shapes
            |-- 移除未用initializer
            |-- post_process_clip_ranges()
    |
    |-- export_tables()
    |-- align_final_opt() / align_canonicalize()  # 名字对齐
```

### 二、主要函数与成员变量

#### 1. 量化节点类型定义

```sql
PERCHANNEL_FAKEQUANTIZER = ['FakeQuantizeLearnablePerchannelAffine',
                                'FixedPerChannelAffine',
                                'FakeQuantizeDSQPerchannel',
                                'FPEmuOp_per_channel']
    PERTENSOR_FAKEQUANTIZER = ['LearnablePerTensorAffine',
                               'FixedPerTensorAffine',
                               'FakeQuantizeDSQPertensor',
                               'FakeQuantizeTqtAffine',
                               'FPEmuOp_per_tensor']
    ALL_FAKEQUANTIZER = PERCHANNEL_FAKEQUANTIZER + PERTENSOR_FAKEQUANTIZER
```

- PERCHANNEL_FAKEQUANTIZER：按通道量化的 FakeQuant 节点类型列表。
- PERTENSOR_FAKEQUANTIZER：按张量量化的 FakeQuant 节点类型列表。
- ALL_FAKEQUANTIZER：所有支持的 FakeQuant 节点类型。

#### 2. 初始化与成员变量

```python
def __init__(_self_, _input_model_path_, _input_model_name_):
        _self_.input_model_name = _input_model_name_
        _self_.input_model_path = _input_model_path_
        _self_.output_model_path = _input_model_path_.replace('.onnx', '_qat.onnx')
        _self_.fakequant_model = _self_.check_onnx_for_fakequant_nodes(_input_model_path_)
        _self_.calitable_name = _input_model_name_ + "_calitable_qat"
        _self_.qtable_name = _input_model_name_ + "_qtable_qat"
        _self_.nodes_to_be_removed = []
        _self_.cali_table = {}
        _self_.weight_table = {}
        _self_.q_table = {}
```

- input_model_path/input_model_name：输入模型路径和名称。
- output_model_path：输出模型路径（自动加后缀）。
- fakequant_model：模型中是否包含 FakeQuant 节点。
- calitable_name/qtable_name：量化表文件名。
- nodes_to_be_removed：待移除节点列表。
- cali_table/weight_table/q_table：量化参数表、权重量化表、量化类型表。

#### 3.process_model()

process_model() 是 FakeQuantNodelProcessor 类的核心方法，主要用于对 QAT（量化感知训练）得到的 ONNX 模型进行后处理。其目标是：

- 移除 FakeQuant 节点（量化伪节点）
- 修正权重数据
- 生成量化和校准表
- 简化模型结构，便于后续部署

```python
def process_model(_self_):
        _self_.prepare_params() #初始化输入输出映射、参数、initializer。
        _self_.remove_fake_pad_op() #移除无效 Pad 节点，修正后续节点输入。
        _self_.update_inp2node_out2node(_self_.graph) #建立输入到节点、输出到节点的映射。
        _for_ node _in_ _self_.graph.node:
            print(f'process_node :{node.name}, type:{node.op_type}')
            # 处理伪量化节点
            _if_ node.op_type in _self_.ALL_FAKEQUANTIZER:
                _self_.nodes_to_be_removed.append(node)
                _self_.nodes_to_be_removed.extend(_self_.get_constant_inputs(node))
            # 处理输出节点映射
            _if_ node.output[0] not in _self_.inp2node:
                _assert_ node.output[0] in [l.name _for_ l _in_ _self_.graph.output]#[l.name for l in self.graph.output]：提取模型所有最终输出的名称，用于验证 “未被映射的输出” 的合法性。
                _self_.inp2node[node.output[0]] = []
            next_nodes = _self_.inp2node[node.output[0]]
            #权重量化节点处理（PERCHANNEL_FAKEQUANTIZER）：调用 deal_with_weight_fakequant，将权重 FakeQuant 节点替换为原始权重，收集冗余节点。
            #调用 clip_weight，对权重做裁剪。
            #调用 parse_qparams，解析量化参数，生成权重量化表和量化类型表。
            _if_ node.op_type in _self_.PERCHANNEL_FAKEQUANTIZER:
                redundant_nodes = _self_.deal_with_weight_fakequant(node)
                _self_.nodes_to_be_removed.extend(redundant_nodes)
                _self_.clip_weight(node)
                # 生成权重量化参数表
                tensor_name, scale, zero_point, qmin, qmax, dtype, quant_type = _self_.parse_qparams(node)
                _if_ len(next_nodes) == 1 and next_nodes[0][0].op_type in ['Gemm', 'Conv']:
                    next_node_output = next_nodes[0][0].output[0]
                    _assert_ next_nodes[0][0].op_type in ['Gemm', 'Conv']
                    _if_ _self_.inp2node[next_node_output][0][0].op_type == 'Relu':
                        tensor_name = '{}_{}_weight'.format(_self_.inp2node[next_node_output][0][0].output[0], 'Relu')
                    _else_:
                        tensor_name = '{}_{}_weight'.format(next_node_output, next_nodes[0][0].op_type)
                    _self_.weight_table[tensor_name] = [
                        tensor_name,
                        len(scale),
                        *[float(f"{float(x):.7f}") _for_ x _in_ scale],
                        len(zero_point),
                        *[int(x) _for_ x _in_ zero_point]
                        ]
                    _self_.q_table[tensor_name] = [tensor_name,quant_type]
             # 处理张量级伪量化（激活或权重）
            _elif_ node.op_type in _self_.PERTENSOR_FAKEQUANTIZER:
                _if_ len(next_nodes) == 1 and next_nodes[0][1] == 1 and next_nodes[0][0].op_type in ['Gemm', 'Conv']:
                    _# 处理权重伪量化_
                    redundant_nodes = _self_.deal_with_weight_fakequant(node)
                    _self_.nodes_to_be_removed.extend(redundant_nodes)
                    _self_.clip_weight(node)
                    tensor_name, scale, zero_point, qmin, qmax, dtype, quant_type = _self_.parse_qparams(node)
                    _assert_ next_nodes[0][0].op_type in ['Gemm', 'Conv']
                    tensor_name_new = '{}_{}_weight'.format(next_nodes[0][0].output[0], next_nodes[0][0].op_type)
                    _self_.weight_table[tensor_name_new] = [
                        tensor_name_new,
                        len(scale),
                        *[float(f"{float(x):.7f}") _for_ x _in_ scale],
                        len(zero_point),
                        *[int(x) _for_ x _in_ zero_point]
                        ]
                    _self_.q_table[tensor_name_new] = [tensor_name_new,quant_type]
                _else_:
                    # 处理激活伪量化
                    tensor_name, scale, zero_point, qmin, qmax, dtype, quant_type = _self_.parse_qparams(node)
                    tensor_name = node.input[0]
                    _if_ node.input[0] in _self_.out2node:
                        pre_node = _self_.out2node[tensor_name]
                        pre_type = pre_node.op_type
                        tensor_name = '{}_{}'.format(tensor_name, pre_type)
                    _self_.cali_table[tensor_name] = [
                        tensor_name,
                        float(f"{float(scale * max(-qmin, qmax)):.7f}"),
                        float(f"{float(scale * (qmin - zero_point)):.7f}"),
                        float(f"{float(scale * (qmax - zero_point)):.7f}")
                    ]
                    _self_.q_table[tensor_name] = [tensor_name,quant_type]
                    _self_.deal_with_activation_fakequant(node)
                    output_name = node.output[0]
                    _for_ out _in_ _self_.graph.output:
                        _if_ out.name == output_name:
                            out.name = node.input[0]
        #移除冗余节点
        _for_ node _in_ _self_.nodes_to_be_removed:
            _self_.graph.node.remove(node)
        #形状推理与保存模型
        model_onnx = onnx.shape_inference.infer_shapes(_self_.model)
        onnx.save(model_onnx, _self_.output_model_path)

        _# 清理初始化器_
        _self_.out2node, _self_.inp2node = _self_.update_inp2node_out2node(_self_.graph)
        _self_.named_initializer = _self_.prepare_initializer(_self_.graph)
        _for_ name, initial_data _in_ _self_.named_initializer.items():
            _if_ name in (_self_.out2node.keys() | _self_.inp2node.keys()):
                _continue_
            _self_.graph.initializer.remove(initial_data)
        #后处理裁剪范围
        _self_.post_process_clip_ranges()
```

- prepare_params():初始化输入输出映射、参数、initializer。
- remove_fake_pad_op():移除无效 Pad 节点，修正后续节点输入。
- update_inp2node_out2node(graph)：建立输入到节点、输出到节点的映射。
- deal_with_weight_fakequant(node)：处理权重量化的 FakeQuant 节点，将其替换为原始权重，返回冗余节点。
- clip_weight(node)：对权重做裁剪（clip）到量化区间。
- parse_qparams(node)：解析量化参数（scale、zero_point、qmin、qmax、dtype、quant_type）。
- deal_with_activation_fakequant(node)：处理激活量化的 FakeQuant 节点，将其前后节点直接连接。
- post_process_clip_ranges()：对特殊节点（如 Flatten、Reshape 等）输入输出的 clip range 做对齐，补全校准表。
- numpy_helper.to_array ()： 是 ONNX（Open Neural Network Exchange）工具包中的一个函数，其主要功能是将 ONNX 格式的张量（TensorProto）转换为 NumPy 数组。

#### 4.clip_weight(_self_, _node_)

该函数的核心作用是将权重裁剪到量化对应的浮点范围内，确保量化时不会因数值溢出导致精度损失。

```python
def clip_weight(self, node):
    # 1. 从伪量化节点中解析量化参数
    # tensor_name：权重名称；scale/zero_point：量化缩放和零点；qmin/qmax：量化范围边界
    # dtype：数据类型；quant_type：量化类型（如PER_CHANNEL/PER_TENSOR）
    tensor_name, scale, zero_point, qmin, qmax, dtype, quant_type = self.parse_qparams(node)
    
    # 2. 根据权重名称获取原始权重数据（NumPy数组格式）
    data = self.name2data[tensor_name]
    
    # 3. 计算量化对应的浮点裁剪范围
    # 公式：浮点最小值 = (量化最小值 - 零点) * 缩放因子
    # 作用：将整数量化范围[qmin, qmax]转换为对应的浮点数范围
    clip_range_min = ((qmin - zero_point) * scale).astype(data.dtype)
    clip_range_max = ((qmax - zero_point) * scale).astype(data.dtype)
    
    # 4. 判断是否为通道级量化（每个通道有独立的scale）
    # scale.shape[0] > 1 表示每个通道有独立的缩放因子
    if len(scale.shape) > 0 and scale.shape[0] > 1:
        new_data = []  # 存储裁剪后的权重
        transposed = False  # 标记是否需要转置（针对反卷积）
        
        # 5. 获取当前节点的下游节点（使用该权重的节点）
        next_node = self.inp2node[node.output[0]]
        
        # 6. 特殊处理反卷积层（ConvTranspose）的权重维度
        # 反卷积权重维度通常为[in_channels, out_channels, h, w]，需转置为[out_channels, ...]
        if len(next_node) == 1 and next_node[0][0].op_type == 'ConvTranspose':
            transposed = True
            data = data.transpose(1, 0, 2, 3)  # 调整维度顺序以匹配通道
        
        # 7. 按通道裁剪权重（每个通道使用独立的裁剪范围）
        for c in range(data.shape[0]):
            # 对第c个通道的权重裁剪到该通道对应的范围
            new_data.append(np.clip(data[c], clip_range_min[c], clip_range_max[c]))
        
        # 8. 将列表转换为NumPy数组
        new_data = np.array(new_data)
        
        # 9. 若之前转置过，恢复反卷积权重的原始维度
        if transposed:
            new_data = new_data.transpose(1, 0, 2, 3)
    
    # 10. 若为张量级量化（所有通道共享一个scale），直接裁剪整个权重
    else:
        new_data = np.clip(data, clip_range_min, clip_range_max)
    
    # 11. 将裁剪后的NumPy数组转换为ONNX张量格式
    new_data = numpy_helper.from_array(new_data)
    
    # 12. 更新初始化器中的权重数据（替换为裁剪后的数据）
    self.named_initializer[tensor_name].raw_data = new_data.raw_data
```

#### 5.parse_qparams(self, node)

`parse_qparams` 是 QAT（量化感知训练）模型后处理中的量化参数解析核心函数。它的核心作用是从伪量化（`FakeQuant`）节点中提取关键量化参数（如缩放因子、零点、量化范围等），并自动判断量化类型（如 INT8、UINT8、FP8），为后续模型量化部署（如权重裁剪、算子融合、硬件适配）提供必要的参数支持。

##### 提取关键量化参数

在计算图（如 ONNX）中，“输入（Input）” 和 “属性（Attribute）” 的设计有明确分工：

- 输入（Input）：用于传递 “动态数据”（如张量、中间计算结果），这些数据在图执行过程中可能变化（如不同批次的输入、动态生成的量化参数）。
- 属性（Attribute）：用于传递 “静态配置”（如固定的数值、类型），这些参数在图定义时就已确定，执行过程中不会变化（如 INT8 的固定范围 [-128,127]）。

FakeQuant 节点的核心参数（qmin/qmax、scale、zero_point）既可能是 “动态生成的”（需通过输入传递），也可能是 “固定配置的”（需通过属性传递），因此代码需要兼容两种情况。具体原因如下：

1. 输入传入（qmin/qmax 在 node.input 中）的场景与设计逻辑

适用场景：当 qmin/qmax 等参数是 “动态计算的结果” 时（如通过校准算法生成的量化范围）。

例如：在模型训练或校准阶段，qmin/qmax 可能根据输入数据的分布动态计算（如通过 “最小最大校准法” 统计输入的最小值和最大值作为 qmin/qmax），这些动态生成的参数会作为 “张量数据” 通过节点的 “输入” 传递给 FakeQuant 节点。

```python
if len(node.input) > 3:# 情况1：qmin/qmax通过节点输入传入（部分FakeQuant节点设计）
        qmin, qmax = node.input[-2:]
        qmin, qmax = self.name2data[qmin], self.name2data[qmax]  # 转换为数值# 从属性中提取数据类型（如“int8”）if len(node.attribute) > 0:
            qparams = self.parse_attrs(node.attribute)  # 解析属性为字典
            dtype = qparams['dtype']else:
            dtype = 'None'
```

这里的 `node.input` 是一个列表，存储了节点的所有输入张量名称。当输入长度超过 3 时（前 3 个通常是 tensor_name、scale、zero_point），最后 2 个输入就是动态生成的 qmin 和 qmax（以张量名称的形式存储，需通过 `self.name2data` 映射到实际数值）。

1. 属性传入（qmin/qmax 在 node.attribute 中）的场景与设计逻辑

适用场景：当 qmin/qmax 等参数是 “固定配置” 时（如预定义的量化类型对应的固定范围）。
例如：INT8 的量化范围是固定的 `qmin=-128，qmax=127`，UINT8 是 `qmin=0，qmax=255`，这些无需动态计算，可直接作为 “静态配置” 写入节点属性。

```python
elif len(node.attribute) > 0:# 情况2：qmin/qmax和dtype通过节点属性传入（另一类FakeQuant节点设计）
        qparams = self.parse_attrs(node.attribute)  # 解析属性（如quant_min、quant_max）
        qmin = qparams['quant_min']  # 量化最小值（如INT8的-128）
        qmax = qparams['quant_max']  # 量化最大值（如INT8的127）
        dtype = qparams['dtype']  # 数据类型（如“int”“uint”）
    else:# 异常情况：未找到qmin/qmax（可能导致后续量化错误）
        print.info(f'qmin and qmax are not found for <{node.name}>!')
```

这里的 `node.attribute` 是节点的静态配置列表，存储了预定义的量化范围（如 `quant_min` 对应 qmin，`quant_max` 对应 qmax），这些参数在图定义时就已确定，无需动态计算。

##### 自动判断量化类型

```python
_if_ qmax == float(448.0) or qmax == float(57344.0):
            quant_type = 'FP8'
```

- FP8（浮点 8 位）是一种特殊的量化格式，它的量化范围由硬件标准定义，而非整数范围。目前主流的 FP8 标准（如 IEEE 754-2019）中：

  - `qmax=448.0` 对应 FP8 的 “E4M3” 格式（指数位 4 位，尾数位 3 位）的最大正值范围；
  - `qmax=57344.0` 对应 FP8 的 “E5M2” 格式（指数位 5 位，尾数位 2 位）的最大正值范围。
- 逻辑：通过 `qmax` 的固定值直接匹配 FP8 类型（无需计算位数，因 FP8 不是整数离散范围）

```python
bit = int(np.log2(qmax-qmin+1))
        _if_ (bit == 8 and qmin < 0):
            dtype = 'int'
            quant_type = 'INT8'
        _elif_ (bit == 8 and qmin ==0):
            dtype = 'uint'
            quant_type = 'UINT8'
        _elif_ (bit == 4 and qmin < 0):
            dtype = 'int'
            quant_type = 'INT4'
```

整数量化类型（如 INT8、INT4）的量化范围是 “连续整数”，范围大小（`qmax - qmin + 1`）正好等于 `2^bit`（bit 为量化位数）。

位数（bit）：决定是 8 位还是 4 位量化（通过 `bit` 值判断）；

符号（qmin）：决定是带符号（`qmin < 0`，如 INT8、INT4）还是无符号（`qmin = 0`，如 UINT8）。

### 三、其他函数

- __init__(self, input_model_path, input_model_name)：初始化类成员变量，加载模型，设置输出路径、表名等。
- check_onnx_for_fakequant_nodes(self, onnx_model_path)：检查 ONNX 模型中是否包含 FakeQuant 节点。
- prepare_params(self)：准备模型的输入输出映射、参数、initializer。
- parse_attrs(self, node_attrs)：解析节点属性，转为 Python 字典。
- update_inp2node_out2node(self, graph)：建立输出到节点、输入到节点的映射。
- prepare_data(self, graph)：收集所有 initializer 和 Constant 节点的数据。
- prepare_initializer(self, graph)：收集所有 initializer 节点。
- get_constant_inputs(self, node)：获取节点的常量输入节点。
- remove_fake_pad_op(self)：移除所有 pads 全为 0 的 Pad 节点，并修正后续节点输入。
- deal_with_weight_fakequant(self, node)：处理权重量化的 FakeQuant 节点，将其替换为原始权重，返回冗余节点。
- weight_preprocess(self, target_tensor)：对权重做归一化处理（tanh+ 归一化），并找出冗余节点。
- get_constant_inputs(self, node)：获取节点的常量输入节点。
- post_process_clip_ranges(self)：对 Flatten、Resize、Reshape、Transpose 等节点的输入输出做 clip range 对齐，补全校准表。
- deal_with_activation_fakequant(self, node)：处理激活量化的 FakeQuant 节点，将其前后节点直接连接。
- export_tables(self)：导出校准表（calitable）和量化表（qtable）。
- get_activation_mappings(self, model)：获取激活节点的输入输出映射。
- align_final_opt(self, node_name_mapping, onnx_sim="")：对齐优化后的 ONNX 模型和原始模型的激活节点名。
- creat_new_qat_item(self, oir_name, new_name)：在表格中创建新的 QAT 项（用于节点名对齐）。
- align_canonicalize(self, mlir_file, test_result)：对齐 MLIR 文件中的激活名和 QAT 表。
- extract_activation_names_mlir(self, mlir_path)：从 MLIR 文件中提取激活名。
- compare_npz_name_mapping(self, test_result)：通过 npz 文件比对激活名，辅助对齐。

## 4.model_runner.py

### 一、整体定位

这个文件是一个多框架模型推理工具，支持 ONNX、MLIR、TFLite、Caffe、Torch、BModel 等多种格式的模型推理，并能将推理结果保存为 npz 文件。它既可以作为命令行工具使用，也可以作为 Python 模块被调用。主要功能包括：

- 加载输入数据（npz）
- 根据模型类型选择合适的推理后端
- 支持 dump 所有中间张量
- 支持多种硬件/仿真环境
- 支持多线程/多进程下的硬件资源锁管理

### 二、main 函数的整体流程

1. 参数解析：使用 argparse 统一解析命令行参数，获取输入文件、模型文件、输出文件、模型类型等信息。
2. 加载输入数据：通过 np.load(args.input) 加载输入的 npz 文件，得到输入张量字典。
3. 根据模型类型分发推理函数：通过判断模型文件的后缀，选择合适的推理函数进行模型推理。

   - .final.mlir → final_mlir_inference
   - .mlir → mlir_inference
   - .onnx → onnx_inference
   - .tflite → tflite_inference
   - .prototxt + .caffemodel → caffe_inference
   - .pt/.pth → torch_inference
   - .bmodel/.cvimodel → model_inference
   - 其他 → 报错
4. 保存推理结果

```python
_if_ __name__ == '__main__':
    _# yapf: disable_
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", _required_=True, _help_="input npz file")
    parser.add_argument("--model", _type_=str, _required_=True,
                        _help_="mlir/pytorch/onnx/tflie/bmodel/prototxt file.")
    parser.add_argument("--weight", _type_=str, _default_="",
                        _help_="caffemodel for caffe")
    parser.add_argument("--output", _default_='_output.npz',
                        _help_="output npz file")
    parser.add_argument("--dump_all_tensors", _action_='store_true',
                        _help_="dump all tensors to output file")
    parser.add_argument("--debug", _type_=str, _nargs_="?", _const_="",
                        _help_="configure the debugging information.")
    parser.add_argument("--out_fixed", _action_="store_true",
                        _help_="no float number transforming, only for int8/uint8.")
    parser.add_argument("--cuda", _action_="store_true",
                        _help_="use cuda to do inference")
    parser.add_argument("--decrypt_lib", _type_=str, _default_="",
                        _help_="use decrypt_lib to load encrypted bmodel")
    _# yapf: enable_
    args = parser.parse_args()
    data = np.load(args.input)
    output = dict()
    _if_ args.model.endswith("final.mlir"):
        output = final_mlir_inference(data, args.model, args.dump_all_tensors)
    _elif_ args.model.endswith(".mlir"):
        output = mlir_inference(data, args.model, args.dump_all_tensors, args.debug, args.out_fixed,
                                args.cuda)
    _elif_ args.model.endswith('.onnx'):
        output = onnx_inference(data, args.model, args.dump_all_tensors)
    _elif_ args.model.endswith(".tflite"):
        output = tflite_inference(data, args.model, args.dump_all_tensors)
    _elif_ args.model.endswith(".prototxt") and args.weight.endswith(".caffemodel"):
        output = caffe_inference(data, args.model, args.weight, args.dump_all_tensors)
    _elif_ args.model.endswith(".pt") or args.model.endswith(".pth"):
        output = torch_inference(data, args.model, args.dump_all_tensors)
    _elif_ args.model.endswith(".bmodel") or args.model.endswith(".cvimodel"):
        output = model_inference(data,
                                 args.model,
                                 _out_fixed_=args.out_fixed,
                                 _decrypt_lib_=args.decrypt_lib)
    _else_:
        _raise_ RuntimeError("not support modle file:{}".format(args.model))
    print("\nSaving ...")
    _if_ output:
        np.savez(args.output, **output)
        print("\nResult saved to:{}".format(args.output))
```

- final_mlir_inference：针对 .final.mlir 文件的推理，调用 pyfinalmlir 库，支持 dump 所有张量。
- mlir_inference：针对 .mlir 文件的推理，支持 CPU/CUDA，支持 dump 所有张量。
- onnx_inference：针对 .onnx 文件的推理，支持 dump 所有中间张量（通过修改 ONNX graph 的 output）。
- tflite_inference：针对 .tflite 文件的推理，支持 dump 所有中间张量，支持 NCHW/NHWC 格式转换。
- caffe_inference：针对 Caffe 的 prototxt/caffemodel 文件推理，支持 dump 所有中间张量。
- torch_inference：针对 PyTorch 的 pt/pth 文件推理，支持 dump 所有中间张量。
- model_inference：针对 bmodel/cvimodel 文件推理，支持硬件仿真、文件锁、dump 所有张量等。

### 三、其他函数功能汇总

##### show_fake_cmd

功能：打印可复现的命令行调用示例，方便调试和复现推理过程。

原理：通过字符串格式化将参数拼接成完整命令行字符串，直接输出到控制台。

##### get_chip_from_model

功能：获取模型对应的芯片类型。

原理：调用外部命令 `model_tool --chip` 解析模型文件，通过 `os.popen` 执行命令并读取输出结果，适用于 bmodel、cvimodel 等需要绑定芯片类型的模型格式。

##### pack_bmodel_context_generator

功能：保存 bmodel 的输入和输出数据到文件。

原理：利用 Python 生成器（`yield`）机制，先保存输入数据后暂停执行，待推理完成后恢复执行并保存输出数据，实现推理前后的数据记录。

##### ChipLock

功能：硬件资源锁类，用于多进程 / 多线程环境下管理硬件资源（如仿真器），防止资源冲突。

原理：

##### model_inference

功能：BModel/CVIMODEL 的统一推理入口。

原理：

##### get_cmodel_so / link_custom_so / link_cmodel_so

功能：选择并链接正确的仿真库（.so 文件），确保仿真环境匹配芯片类型。

原理：

##### _model_inference

功能：BModel/CVIMODEL 的底层推理实现。

原理：

##### final_mlir_inference

功能：针对 `.final.mlir` 文件的推理。

原理：

##### mlir_inference

功能：针对 `.mlir` 文件的推理，支持 CPU 和 CUDA 环境。

原理：

```python
def mlir_inference(inputs: dict,
                   mlir_file: str,
                   dump_all: bool = True,
                   mute: bool = False,
                   out_fixed: bool = False,
                   use_cuda: bool = False,
                   log_level: str = 'normal') -> dict:
    """
    基于MLIR文件执行模型推理（CPU或CUDA），返回推理结果
    
    参数说明：
    - inputs: 输入数据字典（键为输入名称，值为输入张量/数据）
    - mlir_file: 待执行的MLIR文件路径（通常是TPU方言或适配硬件的MLIR）
    - dump_all: 是否输出所有中间结果（用于调试，默认True）
    - mute: 是否静音（强制不输出日志，优先级高于log_level）
    - out_fixed: 输出是否为固定点格式（如量化模型的整数输出，默认False）
    - use_cuda: 是否使用CUDA加速（默认False，使用CPU推理）
    - log_level: 日志级别（控制输出详细程度，默认'normal'）
    返回值：
    - 推理结果字典（键为输出名称，值为输出张量/数据）
    """
    
    # 1. 处理静音/安静模式：重定向标准输出和错误输出（避免日志干扰）
    # 若开启静音（mute）或日志级别为quiet，将所有输出重定向到"黑洞"设备
    if mute or log_level == "quiet":
        # 打开Linux下的"黑洞"设备（/dev/null），所有写入的数据会被丢弃
        with open(os.devnull, "w") as devnull:
            # 复制标准输出（stdout）的文件描述符到黑洞设备（不再打印到控制台）
            os.dup2(devnull.fileno(), sys.stdout.fileno())
            # 复制标准错误（stderr）的文件描述符到黑洞设备（错误信息也不打印）
            os.dup2(devnull.fileno(), sys.stderr.fileno())
    
    try:
        # 2. 根据硬件选择推理方式（CPU或CUDA）
        if not use_cuda:  # 默认使用CPU推理
            # 调用CPU推理实现（内部执行MLIR文件，处理输入并返回结果）
            # 传入dump_all（是否输出中间结果）、out_fixed（输出格式）等参数
            return _mlir_inference_by_cpu(inputs, mlir_file, dump_all, out_fixed)
        else:  # 若指定use_cuda=True，使用CUDA加速推理
            # 调用CUDA推理实现（依赖GPU环境，速度更快）
            return _mlir_inference_by_cuda(inputs, mlir_file, dump_all)
    
    finally:
        # 3. 恢复标准输出和错误输出（无论推理是否成功，确保后续输出正常）
        # 仅在静音/quiet模式下需要恢复（否则无需操作）
        if mute or log_level == "quiet":
            # 将标准输出恢复为原始stdout（sys.__stdout__是Python保存的原始stdout）
            os.dup2(sys.__stdout__.fileno(), sys.stdout.fileno())
            # 将标准错误恢复为原始stderr
            os.dup2(sys.__stderr__.fileno(), sys.stderr.fileno())
```

##### _mlir_inference_by_cpu

功能：MLIR 模型在 CPU 环境下的底层推理实现。

原理：

##### _mlir_inference_by_cuda

功能：MLIR 模型在 CUDA 环境下的底层推理实现。

原理：

##### free_mlir_module

功能：释放全局 MLIR 模块资源。

原理：将全局 MLIR 模块变量设为 `None`，触发 Python 垃圾回收机制，避免长期运行时的内存泄漏。

##### onnx_inference

功能：ONNX 模型的推理实现。

原理：

##### caffe_inference

功能：Caffe 模型的推理实现。

原理：

##### tflite_inference

功能：TFLite 模型的推理实现。

原理：

##### torch_inference

功能：PyTorch 模型（`torch.jit` 导出的模型）的推理实现。

原理：

## 5.npz_tool.py

### 一、整体功能

这个脚本是一个多功能 npz 文件处理工具，用于对 .npz 文件（numpy 的多数组存储格式）进行各种操作，如对比、可视化、提取、合并、重命名、格式转换、统计等。它通过命令行参数选择不同的功能，适合模型开发、调试、量化、部署等场景下对中间/输出数据的批量处理。

### 二、主要结构与逻辑

1. 功能映射字典

```sql
npz_tool_func = {
    "compare": npz_compare,
    "print_diff": npz_print_diff,
    "visualize_diff": npz_visualize_diff,
    'dump':npz_dump,
    ...
}
```

- 用于根据命令行参数动态调用对应的处理函数。
- 每个 key 是命令行功能名，value 是实际执行的函数。

1. main 函数

```python
def main():
    args_list = sys.argv
    if len(args_list) < 2:
        funcs = npz_tool_func.keys()
        funcs_str = "["
        for idx, key in enumerate(npz_tool_func.keys()):
            funcs_str += key + ("|" if idx != len(funcs)-1 else '')
        funcs_str += "]"
        print(f"Usage: {args_list[0]} " + funcs_str + " ...")
        exit(-1)

    def NoneAndRaise(func):
        raise RuntimeError("No support {} Method".format(func))

    npz_tool_func.get(args_list[1], lambda x: NoneAndRaise(args_list[1]))(args_list[2:])
```

整体逻辑分为 3 步：

1. 参数数量检查：判断用户是否传入了至少 1 个功能名称（`len(args_list) < 2`）。若未传入，进入下一步提示用法；若已传入，直接执行对应功能。
2. 用法提示生成：当参数不足时，自动收集 `npz_tool_func` 字典中所有支持的功能名称，拼接成 `[功能1|功能2|...]` 格式的提示文本，告知用户工具的正确用法（如 `python script.py [功能名] ...`），然后退出。
3. 功能调用与错误处理：根据用户传入的功能名（`args_list[1]`），从 `npz_tool_func` 中查找对应的函数并调用（传入剩余参数 `args_list[2:]`）。若功能名不存在，通过 `NoneAndRaise` 函数抛出异常，提示 “不支持该功能”。

## 6.tpuc-opt.cpp

### 一、整体功能

这个文件实现了一个 TPU-MLIR 优化器命令行工具（类似于官方 MLIR 的 mlir-opt），用于对 MLIR（多层次中间表示）模块进行优化和转换。它是 TPU-MLIR 工具链中的核心组件之一，负责加载、注册所有自定义 Dialect 和 Pass，并根据命令行参数执行优化流程。

### 二、main 函数

#### 1）注册 Pass 和 Dialect

```python
tpu_mlir::registerAllPasses();
DialectRegistry registry;
tpu_mlir::registerAllDialects(registry);
```

- 注册所有自定义 Pass 和 Dialect，保证后续优化流程可用。

#### 2）处理 --deinit 选项

```go
bool hasDeinit = false;
for (int i = 1; i < argc; ++i) {
  if (std::string(argv[i]).find("--deinit") != std::string(argv[i]).npos) {
    hasDeinit = true;
    break;
  }
}
if (hasDeinit) {
  PluginPostPass = {"--mlir-print-debuginfo"};
} else {
  PluginPostPass = {"--deinit", "--mlir-print-debuginfo"};
}
```

- 检查命令行参数是否包含 --deinit。
- 如果有，则只加 --mlir-print-debuginfo，否则加 --deinit 和 --mlir-print-debuginfo。
- 这样可以灵活控制 pass 流程，避免重复 deinit。

#### 3）参数数量判断

```python
if (argc <= 2) {
  return asMainReturnCode(MlirOptMain(
      argc, argv, "TPU MLIR module optimizer driver\n", registry));
}
```

- 如果参数很少，直接调用 MLIR 的主入口，不做特殊处理。

#### 4）处理 --debug_cmd

```python
std::string debug_cmd = argv[argc - 1];
std::string substring = "--debug_cmd=";
if (debug_cmd.find(substring) != std::string::npos) {
  std::ofstream ofs;
  ofs.open("/tmp/debug_cmd", std::ios::out | std::ios::trunc);
  ofs << debug_cmd.substr(substring.size()) << std::endl;
  argc -= 1;
}
```

- 如果最后一个参数是 --debug_cmd=xxx，则将 xxx 写入 /tmp/debug_cmd 文件，并从参数列表中移除该参数。
- 便于调试和外部工具集成。

#### 5）构造新的参数列表

```python
int num_pre = sizeof(PluginPrePass) / sizeof(PluginPrePass[0]);
int num_post = PluginPostPass.size();
int new_argc = num_pre + argc + num_post;
char *new_argv[new_argc];
...
```

- 计算新参数数量（原始参数 + pre pass + post pass）。
- 构造新的参数数组 new_argv，将 pre pass、原始参数、post pass 按顺序插入。

##### 参数插入逻辑：

- 先插入原始参数（直到遇到第一个以 -- 开头的参数）。
- 插入 pre pass（如果原始参数中没有同名 pass）。
- 插入剩余原始参数（直到遇到 -o）。
- 插入 post pass。
- 插入剩余参数。

#### 6）调用 MLIR 主入口

```python
return asMainReturnCode(MlirOptMain(
    new_argc, new_argv, "TPU MLIR module optimizer driver\n", registry));
```

- 调用 MLIR 的主入口 MlirOptMain，传入新参数列表和注册表，执行优化流程。

## 7.mlir_shell.py

### 一、整体功能

这个文件是 TPU-MLIR 项目中的一个工具脚本，主要用于自动化 MLIR（Multi-Level Intermediate Representation）模型的转换、优化、量化、推理、编译等流程。它通过调用一系列命令行工具（如 tpuc-opt、mlir-opt、clang 等），将高层的 MLIR 文件一步步转换为适合 TPU 芯片（如 Sophgo BM1684/1684X 等）运行的二进制模型（bmodel），并支持调试、日志、性能分析等功能。

```python
输入：高层MLIR模型（如TOP方言）、配置参数（芯片型号/量化模式等）
  ↓
1. 高层优化：对MLIR进行形状推理、算子规范化（适配TPU方言）
  ↓
2. 硬件适配：将MLIR转换为目标芯片（如BM1684X）的TPU算子，融入量化配置
  ↓
3. 硬件级优化：层分组、核心并行、地址分配（最大化硬件利用率）
  ↓
4. 生成目标文件：转换为芯片可直接运行的bmodel格式
  ↓
5. 精度验证：对比转换前后的模型输出，确保精度达标
输出：可部署的bmodel、日志及中间文件
```

### 二、MLIR 优化与转换函数

#### top_opt_options

功能：用于生成 TPU-MLIR 工具链中对 TOP 方言进行高层优化的命令行选项，这些选项会被传递给 `tpuc-opt` 工具（TPU-MLIR 的核心优化工具），控制对 TOP 方言（TPU 专用的高层算子集合）的优化流程。

```python
def top_opt_options(add_postprocess: str = ""):
    # 1. 初始化优化选项列表，首先添加"--shape-infer"（形状推理）
    options = ["--shape-infer"]
    # 2. 若指定了后处理类型（如检测模型的NMS），添加对应的后处理选项
    if len(add_postprocess) > 0:
        options.extend([f"--add-postprocess=\"type={add_postprocess}\""])
    # 3. 添加通用优化选项：算子规范化和额外优化
    options.extend(["--canonicalize", "--extra-optimize"])
    # 4. 返回组装好的优化选项列表
    return options
```

#### mlir_opt_for_top

功能：`mlir_opt_for_top` 是 TPU-MLIR 工具链中对 TOP 方言 MLIR 文件进行优化的核心函数，它通过调用 `tpuc-opt` 工具（TPU-MLIR 的专用优化器），对输入的 TOP 方言 MLIR 文件执行一系列优化，并生成优化后的 MLIR 文件。同时支持日志级别控制和优化模式统计，方便调试和性能分析。

```python
def mlir_opt_for_top(mlirfile: str,
                     opt_mlirfile: str,
                     add_postprocess: str = "",
                     count_patterns: bool = False, 
                     log_level:str="normal"):
    # 1. 初始化命令列表：调用tpuc-opt工具，指定输入的MLIR文件
    cmd = ["tpuc-opt", mlirfile]
    
    # 2. 获取TOP方言的优化选项（复用之前的top_opt_options函数）
    options = top_opt_options(add_postprocess)
    cmd.extend(options)  # 将优化选项添加到命令中
    
    # 3. 指定优化后的输出MLIR文件路径
    cmd.extend(["-o", opt_mlirfile])
    
    # 4. 处理模式统计（记录哪些优化模式被应用）
    log_file = ""
    if count_patterns:
        log_file = "top_patterns.log"  # 日志文件保存路径
        # 添加调试选项：记录模式应用、方言转换、贪婪重写器的详细日志
        cmd.extend([
            "-debug-only=pattern-application,dialect-conversion,greedy-rewriter",
            "> {} 2>&1".format(log_file)  # 将日志重定向到文件
        ])
    
    # 5. 处理日志级别（控制输出详细程度）
    if log_level == "quiet":
        cmd.extend(["> /dev/null"])  # 安静模式：不输出任何日志
    elif log_level == "simple":
        cmd.insert(2, '--init="level=1"')  # 简单模式：只输出关键信息
    
    # 6. 执行命令（调用操作系统接口运行tpuc-opt）
    _os_system(cmd, log_level=log_level)
    
    # 7. 返回匹配的优化模式统计结果（从日志文件中解析）
    return get_matched_patterns(log_file)
```

#### top_to_tosa

功能：将高层的 TOP 方言转换为标准化的 TOSA 方言，是模型编译流程中的重要一步，目的是让模型能够适配更广泛的硬件平台，或为后续的硬件特定优化（如量化、算子融合）提供统一的基础。

```python
def top_to_tosa(top_mlir: str, tosa_mlir: str, includeWeight: bool = False):
    # 初始化命令列表，基础工具为 "tpuc-opt"，输入文件为 top_mlir
    cmd = ["tpuc-opt", top_mlir]

    # 构建转换参数：--convert-top-to-tosa，包含 includeWeight 的配置
    lower_param = "--convert-top-to-tosa=\"includeWeight="
    if includeWeight:
        lower_param += "True\""  # 如果需要包含权重，参数值设为 True
    else:
        lower_param += "False\""  # 否则设为 False

    # 扩展命令列表，添加转换参数、规范化处理和输出文件
    cmd.extend([lower_param, "--canonicalize", "-o", tosa_mlir])
    _os_system(cmd)  # 执行构建好的命令列表
```

#### tosa_to_llvm

功能：该函数用于将 TOSA 方言的 MLIR 文件 转换为 LLVM 目标文件（.obj），适配 CPU 执行（LLVM IR 是 CPU 可执行的底层中间表示）。

详细流程可见下：

```python
TOSA方言MLIR（高层抽象）
  ↓（mlir-opt：10步方言转换+优化）
LLVM方言MLIR（MLIR格式的LLVM兼容表示）
  ↓（mlir-translate：格式转换）
LLVM IR（LLVM原生中间表示）
  ↓（llc：编译为机器码）
LLVM目标文件（.obj，x86_64机器码，CPU可执行）
```

##### 阶段 1：MLIR 内部方言转换（`mlir-opt` 工具，输入 TOSA MLIR）

这一阶段通过 `mlir-opt` 的 `--pass-pipeline` 定义的转换流水线，将 TOSA 方言逐步转为 LLVM 兼容的 MLIR 方言（降低抽象级别，接近硬件执行逻辑）。共包含 10 个细分转换步骤：

##### 阶段 2：MLIR 转 LLVM IR（`mlir-translate` 工具）

- 工具：`mlir-translate --mlir-to-llvmir`
- 输入：阶段 1 输出的 “LLVM 方言 MLIR”（MLIR 格式，语法接近 LLVM IR）
- 输出：LLVM IR（文本格式，如 `%0 = add i32 %1, %2`，LLVM 的原生中间表示）
- 作用：将 ML 格式的 LLVM 方言转为 LLVM 原生的 IR 格式（LLVM 生态的 “通用中间表示”，后续编译依赖 LLVM 工具链）。

##### 阶段 3：LLVM IR 转目标文件（`llc` 工具）

- 工具：`llc -mtriple=x86_64-unknown-linux-gnu --filetype=obj`
- 输入：阶段 2 输出的 LLVM IR（文本）
- 输出：`objfile`（.obj 目标文件，二进制格式，包含 x86_64 架构的机器码）
- 关键参数：`-mtriple=x86_64-unknown-linux-gnu` 指定目标架构（x86_64 Linux），确保生成的机器码适配 CPU；`--filetype=obj` 指定输出为目标文件（而非汇编文本）。
- 作用：将 LLVM IR 编译为 CPU 可执行的机器码（二进制指令），最终生成可被链接器（如 `ld`）处理的目标文件。

```python
# TOSATOObj：函数功能标识（TOSA方言转LLVM目标文件）
def tosa_to_llvm(tosa_mlir: str, objfile: str):
    """
    将TOSA方言的MLIR文件转换为LLVM目标文件（.obj），适配CPU执行
    
    参数：
    - tosa_mlir：输入TOSA方言MLIR文件路径（高层通用方言，与硬件无关）
    - objfile：输出LLVM目标文件路径（.obj格式，可被CPU直接执行或链接为可执行程序）
    """
    # 1. 初始化命令列表：调用mlir-opt工具（MLIR优化器），指定输入TOSA MLIR文件
    # mlir-opt是MLIR官方优化工具，用于执行方言转换、优化等流水线操作
    cmd = ["mlir-opt", tosa_mlir]
    
    # 2. 定义TOSA到LLVM的转换参数（核心转换流水线）
    # lower_param是一串MLIR转换和优化的参数，通过"--pass-pipeline"指定完整转换流程
    lower_param = (
        # 开始定义模块级转换流水线（builtin.module表示对整个模块执行）
        "--pass-pipeline=\"builtin.module("
        # 阶段1：TOSA方言转底层方言（将TOSA算子转为Linalg、Arith等中间方言）
        "func.func(tosa-to-linalg-named, tosa-to-linalg, tosa-to-arith, tosa-to-tensor, tosa-to-scf), "
        # 阶段2：Tensor方言转Linalg（进一步降低抽象级别）
        "convert-tensor-to-linalg, "
        # 阶段3：Linalg转Affine（将线性代数算子转为仿射循环，接近硬件执行逻辑）
        "func.func(canonicalize, linalg-bufferize, convert-linalg-to-affine-loops, affine-loop-fusion, affine-simplify-structures, lower-affine), "
        # 阶段4：函数缓冲化（将SSA值转为内存缓冲，适配硬件内存模型）
        "func-bufferize, "
        # 阶段5：张量缓冲化（将张量操作转为内存操作）
        "func.func(tensor-bufferize, llvm-request-c-wrappers), "
        # 阶段6：算术和控制流方言转LLVM（Arith/Scf转LLVM兼容格式）
        "arith-expand, arith-bufferize, normalize-memrefs, convert-scf-to-cf, "
        # 阶段7：数学/算术/函数/控制流方言最终转LLVM（核心转换步骤）
        "convert-math-to-llvm, convert-arith-to-llvm, convert-func-to-llvm, convert-cf-to-llvm, "
        # 阶段8：内存引用转LLVM（MemRef方言转LLVM内存模型）
        "convert-bufferization-to-memref, memref-expand, expand-strided-metadata, finalize-memref-to-llvm, "
        # 阶段9：优化和合法化（确保LLVM IR可被导出为目标文件）
        "canonicalize, llvm-legalize-for-export, reconcile-unrealized-casts)\""
        # 阶段10：MLIR转LLVM IR（mlir-translate工具将MLIR转为LLVM IR）
        "| mlir-translate --mlir-to-llvmir "
        # 阶段11：LLVM IR转目标文件（llc工具编译为x86_64架构的.obj文件）
        "| llc -mtriple=x86_64-unknown-linux-gnu --filetype=obj"
    )
    
    # 3. 将转换参数和输出路径添加到命令中
    cmd.extend([lower_param, "-o", objfile])  # -o指定输出目标文件路径
    
    # 4. 执行命令（调用操作系统接口运行转换流水线）
    # _os_system是封装的系统命令执行函数（如调用subprocess执行cmd）
    _os_system(cmd)
```

#### mlir_lowering

功能：将输入的 `top_mlir`（高层 TOP 格式 MLIR）通过一系列编译优化（如量化、算子适配、硬件并行配置等），转换为 `tpu_mlir`（TPU 专用低层 MLIR），使其能在目标 TPU 上高效执行。

```python
def mlir_lowering(top_mlir: str,
                  tpu_mlir: str,
                  mode: str,
                  chip: str,
                  num_device: int = 1,
                  num_core: int = 1,
                  cali_table: str = None,
                  asymmetric: bool = False,
                  quantize_table: str = None,
                  customization_format: str = None,
                  fuse_preprocess: bool = False,
                  aligned_input: bool = False,
                  high_precision: bool = False,
                  do_winograd: bool = False,
                  q_group_size: int = 0,
                  q_symmetric: bool = False,
                  count_patterns: bool = False,
                  addr_mode: str = "auto",
                  mute: bool = False,
                  log_level: str = "normal",
                  matmul_perchannel: bool = False,
                  gelu_mode: str = "normal"):
    # 1. 统一模式参数格式（避免大小写不一致导致的错误，如"inference"转为"INFERENCE"）
    mode = mode.upper()
    
    # 2. 初始化命令列表：调用tpuc-opt工具，指定输入的TOP方言MLIR文件
    # top_mlir是待lowering的TOP方言MLIR文件（高层抽象，与硬件无关）
    cmd = ["tpuc-opt", top_mlir]
    
    # 3. 处理量化权重文件（仅当需要量化时生成）
    weight_name = ""  # 初始化权重文件名（默认空，不生成）
    if quantize_table:  # 如果指定了量化表（用于模型量化，减少精度损失）
        # 断言输出文件是.mlir格式（避免路径错误，确保权重文件路径正确生成）
        assert (tpu_mlir.endswith(".mlir"))
        # 生成权重文件路径：与输出TPU MLIR同目录，名称为"输出文件名_qtable_weights.npz"
        # 例如tpu_mlir为"model.tpu.mlir"，则权重文件为"model.tpu_qtable_weights.npz"
        weight_name = tpu_mlir[:-len(".mlir")] + "_qtable_weights.npz"
    
    # 4. 获取TPU lowering选项（根据硬件和配置生成lowering规则）
    # lowering_options函数会根据参数生成适配目标芯片的lowering规则
    # 例如：芯片型号（chip）决定算子实现方式，量化参数（asymmetric）决定量化逻辑
    options = lowering_options(mode,
                                chip,
                                num_device,
                                num_core,
                                cali_table,
                                asymmetric,
                                quantize_table,
                                weight_name,
                                customization_format,
                                fuse_preprocess,
                                aligned_input,
                                high_precision,
                                do_winograd,
                                q_group_size,
                                q_symmetric,
                                addr_mode,
                                matmul_perchannel,
                                gelu_mode)
    cmd.extend(options)  # 将lowering选项添加到命令中，指导tpuc-opt执行lowering
    
    # 5. 指定lowering后的输出TPU MLIR文件路径
    # tpu_mlir是lowering后的TPU方言MLIR文件（底层抽象，与硬件相关，可直接在TPU上执行）
    cmd.extend(["-o", tpu_mlir])
    
    # 6. 处理模式统计（记录lowering过程中应用的优化模式）
    log_file = ""  # 初始化日志文件路径（默认空，不记录）
    if count_patterns:  # 如果需要统计lowering中的优化模式（如调试lowering是否符合预期）
        log_file = "tpu_patterns.log"  # 日志文件固定保存路径
        # 添加调试选项：记录模式应用、方言转换、贪婪重写器的日志（与mlir_opt_for_top逻辑一致）
        cmd.extend(["--debug-only=pattern-application,dialect-conversion,greedy-rewriter", 
                   "> {} 2>&1".format(log_file)])
    
    # 7. 处理日志级别（控制输出详细程度，适配不同场景）
    if log_level == "quiet":  # 安静模式：不输出任何日志
        cmd.extend(["> /dev/null"])
    elif log_level == "only-layer-group":  # 仅输出层分组日志（用于调试硬件资源分配）
        # --debug-only指定只输出层分组相关日志（层分组是TPU并行计算的基础）
        cmd.extend(["--debug-only=layer-group,LayerGroupUtil"])
        # --init="level=2"设置日志级别2（输出较详细的层分组信息）
        cmd.insert(2, '--init="level=2"')
    elif log_level == "simple":  # 简单模式：只输出关键信息（如lowering开始/结束）
        cmd.insert(2, '--init="level=1"')  # 日志级别1（仅关键信息）
    
    # 8. 执行命令（调用操作系统接口运行tpuc-opt，执行lowering）
    # mute控制是否静音（覆盖log_level，强制不输出），log_level控制输出详细程度
    _os_system(cmd, mute=mute, log_level=log_level)
    
    # 9. 返回lowering过程中的优化模式统计结果（从日志文件中解析）
    # 例如：哪些算子被成功lowering到TPU，哪些优化规则被应用
    return get_matched_patterns(log_file)
```

6.mlir_to_model()

功能：该函数是将 TPU 方言 MLIR 转换为最终可执行模型（如 BModel）的核心入口，负责构建转换命令并配置关键参数。

```python
def mlir_to_model(
    *,
    tpu_mlir: str,
    bmodel_path: str,
    final_mlir: str,
    dynamic: bool = False,
    quant_input: bool = False,
    quant_output: bool = False,
    quant_input_list: str = "",
    quant_output_list: str = "",
    disable_layer_group: bool = False,
    opt: int = 2,
    merge_weight: bool = False,
    op_divide: bool = False,
    embed_debug_info: bool = False,
    group_by_cores: str = "auto",
    model_version: str = "",
    count_patterns: bool = False,
    compress_mode: str = "none",
    future_update_rank: int = 0,
    future_update_list: str = "",
    debug_info: str = "",
    log_level: str = "normal",
    trunc_final: list = None,
    command_mem: dict = None,
    quant_output_bf16: bool = False,
    opt_post_processor: bool = False,
    gdma_check: bool = True,
    lg_debugger: bool = False,
):
    """
    将TPU方言MLIR转换为目标硬件可执行模型（如BModel）
    
    核心逻辑：
    - 构建tpuc-opt工具的转换命令，集成量化、优化、层分组等配置
    - 生成最终模型文件（bmodel_path）和中间MLIR文件（final_mlir）
    - 记录转换过程中的命令（用于调试和追溯）
    """
    # 1. 初始化命令记录字典（若未传入则创建空字典）
    if command_mem is None:
        command_mem = {}  # 用于存储转换过程中执行的命令（后续可被外部记录）
    
    # 2. 初始化转换命令：调用tpuc-opt工具，指定输入的TPU方言MLIR文件
    # tpuc-opt是TPU专用的MLIR优化工具，tpu_mlir是已lowering的TPU方言MLIR（中间产物）
    cmd = ["tpuc-opt", tpu_mlir]
    
    # 3. 配置调试命令参数（传递调试信息，如特定模块的日志开关）
    debug_cmd = f"--debug_cmd={debug_info}"  # 将调试信息封装为命令行参数
    
    # 4. 生成TPU优化选项（量化相关配置）
    # tpu_opt_options函数根据参数生成量化输入/输出的配置选项
    options = tpu_opt_options(
        quant_input,  # 是否量化输入
        quant_output,  # 是否量化输出
        quant_input_list,  # 指定需要量化的输入列表
        quant_output_list,  # 指定需要量化的输出列表
        quant_output_bf16=quant_output_bf16  # 是否用BF16格式量化输出
    )
    cmd.extend(options)  # 将量化选项添加到命令中，指导tpuc-opt执行量化逻辑
```

## 8.mlir_deploy.py

### 一、整体功能

本文件是 TPU-MLIR 工具链中模型部署的主入口脚本，主要用于将 MLIR 文件转换为可在 TPU 芯片上运行的 bmodel 文件，并支持推理、验证、量化、调试等功能。

##### 文件整体结构与主流程

- 依赖导入：导入了大量 utils 下的工具函数、类，以及 numpy、argparse、os 等常用库。
- 核心类 DeployTool：封装了模型转换、推理、验证、输入准备等主要流程。
- 主函数入口：解析命令行参数，实例化 DeployTool，依次执行 lowering、build_model、cleanup 等步骤。

### 二、 主函数流程

1. 参数解析：使用 argparse 解析命令行参数，支持模型路径、芯片类型、量化方式、输入输出、调试选项等几十个参数。
2. 参数合法性检查：对废弃参数、冲突参数进行检查。
3. 实例化 DeployTool：传入参数，初始化部署工具。
4. lowering：调用 lowering，将 mlir 转为 tpu/tosa mlir。
5. build_model：调用 build_model，将 tpu/tosa mlir 编译为 bmodel。
6. cleanup：非 debug 模式下清理临时文件。
7. pattern 检查：如果指定了 patterns_count，检查优化 pattern 是否达到预期次数。
8. 主要函数/类详细解释

```python
_if_ __name__ == '__main__':
    logger.info("TPU-MLIR {}".format(pymlir.__version__))
    parser = argparse.ArgumentParser()
    _# yapf: disable_
    _# ========== Basic Options ===========_
    parser.add_argument("--mlir", _required_=True, _help_="top mlir from model_transform.py")
    ... #参数解析，同上
# yapf: enable  # 启用yapf代码格式化（确保代码风格一致）
    # 1. 解析命令行参数（从用户输入中提取配置，如模型路径、量化模式等）
    args = parser.parse_args()  # parser是预定义的参数解析器，args存储所有参数值
    
    # 2. 处理废弃参数（提示用户使用新参数，保证兼容性）
    # 若用户使用了--io_alone（旧参数），提示用--addr_mode io_alone（新参数）
    deprecated_option(args.io_alone, "DEPRECATED, please use --addr_mode io_alone")
    # 若用户使用了--ignore_f16_overflow（旧参数），提示用--high_precision（新参数）
    deprecated_option(args.ignore_f16_overflow, "DEPRECATED, please use --high_precision")
    
    # 3. 量化参数合法性校验（防止矛盾配置，保证量化逻辑正确）
    # 场景1：若启用BF16量化输出（quant_output_bf16=True）
    if args.quant_output_bf16:
        # 禁止同时设置全局量化模式为BF16（需用--quant_output替代）
        if args.quantize == "BF16":
            RuntimeError("quantize is BF16, please use --quant_output instead")
        # 禁止同时启用普通量化输出（quant_output与quant_output_bf16互斥）
        if args.quant_output:
            RuntimeError("quant_output and quant_output_bf16 can't both be true")
    
    # 4. 输入格式与预处理参数校验（确保输入处理逻辑一致）
    # 场景1：若自定义格式为YUV（图像格式），强制启用输入对齐（提升硬件访问效率）
    if args.customization_format.startswith("YUV"):
        args.aligned_input = True  # 自动设置aligned_input=True（无需用户手动配置）
    # 场景2：若未融合预处理（fuse_preprocess=False），禁止设置自定义格式
    # 原因：自定义格式（如YUV转RGB）需依赖预处理逻辑，未融合时无法生效
    if not args.fuse_preprocess and args.customization_format:
        # 断言失败并提示错误（0 and "..." 等价于False，触发assert错误）
        assert (0 and "Error! If not fuse_preprocess, customization_format shouldn't be set.")
    
    # 5. 初始化部署工具（封装所有部署流程，如模型lowering、构建、验证）
    tool = DeployTool(args)  # 将解析后的参数传入工具类，初始化部署环境
    
    # 6. 执行模型lowering（核心步骤1：将高层MLIR转为硬件相关MLIR）
    # 若启用"不生成BModel"模式（not_gen_bmodel=True，仅调试lowering过程）
    if args.not_gen_bmodel:
        tool.do_validate = False  # 关闭验证（无需验证未完成的模型）
    # 调用tool.lowering()执行lowering（如TOP方言→TPU方言），返回lowering过程的优化模式统计
    lowering_patterns = tool.lowering()
    
    # 7. 生成目标模型（核心步骤2：将硬件相关MLIR转为可执行模型，如BModel）
    # 若仅lowering而不生成BModel，直接退出（调试场景）
    if args.not_gen_bmodel:
        exit(0)
    # 调用tool.build_model()生成BModel，返回模型构建过程的优化模式统计
    tpu_patterns = tool.build_model()
    
    # 8. 清理临时文件（默认启用，调试模式保留）
    if not args.debug:  # 非调试模式（生产环境）
        tool.cleanup()  # 删除中间产物（如临时MLIR、日志文件），节省磁盘空间
    
    # 9. 统计并验证优化模式应用次数（确保优化按预期生效）
    # 合并lowering和构建过程的所有优化模式统计（键为模式名称，值为应用次数）
    total_patterns = {** lowering_patterns, **tpu_patterns}
    # 若指定了模式次数校验（patterns_count非空，如{"conv_fuse": 5}）
    if args.patterns_count:
        # 遍历所有需要校验的模式
        for k, v in args.patterns_count.items():
            # 断言模式存在且应用次数符合预期（否则报错并提示具体差异）
            assert k in total_patterns and v == total_patterns[k], \
            "The number of times {} was applied does not meet the requirements. Expected {}, got {}" \
            .format(k, v, total_patterns.get(k))
```

### 三、 辅助函数/核心类

#### 辅助函数：

##### str2list(v)

- 功能：将逗号分隔的字符串转为字符串列表，并去除空字符串。
- 原理：字符串分割 +strip+ 去空。
- 用途：用于 argparse 解析多输入文件参数。

##### getCustomFormat(pixel_format, channel_format)

- 功能：根据像素格式和通道格式，返回自定义格式字符串（如 RGB_PLANAR、BGR_PACKED 等）。
- 原理：条件判断映射。
- 用途：用于 fuse_preprocess 时，确定输入图片的格式。

#### 核心类 DeployTool：

##### _init__(self, args)

- 功能：初始化部署工具，解析参数，设置各种路径、前缀、状态，准备输入数据，初始化文件记录器。
- 原理：参数赋值、路径拼接、状态判断、目录创建、调用 _prepare_input_npz。_
- 用途：为后续模型转换、推理、验证等流程做准备。

##### cleanup(self)

- 功能：清理临时文件。
- 原理：调用 file_clean 工具函数。
- 用途：部署结束后清理环境。

##### pack_profile(self)

- 功能：打包 profile 相关文件（mlir、onnx、tpu.mlir 等）到一个目录，便于调试和归档。
- 原理：shutil 复制文件，调用 mlir2onnx 转换。
- 用途：便于后续分析和复现。

##### lowering(self)

- 功能：将 top-level mlir 降级为 tpu/tosa mlir，支持 cpu/tpu 两种芯片。
- 原理：

  - cpu：调用 top_to_tosa，再替换 func 名称，生成 tosa mlir。
  - tpu：调用 mlir_lowering（来自 mlir_shell.py），生成 tpu.mlir，并可选进行验证。
- 用途：模型转换流程的第一步。

##### _prepare_input_npz(self)

- 功能：准备推理输入数据（npz/npy/image），并生成参考输出（ref_npz）。
- 原理：

  - 判断输入类型，支持 npz、npy、图片等。
  - 支持 fuse_preprocess，自动推断格式。
  - 支持自动生成参考输出（top_outputs）。
  - 支持动态层输出数据 dump。
- 用途：为模型推理和验证准备输入和参考输出。

##### validate_tpu_mlir(self)

- 功能：对 tpu.mlir 进行推理，并与参考输出对比，支持 cuda 验证。
- 原理：

  - 调用 mlir_inference 进行推理。
  - 调用 f32_blobs_compare 进行输出对比。
  - 支持 cuda 推理和对比。
- 用途：验证 tpu.mlir 的正确性。

##### build_model(self)

- 功能：将 tpu.mlir/tosa.mlir 编译为 bmodel 文件，并可选进行推理验证。
- 原理：

  - cpu：调用 tosa_to_llvm。
  - tpu：调用 mlir_to_model（来自 mlir_shell.py），生成 bmodel，并可选进行推理验证。
  - 记录生成的文件和命令。
- 用途：模型转换流程的第二步，生成最终可部署的模型文件。

##### revise_MaskRCNN_tpu_ref(self)

- 功能：修正 MaskRCNN 的 tpu 参考输出，保证 key 顺序一致。
- 原理：遍历 key，重新映射。
- 用途：特殊模型的兼容性处理。

##### validate_model(self)

- 功能：对 bmodel 进行推理，并与参考输出或 tpu 输出对比。
- 原理：

  - 调用 model_inference 进行推理。
  - MaskRCNN 特殊处理。
  - 根据模型状态选择对比对象（ref_npz 或 tpu_npz）。
  - 调用 f32_blobs_compare 进行输出对比。
- 用途：验证最终 bmodel 的正确性。

### 四、 重要代码解析

#### lowering(self)

- 原理：cpu 走 tosa_to_llvm，tpu 走 mlir_to_model，生成 bmodel 并可选验证。

##### CPU 分支：

- 核心操作：调用 `top_to_tosa` 工具（可跳转到 7.2.3）将输入的 MLIR 转换为 TOSA dialect 格式。
  TOSA（Tensor Operator Set Architecture）是一种标准化的机器学习算子集中间表示，适合在 CPU 等通用硬件上进行优化和执行。
- 辅助处理：替换函数名（`main`→`model`）是为了统一模型入口函数的命名规范，便于后续流程识别。

```python
if self.chip == 'cpu':
    # 将输入的 MLIR 文件转换为 TOSA  dialect 格式，保存为临时文件
    top_to_tosa(self.mlir_file, "tmp_tosa.mlir", self.includeWeight)
    # 定义输出的 TOSA MLIR 文件名（用前缀+固定后缀命名）
    self.tosa_mlir = "{}_tosa.mlir".format(self.prefix)
    # 读取临时文件内容，将函数名从 "main" 替换为 "model"（统一命名规范）
    with open("tmp_tosa.mlir", "r", encoding="utf-8") as file:
        content = file.read()
    content = content.replace("main", "model")
    # 写入最终的 TOSA MLIR 文件，并删除临时文件
    with open(self.tosa_mlir, "w", encoding="utf-8") as file:
        file.write(content)
    delete_file("tmp_tosa.mlir")
    return {}
```

##### 非 CPU 分支：

- 核心操作：调用 `mlir_lowering` 工具（可跳转到 7.2.5）将 MLIR lowering 为 TPU 专用格式。
  “lowering” 是编译领域的术语，指将高层中间表示（接近算法逻辑）转换为低层中间表示（接近硬件执行逻辑），以便进行硬件特定的优化（如算子适配、内存布局调整等）。
- 关键参数解析：

  - 量化相关参数（`quantize`、`cali_table` 等）：TPU 通常擅长整数计算，量化能减少计算量和内存占用；
  - 硬件配置（`num_device`、`num_core`）：适配多设备 / 多核心的并行执行；
  - 优化选项（`fuse_preprocess`、`do_winograd`）：融合算子减少数据搬运、用 Winograd 算法加速卷积，提升执行效率。
- 验证步骤：`validate_tpu_mlir` 用于检查 lowering 后的 MLIR 是否符合 TPU 执行要求（如算子支持、格式正确等），避免部署时出错。

#### build_model

- ```
  功能：构建目标芯片可执行的模型（如BModel），包含模型转换、验证和文件记录。
  ```
- ```
  核心逻辑：
  ```

  - 针对 CPU：将 TOSA 方言 MLIR 转为 LLVM 方言（适配 CPU 执行），调用 tosa_to_llvm()函数（可看 7.2.4）。
  - 针对非 CPU：调用 mlir_to_model 核心函数：将 TPU 方言 MLIR 转换为最终模型。
  - 自动完成模型验证（可选）和文件记录（保存中间产物和命令）。

```python
def build_model(self):

    try:
        # 1. 根据目标芯片类型选择构建逻辑
        if self.chip == "cpu":
            # 1.1 CPU场景：将TOSA方言MLIR转换为LLVM方言MLIR（CPU可执行）
            # tosa_to_llvm：专用转换函数，TOSA是高层通用方言，LLVM是CPU底层方言
            tosa_to_llvm(self.tosa_mlir, self.bmodel_path)
            return {}  # CPU场景无优化模式统计，返回空字典
        
        else:
            # 1.2 非CPU场景（如TPU）：生成目标芯片可执行的模型（如BModel）
            command_mem = {}  # 用于记录构建过程中执行的命令（后续保存）
            
            # 调用mlir_to_model核心函数：将TPU方言MLIR转换为最终模型（如BModel）
            # 传入大量配置参数，控制模型转换、优化、量化等逻辑
            patterns = mlir_to_model(
                tpu_mlir=self.tpu_mlir,  # 输入：TPU方言MLIR文件（已lowering的中间产物）
                bmodel_path=self.bmodel_path,  # 输出：最终可执行模型路径（如BModel）
                final_mlir=self.final_mlir,  # 输出：最终优化后的MLIR文件（用于调试）
                dynamic=self.dynamic,  # 是否支持动态形状输入
                quant_input=self.quant_input,  # 是否量化输入
                quant_output=self.quant_output,  # 是否量化输出
                quant_input_list=self.quant_input_list,  # 指定需要量化的输入列表
                quant_output_list=self.quant_output_list,  # 指定需要量化的输出列表
                disable_layer_group=self.disable_layer_group,  # 是否禁用层分组（TPU并行计算的基础）
                opt=self.opt,  # 是否启用优化（如算子融合、常量折叠）
                merge_weight=self.merge_weight,  # 是否合并权重（减少内存占用）
                op_divide=self.op_divide,  # 是否拆分大算子（适配硬件计算能力）
                embed_debug_info=self.embed_debug_info,  # 是否嵌入调试信息（便于定位问题）
                group_by_cores=self.group_by_cores,  # 是否按核心分组（优化多核心并行）
                model_version=self.model_version,  # 模型版本（用于兼容性控制）
                # 是否统计优化模式应用情况（根据self.patterns_count开关决定）
                count_patterns=True if self.patterns_count else False,
                compress_mode=self.compress_mode,  # 模型压缩模式（如权重压缩）
                future_update_rank=self.future_update_rank,  # 后续更新的秩（预留功能）
                future_update_list=self.future_update_list,  # 后续更新的算子列表（预留功能）
                debug_info=self.debug_cmd,  # 调试命令（传递给底层工具）
                trunc_final=self.trunc_final,  # 是否截断最终MLIR（简化输出）
                command_mem=command_mem,  # 传入命令记录字典（底层会填充执行过的命令）
                quant_output_bf16=self.quant_output_bf16,  # 是否用BF16量化输出（平衡精度和性能）
                opt_post_processor=self.opt_post_processor,  # 后处理优化器（自定义优化逻辑）
                gdma_check=self.gdma_check,  # 是否启用GDMA（全局DMA）检查（内存访问安全）
                lg_debugger=self.lg_debugger  # 层分组调试器（调试多核心分组逻辑）
            )
            
            # 2. 模型验证（可选，确保构建的模型可用）
            # 若未跳过验证且启用验证开关，则执行验证
            if not self.skip_validation and self.do_validate:
                self.validate_model()  # 调用验证方法（如检查输出形状、精度是否符合预期）
            
            return patterns  # 返回优化模式统计结果（供调试分析）
    
    # 2. 最终处理：无论构建是否成功，记录关键文件和命令（便于追溯和调试）
    finally:
        # 仅非CPU场景需要记录（CPU场景产物简单，无需详细记录）
        if self.chip != "cpu":
            # 2.1 记录构建过程中的关键文件（中间产物、输出模型等）
            self.file_recorder.add_file(
                bmodel=self.bmodel_path,  # 最终生成的BModel路径
                tensor_location=f"{self.bmodel_path}.json",  # 张量位置信息文件
                final_mlir=self.final_mlir,  # 最终优化后的MLIR文件
                tpu_mlir=self.tpu_mlir,  # TPU方言MLIR（中间产物）
                tpu_opt_mlir=self.tpu_opt_mlir,  # 优化后的TPU方言MLIR
                tpu_output=self.tpu_npz,  # TPU权重文件（NPZ格式）
                bmodel_output=self.model_npz,  # BModel输出结果（NPZ格式，用于验证）
                context_dir=self.context_dir,  # 上下文目录（存放临时文件）
                layer_group_cache=f"{self.prefix}.layer_group_cache.json",  # 层分组缓存（加速下次构建）
            )
            
            # 2.2 记录构建过程中执行的命令（如mlir_to_model调用的底层工具命令）
            self.file_recorder.add_command(** command_mem)  # command_mem由mlir_to_model填充
            
            # 2.3 将记录的文件和命令写入磁盘（持久化保存）
            self.file_recorder.dump()
```

#### _prepare_input_npz

- 功能：该函数是模型验证前的输入数据准备核心函数，负责处理测试输入（图片、NPZ、NPY 等）、生成模型可接收的输入格式（NPZ），并根据需要生成参考输出（用于后续模型验证）。
- 核心逻辑：

  - 处理多种输入类型（图片、NPZ、NPY），适配模型输入要求。
  - 支持预处理融合（fuse_preprocess），自动处理图片预处理（如 resize、格式转换）。
  - 生成输入 NPZ 文件（供模型推理使用）和参考输出（供验证模型正确性）。

```python
def _prepare_input_npz(self):
    # 1. 初始化验证开关：根据测试输入数量决定是否执行验证（有输入才验证）
    num_inputs = len(self.test_input)  # self.test_input：测试输入文件列表（如图片、NPZ路径）
    self.do_validate = (0 < num_inputs)  # 若输入数量>0，则开启验证（do_validate设为True）
    
    # 2. 无输入时的处理（不执行验证，仅初始化预处理格式）
    if not self.do_validate:  # 若无需验证（无输入）
        if self.customization_format == '':  # 若未指定自定义格式
            ppa = preprocess()  # 初始化预处理工具
            input_op = self.module.inputs[0].op  # 获取模型第一个输入算子（用于加载预处理配置）
            ppa.load_config(input_op)  # 从输入算子加载预处理配置（如像素格式、通道格式）
            if ppa.has_pre:  # 若存在预处理逻辑
                # 生成自定义格式（基于预处理的像素格式和通道格式）
                self.customization_format = getCustomFormat(ppa.pixel_format,
                                                            ppa.channel_format)
        return  # 无输入时直接返回，不继续处理
    
    # 3. 初始化输入存储变量（用于保存模型可接收的输入数据）
    self.tpu_inputs = {}  # 存储模型实际输入数据（键：输入名称，值：numpy数组）
    gen_input_f32 = {}  # 存储用于生成参考输出的输入数据（需保持float32格式）
    # 决定是否生成参考输出：若未指定参考输出文件（ref_npz为空），则需要生成
    gen_ref = True if len(self.ref_npz) == 0 else False
    
    # 4. 处理融合预处理场景（fuse_preprocess=True时，输入为原始图片）
    if self.fuse_preprocess:
        # 断言输入为图片（融合预处理仅支持原始图片，需自动处理预处理）
        assert (self.test_input[0].endswith(('.jpg', '.jpeg', '.png')))
    
    # 5. 按输入类型处理数据（分NPZ、图片、NPY三类输入）
    # 场景1：单输入且为NPZ文件（直接加载其中的所有输入数据）
    if num_inputs == 1 and self.test_input[0].endswith(".npz"):
        x = np.load(self.test_input[0])  # 加载NPZ文件（包含多个输入张量）
        for name in x.files:  # 遍历NPZ中的所有张量
            self.tpu_inputs[name] = x[name]  # 存入tpu_inputs（模型输入）
        if gen_ref:  # 若需要生成参考输出
            gen_input_f32 = self.tpu_inputs  # 直接使用NPZ中的数据作为参考输入
    
    # 场景2：多输入或非NPZ输入（图片、NPY）
    else:
        # 断言输入数量与模型输入数量一致（避免输入不匹配）
        assert (len(self.test_input) == len(self.module.inputs))
        # 遍历输入文件和模型输入算子（一一对应处理）
        for infile, op in zip(self.test_input, self.module.inputs):
            # 子场景2.1：输入为图片（.jpg/.jpeg/.png）
            if infile.endswith(('.jpg', '.jpeg', '.png')):
                ppa = preprocess()  # 初始化预处理工具（处理图片到模型输入的转换）
                input_op = op.op  # 获取当前输入对应的模型算子（用于获取输入形状、预处理配置）
                input_shape = [Operation.shape(input_op)]  # 获取模型输入形状（如[1, 3, 224, 224]）
                ppa.load_config(input_op)  # 从算子加载预处理配置（如resize尺寸、像素格式）
                
                # 若启用预处理融合（fuse_preprocess=True）：将图片预处理逻辑融入模型
                if self.fuse_preprocess:
                    # 若未指定自定义格式，根据预处理配置生成（如像素格式RGB、通道格式NCHW）
                    if self.customization_format == '':
                        self.customization_format = getCustomFormat(
                            ppa.pixel_format, ppa.channel_format)
                    # 构建预处理配置（传递给模型，用于融合预处理逻辑）
                    config = {
                        'input_shapes': input_shape,  # 模型输入形状
                        'resize_dims': ppa.resize_dims,  # 缩放尺寸（如[224, 224]）
                        'fuse_pre': True,  # 标记启用预处理融合
                        'keep_aspect_ratio': ppa.keep_aspect_ratio,  # 是否保持宽高比（避免变形）
                        'keep_ratio_mode': ppa.keep_ratio_mode,  # 保持比例的模式（如pad填充）
                        "pixel_format": ppa.pixel_format,  # 像素格式（如RGB）
                        'customization_format': self.customization_format,  # 自定义格式
                        'aligned': self.aligned_input,  # 输入是否对齐（内存对齐，提升效率）
                        'pad_type': ppa.pad_type,  # 填充类型（如常数填充）
                        'pad_value': ppa.pad_value,  # 填充值（如0）
                        'chip': self.chip,  # 目标芯片（预处理逻辑需适配硬件）
                    }
                    logger.info("Add preprocess, set the following params:")  # 日志输出预处理配置
                    ppb = preprocess()  # 初始化预处理执行器
                    ppb.config(** config)  # 应用配置
                    # 执行预处理并保存结果：键为"输入名称_raw"（标记为原始图片处理后的数据）
                    self.tpu_inputs[op.name + "_raw"] = ppb.run(infile)
                    # 定义输入NPZ文件路径（模型推理时加载）
                    self.in_f32_npz = self.module_name + "_in_ori.npz"
                
                # 若不启用预处理融合：单独执行预处理，结果作为模型输入
                else:
                    # 执行预处理（如resize、归一化），结果存入tpu_inputs（键为预处理工具的输入名称）
                    self.tpu_inputs[ppa.input_name] = ppa.run(infile)
                
                # 若需要生成参考输出：将预处理后的结果作为参考输入
                if gen_ref:
                    gen_input_f32[ppa.input_name] = ppa.run(infile)
            
            # 子场景2.2：输入为NPY文件（单张量文件）
            elif infile.endswith(".npy"):
                data = np.load(infile)  # 加载NPY文件（单输入张量）
                self.tpu_inputs[op.name] = data  # 存入tpu_inputs（键为模型输入算子名称）
                if gen_ref:  # 若需要生成参考输出
                    gen_input_f32[op.name] = self.tpu_inputs  # 存入参考输入
            
            # 子场景2.3：不支持的输入类型（报错提示）
            else:
                raise TypeError("Unsupport input type *{}".format(os.path.splitext(infile)))
    
    # 6. 输入对齐检查（仅支持预处理融合时启用输入对齐）
    if self.aligned_input and not self.fuse_preprocess:
        # 若启用了输入对齐（aligned_input=True）但未融合预处理，抛出错误（当前不支持该组合）
        raise RuntimeError(
            "Not support now, aligned_input requires fuse_preprocess to be set to True.")
    
    # 7. 保存模型输入为NPZ文件（供后续推理使用）
    np.savez(self.in_f32_npz, **self.tpu_inputs)
    
    # 8. 生成参考输出（供模型验证时对比）
    if gen_ref:
        # 定义参考输入NPZ路径
        gen_in_f32_npz = self.module_name + '_in_f32.npz'
        file_mark(gen_in_f32_npz)  # 标记文件（可能用于缓存或版本管理）
        np.savez(gen_in_f32_npz,** gen_input_f32)  # 保存参考输入
        # 定义参考输出NPZ路径（后续验证时用模型输出与其对比）
        self.ref_npz = self.module_name + "_top_outputs.npz"
        show_fake_cmd(gen_in_f32_npz, self.mlir_file, self.ref_npz)  # 日志输出参考生成命令（伪命令，用于调试）
        # 调用mlir_inference执行推理，生成参考输出（基于原始MLIR文件，确保参考的正确性）
        top_outputs = mlir_inference(gen_input_f32, self.mlir_file)
        np.savez(self.ref_npz, **top_outputs)  # 保存参考输出
```

#### validate_model()

- 功能：该函数是模型验证流程的核心，负责对比目标模型（如 BModel）的输出与参考输出（如原始 MLIR 推理结果），验证模型正确性。
- 核心逻辑：

  - 执行目标模型推理，获取实际输出。
  - 针对特殊模型（如 MaskRCNN）修正参考输出格式。
  - 根据模型状态（如量化/非量化）调用对应对比函数，检查输出精度。

```python
def validate_model(self):

    # 1. 输出验证命令日志（伪命令，用于调试和流程追溯）
    # 显示输入文件、目标模型、输出文件、对比范围等关键信息（非实际执行命令）
    show_fake_cmd(
        self.in_f32_npz,  # 输入数据NPZ文件（模型推理的输入）
        self.bmodel_path,  # 目标模型路径（如BModel，待验证的模型）
        self.model_npz,  # 目标模型输出的NPZ文件（存储实际推理结果）
        self.compare_all  # 是否对比所有中间输出（True：全量对比；False：仅对比最终输出）
    )
    
    # 2. 执行目标模型推理，获取实际输出
    # 调用model_inference加载目标模型，用准备好的输入（self.tpu_inputs）执行推理
    model_outputs = model_inference(
        self.tpu_inputs,  # 输入数据字典（键：输入名称，值：numpy数组）
        self.bmodel_path,  # 目标模型路径（如BModel）
        self.compare_all  # 是否返回所有中间输出（用于全量对比）
    )
    
    # 3. 保存目标模型的输出结果（便于后续调试和二次对比）
    np.savez(self.model_npz, **model_outputs)  # 将推理输出存入NPZ文件
    
    # 4. 特殊模型适配：修正MaskRCNN的参考输出格式（若启用）
    # MaskRCNN等检测模型输出格式特殊（如包含框、掩码等），需统一参考输出与实际输出的格式
    if self.enable_maskrcnn:
        self.revise_MaskRCNN_tpu_ref()  # 调用修正方法（如调整张量维度、数据类型）
    
    # 5. 根据模型状态选择对比逻辑（量化模型与非量化模型的对比策略不同）
    # 场景1：模型状态为"TOP_QUANTIZED"（量化后的TOP方言模型）
    if self.state == "TOP_QUANTIZED":
        # 调用f32_blobs_compare对比目标输出与量化参考输出
        # 参数说明：
        # - self.model_npz：目标模型输出（实际推理结果）
        # - self.ref_npz：量化模型的参考输出（如原始MLIR量化推理结果）
        # - self.correctness：精度阈值（如允许的最大误差）
        # - self.excepts：例外算子列表（不参与对比的算子输出）
        # - True：启用详细日志（输出对比结果）
        # - self.fazzy_match：是否启用模糊匹配（允许微小误差，适配量化模型）
        f32_blobs_compare(
            self.model_npz,
            self.ref_npz,
            self.correctness,
            self.excepts,
            True,
            self.fazzy_match
        )
    
    # 场景2：非量化模型（如原始TPU方言模型）
    else:
        # 对比目标输出与TPU参考输出（self.tpu_npz为TPU方言MLIR的推理结果）
        # 无需模糊匹配（非量化模型精度要求更高）
        f32_blobs_compare(
            self.model_npz,
            self.tpu_npz,
            self.correctness,
            self.excepts,
            True
        )


### 核心逻辑总结
1. **推理与输出保存**：通过 `model_inference` 执行目标模型推理，将输出存入 NPZ 文件（便于追溯）。
2. **特殊模型适配**：针对 MaskRCNN 等特殊模型修正参考输出格式，避免因格式差异导致的误判。
3. **差异化对比**：
   - 量化模型（`TOP_QUANTIZED`）：启用 `fazzy_match` 模糊匹配（允许量化引入的微小误差），对比目标输出与量化参考输出。
   - 非量化模型：严格对比目标输出与 TPU 方言推理结果（无模糊匹配，要求高精度一致）。

该函数是模型部署的“质量把关”环节，通过标准化对比流程确保目标模型的输出符合预期，避免因优化、下转等步骤引入精度损失或功能错误。
```

## 9.run_calibration.py

该文件是 TPU-MLIR 工具链中模型量化校准的核心脚本，用于将浮点模型（MLIR 格式）通过量化校准转换为适配 TPU 硬件的定点模型。核心功能是：根据输入的模型、数据集和配置参数，自动完成数据选择、激活值分析、量化参数计算（阈值 / 量化表），并支持 SmoothQuant、权重均衡等量化优化技术，最终生成可用于 TPU 部署的量化表。

### 一、代码逻辑与分步功能

代码按 “参数解析 → 数据准备 → 预处理 → 核心量化流程 → 优化与适配” 的顺序执行，每一步的具体功能如下：

#### 初始化与参数解析

- 功能：定义并解析命令行参数，为后续流程提供配置依据。
- 具体操作：

  - 通过 `argparse.ArgumentParser` 定义参数（如模型路径 `mlir_file`、数据集 `--dataset`、校准方法 `--cali_method` 等）。
  - 参数涵盖 “输入输出”（如 `--dataset` 指定校准数据集、`-o` 指定量化表输出路径）、“量化策略”（如 `-``-search` 选择量化方案）、“优化选项”（如 `--sq` 启用 SmoothQuant）等。
  - 通过 `args = parser.parse_args()` 解析实际运行时传入的命令行参数（例如用户执行 `run_calibration yolov5s.mlir --dataset ../COCO2017` 时的参数）。

#### 数据选择与准备

- 功能：从数据集筛选用于校准和调优的样本，确保量化参数的可靠性。
- 具体操作：

  - 校准数据选择：通过 `DataSelector(args.dataset, args.input_num, args.data_list)` 从 `--dataset` 指定的数据集（或 `--data_list` 指定的文件）中选择 `--input_num` 个样本（如 100 张图片），存储在 `selector` 中。
  - 调优数据选择：若指定 `--tune_list`（调优样本列表文件），则通过 `DataSelector` 从该列表中选择 `--tune_num` 个样本（如 5 张），存储在 `tune_ds` 中（用于后续量化参数调优）。
  - 调试支持：若 `debug_cmd` 包含 `dump_list`，则将选中的样本路径导出到 `selected_image_list.txt` 和 `selected_tune_image_list.txt`（方便查看选了哪些样本）。

#### 输入合法性校验

- 功能：确保用户配置的合理性，避免后续流程出错。
- 具体操作：若用户指定 `--part_quantize custom_mode`（自定义算子量化模式），但未通过 `--custom_operator` 指定算子类型，则通过 `parser.error` 报错并终止，提示用户补充参数。

#### 日志配置与形状预处理

- 功能：配置日志输出级别，并处理模型中的形状相关算子（确保量化时张量形状正确）。
- 具体操作：

  - 日志级别：根据 `--debug_log` 是否启用，设置日志为 `DEBUG`（调试时输出详细信息）或 `INFO`（默认，输出关键步骤）。
  - 形状处理：通过 `ShapeOps(args).run()` 解析模型中的形状算子（如 Reshape、Transpose），确保量化过程中张量形状的一致性（避免因形状不匹配导致量化失败）。

#### 核心量化流程

根据 `--search` 参数（量化方案）的不同，执行对应的量化逻辑，这是整个脚本的核心：

##### 5.1 若 `--search search_qtable`（混合精度量化表搜索）

- 功能：为模型各层分配不同量化位宽（如 8 位 / 16 位），生成最优量化表（平衡精度与效率）。
- 具体操作：

  - 初始化 `SearchQtable`（量化表搜索器），传入参数、校准数据 `selector` 和调优数据 `tune_ds`。
  - 根据 `--mix_mode` 选择位宽模式：若为 `4_8`，执行 `run_4_8()`（4 位与 8 位混合）；默认 `8_16`（8 位与 16 位混合）。
  - 若指定 `--fast`，执行 `run_fast()`（快速搜索，牺牲部分精度换速度）；否则执行 `run()`（完整搜索，精度更高）。
  - 最终生成 `--quantize_table` 指定的量化表文件（用于后续模型量化部署）。

##### 5.2 若 `--search` 为 `search_threshold` 或 `False`（基础量化流程）

- 功能：计算各层量化阈值（将浮点值映射到定点范围的临界值），生成基础量化表。

###### 5.2.1 可选优化：SmoothQuant

- 若启用 `--sq`（SmoothQuant 优化），初始化 `SmoothQuant` 并执行 `run()`：通过调整权重和激活值的分布，减少极端值对量化的影响（尤其适用于 Transformer 等模型）。

###### 5.2.2 可选优化：权重均衡

- 若启用 `--we`（权重均衡），通过 `MixPrecSearcher` 的 `weight_equalization()` 平衡层间权重分布，避免部分层权重范围过大导致的量化误差。

###### 5.2.3 校准与阈值计算

- 若 `--search search_threshold`：通过 `SearchThreshold` 的 `run_search_calitable()` 搜索最优阈值（在保证精度的前提下，找到使量化误差最小的阈值）。
- 若 `--search False`：通过 `ActivationCalibrator` 的 `run()` 直接计算阈值（基于 `--cali_method` 指定的方法，如 KL 散度 `use_kl`、MSE 等）。

###### 5.2.4 可选优化：偏差校正

- 若启用 `--bc`（偏差校正），通过 `MixPrecSearcher` 的 `run_bias_correction()` 补偿量化导致的输出偏差：
  - 临时使用 `--bc_inference_num` 个样本重新校准。
  - 校正后重新执行校准（确保阈值更新）。

#### 模型结构适配

- 功能：针对特殊模型结构（如 Transformer 注意力模块）应用定制化量化策略。
- 具体操作：通过 `MatchPattern(args).run()` 识别模型中的特殊结构（如 `--transformer True` 时识别注意力层），并为其设置适配的量化参数（避免通用量化策略导致的精度损失）。

### 二、重点函数功能解析

## 10.data_selector.py

### 一、整体定位

- 功能：该 python 文件的功能是从指定数据集（或数据列表文件）中筛选符合要求的样本（如图片、NPY/NPZ 数据文件），并校验数据格式的合法性，为后续模型量化校准提供标准化的输入数据。
- 具体流程如下：

  1. 根据输入的 `dataset`（数据集路径）或 `data_list_file`（数据列表文件）加载原始数据列表。
  2. 对数据进行筛选（随机选择指定数量的样本，或直接读取列表中的样本）。
  3. 校验所有样本的格式是否统一（只能是图片、NPY、NPZ 中的一种），确保后续处理兼容性。
  4. 支持将筛选结果导出为文件（用于调试或记录）。

### 二、函数解释

1. 初始化方法 `init`（核心入口）

- 功能：根据输入参数加载并筛选数据，初始化数据列表。
- 生成逻辑：

```python
def __init__(self, dataset: str, num: int = 0, data_list_file: str = None):
    self.data_list = []  # 存储最终筛选后的样本路径
    # 情况1：若指定data_list_file（数据列表文件），直接从文件读取
    if data_list_file:
        with open(data_list_file, 'r') as f:
            # 读取文件中每一行（去除首尾空格），作为样本路径
            self.data_list = [line.strip() for line in f.readlines()]
        # 若指定了num（样本数量），且num小于列表长度，则截取前num个
        if num > 0 and num < len(self.data_list):
            self.data_list = self.data_list[:num]
    # 情况2：若指定dataset（数据集路径），则随机筛选
    elif dataset:
        self.data_list = self._random_select(dataset, num)
    # 异常处理：未指定数据来源
    else:
        raise RuntimeError("Please specific dataset path by --dataset")
    # 异常处理：筛选后无有效样本
    if len(self.data_list) == 0:
        raise RuntimeError("There is no inputs")
    # 校验数据格式合法性
    self._check_data_list()
```

1. 数据筛选方法 `_random_select`

- 功能：从 `dataset` 目录中随机选择指定数量的样本（支持子目录递归查找）。
- 生成逻辑：

```python
def _random_select(self, dataset_path, num):
    full_list = []
    # 递归遍历dataset_path下所有文件（包括子目录）
    for file in pathlib.Path(dataset_path).glob('**/*'):
        name = str(file)
        # 只保留图片、NPY、NPZ格式的文件
        if self.is_npz(name) or self.is_npy(name) or self.is_image(name):
            full_list.append(name)
    # 排序后随机打乱（固定种子1684，确保结果可复现）
    full_list = sorted(full_list)
    random.seed(1684)  # 固定种子，多次运行选择相同样本
    random.shuffle(full_list)
    # 确定最终选择数量（不超过总样本数，若num=0则全选）
    num = num if len(full_list) > num else len(full_list)
    if num == 0:
        num = len(full_list)
    return full_list[:num]  # 返回前num个样本
```

1. 格式校验方法 `_check_data_list`

- 功能：确保所有样本格式统一（只能是图片、NPY、NPZ 中的一种），避免后续处理出错。
- 生成逻辑：

```python
def _check_data_list(self):
    # 标记是否存在NPZ、NPY、图片格式
    self.all_npz, self.all_npy, self.all_image = False, False, False
    for file in self.data_list:
        if self.is_npz(file):  # 若文件是NPZ
            self.all_npz = True
        else:
            # 处理多输入情况（如"a.npy,b.npy"，按逗号分割）
            inputs = [s.strip() for s in file.split(',')]
            for i in inputs:
                if self.is_npy(i):  # 若文件是NPY
                    self.all_npy = True
                elif self.is_image(i):  # 若文件是图片
                    self.all_image = True
                else:  # 不支持的格式
                    raise RuntimeError("File illegal:{}".format(file))
        # 校验格式唯一性：只能存在一种格式（NPZ/NPY/图片）
        # （布尔值相加：True=1，False=0，若num_type!=1则存在多种格式）
        num_type = self.all_npz + self.all_image + self.all_npy
        if num_type != 1:
            raise RuntimeError("Only support one input type: npy/npz/image")
```

1. 格式判断工具方法

- 功能：判断文件是否为 NPZ、NPY 或图片格式（基于文件后缀）。
- 实现逻辑：

```python
def is_npz(self, filename: str):
    # NPZ文件：后缀为.npz（忽略大小写，如.NPZ也支持）
    return filename.lower().split('.')[-1] == 'npz'

def is_npy(self, filename: str):
    # NPY文件：后缀为.npy（忽略大小写）
    return filename.lower().split('.')[-1] == 'npy'

def is_image(self, filename: str):
    # 图片文件：后缀为jpg/bmp/png/jpeg/jfif（忽略大小写）
    return filename.lower().split('.')[-1] in ['jpg', 'bmp', 'png', 'jpeg', 'jfif']
```

1. 结果导出方法 `dump`

- 功能：将筛选后的样本路径写入文件（用于调试或记录选择的样本）。
- 实现逻辑：

```python
def dump(self, file):
    with open(file, 'w') as f:
        # 每行写入一个样本路径
        for input in self.data_list:
            f.write(input + '\n')
```

### 三、辅助知识

#### data_list_file（数据列表文件）和 dataset（数据集路径）的区别：

##### 数据列表文件（`data_list_file`）

- 定义：是一个文本文件（如 `.txt`），文件内容是手动指定的输入文件路径列表（每行一个路径）。
- 内容格式：每行对应一个输入（支持单文件或多文件组合），例如：

```
# 单行可以是单个npz/npy/图片文件
a.npz
b.jpg
# 单行也可以是多个npy/图片文件（用逗号分隔，表示多输入）
c.npy,d.npy
e.jpg,f.png
```

- 作用：用于精确指定需要使用的输入文件，适合已知具体哪些文件需要处理的场景（例如筛选过的测试集）。
- 处理逻辑：

  - 直接读取文本文件中的每行内容，作为 `data_list` 的元素。
  - 如果指定了 `num` 参数（如 `num=5`），则只取前 `num` 个文件（避免读取过多）。

##### 数据集文件（`dataset`）

- 定义：是一个文件夹路径，该文件夹下包含若干输入文件（支持子文件夹递归查找）。
- 内容格式：文件夹中存放的是实际的输入文件（如 `.npz`、`.npy`、`.jpg` 等），无需手动整理列表。
- 作用：用于从大量文件中自动筛选并随机选择输入，适合需要从原始数据集中抽样的场景（例如从 1000 张图片中随机选 100 张测试）。
- 处理逻辑：

  - 递归遍历文件夹下所有文件，筛选出后缀为 `.npz`、`.npy` 或图片格式（`.jpg`、`.png` 等）的文件。
  - 对筛选后的文件列表随机打乱（固定种子 `1684`，保证结果可复现），然后按 `num` 参数选取前 `num` 个文件（若 `num=0` 则取全部）。

## 11.search_qtable.py

### 一、整体定位

SearchQtable 是 TPU-MLIR 量化校准流程中自动搜索最优量化表（quantize table）的核心类。它的主要目标是：

- 针对每一层（op），自动选择最优的量化阈值和量化方法（如 KL、MSE、MAX、Percentile9999），
- 通过混合精度（MixPrecision）策略，自动将部分对精度敏感的层保留为浮点（FP32/FP16），其余层量化为 INT8/INT4，
- 支持聚类、敏感性分析、快速搜索等多种自动化策略，
- 生成最终的量化表（quantize table），以便后续模型部署。

### 二、主要函数

#### gen_multiple_thresholds

功能：针对每种量化方法（如 KL、MSE、MAX、Percentile9999），为所有 op 生成一份阈值表，并可选用调优数据集微调阈值。逻辑：

- 遍历所有量化方法，分别用 ActivationCalibrator 计算阈值。
- 支持调优（tune_ds），用 SimpleTuner 微调阈值。
- 结果写入不同的 calibration_table 文件。
- 返回每种方法下每一层的阈值字典。

原理：

1. 前置判断：`if out not in thresholds_map: continue`

作用：过滤未参与校准的算子输出。其中，`thresholds_map` 是校准器（`ActivationCalibrator`）预先计算的 “算子输出 → 阈值” 映射表。如果某个算子输出（`out`）不在该表中，说明它无需量化（或未被校准），直接跳过。

1. 特殊情况：使用 PyTorch 观测器校准（`use_torch_observer_for_cali`）

当启用 PyTorch 的量化观测器时，阈值计算依赖 PyTorch 的量化参数（`scale` 和 `zp`），而非直接统计激活值。

1. 普通情况：使用校准器统计校准

当不使用 PyTorch 观测器时，阈值直接基于输入数据的激活值分布统计得到。

```python
def gen_multiple_thresholds(self, all_op_names, quantize_method_list):
    """
    生成多种校准方法（如MAX、MSE）对应的量化阈值，并保存到文件中
    :param all_op_names: 模型中所有算子的名称列表
    :param quantize_method_list: 校准方法列表（如['MAX', 'MSE']）
    :return: 层阈值字典（键：校准方法，值：{算子名: [绝对最大值, 调优后阈值]}）
    """
    # 初始化层阈值字典，用于存储不同校准方法对应的阈值结果
    layer_th_dicts = {}
    # 遍历每种校准方法（如MAX、MSE、KL等）
    for i, method_name in enumerate(quantize_method_list):
        # 临时存储当前校准方法下的阈值（键：算子名，值：[绝对最大值, 阈值]）
        tmp_th_dict = {}
        # 初始化激活值校准器（核心工具：收集激活值并计算初始阈值）
        calibrator = ActivationCalibrator(self.args, self.selector, self.tune_ds)
        # 根据校准方法设置调试命令（指定阈值计算方式）
        if method_name == "MAX":
            calibrator.debug_cmd = 'use_max'  # 使用最大值法计算阈值
        elif method_name == "Percentile9999":
            calibrator.debug_cmd = 'use_percentile9999'  # 使用99.99分位法
        elif method_name == "MSE":
            calibrator.debug_cmd = 'use_mse'  # 使用均方误差法
        
        # 收集激活值并计算初始阈值（核心步骤）
        # 返回值：阈值映射、绝对最大值映射、缩放因子映射、零点映射等
        thresholds_map, thresholds_map_absmax, thresholds_map_scale, thresholds_map_zp, _, _, _, _ = calibrator.activation_collect_and_calc_th_new()
        # 清理校准器占用的资源（如缓存的激活值数据）
        calibrator._clean_resource()

        # 存储当前方法下的阈值列表（用于后续校验）
        thresholds_map_list = []
        # 获取模型中所有算子的名称列表（从MLIR解析）
        op_layers = self.parser.get_op_name_list()
        # 定义校准表文件路径（含当前校准方法，如"calib_table_MAX"）
        cali_table = self.args.calibration_table + "_" + method_name
        # 若指定了调优样本数，在文件名后加".1"（临时标记）
        if self.args.tune_num > 0:
            cali_table += ".1"
        
        # 将初始阈值写入校准表文件（用于记录原始结果）
        with open(cali_table, 'w') as f:
            # 写入文件头（版本、时间、参数等元信息）
            f.write("# mlir version: {}\n".format(pymlir.__version__))
            f.write("# mlir: {}\n".format(self.args.mlir_file))
            f.write("# genertated time: {}\n".format(datetime.datetime.now()))
            f.write("# histogram number: {}\n".format(calibrator.histogram_bin_num))  # 直方图分箱数
            f.write("# sample number: {}\n###\n".format(calibrator.num_samples))  # 校准样本数
            f.write("# op_name    threshold    min    max\n")  # 表头：算子名、阈值、最小值、最大值
            
            # 遍历每个算子，写入对应的阈值信息
            for i, op_name in enumerate(op_layers):
                # 获取当前算子的输出张量名称（一个算子可能有多个输出）
                outputs = self.parser.get_outputs_by_op_name(op_name)
                # 遍历每个输出张量
                for out in outputs:
                    # 若当前输出张量无阈值（未被校准），跳过
                    if out not in thresholds_map:
                        continue
                    else:
                        # 特殊情况：使用PyTorch的观测器计算校准时的阈值
                        if 'use_torch_observer_for_cali' in calibrator.debug_cmd:
                            # 量化范围（INT8：-128~127）
                            qmin, qmax = -128, 127
                            # 获取缩放因子和零点（量化参数）
                            scale = thresholds_map_scale[op_name]
                            zp = thresholds_map_zp[op_name]
                            # 根据量化参数计算阈值（最大可表示值）
                            threshold = float(scale * max(-(qmin-zp), qmax-zp))
                            # 计算量化后的最小/最大值
                            min_value = float(scale * (qmin - zp))
                            max_value = float(scale * (qmax - zp))
                        # 普通情况：使用校准器计算的阈值
                        else:
                            # 获取当前输出的阈值（若不存在则默认1.0）
                            if out in thresholds_map:
                                threshold = thresholds_map[out]
                            else:
                                threshold = 1.0
                            # 获取激活值的最小/最大值（从校准器统计结果中读取）
                            if out in calibrator.activations_statistics:
                                min_value, max_value, _ = calibrator.activations_statistics[out]
                            else:
                                min_value, max_value = -1, 1  # 默认值
                        # 记录阈值到列表（用于后续校验）
                        thresholds_map_list.append(threshold)
                        # 将阈值、最小/最大值写入校准表文件（保留7位小数）
                        f.write("{} {:.7f} {:.7f} {:.7f}\n".format(out, threshold, min_value, max_value))
        
        # 若未指定调优样本数（无需调优），直接返回（不再执行后续调优步骤）
        if calibrator.args.tune_num <= 0:
            return

        # 若指定了调优样本数，处理校准表文件名（移除临时标记".1"）
        if self.args.tune_num > 0:
            cali_table = cali_table.rsplit(".1", 1)[0]
        # 将校准表路径设置到校准器参数中（用于调优）
        calibrator.args.calibration_table = cali_table
        # 初始化简单调优器（基于调优样本微调阈值，提升精度）
        tunner = SimpleTuner(calibrator.args, calibrator.tune_ds, calibrator.ppa_list, thresholds_map_absmax)
        # 执行调优并获取调优后的阈值
        thresholds_map = tunner.run()

        # 存储调优后的阈值和层名（用于后续记录）
        tuned_threshold_list = []
        layer_name_list = []
        # 定义调优后的校准表文件名（加"_tune"标记）
        cali_table += "_tune"
        # 过滤掉融合算子（只保留需要量化的原始算子）
        op_layers = calibrator.get_no_fused_tensors(op_layers)
        # 将调优后的阈值写入新的校准表文件
        with open(cali_table, 'w') as f:
            # 写入文件头（元信息）
            f.write("# mlir version: {}\n".format(pymlir.__version__))
            f.write("# mlir: {}\n".format(self.args.mlir_file))
            f.write("# genertated time: {}\n".format(datetime.datetime.now()))
            f.write("# histogram number: {}\n".format(calibrator.histogram_bin_num))
            f.write("# sample number: {}\n".format(calibrator.num_samples))
            f.write("# tune number: {}\n###\n".format(self.args.tune_num))  # 调优样本数
            f.write("# op_name   threshold    min    max\n")  # 表头
            
            # 遍历每个算子，写入调优后的阈值
            for i, op_name in enumerate(op_layers):
                # 获取调优后的阈值
                threshold = thresholds_map[op_name]
                # 处理异常值（阈值过小或NaN时，强制设为1e-5避免后续错误）
                if threshold <= 1e-5 or np.isnan(threshold):
                    threshold = 1e-5
                    self.mix_prec.logger.print_info("WARNING: layer {} threshold is zero. Please check the "
                        "input data correctness.".format(op_name))  # 日志警告
                # 记录层名和阈值（用于后续统计）
                layer_name_list.append('{}_{}'.format(i, op_name))
                tuned_threshold_list.append(threshold)
                # 获取激活值的最小/最大值（从校准器统计结果中读取）
                min_value, max_value, _ = calibrator.activations_statistics[op_name]
                # 写入调优后的阈值、最小/最大值（保留7位小数）
                f.write("{} {:.7f} {:.7f} {:.7f}\n".format(op_name, threshold, min_value, max_value))
        
        # 将当前校准方法的阈值结果存入临时字典
        for op_name in all_op_names:
            # 跳过无阈值的算子
            if op_name not in thresholds_map:
                pass
            else:
                # 再次处理异常值（确保阈值有效）
                if thresholds_map[op_name] <= 1e-5 or np.isnan(thresholds_map[op_name]):
                    thresholds_map[op_name] = 1e-5
                # 存储：[绝对最大值（参考）, 调优后阈值（实际使用）]
                tmp_th_dict[op_name] = [thresholds_map_absmax[op_name], thresholds_map[op_name]]
        # 将当前校准方法的结果存入总字典
        layer_th_dicts[method_name] = tmp_th_dict
    # 返回所有校准方法的阈值结果
    return layer_th_dicts
```

#### 2. search_layer_type_no_need_quant

功能：自动分析哪些 op 类型对精度影响较大（敏感），建议保留为浮点。逻辑：

- 遍历所有 op 类型，分别将该类型全部保留为浮点，其余量化，评估整体精度（cosine similarity）。
- 如果精度下降明显，则该类型为敏感类型。
- 返回所有敏感类型。

原理：

- 通过“整体置浮点-量化对比”法，自动发现对精度影响最大的算子类型，便于后续混合精度策略。

```python
def search_layer_type_no_need_quant(self, layer_names, float_outputs_cos, global_compare_layers, layers_rate, predictions_gt):
    """
    搜索对量化不敏感的算子类型（即量化后精度损失小的类型），仅关注敏感类型以减少后续计算量
    :param layer_names: 需要分析的层名称列表
    :param float_outputs_cos: 浮点模型的输出余弦相似度（精度基准）
    :param global_compare_layers: 用于精度对比的关键层列表
    :param layers_rate: 各对比层的权重（影响精度评估结果）
    :param predictions_gt: 浮点模型的输出结果（作为精度对比的基准）
    :return: 对量化敏感的算子类型列表（需要重点关注的类型）
    """
    # 收集所有层对应的算子类型（去重，避免重复分析）
    op_types = set()
    for layer_name in layer_names:
        # 通过层名获取对应的算子类型（如"top.Conv"、"top.MatMul"）
        op_type = self.parser.get_op_type_by_op_name(layer_name)
        op_types.add(op_type)  # 用集合存储，自动去重

    # 存储对量化敏感的算子类型（量化后精度损失大的类型）
    sensitive_op_type = []
    # 构建"层名→算子类型"的映射（方便后续快速查询）
    layer_op_map = {layer_name: self.parser.get_op_type_by_op_name(layer_name) for layer_name in layer_names}
    # 设定余弦相似度阈值：取0.999和预期精度的最大值（确保精度要求不低于基础阈值）
    cos_threshold = max(0.999, self.args.expected_cos)

    # 遍历每种算子类型，评估该类型量化后的精度损失
    for op_type in op_types:
        # 构建"浮点层列表"：除当前算子类型外，其他层均保持浮点（仅量化当前类型的层）
        fp_list = []
        for layer_name in layer_names:
            # 若层的算子类型不是当前类型，则加入浮点列表（不量化）
            if layer_op_map[layer_name] == op_type:
                pass  # 当前类型的层会被量化，不加入浮点列表
            else:
                fp_list.append(layer_name)  # 非当前类型的层保持浮点

        # 生成混合精度量化表（指定哪些层保持浮点）
        mix_table = self.mix_prec._gen_mix_table(fp_list)
        # 创建混合精度模型（仅当前算子类型的层被量化，其他层浮点）
        mix_model = MixQuantModel(self.fp32_mlir, self.chip, self.cali_table_name, mix_table)

        # 评估混合模型的精度：计算量化后与浮点模型的相似度（值越小，精度损失越大）
        # 1 - 余弦相似度 = 精度损失（值越小越好）
        similarity = 1 - self.mix_prec.run_model_new(
            mix_model,  # 混合精度模型
            False,  # 非浮点模型（需要与浮点基准对比）
            global_compare_layers,  # 对比层
            layers_rate,  # 对比层权重
            predictions_gt,  # 浮点模型输出（基准）
            -1,  # 使用所有样本评估
            ['cos']  # 用余弦相似度评估精度
        )
        # 打印当前算子类型的精度损失结果（方便调试和分析）
        self.mix_prec.logger.print_info(f"op_type : {op_type}, similarity : {similarity}")

        # 判断当前算子类型是否对量化敏感：
        # 若精度损失（similarity）小于 "浮点基准 * 阈值"，说明量化后精度足够，非敏感；
        # 反之则敏感（量化后精度损失大，需要重点关注）
        if similarity < float_outputs_cos * cos_threshold:
            sensitive_op_type.append(op_type)

    # 打印敏感算子类型（后续量化需优先保证这些类型的层精度）
    self.mix_prec.logger.print_info(f"sensitive_op_type : {sensitive_op_type}, please pay attention to these types of operations")
    return sensitive_op_type
```

## 附录一：关于 MaskRCNN

可以参考一下链接的介绍：

[https://blog.csdn.net/IanYue/article/details/126657217](https://blog.csdn.net/IanYue/article/details/126657217)

[https://zhuanlan.zhihu.com/p/407831250](https://zhuanlan.zhihu.com/p/407831250)
