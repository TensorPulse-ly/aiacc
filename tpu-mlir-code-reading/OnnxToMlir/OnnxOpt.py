from collections import Counter, defaultdict, OrderedDict
import onnx
import onnx.numpy_helper
import copy
import numpy as np
import onnxruntime as rt
from transform.OnnxOpOptionalAttrs import OnnxOpOptionalAttrGetter
from onnxruntime_extensions import onnx_op, PyOp, PyOrtFunction
import torch

onnx_attr_translator = {
    "axis": lambda x: int(x),
    "axes": lambda x: [int(a) for a in x],
    "keepdims": lambda x: bool(x),
}

optional_attr_getter = OnnxOpOptionalAttrGetter()


def translate_onnx(key, val):
    return onnx_attr_translator.get(key, lambda x: x)(val)


def convert_onnx_attribute_proto(attr_proto):
    if attr_proto.HasField('f'):
        return attr_proto.f
    elif attr_proto.HasField('i'):
        return attr_proto.i
    elif attr_proto.HasField('s'):
        return attr_proto.s
    elif attr_proto.HasField('t'):
        return attr_proto.t  # this is a proto!
    elif attr_proto.floats:
        return list(attr_proto.floats)
    elif attr_proto.ints:
        return list(attr_proto.ints)
    elif attr_proto.strings:
        str_list = list(attr_proto.strings)
        return str_list
    elif attr_proto.name:
        name_list = list(attr_proto.name)
        return name_list
    else:
        raise ValueError("Unsupported ONNX attribute: {}".format(attr_proto))


def dump_model(model, name="opt.onnx"):
    data = model.SerializeToString()
    with open(name, "wb") as file:
        file.write(data)


def get_node_attrs(node) -> dict:
    attrs = dict((attr.name, translate_onnx(attr.name, convert_onnx_attribute_proto(attr)))
                 for attr in node.attribute)
    attrs_full = optional_attr_getter.get(node.op_type)
    for k, v in attrs_full.items():
        if k not in attrs:
            attrs[k] = v
    return attrs


class ConstantFolding(object):

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

    def get_inputs(self):   #过滤掉initializer，只返回真正的外部输入        ONNX中input包含了外部输入和权重，需要区分
        initializer_names = [x.name for x in self.model.graph.initializer]
        return [ipt for ipt in self.model.graph.input if ipt.name not in initializer_names] #

    def get_input_names(self):      #获取输入名称列表
        input_names = [ipt.name for ipt in self.get_inputs()]
        return input_names

    def generate_specific_rand_input(self, input_shapes):   #随机输入生成函数
        inputs = {}     #最终返回的字典，键为输入名称，值为对应的numpy数组
        for key, shape in input_shapes.items():     #遍历键值，.items()字典的键值迭代器
            if not np.all(np.array(shape) > 0):     #np.array将Python列表转化为numpy数组       np.all检查是否所有元素都为True，如果存在任何维度≤0，条件为True
                raise RuntimeError("The shape of input '{}' has dynamic size '{}', "    #抛出异常
                                   "please determine the input size when export "
                                   "onnx".format(key, shape))
            elem_type = self.get_elem_type(key)     #调用实例方法获取ONNX数据类型
            elem_type = self.get_np_type_from_elem_type(elem_type)  #将ONNX类型码转换为NumPy数据类型
            if elem_type == np.bool_:  # for mask
                inputs.update({key: np.random.randint(0, 2, shape, dtype=elem_type)})   #布尔数据生成
            elif elem_type == np.int64:
                inputs.update({key: np.random.randint(1, 2, size=shape, dtype=elem_type)})      #生成[1, 2)区间的整数，即只生成1
            elif len(shape) == 0:  # for idx
                inputs.update({key: np.array(0, dtype=elem_type)})  #选择0作为安全的默认值
            else:
                inputs.update({key: np.random.rand(*shape).astype(elem_type)})  #浮点处理，解包shape
        return inputs

    def get_value_info_all(self, name): #值信息获取
        for v in self.model.graph.value_info:   #在value_info列表中搜索
            if v.name == name:
                return v
        for v in self.model.graph.input:    #在输入列表中搜索
            if v.name == name:
                return v
        for v in self.model.graph.output:   #在输出列表中搜索
            if v.name == name:
                return v
        return None

    @staticmethod
    def insert_elem(nodes, idx, element):       #元素插入
        nodes.extend([nodes[-1]])       #在列表末尾添加一个位置
        for i in reversed(range(idx + 1, len(nodes) - 1)):      #reversed(): 反转迭代器，从后往前遍历
            nodes[i].CopyFrom(nodes[i - 1])     #将前一个元素复制到当前位置
        nodes[idx].CopyFrom(element)        #将目标元素复制到指定位置

    @staticmethod
    def get_shape_from_value_info_proto(vinfo):
        return [dim.dim_value for dim in vinfo.type.tensor_type.shape.dim]

    @staticmethod
    def get_np_type_from_elem_type(elem_type):      #类型转换，将ONNX类型转换为NumPy类型
        types = (None, np.float32, np.uint8, np.int8, np.uint16, np.int16, np.int32, np.int64, str,
                 np.bool_, np.float16, np.double, np.uint32, np.uint64, np.complex64, np.complex128,
                 np.float16)
        assert len(types) == 17 #确保映射表完整性
        _type = types[elem_type]        #elem_type为枚举值，它作为索引，查找对应再types里的numpy类型
        assert _type is not None        # 确保映射结果不为None
        return _type        #返回对应的NumPy数据类型对象

    def get_shape(self, name):      # 形状获取方法
        vinfo = self.get_value_info_all(name)
        if vinfo is None:
            raise RuntimeError("Can't get shape of '{}'".format(name))
        return self.get_shape_from_value_info_proto(vinfo)

    def get_elem_type(self, name):  #获取张量的元素类型
        vinfo = self.get_value_info_all(name)   #使用相同的值信息获取方法
        if vinfo is None:   #如果没找到信息，抛出错误
            raise RuntimeError("Can't get dtype of '{}'".format(name))
        return vinfo.type.tensor_type.elem_type #获取ONNX元素类型枚举值

    def is_dynamic(self, node):     #用于判断一个ONNX节点是否具有"动态性"，即在编译时无法确定其输出大小或内容，因此不能进行常量折叠。
        # for i in node.input:
        #     if i in self.dynamic_shape_input_names:
        #         return True
        if node.op_type in ["NonMaxSuppression", "NonZero", "Unique"] \
                and node.input[0] not in self.const_tensors:        #如果node.op_type在["NonMaxSuppression", "NonZero", "Unique"]中，且不是常量，返回true
            return True     #       大小不确定的算子        NonMaxSuppression: 非极大值抑制，输出的边界框数量取决于输入数据的内容      NonZero: 找出非零元素的位置，输出数量取决于有多少非零元素       Unique: 去重操作，输出大小取决于输入中有多少不重复的元素
        if node.op_type in ["Reshape", "Expand", "Upsample", "ConstantOfShape"] \
                and len(node.input) > 1 and node.input[1] not in self.const_tensors:    #形状参数动态的算子 Reshape: 改变张量形状，新形状由第二个输入指定       Expand: 扩展张量到指定形状      Upsample: 上采样操作，缩放因子由参数指定        ConstantOfShape: 创建指定形状的常量张量
            return True
        if node.op_type in ["Resize"] \
                and ((len(node.input) > 2 and node.input[2] not in self.const_tensors) \
                    or (len(node.input) > 3 and node.input[3] not in self.const_tensors)):      #Resize有多种参数化方式，scales和sizes都可以控制输出大小，任一个动态都会导致输出大小不确定。
            return True
        if node.op_type in ["Slice"] \
                and ((len(node.input) > 1 and node.input[1] not in self.const_tensors) \
                    or (len(node.input) > 2 and node.input[2] not in self.const_tensors) \
                    or (len(node.input) > 3 and node.input[3] not in self.const_tensors) \
                    or (len(node.input) > 4 and node.input[4] not in self.const_tensors)):      #Slice的输出大小和内容完全由这些参数决定，任何参数的动态变化都会导致不可预测的输出。
            return True
        return False

    def has_subgraph_in_node(self, node):   #检查节点是否包含子图
        for attr in node.attribute: #遍历节点的所有属性
            if attr.type in [onnx.AttributeProto.GRAPH, onnx.AttributeProto.GRAPHS]:        #检查属性类型是否为图类型
                return True
        return False

    def is_quantizeLinear(self, node):      #量化检测
        return node.op_type in ["DequantizeLinear", "QuantizeLinear"]   #识别量化相关算子

    def is_non_determinstic_node(self, node):   #非确定性检测
        return node.op_type in ["RandomNormal", "RandomNormalLike", "RandomUniformLike"]        #识别随机算子

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

    #输出获取
    def forward_for_node_outputs(self, const_nodes):
        model = copy.deepcopy(self.model)   #深拷贝模型
        test_input = self.test_input    #直接引用测试输入
        for node in const_nodes:    #为每个常量节点处理其输出
            for output in node.output:  #遍历所有输出
                model.graph.output.extend([onnx.ValueInfoProto(name=output)])   #将中间节点的输出添加到图的输出列表
        return self.forward(model, test_input)      #使用修改后的模型进行推理

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

    def infer_shapes(self): #形状推理
        try:
            self.model = onnx.shape_inference.infer_shapes(self.model)  #调用ONNX形状推理: 使用ONNX库的形状推理功能
        except:
            pass    # 形状推理失败不影响程序继续
        # self.model = onnx.shape_inference.infer_shapes(self.model, strict_mode =True, data_prop=True)

    def folding(self, infer_shapes=True):   #单次折叠 
        const_nodes = self.get_constant_nodes() #调用核心算法获取可折叠节点
        res = self.forward_for_node_outputs(const_nodes)    #通过推理获取节点输出值
        const_node = [node for node in const_nodes if node.output[0] in res]    #只保留推理成功的节点
        do_eliminate = self.eliminate_const_nodes(const_node, res)  #调用节点消除方法
        if infer_shapes:    #根据参数决定是否执行形状推理
            self.infer_shapes() #更新模型的形状信息
        return do_eliminate #返回是否执行了节点消除

    def run(self):  #主运行方法

        def fixed_point(fun):   #实现固定点迭代算法
            flag = fun()    #第一次调用函数
            while True: #直到条件满足才退出
                if flag:    #如果函数返回True
                    flag = fun()    #再次调用函数
                    continue    #跳到循环开始
                break   #如果函数返回False退出循环

        fixed_point(self.folding)   #传递folding方法作为参数
        self.remove_unused_nodes()  #移除优化后产生的无用节点
        # dump_model(self.model, "constant_opt.onnx")
        try:
            onnx.checker.check_model(self.model)    #检查优化后模型的正确性
        except:
            print("WARNING: onnx model check failed")   #输出警告但不中断
        return self.model   #返回经过常量折叠优化的模型


class OuterNode(object):        #模式外部节点
    #核心作用: 表示模式匹配中的"外部节点"，即不在匹配模式内部，但与模式有连接关系的节点或张量

    def __init__(self, is_tensor=False, tensor_value=None, attr_name=None): #is_tensor=False: 默认参数，标识是否为张量节点
        '''out of pattern chain. eg. pattern[0]'s input / tensor''' #说明这是模式链之外的节点，如模式第一个节点的输入或张量
        self.output = []  # when do input match we get name direct from onnx_node   在输入匹配时直接从ONNX节点获取名称
        self.is_tensor = is_tensor  # also check if tensor with same value      标记是否为张量类型,还用于检查张量是否有相同的值
        # will be checked when pattern match, will be set when insert new node in replace
        self.tensor_value = tensor_value
        self.attr_name = attr_name
        self.attr_value = None
        if is_tensor == False:  #如果不是张量类型
            if tensor_value is not None:    #但提供了张量值
                self.tensor_value = np.array(tensor_value)  #将输入值转换为NumPy数组
                if self.tensor_value.shape == ():   # 检查是否为标量（形状为空元组）
                    self.tensor_value = np.expand_dims(self.tensor_value, 0)    #将标量扩展为1维数组
                self.is_tensor = True   # 既然有了张量值，就标记为张量类型
        if attr_name:       #强制标记为张量: 如果有属性名，说明这个张量会成为新节点的属性
            # for some case tensor is a part of new onnx_node's attr
            self.is_tensor = True

    def get_attr(self): #生成ONNX节点属性的字典格式
        attr_value = self.attr_value        #创建属性值的局部引用
        if len(self.attr_value.shape) == 0:     #检查属性值是否为标量
            attr_value = float(attr_value)      #将NumPy标量转换为Python float
        return {self.attr_name: translate_onnx(self.attr_name, attr_value)}     #返回属性名到属性值的映射       格式: {"属性名": 转换后的值}


class AttrCheck(object):        #属性检查器     对节点属性进行验证检查,确保模式匹配时节点具有正确的属性值

    def __init__(self, attrs: list = [], func=(lambda x: x)):
        self.attrs = attrs
        self.func = func


class AttrFunctor(object):      #属性函数处理器     处理属性值的函数式映射，从输入节点的属性计算新节点的属性

    def __init__(self, inputs: list = [], attrs: list = [], func=(lambda x: x)):
        assert (len(inputs) == len(attrs))
        self.inputs = inputs
        self.attrs = attrs
        self.func = func


class PatternNode(object):      #核心作用: 表示模式匹配中的一个操作节点，定义了节点的类型、输入、属性等约束

    def __init__(self,
                 op_type,
                 input=[],
                 cur_attr_name=[],
                 new_attr_name=[],
                 new_attr={},
                 attrmap={},
                 constraint='',
                 attrcheck=None):
        self.op_type = op_type      #操作类型: 存储ONNX算子类型字符串
        self.input = input          #输入列表: 存储输入节点引用
        self.output = []            #输出列表: 初始化为空，运行时填充
        self.attr = {}              #属性字典: 存储节点的属性
        # get attr form current node and renamed with new_attr_name     支持属性重命名
        self.cur_attr_name = cur_attr_name  #从匹配的ONNX节点获取的属性名
        self.new_attr_name = new_attr_name  #在替换节点中使用的属性名
        # add new attr in curent node   在目前的节点中添加新的属性
        self.new_attr = new_attr        #直接添加到节点的新属性
        self.attrmap = attrmap          #属性映射: AttrFunctor对象的字典，用于复杂属性计算
        # check current node's cal manner
        self.constraint = constraint        #
        # check attr, should be AttrFunctor or None
        self.attrcheck = attrcheck

        #类型验证，确保各属性的类型正确
        assert (isinstance(self.input, list))
        assert (isinstance(self.attr, dict))
        assert (isinstance(self.cur_attr_name, list))
        assert (isinstance(self.new_attr_name, list))
        assert (isinstance(self.constraint, str))

        if cur_attr_name and len(new_attr_name) == 0:       #如果提供了当前属性名但没有新属性名
            # if cur_attr_name and new_attr_name are all the same leave new_attr_name blank is ok
            # otherwise you should explicit assign all the key in both cur_attr_name and new_attr_name
            self.new_attr_name = cur_attr_name      #将当前属性名复制为新属性名
        assert (len(self.cur_attr_name) == len(self.new_attr_name))     #确保属性名映射的一一对应关系

    def update(self, output, attr_value):       #在模式匹配成功后更新节点状态
        # attr: from both inp / node / new, output
        self.output.clear()     #清除之前的输出
        self.attr.clear()       #清除之前的属性
        self.output.extend(output)      #添加新的输出名称列表
        self.attr.update(zip(self.new_attr_name, attr_value))       #使用zip将属性名和属性值配对

    def get_attr(self):     #计算并返回节点的完整属性字典
        for new_attr, attr_func in self.attrmap.items():        #处理所有AttrFunctor定义的属性
            args = [    #参数收集: 从输入节点收集属性值
                t.get_attr()[old_attr] for t, old_attr in zip(attr_func.inputs, attr_func.attrs)
            ]
            self.attr.update({new_attr: attr_func.func(*args)})     #调用AttrFunctor的函数处理收集的参数
        return self.attr        #返回包含所有属性的字典


class ReformInfo(object):       #重构信息容器       核心作用: 封装一个完整的图重构规则，包含源模式和目标模式

    def __init__(self, name: str, src_nodes, dst_nodes):    #src_nodes: 源模式节点列表（要被替换的节点）        dst_nodes: 目标模式节点列表（替换后的节点）
        self.name = name
        self.src_nodes = src_nodes
        self.dst_nodes = dst_nodes


class ReForm(object):       #ReForm类是一个基于模式匹配的ONNX图重构优化器，主要功能是识别特定的子图模式并用更高效的实现替换它们。
    # current just support form/deform single output op     说明当前只支持单输出算子的重构
    def __init__(self, model, rigorous):        #构造函数，初始化ReForm实例
        self.rigorous = rigorous    #存储严格模式标志
        self.reform_info_list = []  #创建空列表存储重构规则
        self.nodes = model.graph.node   #直接引用模型图中的节点列表
        self.weight = model.graph.initializer       #直接引用模型的权重初始化器
        self.gout = model.graph.output      #引用图的输出信息
        self.ginfo = model.graph.value_info #引用图的值信息
        # store node shape
        self.shape_info = [info for info in model.graph.value_info]     #从value_info创建新列表，创建可修改的副本，避免直接修改原model
        self.shape_info.extend(model.graph.output)      #将图输出信息也加入形状信息
        self.shape_info = {     #将形状信息转换为 {张量名: 形状列表} 的字典
            info.name: [i.dim_value for i in info.type.tensor_type.shape.dim if i.dim_value > 0]
            for info in self.shape_info
        }
        self.weight_tensor = [x.name for x in self.weight]      #提取所有权重张量的名称
        self.node_tensor = [node.output[0] for node in self.nodes if node.op_type == "Constant"]    #遍历所有 NodeProto，选取 op_type == "Constant" 的节点，取它们的第一个输出名 node.output[0]。
        # stores output node name mapping from src to dst of replace subgraphs
        self.node_name_mapping = {}

    def get_tensor_value(self, name):   #该方法先在 Constant 节点中查找，再在 initializer 中查找，返回对应 numpy 值；若两处都未找到则函数隐式返回 None
        for n in self.nodes:
            if name == n.output[0] and n.op_type == 'Constant':     #如果第一个输出名字等于传入的name参数，且当前节点为Constant节点
                return onnx.numpy_helper.to_array(n.attribute[0].t) #一旦找到对应 Constant 节点，立即返回该常量的 numpy 值。
        for w in self.weight:   #遍历所有权重
            if name == w.name:
                return onnx.numpy_helper.to_array(w).astype(np.float32) #将其转为numpy然后再转为f32

    def find_tensor(self, name):
        if name in self.node_tensor or name in self.weight_tensor:  #判断名字 name 是否是已知的常量张量名（要么来自 Constant 节点，要么来自 initializer）。
            return True
        return False

    def get_node(self, name):   #在 self.nodes 中找到 第一个 输出列表中包含 name 的节点，返回 (index, node)
        for idx, n in enumerate(self.nodes):
            if name in n.output:
                return idx, n

    def get_input_shape(self, name):    #此函数假设 name 要么是某个中间 / 输出的名字并在 self.shape_info 中有条目，要么是 initializer 的名字。若两者都不匹配将隐式返回 None
        for n in self.nodes:        #遍历所有节点
            if name == n.output[0]:     #如果当前节点的第一个输出名称等于name，返回self.shape_info[name]
                return self.shape_info[name]
        for w in self.weight:       #若没找到对应节点，遍历weight，如果 name == w.name，返回 list(w.dims)
            if name == w.name:
                return list(w.dims)

    def constraint(self, node, mode):       #这个函数用于 pattern 的 constraint 校验（PatternNode.constraint），目的是保证该模式在当前节点上语义正确
        if mode == 'broadcast' and len(node.input) == 2:    #该函数目前仅支持 mode == 'broadcast'，且期望待检查节点有两个输入（二元广播情形）。
            inp_0, inp_1 = node.input
            inp0Shape = self.get_input_shape(inp_0) #获取输入的形状
            inp1Shape = self.get_input_shape(inp_1)
            if len(inp0Shape) == 1 or len(inp1Shape) == 1:  #如果输入的形状至少有一个是一维
                # normal case
                if inp0Shape[-1] == inp1Shape[-1] \
                    or inp0Shape[-1] == 1 or inp1Shape[-1] == 1:    #判断最后一维是否兼容（相等或其中一个为 1），若成立则认为满足 broadcast 约束。
                    return True
            elif ((inp0Shape[-2] == 1 or inp1Shape[-2] == 1) \
                  and inp0Shape[:-2] == inp1Shape[:-2]):
                # for group fc      #处理类似 group fc 的情形：检查倒数第二维是否为 1，并且前面的 prefix 维度完全相等
                return True
        else:   #如果 mode 不是 'broadcast' 或输入数不为 2，抛出 ValueError（当前仅实现 broadcast 检查）。
            raise ValueError("constrain mode: {} not support now.".format(mode))
        return False        #若上述条件都不满足，返回 False

    def check_attrs(self, node, attrcheck: AttrCheck):
        attrs = get_node_attrs(node)    #调用函数 get_node_attrs，把 node.attribute 转换为 Python 字典 。
        for key in attrcheck.attrs: #attrcheck 是 AttrCheck 对象，包含 .attrs（字符串列表） 和 .func（callable）。遍历要检查的属性名。
            if key not in attrs:    #若任何期望的属性在节点属性里不存在，检查失败。
                return False
        args = tuple(attrs[key] for key in attrcheck.attrs)     #按顺序从 attrs 中提取这些属性值，构建元组 args。
        return attrcheck.func(*args)        #把属性值传给 attrcheck.func，其返回布尔值作为检查结果。

    def attr_to_tensor(self, node, pindices, op_type):  #处理低 opset（旧版本 ONNX）里，某些原本作为“输入 tensor”的值被放在节点 attribute 里的情况 —— 把这些 attribute 转成 numpy 张量值，返回值列表。
        '''
           high opset node's input is low opset node's attr
           here map pattern node input's idx to attr key
        '''
        tensor_value = []       #初始化空列表用于收集由 attribute 转成的 tensor 值。
        attrs = get_node_attrs(node)        #取得属性字典
        for i in pindices:      #pindices 是一个索引列表（pattern 中那些“应该是 tensor 的输入在实际 node 中可能是 attribute”对应的索引），遍历这些索引。
            key = "None"
            if op_type == "Clip":       #在 Clip 的低 opset 里，min/max 可能是 attribute（index 1 对应 min，2 对应 max），所以把索引映射为属性名。
                if i == 1:
                    key = "min"
                elif i == 2:
                    key = "max"
            # add other op here
            try:        
                tensor_value.append(np.array(attrs[key]))       #尝试从 attrs 中读取对应属性值并转为 numpy 数组追加。
            except KeyError:        #若 key 不在 attrs 中会抛 KeyError，随后 except KeyError: pass 忽略
                pass
        return tensor_value

    def process_low_opset(self, node, pninp, nofdiff):  #把 pattern 对应的“额外 input”从 node 的 attributes 中提取为 tensor，以便后续 match_input 使用；在 opset 不匹配时以 rigorous 决定是抛错还是跳过。
        tensor_value = []       #pninp是pattern inputs，是一个列表，里面是pattern定义的输入节点     nofdiff是number of inputs difference，他是实际节点的输入数 ninp 和 pattern 输入数 len(pninp) 的差
        if nofdiff == 0:        #当 pattern 输入数与节点输入数相等（nofdiff == 0）时不需要处理，直接返回空列表。
            return tensor_value
        flag = True  # this mean maybe tensor in pinp is onnx node's attr       假设多出来的输入（差值部分）其实是常量参数（attr），而不是普通张量。
        start_idx = len(pninp) - nofdiff        #计算 pattern 里哪些位置的输入可能被 ONNX 导出成 attr → tensor。
        for pnode in pninp[start_idx:]:     #遍历 pattern 定义的多余输入部分。
            if not pnode.is_tensor:     #如果发现这些输入不是“tensor常量”，就认为这个节点不匹配。
                flag = False
                break
        if flag:        #如果这些输入是 tensor，就尝试把它们从 attr 转换为 tensor 值。
            tensor_value = self.attr_to_tensor(node, range(start_idx, len(pninp)), node.op_type)
        if not flag or not len(tensor_value) == nofdiff:    #如果 flag 失败，或者转换出的 tensor 个数和差值不匹配：
            if self.rigorous:   #严格模式下抛异常。
                raise RuntimeError("Unsupport opset for {}".format(node.op_type))
            else:       #否则打印 warning，跳过这个算子。
                print("Warning unsupport opset for {} skipped.".format(node.op_type))
        return tensor_value     #返回最终解析出来的 tensor 常量值

        '''
        举例：比如ONNX的Slice算子
            高opset(>=10)       %out = Slice(%data, %starts, %ends, %axes, %steps)
                                输入5个，data，starts，ends，axes，steps，后两个是可选的
            低opset(<10)        %out = Slice(%data)
                                输入一个，属性有starts，ends，axes，steps
            假设 TPU-MLIR 里 pattern 定义 Slice 节点时，认为它有 1 个输入：pninp = ["data"]
                低opset：
                        onnx节点：输入1个，data，参数在attr里
                        实际输入数：ninp = 1
                        pattern输入数：len(pninp) = 1
                        差值：nofdiff = ninp - len(pninp) = 0
                        process_low_opset 直接返回，不做处理。
                高opset：
                        onnx节点：输入3个（data, starts, ends），axes/steps 可能省略。
                        实际输入数：ninp = 3
                        pattern 输入数：len(pninp) = 1
                        差值：nofdiff = 2
                        process_low_opset 逻辑：
                            检查 pninp 的最后 nofdiff=2 个是不是 tensor（即 starts、ends）。
                            是的话，把它们转为 tensor value（attr_to_tensor）。
                            这样就把 高 opset 输入的 tensor 对应到 低 opset attr。

        '''






    '''
    这是 match_node 的输入匹配核心：
        把真实节点的 ninp（实际输入）和 pattern 的 pninp（pattern 定义的输入）逐一比对，
        并处理多种情形（OuterNode、tensor 值对比、attr 注入等）。
    '''
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

    def match_node(self, node, pnode):
        """
        匹配单个节点 node 是否符合 pattern 节点 pnode 的定义。
    
        参数:
            node: ONNX 节点对象，通常来自 self.nodes 列表，表示实际图中的节点。
            pnode: PatternNode 对象，定义了一个 pattern 的节点，包括 op_type、输入、属性等。

        返回:
            matched: bool，表示 node 是否匹配 pattern 节点 pnode。
        """
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

    def match_pattern(self, reform_info):

        """
            在整个图 self.nodes 中匹配一个 pattern (reform_info)
    
            参数:
                reform_info (ReformInfo): pattern 定义，包括 src_nodes (pattern 节点列表) 和 dst_nodes (替换节点)
    
            返回:
                matched_patterns (list[ReformInfo]): 匹配到的子图列表，每个都可以用来做替换
        """

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

    def reset_outer_node(self, pattern):

        """
            重置 pattern 中所有 OuterNode 的输出

            参数:
                pattern (list[PatternNode]): 待重置的 pattern 节点列表

            作用：在匹配失败或者完成一次 pattern 匹配后，需要清空 OuterNode 的 output 列表，
                  以保证下一次匹配时 OuterNode 的输出不会干扰。7

        """

        # reset outer node
        for p in pattern:   # 遍历 pattern 中每个 PatternNode
            for pinp in p.input:    # 遍历 PatternNode 的输入
                if isinstance(pinp, OuterNode): # 如果输入是 OuterNode
                    pinp.output.clear()  # 清空输出列表，避免残留影响下次匹配

    def replace_pattern(self, matched_pattern):

        """
        根据匹配到的 pattern 子图，将原图中的子图替换为目标 dst_nodes。

        参数：
            matched_pattern: list[ReformInfo]，包含匹配成功的子图信息及替换目标。
    
        作用：
            用 pattern 的 dst_nodes 替换 src_nodes，更新节点列表和输出映射。
            目前假设子图仅有一个输出。
        """

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

    def remove_unused_tensor(self):

        """
        清理图中未使用的 Constant 或权重节点。

        作用：
            遍历图节点和权重，找到未被任何节点使用的 Constant 或权重，移除它们。
            更新 weight_tensor 和 node_tensor 列表。
        """

        # purging redundancy tensor
        all_input = []  # 所有节点输入
        all_node = [n for n in self.nodes]  # 遍历所有节点副本
        for n in all_node:
            all_input.extend(n.input)   # 收集每个节点的输入名
        unused_weight = []  # 待删除权重列表
        unused_node = []     # 待删除 Constant 节点列表
        for w in self.weight:   # 找出未使用的 weight
            if w.name in all_input:
                continue
            unused_weight.append(w)
        for n in self.nodes:    # 找出未使用的 Constant 节点
            if n.op_type != "Constant" or n.output[0] in all_input:
                continue
            unused_node.append(n)
        for w in unused_weight:
            self.weight.remove(w)
        for n in unused_node:
            self.nodes.remove(n)
        # update        # 更新当前图的 weight_tensor 和 node_tensor
        self.weight_tensor = [x.name for x in self.weight]
        self.node_tensor = [node.output[0] for node in self.nodes if node.op_type == "Constant"]

    def remove_duplicate(self):
        # same op_type and inputs different output_name
        nodes_info = {} # 临时字典，记录每种 op_type 对应的节点输入字符串
        duplicate_op = {}   # 存储检测到重复节点信息 {op_type: [重复输入列表]}
        kept_info = {}      # 记录保留节点的输入对应输出映射
        oname_map = {}      # 记录被移除节点输出 -> 保留节点输出的映射
        rm_node = []        # 待移除节点列表
        # find duplicate node's {op_type: str(inputs)}
        for node in self.nodes: # 遍历所有节点，构建 nodes_info 字典
            if len(node.attribute) > 0:  # FIXME consider node's attr       # 如果节点有属性，暂不考虑重复（属性不同可能功能不同）
                continue
            if node.op_type not in nodes_info:   # 初始化 op_type 列表
                nodes_info[node.op_type] = []
            nodes_info[node.op_type].append(" ".join(node.input))   # 将节点输入序列转为字符串，加入列表
        # 检查重复节点
        for k, v in nodes_info.items(): # 遍历每个 op_type
            if not len(set(v)) == len(v):   # 如果输入字符串去重后数量少于原数量，则存在重复
                inputs = dict(Counter(v))   # 统计每个输入字符串出现次数
                duplicate_op[k] = [i.split(" ") for i, c in inputs.items() if c > 1]    # 保存重复输入（拆回列表）
        nodes_info.clear()  # 清空 nodes_info，释放内存
        # find duplicate node's str(input) output_name
        duplicate_op_type = duplicate_op.keys() # 获取有重复的 op_type 集合
        for node in self.nodes: # 遍历所有节点，确定要移除的节点
            if node.op_type not in duplicate_op_type:   # 如果节点不是重复类型，跳过
                continue
            if node.input in duplicate_op[node.op_type]:    # 如果节点输入属于重复列表
                tinp = node.op_type + " " + " ".join(node.input)     # 构建输入标识字符串
                if tinp not in kept_info:   # 如果还没有保留节点
                    kept_info[tinp] = node.output   # 记录该节点输出为保留节点输出
                else:   # 如果已有保留节点
                    okept = kept_info[tinp] # 保留节点输出
                    oremove = node.output   # 当前节点输出
                    assert (len(okept) == len(oremove))     # 确保输出数量一致
                    for i in range(len(okept)):         # 遍历输出
                        oname_map[oremove[i]] = okept[i]    # 记录被移除输出 -> 保留输出
                    rm_node.append(node)    # 将当前节点加入待移除列表
        # remove duplicat node  # 删除重复节点
        for n in rm_node:
            self.nodes.remove(n)
        # verify inputs for each node
        removed_input = oname_map.keys()    # 获取所有被移除输出名
        for node in self.nodes: # 更新全图节点输入，将被移除输出替换为保留输出
            for i, inp in enumerate(node.input):
                if inp in removed_input:    # 如果输入是被移除的输出
                    node.input[i] = oname_map[inp]  # 替换为保留输出名
        # verify graph output   # 更新图输出，如果有节点输出被移除，也替换为保留输出
        for o in self.gout:
            if o.name in removed_input: # 如果网络输出在移除列表中
                o.name = oname_map[o.name]  # 替换为保留输出名

    def remove_cast(self):
        '''

        移除图中的 Cast 节点（类型转换），并维护图输入输出及中间节点输入引用。

        '''
        cast_ops = []    # 存储所有 Cast 节点
        cast_in_dict = defaultdict(str) # 存储 Cast 节点输入 -> 输出映射，用于正向搜索
        cast_out_dict = defaultdict(str)    # 存储 Cast 节点输出 -> 输入映射，用于反向搜索
        net_out_names = set()   # 存储网络输出节点名称，用于判断是否需要插入 Identity 节点
        for gout in self.gout:  # 遍历网络输出
            net_out_names.add(gout.name)     # 将输出名称加入集合
        reverse_search = False   # 标志是否需要反向搜索

        def find_cast(node, cast_dict): # 定义递归查找最终节点的函数
            if node not in cast_dict:   # 如果当前节点不在映射中
                return node # 返回自身
            else:
                return find_cast(cast_dict[node], cast_dict)    # 否则递归查找映射后的节点

        def insert_identity(cur_node_out, out_name):     # 定义插入 Identity 节点的函数
            identity_node = onnx.helper.make_node("Identity",   # 构造 Identity 节点，输入 cur_node_out，输出 out_name
                                                  name=cur_node_out + "_insert_Identity",
                                                  inputs=[cur_node_out],
                                                  outputs=[out_name])
            insert_idx, _ = self.get_node(out_name) # 获取插入位置
            self.nodes.insert(insert_idx, identity_node)    # 插入节点

        for node in self.nodes: # 正向搜索：把节点输入中指向 Cast 输出的地方直接指向 Cast 输入
            if node.op_type == "Cast":  # 如果是 Cast 节点
                cast_ops.append(node)   # 保存到 Cast 列表
                cast_in_dict[node.output[0]] = node.input[0]    # 记录输入 -> 输出映射
                if node.output[0] in net_out_names: reverse_search = True   # 如果 Cast 输出是网络输出,需要反向搜索
                continue
            if node.op_type == "Constant":  # Constant 节点不处理
                continue
            for i in range(len(node.input)):    # 遍历节点输入
                if node.input[i] in cast_in_dict:   # 如果输入是 Cast 输出
                    node.input[i] = find_cast(cast_in_dict[node.input[i]], cast_in_dict)    # 替换为原始输入

        if reverse_search:  # 反向搜索：如果 Cast 输出是网络输出，需要插入 Identity 保持输出不变
            for node in reversed(self.nodes):   # 逆序遍历节点
                if node.op_type == "Cast":      # 如果是 Cast 节点
                    cast_out_dict[node.input[0]] = node.output[0]   # 输出 -> 输入映射
                    continue
                if node.op_type == "Constant":  # Constant 节点不处理
                    continue
                for i in range(len(node.output)):   # 遍历节点输出
                    if node.output[i] in cast_out_dict: # 如果输出在 Cast 输出列表
                        out_name = find_cast(cast_out_dict[node.output[i]], cast_out_dict)  # 查找最终输出
                        if out_name in net_out_names:   # 如果最终输出是网络输出
                            insert_identity(node.output[i], out_name)   # 插入 Identity 节点

        for op in cast_ops: # 移除所有 Cast 节点
            self.nodes.remove(op)

    # remove invalid slice node which shape is 0
    def remove_invalid_slice(self):

        """
        移除 Slice 节点无效的情况（切片维度为 0），并清理相关输入输出。
        """

        node_slice_name = []    # 存储 Slice 节点输出名称
        node_invalid_slice_name = []    # 存储无效 Slice 节点输出名称
        delete_info_ops = []    # ginfo 中需要删除的节点信息
        delte_node_ops = [] # nodes 中需要删除的 Slice 节点

        for node in self.nodes:     # 找到所有 Slice 节点输出
            if node.op_type == "Slice":
                node_slice_name.append(node.output[0])

        if len(node_slice_name) > 0:    # 如果存在 Slice 节点
            for info in self.ginfo:     # 遍历图信息
                if info.name in node_slice_name:    # 如果 info 对应 Slice 输出
                    for info_dim in info.type.tensor_type.shape.dim:    # 遍历形状维度
                        if info_dim.HasField("dim_value") and info_dim.dim_value == 0:  # 维度为 0
                            node_invalid_slice_name.append(info.name)   # 加入无效 Slice 列表
                            delete_info_ops.append(info)    # 加入 ginfo 删除列表

        if len(node_invalid_slice_name) > 0:    # 如果有无效 Slice
            for node in self.nodes:     # 遍历节点
                if node.output[0] in node_invalid_slice_name:   # 如果输出是无效 Slice
                    delte_node_ops.append(node) # 加入删除节点列表
                for i, input_name in enumerate(node.input): # 遍历节点输入
                    if input_name in node_invalid_slice_name:   # 如果输入是无效 Slice 输出
                        del node.input[i]   # 删除该输入

        for op in delete_info_ops:  # 删除 ginfo 中对应信息
            self.ginfo.remove(op)

        for op in delte_node_ops:   # 删除 nodes 中对应节点
            self.nodes.remove(op)

    def graph_opt(self):

        """
        图优化主流程：
        1. 对每个 pattern 在图中进行匹配
        2. 若匹配成功则替换子图
        3. 递归直到没有更多替换
        """

        replaced = False    # 标志是否有节点被替换
        for reform_info in self.reform_info_list:   # 遍历每个重写规则
            matched_pattern = self.match_pattern(reform_info)   # 匹配 pattern
            if len(matched_pattern) > 0:    # 如果匹配到 pattern
                replaced = True # 标记替换成功
            self.replace_pattern(matched_pattern)   # 执行替换

        if replaced:    # 如果有替换发生
            self.graph_opt()    # 递归优化，处理新生成的子图

    def __call__(self, reform_info_list):

        """
        ReForm 类的调用接口：
        输入重写规则列表，执行一系列图优化操作。
        返回图节点名称映射、节点列表、权重列表。
        """

        self.reform_info_list = reform_info_list    # 保存重写规则列表
        self.remove_cast()   # 先移除所有 Cast 节点
        self.remove_invalid_slice() # 移除无效 Slice 节点
        self.remove_duplicate()  # 移除重复节点
        self.graph_opt()     # 执行 pattern 替换优化
        return self.node_name_mapping, self.nodes, self.weight  # 返回优化结果


###====================== Declare your patterns here ======================###


############ torch.LayerNorm ############
def TorchLayerNormPattern(patterns: list):

    def is_last_dims(x: list):
        return np.all(np.diff(x) == 1) and x[-1] == -1

    reducemean_input = OuterNode()

    pow_tensor = OuterNode(tensor_value=2)
    add_0_tensor = OuterNode(attr_name="eps")
    mul_tensor = OuterNode(is_tensor=True)
    add_1_tensor = OuterNode(is_tensor=True)

    _reducemean_0 = PatternNode(
        "ReduceMean",
        [reducemean_input],
        ["axes"],
        attrcheck=AttrCheck(attrs=["axes"], func=is_last_dims),
    )
    _sub = PatternNode("Sub", [reducemean_input, _reducemean_0])
    _pow = PatternNode("Pow", [_sub, pow_tensor])
    _reducemean_1 = PatternNode(
        "ReduceMean",
        [_pow],
        attrcheck=AttrCheck(attrs=["axes"], func=is_last_dims),
    )
    _add_0 = PatternNode("Add", [_reducemean_1, add_0_tensor])
    _sqrt = PatternNode("Sqrt", [_add_0])
    _div = PatternNode("Div", [_sub, _sqrt])
    mul = PatternNode("Mul", [_div, mul_tensor])
    _add_1 = PatternNode("Add", [mul, add_1_tensor])

    epsilon_attrfunc = AttrFunctor([add_0_tensor], ["eps"])
    axis_attrfunc = AttrFunctor([_reducemean_0], ["axes"], lambda x: x[0])

    # affine (have both weight and bias)
    layernorm_aff = PatternNode("LayerNormalization", [reducemean_input, mul_tensor, add_1_tensor],
                                attrmap={
                                    "epsilon": epsilon_attrfunc,
                                    "axis": axis_attrfunc
                                })
    patterns.append(
        ReformInfo(
            name="layernorm_aff",
            src_nodes=[_reducemean_0, _sub, _pow, _reducemean_1, _add_0, _sqrt, _div, mul, _add_1],
            dst_nodes=[layernorm_aff]))
    # without affine (do not have both weight and bias)
    layernorm = PatternNode("LayerNormalization", [reducemean_input],
                            attrmap={
                                "epsilon": epsilon_attrfunc,
                                "axis": axis_attrfunc
                            })
    patterns.append(
        ReformInfo(name="layernorm",
                   src_nodes=[_reducemean_0, _sub, _pow, _reducemean_1, _add_0, _sqrt, _div],
                   dst_nodes=[layernorm]))


############ torch.PixelNorm ############
def TorchPixelNormPattern(patterns: list):

    def is_c_dim(x: list):
        return len(x) == 1 and x[0] == 1

    reducemean_input = OuterNode()

    pow_tensor = OuterNode(tensor_value=2)
    add_0_tensor = OuterNode(attr_name="eps")
    mul_tensor = OuterNode(is_tensor=True)
    add_1_tensor = OuterNode(is_tensor=True)

    _reducemean_0 = PatternNode(
        "ReduceMean",
        [reducemean_input],
        ["axes"],
        attrcheck=AttrCheck(attrs=["axes"], func=is_c_dim),
    )
    _sub = PatternNode("Sub", [reducemean_input, _reducemean_0])
    _pow = PatternNode("Pow", [_sub, pow_tensor])
    _reducemean_1 = PatternNode(
        "ReduceMean",
        [_pow],
        attrcheck=AttrCheck(attrs=["axes"], func=is_c_dim),
    )
    _add_0 = PatternNode("Add", [_reducemean_1, add_0_tensor])
    _sqrt = PatternNode("Sqrt", [_add_0])
    _div = PatternNode("Div", [_sub, _sqrt])
    mul = PatternNode("Mul", [_div, mul_tensor])
    _add_1 = PatternNode("Add", [mul, add_1_tensor])

    epsilon_attrfunc = AttrFunctor([add_0_tensor], ["eps"])

    # affine (have both weight and bias)
    layernorm_aff = PatternNode("PixelNormalization", [reducemean_input, mul_tensor, add_1_tensor],
                                attrmap={"epsilon": epsilon_attrfunc})
    patterns.append(
        ReformInfo(
            name="pixelnorm_aff",
            src_nodes=[_reducemean_0, _sub, _pow, _reducemean_1, _add_0, _sqrt, _div, mul, _add_1],
            dst_nodes=[layernorm_aff]))
    # without affine (do not have both weight and bias)
    layernorm = PatternNode("PixelNormalization", [reducemean_input],
                            attrmap={"epsilon": epsilon_attrfunc})
    patterns.append(
        ReformInfo(name="pixelnorm",
                   src_nodes=[_reducemean_0, _sub, _pow, _reducemean_1, _add_0, _sqrt, _div],
                   dst_nodes=[layernorm]))


############ torch.GELU ############
def TorchGELUPattern(patterns: list):
    gelu_input = OuterNode()
    div_tensor = OuterNode(is_tensor=True)
    add_tensor = OuterNode(tensor_value=1)
    mul_tensor = OuterNode(tensor_value=0.5)

    _div = PatternNode("Div", [gelu_input, div_tensor])
    _erf = PatternNode("Erf", [_div])
    _add = PatternNode("Add", [_erf, add_tensor])
    _mu_0 = PatternNode("Mul", [gelu_input, _add])
    _mul_1 = PatternNode("Mul", [_mu_0, mul_tensor])
    gelu = PatternNode("GELU", [gelu_input])
    patterns.append(
        ReformInfo(name="GELU", src_nodes=[_div, _erf, _add, _mu_0, _mul_1], dst_nodes=[gelu]))


def TorchGELUPattern2(patterns: list):
    gelu_input = OuterNode()
    add_tensor = OuterNode(tensor_value=1)
    mul_tensor = OuterNode(tensor_value=0.5)
    power_tensor = OuterNode(tensor_value=3)
    add_tensor = OuterNode(tensor_value=1)
    mul_tensor_1 = OuterNode(is_tensor=True)
    mul_tensor_2 = OuterNode(is_tensor=True)
    _mul_0 = PatternNode("Mul", [gelu_input, mul_tensor])
    _power_1 = PatternNode("Pow", [gelu_input, power_tensor])
    _mul_2 = PatternNode("Mul", [_power_1, mul_tensor_1])
    _add_3 = PatternNode("Add", [gelu_input, _mul_2])
    _mul_4 = PatternNode("Mul", [_add_3, mul_tensor_2])
    _tanh_5 = PatternNode("Tanh", [_mul_4])
    _add_6 = PatternNode("Add", [_tanh_5, add_tensor])
    _mul_7 = PatternNode("Mul", [_mul_0, _add_6])
    gelu = PatternNode("GELU", [gelu_input])
    patterns.append(
        ReformInfo(name="GELU",
                   src_nodes=[_mul_0, _power_1, _mul_2, _add_3, _mul_4, _tanh_5, _add_6, _mul_7],
                   dst_nodes=[gelu]))


############ torch.HardSigmodid ############
def TorchHardSigmoidPattern(patterns: list):
    # nomal case
    add_input = OuterNode()
    add_tensor = OuterNode(tensor_value=3)
    clip_min = OuterNode(tensor_value=0)
    clip_max = OuterNode(tensor_value=6)
    div_tensor = OuterNode(tensor_value=6)
    add = PatternNode("Add", [add_input, add_tensor])
    clip = PatternNode("Clip", [add, clip_min, clip_max])
    div = PatternNode("Div", [clip, div_tensor])
    hard_sigmoid = PatternNode("HardSigmoid", [add_input])
    patterns.append(
        ReformInfo(name="HardSigmoid", src_nodes=[add, clip, div], dst_nodes=[hard_sigmoid]))


############ torch.HardSwish ############
def TorchHardSwishPattern(patterns: list):
    input = OuterNode()
    attrcheck = AttrCheck(attrs=['alpha', 'beta'],
                          func=lambda x, y: x == 0.1666666716337204 and y == 0.5)
    hard_sigmoid = PatternNode("HardSigmoid", [input], attrcheck=attrcheck)
    mul = PatternNode("Mul", [input, hard_sigmoid])
    hard_swish = PatternNode("HardSwish", [input])
    patterns.append(
        ReformInfo(name="hardswish", src_nodes=[hard_sigmoid, mul], dst_nodes=[hard_swish]))


def TorchHardSwishPattern2(patterns: list):
    add_input = OuterNode()
    add_tensor = OuterNode(tensor_value=3)
    clip_min = OuterNode(tensor_value=0)
    clip_max = OuterNode(tensor_value=6)
    div_tensor = OuterNode(tensor_value=6)

    add = PatternNode("Add", [add_input, add_tensor])
    clip = PatternNode("Clip", [add, clip_min, clip_max])
    mul = PatternNode("Mul", [add_input, clip])
    div = PatternNode("Div", [mul, div_tensor])
    hard_swish = PatternNode("HardSwish", [add_input])
    patterns.append(
        ReformInfo(name="hardswish", src_nodes=[add, clip, mul, div], dst_nodes=[hard_swish]))


###====================== Register your custom operators here ======================###


############ correlation ############
@onnx_op(
    op_type="tpu_mlir::Correlation",
    inputs=[
        PyOp.dt_float,  # 0: left_features,
        PyOp.dt_float,  # 1: right_features
    ],
    outputs=[PyOp.dt_float],
    attrs={
        "max_disp": PyOp.dt_int64,
        "num_groups": PyOp.dt_int64
    })
def correlation(left_features, right_features, max_disp, num_groups):
    # the user custom op implementation here:
    b, c, h, w = left_features.shape
    left_features = left_features.reshape(num_groups, c // num_groups, h, w)
    right_features = right_features.reshape(num_groups, c // num_groups, h, w)
    cost_volume = np.zeros((num_groups, max_disp, h, w), dtype=left_features.dtype)
    for i in range(max_disp):
        if i > 0:
            cost_volume[:, i, :, i:] = (left_features[:, :, :, i:] *
                                        right_features[:, :, :, :-i]).mean(axis=1)
        else:
            cost_volume[:, i, :, :] = (left_features * right_features).mean(axis=1)
    return cost_volume


############ SelectiveScan ############
@onnx_op(
    op_type="tpu_mlir::SelectiveScan",
    inputs=[
        PyOp.dt_float,  # 0: c
        PyOp.dt_float,  # 1: deltaA
        PyOp.dt_float,  # 2: deltaB_u
        PyOp.dt_float,  # 3: u
        PyOp.dt_float,  # 4: D
    ],
    outputs=[PyOp.dt_float],
    attrs={})
def SelectiveScan(c, deltaA, deltaB_u, u, D):
    """
    NumPy implementation of SelectiveScan

    Parameters:
        u:          input tensor [N, Kcdim, L, Batch]
        deltaA:     ΔA tensor [N, Kcdim, L, Batch]
        deltaB_u:   ΔB ⊙ u tensor [N, Kcdim, L, Batch]
        c:          context tensor [L, Kcdim, N, Batch]
        D:          residual parameter tensor [Kdim] or None

    Returns:
        out:        output tensor [L, Kcdim, Batch]
    """
    N, Kcdim, L, Batch = deltaA.shape
    Cdim_plus_2 = Kcdim // 2

    deltaA_up = deltaA[:, :Cdim_plus_2, :, :]
    deltaA_down = deltaA[:, Cdim_plus_2:, :, :]

    deltaB_u_up = deltaB_u[:, :Cdim_plus_2, :, :]
    deltaB_u_down = deltaB_u[:, Cdim_plus_2:, :, :]

    c_up = c[:, :Cdim_plus_2, :, :]
    c_down = c[:, Cdim_plus_2:, :, :]

    dtype = c.dtype
    x_up = np.zeros((N, Cdim_plus_2, Batch), dtype=dtype)
    x_down = np.zeros((N, Cdim_plus_2, Batch), dtype=dtype)

    y_up = np.zeros((L, Cdim_plus_2, Batch), dtype=dtype)
    y_down = np.zeros((L, Cdim_plus_2, Batch), dtype=dtype)

    for i in range(L):
        # x(t) = ΔA * x(t-1) + ΔB ⊙ u
        x_up = deltaA_up[:, :, i, :] * x_up + deltaB_u_up[:, :, i, :]

        y_up[i, :, :] = x_up[0, :, :] * c_up[i, :, 0, :]

    for i in range(L):
        rev_i = L - 1 - i

        # x(t) = ΔA * x(t+1) + ΔB ⊙ u
        x_down = deltaA_down[:, :, rev_i, :] * x_down + deltaB_u_down[:, :, rev_i, :]

        y_down[rev_i, :, :] = x_down[0, :, :] * c_down[rev_i, :, 0, :]

    y = np.concatenate([y_up, y_down], axis=1)  # Output shape [L, Kcdim, Batch]

    if D is not None:
        residual = u * D[np.newaxis, :, np.newaxis]
        out = y + residual
    else:
        out = y

    return out


def remove_tensor_from_input(model):
    tensor_names = [x.name for x in model.graph.initializer]
    tensor_names.extend([x.name for x in model.graph.node if x.op_type == "Constant"])
    inputs = model.graph.input
    tensors = []
    for i in inputs:
        if i.name in tensor_names:
            tensors.append(i)
    for t in tensors:
        model.graph.input.remove(t)


def onnx_opt(model, dump=False, rigorous=True):
    remove_tensor_from_input(model)
    # add your patterns here if you expect that your patterns actually works
    pattern_functions = [
        TorchLayerNormPattern,
        TorchPixelNormPattern,
        TorchHardSigmoidPattern,
        TorchHardSwishPattern,
        TorchHardSwishPattern2,
        TorchGELUPattern,
        TorchGELUPattern2,
    ]

    patterns = []
    for pf in pattern_functions:
        pf(patterns)

    reform = ReForm(model, rigorous)
    node_name_mapping, _, _ = reform(patterns)
    if dump:
        dump_model(model, "final_opt.onnx")
    return model, node_name_mapping
