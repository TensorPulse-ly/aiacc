# Copyright (C) 2022 Sophgo Technologies Inc.  All rights reserved.
#
# TPU-MLIR is licensed under the 2-Clause BSD License except for the
# third-party components.
#
# ==============================================================================

from mlir.ir import *   #导入MLIR核心IR构建工具，包括Context、Location、Type、Operation等所有基础类
import mlir.dialects.top as top     #导入TPU-MLIR定制的"top"dialect，包含TPU特有的操作如InputOp、WeightOp等


class State:        #State枚举 - 模型状态吗，表示模型的精度状态，F32用于训练和高精度推理，QUANTIZED用于量化部署。
    TOP_F32 = 'TOP_F32'
    TOP_QUANTIZED = 'TOP_QUANTIZED'


class Platform:     #Platform枚举 - 支持的框架，支持多种深度学习框架的模型转换，体现了TPU-MLIR的通用性。
    ONNX = "ONNX"
    TORCH = "TORCH"
    TFLITE = "TFLITE"
    CAFFE = "CAFFE"
    TPULANG = "TPULANG"
    LLM = "LLM"


def get_weight_file(model_name: str, state: str, chip: str):    #权重文件命名工具
    name = "{}_{}_{}_origin_weight.npz".format(model_name, state, chip)     #模型名_状态_芯片类型_origin_weight.npz，统一的权重文件命名约定。
    return name.lower() #把nam中大写字母变成小写字母


class MLIRImporter(object):

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

    def __del__(self):  #析构函数
        try:
            self.loc.__exit__(None, None, None) # 安全退出位置上下文
        except:
            pass    # 忽略退出异常
        try:
            self.ctx.__exit__(None, None, None) # 安全退出MLIR上下文
        except:
            pass    # 忽略退出异常

    #ArrayAttr() - 数组属性构造器
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

    def get_value_type(self, value):    #从一个MLIR值对象中提取出它的元素数据类型。
        _type = str(value.type) #类型字符串提取  value.type：访问MLIR值的type属性，返回Type对象     str(...)：将Type对象转换为字符串表示
        """
        假设value是一个tensor<1x3x224x224xf32>类型的值
        value.type  # → RankedTensorType对象
        str(value.type)  # → "tensor<1x3x224x224xf32>"
        _type = "tensor<1x3x224x224xf32>"
        """
        _type = _type.split('<')[-1].split('x')[-1].split('>')[0]   #链式字符串处理
        """
        例如tensor<1x3x224x224xf32>
        首先split('<')是将其按<分割，分割后为["tensor", "1x3x224x224xf32>"]
        [-1]表示取最后一个元素，为1x3x224x224xf32
        split('x')表示再按x分割，分割后为["1", "3", "224", "224", "f32>"]
        [-1]与split('>')使其结果为["f32", ""]
        [0]取第一个元素，即为f32。总的来说这就是获取元素类型
        """
        if _type == "f32":  #如果是f32，从类型字典里获取F32Type对象
            return self.mlir_type['F32']
        elif _type == "i8":
            return self.mlir_type['INT8']
        elif _type == "ui8":
            return self.mlir_type['UINT8']
        elif _type == "i32" or _type == "si32":
            return self.mlir_type['INT32']
        else:   #所有条件都不满足，报错
            raise RuntimeError("No support {}".format(_type))

    def buildBlock(self, region, arg_types, **kargs):   #定义一个实例方法，接收region（区域）、arg_types（参数类型）和可变关键字参数
        block = Block.create_at_start(region, arg_types)    #在指定区域的开始位置创建一个新的基本块     Block.create_at_start(): MLIR API调用，在region开头创建block

    def reconfig_insert_point(self, block): #如果insert_point_save_flag为False，则备份当前插入点
        self.insert_point_back = self.insert_point \
                        if not self.insert_point_save_flag else self.insert_point_back
        self.insert_point = InsertionPoint(block)   #创建新的插入点对象，指向传入的block
        self.insert_point_save_flag = True  #设置保存标志为True，表示已备份插入点

    def restore_insert_point(self): #恢复之前保存的插入点状态
        self.insert_point = self.insert_point_back  #将当前插入点恢复为备份的插入点
        self.insert_point_save_flag = False #重置保存标志

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

    def create_return_op(self, Operands):
        return_op = Operation.create("func.return", operands=Operands, results=[])  #创建返回操作   "func.return"：操作名称字符串   operands=Operands：关键字参数，指定操作的输入操作数     results=[]：关键字参数，指定操作的输出结果类型
        self.insert_point.insert(return_op) #self.insert_point：当前代码插入点对象，.insert(op)：方法调用，将操作插入到指定位置
        return return_op    #返回值：创建的MLIR操作对象

    def create_yield_op(self, Operands):    #让步操作创建器 Operands：要让步（yield）的值列表，用于控制流操作的块终结
        yield_op = Operation.create("top.Yield", operands=Operands, results=[])
        self.insert_point.insert(yield_op)
        return yield_op

    def create_if_op(self, operands, output_shape, **kargs):    #条件操作创建器     **kargs：关键字参数字典，包含额外配置，必需参数："region"：区域数量（整数），"name"：操作名称列表，用于调试
        region = IntegerAttr.get(self.mlir_type['INT64'], kargs["region"]).value
        op = Operation.create("top.If",
                              results=[self.get_tensor_type(output_shape)], #调用get_tensor_type获取输出类型，用列表包装，表示单个输出
                              operands=operands,
                              loc=Location.fused([Location.name(x) for x in kargs['name']]),    #遍历名称列表，为每个名称创建位置对象
                              attributes=dict(),
                              regions=region)
        self.insert_point.insert(op)
        return op.result

    def create_loop_op(self, operands, output_shape, **kargs):
        region = IntegerAttr.get(self.mlir_type['INT64'], kargs["region"]).value
        op = Operation.create("top.Loop",
                              results=self.get_tensor_type(output_shape),
                              operands=operands,
                              loc=Location.fused([Location.name(x) for x in kargs['name']]),
                              attributes=dict(),
                              regions=region)
        self.insert_point.insert(op)
        return op.results

    def create_subgraph_input_op(self, name, type, val, **kargs):   #子图输入创建器
        param = {}  #为操作属性准备空字典
        op = Operation.create("top.Input",
                              results=[type],
                              operands=[val],
                              loc=Location.fused([Location.name(name)]),
                              attributes=param)
        self.insert_point.insert(op)
        return op.results[0]

    def create_range_op(self, operands, output_shape, **kargs):
        # output_type = self.get_tensor_type(output_shape)
        # param = {'name': kargs['name']}
        # return self.buildOp(Top.RangeOp, operands, [output_type], **param)
        pass

    def print_module(self): #模块打印器
        mlir_format = self.mlir_module.operation.get_asm(enable_debug_info=True)
        return mlir_format

    #MLIR函数声明器
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