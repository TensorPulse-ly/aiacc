
@Jabari

## Onnx模型转化路径

​	比如resnet18.onnx这个模型，它的转化路径如下：

​	resnet18.onnx  -->  resnet18_opt.onnx  -->  final_opt.onnx  -->  resnet18_origin.mlir

​	**首先**，是通过ONNX Simplifier(onnxsim)这个外部工具来对resnet18.onnx模型做一个初步的优化，比如shape推导、常量合并等，将其转化为restnet18_opt.onnx。

​	**其次**，Onnxopt.py这个文件会帮我们做一些onnxsim无法完成的一些功能，包括一些特殊算子的合并，经过Onnxopt.py后转化为final_opt.onnx模型。

​	**最后**，是使用OnnxConverter.py工具。OnnxConverter.py工具导入的模型是final_opt.onnx，这会使final_opt.onnx模型转化为resnet18_origin.mlir文件。

## Onnxopt.py文件

### 	**ConstantFolding类**

​		这个类的功能是将计算图中可以在编译时确定的计算节点替换为常量节点。它的关键方法有**get_constant_nodes()，forward()，eliminate_const_nodes()，run()等。**

​		 `get_constant_nodes()`: 识别可常量折叠的节点 

​		 `forward()`: 使用onnxruntime执行前向推理 

​		 `eliminate_const_nodes()`: 将计算结果替换为Constant节点 

​		 `run()`: 执行完整的常量折叠流程

​		**函数汇总：**

1. **构造与初始化**

| 函数名     | 功能                                             | 参数                                               | 输入类型                    | 输出类型 | 备注                         |
| ---------- | ------------------------------------------------ | -------------------------------------------------- | --------------------------- | -------- | ---------------------------- |
| `__init__` | 初始化常量折叠器，设置模型和参数，清空value_info | `model`, `test_input`, `dynamic_shape_input_names` | onnx.ModelProto, list, list | None     | 深拷贝模型，避免修改原始对象 |

2. **输入处理函数组**

| 函数名                         | 功能                                          | 参数           | 输入类型        | 输出类型              | 备注                           |
| ------------------------------ | --------------------------------------------- | -------------- | --------------- | --------------------- | ------------------------------ |
| `get_inputs`                   | 获取模型的真实外部输入（排除initializer权重） | 无             | None            | list[ValueInfoProto]  | 过滤掉权重参数，只返回外部输入 |
| `get_input_names`              | 获取外部输入的名称列表                        | 无             | None            | list[str]             | 基于get_inputs()的简单包装     |
| `generate_specific_rand_input` | 根据输入形状和类型生成随机测试数据            | `input_shapes` | dict[str, list] | dict[str, np.ndarray] | 智能处理不同数据类型           |

3. **元数据访问函数组**

| 函数名               | 功能                                          | 参数   | 输入类型 | 输出类型               | 备注                         |
| -------------------- | --------------------------------------------- | ------ | -------- | ---------------------- | ---------------------------- |
| `get_value_info_all` | 在value_info、input、output中查找张量的值信息 | `name` | str      | ValueInfoProto or None | 多位置查找的统一接口         |
| `get_shape`          | 获取张量的形状信息                            | `name` | str      | list[int]              | 基于get_value_info_all()     |
| `get_elem_type`      | 获取张量的ONNX元素类型枚举值                  | `name` | str      | int                    | 返回TensorProto.DataType枚举 |

4. **静态工具函数组**

| 函数名                            | 功能                              | 参数                      | 输入类型          | 输出类型  | 备注                           |
| --------------------------------- | --------------------------------- | ------------------------- | ----------------- | --------- | ------------------------------ |
| `insert_elem`                     | 在protobuf列表的指定位置插入元素  | `nodes`, `idx`, `element` | list, int, object | None      | 使用CopyFrom避免引用问题       |
| `get_shape_from_value_info_proto` | 从ValueInfoProto对象提取形状列表  | `vinfo`                   | ValueInfoProto    | list[int] | 静态方法，处理protobuf嵌套结构 |
| `get_np_type_from_elem_type`      | 将ONNX类型枚举转换为NumPy数据类型 | `elem_type`               | int               | np.dtype  | 静态方法，使用元组映射表       |

5. **动态性检测函数组**

| 函数名                     | 功能                                     | 参数   | 输入类型  | 输出类型 | 备注                                 |
| -------------------------- | ---------------------------------------- | ------ | --------- | -------- | ------------------------------------ |
| `is_dynamic`               | 判断节点是否具有动态特性（不能常量折叠） | `node` | NodeProto | bool     | 核心动态性检测逻辑                   |
| `has_subgraph_in_node`     | 检查节点是否包含子图（If、Loop、Scan等） | `node` | NodeProto | bool     | 检查GRAPH和GRAPHS属性类型            |
| `is_quantizeLinear`        | 检查是否为量化相关节点                   | `node` | NodeProto | bool     | 识别DequantizeLinear、QuantizeLinear |
| `is_non_determinstic_node` | 检查是否为非确定性（随机）节点           | `node` | NodeProto | bool     | 识别Random类算子                     |

6. **核心算法函数**

| 函数名               | 功能                         | 参数 | 输入类型 | 输出类型        | 备注                             |
| -------------------- | ---------------------------- | ---- | -------- | --------------- | -------------------------------- |
| `get_constant_nodes` | 识别图中可进行常量折叠的节点 | 无   | None     | list[NodeProto] | 常量折叠的核心算法，使用前向传播 |

7. **模型推理函数组**

| 函数名                     | 功能                        | 参数                  | 输入类型         | 输出类型    | 备注                         |
| -------------------------- | --------------------------- | --------------------- | ---------------- | ----------- | ---------------------------- |
| `forward`                  | 使用onnxruntime执行模型推理 | `model`, `test_input` | ModelProto, list | OrderedDict | 支持大模型和自定义算子       |
| `forward_for_node_outputs` | 获取指定节点的推理输出值    | `const_nodes`         | list[NodeProto]  | OrderedDict | 临时修改图输出来获取中间结果 |

8. **图变换函数组**

| 函数名                  | 功能                         | 参数                | 输入类型              | 输出类型 | 备注                   |
| ----------------------- | ---------------------------- | ------------------- | --------------------- | -------- | ---------------------- |
| `eliminate_const_nodes` | 将常量节点替换为Constant节点 | `const_node`, `res` | list[NodeProto], dict | bool     | 执行实际的节点替换操作 |
| `remove_unused_nodes`   | 移除图中未被使用的节点       | 无                  | None                  | None     | 清理优化后的冗余节点   |
| `infer_shapes`          | 调用ONNX库执行形状推理       | 无                  | None                  | None     | 更新模型的形状信息     |

9. **主控制流函数**

| 函数名    | 功能                         | 参数                | 输入类型 | 输出类型   | 备注                           |
| --------- | ---------------------------- | ------------------- | -------- | ---------- | ------------------------------ |
| `folding` | 执行一轮常量折叠过程         | `infer_shapes=True` | bool     | bool       | 单次折叠的完整流程             |
| `run`     | 主执行入口，迭代执行直到收敛 | 无                  | None     | ModelProto | 使用固定点算法，返回优化后模型 |

**执行流程**

​	**一、初始化（\__init__）**

​		功能：深拷贝原始模型，清空value_info避免形状推理冲突，严重模型的合法性，初始化常量张量列表。

​		代码：

```python
    def __init__(self, model, test_input, dynamic_shape_input_names):
        self.test_input = test_input
        self.model = copy.deepcopy(model)       #使用深拷贝，避免修改原模型
        self.dynamic_shape_input_names = dynamic_shape_input_names
        if self.model.graph.value_info:         #清空value_info避免形状推理冲突
            n = len(self.model.graph.value_info)
            for _ in range(n):  #下划线是Python惯用法，表示不关心循环变量值
                v = self.model.graph.value_info[0]
                self.model.graph.value_info.remove(v)
        try:    #模型检查，失败不会中断流程，只是警告
            onnx.checker.check_model(self.model)
        except:
            print("WARNING: onnx model check failed")
        self.const_tensors = [] # 存储常量张量名称

```

​	**二、固定点迭代( `run` → `fixed_point` → `folding` )**

​		单轮折叠过程（folding）：

​				1.调用 get_constant_nodes 方法，用于识别常量节点。

​				2.调用 forward_for_node_outputs 方法，用于执行推理。（通过调用forward方法）

​				3.调用 eliminate_const_nodes 方法，用于节点替换。

​				4.调用infer_shapes方法，执行形状推理。

​		下面是一些比较核心的方法：

​		**get_constant_nodes**

​			功能：识别可进行常量折叠的节点

​			算法逻辑：1.初始化常量张量列表

​							  2.遍历所有节点，判断其输入是否全为常量

​							  3.特殊处理动态shape相关的节点（Reshape、Slice等）

​							  4.返回可折叠的节点列表

```python
    def get_constant_nodes(self):       #常量折叠的关键方法
        const_nodes = []        #可以常量折叠的节点列表
        dynamic_tensors = []    #动态张量名称列表
        dynamic_tensors.extend(self.dynamic_shape_input_names)  #添加预定义的动态形状输入
        self.const_tensors = [x.name for x in self.model.graph.initializer] #所有权重参数都是常量
        self.const_tensors.extend(  #添加Constant算子的第一个输出（Constant节点通常只有一个输出）
            [node.output[0] for node in self.model.graph.node if node.op_type == "Constant"])
        self.const_tensors.extend([''])     #添加空字符串作为安全占位符
        for node in self.model.graph.node:  #遍历图中的所有节点
            if node.op_type == "Shape" and node.input[0] not in dynamic_tensors:    #Shape节点特殊处理: Shape算子通常可以常量折叠
                const_nodes.append(node)    #如果是Shape算子且第一个输入不是动态的，则将节点加入常量节点列表
                self.const_tensors.extend(node.output)  #更新常量集合: 将输出加入常量张量集合
            elif node.op_type == "Resize" and all([x in self.const_tensors for x in node.input]):   #如果是Resize算子且所有输入是否都是常量
                const_nodes.append(node)    #如果满足，添加到常量节点列表
                self.const_tensors.extend(node.output)  #更新常量集合: 将输出加入常量张量集合
            elif any(x in dynamic_tensors for x in node.input): #如果有任何输入是动态的（动态输入导致动态输出）
                dynamic_tensors.extend(node.output) #将输出标记为动态张量
            elif self.is_dynamic(node): #使用之前定义的动态性检查方法
                dynamic_tensors.extend(node.output) #将输出标记为动态张量
            elif self.is_quantizeLinear(node):  #量化节点跳过: 量化算子不进行常量折叠
                pass
            elif self.has_subgraph_in_node(node):   #包含子图的节点特殊处理
                if all([x in self.const_tensors for x in node.input]):  #所有输入都必须是常量
                    if (node.op_type == "If"):  #目前只支持If类型的子图节点
                        const_nodes.append(node)    #满足条件的If节点可以常量折叠
            elif len(node.input) > 0 and all([x in self.const_tensors for x in node.input]) \
                    and not self.is_non_determinstic_node(node):    #节点有输入、所有输入都是常量、不是随机节点
                const_nodes.append(node)    #满足条件的节点加入结果
                self.const_tensors.extend(node.output)  #更新常量集合: 将输出加入常量张量集合
            elif node.op_type == "Transpose" and all([x in self.const_tensors for x in node.input]):    #Transpose特殊处理: Transpose算子的额外处理
                const_nodes.append(node)
                self.const_tensors.extend(node.output)
        return copy.deepcopy(const_nodes)   #返回结果的深拷贝，避免外部修改影响内部状态
```

​		**forward**

​			 功能: 使用onnxruntime执行模型推理 

​			 特殊处理：1. 超大模型(>2GB)通过临时文件加载 

​							   2. 自定义算子通过PyOrtFunction处理

​							   3. 支持.npz格式的测试输入 

​							   4. 动态生成随机输入数据 

```python
    def forward(self, model, test_input):   #模型推理 forward       推理执行方法: 使用onnxruntime执行模型
        input_shapes = {}   #创建输入形状字典
        sess_options = rt.SessionOptions()  #创建会话选项   rt.SessionOptions(): onnxruntime的会话配置对象      SessionOptions是ONNX Runtime中用于配置推理会话(InferenceSession)的核心对象。它允许开发者在创建会话实例时指定各种运行参数，包括执行提供器(Execution Providers)、线程数、日志级别等关键配置。
        sess_options.graph_optimization_level = rt.GraphOptimizationLevel(0)    #设置图优化级别为0
        sess_options.log_severity_level = 3     #设置日志级别为3（只显示错误）
        coustom_flag = False        #标记是否使用自定义算子处理
        try:
            try:
                sess = rt.InferenceSession(model.SerializeToString(),   #创建推理会话: 使用onnxruntime创建会话      model.SerializeToString(): 将protobuf模型序列化为字节串。Protobuf是一种轻便高效的结构化数据存储格式，可以用于数据的结构化和序列化，适合做数据存储或数据交换格式（与语言无关、平台无关）。ONNX采用protobuf来进行数据的结构化
                                           sess_options=sess_options,   #传递会话配置
                                           providers=["CPUExecutionProvider"])  #指定使用CPU执行提供者
            except Exception as E:      #异常捕获
                if "Message onnx.ModelProto exceeds maximum protobuf size of 2GB" in str(E):    #检查是否因模型过大导致失败
                    print("LOG: Try to convert through a temporary file when Constant Folding.")    #日志输出: 提示使用临时文件处理大模型
                    # large models try to convert through a temporary file
                    import os
                    import tempfile
                    with tempfile.TemporaryDirectory() as tmpdirname:   #上下文管理器: 自动管理临时目录的生命周期。tmpdirname: 临时目录的路径
                        model_path = os.path.join(tmpdirname, 'model.onnx') #创建模型文件的完整路径
                        onnx.save(model,        #将大模型保存为外部数据格式
                                  model_path,
                                  save_as_external_data=True,   #启用外部数据存储
                                  location="temp_external_data",    #外部数据文件的位置
                                  convert_attribute=True)   #转换属性为外部数据
                        sess = rt.InferenceSession(model_path,      #从文件路径创建会话而不是内存
                                                   sess_options=sess_options,
                                                   providers=["CPUExecutionProvider"])
                elif "is not a registered function/op" in str(E):   #检查是否因未注册算子失败
                    coustom_flag = True #标记使用自定义算子处理
                    sess = PyOrtFunction.from_model(model)      #使用PyOrtFunction处理自定义算子
                else:   #重新抛出: 其他异常重新抛出
                    raise E
        except ValueError:      #兜底处理: 输出警告但不中断程序
            print("WARNING: onnxruntime.InferenceSession error.")

        input_names = self.get_input_names()    #调用之前定义的方法获取输入名称
        inputs = {}     #存储实际的输入数据
        for name in input_names:
            shape = self.get_shape(name)    #获取输入形状
            input_shapes.update({name: shape})  #将输入名称和形状的映射存储

        if len(test_input) == 1 and test_input[0].endswith('.npz'): #只有一个输入且以.npz结尾
            inputs_npz = np.load(test_input[0]) #取第一个（也是唯一的）输入文件路径
            for name in inputs_npz.files:
                elem_type = self.get_elem_type(name)    #获取模型期望的数据类型
                elem_type = self.get_np_type_from_elem_type(elem_type)  #将ONNX类型转换为NumPy类型
                inputs[name] = inputs_npz[name].astype(elem_type)   #将npz中的数据转换为正确类型
        else:   #如果没有提供.npz文件
            inputs.update(self.generate_specific_rand_input(input_shapes))  #生成随机输入: 调用之前的方法

        if coustom_flag:    #如果有自定义算子
            input_tensors = [torch.tensor(inputs[name]).numpy() for name in input_names]    #将输入转换为torch张量再转换为numpy
            output_tensors = sess(*input_tensors)   #使用参数解包调用PyOrtFunction      PyOrtFunction是onnxruntime_extensions库提供的一个类，专门用于处理包含自定义算子的ONNX模型。
            return OrderedDict(zip(sess.output_names, output_tensors))  #创建输出名称到张量的有序映射

        # 标准onnxruntime路径
        outputs = [x.name for x in sess.get_outputs()]      #从会话中获取所有输出的名称
        run_options = rt.RunOptions()       #创建推理运行时选项
        run_options.log_severity_level = 3      #设置运行时日志级别
        return OrderedDict(zip(outputs, sess.run(outputs, inputs, run_options=run_options)))        #sess.run(): 执行推理，传入输出名称、输入数据和运行选项
```

​		**eliminate_const_nodes**

​			功能： 将常量节点的计算结果替换为Constant节点 

​			逻辑：1. 为每个输出创建新的Constant节点 

​					   2. 将计算结果序列化为ONNX张量 

​					   3. 插入新节点并删除原始节点 

​					   4. 特殊处理If节点的子图替换

```python
    def eliminate_const_nodes(self, const_node, res):   #节点消除   将常量节点替换为Constant节点    推理结果字典，包含节点输出的实际值
        do_eliminate = False    #记录是否执行了消除操作
        for i, node in enumerate(self.model.graph.node):    #同时获取索引和节点对象
            if node in const_node:      #检查当前节点是否在要消除的列表中
                if node.op_type == "If":    #如果是If算子
                    sub_graph = {}  #存储If节点的分支子图
                    for attr in node.attribute: #遍历If节点的属性
                        sub_graph[attr.name] = attr.g.node  #将分支子图存储到字典中，attr.g.node: 图属性中的节点列表
                    if res[node.input[0]]:  #条件判断: 使用推理结果中的条件值       res[node.input[0]]: 获取条件输入的计算结果
                        sub_nodes = sub_graph['then_branch']    #条件为真时选择then分支
                    else:   #条件为假时选择else分支
                        sub_nodes = sub_graph['else_branch']
                    if len(node.output) != len(sub_nodes[-1].output):   #验证If节点输出与分支最后节点输出数量一致
                        raise RuntimeError("If op not support multi output now, fix me.")   #目前不支持多输出的If节点
                    sub_nodes[-1].output[:] = []    #清空分支最后节点的输出列表
                    sub_nodes[-1].output.extend(node.output)    #将If节点的输出赋给分支最后节点
                    sub_nodes = sub_nodes[::-1]
                    for n in sub_nodes:
                        self.insert_elem(self.model.graph.node, i + 1, n)
                    self.model.graph.node.remove(node)
                    do_eliminate = True
                    continue
                for output in node.output:
                    new_node = copy.deepcopy(node)
                    new_node.name = "node_" + output
                    new_node.op_type = "Constant"
                    new_attr = onnx.helper.make_attribute(
                        "value", onnx.numpy_helper.from_array(res[output], name=output))
                    del new_node.input[:]
                    del new_node.attribute[:]
                    del new_node.output[:]
                    new_node.output.extend([output])
                    new_node.attribute.extend([new_attr])
                    self.insert_elem(self.model.graph.node, i + 1, new_node)
                del self.model.graph.node[i]
                do_eliminate = True
        return do_eliminate
```

​	**三、 图清理** 

​		通过remove_unsed_nodes实现图清理。它负责移除优化后产生的无用节点，维护图的干净结构。

```python
    def remove_unused_nodes(self):  #无用节点移除，移除图中未使用的节点
        # find subgraph nodes
        def collect_subgraph_tensors(graph):    #在方法内部定义辅助函数
            tensors = set() #创建空集合存储张量名称
            for node in graph.node: #遍历子图节点
                tensors.update(node.input)  #将节点输入添加到集合中
            return tensors

        node_inputs = []    #分别存储节点输入、未使用节点、子图节点
        unused_node = []
        subgraph_nodes = set()
        for n in self.model.graph.node: #遍历主图中所有节点
            node_inputs.extend(n.input) #添加所有节点的输入
            if n.op_type in ["If", "Loop", "Scan"]: #检查是否为包含子图的节点类型
                for attr in n.attribute:    #遍历节点属性
                    if attr.type == onnx.AttributeProto.GRAPH:  #检查是否为图类型属性
                        subgraph_nodes.update(collect_subgraph_tensors(attr.g)) #调用嵌套函数收集子图中的张量
        node_inputs.extend([out.name for out in self.model.graph.output])   #将图的输出也视为"被使用"的张量
        node_inputs = set(node_inputs)  #将列表转换为集合，提高查找效率并去重

        for n in self.model.graph.node: #第二次遍历所有节点
            if len(set(n.output).intersection(node_inputs)) == 0 and len(
                    set(n.output).intersection(subgraph_nodes)) == 0:   #双重检查（检查主图与子图），set(n.output)将当前节点n的输出转为集合，然后.intersection(node_inputs)与node_inputs求交集，找出哪些输出被使用了。
                unused_node.append(n)   #将未使用的节点添加到列表
        for n in unused_node:   #遍历未使用节点列表
            self.model.graph.node.remove(n) #删除未使用的节点

```

​	 **函数调用关系图** 

```
run()
├── fixed_point()
    └── folding()
        ├── get_constant_nodes()
        │   ├── is_dynamic()
        │   ├── has_subgraph_in_node()
        │   ├── is_quantizeLinear()
        │   └── is_non_determinstic_node()
        ├── forward_for_node_outputs()
        │   └── forward()
        │       ├── get_input_names()
        │       │   └── get_inputs()
        │       ├── get_shape()
        │       │   ├── get_value_info_all()
        │       │   └── get_shape_from_value_info_proto()
        │       ├── get_elem_type()
        │       └── generate_specific_rand_input()
        │           └── get_np_type_from_elem_type()
        ├── eliminate_const_nodes()
        │   └── insert_elem()
        └── infer_shapes()
└── remove_unused_nodes()
```

### 	ReForm类

​	ReForm类是一个基于模式匹配的ONNX图重构优化器，主要功能是识别特定的子图模式并用更高效的实现替换它们。

​	**函数汇总：**

**1. 初始化和配置**

| 函数名     | 功能描述                             | 参数                | 返回值                               | 备注                                 |
| ---------- | ------------------------------------ | ------------------- | ------------------------------------ | ------------------------------------ |
| `__init__` | 初始化重构器，设置模型数据和优化配置 | `model`, `rigorous` | None                                 | 构建形状信息字典，初始化各种数据结构 |
| `__call__` | 主入口函数，执行完整的图优化流程     | `reform_info_list`  | `(node_name_mapping, nodes, weight)` | 依次执行预处理、模式匹配、后处理     |

**2. 数据访问工具**

| 函数名             | 功能描述                     | 参数   | 返回值             | 备注                             |
| ------------------ | ---------------------------- | ------ | ------------------ | -------------------------------- |
| `get_tensor_value` | 获取张量的具体数值           | `name` | `np.ndarray`       | 从Constant节点或initializer获取  |
| `find_tensor`      | 检查指定名称的张量是否存在   | `name` | `bool`             | 在节点张量或权重张量中查找       |
| `get_node`         | 根据输出名称获取节点及其索引 | `name` | `(int, NodeProto)` | 返回节点在列表中的位置和节点对象 |
| `get_input_shape`  | 获取输入张量的形状信息       | `name` | `list[int]`        | 从形状信息字典或权重维度获取     |

**3. 模式匹配核心**

| 函数名              | 功能描述                              | 参数                          | 返回值             | 备注                        |
| ------------------- | ------------------------------------- | ----------------------------- | ------------------ | --------------------------- |
| `constraint`        | 检查节点是否满足特定约束条件          | `node`, `mode`                | `bool`             | 目前支持广播约束检查        |
| `check_attrs`       | 验证节点属性是否满足AttrCheck条件     | `node`, `attrcheck`           | `bool`             | 调用AttrCheck的函数进行验证 |
| `attr_to_tensor`    | 将节点属性转换为张量值（opset兼容性） | `node`, `pindices`, `op_type` | `list[np.ndarray]` | 处理高低opset版本的差异     |
| `process_low_opset` | 处理低版本opset的兼容性问题           | `node`, `pninp`, `nofdiff`    | `list[np.ndarray]` | 将属性转换为输入张量        |
| `match_input`       | 匹配节点的输入是否符合模式要求        | `node`, `ninp`, `pninp`       | `bool`             | 核心匹配逻辑，处理OuterNode |
| `match_node`        | 匹配单个节点是否符合PatternNode定义   | `node`, `pnode`               | `bool`             | 综合检查输入、约束、属性    |
| `match_pattern`     | 在图中搜索匹配完整模式的子图          | `reform_info`                 | `list[ReformInfo]` | 顺序匹配，支持模式重置      |
| `reset_outer_node`  | 重置模式中OuterNode的状态             | `pattern`                     | None               | 清空OuterNode的输出信息     |

**4. 图变换和优化**

| 函数名            | 功能描述                       | 参数              | 返回值 | 备注                           |
| ----------------- | ------------------------------ | ----------------- | ------ | ------------------------------ |
| `replace_pattern` | 将匹配的子图替换为优化后的实现 | `matched_pattern` | None   | 创建新节点，删除旧节点         |
| `graph_opt`       | 递归执行模式匹配和替换直到收敛 | None              | None   | 固定点算法，重复直到无更多匹配 |

**5. 图清理工具**

| 函数名                 | 功能描述                         | 参数 | 返回值 | 备注                   |
| ---------------------- | -------------------------------- | ---- | ------ | ---------------------- |
| `remove_unused_tensor` | 移除图中未被使用的张量和节点     | None | None   | 清理权重和Constant节点 |
| `remove_duplicate`     | 移除具有相同输入和操作的重复节点 | None | None   | 优化图结构，减少冗余   |
| `remove_cast`          | 移除冗余的类型转换节点           | None | None   | 简化数据流，提高效率   |
| `remove_invalid_slice` | 移除输出形状为0的无效Slice节点   | None | None   | 清理无意义的切片操作   |

​	**核心函数：**

​		**1.match_input**

​			这是 match_node 的输入匹配核心：把真实节点的 ninp（实际输入）和 pattern 的 pninp（pattern 定义的输入）逐一比对，并处理多种情形（OuterNode、tensor 值对比、attr 注入等）。

```python
    def match_input(self, node, ninp, pninp):
        nofdiff = len(pninp) - len(ninp)        #计算 pattern 的输入数量与 node 实际输入数量的差异。若 pattern 要求比实际更多（nofdiff>0），有可能是 pattern 期待某些输入来自 attribute
        if nofdiff >= 0:        #若 pattern inputs 不少于 node inputs：
            ex_tensor_value = self.process_low_opset(node, pninp, nofdiff)  #调用上面的 process_low_opset，尝试把多出的 pattern inputs 从 node attribute（如果存在）转换为 tensor 值列表
            ninp = ninp[:] + ex_tensor_value    #先拷贝 ninp[:]（防止修改原始列表），然后把 ex_tensor_value 追加到末尾
        else:   #若 nofdiff < 0（实际 node inputs 比 pattern 多），认为 opset/模式不匹配；在严格模式抛错，非严格模式打印并返回 False（不匹配）。
            if self.rigorous:
                raise RuntimeError("Unsupport opset for {}".format(node.op_type))
            else:
                print("Warning unsupport opset for {} skipped.".format(node.op_type))
                return False

        for pnode, node_name in zip(pninp, ninp):   #把 pninp 与处理后的 ninp zip 配对逐项比较
            if isinstance(pnode, OuterNode):    #如果 pattern 输入是 OuterNode
                if pnode.is_tensor: #若该 OuterNode 标记为 tensor
                    tensor_value = node_name    #暂把 node_name 赋给 tensor_value
                    if not type(node_name) == np.ndarray:   #检查输入是否是numpy数组，目的是区分张量名称和实际张量值
                        # check if tensor exist
                        if not self.find_tensor(node_name): #检查该名字是否在常量集合（initializer 或 Constant）中，确保张量在模型中存在
                            return False    #若不是，则匹配失败
                        if pnode.attr_name or pnode.tensor_value is not None:   #如果 pnode 还需要把该张量当作属性（attr_name 非空），或 pnode.tensor_value（pattern 期望的具体值）不为 None，就取实际 tensor 值
                            tensor_value = self.get_tensor_value(node_name)

                    if pnode.tensor_value is not None:  #如果 pattern 指定了一个确切的 tensor 值（比如 tensor_value=2），需要进行值相等检查：
                        # check tensor value
                        # tensor_value = self.get_tensor_value(node_name)
                        _tensor_value = copy.deepcopy(tensor_value) #拷贝以免修改原始（通常为 numpy array 或标量）。
                        if _tensor_value.shape == ():   #若为标量，扩为 1D 以便形状比较一致。
                            _tensor_value = np.expand_dims(_tensor_value, 0)
                        if pnode.tensor_value.shape != _tensor_value.shape \
                           or (pnode.tensor_value != _tensor_value).any():
                            return False    #先比较形状，再做逐元素不等检查；若任一不匹配则返回 False。
                    if pnode.attr_name: #如果 OuterNode 指定了 attr_name（意味着该 tensor 会在替换的新节点中作为 attribute 使用），则把 tensor_value 存入 pnode.attr_value，供后面 PatternNode.get_attr() 使用。
                        # tensor_value = self.get_tensor_value(node_name)
                        pnode.attr_value = tensor_value
                if not pnode.output or pnode.is_tensor: #如果 pnode.output 为空或 pnode.is_tensor 为 True
                    pnode.output.clear()    #清空 OuterNode 的 output 列表
                    pnode.output.append(node_name)  #把当前 node_name（通常为字符串名）记录到 pnode.output。
            if not node_name in pnode.output:       #对于非 OuterNode，检查 node_name 是否包含在 pnode.output
                return False    #若不包含则匹配失败。
        return True
```

​		**2.match_node**

​			匹配单个节点 node 是否符合 pattern 节点 pnode 的定义。参数为node和pnode，分别为ONNX 节点对象，通常来自 self.nodes 列表，表示实际图中的节点。PatternNode 对象，定义了一个 pattern 的节点，包括 op_type、输入、属性等。

```python
    def match_node(self, node, pnode):
        matched = self.match_input(node, node.input, pnode.input)   # 尝试按照正序匹配 node 的输入和 pattern 节点的输入
         # 对于 Add / Mul 这类 commutative (交换律) 的节点，如果正序匹配失败，尝试逆序匹配
        if not matched and (node.op_type == 'Mul' or node.op_type == 'Add'):
            # naive method, need to be discussed
            matched = self.match_input(node, node.input[::-1], pnode.input)
        if matched:
            # 如果 pattern 节点 pnode 有额外的约束条件 constraint，则检查
            # process constraint and check attrs
            if pnode.constraint:
                matched = self.constraint(node, pnode.constraint)
            
             # 如果匹配成功且有属性检查函数 attrcheck，则检查属性
            if matched and pnode.attrcheck:
                matched = self.check_attrs(node, pnode.attrcheck)
                if not matched:
                    return matched      ## 如果属性不匹配，直接返回 False
            # update output and needed attr

            # 匹配成功后，更新 pattern 节点的输出和当前需要记录的属性值
            attr_value = []
            if pnode.cur_attr_name:
                attrs = get_node_attrs(node)    # 获取 node 的属性字典
                for key in pnode.cur_attr_name:
                    attr_value.append(attrs[key])   # 保存需要记录的属性值
            pnode.update(node.output, attr_value)   # 更新 pnode 的 output 与属性值
        return matched
```

​		**3.match_pattern**

​			在整个图 self.nodes 中匹配一个 pattern (reform_info)。参数为reform_info：pattern 定义，包括 src_nodes (pattern 节点列表) 和 dst_nodes (替换节点)。

```python
    def match_pattern(self, reform_info):
        name = reform_info.name
        pnodeIdx = 0    # pattern 中当前待匹配节点的索引
        matched_patterns = []    # 保存匹配成功的 pattern 子图
        unused_nodes = []   # 临时保存匹配成功的 node 节点
        pattern = reform_info.src_nodes # pattern 的节点列表
        patternLens = len(pattern)  # pattern 长度
        for node in self.nodes:
            matched = False
            if node.op_type == 'Constant':  # 跳过 Constant 节点
                continue
            if node.op_type == pattern[pnodeIdx].op_type:    # 正序匹配当前 pattern 节点
                matched = self.match_node(node, pattern[pnodeIdx])
            if matched:
                pnodeIdx += 1
                unused_nodes.append(node)
                if pnodeIdx == patternLens:  # 如果 pattern 已经完全匹配
                    newNodes = copy.deepcopy(reform_info.dst_nodes) # 深拷贝 dst_nodes，用于替换
                    matched_patterns.append(ReformInfo(name, unused_nodes, newNodes))    # 保存匹配信息
                    pnodeIdx = 0    # 重置索引和临时节点
                    unused_nodes = []
                    self.reset_outer_node(pattern)  # 清空 pattern 中 outer node 的输出
            else:   # 匹配失败，重置状态
                pnodeIdx = 0
                unused_nodes = []
                self.reset_outer_node(pattern)
                # 尝试匹配 pattern 的第一个节点
                if node.op_type == pattern[0].op_type:
                    matched = self.match_node(node, pattern[0])
                if matched:
                    pnodeIdx += 1
                    unused_nodes.append(node)
                else:
                    self.reset_outer_node(pattern)
        return matched_patterns
```

​		**4.replace_pattern**

​			它将匹配到的pattern子图替换成新节点子图。核心作用是处理OuterNode生成新的Constant节点，构建新的ONNX节点，更新节点映射，移除原子图节点并清理冗余tensor。

```python
    def replace_pattern(self, matched_pattern):
        # Recently we assume that subgraph to be replace has only one output
        # TODO: implement for multi-output cases
        for reform_info in matched_pattern:     # 遍历每一个匹配到的 pattern
            src_nodes = reform_info.src_nodes   # 原始节点序列
            dst_nodes = reform_info.dst_nodes   # 替换节点序列
            last_node = src_nodes[-1]      # 取最后一个节点，作为子图输出
            insert_idx, _ = self.get_node(last_node.output[0])   # 获取最后一个节点输出在 self.nodes 中的位置，用于插入新节点
            out = last_node.output  # 子图输出名列表
            for i, new_node in enumerate(dst_nodes):    # 遍历新节点列表，逐个插入
                if i == len(dst_nodes) - 1:  # dst_nodes 最后一个节点使用原子图输出名，其他临时生成名字
                    _output = out
                else:
                    _output = ["{}_{}".format(last_node.name, i)]
                new_node.output.clear() # 清空原有输出
                new_node.output.extend(_output) # 更新输出名
                _input = [] # 处理 new_node 输入
                for j, inode in enumerate(new_node.input):
                    if isinstance(inode, OuterNode) and len(inode.output) == 0:
                        # insert new tensor node     # 插入新的 Constant 节点
                        if inode.tensor_value is None:
                            raise ValueError("New tensor node must with tensor_value.")
                        tensor_value = np.array(inode.tensor_value)
                        tensor_name = _output[0] + "_in_{}".format(j)
                        new_onnx_node = onnx.helper.make_node("Constant",
                                                              name=tensor_name,
                                                              inputs=[],
                                                              outputs=[tensor_name],
                                                              value=onnx.helper.make_tensor(
                                                                  "value", onnx.TensorProto.FLOAT,
                                                                  tensor_value.shape, tensor_value))
                        self.nodes.insert(insert_idx, new_onnx_node)
                        insert_idx += 1
                        inode.output.extend(new_onnx_node.output)
                    _input.append(inode.output[0])
                # insert new pattern node   # 构建新的 pattern 节点
                new_node = onnx.helper.make_node(new_node.op_type,
                                                 name=_output[0],
                                                 inputs=_input,
                                                 outputs=_output,
                                                 **new_node.get_attr())
                self.nodes.insert(insert_idx, new_node)
                insert_idx += 1
            node_name = _output[0]      # 更新 node_name_mapping，用于追踪替换前后的节点名
            src_oname = "{}_{}".format(node_name, src_nodes[-1].op_type)
            dst_oname = "{}_{}".format(node_name, dst_nodes[-1].op_type)
            assert (src_oname not in self.node_name_mapping)
            self.node_name_mapping[src_oname] = dst_oname
            # clear up            # 移除原始 src_nodes
            for node in src_nodes:
                self.nodes.remove(node)
            self.remove_unused_tensor()     # 移除未使用的 Constant 节点
            # print("[ONNX OPT] RULE <<{}>> applied \n".format(reform_info.name))
```

​		**5.graph_opt**

​			用于递归执行所有pattern的匹配和替换，知道没有更多替换可做。是整体图优化流程的核心函数。

```python
    def graph_opt(self):
        replaced = False    # 标志是否有节点被替换
        for reform_info in self.reform_info_list:   # 遍历每个重写规则
            matched_pattern = self.match_pattern(reform_info)   # 匹配 pattern
            if len(matched_pattern) > 0:    # 如果匹配到 pattern
                replaced = True # 标记替换成功
            self.replace_pattern(matched_pattern)   # 执行替换

        if replaced:    # 如果有替换发生
            self.graph_opt()    # 递归优化，处理新生成的子图
```

## OnnxConverter.py文件

### 		整体架构

​			有三个类：

​				1.BaseNode类，这是将一个通用操作的抽象信息封装成一个结构化的，易于操作的Python对象，作为计算图中节点的通用表示模板，存储节点的所有关键信息。

​				2.OnnxNode类，这个类是专门为了封装和表示 ONNX 模型中的节点而设计的。它继承自BaseNode。它输入是原始的、底层的、与 ONNX protobuf 格式紧密耦合的 NodeProto 对象。输出是 一个干净的、标准化的、易于处理的 BaseNode 子类对象。

​				3.OnnxConverter类， 继承自BaseConverter，提供基础的转换功能 ， 专门负责将ONNX模型转换为MLIR格式 。

### 		主要流程

​			 整体流程为：ONNX模型 → 预处理 → 节点转换 → MLIR生成 → 权重文件 

​			 详细流程如下：

​				初始化阶段：加载ONNX模型（ load_onnx_model ），模型简化和优化（ model_simplify ），形状推理和分配（ input_shape_assign ），初始化MLIR导入器（init_MLIRImporter）

​				转换阶段： 创建输入操作（ generate_mlir） ， 逐个转换ONNX节点 （onnxop_factory里对应了一系列转换函数）， 处理控制流（ convert_if_op ） ， 创建返回操作 （ generate_mlir ）

​				生成阶段： 生成MLIR文件（ generate_mlir ） ， 保存权重文件 （ WeightToNpz ）

​				调用关系

```
# 主入口
OnnxConverter.__init__()
    ├── load_onnx_model()
    │   ├── select_output()
    │   ├── model_simplify()
    │   │   ├── ConstantFolding().run()
    │   │   ├── onnxsim.simplify()
    │   │   └── onnx_opt()
    │   ├── input_shape_assign()
    │   └── get_dynamic_op_shape()
    └── init_MLIRImporter()

# 转换入口
generate_mlir()
    ├── mlir.create_input_op()  # 创建输入
    ├── onnxop_factory[op_type](node)  # 转换节点
    │   ├── convert_if_op()
    │   │   └── parse_subgraph()
    │   └── convert_loop_op()
    │       └── parse_subgraph()
    ├── mlir.create_return_op()  # 创建返回
    ├── mlir.print_module()  # 生成MLIR
    └── WeightToNpz()  # 保存权重
```

​		**主要函数：**

​			**1. 初始化和配置函数**  __init__ 

​				核心功能： 构造函数，初始化转换器的所有配置参数 。 设置动态形状处理模式 ， 初始化数据类型映射表 ， 调用模型加载和MLIR导入器初始化 ， 创建算子工厂字典（onnxop_factory）。

```python
    def __init__(self,
                 model_name: str,   #指定输出 MLIR 文件的名称（或模型标识符）。生成的文件通常命名为 {model_name}.mlir。
                 onnx_file, #指定要转换的 ONNX 模型的来源。，通常是 str（文件路径）或一个已加载的 ONNX ModelProto 对象。
                 input_shapes: list,    #指定模型输入张量的形状。类型： List[List[int]]
                 output_names: list,    #指定模型的哪些输出节点需要被保留和转换。这可以用于只转换模型的一部分（例如，去除最后的损失函数层）。类型： List[str]
                 #预处理与校准参数 (Preprocessing & Calibration)
                 test_input,    #通常是 List[np.ndarray] 或一个 .npz 文件路径。提供一个或多个符合 input_shapes 的真实输入数据样本（例如，一张图片的 tensor）。
                 preprocess_args: dict = {},    #指定如何对 test_input 进行预处理，使其符合模型原始训练时预期的输入格式。
                #形状与优化参数 (Shape & Optimization Parameters)
                 static_shape=True,
                 onnx_sim_param="", #传递给 onnxsim（ONNX 简化器）的额外参数字符串。用于更精细地控制简化过程。
                 dynamic_shape_input_names=[],  # 当 static_shape=False 时，指定哪些输入的名称是动态的（其形状在运行时变化）。
                 shape_influencing_input_names=[],  # 指定哪些输入不仅自身是动态的，其值还会影响后续操作的计算图结构或张量形状（例如，Reshape 操作的目标形状输入）。这需要编译器特别处理。
                 dynamic=False, 
                 dump_final_opt=True,   # 是否在应用所有优化（如 onnxsim）后，将优化后的 ONNX 模型保存到文件中（例如 {model_name}_final_opt.onnx）。用于调试转换过程。
                 op_custom_shape: dict = {},    #允许用户手动覆盖或指定模型中特定操作的输出形状。键是操作名，值是期望的形状。用于处理形状推理可能不准确的特殊情况。
                 replace_topk_indices=False,
                 do_onnx_sim=True):
        super().__init__()  #调用父类的构造函数

        self.dynamic_shape_input_names = dynamic_shape_input_names      #保存用户传入的动态形状相关参数到实例变量中，供后续处理使用。
        self.shape_influencing_input_names = shape_influencing_input_names
        # self.dynamic = dynamic
        if self.dynamic_shape_input_names or self.shape_influencing_input_names:
            self.dynamic = "manual"     #如果用户传入了任何动态形状或影响形状的输入名称，设置动态模式为“manual”（手动模式）
            dynamic = True  #确保后续逻辑知道处于动态模式。
        elif dynamic:       #如果用户只是简单设置了 dynamic=True，设置动态模式为"auto"（自动模式）。
            self.dynamic = "auto"
        else:       #默认情况，关闭动态形状处理，使用完全静态模式。
            self.dynamic = "off"
        self.run_mode = "DYNAMIC" if dynamic else "STATIC"  #根据最终的dynamic值设置run_model字符串，用于后续的日志记录或MLIR生成。
        self.dynamic_shapes = dict()        #初始化一个空字典
        self.op_custom_shape = op_custom_shape  #保存用户传入的自定义形状
        self.test_input = test_input    #保存用户传入的测试输入数据
        self.model_name = model_name    #保存用户传入的模型名称参数
        self.weight_file = "{}_top_origin_weight.npz".format(model_name)    #生成权重文件名，格式为"模型名_top_origin_weight.npz"，用于保存从ONNX模型中提取的权重。
        self.model = None   #初始化模型和MLIR导入器对象为None，稍后通过方法调用进行实际初始化。
        self.mlir = None
        self.node_name_mapping = {}  # used in onnx opt #初始化空字典，用于在ONNX优化过程中维护节点名称映射关系。
        self.np_onnx_dt_map = [
            None, np.float32, np.uint8, np.int8, np.int16, np.int16, np.int32, np.int64, None,
            np.bool_, np.float16, np.float64, np.uint32, np.uint64, None, None, None
        ]       #创建ONNX数据类型到NumPy数据类型的映射表。列表索引对应ONNX数据类型枚举值，值是对应的NumPy类型。
        self.do_onnx_sim = do_onnx_sim      #保存是否进行ONNX简化以及简化参数。
        self.onnx_sim_param = onnx_sim_param
        self.origin_output_names = output_names.copy()  #创建输出名称列表的副本，保留原始输出名称，防止后续修改影响原始数据。
        self.load_onnx_model(onnx_file, input_shapes, output_names, static_shape, dump_final_opt)   #调用方法加载和预处理ONNX模型
        self.init_MLIRImporter()    #初始化MLIR导入器，创建用于生成MLIR代码的核心工具。
        self.unranked_type = self.mlir.get_tensor_type([])  #获取无指定维度的张量类型（如tensor<*xf32>），用于处理动态形状。
        # some onnx may have strange domain, such as "ai.onnx.ml"   一些onnx可能具有奇怪的域，例如"ai.onnx.ml"
        for ver_info in self.model.opset_import:    #遍历模型的算子集导入信息，找到标准ONNX域("")的版本号并保存。opset_import 是 ONNX 模型的一个属性，它是一个列表，包含模型所使用的所有算子集（Operator Set）的版本信息
            if ver_info.domain == "":   #检查当前算子集的域（domain）是否为空字符串，空字符串 "" 表示标准的 ONNX 域（即 ai.onnx），#https://www.cnblogs.com/qsbye/p/18815786这是有关onnx算子集版本的链接
                self.opset = ver_info.version   #如果找到标准域，将其版本号赋值给 self.opset 实例变量
                break   #找到标准域的版本号后，立即退出循环
        self.preprocess_args = {}   #初始化一个空字典，用于存储最终生效的预处理参数
        if 'preprocess_list' in preprocess_args:    #检查用户提供的 preprocess_args 字典中是否存在 'preprocess_list' 键
            if preprocess_args['preprocess_list'] is not None:  #如果值不是 None，则遍历 preprocess_list 列表中的每个元素（input_index）
                for input_index in preprocess_args['preprocess_list']:
                    assert (0 < input_index <= self.num_input   #对于列表中的每个 input_index，使用断言验证其有效性
                            and "Please check --preprocess_list is right input")
            else:   #如果 'preprocess_list' 的值是 None
                preprocess_args['preprocess_list'] = [i + 1 for i in range(self.num_input)] #使用列表推导式生成一个默认的预处理列表，结果是一个从1到self.num_input的整数列表，表示所有的输入都需要预处理
        if 'channel_format' in preprocess_args: #检查用户提供的 preprocess_args 字典中是否存在 'channel_format' 键
            if preprocess_args['channel_format'] != "none": #如果 'channel_format' 键存在，进一步检查它的值是否不是字符串 "none"
                self.preprocess_args = preprocess_args  #如果通道格式不是 "none"（例如是 "BGR" 或 "RGB"），则将整个 preprocess_args 字典赋值给 self.preprocess_args，这意味着只有当用户明确指定了非 "none" 的通道格式时，预处理参数才会被真正激活和使用
        self.converted_nodes = list()   #初始化一个空列表 self.converted_nodes，这个列表用于在后续的图转换过程中记录已经成功转换为 MLIR 操作的节点
        self.subgraph_initializer = None    #将 self.subgraph_initializer 初始化为 None
        self.replace_topk_indices = replace_topk_indices    #将构造函数参数 replace_topk_indices 的值存储到同名的实例变量中，这个布尔标志控制是否对 TopK 算子的索引输出进行特殊处理或替换

        self.onnxop_factory = {
        					......	#省略
        					}
```

​		**2. 模型加载和处理函数**

​			  **load_onnx_model** 

​			核心功能： 加载和预处理ONNX模型的核心函数 。 加载ONNX模型文件或对象 ， 选择指定的输出节点（如果提供） ， 获取输入名称和数量 ， 执行模型简化优化 ， 提取并保存模型权重 ， 应用图优化（如LayerNorm、GELU融合等） 。

```python
    def load_onnx_model(self,
                        onnx_file,
                        input_shapes: list,
                        output_names: list,
                        static_shape=True,
                        dump_final_opt=True):
        if isinstance(onnx_file, str):  #如果 onnx_file 是字符串，视为文件路径，使用 onnx.load() 加载模型
            self.model = onnx.load(onnx_file)
        else:
            self.model = onnx_file   #否则，直接使用传入的模型对象
        if output_names:    #如果提供了输出名称，调用 select_output 方法选择指定输出
            self.select_output(output_names)
        self.input_names = self.get_input_names(self.model) #获取模型的输入名称列表
        self.num_input = len(self.input_names)  #计算输入数量
        self.dynamic_input_names_auto_assign()  #调用方法自动分配动态输入名称
        if not self.dynamic_shape_input_names:  #根据是否存在动态形状输入，执行不同的处理流程
            self.input_shape_assign(input_shapes)   #如果没有动态形状输入，分配输入形状并记录日志
            logger.info("Input_shape assigned")
            if static_shape:
                self.model_simplify()   #如果使用静态形状则执行模型简化
        else:
            self.model_simplify(input_shapes)   #如果有动态形状输入，执行模型简化并传入输入形状参数

        self.input_shapes = self.get_input_shapes(self.model)   #获取模型的输入形状
        self.input_types = self.get_input_types(self.model) #获取模型的输入类型
        self.output_types = self.get_output_types(self.model)   #获取模型的输出类型
        # add all weight
        for tensor in self.model.graph.initializer: #遍历模型中的所有权重/常量张量
            name = tensor.name  #获取当前权重张量的名称
            data = numpy_helper.to_array(tensor).astype(np.float32) #将权重张量转换为 NumPy 数组并转换为 float32 类型
            self.addWeight(name, data)  #调用方法将权重添加到转换器中
            # TODO: for quantized onnx, keep the same type  #注释说明对于量化 ONNX 模型，需要保持原始数据类型
        self.get_output_name(self.model.graph)  #调用方法获取输出名称
        # self.add_shape_info(self.model.graph)
        if self.dynamic:    #如果处于动态模式，获取动态操作的形状信息
            self.get_dynamic_op_shape(self.model)
        self.onnx_file = "{}_opt.onnx".format(self.model_name)  #生成优化后的 ONNX 文件名
        file_mark(self.onnx_file)   #标记文件，可能用于后续清理
        try:
            onnx.save(self.model, self.onnx_file)   #尝试保存优化后的 ONNX 模型
        except Exception as E:
            if "The proto size is larger than the 2 GB limit." in str(E):# 捕获保存异常，检查是否是模型大小超过 2GB 限制
                logger.info(    #记录信息日志，说明将尝试使用外部数据保存
                    "LOG: Try to save {} by using save_as_external_data to save tensors separately from the model file."
                    .format(self.onnx_file))
                onnx.save(self.model,
                          self.onnx_file,
                          save_as_external_data=True,
                          location=self.model_name + "_external_data",
                          convert_attribute=True)   #使用外部数据方式保存模型，将张量数据与模型结构分开存储
            else:
                raise E #如果不是大小限制错误，重新抛出异常
        strip_model = onnx.ModelProto() #创建一个新的 ONNX 模型原型对象
        strip_model.CopyFrom(self.model)    #从原始模型复制内容到新模型
        strip_model.graph.ClearField("initializer") #清除新模型中的初始权重字段，只保留模型结构
        with open(self.onnx_file + ".prototxt", "w") as f:  #将去除权重的模型结构保存为文本格式（prototxt）
            f.write(str(strip_model))
        if static_shape:
            # fuse ops such as layernorm gelu...
            self.model, self.node_name_mapping = onnx_opt(self.model, dump_final_opt)   #如果使用静态形状，执行额外的 ONNX 优化（如层归一化、GELU 等操作的融合）
```

​			 **model_simplify** 

​				核心功能： 对ONNX模型进行简化和优化 。

​				优化步骤： 常量折叠，使用ConstantFolding类预先计算常量表达式 。 ONNX简化，调用onnxsim库进行模型结构简化 。 形状分配，为动态输入分配具体形状 。 二次常量折叠: 再次进行常量折叠优化 

```python
def model_simplify(self, input_shapes=[]):
        if not self.do_onnx_sim:    #检查是否启用了ONNX简化功能
            return  #如果没启用，直接返回
        # Do constantFolding before onnxsim to avoid onnxsim bug (such as run yolox)    #注释说明为什么在 ONNX 简化之前先进行常量折叠   背景: 某些模型（如 YOLOX）在 ONNX 简化器中存在 bug，先进行常量折叠可以避免这些问题
        try:
            self.model = ConstantFolding(self.model, self.test_input,
                                         self.dynamic_shape_input_names).run()  #优化后的模型赋值回 self.model
        except:
            logger.warning("ConstantFolding failed.")   #如果常量折叠失败，记录警告信息但不中断程序
        logger.info("ConstantFolding finished") #记录常量折叠完成的信息日志
        try:    #解析 ONNX 简化器参数字符串
            onnx_sim_param = self.onnx_sim_param.split(',') #将参数字符串分割为列表
            skip_fuse_bn = "skip_fuse_bn" in onnx_sim_param #检查是否包含跳过批量归一化融合的参数
            logger.info(f'skip_fuse_bn:{skip_fuse_bn}') #记录日志，显示是否跳过 BN 融合
            self.model, _ = onnxsim.simplify(self.model,    #调用 ONNX 简化器进行模型优化，简化后的模型赋值回 self.model，忽略第二个返回值
                                             skip_fuse_bn=skip_fuse_bn,
                                             skip_constant_folding=True,
                                             skip_shape_inference=True)
        except: #捕获并处理 ONNX 简化过程中可能出现的异常
            logger.warning("onnxsim opt failed.")
        logger.info("Onnxsim opt finished") #记录信息日志，表明 ONNX 简化步骤已完成
        if self.dynamic_shape_input_names:  #检查是否存在动态形状输入
            self.input_shape_assign(input_shapes)   #调用方法为动态输入分配具体形状
            logger.info("Input_shape assigned") #记录信息日志，表明输入形状已分配
        # Do constantFolding after onnxsim to avoid onnxsim bug (such as run ppyolo_tiny)
        try:    #第二次常量折叠
            self.model = ConstantFolding(self.model, self.test_input,
                                         self.dynamic_shape_input_names).run()
        except:
            logger.warning("ConstantFolding failed.")
        logger.info("ConstantFolding finished")
```

​		  **MLIR生成函数** 

​				 **generate_mlir** 

​					功能： 将ONNX模型转换为MLIR格式的主函数 

​					流程：创建输入操作: 为每个模型输入创建MLIR输入操作

​							   节点转换: 遍历所有ONNX节点，调用对应的转换函数

​							   算子支持检查: 验证所有算子都有对应的转换实现

​							   创建输出操作: 生成MLIR返回操作

​							   保存文件: 输出MLIR文件和权重文件

```python
    def generate_mlir(self, mlir_file: str):
        """convert all to mlir"""       #将模型转换为MLIR格式
        # add input op
        input_data = None
        if self.shape_influencing_input_names:  #检查是否存在影响形状的输入名称
            test_file = ''  #初始化测试文件路径
            if isinstance(self.test_input, list):   #检查测试输入是否为列表
                assert self.test_input[0].endswith('.npz')  #断言test_input的第一个元素是.npz文件
                test_file = self.test_input[0]  #将self.test_input第一个元素赋值给test_file
            elif isinstance(self.test_input, str):  #如果不是列表，则检查是否是字符串
                assert self.test_input.endswith('.npz') #断言字符串以.npz结尾
                test_file = self.test_input #将self.test_input赋值给test_file
            else:   #如果既不是列表也不是字符串，则抛出错误 ：当设置了shape_influencing_input_names时必须提供测试输入npz文件
                raise ValueError(
                    "test_input npz file is necessary when shape_influencing_input_names is set")
            input_data = np.load(test_file) #加载测试数据
        for idx, _name in enumerate(self.input_names):  #遍历所有输入名称
            kwargs = copy.deepcopy(self.preprocess_args)    #深拷贝预处理参数
            if _name in self.shape_influencing_input_names: #检查当前输入名称是否在影响形状的输入名称列表中
                assert input_data[_name].ndim == 1, "input shape tensor should be 1D tensor"    #确认输入形状张量是一维的
                kwargs['shape_tensor'] = input_data[_name]  #设置形状张量参数
            input_ = self.mlir.create_input_op(self.get_loc(_name), idx, kwargs)    #创建输入操作
            self.addOperand(_name, input_)   # 添加操作

        def NoneAndRaise(node): # # 定义不支持操作的处理函数
            raise RuntimeError("{} Op not support now".format(node.op_type))

        self.converted_nodes.clear()    # 清空已转换节点列表
        for n in self.model.graph.node: #遍历模型图中的所有节点
            node = OnnxNode(n)
            if n.op_type in ["Gather"]: # 如果节点类型是Gather
                input_shape = dict()    # 初始化输入形状字典
                for input in n.input:   # 遍历节点的所有输入
                    input_shape[input] = self.get_shape_for_node(self.model.graph.input,
                                                                 self.model.graph.output,
                                                                 self.model.graph.value_info, input)    ## 获取输入形状并存储到字典中
                output_shape = dict()   # 初始化输出形状字典
                for output in n.output: # 遍历节点的所有输出
                    output_shape[output] = self.get_shape_for_node(self.model.graph.input,  # 获取输出形状并存储到字典中
                                                                   self.model.graph.output,
                                                                   self.model.graph.value_info,
                                                                   output)
                node.shape_info["input"] = input_shape  # 将形状信息存储到节点中
                node.shape_info["output"] = output_shape
            self.converted_nodes.append(node)   #将节点添加到已转换节点列表
        # checkout all type is supported     检查所有操作类型是否支持
        unsupported = set()
        for n in self.converted_nodes:  # 遍历所有已转换节点
            if n.op_type not in self.onnxop_factory:    #如果节点类型不在支持的工厂函数中
                unsupported.add(n.op_type)  #添加到不支持集合中
        if unsupported: ## 如果有不支持的操作类型，抛出运行时错误
            raise RuntimeError("Op not support:{}".format(unsupported))

        for n in self.converted_nodes:  # 遍历所有已转换节点
            self.onnxop_factory.get(n.op_type, lambda x: NoneAndRaise(x))(n)    # # 获取对应的处理函数，如果没有则使用NoneAndRaise函数
        # add return op
        return_op = list()  ## 初始化返回操作列表
        # Set output
        final_output_names = [] # 设置最终输出名称
        if self.origin_output_names:    # 如果存在原始输出名称
            final_output_names = self.origin_output_names   #使用原始输出名称
        else:
            final_output_names = self.output_names  # 使用当前输出名称
        for idx, _name in enumerate(final_output_names):    # 遍历所有最终输出名称
            op = self.getOperand(_name) #获取对应的操作数
            return_op.append(op)    # 添加到返回操作列表

        self.mlir.create_return_op(return_op)   #创建返回操作
        mlir_txt = self.mlir.print_module() # 打印模块内容
        with open(mlir_file, "w") as f: #写入MLIR文件
            f.write(mlir_txt)
        self.WeightToNpz(self.weight_file)   # 将权重保存为NPZ文件
        logger.info("Save mlir file: {}".format(mlir_file)) # 记录日志信息
```

​				 **init_MLIRImporter** 

​					功能： 初始化MLIR导入器 

​					流程：输入和输出形状列表

​							   模型名称和平台信息

​							   输入数据类型

​							   运行模式（静态/动态）

```python
    def init_MLIRImporter(self):
        input_shapes = list()   #初始化输入形状列表
        for _name in self.input_names:  #遍历所有输入名称
            input_shapes.append(self.getShape(_name))   #获取每个输入的形状并添加到列表中
        output_shapes = list()  #初始化输出形状列表
        output_shapes = len(self.output_names) * [[]]   #创建与输出名称数量相同的空列表
        for i, o in enumerate(self.output_names):   #遍历输出名称
            if o in self.dynamic_shapes:    #如果输出名称在动态形状字典中
                output_shapes[i] = self.getDynamicShape(o)  #获取动态形状并赋值给对应输出
        # init importer 初始化MLIR导入器，传入输入形状、输出形状、模型名称、平台类型、输入类型和运行模式
        self.mlir = MLIRImporter(input_shapes,
                                 output_shapes,
                                 self.model_name,
                                 Platform.ONNX,
                                 self.input_types,
                                 run_mode=self.run_mode)
        self.weight_file = self.mlir.weight_file    #将导入器的权重文件路径保存到实例变量中
```



## MLIRImporter.py

​			 MLIRImporter是一个专门的MLIR代码生成器，负责：  创建和管理MLIR上下文 ， 定义函数签名和模块结构 ， 生成各种MLIR操作 ， 管理类型系统和插入点 。

​		 **关键功能模块：** 

​			  **类型系统** (`get_tensor_type`, `ArrayAttr`) ： 处理静态/动态形状张量 ， 支持多输出类型推导 ， 完整的Python到MLIR类型映射 

​			 **函数声明** (`declare_func`) ： 生成完整的MLIR模块模板 ， 设置函数签名和属性， 管理插入点和基本块 

​			 **操作创建** (`create_*_op`系列) ：输入/权重/返回操作创建， 控制流操作支持(If/Loop) ， 子图和嵌套结构处理 

​			上下文管理 (插入点栈、区域管理) ： 支持复杂的嵌套代码生成 ， 资源自动清理和错误处理 

​		**主要函数：**

​			**1. 初始化函数** 

​				核心功能： 创建MLIR上下文和位置管理 ， 初始化类型系统映射 ， 设置模型基础信息 ， 可选择是否立即声明函数 

```python
    def __init__(self,
                 input_shapes: list,    # 输入张量形状列表
                 output_shapes: list,   # 输出张量形状列表
                 model_name: str,       # 模型名称，用于生成MLIR模块名
                 platform: str = Platform.ONNX, # 源框架平台
                 input_types: list = [],    # 输入数据类型，默认F32
                 output_types: list = [],   # 输出数据类型，默认F32
                 state: str = State.TOP_F32,
                 do_declare: bool = True,
                 run_mode: str = "STATIC",  # 运行模式：STATIC/DYNAMIC
                 no_save: bool = False, # 是否禁用权重文件保存
                 weight_file: str = ""):    # 自定义权重文件名
        """
            input_shape: List[List], put module input shape. ex: [[1, 3, 224, 224]]
            output_shape: List, put module output shape. ex: [1, 1000]
        """
        #通过断言确保输入有效性，所有重要参数都作为实例变量存储。
        assert (len(model_name) > 0)    # 确保模型名称非空
        self.no_save = no_save  # 保存权重文件保存标志
        self.model_name = model_name    # 存储模型名称
        self.state = state  # 存储模型状态
        self.chip = "ALL"   # 默认支持所有芯片类型
        self.run_mode = run_mode    # 存储运行模式
        self.platform = platform    # 存储源平台信息
        if weight_file == "":   #如果用户未指定权重文件，使用标准命名规则生成，否则使用用户指定的路径。
            self.weight_file = get_weight_file(self.model_name, self.state, self.chip)
        else:
            self.weight_file = weight_file
        self.ctx = Context()    # 创建MLIR上下文，管理所有MLIR对象
        self.ctx.allow_unregistered_dialects = True # 允许使用未注册的dialect
        self.loc = Location.unknown(self.ctx)   # 创建未知位置对象，用于调试
        self.ctx.__enter__()    # 进入上下文管理器
        self.loc.__enter__()    # 进入位置上下文
        self.input_shapes = input_shapes    # 存储输入形状
        self.output_shapes = output_shapes  # 存储输出形状
        self.num_input = len(self.input_shapes) # 计算输入数量
        self.num_output = len(self.output_shapes)   # 计算输出数量
        self.load_weight = dict()   # 权重缓存字典，避免重复创建
        self.F32Type = F32Type.get()    #  获取F32类型实例，频繁使用
        self.insert_point_save_flag = False # 插入点保存标志，用于嵌套代码生成
        self.mlir_type = {  #类型系统映射表 - 核心类型转换
            "INT8": IntegerType.get_signed(8),
            "UINT8": IntegerType.get_unsigned(8),
            "SINT8": IntegerType.get_signed(8),
            "INT16": IntegerType.get_signed(16),
            "UINT16": IntegerType.get_unsigned(16),
            "INT32": IntegerType.get_signed(32),
            "UINT32": IntegerType.get_unsigned(32),
            "INT64": IntegerType.get_signless(64),  #special
            "UINT64": IntegerType.get_unsigned(64),
            "BOOL": IntegerType.get_signless(1),
            "F64": F64Type.get(),
            "F32": F32Type.get(),
            "F16": F16Type.get(),
            "BF16": BF16Type.get(),
            "DICT": DictAttr.get(),
        }
        if do_declare:  #如果do_declare为True，立即声明MLIR函数结构，否则延迟到后续调用。
            self.declare_func(input_types, output_types)

```

​			**2. 函数声明器** 

​				核心功能： 根据输入输出形状和类型创建MLIR函数 ， 生成完整的MLIR模块模板 ， 设置插入点和函数参数 

```python
    def declare_func(self, input_types: list = [], output_types: list = []):
        if len(input_types) == 0:   #检查列表是否为空。     如果用户不指定类型，所有输入默认为F32
            input_types = self.num_input * ['F32']  #self.num_input：输入张量的数量（整数），* ['F32']：列表重复操作，3 * ['F32'] → ['F32', 'F32', 'F32']
        if len(output_types) == 0:
            output_types = self.num_output * ['F32']

        self.input_types = list()   # 用户指定的输入类型
        self.input_op_types = list()    # 内部操作的输入类型（固定F32）
        self.output_types = list()  # 输出类型
        for _shape, _type in zip(self.input_shapes, input_types):   #zip(list1, list2)：Python内置函数，将两个列表打包      _shape, _type：解包赋值，每次循环获取一对形状和类型
            self.input_op_types.append(RankedTensorType.get(_shape, self.F32Type))      #内部操作统一使用F32，简化处理
            if isinstance(_type, str):
                self.input_types.append(RankedTensorType.get(_shape, self.mlir_type[_type]))    #self.mlir_type[_type]：从类型字典获取MLIR类型对象      示例：'F32' → F32Type.get()
            else:   #_type已经是MLIR类型对象
                self.input_types.append(RankedTensorType.get(_shape, _type))    #直接使用：无需转换
        for _shape, _type in zip(self.output_shapes, output_types):
            t = _type
            if isinstance(_type, str):
                t = self.mlir_type[_type]
            self.output_types.append(self.get_tensor_type(_shape, t))   #调用张量类型生成器
        args_txt = str()    #初始化空字符串
        for _idx, _type in enumerate(self.input_types): #遍历输入类型
            args_txt += "%args{}: {} loc(unknown)".format(_idx, _type.__str__())        #示例   输入：2个张量  结果： args_txt = "%args0: tensor<1x3x224x224xf32> loc(unknown), %args1: tensor<1x1000xf32> loc(unknown)"
            if (_idx + 1) < self.num_input: #添加分隔符
                args_txt += ", "

        output_txt = str()  #输出类型字符串构建，逻辑类似输入，但更简洁。不包含变量名：只有类型信息
        for _idx, _type in enumerate(self.output_types):    #生成示例：tensor<1x1000xf32>, tensor<1x512xf32>
            output_txt += _type.__str__()
            if (_idx + 1) < self.num_output:
                output_txt += ", "
        result_types = output_txt
        result_var_name = "%1"
        if self.num_output > 1:
            output_txt = "({})".format(output_txt)
            result_types = output_txt[1:-1]
            result_var_name = ",".join([f"%1#{var_id}" for var_id in range(self.num_output)])
            #MLIR模板字符串构建
        main_func = """ 
            module @\"{name}\" attributes {{module.weight_file= \"{weight_file}\", module.platform=\"{platform}\", module.state=\"{state}\", module.chip=\"{chip}\", module.top_run_mode=\"{run_mode}\"}} {{
                func.func @main({args}) -> {output} {{
                    %0 = \"top.None\"() : () -> none loc(unknown)
                    %1:{last_output_num} = \"Placeholder.Op\"() : () -> {output}
                    return {result_var} : {result_types}
                }} loc(unknown)
            }} loc(unknown)
        """.format(name=self.model_name,    #格式化参数
                   weight_file="" if self.no_save else self.weight_file,
                   platform=self.platform,
                   state=self.state,
                   chip=self.chip,
                   run_mode=self.run_mode,
                   args=args_txt,
                   output=output_txt,
                   last_output_num=self.num_output,
                   result_var=result_var_name,
                   result_types=result_types)
        """生成示例
        module @"my_model" attributes {module.weight_file= "my_model_top_f32_all_origin_weight.npz", module.platform="ONNX", module.state="TOP_F32", module.chip="ALL", module.top_run_mode="STATIC"} {
            func.func @main(%args0: tensor<1x3x224x224xf32> loc(unknown)) -> tensor<1x1000xf32> {
                %0 = "top.None"() : () -> none loc(unknown)
                %1:1 = "Placeholder.Op"() : () -> tensor<1x1000xf32>
                return %1 : tensor<1x1000xf32>
            } loc(unknown)
        } loc(unknown)
        """
        self.mlir_module = Module.parse(main_func, self.ctx)    #解析MLIR模块
        self.func = self.mlir_module.body.operations[0] #提取函数对象
        self.entry_block = self.func.regions[0].blocks[0]   #获取入口基本块
        self.insert_point = InsertionPoint(self.entry_block)    #设置插入点
        self.none_op = self.entry_block.operations[0].operation.results[0]  #获取None操作
        # remove Placeholder.Op and return Op.
        # These operations are placeholders and are only used to generate a legal MLIR code.
        self.entry_block.operations[2].operation.erase()    #删除占位符操作
        self.entry_block.operations[1].operation.erase()

        self.func_args = list() #提取函数参数
        for i in self.entry_block.arguments:
            self.func_args.append(i)
```

​			**3. 张量类型生成器** 

​				核心功能： 根据形状和元素类型创建MLIR张量类型 ， 支持动态形状、多输出、空形状等情况 

```python
  # shape: [] => [* x f32]; None => NoneType; [None, None] => [NoneType, NoneType]
    # type: None => f32; or type
    #get_tensor_type 函数 - 张量类型生成器
    def get_tensor_type(self, output_shapes, type=None):
        if type is None:    #如果用户没有指定元素类型，默认使用F32类型
            type = self.F32Type
        if output_shapes == []: #处理空形状列表（动态形状张量）
            return UnrankedTensorType.get(type) #UnrankedTensorType - 表示形状未知的张量    MLIR表示：tensor<*xf32> (星号表示任意维度)  使用场景：动态形状推理，编译时无法确定具体形状
        if output_shapes is None:   #处理None值（表示无输出）
            return NoneType.get()   #返回类型：NoneType - 表示该操作无输出
        if isinstance(output_shapes, tuple):    #如果output_shapes是元组
            output_shapes = list(output_shapes) #将其转为列表
        assert (isinstance(output_shapes, list))    #断言output_shapes是列表
        assert (len(output_shapes) > 0) #断言output_shapes非空
        if not isinstance(output_shapes[0], list) and output_shapes[0] is not None: #如果output_shapes第一个元素非空且不是列表
            return RankedTensorType.get(tuple(output_shapes), type) #创建单个有秩张量类型，例子如下：
            """
            output_shapes = [1, 3, 224, 224]  # Python列表
            tuple(output_shapes)  # → (1, 3, 224, 224) Python元组
            type = F32Type.get()  # → f32类型
            MLIR内部创建：tensor<1x3x224x224xf32>
            """
        # multi output 多输出张量处理
        # 触发条件：output_shapes = [[1,1000], [1,512], None] (多输出情况)
        # 处理逻辑：为每个输出形状创建对应类型
        # 返回结果：类型对象列表
        out_types = []  #创建空列表，用于存储每个输出的类型对象
        for s in output_shapes: #遍历
            if s == []: #判断当前输出形状是否为空列表
                out_types.append(UnrankedTensorType.get(type))  #UnrankedTensorType.get(type) 创建UnrankedTensor，元素类型为type    out_types.append(...)：将类型添加到结果列表
            elif s is None:
                out_types.append(NoneType.get())    #如果s是None，添加None到out_types
            else:
                out_types.append(RankedTensorType.get(tuple(s), type))  #前面条件都不满足，将形状列表转换为元组，RankedTensorType：MLIR有秩张量类型类   .get(shape, element_type)：静态方法创建有秩张量
        return out_types
```

​			**4. 数组属性构造器** 

​				核心功能： 将Python列表转换为MLIR数组属性 

```python
  def ArrayAttr(self, data: list, data_type: str = 'INT64'):  # data_type默认为INT64
        assert (data_type in self.mlir_type)    # 确保传入的data_type在支持的类型映射表也就是self.mlir_type中
        if data_type.find("INT") >= 0:  #当data_type字符串中包含"INT"时：支持的类型：INT8, UINT8, SINT8, INT16, UINT16, INT32, UINT32, INT64, UINT64
            #遍历data中的每个元素x，对每个x调用IntegerAttr.get(type, value)创建整数属性。self.mlir_type[data_type]获取对应的MLIR类型对象，IntegerAttr.get(类型, 值)创建单个整数属性，ArrayAttr.get([属性列表])将所有属性打包成数组属性
            """
            示例：
            # 输入：data=[1, 2, 3], data_type="INT32"
                过程：
                1. self.mlir_type["INT32"] → IntegerType.get_signed(32)
                2. [IntegerAttr.get(IntegerType.get_signed(32), 1),
                   IntegerAttr.get(IntegerType.get_signed(32), 2), 
                   IntegerAttr.get(IntegerType.get_signed(32), 3)]
                3. ArrayAttr.get([IntegerAttr1, IntegerAttr2, IntegerAttr3])
            """
            return ArrayAttr.get([IntegerAttr.get(self.mlir_type[data_type], x) for x in data])
        if data_type == 'F32':  #严格匹配F32
            return ArrayAttr.get([FloatAttr.get_f32(x) for x in data])
        if data_type == 'F64':  #严格匹配F64
            return ArrayAttr.get([FloatAttr.get_f64(x) for x in data])
        if data_type == 'DICT': #严格匹配字典
            # the data in list has been transformed to DictAttr 输入列表中的数据已经被转换为DictAttr对象
            return ArrayAttr.get(data)  #直接用ArrayAttr.get(data)封装
        raise RuntimeError("unsupport data type:{}".format(data_type))  #当所有已知类型都不匹配时 作用：提供清晰的错误信息，帮助调试

```

​			5. 输入操作创建器 

​				核心功能：  创建模型输入操作，支持预处理配置 

```python
    def create_input_op(self, loc, index, kargs: dict = {}):
        assert (index < len(self.func_args))    #确保索引不超出函数参数范围。
        init_args = {}  #创建空字典
        channel_axis = 1    #设置通道轴默认值
        shape = self.input_shapes[index]    #获取指定索引的输入形状
        if 'channel_format' in kargs:   #检查是否指定了通道格式
            if kargs['channel_format'] == 'nhwc':   # 如果是NHWC格式，通道轴设为-1（最后一维）
                channel_axis = -1
            if (len(shape) == 4 and shape[channel_axis] <= 4) or len(shape) == 3:   #4D且通道数≤4，或3D张量时
                init_args = {
                    k: StringAttr.get(v) if isinstance(v, str) else v
                    for k, v in kargs.items()
                }
        if 'preprocess_list' in kargs and kargs['preprocess_list'] is not None: #检查预处理列表是否存在且非空
            if index + 1 in kargs['preprocess_list']:   #当前输入索引+1是否在预处理列表中
                init_args["do_preprocess"] = 1
            if 'preprocess_list' in init_args:
                del init_args["preprocess_list"]    #删除临时的预处理列表键
        if 'shape_tensor' in kargs: #如果提供了形状张量参数，添加到初始化参数中
            init_args["shape_tensor"] = kargs['shape_tensor']
        init_args["loc"] = loc  #位置信息
        init_args["ip"] = self.insert_point #插入点
        init_args["input"] = self.func_args[index]  #函数参数
        init_args["output"] = self.input_types[index] if self.platform in [
            Platform.TFLITE, Platform.TPULANG
        ] else self.input_op_types[index]   #根据平台选择不同的输出类型
        input_op = top.InputOp(**init_args) #使用**操作符解包字典作为关键字参数
        return input_op.output  #返回创建的输入操作的输出

```

​			**6. 权重操作创建器** 

​				核心功能： 创建权重张量操作，支持缓存复用 

```python
    def create_weight_op(self, name, output_shape, data_type="F32"):
        if name in self.load_weight:
            _op, _shape, _type = self.load_weight[name]
            if _shape != output_shape or _type != data_type:
                raise RuntimeError("{} weight conflict".format(name))
            return _op
        attrs = dict()
        if self.no_save:
            attrs["inline_bytes"] = StringAttr.get(tensor.buffer.tobytes())
        tensor_type = RankedTensorType.get(output_shape, self.mlir_type[data_type])
        op = Operation.create("top.Weight",
                              results=[tensor_type],
                              loc=Location.fused([Location.name(name)]),
                              attributes=attrs)
        self.insert_point.insert(op)
        result = op.results[0]
        self.load_weight[name] = (result, output_shape, data_type)
        return result

```


​		onnx的一些基础知识： [ONNX 基础知识 - 知乎](https://zhuanlan.zhihu.com/p/686126692) 

