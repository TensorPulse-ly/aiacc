# Copyright (C) 2022 Sophgo Technologies Inc.  All rights reserved.
#
# TPU-MLIR is licensed under the 2-Clause BSD License except for the
# third-party components.
#
# ==============================================================================

# ONNX Node define:
# https://github.com/onnx/onnx/blob/main/docs/Operators.md

from .MLIRImporter import MLIRImporter, Platform    #MLIRImporter: 用于将计算图转换为 MLIR 格式的核心类
from .BaseConverter import BaseConverter    #BaseConverter: 转换器的基类，提供通用功能
from .OnnxOpt import onnx_opt, ConstantFolding  #OnnxOpt: ONNX 模型优化相关功能，包括常量折叠
from onnx import numpy_helper, mapping      #onnx: ONNX 模型处理库
from numbers import Number  # numpy: 数值计算库，用于处理张量数据
import onnx
import numpy as np
from utils.pad_setting import set_auto_pad  #set_auto_pad: 自动填充设置工具
from utils.auto_remove import file_mark, file_clean #file_mark/file_clean: 文件管理工具，可能用于临时文件处理
import copy, sys
import mlir.dialects.top as top
from mlir.ir import *
from typing import List
import onnxsim.onnx_simplifier as onnxsim   #onnxsim: ONNX 模型简化工具
import onnxruntime as rt    #onnxruntime: ONNX 运行时，可能用于模型验证或推理
import logging  #logging: 日志记录模块
import copy
import time

logger = logging.getLogger("root")  #设置日志记录器
sys.setrecursionlimit(1000000)

onnx_attr_translator = {    #onnx_attr_translator 是一个字典，本质上是一个函数查找表，用于将 ONNX 节点属性（存储为通用格式）转换为 特定的 Python 数据类型。这是在 ONNX 模型解析过程中非常重要的数据清洗和标准化步骤。
    "axis": lambda x: int(x),   # 将属性转换为整数
    "axes": lambda x: [int(a) for a in x],  # 将属性转换为整数列表
    "dtype": lambda x: onnx_dtype(x),   # 转换为 ONNX 数据类型（需要外部函数）
    "keepdims": lambda x: bool(x),  # 转换为布尔值
    "to": lambda x: onnx_dtype(x),  # 转换为 ONNX 数据类型
}

int64_max = np.iinfo(np.int64).max      #定义 int64 和 int32 的最大值，可能用于边界检查或特殊处理
int32_max = np.iinfo(np.int32).max

#下面3个函数：translate_onnx，onnx_dtype，convert_onnx_attribute_proto，是用于处理ONNX模型中的属性转换
def translate_onnx(key, val):   #这是一个通用的属性转换函数，根据属性名称 (key) 选择合适的转换器
    return onnx_attr_translator.get(key, lambda x: x)(val)  #使用之前定义的 onnx_attr_translator 字典来查找对应的转换函数，如果找不到对应的转换器，使用恒等函数 lambda x: x（即直接返回原值）


def onnx_dtype(dtype):  #dtype输入参数类型可以是：数字（整数）：ONNX 数据类型的枚举值，字符串：ONNX 数据类型的名称。其他类型：会抛出运行时错误
    if isinstance(dtype, Number):   #判断是否是Number类型
        onnx_dtype = dtype      #如果是直接使用数字值
    elif isinstance(dtype, str):    #判断是否是字符串
        onnx_dtype = onnx.TensorProto.DataType.Value(dtype) #将字符串转换为枚举值
    else:   ## 类型错误处理
        raise RuntimeError("dtype should be number or str.")
    return mapping.TENSOR_TYPE_TO_NP_TYPE[onnx_dtype]


#这个函数是将一个 ONNX 协议缓冲区（protobuf）的 AttributeProto 对象转换成一个标准的 Python 数据类型。
#为什么需要这个函数？
#在 ONNX 模型文件中，节点的属性（如卷积的 kernel_shape、步长 strides、填充 pads 等）是以 Google Protocol Buffers 的格式存储的。
#这是一种高效的二进制序列化格式，但在 Python 代码中直接使用很不方便。此函数的作用就是将这些 protobuf 对象“解包”成直观的 Python 列表、整数、浮点数等，供后续的转换逻辑使用。
def convert_onnx_attribute_proto(attr_proto):
    if attr_proto.HasField('f'):    #检查属性是否包含一个单精度浮点数f代表 float
        return attr_proto.f #返回 Python 的 float 类型数值。
    elif attr_proto.HasField('i'):  #整数
        return attr_proto.i
    elif attr_proto.HasField('s'):  #字符串
        return attr_proto.s
    elif attr_proto.HasField('t'):  #tensor
        return attr_proto.t  # this is a proto! 直接返回 attr_proto.t，这是一个 TensorProto 对象本身，而不是转换后的值。
    elif attr_proto.floats: #检查属性中是否包含一个float列表
        return list(attr_proto.floats)  #返回一个 Python 的 list，元素为 float。
    elif attr_proto.ints:   #整数列表
        return list(attr_proto.ints)
    elif attr_proto.strings:    #字符串列表
        str_list = list(attr_proto.strings)
        return str_list
    elif attr_proto.name:   #检查属性是否包含一个名称列表
        name_list = list(attr_proto.name)   #返回一个 Python 的 list。
        return name_list
    else:   #如果以上所有字段都不存在，说明遇到了不支持的属性类型。抛出一个 ValueError 异常
        raise ValueError("Unsupported ONNX attribute: {}".format(attr_proto))


#这个类的目的是将一个通用操作的抽象信息封装成一个结构化的、易于操作的 Python 对象。
#作用： 作为计算图中节点的通用表示模板，存储节点的所有关键信息。
class BaseNode():

    def __init__(self, info):   #它接受一个字典 info 作为参数，这个字典预期包含以下键，用于初始化节点的属性：
        self.name = str(info["name"])   #info["name"]，节点的唯一标识符
        self.op_type = str(info["op_type"]) #info["op_type"]， 节点的操作类型，即它执行的计算种类。例如Conv，Const等
        self.attrs = dict(info["attrs"])    #info["attrs"]， 一个字典，存储了该操作节点的所有属性
        self.inputs = list(info["inputs"])  #info["inputs"]， 一个列表，存储了该节点的所有输入张量的名称。
        self.outputs = list(info["outputs"])    #info["outputs"]，  一个列表，存储了该节点的所有输出张量的名称。
        self.shape_info = dict()    #一个初始化为空的字典，用于在后续的图处理过程中存储和缓存与该节点输入/输出张量相关的形状信息。


#这个类是专门为了封装和表示 ONNX 模型中的节点而设计的。它继承自BaseNode
class OnnxNode(BaseNode):
    #OnnxNode 类扮演了一个桥梁的角色：它输入是原始的、底层的、与 ONNX protobuf 格式紧密耦合的 NodeProto 对象。输出是 一个干净的、标准化的、易于处理的 BaseNode 子类对象。
    def __init__(self, node):   #它接受一个参数 node，这是一个 ONNX 的 NodeProto 对象（直接来自加载的 .onnx 模型）。
        info = dict()   #创建info字典

        info["name"] = node.output[0]   #设置节点的名称。使用该节点的第一个输出张量的名称作为整个节点的名称。
        info["op_type"] = node.op_type  #设置节点的操作类型。直接从 NodeProto 对象的 op_type 字段获取。
        info["attrs"] = [(attr.name, translate_onnx(attr.name, convert_onnx_attribute_proto(attr))) #构建节点的属性字典。这是最关键的一步，它完成了从 ONNX 原生属性到标准化 Python 数据类型的转换。
                         for attr in node.attribute]
        info["inputs"] = node.input #设置节点的输入列表。直接使用 NodeProto 的 input 字段，它是一个列表，包含了所有输入张量的名称。
        info["outputs"] = node.output   #设置节点的输出列表。直接使用 NodeProto 的 output 字段，它是一个列表，包含了所有输出张量的名称。
        super().__init__(info)  #调用父类 BaseNode 的构造函数，完成对象的初始化。它将上面准备好的 info 字典传递给 BaseNode，由 BaseNode 来创建 self.name, self.op_type 等实例变量。
        self.node_proto = node  #将原始的 ONNX NodeProto 对象作为一个成员变量保存起来。为了保留所有原始信息，以备不时之需。


class OnnxConverter(BaseConverter):

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

        self.onnxop_factory = {     #字典，键是算子名称，值是Lambda 函数，这些函数包装了对实际转换方法的调用
            # NOTICE: Please add the Op alphabetically !!!  注意：请按字母顺序添加操作符。
            "Abs": lambda node: self.convert_abs_op(node),
            "Add": lambda node: self.convert_add_op(node),
            "Acos": lambda node: self.convert_arccos_op(node),
            "Atan": lambda node: self.convert_arctan_op(node),
            "Atanh": lambda node: self.convert_arctanh_op(node),
            "ArgMax": lambda node: self.convert_arg_op(node),
            "ArgMin": lambda node: self.convert_arg_op(node),
            "And": lambda node: self.convert_cmp_op(node),
            "AveragePool": lambda node: self.convert_avgpool_op(node),
            "BatchNormalization": lambda node: self.convert_batchnorm_op(node),
            "Cast": lambda node: self.convert_cast_op(node),
            "Ceil": lambda node: self.convert_ceil_op(node),
            "Concat": lambda node: self.convert_concat_op(node),
            "Constant": lambda node: self.convert_constant_op(node),
            "ConstantOfShape": lambda node: self.convert_constantofshape_op(node),
            "Conv": lambda node: self.convert_conv_op(node),
            "Correlation": lambda node: self.convert_correlation_op(node),
            "Cos": lambda node: self.convert_cos_op(node),
            "Clip": lambda node: self.convert_clip_op(node),
            "ConvTranspose": lambda node: self.convert_conv_transpose_op(node),
            "CumSum": lambda node: self.convert_cumsum_op(node),
            "DepthToSpace": lambda node: self.convert_depth2space_op(node),
            "DequantizeLinear": lambda node: self.convert_deqlinear_op(node),
            "Div": lambda node: self.convert_div_op(node),
            "Dropout": lambda node: self.convert_skip_op(node),
            "Einsum": lambda node: self.convert_einsum_op(node),
            "Elu": lambda node: self.convert_elu_op(node),
            "Erf": lambda node: self.convert_erf_op(node),
            "Exp": lambda node: self.convert_exp_op(node),
            "Expand": lambda node: self.convert_expand_op(node),
            "Equal": lambda node: self.convert_cmp_op(node),
            "Flatten": lambda node: self.convert_flatten_op(node),
            "Floor": lambda node: self.convert_floor_op(node),
            "Gather": lambda node: self.convert_gather_op(node),
            "GatherElements": lambda node: self.convert_gather_elements_op(node),
            "GatherND": lambda node: self.convert_gathernd_op(node),
            "GELU": lambda node: self.convert_gelu_op(node),
            "Gemm": lambda node: self.convert_gemm_op(node),
            "GlobalAveragePool": lambda node: self.convert_global_avgpool_op(node),
            "GlobalMaxPool": lambda node: self.convert_global_maxpool_op(node),
            "GroupNormalization": lambda node: self.convert_group_norm_op(node),
            "Greater": lambda node: self.convert_cmp_op(node),
            "GreaterOrEqual": lambda node: self.convert_cmp_op(node),
            "GridSample": lambda node: self.convert_grid_sampler_op(node),
            "GRU": lambda node: self.convert_gru_op(node),
            "HardSigmoid": lambda node: self.convert_hsigmoid_op(node),
            "HardSwish": lambda node: self.convert_hswish_op(node),
            "Identity": lambda node: self.convert_skip_op(node),
            "InstanceNormalization": lambda node: self.convert_instance_norm_op(node),
            "LayerNormalization": lambda node: self.convert_layer_norm_op(node),
            "LeakyRelu": lambda node: self.convert_leaky_relu_op(node),
            "Log": lambda node: self.convert_log_op(node),
            "LRN": lambda node: self.convert_lrn_op(node),
            "LSTM": lambda node: self.convert_lstm_op(node),
            "LogSoftmax": lambda node: self.convert_softmax_op(node),
            "Less": lambda node: self.convert_cmp_op(node),
            "LessOrEqual": lambda node: self.convert_cmp_op(node),
            "MatMul": lambda node: self.convert_gemm_op(node),
            "Max": lambda node: self.convert_max_op(node),
            "MaxPool": lambda node: self.convert_maxpool_op(node),
            "Min": lambda node: self.convert_min_op(node),
            "Mod": lambda node: self.convert_mod_op(node),
            "Mul": lambda node: self.convert_mul_op(node),
            "Neg": lambda node: self.convert_neg_op(node),
            "NonMaxSuppression": lambda node: self.convert_nms_op(node),
            "Not": lambda node: self.convert_not_op(node),
            "NonZero": lambda node: self.convert_nonzero_op(node),
            "OneHot": lambda node: self.convert_onehot_op(node),
            "Or": lambda node: self.convert_or_op(node),
            "Pad": lambda node: self.convert_pad_op(node),
            "PixelNormalization": lambda node: self.convert_pixel_norm_op(node),
            "PRelu": lambda node: self.convert_prelu_op(node),
            "Pow": lambda node: self.convert_pow_op(node),
            "QuantizeLinear": lambda node: self.convert_qlinear_op(node),
            "RandomNormalLike": lambda node: self.convert_random_normal_op(node),
            "Range": lambda node: self.convert_range_op(node),
            "Reciprocal": lambda node: self.convert_reciprocal_op(node),
            "ReduceMean": lambda node: self.convert_reduce_op(node),
            "ReduceMax": lambda node: self.convert_reduce_op(node),
            "ReduceMin": lambda node: self.convert_reduce_op(node),
            "ReduceL2": lambda node: self.convert_reduce_op(node),
            "ReduceL1": lambda node: self.convert_reduce_op(node),
            "ReduceProd": lambda node: self.convert_reduce_op(node),
            "ReduceSum": lambda node: self.convert_reduce_op(node),
            "ReduceLogSumExp": lambda node: self.convert_reduce_log_sum_exp_op(node),
            "Relu": lambda node: self.convert_relu_op(node),
            "Reshape": lambda node: self.convert_reshape_op(node),
            "Resize": lambda node: self.convert_resize_op(node),
            "ReverseSequence": lambda node: self.convert_reverse_sequence_op(node),
            "RoiAlign": lambda node: self.convert_roi_align_op(node),
            "Round": lambda node: self.convert_round_op(node),
            "ScatterElements": lambda node: self.convert_scatter_elements_op(node),
            "ScatterND": lambda node: self.convert_scatternd_op(node),
            "SelectiveScan": lambda node: self.convert_selective_scan(node),
            "Shape": lambda node: self.convert_shape_op(node),
            "Sigmoid": lambda node: self.convert_sigmoid_op(node),
            "Sign": lambda node: self.convert_sign_op(node),
            "Sin": lambda node: self.convert_sin_op(node),
            "Slice": lambda node: self.convert_slice_op(node),
            "Softmax": lambda node: self.convert_softmax_op(node),
            "Softplus": lambda node: self.convert_softplus_op(node),
            "SpaceToDepth": lambda node: self.convert_space2depth_op(node),
            "Squeeze": lambda node: self.convert_squeeze_op(node),
            "Split": lambda node: self.convert_split_op(node),
            "Sub": lambda node: self.convert_sub_op(node),
            "Sum": lambda node: self.convert_sum_op(node),
            "Sqrt": lambda node: self.convert_sqrt_op(node),
            "Tanh": lambda node: self.convert_tanh_op(node),
            "Tile": lambda node: self.convert_tile_op(node),
            "TopK": lambda node: self.convert_topk_op(node),
            "Trilu": lambda node: self.convert_trilu_op(node),
            "Transpose": lambda node: self.convert_transpose_op(node),
            "Unsqueeze": lambda node: self.convert_unsqueeze_op(node),
            "Upsample": lambda node: self.convert_upsample_op(node),
            "Where": lambda node: self.convert_where_op(node),
            "Xor": lambda node: self.convert_cmp_op(node),
            "If": lambda node: self.convert_if_op(node),
            "Loop": lambda node: self.convert_loop_op(node),
        }

    def __del__(self):      #析构函数
        if self.mlir != None:   #检查self.mlir是否为None
            del self.mlir   #如果不是none，del self.mlir释放资源
            self.mlir = None    #将 self.mlir 设置为 None，确保不会再次访问已删除的对象

    def cleanup(self):  #用于清理转换过程中可能生成的临时文件
        file_clean()

    def check_need(self, name): #检查张量是否被需要
        for node in self.converted_nodes:   #遍历所有已转换的节点 
            for i in node.inputs:   #遍历所有输入张量名称
                if i == name:   #如果找到与name匹配的输入张量，立即返回true
                    return True
        if name in self.output_names:   #检查name是否再输出张量名称列表
            return True #如果在，返回true
        return False    #如果上面两个条件都不满足，返回False

    def select_unuse(self, names):  #参数: names - 要检查的张量名称列表，这些张量被认为是"已使用"的起点
        for name in names:  #遍历传入的所有名称
            if name in self.all_weights:    #权重/常量张量集合
                self.all_weights.pop(name)  # 如果当前名称在权重字典 self.all_weights 中，则从字典中移除该名称对应的权重
            if name in self.all_values: #中间值信息集合
                self.all_values.pop(name)
            if name in self.all_inputs: #模型输入集合
                self.all_inputs.pop(name)
            if name in self.all_nodes:  #节点集合（通过输出名称索引）
                cur_node = self.all_nodes.pop(name)
                for o in cur_node.output:
                    if o in self.all_nodes:
                        self.all_nodes.pop(o)
                self.select_unuse(cur_node.input)

    def select_output(self, output_names: list):    #output_names - 要保留的输出张量名称列表
        # set new output
        self.all_outputs = []   #初始化一个空列表 self.all_outputs，用于存储最终需要保留的输出名称
        self.all_inputs = {}    #初始化一个空字典 self.all_inputs，用于存储需要保留的输入
        for x in self.model.graph.input:
            self.all_inputs[x.name] = x     #遍历模型的所有输入，将输入名称映射到输入对象，存入 self.all_inputs
        self.all_values = {}    #初始化一个空字典 self.all_values，用于存储需要保留的值信息
        for x in self.model.graph.output:   #遍历模型的所有输出
            if x.name in output_names:  #检查当前输出名称是否在请求的输出名称列表中
                self.all_outputs.append(x.name) #将输出名称添加到需要保留的输出列表
                output_names.remove(x.name) # 从请求的输出名称列表中移除已处理的名称
                if len(output_names) == 0:  #如果所有请求的输出都已找到，提前终止循环
                    break
        for x in self.model.graph.value_info:   #遍历模型的所有值信息
            self.all_values[x.name] = x #将值信息名称映射到值信息对象，存入 self.all_values
            if x.name not in output_names:  #如果当前值信息名称不在请求的输出名称列表中，跳过后续处理
                continue
            self.model.graph.output.append(x)   #将值信息对象添加到模型的输出中
            self.all_outputs.append(x.name) #将值信息名称添加到需要保留的输出列表
            output_names.remove(x.name) #从请求的输出名称列表中移除已处理的名称
        # node map name
        self.all_nodes = {} #初始化一个空字典 self.all_nodes，用于存储节点映射（输出名称 → 节点）
        for x in self.model.graph.node: #遍历模型的所有节点
            for o in x.output:  #遍历当前节点的所有输出名称
                self.all_nodes[o] = x   #将输出名称映射到节点对象，存入 self.all_nodes
                if o in output_names:   #如果输出名称在请求的输出名称列表中
                    intermediate_layer_value_info = onnx.helper.ValueInfoProto()    #创建一个新的值信息原型对象
                    intermediate_layer_value_info.name = o  #设置值信息的名称为当前输出名称
                    self.model.graph.output.append(intermediate_layer_value_info)   #将新创建的值信息添加到模型的输出中
                    output_names.remove(o)  #从请求的输出名称列表中移除已处理的名称
                    self.all_outputs.append(o)  #将输出名称添加到需要保留的输出列表
        if len(output_names) != 0:  #如果请求的输出名称列表中仍有未处理的名称，抛出运行时错误
            raise RuntimeError("Error, can't find {} in model".format(output_names))
        # weight map name
        self.all_weights = {}   #初始化一个空字典 self.all_weights，用于存储权重映射
        for w in self.model.graph.initializer: #遍历模型的所有初始权重，将权重名称映射到权重对象，存入 self.all_weights
            self.all_weights[w.name] = w
        # remove unused node
        self.select_unuse(self.all_outputs) #调用 select_unuse 方法，从需要保留的输出开始，递归标记和移除未使用的元素
        for n in self.all_nodes.values():   #遍历节点字典中的所有节点对象
            if n in self.model.graph.node:  #如果节点仍在模型的节点列表中，则从模型中移除该节点
                self.model.graph.node.remove(n)
        for w in self.all_weights.values(): #遍历权重字典中的所有权重对象，并从模型的初始权重列表中移除它们
            self.model.graph.initializer.remove(w)
        for i in self.all_inputs.values():  #遍历输入字典中的所有输入对象，并从模型的输入列表中移除它们
            self.model.graph.input.remove(i)
        for v in self.all_values.values():  #遍历值信息字典中的所有值信息对象，并从模型的值信息列表中移除它们
            self.model.graph.value_info.remove(v)
        unuse_output = []   #初始化一个空列表 unuse_output，用于存储未使用的输出
        for o in self.model.graph.output:   #遍历模型的所有输出
            if o.name not in self.all_outputs:  #如果输出名称不在需要保留的输出列表中，将该输出添加到未使用输出列表
                unuse_output.append(o)
        for o in unuse_output:  #遍历未使用输出列表，并从模型的输出列表中移除这些输出
            self.model.graph.output.remove(o)

    def get_value_info(self, name): #通过名称查找并返回模型中的值信息（ValueInfoProto）对象
        for x in self.model.graph.value_info:   #遍历模型的所有值信息
            if x.name == name:  #如果找到匹配的值信息对象则返回该对象，否则返回 None
                return x
        return None

    #model.graph.initializer 是一个tensor列表，其中的元素类型为TensorProto。 Initializer通常保存模型的权重参数，一些输入默认值也可以保存在这里，可以将其理解为一个tensor常量池。
    def get_outputs(self, model: onnx.ModelProto):  #获取模型的真正输出（排除权重/常量）    model - ONNX 模型对象（ModelProto）
        initializer_names = [x.name for x in model.graph.initializer]   #创建模型所有权重/常量名称的列表
        return [opt for opt in model.graph.output if opt.name not in initializer_names] #列表推导式：只包含那些名称不在 initializer_names 中的输入对象

    #返回过滤后的输入列表，排除那些实际上是权重的输入
    def get_inputs(self, model: onnx.ModelProto):
        initializer_names = [x.name for x in model.graph.initializer]
        return [ipt for ipt in model.graph.input if ipt.name not in initializer_names]

    def get_input_names(self, model: onnx.ModelProto):  #获取所有真正输入的名称列表
        input_names = [ipt.name for ipt in self.get_inputs(model)]
        return input_names

    def get_input_types(self, model: onnx.ModelProto):
        input_types = []
        for input in self.get_inputs(model):    #遍历所有真正的输入对象，排除权重、常量
            if input.type.tensor_type.elem_type in [onnx.TensorProto.INT64, onnx.TensorProto.INT32]:    #检查输入元素的类型是否为 INT64 或 INT32
                input_types.append('INT32') #如果是 INT64 或 INT32 类型，添加 'INT32' 到类型列表
            else:
                input_types.append('F32')   #如果是其他类型（主要是 FLOAT），添加 'F32' 到类型列表
        return input_types

    def get_output_types(self, model: onnx.ModelProto):
        output_types = []
        for output in self.get_outputs(model):  #遍历所有真正的输出对象，排除权重、常量
            if output.type.tensor_type.elem_type in [
                    onnx.TensorProto.INT64, onnx.TensorProto.INT32
            ]:  #检查输出元素的类型是否为 INT64 或 INT32
                output_types.append('INT32')    #如果是 INT64 或 INT32 类型，添加 'INT32' 到类型列表
            else:
                output_types.append('F32')  #如果是其他类型（主要是 FLOAT），添加 'F32' 到类型列表
        return output_types

    def get_shape_from_value_info_proto(self, v: onnx.ValueInfoProto):  #从 ValueInfoProto 对象中提取形状信息并返回
        return [dim.dim_value for dim in v.type.tensor_type.shape.dim]  #列表推导式：提取所有维度的具体值

    def get_input_shapes(self, model: onnx.ModelProto): #返回所有输入形状的列表
        inputs = self.get_inputs(model) #遍历所有真正的输入对象，排除权重、常量
        return [self.get_shape_from_value_info_proto(i) for i in inputs]    #遍历所有真正的输入对象，并调用方法返回维度信息

    def get_loc(self, names):
        if isinstance(names, str):  #判断names是不是单字符串，如果是，创建一个基于该名称的位置对象
            return Location.fused([Location.name(names)], context=self.mlir.ctx)    #Location.name(names): 创建一个基于名称的位置对象   Location.fused([...]): 创建一个融合位置，即使只有一个位置也使用融合形式
        elif isinstance(names, list):   #判断names是不是列表，如果是，为每个名称创建位置对象，然后融合它们
            return Location.fused([Location.name(n) for n in names], context=self.mlir.ctx)
        else:   #如果 names 既不是字符串也不是列表，抛出运行时错误
            raise RuntimeError("Unknown names:{}".format(names))

    def is_dynamic(self):
        return self.run_mode == "DYNAMIC"   #返回一个布尔值，表示当前是否处于动态模式

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

    def find_named_tensor(self, name):  #定义名为 find_named_tensor 的方法，用于查找指定名称的张量
        for tensor in self.model.graph.initializer: #遍历模型中的所有初始权重/常量张量
            if name == tensor.name:     #检查当前权重张量的名称是否与目标名称匹配
                #numpy_helper.to_array(tensor): ONNX 工具函数，将 TensorProto 转换为 NumPy 数组 .astype(np.float32): 将数组元素类型转换为 float32
                return numpy_helper.to_array(tensor).astype(np.float32) #如果找到匹配的权重张量，将其转换为 NumPy 数组并转换为 float32 类型
        if self.subgraph_initializer is not None:   #检查是否存在子图初始化器（用于控制流操作） self.subgraph_initializer - 子图初始化器列表，可能为 None
            for tensor in self.subgraph_initializer:
                if name == tensor.name: #如果在子图初始化器中找到匹配的张量，同样转换为 NumPy 数组并返回
                    return numpy_helper.to_array(tensor).astype(np.float32)
        for node in self.converted_nodes:   #遍历所有已转换的节点
            if node.op_type != "Constant":  #跳过不是 "Constant" 类型的节点
                #这里是因为对于已转换的节点，只有"Constant"类型的节点才会在属性中存储具体的张量值（通过'value'属性）。其他类型的节点（如Conv、Relu等）的输出张量是在运行时计算得到的，并不在节点属性中存储具体数值，因此无法直接提取。
                continue
            if node.name == name:   #检查常量节点的名称是否与目标名称匹配
                onnx_tensor = node.attrs['value']   #从节点属性中获取常量值
                return numpy_helper.to_array(onnx_tensor)   #将 ONNX 张量对象转换为 NumPy 数组并返回

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

    def get_output_name(self, graph):   #定义名为 get_output_name 的方法，用于从计算图中提取非权重的输出名称
        for output in graph.output: #遍历计算图的所有输出
            if not self.isWeight(output.name):  #检查输出名称是否不是权重名称，只有不是权重的输出才被认为是模型的真正输出
                self.output_names.append(output.name)   #将非权重的输出名称添加到输出名称列表

    def addDynamicShape(self, name, shape):
        if len(shape) == 0: #如果形状为空，设置为默认形状 [1]，确保形状至少有一个维度
            shape = [1]
        if isinstance(shape, tuple):    #如果是元组，则转换为列表
            shape = list(shape)
        elif not isinstance(shape, list):   #如果形状既不是列表也不是元组，抛出错误，确保形状是已知的格式
            raise KeyError("{}:{} unknown shape".format(name, shape))
        if name in self.shapes: #检查形状是否冲突,检查name是否在self.shape里
            if self.shapes[name] != shape:  #如果同一个名称已经有形状信息，且与新形状不同，抛出冲突错误
                raise KeyError("shape {} conflict {} vs {}".format(name, self.shapes[name], shape))
        self.dynamic_shapes[name] = shape   #将形状信息添加到动态形状字典

    def getDynamicShape(self, name):    #定义获取动态形状的方法
        if name not in self.dynamic_shapes: #检查名称是否在动态形状字典中，如果不存在，记录警告并返回 None
            logger.warning("shape {} not found in dynamic_shapes".format(name))
            return None
        return self.dynamic_shapes[name]    #返回指定名称的形状信息



    """
    get_dynamic_op_shape 方法的主要目的是处理那些输出形状在静态分析阶段无法确定的操作（如 RandomNormalLike）。它通过以下步骤实现：

    识别动态操作: 遍历模型中的所有节点，找到需要动态形状处理的操作

    临时修改输出: 将这些动态操作的输出临时添加到模型的输出列表中

    运行模型: 使用 ONNX Runtime 实际运行模型，获取动态操作的输出形状

    处理大模型: 特别处理超过 2GB 限制的大模型，使用临时文件和外部数据存储

    记录形状信息: 将获取到的形状信息存储在动态形状字典中

    恢复原始输出: 恢复模型的原始输出设置

    这种方法确保了即使对于输出形状在编译时无法确定的操作，转换器也能通过实际运行模型来获取准确的形状信息，为后续的 MLIR 转换提供必要的基础数据。
    """
    def get_dynamic_op_shape(self, model):  #定义获取动态操作形状的方法
        dynamic_op = ["RandomNormalLike"]   #定义需要特殊处理的动态操作列表
        ori_outputs = []    #定义并保存原始输出列表
        ori_outputs.extend(model.graph.output)
        del self.model.graph.output[:]  #清空模型的输出列表，为临时添加动态操作的输出做准备
        for node in model.graph.node:   #遍历所有节点，找到动态操作并将其输出添加到模型输出中
            if node.op_type in dynamic_op:  #检查节点类型是否在动态操作列表中
                for output in node.output:  #对于动态操作的每个输出，如果不是权重，则添加到模型输出中，确保只处理非权重的输出
                    if not self.isWeight(output):
                        model.graph.output.extend([onnx.ValueInfoProto(name=output)])
        if model.graph.output:  #检查是否有动态操作的输出需要处理
            ort_inputs = {} #初始化一个空字典，用于存储 ONNX Runtime 的输入数据
            test_file = ''  #初始化测试文件路径变量
            if isinstance(self.test_input, list):   #检查 self.test_input 是否为列表类型
                assert self.test_input[0].endswith('.npz')  #断言列表中的第一个元素以 '.npz' 结尾，确保测试数据文件是 NPZ 格式
                test_file = self.test_input[0]  #将列表中的第一个元素赋值给 test_file
            elif isinstance(self.test_input, str):  # 检查 self.test_input 是否为字符串类型
                assert self.test_input.endswith('.npz') #断言字符串以 '.npz' 结尾
                test_file = self.test_input #将字符串直接赋值给 test_file
            else:   #如果 self.test_input 既不是列表也不是字符串，抛出值错误，说明在转换动态形状模型时需要 NPZ 格式的测试输入文件
                raise ValueError(
                    "test_input npz file is necessary when transform dynamic shape model")
            test_data = np.load(test_file)  # 加载测试数据文件
            for i in test_data.files:   #遍历测试数据文件中的所有键
                ort_inputs[i] = test_data[i]    #将测试数据添加到输入字典中
            try:
                try:    #尝试创建 ONNX Runtime 推理会话 model.SerializeToString() - 将 ONNX 模型序列化为字符串      rt.InferenceSession() - 创建 ONNX Runtime 推理会话
                    ort_session = rt.InferenceSession(model.SerializeToString())
                except Exception as E:  #捕获创建会话时可能出现的异常
                    if "Message onnx.ModelProto exceeds maximum protobuf size of 2GB" in str(E):    #检查异常信息是否包含模型超过 2GB 限制的消息
                        print("LOG: Try to convert through a temporary file when Constant Folding.")    #打印日志信息，说明将尝试通过临时文件进行转换
                        # large models try to convert through a temporary file
                        import os   #操作系统接口模块
                        import tempfile #临时文件和目录管理模块
                        with tempfile.TemporaryDirectory() as tmpdirname:   #创建临时目录，并在退出 with 块时自动清理
                            model_path = os.path.join(tmpdirname, 'dynamic_model.onnx') #创建模型文件路径
                            onnx.save(model,    #保存模型到临时文件，使用外部数据存储
                                      model_path,
                                      save_as_external_data=True,
                                      location="temp_external_data",
                                      convert_attribute=True)
                            ort_session = rt.InferenceSession(model.SerializeToString())    #再次尝试创建 ONNX Runtime 推理会话
                    else:
                        raise E #如果不是模型大小超过限制的错误，重新抛出异常
            except ValueError:  #捕获值错误异常，记录警告信息       如果创建 ONNX Runtime 会话失败，记录警告但不中断程序
                logger.warning(
                    "onnxruntime.InferenceSession error when getting dynamic output shape.")

            # ort_session = rt.InferenceSession(model.SerializeToString())
            outputs = [x.name for x in ort_session.get_outputs()]   #获取会话的输出名称列表
            ort_outs = ort_session.run(outputs, ort_inputs)     #运行模型，获取输出结果
            ort_outs_shape = [x.shape for x in ort_outs]        #提取所有输出的形状信息
            for i, output in enumerate(outputs):    #遍历所有输出名称和对应的形状       enumerate() - 同时获取索引和值
                self.addDynamicShape(output, ort_outs_shape[i]) #将输出形状添加到动态形状字典中
            del self.model.graph.output[:]  #清空模型的输出列表（移除临时添加的动态操作输出）
        model.graph.output.extend(ori_outputs)  #恢复模型的原始输出

    def dynamic_input_names_auto_assign(self):  #定义自动分配动态输入名称的方法
        if self.dynamic != "auto":  #检查是否处于自动动态模式
            return  #如果不是自动模式，直接返回，不执行后续操作
        inputs = self.get_inputs(self.model)    #获取模型的真正输入（排除权重）
        for idx, input in enumerate(inputs):    #遍历所有输入对象
            _dims = input.type.tensor_type.shape.dim    #获取输入张量的维度信息
            if _dims:
                if len(_dims) == 1: #如果只有一个维度，将输入名称添加到形状影响输入列表
                    self.shape_influencing_input_names.append(input.name)
                for _i, _dim in enumerate(_dims):   #遍历所有维度
                    if _dim.dim_value == 0 and _dim.dim_param:  #检查维度值是否为 0 且存在维度参数
                        self.dynamic_shape_input_names.append(input.name)   #将输入名称添加到动态形状输入列表，并跳出循环
                        break

    def input_shape_assign(self, input_shapes): #定义输入形状分配方法
        inputs = self.get_inputs(self.model)    #获取模型的输入和输出对象列表
        outputs = self.get_outputs(self.model)
        shape_changed = False   #初始化标志变量
        no_shape = True

        def check_shape(l, r):  #定义内部函数，用于检查形状一致性
            if no_shape == False and l != r:    #如果有形状且l与r不相同，抛出错误
                raise KeyError("input shapes error:{}, {} vs {}".format(input_shapes, l, r))

        if len(input_shapes) > 0:
            no_shape = False
            check_shape(self.num_input, len(input_shapes))   #检查输入形状数量是否与模型输入数量一致
        for idx, input in enumerate(inputs):    #遍历所有输入
            _dims = input.type.tensor_type.shape.dim    #获取输入张量的维度信息
            # for 1-element scalars that has no shape, assign [1] as shape to convert to tensor 
            if not _dims:   #处理没有形状信息的标量输入，为其分配形状 [1]
                _dims.append(onnx.TensorShapeProto.Dimension(dim_value=1))
            num_dims = len(_dims)
            if no_shape == False:
                check_shape(num_dims, len(input_shapes[idx]))   #检查输入维度数量是否与提供的形状一致
            _shape = [] #初始化形状列表
            for _i, _dim in enumerate(_dims):   #遍历所有维度
                if _dim.dim_value <= 0: #处理动态维度（值小于等于 0）
                    if no_shape:    #如果没有提供形状信息，抛出错误
                        assert 0, "Please check --input_shapes formula or check if there is any dynamic dim"
                    else:   #如果提供了形状信息，使用提供的形状值
                        _dim.dim_value = input_shapes[idx][_i]
                # elif not no_shape:
                #     check_shape(_dim_value, input_shapes)
                elif not no_shape and input_shapes[idx][_i] != _dim.dim_value:  #如果提供了形状信息且与当前维度值不匹配，更新维度值并设置形状改变标志
                    _dim.dim_value = input_shapes[idx][_i]
                    shape_changed = True
                _shape.append(_dim.dim_value)   #将维度值添加到形状列表
            self.addShape(input.name, _shape)   #将形状信息添加到形状字典
        idx = 0  # avoid confilict for multi dynamic axes   初始化索引，避免多个动态轴的冲突
        for o in outputs:   #遍历所有输出对象
            # for set arbitrary axes
            _odims = o.type.tensor_type.shape.dim   #获取输出张量的维度信息
            for _odim in _odims:    #遍历所有输出维度
                if _odim.dim_value <= 0 or shape_changed:   #如果维度值小于等于 0 或形状已改变，设置维度参数并增加索引
                    _odim.dim_param = '?_' + str(idx)
                    idx += 1

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

    def get_shape_for_node(self, input, output, value_info, name):
        for i in value_info:    #在值信息中查找指定名称的节点
            if i.name == name:
                return i.type.tensor_type.shape.dim #返回该节点的张量形状维度信息
        for i in input: #在输入节点中查找指定名称的节点
            if i.name == name:
                return i.type.tensor_type.shape.dim #返回该节点的张量形状维度信息
        for i in output:    #在输出节点中查找指定名称的节点
            if i.name == name:
                return i.type.tensor_type.shape.dim #返回该节点的张量形状维度信息

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

    def convert_skip_op(self, onnx_node):
        op = self.getOperand(onnx_node.inputs[0])
        self.addOperand(onnx_node.name, op)
    #具体算子部分未注释，遇到时可以查找
    def convert_add_op(self, onnx_node):
        assert (onnx_node.op_type == "Add")
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        if self.isWeight(lhs) and not self.isWeight(rhs):
            onnx_node.inputs[0], onnx_node.inputs[1] = onnx_node.inputs[1], onnx_node.inputs[0]
            self.convert_add_op(onnx_node)
            return
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        lhs_op = self.getOp(lhs)
        rhs_op = self.getOp(rhs)
        new_op = top.AddOp(self.unranked_type, [lhs_op, rhs_op],
                           loc=self.get_loc(name),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_sub_op(self, onnx_node):
        assert (onnx_node.op_type == "Sub")
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        new_op = None
        if self.isScalar(lhs):
            # lhs_const + (-1 * rhs)
            rhs_op = self.getOp(rhs)
            new_op = top.SubConstOp(self.unranked_type,
                                    rhs_op,
                                    const_val=self.getScalar(lhs),
                                    loc=self.get_loc(name),
                                    is_reverse=True,
                                    ip=self.mlir.insert_point).output
        elif self.isScalar(rhs):
            # lhs + (-rhs_const)
            lhs_op = self.getOp(lhs)
            new_op = top.AddConstOp(self.unranked_type,
                                    lhs_op,
                                    const_val=-self.getScalar(rhs),
                                    loc=self.get_loc(name),
                                    ip=self.mlir.insert_point).output
        else:
            lhs_op = self.getOp(lhs)
            rhs_op = self.getOp(rhs)
            new_op = top.SubOp(self.unranked_type, [lhs_op, rhs_op],
                               loc=self.get_loc(name),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_batchnorm_op(self, onnx_node):
        assert (onnx_node.op_type == "BatchNormalization")
        op = self.getOperand(onnx_node.inputs[0])
        gamma = self.getWeightOp(onnx_node.inputs[1])
        beta = self.getWeightOp(onnx_node.inputs[2])
        mean = self.getWeightOp(onnx_node.inputs[3])
        variance = self.getWeightOp(onnx_node.inputs[4])
        epsilon = onnx_node.attrs.get("epsilon")
        new_op = top.BatchNormOp(self.unranked_type,
                                 op,
                                 mean,
                                 variance,
                                 gamma,
                                 beta,
                                 epsilon=epsilon,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_cast_op(self, onnx_node):
        assert (onnx_node.op_type == "Cast")
        if self.isWeight(onnx_node.inputs[0]):
            data = self.getWeight(onnx_node.inputs[0])
            self.addWeight(onnx_node.name, data)
        else:
            op = self.getOperand(onnx_node.inputs[0])
            self.addOperand(onnx_node.name, op)

    def convert_ceil_op(self, onnx_node):
        assert (onnx_node.op_type == "Ceil")
        op = self.getOp(onnx_node.inputs[0])
        new_op = top.CeilOp(self.unranked_type,
                            op,
                            loc=self.get_loc(onnx_node.name),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_concat_op(self, onnx_node):
        assert (onnx_node.op_type == "Concat")
        axis = onnx_node.attrs['axis']
        operands = list()
        weight_data = None
        last_name = None
        for x in onnx_node.inputs:
            if self.isWeight(x):
                data = self.getWeight(x).copy()
                data[data == int64_max] = int32_max - 1024
                if len(data.shape) == 1 and data.shape[0] == 0:
                    continue
                if weight_data is not None:
                    weight_data = np.concatenate((weight_data, data), axis=axis)
                    last_name = "{}_{}".format(last_name, x)
                else:
                    weight_data = data
                    last_name = x
                continue
            else:
                if weight_data is not None:
                    if last_name in self.tensors:
                        w_name = last_name + "_" + onnx_node.name + "_weight"
                    else:
                        w_name = last_name + "_weight"
                    self.addWeight(w_name, weight_data)
                    operands.append(self.getWeightOp(w_name))
                    weight_data = None
                operands.append(self.getOperand(x))
        if len(operands) == 0:
            # all weight
            self.addWeight(onnx_node.name, weight_data)
            return
        if weight_data is not None:
            w_name = onnx_node.name + "_weight"
            self.addWeight(w_name, weight_data)
            operands.append(self.getWeightOp(w_name))
        if len(operands) == 1:
            self.addOperand(onnx_node.name, operands[0])
            return
        new_op = top.ConcatOp(self.unranked_type,
                              operands,
                              axis=axis,
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_constant_op(self, onnx_node):
        """
            Constant Op is tensor data at IR,
            we change it to load weight tensor, and store
        """
        assert (onnx_node.op_type == "Constant")
        onnx_tensor = onnx_node.attrs['value']
        np_tensor = numpy_helper.to_array(onnx_tensor)
        self.addWeight(onnx_node.name, np_tensor)

    def convert_constantofshape_op(self, onnx_node):
        """
            Constant Op is tensor data at IR,
            we change it to load weight tensor, and store
        """
        assert (onnx_node.op_type == "ConstantOfShape")
        value = 0
        if 'value' in onnx_node.attrs:
            onnx_tensor = onnx_node.attrs['value']
            np_tensor = numpy_helper.to_array(onnx_tensor)
            assert (np_tensor.size == 1)
            value = np_tensor[0]
        op = self.getOp(onnx_node.inputs[0])
        new_op = top.ConstantFillOp(self.unranked_type,
                                    op,
                                    value=value,
                                    loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                    onnx_node.op_type)),
                                    ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_conv_op(self, onnx_node):
        assert (onnx_node.op_type == "Conv")
        op = self.getOp(onnx_node.inputs[0])  # input can be weight
        kernel_shape = onnx_node.attrs['kernel_shape']
        dim = len(kernel_shape)
        dilations = onnx_node.attrs.get("dilations", dim * [1])
        group = onnx_node.attrs.get("group", 1)
        strides = onnx_node.attrs.get("strides", dim * [1])
        auto_pad = onnx_node.attrs.get("auto_pad", "NOTSET")
        if not isinstance(auto_pad, str):
            auto_pad = auto_pad.decode('utf-8')
        pads = onnx_node.attrs.get("pads", dim * 2 * [0])
        operands = list()
        operands.append(op)
        # filter may be dynamic weight
        filter_op = self.getOp(onnx_node.inputs[1])
        operands.append(filter_op)
        weight_is_coeff = 1 if self.isWeight(onnx_node.inputs[1]) else 0
        if len(onnx_node.inputs) > 2:
            bias_op = self.getWeightOp(onnx_node.inputs[2])
        else:
            bias_op = self.mlir.none_op
        operands.append(bias_op)
        new_op = top.ConvOp(self.unranked_type,
                            *operands,
                            kernel_shape=kernel_shape,
                            strides=strides,
                            dilations=dilations,
                            auto_pad=StringAttr.get(auto_pad),
                            pads=pads,
                            group=group,
                            weight_is_coeff=weight_is_coeff,
                            do_relu=False,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_correlation_op(self, onnx_node):
        assert (onnx_node.op_type == "Correlation")
        l_op = self.getOperand(onnx_node.inputs[0])
        r_op = self.getOperand(onnx_node.inputs[1])
        max_disp = onnx_node.attrs.get('max_disp', 0)
        num_groups = onnx_node.attrs.get('num_groups', 1)
        new_op = top.CorrelationOp(self.unranked_type, [l_op, r_op],
                                   max_disp=max_disp,
                                   num_groups=num_groups,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_depth2space_op(self, onnx_node):
        assert (onnx_node.op_type == "DepthToSpace")
        op = self.getOperand(onnx_node.inputs[0])
        blocksize = onnx_node.attrs['blocksize']
        mode = onnx_node.attrs.get("mode", b"DCR")
        new_op = top.Depth2SpaceOp(self.unranked_type,
                                   op,
                                   block_h=blocksize,
                                   block_w=blocksize,
                                   is_CRD=(mode != b"DCR"),
                                   is_inversed=False,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_space2depth_op(self, onnx_node):
        assert (onnx_node.op_type == "SpaceToDepth")
        op = self.getOperand(onnx_node.inputs[0])
        blocksize = onnx_node.attrs['blocksize']
        mode = onnx_node.attrs.get("mode", b"DCR")
        new_op = top.Depth2SpaceOp(self.unranked_type,
                                   op,
                                   block_h=blocksize,
                                   block_w=blocksize,
                                   is_CRD=(mode != b"DCR"),
                                   is_inversed=True,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_flatten_op(self, onnx_node):
        assert (onnx_node.op_type == "Flatten")
        op = self.getOperand(onnx_node.inputs[0])
        axis = onnx_node.attrs.get('axis', 1)
        new_op = top.FlattenOp(self.unranked_type,
                               op,
                               start_dim=axis,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_floor_op(self, onnx_node):
        assert (onnx_node.op_type == "Floor")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.FloorOp(self.unranked_type,
                             op,
                             loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_gemm_op(self, onnx_node):
        assert (onnx_node.op_type == "Gemm" or onnx_node.op_type == 'MatMul')
        # (M, K) * (K, N) => (M, N)
        alpha = onnx_node.attrs.get('alpha', 1)
        beta = onnx_node.attrs.get('beta', 1)
        trans_a = onnx_node.attrs.get('transA', 0)
        trans_b = onnx_node.attrs.get('transB', 0)
        # TODO:support more situations
        assert (trans_a == 0)
        operands = list()
        A = onnx_node.inputs[0]
        B = onnx_node.inputs[1]
        if self.isWeight(A):
            if trans_a == 1 or alpha != 1:
                _tensor = self.getWeight(A)
                _tensor = copy.deepcopy(_tensor)  #if change weight,should do deepcopy
                if trans_a == 1:
                    _tensor = np.ascontiguousarray(np.transpose(_tensor, (1, 0)))
                if alpha != 1:
                    _tensor *= alpha
                A += '_fix'
                self.addWeight(A, _tensor)
            operands.append(self.getWeightOp(A))
        else:
            operands.append(self.getOperand(A))

        if self.isWeight(B):
            if trans_b == 1 or alpha != 1:
                _tensor = self.getWeight(B)
                _tensor = copy.deepcopy(_tensor)  #if change weight,should do deepcopy
                if trans_b == 1:
                    _tensor = np.ascontiguousarray(np.transpose(_tensor, (1, 0)))
                if alpha != 1:
                    _tensor *= alpha
                B += '_fix'
                self.addWeight(B, _tensor)
            operands.append(self.getWeightOp(B))
        else:
            operands.append(self.getOperand(B))
        if len(onnx_node.inputs) > 2 and beta != 0:
            C = onnx_node.inputs[2]
            if self.isWeight(C):
                if beta != 1:
                    _tensor = self.getWeight(C)
                    _tensor = copy.deepcopy(_tensor)  #if change weight,should do deepcopy
                    _tensor *= beta
                    C += '_fix'
                    self.addWeight(C, _tensor)
                operands.append(self.getWeightOp(C))
            else:
                operands.append(self.getOperand(C))
        else:
            operands.append(self.mlir.none_op)

        new_op = top.MatMulOp(self.unranked_type,
                              *operands,
                              do_relu=False,
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_global_maxpool_op(self, onnx_node):
        assert (onnx_node.op_type == "GlobalMaxPool")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.MaxPoolOp(self.unranked_type,
                               op,
                               kernel_shape=[],
                               strides=[],
                               pads=[],
                               count_include_pad=True,
                               do_relu=False,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_global_avgpool_op(self, onnx_node):
        assert (onnx_node.op_type == "GlobalAveragePool")
        op = self.getOperand(onnx_node.inputs[0])
        # check onnx define
        new_op = top.AvgPoolOp(self.unranked_type,
                               op,
                               kernel_shape=[],
                               strides=[],
                               pads=[],
                               count_include_pad=True,
                               do_relu=False,
                               keepdims=True,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_avgpool_op(self, onnx_node):
        assert (onnx_node.op_type == "AveragePool")
        op = self.getOperand(onnx_node.inputs[0])
        ceil_mode = onnx_node.attrs.get("ceil_mode", False)
        kernel_shape = onnx_node.attrs['kernel_shape']
        count_include_pad = onnx_node.attrs.get('count_include_pad', False)
        dim = len(kernel_shape)
        strides = onnx_node.attrs.get("strides", kernel_shape)
        auto_pad = onnx_node.attrs.get("auto_pad", b"NOTSET")
        pads = onnx_node.attrs.get("pads", dim * 2 * [0])
        if np.prod(kernel_shape) == 1 and np.sum(pads) == 0 and np.prod(strides) == 1:
            self.addOperand(onnx_node.name, op)
            return
        new_op = top.AvgPoolOp(self.unranked_type,
                               op,
                               kernel_shape=kernel_shape,
                               strides=strides,
                               pads=pads,
                               auto_pad=StringAttr.get(auto_pad),
                               ceil_mode=ceil_mode,
                               count_include_pad=count_include_pad,
                               do_relu=False,
                               keepdims=True,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_maxpool_op(self, onnx_node):
        assert (onnx_node.op_type == "MaxPool")
        op = self.getOperand(onnx_node.inputs[0])
        ceil_mode = onnx_node.attrs.get("ceil_mode", False)
        kernel_shape = onnx_node.attrs['kernel_shape']
        count_include_pad = onnx_node.attrs.get('count_include_pad', False)
        dim = len(kernel_shape)
        strides = onnx_node.attrs.get("strides", kernel_shape)
        auto_pad = onnx_node.attrs.get("auto_pad", b"NOTSET")
        pads = onnx_node.attrs.get("pads", dim * 2 * [0])
        new_op = top.MaxPoolOp(self.unranked_type,
                               op,
                               kernel_shape=kernel_shape,
                               strides=strides,
                               pads=pads,
                               auto_pad=StringAttr.get(auto_pad),
                               ceil_mode=ceil_mode,
                               count_include_pad=count_include_pad,
                               do_relu=False,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_mul_op(self, onnx_node):
        assert (onnx_node.op_type == "Mul")
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        if self.isWeight(lhs) and not self.isWeight(rhs):
            onnx_node.inputs[0], onnx_node.inputs[1] = rhs, lhs
            self.convert_mul_op(onnx_node)
            return
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        op0 = self.getOp(lhs)
        op1 = self.getOp(rhs)
        mul_op = top.MulOp(self.unranked_type, [op0, op1],
                           loc=self.get_loc(name),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, mul_op)
        return

    def convert_dropout_op(self, onnx_node):
        assert (onnx_node.op_type == "Dropout")
        op = self.getOperand(onnx_node.inputs[0])
        self.addOperand(onnx_node.name, op)

    def convert_relu_op(self, onnx_node):
        assert (onnx_node.op_type == "Relu")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.ReluOp(self.unranked_type,
                            op,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_leaky_relu_op(self, onnx_node):
        assert (onnx_node.op_type == "LeakyRelu")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.LeakyReluOp(self.unranked_type,
                                 op,
                                 alpha=onnx_node.attrs.get("alpha", 0.),
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_reshape_op(self, onnx_node):
        assert (onnx_node.op_type == "Reshape")
        op = self.getOperand(onnx_node.inputs[0])
        if self.isWeight(onnx_node.inputs[1]):
            shape = self.getWeight(onnx_node.inputs[1])
            new_op = top.ReshapeOp(self.unranked_type,
                                   op,
                                   shape=shape,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        else:
            shape = self.getOperand(onnx_node.inputs[1])
            new_op = top.ReshapeOp(self.unranked_type,
                                   op,
                                   shapeT=shape,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_reverse_sequence_op(self, onnx_node):
        assert (onnx_node.op_type == 'ReverseSequence')
        op = self.getOperand(onnx_node.inputs[0])
        batch_axis = onnx_node.attrs['batch_axis']
        time_axis = onnx_node.attrs['time_axis']
        axis_dict = {'batch_axis': batch_axis, 'time_axis': time_axis}
        assert (sorted(axis_dict.values()) == [0, 1])
        # not suppport length of the sequences each batch equals to time temporarily
        new_op = top.ReverseOp(self.unranked_type,
                               op,
                               axis=time_axis,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    # when resize by linear or nearst, with float scale_h or float scale_w
    def resize_to_interp(self, onnx_node, op, scale_h, scale_w, mode,
                         coordinate_transformation_mode, target_shape):
        new_op = top.InterpOp(self.unranked_type,
                              op,
                              target_shape,
                              scale_h=float(scale_h),
                              scale_w=float(scale_w),
                              mode=StringAttr.get(mode),
                              coord_mode=StringAttr.get(coordinate_transformation_mode),
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_upsample_op(self, onnx_node):
        assert (onnx_node.op_type == "Upsample")
        mode = onnx_node.attrs.get("mode", "nearest")
        op = self.getOperand(onnx_node.inputs[0])
        scale_factor = []
        scale_factor = self.getWeight(onnx_node.inputs[1])
        scale_factor = copy.deepcopy(scale_factor)  #if change it,should do deepcopy first
        if (type(scale_factor) == np.ndarray and len(scale_factor.shape) == 2
                and scale_factor.shape[1] == 1):
            scale_factor = scale_factor.reshape(-1)
        scale_h = scale_factor[2]  # scale [n, c, h, w]
        scale_w = scale_factor[3]
        coord_mode = onnx_node.attrs.get("coordinate_transformation_mode", "half_pixel")
        self.resize_to_interp(onnx_node,
                              op,
                              scale_h,
                              scale_w,
                              mode,
                              coord_mode,
                              target_shape=self.mlir.none_op)
        return

    def convert_resize_op(self, onnx_node):
        assert (onnx_node.op_type == "Resize")
        mode = onnx_node.attrs.get("mode", "nearest")

        op = self.getOp(onnx_node.inputs[0])
        scale_factor = []
        sizes = []
        use_size = False
        target_shape = self.mlir.none_op
        if len(onnx_node.inputs) > 2:
            # onnx opset 11
            try:
                scale_factor = self.getWeight(onnx_node.inputs[2])
                scale_factor = copy.deepcopy(scale_factor)  #if change it,should do deepcopy first
            except KeyError:
                scale_factor = []
            if (type(scale_factor) == np.ndarray and len(scale_factor.shape) == 2
                    and scale_factor.shape[1] == 1):
                dims = scale_factor.shape[0]
                scale_factor = scale_factor.reshape(dims)
            if len(scale_factor) == 0:
                try:
                    sizes = self.getWeight(onnx_node.inputs[3])
                    assert (len(sizes) >= 2)
                    scale_factor = sizes
                    use_size = True
                except KeyError:
                    sizes = self.getOp(onnx_node.inputs[3])
                    use_size = True
        else:
            # opset 10
            scale_factor = self.getWeight(onnx_node.inputs[1])

        if (use_size):
            scale_d, scale_h, scale_w = -1, -1, -1
            if len(scale_factor) == 0:
                target_shape = sizes
            else:
                self.addWeight(onnx_node.name + "_target_shape",
                               np.array(scale_factor[2:], dtype=np.int64))
                target_shape = self.getWeightOp(onnx_node.name + "_target_shape")
        else:
            scale_d = -1 if len(scale_factor) <= 4 else scale_factor[-3]
            scale_h = -1 if len(scale_factor) <= 3 else scale_factor[-2]
            scale_w = scale_factor[-1]
            if scale_h == 1.0 and scale_w == 1.0:
                self.addOperand(onnx_node.name, op)
                return

        coord_mode = onnx_node.attrs.get("coordinate_transformation_mode", "half_pixel")
        if coord_mode == b'tf_half_pixel_for_nn':  # different mode name in tf and pyt
            coord_mode = 'half_pixel'
        if mode == b'cubic':
            logging.warning("Not Support Resize Cubic !!!! Using Linear Instead !!!!!")
            time.sleep(3)
            mode = b'linear'
        self.resize_to_interp(onnx_node,
                              op,
                              scale_h,
                              scale_w,
                              mode,
                              coord_mode,
                              target_shape=target_shape)

    def convert_shape_op(self, onnx_node):
        assert (onnx_node.op_type == "Shape")
        input = onnx_node.inputs[0]
        start = onnx_node.attrs.get("start", 0)
        end = onnx_node.attrs.get("end", sys.maxsize)
        op = self.getOp(input)
        final_name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        new_op = top.ShapeOp(self.unranked_type,
                             op,
                             start=start,
                             end=end,
                             loc=self.get_loc(final_name),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_random_normal_op(self, onnx_node):
        assert (onnx_node.op_type == "RandomNormalLike")
        input = self.getOp(onnx_node.inputs[0])
        weight_shape = self.getDynamicShape(onnx_node.name)
        weight = np.random.randn(*weight_shape).astype(np.float32)
        weight_name = onnx_node.name + "_weight"
        self.addWeight(weight_name, weight)
        randn_data = self.getWeightOp(weight_name)

        randn_like_op = top.RandnLikeOp(self.unranked_type,
                                        input,
                                        randn_data,
                                        loc=self.get_loc("{}_{}".format(
                                            onnx_node.name, onnx_node.op_type)),
                                        ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, randn_like_op)

    def convert_range_op(self, onnx_node):
        assert (onnx_node.op_type == "Range")
        output_shape = None
        if self.op_custom_shape is None:
            self.op_custom_shape = {}
        range_custom_shape = self.op_custom_shape.get('Range', {})
        if onnx_node.name in range_custom_shape:
            output_len = range_custom_shape[onnx_node.name]
            if isinstance(output_len, int):
                output_shape = [output_len]
                print("[OnnxConver] Get custom shape for RangeOp \"{}\": {}".format(
                    onnx_node.name, output_shape))
            elif isinstance(output_len, list):
                output_shape = output_len
                print("[OnnxConver] Get custom shape for RangeOp \"{}\": {}".format(
                    onnx_node.name, output_shape))
            else:
                raise ValueError("op_custom_shape should be int or list, get {}".format(output_len))
        start = self.getOp(onnx_node.inputs[0])
        limit = self.getOp(onnx_node.inputs[1])
        delta = self.getOp(onnx_node.inputs[2])
        if output_shape is None:
            range_op = top.RangeOp(self.unranked_type,
                                   start,
                                   limit,
                                   delta,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        else:
            range_op = top.RangeOp(self.mlir.get_tensor_type(output_shape),
                                   start,
                                   limit,
                                   delta,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, range_op)

    def convert_selective_scan(self, onnx_node):
        assert (onnx_node.op_type == "SelectiveScan")
        Cs = self.getOp(onnx_node.inputs[0])
        DeltaA = self.getOp(onnx_node.inputs[1])
        DeltaB_u = self.getOp(onnx_node.inputs[2])
        us = self.getOp(onnx_node.inputs[3])
        Ds = self.getOp(onnx_node.inputs[4])

        operands = list()
        operands.append(Cs)
        operands.append(DeltaA)
        operands.append(DeltaB_u)
        operands.append(us)
        operands.append(Ds)

        ss2d_op = top.SelectiveScanOp(self.unranked_type,
                                      *operands,
                                      loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                      onnx_node.op_type)),
                                      ip=self.mlir.insert_point).output

        self.addOperand(onnx_node.name, ss2d_op)

    def convert_sigmoid_op(self, onnx_node):
        assert (onnx_node.op_type == "Sigmoid")
        op = self.getOperand(onnx_node.inputs[0])
        scale = onnx_node.attrs.get('scale', 1)
        bias = onnx_node.attrs.get('bias', 0)
        new_op = top.SigmoidOp(self.unranked_type,
                               op,
                               scale=scale,
                               bias=bias,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_sign_op(self, onnx_node):
        assert (onnx_node.op_type == "Sign")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.SignOp(self.unranked_type,
                            op,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_sin_op(self, onnx_node):
        assert (onnx_node.op_type == "Sin")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.SinOp(self.unranked_type,
                           op,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_cos_op(self, onnx_node):
        assert (onnx_node.op_type == "Cos")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.CosOp(self.unranked_type,
                           op,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_slice_op(self, onnx_node):

        def try_get_slice_input(node, i, attr):
            is_const = self.isWeight(node.inputs[i])
            ret_list = []
            ret_op = self.mlir.none_op
            if is_const:
                ret_list = self.getWeight(node.inputs[i])
                ret_list[ret_list == int64_max] = int32_max - 1024
                ret_op = self.getWeightOp(node.inputs[i])
            elif attr in node.attrs:
                ret_list = node.attrs.get(attr)
                is_const = True
            else:
                ret_op = self.getOperand(node.inputs[i])
            return ret_list, ret_op, is_const

        assert (onnx_node.op_type == "Slice")
        starts = []
        ends = []
        axes = []
        steps = [1]
        num_input = len(onnx_node.inputs)
        if num_input > 1:
            op = self.getOperand(onnx_node.inputs[0]) if not self.isWeight(onnx_node.inputs[0]) \
                else self.getWeightOp(onnx_node.inputs[0])
            starts, start_op, starts_is_const = try_get_slice_input(onnx_node, 1, 'starts')
            ends, end_op, ends_is_const = try_get_slice_input(onnx_node, 2, 'ends') \
                if num_input > 2 else (ends, self.mlir.none_op, True)
            axes, axis_op, axes_is_const = try_get_slice_input(onnx_node, 3, 'axes') \
                if num_input > 3 else (list(np.arange(len(ends))), self.mlir.none_op, True)
            steps, step_op, steps_is_const = try_get_slice_input(onnx_node, 4, 'steps') \
                if num_input > 4 else ([1] * len(axes), self.mlir.none_op, True)
            if steps[0] == -1 and starts[0] == -1 and ends == -np.iinfo(
                    np.int64).max and self.isWeight(op):
                in0 = op
                indices_op_name = 'indices_' + onnx_node.inputs[0]
                extra_attr = {}
                dim_length = self.getWeight(onnx_node.inputs[axes])
                np_tensor = np.arange(dim_length, -1, -1, dtype=np.int64)
                self.addWeight(indices_op_name, np_tensor)
                indices_op = self.getWeightOp(indices_op_name)
                extra_attr.update({"keepdims": True})
                indices = indices_op
                new_op = top.GatherOp(self.unranked_type,
                                      in0,
                                      indices,
                                      axis=axes,
                                      **extra_attr,
                                      loc=self.get_loc("{}_{}".format(onnx_node.name, 'Gather')),
                                      ip=self.mlir.insert_point).output
                self.addOperand(onnx_node.name, new_op)
                return

            ends = list(
                map(lambda x: np.iinfo(np.int64).max if x >= np.iinfo(np.int64).max else x, ends))
            if not (starts_is_const * ends_is_const * axes_is_const * steps_is_const):
                new_op = top.SliceAxisOp(self.unranked_type,
                                         op,
                                         axis_op,
                                         start_op,
                                         step_op,
                                         end_op,
                                         loc=self.get_loc("{}_{}".format(
                                             onnx_node.name, onnx_node.op_type)),
                                         ip=self.mlir.insert_point).output
                self.addOperand(onnx_node.name, new_op)
                return
        else:
            starts = onnx_node.attrs.get('starts')
            ends = onnx_node.attrs.get('ends')
            axes = onnx_node.attrs.get('axes')
            if axes == None:
                axes_len = len(ends)
                axes = [i for i in range(axes_len)]
            steps = [1] * len(axes)
        assert (len(starts) == len(ends))
        assert (len(axes) == len(ends))
        if self.isWeight(onnx_node.inputs[0]):
            tensor_data = self.getWeight(onnx_node.inputs[0])
            num_dims = len(tensor_data.shape)
            for start, end, axis, step in zip(starts, ends, axes, steps):
                start, end, axis, step = int(start), int(end), int(axis), int(step)
                if axis < 0:
                    axis = axis + num_dims
                s = slice(start, end, step)
                tensor_data = tensor_data[(slice(None), ) * axis + (s, )]
            self.addWeight(onnx_node.name, tensor_data)
            return
        if axes != []:

            def is_sorted(arr):
                for i in range(len(arr) - 1):
                    if arr[i] > arr[i + 1]:
                        return False
                return True

            if not is_sorted(axes):
                indexed_axes = list(enumerate(axes))
                sorted_indexed_axes = sorted(indexed_axes, key=lambda x: x[1])

                axes = [x[1] for x in sorted_indexed_axes]
                original_indices = [x[0] for x in sorted_indexed_axes]

                starts = [starts[i] for i in original_indices]
                ends = [ends[i] for i in original_indices]
                steps = [steps[i] for i in original_indices]

        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.SliceOp(self.unranked_type,
                             op,
                             self.mlir.none_op,
                             self.mlir.none_op,
                             self.mlir.none_op,
                             offset=list(starts),
                             steps=list(steps),
                             ends=list(ends),
                             axes=list(axes),
                             loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_transpose_op(self, onnx_node):
        assert (onnx_node.op_type == "Transpose")
        op = self.getOp(onnx_node.inputs[0])
        transpose_perm = onnx_node.attrs.get('perm', [])
        new_op = top.PermuteOp(self.unranked_type,
                               op,
                               order=transpose_perm,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_softmax_op(self, onnx_node):
        assert (onnx_node.op_type in ("Softmax", "LogSoftmax"))
        op = self.getOperand(onnx_node.inputs[0])
        axis_default = -1 if self.opset >= 13 else 1
        axis = onnx_node.attrs.get('axis', axis_default)
        new_op = top.SoftmaxOp(self.unranked_type,
                               op,
                               axis=axis,
                               log=onnx_node.op_type == "LogSoftmax",
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_softplus_op(self, onnx_node):
        assert (onnx_node.op_type == "Softplus")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.SoftplusOp(self.unranked_type,
                                op,
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_log_op(self, onnx_node):
        assert (onnx_node.op_type == "Log")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.LogOp(self.unranked_type,
                           op,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    # https://pytorch.org/docs/1.13/generated/torch.einsum.html?highlight=einsum#torch.einsum
    def convert_einsum_op(self, onnx_node):
        assert (onnx_node.op_type == "Einsum")
        equation = onnx_node.attrs.get("equation").decode()

        def normalize_equation(equation_c):
            equation = equation_c
            new_equation = ''
            start = 'a'
            translate_map = {}
            for s in equation:
                if s == ' ':
                    continue
                elif not ((s >= 'a' and s <= 'z') or (s >= 'A' and s <= 'Z')):
                    translate_map[s] = s
                elif s not in translate_map:
                    translate_map[s] = start
                    start = chr(ord(start) + 1)
                new_equation += translate_map[s]
            return new_equation

        equation = normalize_equation(equation)
        lhs = self.getOp(onnx_node.inputs[0])
        rhs = self.getOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) == 2:
            new_op = top.EinsumOp(self.unranked_type, [lhs, rhs],
                                  mode=StringAttr.get(equation),
                                  loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                  onnx_node.op_type)),
                                  ip=self.mlir.insert_point).output
        elif len(onnx_node.inputs) == 3:
            dhs = self.getOp(onnx_node.inputs[2])
            new_op = top.EinsumOp(self.unranked_type, [lhs, rhs, dhs],
                                  mode=StringAttr.get(equation),
                                  loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                  onnx_node.op_type)),
                                  ip=self.mlir.insert_point).output
        else:
            raise RuntimeError("This mode not support yet: {}".format(mode))
        self.addOperand(onnx_node.name, new_op)

    def convert_exp_op(self, onnx_node):
        assert (onnx_node.op_type == "Exp")
        op = self.getOp(onnx_node.inputs[0])
        new_op = top.ExpOp(self.unranked_type,
                           op,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_elu_op(self, onnx_node):
        assert (onnx_node.op_type == "Elu")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.EluOp(self.unranked_type,
                           op,
                           alpha=onnx_node.attrs.get("alpha", 0.),
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_erf_op(self, onnx_node):
        assert (onnx_node.op_type == "Erf")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.ErfOp(self.unranked_type,
                           op,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_pad_op(self, onnx_node):
        assert (onnx_node.op_type == "Pad")
        op = self.getOp(onnx_node.inputs[0])
        # get pad mode
        mode = onnx_node.attrs.get("mode", "constant")
        if isinstance(mode, bytes):
            mode = mode.decode("utf-8")
        assert (mode in ("constant", "reflect", "edge"))
        pads = None
        padsT = None
        if len(onnx_node.inputs) > 1:
            if self.isWeight(onnx_node.inputs[1]):
                pads = list(self.getWeight(onnx_node.inputs[1]))
            else:
                pads = []
                padsT = self.getOperand(onnx_node.inputs[1])
        else:
            pads = onnx_node.attrs.get("pads")
        if pads == None and padsT == None:
            raise RuntimeError("No paddings value")
        # opset 11, value from second input
        val = 0.0
        if len(onnx_node.inputs) > 2 and onnx_node.inputs[2]:
            val = self.getWeight(onnx_node.inputs[2])
        else:
            val = onnx_node.attrs.get("value", 0.0)

        if padsT:
            new_op = top.PadOp(self.unranked_type,
                               op,
                               paddingsT=padsT,
                               paddings=pads,
                               val=val,
                               mode=StringAttr.get(mode),
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        else:
            new_op = top.PadOp(self.unranked_type,
                               op,
                               paddings=pads,
                               val=val,
                               mode=StringAttr.get(mode),
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_div_op(self, onnx_node):
        assert (onnx_node.op_type == "Div")
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        if self.isScalar(lhs):
            # lhs_const * (1 / rhs)
            rhs_op = self.getOp(rhs)
            new_op = top.ReciprocalOp(self.unranked_type,
                                      rhs_op,
                                      const_val=self.getScalar(lhs),
                                      loc=self.get_loc(name),
                                      ip=self.mlir.insert_point).output
        elif self.isScalar(rhs):
            # lhs * (1 / rhs_const)
            lhs_op = self.getOp(lhs)
            lhs_type = None
            output_type = None
            if self.get_value_info(lhs) != None:
                lhs_type = self.get_value_info(lhs).type.tensor_type.elem_type
            if self.get_value_info(onnx_node.name) != None:
                output_type = self.get_value_info(onnx_node.name).type.tensor_type.elem_type
            need_floor = (output_type in [onnx.TensorProto.INT32, onnx.TensorProto.INT64]) \
                        or (lhs_type in [onnx.TensorProto.INT32, onnx.TensorProto.INT64])

            if self.is_dynamic() and need_floor:
                new_op = top.DivConstOp(self.unranked_type,
                                        lhs_op,
                                        const_val=self.getScalar(rhs),
                                        loc=self.get_loc(name),
                                        ip=self.mlir.insert_point).output
            else:
                new_op = top.MulConstOp(self.unranked_type,
                                        lhs_op,
                                        const_val=1 / self.getScalar(rhs),
                                        loc=self.get_loc(name),
                                        ip=self.mlir.insert_point).output
                if (need_floor):
                    new_op = top.FloorOp(self.unranked_type,
                                         new_op,
                                         loc=self.get_loc(name + '_floor'),
                                         ip=self.mlir.insert_point).output
        else:
            lhs_op = self.getOp(lhs)
            rhs_op = self.getOp(rhs)
            new_op = top.DivOp(self.unranked_type, [lhs_op, rhs_op],
                               loc=self.get_loc(name),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_reciprocal_op(self, onnx_node):
        assert (onnx_node.op_type == "Reciprocal")
        assert len(onnx_node.inputs) == 1
        op0 = self.getOperand(onnx_node.inputs[0])
        div_op = top.ReciprocalOp(self.unranked_type,
                                  op0,
                                  const_val=1,
                                  loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                  onnx_node.op_type)),
                                  ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, div_op)

    def convert_or_op(self, onnx_node):
        assert (onnx_node.op_type == "Or")
        operand0 = self.getOperand(onnx_node.inputs[0])
        operand1 = self.getOperand(onnx_node.inputs[1])
        output_name = "{}_{}".format(onnx_node.name, onnx_node.op_type)

        add_value = top.AddOp(self.unranked_type, [operand0, operand1],
                              loc=self.get_loc(output_name + "_add"),
                              ip=self.mlir.insert_point).output

        new_op = top.CompareConstOp(self.unranked_type,
                                    add_value,
                                    mode=StringAttr.get("Greater"),
                                    const_val=np.array([0]),
                                    inversed=False,
                                    loc=self.get_loc(output_name + "_compare"),
                                    ip=self.mlir.insert_point).output

        self.addOperand(onnx_node.name, new_op)

    def convert_squeeze_op(self, onnx_node):
        assert (onnx_node.op_type == "Squeeze")
        op = self.getOperand(onnx_node.inputs[0])
        axes = []
        if 'axes' in onnx_node.attrs or len(onnx_node.inputs) > 1:
            if self.opset < 13:
                axes = onnx_node.attrs.get('axes')
            else:
                if len(onnx_node.inputs) != 1:
                    axes = self.getWeight(onnx_node.inputs[1]).astype(int)
        new_op = top.SqueezeOp(self.unranked_type,
                               op,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point,
                               axes=axes).output
        self.addOperand(onnx_node.name, new_op)

    def convert_unsqueeze_op(self, onnx_node):
        assert (onnx_node.op_type == "Unsqueeze")
        if self.isWeight(onnx_node.inputs[0]):
            op = self.getWeightOp(onnx_node.inputs[0])
        else:
            op = self.getOperand(onnx_node.inputs[0])
        if self.opset < 13:
            axes = onnx_node.attrs.get('axes')
        else:
            if len(onnx_node.inputs) == 1:
                axes = []
            else:
                axes = self.getWeight(onnx_node.inputs[1]).astype(int)
        new_op = top.UnsqueezeOp(self.unranked_type,
                                 op,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point,
                                 axes=axes).output
        self.addOperand(onnx_node.name, new_op)

    def convert_clip_op(self, onnx_node):
        assert (onnx_node.op_type == "Clip")
        input = self.getOperand(onnx_node.inputs[0])
        if len(onnx_node.inputs) == 3:
            try:
                min = self.getWeight(onnx_node.inputs[1])
            except:
                min = onnx_node.attrs.get('min', -np.inf)
            try:
                max = self.getWeight(onnx_node.inputs[2])
            except:
                max = onnx_node.attrs.get('max', np.inf)
        else:
            min = onnx_node.attrs.get('min', -np.inf)
            max = onnx_node.attrs.get('max', np.inf)
        if min == 0.0 and max > min:
            new_op = top.ReluOp(self.unranked_type,
                                input,
                                relu_limit=max if max != np.inf else 0.0,
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
        else:
            new_op = top.ClipOp(self.unranked_type,
                                input,
                                min=min,
                                max=max,
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_conv_transpose_op(self, onnx_node):
        assert (onnx_node.op_type == "ConvTranspose")
        kernel_shape = onnx_node.attrs['kernel_shape']
        dim = len(kernel_shape)
        dilations = onnx_node.attrs.get('dilations', dim * [1])
        group = onnx_node.attrs.get('group', 1)
        strides = onnx_node.attrs.get('strides', dim * [1])
        pads = onnx_node.attrs.get('pads', dim * 2 * [0])
        output_padding = onnx_node.attrs.get('output_padding', dim * [0])

        operands = list()
        input_opd = self.getOperand(onnx_node.inputs[0])
        weight_name = onnx_node.inputs[1]
        # weight can be dynamic
        if weight_name in self.tensors:
            old_weight = np.ascontiguousarray(self.tensors[weight_name])
            if weight_name not in self.mlir.load_weight:
                if group != 1:
                    # (ic, oc / g, kh, kw) --> (g, oc/g, ic / g, kh, kw) --> (oc / g, ic, kh, kw)
                    _shape = list(old_weight.shape)
                    old_shape = [group, int(_shape[0] / group), _shape[1]] + _shape[2:]
                    new_shape = [_shape[1], _shape[0]] + _shape[2:]
                    old_weight = old_weight.reshape(old_shape)
                    order = [0, 2, 1] + list(range(len(_shape) + 1)[3:])
                    new_weight = np.transpose(old_weight, order).reshape(new_shape)
                    self.tensors[weight_name] = new_weight
                else:
                    # (ic, oc, kh, kw) --> (oc, ic, kh, kw)
                    order = [1, 0] + list(range(len(old_weight.shape))[2:])
                    self.tensors[weight_name] = np.transpose(old_weight, order)

                self.shapes[weight_name] = self.tensors[weight_name].shape

        filter_opd = self.getOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) > 2:
            bias_opd = self.getWeightOp(onnx_node.inputs[2])
        else:
            bias_opd = self.mlir.none_op
        operands.append(input_opd)
        operands.append(filter_opd)
        operands.append(bias_opd)

        new_op = top.DeconvOp(self.unranked_type,
                              *operands,
                              kernel_shape=kernel_shape,
                              strides=strides,
                              dilations=dilations,
                              pads=pads,
                              output_padding=output_padding,
                              group=group,
                              do_relu=False,
                              loc=self.get_loc('{}_{}'.format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_split_op(self, onnx_node):
        assert (onnx_node.op_type == "Split")
        op = self.getOperand(onnx_node.inputs[0])
        num_output = len(onnx_node.outputs)
        axis = onnx_node.attrs['axis']
        split_size = onnx_node.attrs.get('split', None)
        if len(onnx_node.inputs) > 1:
            split_size = self.getWeight(onnx_node.inputs[1]).astype(int)

        loc_names = [n + "_" + onnx_node.op_type for n in onnx_node.outputs]
        new_op = top.SplitOp([self.unranked_type] * num_output,
                             op,
                             axis=axis,
                             num=num_output,
                             split_size=split_size,
                             loc=self.get_loc(loc_names),
                             ip=self.mlir.insert_point).outputs
        for i in range(num_output):
            self.addOperand(onnx_node.outputs[i], new_op[i])

    # support max ndims to 6
    def convert_reduce_op(self, onnx_node):
        assert (onnx_node.op_type in [
            "ReduceMin", "ReduceMax", "ReduceMean", "ReduceProd", "ReduceL2", "ReduceL1",
            "ReduceSum"
        ])
        op = self.getOperand(onnx_node.inputs[0])
        axes = onnx_node.attrs.get('axes', list()) \
            if len(onnx_node.inputs) == 1 else self.getWeight(onnx_node.inputs[1])
        axes = copy.deepcopy(axes)  #if change it, should do deepcopy
        keepdims = onnx_node.attrs.get('keepdims', 1) != 0
        axes.sort()
        new_op = top.ReduceOp(self.unranked_type,
                              op,
                              axes=axes,
                              keepdims=keepdims,
                              mode=StringAttr.get(onnx_node.op_type),
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_reduce_log_sum_exp_op(self, onnx_node):
        assert (onnx_node.op_type == "ReduceLogSumExp")
        op = self.getOperand(onnx_node.inputs[0])
        keepdims = onnx_node.attrs.get('keepdims', 1)
        axes = onnx_node.attrs.get('axes', list())
        output_name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        reducemax_value = top.ReduceOp(self.unranked_type,
                                       op,
                                       axes=axes,
                                       keepdims=1,
                                       mode=StringAttr.get("ReduceMax"),
                                       loc=self.get_loc(output_name + "_reducemax"),
                                       ip=self.mlir.insert_point).output
        sub_value = top.SubOp(self.unranked_type, [op, reducemax_value],
                              loc=self.get_loc(output_name + "_sub"),
                              ip=self.mlir.insert_point).output
        exp_value = top.ExpOp(self.unranked_type,
                              sub_value,
                              loc=self.get_loc(output_name + "_exp"),
                              ip=self.mlir.insert_point).output
        reducesum_value = top.ReduceOp(self.unranked_type,
                                       exp_value,
                                       axes=axes,
                                       keepdims=1,
                                       mode=StringAttr.get("ReduceSum"),
                                       loc=self.get_loc(output_name + "_reducesum"),
                                       ip=self.mlir.insert_point).output
        log_value = top.LogOp(self.unranked_type,
                              reducesum_value,
                              loc=self.get_loc(output_name + "_log"),
                              ip=self.mlir.insert_point).output
        if keepdims:
            new_op = top.AddOp(self.unranked_type, [reducemax_value, log_value],
                               loc=self.get_loc(output_name),
                               ip=self.mlir.insert_point).output
        else:
            add_value = top.AddOp(self.unranked_type, [reducemax_value, log_value],
                                  loc=self.get_loc(output_name + "_add"),
                                  ip=self.mlir.insert_point).output
            new_op = top.SqueezeOp(self.unranked_type,
                                   add_value,
                                   axes=axes,
                                   loc=self.get_loc(output_name),
                                   ip=self.mlir.insert_point).output
            self.addOperand(onnx_node.name, new_op)

    def convert_arg_op(self, onnx_node):
        assert (onnx_node.op_type in ["ArgMin", "ArgMax"])
        op = self.getOperand(onnx_node.inputs[0])
        axis = onnx_node.attrs.get('axis', 0)
        keepdims = onnx_node.attrs.get('keepdims', 1) != 0
        select_last_index = onnx_node.attrs.get('select_last_index', 0) != 0
        loc_names = []
        out_shapes = [None, None]
        out_needs = [False, False]
        for idx, out in enumerate(onnx_node.outputs):
            if len(out) > 0 and self.check_need(out):
                loc_names.append("{}_{}".format(out, onnx_node.op_type))
                out_needs[idx] = True
                out_shapes[idx] = []
        out_op = top.ArgOp(*self.mlir.get_tensor_type(out_shapes),
                           op,
                           axis=axis,
                           keepdims=keepdims,
                           mode=StringAttr.get(onnx_node.op_type),
                           select_last_index=select_last_index,
                           loc=self.get_loc(loc_names),
                           ip=self.mlir.insert_point)
        out_ops = [out_op.indices, out_op.values]
        for idx, need in enumerate(out_needs):
            if not need: continue
            self.addOperand(onnx_node.outputs[idx], out_ops[idx])

    def convert_lrn_op(self, onnx_node):
        assert onnx_node.op_type == "LRN"
        op = self.getOperand(onnx_node.inputs[0])

        size = onnx_node.attrs.get("size")
        alpha = onnx_node.attrs.get("alpha", None)
        beta = onnx_node.attrs.get("beta", None)
        bias = onnx_node.attrs.get("bias", None)
        new_op = top.LRNOp(self.unranked_type,
                           op,
                           size=size,
                           alpha=alpha,
                           beta=beta,
                           bias=bias,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_gru_op(self, onnx_node):
        assert (onnx_node.op_type == "GRU")
        direction = onnx_node.attrs.get("direction", 'forward')
        layout = onnx_node.attrs.get("layout", 0)
        hidden_size = onnx_node.attrs.get("hidden_size")
        batch_first = True if layout == 1 else False
        operands = list()
        operands.append(self.getOperand(onnx_node.inputs[0]))  # in
        operands.append(self.getWeightOp(onnx_node.inputs[1]))  # W
        operands.append(self.getWeightOp(onnx_node.inputs[2]))  # R
        num_inputs = len(onnx_node.inputs)
        bias_op, init_h_op = self.mlir.none_op, self.mlir.none_op
        if num_inputs > 3:
            bias_op = self.getWeightOp(onnx_node.inputs[3])
        if num_inputs > 4 and len(onnx_node.inputs[4]) != 0:
            raise RuntimeError("GRU does not test the case of specify the sequence_lens.")
        if num_inputs > 5 and len(onnx_node.inputs[5]) != 0:
            init_h_op = self.getOp(onnx_node.inputs[5])
        operands.extend([bias_op, init_h_op])
        loc_names = [onnx_node.name + '_GRU', onnx_node.name + '_H']
        out_shapes = [None, None]
        out_needs = [False, False]
        for idx, out in enumerate(onnx_node.outputs):
            if len(out) > 0 and self.check_need(out):
                loc_names[idx] = "{}_{}".format(out, onnx_node.op_type)
                out_needs[idx] = True
                out_shapes[idx] = []

        out_op = top.GRUOp(*self.mlir.get_tensor_type(out_shapes),
                           *operands,
                           hidden_size=hidden_size,
                           bidirectional=direction == b'bidirectional',
                           batch_first=batch_first,
                           loc=self.get_loc(loc_names),
                           ip=self.mlir.insert_point)
        out_ops = [out_op.Y, out_op.Y_h]
        for idx, need in enumerate(out_needs):
            if need:
                self.addOperand(onnx_node.outputs[idx], out_ops[idx])

    def convert_lstm_op(self, onnx_node):
        assert (onnx_node.op_type == "LSTM")
        direction = onnx_node.attrs.get("direction", 'forward')
        layout = onnx_node.attrs.get("layout", 0)
        hidden_size = onnx_node.attrs.get("hidden_size")
        batch_first = True if layout == 1 else False
        operands = list()
        operands.append(self.getOperand(onnx_node.inputs[0]))  # in
        operands.append(self.getWeightOp(onnx_node.inputs[1]))  # W
        operands.append(self.getWeightOp(onnx_node.inputs[2]))  # R
        num_inputs = len(onnx_node.inputs)
        bias_op, init_h_op, init_c_op = self.mlir.none_op, self.mlir.none_op, self.mlir.none_op
        if num_inputs > 3 and len(onnx_node.inputs[3]) != 0:
            bias_op = self.getWeightOp(onnx_node.inputs[3])
        if num_inputs > 4 and len(onnx_node.inputs[4]) != 0:
            raise RuntimeError("LSTM does not test the case of specify the sequence_lens.")
        if num_inputs > 5 and len(onnx_node.inputs[5]) != 0:
            init_h_op = self.getOp(onnx_node.inputs[5])
        if num_inputs > 6 and len(onnx_node.inputs[5]) != 0:
            init_c_op = self.getOp(onnx_node.inputs[6])
        operands.extend([bias_op, init_h_op, init_c_op])
        loc_names = [onnx_node.name + '_LSTM', onnx_node.name + '_H', onnx_node.name + '_C']
        operands.append(self.mlir.none_op)
        out_shapes = [None, None, None]
        out_needs = [False, False, False]
        for idx, out in enumerate(onnx_node.outputs):
            if len(out) > 0 and self.check_need(out):
                loc_names[idx] = "{}_{}".format(out, onnx_node.op_type)
                out_needs[idx] = True
                out_shapes[idx] = []
        out_op = top.LSTMOp(*self.mlir.get_tensor_type(out_shapes),
                            *operands,
                            hidden_size=hidden_size,
                            bidirectional=direction == b'bidirectional',
                            batch_first=batch_first,
                            loc=self.get_loc(loc_names),
                            ip=self.mlir.insert_point)
        out_ops = [out_op.Y, out_op.Y_h, out_op.Y_c]
        for idx, need in enumerate(out_needs):
            if need:
                self.addOperand(onnx_node.outputs[idx], out_ops[idx])

    def convert_gather_op(self, onnx_node):
        assert (onnx_node.op_type == "Gather")
        in0 = self.getOp(onnx_node.inputs[0])
        axis = onnx_node.attrs.get('axis', 0)
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        extra_attr = {}
        if self.isScalar(onnx_node.inputs[1]):
            extra_attr.update({"keepdims": True})
            idx = self.find_named_tensor(onnx_node.inputs[1])
            if idx is not None and len(idx.shape) == 0:
                extra_attr["keepdims"] = False
        elif onnx_node.shape_info['input'][onnx_node.inputs[1]] is not None \
            and not onnx_node.shape_info['input'][onnx_node.inputs[1]]:
            extra_attr.update({"keepdims": False})
        indices = self.getOp(onnx_node.inputs[1])
        new_op = top.GatherOp(self.unranked_type,
                              in0,
                              indices,
                              axis=axis,
                              **extra_attr,
                              loc=self.get_loc(name),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_gather_elements_op(self, onnx_node):
        assert (onnx_node.op_type == "GatherElements")
        in0 = self.getOp(onnx_node.inputs[0])
        axis = onnx_node.attrs.get('axis', 0)
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        indices = self.getOp(onnx_node.inputs[1])
        new_op = top.GatherElementsOp(self.unranked_type,
                                      in0,
                                      indices,
                                      axis=axis,
                                      loc=self.get_loc(name),
                                      ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_gathernd_op(self, onnx_node):
        assert (onnx_node.op_type == "GatherND")
        input = self.getOp(onnx_node.inputs[0])
        indices = self.getOp(onnx_node.inputs[1])
        batch_dims = onnx_node.attrs.get('batch_dims', 0)
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        new_op = top.GatherNDOp(self.unranked_type,
                                input,
                                indices,
                                batch_dims=batch_dims,
                                loc=self.get_loc(name),
                                ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_expand_op(self, onnx_node):
        assert (onnx_node.op_type == 'Expand')
        in0 = self.getOp(onnx_node.inputs[0])
        if self.isWeight(onnx_node.inputs[1]):
            shape = self.getWeight(onnx_node.inputs[1])
            new_op = top.ExpandOp(self.unranked_type,
                                  in0,
                                  shape=shape,
                                  loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                  onnx_node.op_type)),
                                  ip=self.mlir.insert_point).output
        else:
            shape = self.getOperand(onnx_node.inputs[1])
            new_op = top.ExpandOp(self.unranked_type,
                                  in0,
                                  shapeT=shape,
                                  loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                  onnx_node.op_type)),
                                  ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)
        return

    def convert_tile_op(self, onnx_node):
        assert (onnx_node.op_type == "Tile")
        in0_op = self.getOp(onnx_node.inputs[0])
        if self.isWeight(onnx_node.inputs[1]):
            tile_data = self.getWeight(onnx_node.inputs[1])
            if np.prod(tile_data) == 1:
                self.addOperand(onnx_node.name, in0_op)
                return
            else:
                new_op = top.TileOp(self.unranked_type,
                                    in0_op,
                                    tile=tile_data,
                                    loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                    onnx_node.op_type)),
                                    ip=self.mlir.insert_point).output
        else:
            tile_op = self.getOperand(onnx_node.inputs[1])
            new_op = top.TileOp(self.unranked_type,
                                in0_op,
                                tileT=tile_op,
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_topk_op(self, onnx_node):
        assert (onnx_node.op_type == "TopK")
        in_op = self.getOperand(onnx_node.inputs[0])
        K = onnx_node.attrs.get('k', -1)  # opset 10
        k_op = None
        if (len(onnx_node.inputs) > 1):
            if self.isWeight(onnx_node.inputs[1]):
                K = self.getScalar(onnx_node.inputs[1])
            else:
                k_op = self.getOperand(onnx_node.inputs[1])
        axis = onnx_node.attrs.get('axis', -1)
        largest = onnx_node.attrs.get('largest', True)
        # sorted = onnx_node.attrs.get('sorted', True)
        sorted = True
        loc_names = [onnx_node.name + '_TopK_indices', onnx_node.name + "_TopK_values"]
        out_shapes = [None, None]
        out_needs = [False, False]
        for idx, out in enumerate(onnx_node.outputs):
            #topk at the hw need two output
            if len(out) > 0:
                loc_names[idx] = "{}_{}".format(out, onnx_node.op_type)
                out_needs[idx] = True
                out_shapes[idx] = []
        out_op = top.TopKOp(*self.mlir.get_tensor_type(out_shapes),
                            in_op,
                            axis=axis,
                            K=K,
                            kT=k_op,
                            largest=largest,
                            sorted=sorted,
                            loc=self.get_loc(loc_names),
                            ip=self.mlir.insert_point,
                            replace_topk_indices=self.replace_topk_indices)
        out_ops = [out_op.values, out_op.indices]
        for idx, need in enumerate(out_needs):
            if need:
                self.addOperand(onnx_node.outputs[idx], out_ops[idx])

    def convert_max_op(self, onnx_node):
        assert (onnx_node.op_type == 'Max')
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        lhs_op = self.getWeightOp(lhs) if self.isWeight(lhs) else self.getOp(lhs)
        rhs_op = self.getWeightOp(rhs) if self.isWeight(rhs) else self.getOp(rhs)
        new_op = top.MaxOp(self.unranked_type, [lhs_op, rhs_op],
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_trilu_op(self, onnx_node):
        assert (onnx_node.op_type == 'Trilu')
        upper = onnx_node.attrs.get('upper', 1)
        diagonal = 0
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.TriluOp(self.unranked_type,
                             operand,
                             upper,
                             diagonal,
                             loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_min_op(self, onnx_node):
        assert (onnx_node.op_type == "Min")
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        lhs_op = self.getWeightOp(lhs) if self.isWeight(lhs) else self.getOp(lhs)
        rhs_op = self.getWeightOp(rhs) if self.isWeight(rhs) else self.getOp(rhs)
        new_op = top.MinOp(self.unranked_type, [lhs_op, rhs_op],
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_mod_op(self, onnx_node):
        assert (onnx_node.op_type == "Mod")
        assert (len(onnx_node.inputs) == 2)
        inp1 = onnx_node.inputs[0]
        inp2 = onnx_node.inputs[1]
        inp1_op = self.getOp(inp1)
        inp2_op = self.getOp(inp2)
        mod_op = top.ModOp(self.unranked_type, [inp1_op, inp2_op],
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output

        notequal_op = top.CompareOp(
            self.unranked_type,
            mod_op,
            inp2_op,
            mode=StringAttr.get("NotEqual"),
            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type) + '_NotEqual'),
            ip=self.mlir.insert_point).output

        new_op = top.MulOp(self.unranked_type, [notequal_op, mod_op],
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type) +
                                            '_Mul'),
                           ip=self.mlir.insert_point).output

        self.addOperand(onnx_node.name, new_op)

    def convert_abs_op(self, onnx_node):
        assert (onnx_node.op_type == "Abs")
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.AbsOp(self.unranked_type,
                           operand,
                           loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_neg_op(self, onnx_node):
        assert (onnx_node.op_type == "Neg")
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        operand = self.getOperand(onnx_node.inputs[0])
        mul_const_op = top.MulConstOp(self.unranked_type,
                                      operand,
                                      const_val=-1.0,
                                      loc=self.get_loc(name),
                                      ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, mul_const_op)

    def convert_nms_op(self, onnx_node):
        assert (onnx_node.op_type == "NonMaxSuppression")
        name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        operands = []
        optional_weight_name = ['max_output_boxes_per_class', 'iou_threshold', 'score_threshold']
        # for i, x in enumerate(onnx_node.inputs):
        inputs_len = len(onnx_node.inputs)
        assert (inputs_len >= 2 and inputs_len <= 5)
        for i in range(5):
            if i < inputs_len:
                x = onnx_node.inputs[i]
                if self.isWeight(x):
                    data = self.getWeight(x)
                    # self.addWeight(x, data)
                    operands.append(self.getWeightOp(x))
                    if i == 2:
                        # not strictly equal to 2**63 -1, (case:9.223372e+18) still can be cast to negative because of overflow
                        if (data > 2**63 - 1000):
                            max_output_size = 10000
                        else:
                            max_output_size = data.astype(np.int64)
                else:
                    operands.append(self.getOperand(x))
            else:
                w_name = "{}_{}_default".format(name, optional_weight_name[i - 2])
                wtype = np.float32 if i > 2 else np.int64
                self.addWeight(w_name, np.array([0], dtype=wtype))
                operands.append(self.getWeightOp(w_name))

        max_output_size = 0
        if (len(onnx_node.inputs) > 2):
            if self.isWeight(onnx_node.inputs[2]):
                if (self.getWeight(onnx_node.inputs[2]) > 2**63 - 1000):
                    max_output_size = 10000
                else:
                    max_output_size = self.getWeight(onnx_node.inputs[2]).astype(np.int64)
        nms_op = top.NmsOp(self.unranked_type,
                           operands,
                           center_point_box=0,
                           max_output_size=max_output_size,
                           loc=self.get_loc(name),
                           ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, nms_op)

    def convert_prelu_op(self, onnx_node):
        assert (onnx_node.op_type == "PRelu")
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        in_op = self.getOperand(lhs)
        if self.isScalar(rhs):
            new_op = top.LeakyReluOp(self.unranked_type,
                                     in_op,
                                     alpha=self.getScalar(rhs),
                                     loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                     onnx_node.op_type)),
                                     ip=self.mlir.insert_point).output
            self.addOperand(onnx_node.name, new_op)
            return
        slope = self.getOp(rhs)
        prelu_op = top.PReluOp(self.unranked_type,
                               in_op,
                               slope,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, prelu_op)

    def convert_sum_op(self, onnx_node):
        assert (onnx_node.op_type == "Sum")
        opd0 = self.getOperand(onnx_node.inputs[0])
        num_inputs = len(onnx_node.inputs)
        for i in range(1, num_inputs):
            opd1 = self.getOperand(onnx_node.inputs[i])
            last_name = onnx_node.name
            if i != num_inputs - 1:
                last_name += "_{}".format(str(i))
            opd0 = top.AddOp(self.unranked_type, [opd0, opd1],
                             do_relu=False,
                             loc=self.get_loc("{}_{}".format(last_name, onnx_node.op_type)),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, opd0)

    def convert_sqrt_op(self, onnx_node):
        assert (onnx_node.op_type == "Sqrt")
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.SqrtOp(self.unranked_type,
                            operand,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_tanh_op(self, onnx_node):
        assert (onnx_node.op_type == "Tanh")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.TanhOp(self.unranked_type,
                            op,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_arctan_op(self, onnx_node):
        assert (onnx_node.op_type == "Atan")
        # arctan(x) = aign(x) * acos(1 / (sqrt(1 + mul(abs(x), abs(x)))))
        op0 = self.getOperand(onnx_node.inputs[0])
        op_name = onnx_node.name + "_sign"
        sign_op = top.SignOp(self.unranked_type,
                             op0,
                             loc=self.get_loc(op_name),
                             ip=self.mlir.insert_point).output
        op_name = onnx_node.name + "_abs"
        abs_op = top.AbsOp(self.unranked_type,
                           op0,
                           loc=self.get_loc(op_name),
                           ip=self.mlir.insert_point).output
        op_name = onnx_node.name + "_mul"
        mul_op = top.MulOp(self.unranked_type, [abs_op, abs_op],
                           do_relu=False,
                           loc=self.get_loc(op_name),
                           ip=self.mlir.insert_point).output

        op_name = onnx_node.name + "_ml_mulscale"
        add_op = top.AddConstOp(self.unranked_type,
                                mul_op,
                                const_val=1,
                                loc=self.get_loc(op_name),
                                ip=self.mlir.insert_point).output

        op_name = onnx_node.name + "_sqrt"
        sqrt_op = top.SqrtOp(self.unranked_type,
                             add_op,
                             loc=self.get_loc(op_name),
                             ip=self.mlir.insert_point).output

        op_name = onnx_node.name + "_reciprocal"
        reciprocal_op = top.ReciprocalOp(self.unranked_type,
                                         sqrt_op,
                                         loc=self.get_loc(op_name),
                                         ip=self.mlir.insert_point).output

        op_name = onnx_node.name + "_arccos"
        arccos_op = top.ArccosOp(self.unranked_type,
                                 reciprocal_op,
                                 loc=self.get_loc(op_name),
                                 ip=self.mlir.insert_point).output
        arctan_op = top.MulOp(self.unranked_type, [sign_op, arccos_op],
                              do_relu=False,
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output

        self.addOperand(onnx_node.name, arctan_op)

    def convert_arctanh_op(self, onnx_node):
        assert (onnx_node.op_type == "Atanh")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.ArctanhOp(self.unranked_type,
                               op,
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_arccos_op(self, onnx_node):
        assert (onnx_node.op_type == "Acos")
        op = self.getOperand(onnx_node.inputs[0])
        new_op = top.ArccosOp(self.unranked_type,
                              op,
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_pow_op(self, onnx_node):
        assert (onnx_node.op_type == "Pow")
        assert (len(onnx_node.inputs) == 2)
        base = onnx_node.inputs[0]
        expn = onnx_node.inputs[1]
        if self.isScalar(expn):
            base_op = self.getOp(base)
            expn_const = self.getScalar(expn)
            if expn_const == 1.0:
                self.addOperand(onnx_node.name, base_op)
                return
            if expn_const == 2.0:
                mul_op = top.MulOp(self.unranked_type, [base_op, base_op],
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
                self.addOperand(onnx_node.name, mul_op)
                return
            else:
                pow_op = top.PowOp(self.unranked_type,
                                   base_op,
                                   exponent=expn_const,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
                self.addOperand(onnx_node.name, pow_op)
        elif self.isScalar(base):
            expn_op = self.getOp(expn)
            base_const = self.getScalar(base)
            pow_op = top.Pow2Op(self.unranked_type,
                                base_const,
                                expn_op,
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
            self.addOperand(onnx_node.name, pow_op)
        else:
            base_op = self.getOp(base)
            expn_op = self.getOp(expn)
            pow_op = top.Pow3Op(self.unranked_type, [base_op, expn_op],
                                loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                                ip=self.mlir.insert_point).output
            self.addOperand(onnx_node.name, pow_op)

    def convert_where_op(self, onnx_node):
        assert (onnx_node.op_type == "Where")
        assert (len(onnx_node.inputs) == 3)
        cond = onnx_node.inputs[0]
        tbrn = onnx_node.inputs[1]
        fbrn = onnx_node.inputs[2]
        cond_opd = self.getOp(cond)
        tbrn_opd = self.getOp(tbrn)
        fbrn_opd = self.getOp(fbrn)
        num_const = 0
        if self.isScalar(tbrn):
            num_const += 1
        # else:
        #     assert (self.getShape(cond) == self.getShape(tbrn)
        #             )  # do not support broadcastable case recently
        if self.isScalar(fbrn):
            num_const += 1
        # else:
        #     assert (self.getShape(cond) == self.getShape(fbrn)
        #             )  # do not support broadcastable case recently
        if num_const == 0:
            new_op = top.WhereOp(self.unranked_type,
                                 cond_opd,
                                 tbrn_opd,
                                 fbrn_opd,
                                 x_is_const=False,
                                 y_is_const=False,
                                 x_const_val=0,
                                 y_const_val=0,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        elif num_const >= 1:
            x_is_const = False
            y_is_const = False
            if self.isScalar(tbrn):
                x_is_const = True
                x_const_val = self.getScalar(tbrn)
                t_opd = self.mlir.none_op
            else:
                t_opd = tbrn_opd
                x_const_val = 0
            if self.isScalar(fbrn):
                y_is_const = True
                y_const_val = self.getScalar(fbrn)
                f_opd = self.mlir.none_op
            else:
                f_opd = fbrn_opd
                y_const_val = 0
            new_op = top.WhereOp(self.unranked_type,
                                 cond_opd,
                                 t_opd,
                                 f_opd,
                                 x_is_const=x_is_const,
                                 y_is_const=y_is_const,
                                 x_const_val=x_const_val,
                                 y_const_val=y_const_val,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        else:
            assert (0)
        self.addOperand(onnx_node.name, new_op)

    def convert_not_op(self, onnx_node):
        assert (onnx_node.op_type == "Not")
        opd = onnx_node.inputs[0]
        not_op = top.CompareConstOp(self.unranked_type,
                                    self.getOp(opd),
                                    mode=StringAttr.get(onnx_node.op_type),
                                    const_val=np.array([0]).astype(np.bool_),
                                    inversed=False,
                                    loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                    onnx_node.op_type)),
                                    ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, not_op)

    def convert_cmp_op(self, onnx_node):
        supports = {"Equal", "Greater", "GreaterOrEqual", "Less", "LessOrEqual", "And", "Xor"}
        assert (onnx_node.op_type in supports)
        assert (len(onnx_node.inputs) == 2)
        lhs = onnx_node.inputs[0]
        rhs = onnx_node.inputs[1]
        if self.isScalar(lhs) and len(self.getShape(lhs)) == 1:
            rhs_opd = self.getOp(rhs)
            cmp_op = top.CompareConstOp(self.unranked_type,
                                        rhs_opd,
                                        mode=StringAttr.get(onnx_node.op_type),
                                        const_val=self.getScalar(lhs),
                                        inversed=True,
                                        loc=self.get_loc("{}_{}".format(
                                            onnx_node.name, onnx_node.op_type)),
                                        ip=self.mlir.insert_point).output
        elif self.isScalar(rhs) and len(self.getShape(rhs)) == 1:
            lhs_opd = self.getOp(lhs)
            cmp_op = top.CompareConstOp(self.unranked_type,
                                        lhs_opd,
                                        mode=StringAttr.get(onnx_node.op_type),
                                        const_val=self.getScalar(rhs),
                                        inversed=False,
                                        loc=self.get_loc("{}_{}".format(
                                            onnx_node.name, onnx_node.op_type)),
                                        ip=self.mlir.insert_point).output
        else:
            rhs_opd = self.getOp(rhs)
            lhs_opd = self.getOp(lhs)
            cmp_op = top.CompareOp(self.unranked_type,
                                   lhs_opd,
                                   rhs_opd,
                                   mode=StringAttr.get(onnx_node.op_type),
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, cmp_op)

    def convert_hsigmoid_op(self, onnx_node):
        # hardsigmoid(x; alpha, beta) := min(max(alpha*x + beta, 0), 1)
        assert (onnx_node.op_type == "HardSigmoid")
        assert (len(onnx_node.inputs) == 1)
        operand = self.getOperand(onnx_node.inputs[0])
        alpha = onnx_node.attrs.get("alpha", 1. / 6)
        beta = onnx_node.attrs.get("beta", 0.5)
        new_op = top.HardSigmoidOp(self.unranked_type,
                                   operand,
                                   alpha=alpha,
                                   beta=beta,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_hswish_op(self, onnx_node):
        # hardswish(x) := x * hardsigmoid(x; 1/6, 0.5)
        assert (onnx_node.op_type == "HardSwish")
        assert (len(onnx_node.inputs) == 1)
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.HardSwishOp(self.unranked_type,
                                 operand,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_gelu_op(self, onnx_node):
        # 0.5 * val * (1.0 + std::erf(val / std::sqrt(2.0)));
        assert (onnx_node.op_type == "GELU")
        assert (len(onnx_node.inputs) == 1)
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.GELUOp(self.unranked_type,
                            operand,
                            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_qlinear_op(self, onnx_node):
        assert (onnx_node.op_type == "QuantizeLinear")
        assert (len(onnx_node.inputs) == 3)
        operand = self.getOperand(onnx_node.inputs[0])
        y_scale = self.getWeight(onnx_node.inputs[1]).tolist()
        y_zero_point = self.getWeight(onnx_node.inputs[2]).tolist()
        if hasattr(onnx_node, 'attrs'):
            axis = onnx_node.attrs.get('axis', None)

        new_op = top.QuantizeLinearOp(self.unranked_type,
                                      operand,
                                      y_scale=y_scale,
                                      y_zero_point=y_zero_point,
                                      axis=axis,
                                      loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                      onnx_node.op_type)),
                                      ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_deqlinear_op(self, onnx_node):
        assert (onnx_node.op_type == "DequantizeLinear")
        assert (len(onnx_node.inputs) == 3)
        try:
            operand = self.getOperand(onnx_node.inputs[0])
        except:
            operand = self.getWeightOp(onnx_node.inputs[0])
        x_scale = self.getWeight(onnx_node.inputs[1])
        x_zero_point = self.getWeight(onnx_node.inputs[2])
        if hasattr(onnx_node, 'attrs'):
            axis = onnx_node.attrs.get('axis', None)
        new_op = top.DequantizeLinearOp(self.unranked_type,
                                        operand,
                                        x_scale=x_scale,
                                        x_zero_point=x_zero_point,
                                        axis=axis,
                                        loc=self.get_loc("{}_{}".format(
                                            onnx_node.name, onnx_node.op_type)),
                                        ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_layer_norm_op(self, onnx_node):
        assert (onnx_node.op_type == "LayerNormalization")
        assert (len(onnx_node.inputs) <= 3)
        axis = onnx_node.attrs.get("axis", -1)
        eps = onnx_node.attrs.get("epsilon", 1e-05)
        if type(eps) == list and len(eps) == 1:
            eps = eps[0]
        input_opd = self.getOp(onnx_node.inputs[0])
        scale_opd = self.mlir.none_op
        bias_opd = self.mlir.none_op
        if len(onnx_node.inputs) > 1:
            if not self.isScalar_(onnx_node.inputs[1], 1):
                scale_opd = self.getWeightOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) > 2:
            if not self.isScalar_(onnx_node.inputs[2], 0):
                bias_opd = self.getWeightOp(onnx_node.inputs[2])
        out_op = top.LayerNormOp(self.unranked_type,
                                 input_opd,
                                 scale_opd,
                                 bias_opd,
                                 normalized_shape=[],
                                 axis=axis,
                                 eps=eps,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, out_op)

    def convert_pixel_norm_op(self, onnx_node):
        assert (onnx_node.op_type == "PixelNormalization")
        assert (len(onnx_node.inputs) in (1, 2, 3))
        eps = onnx_node.attrs.get("epsilon", 1e-05)
        input_opd = self.getOperand(onnx_node.inputs[0])
        scale_opd = self.mlir.none_op
        bias_opd = self.mlir.none_op
        if len(onnx_node.inputs) > 1:
            if not self.isScalar_(onnx_node.inputs[1], 1):
                scale_opd = self.getWeightOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) > 2:
            if not self.isScalar_(onnx_node.inputs[2], 0):
                bias_opd = self.getWeightOp(onnx_node.inputs[2])
        new_op = top.PixelNormOp(self.unranked_type,
                                 input_opd,
                                 scale_opd,
                                 bias_opd,
                                 eps=eps,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_instance_norm_op(self, onnx_node):
        assert (onnx_node.op_type == "InstanceNormalization")
        assert (len(onnx_node.inputs) in (1, 2, 3))
        eps = onnx_node.attrs.get("epsilon", 1e-05)
        input_opd = self.getOperand(onnx_node.inputs[0])
        scale_opd = self.mlir.none_op
        bias_opd = self.mlir.none_op
        if len(onnx_node.inputs) > 1:
            if not np.all(self.getWeight(onnx_node.inputs[1]) == 1):
                scale_opd = self.getWeightOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) > 2:
            if not np.all(self.getWeight(onnx_node.inputs[2]) == 0):
                bias_opd = self.getWeightOp(onnx_node.inputs[2])
        new_op = top.InstanceNormOp(self.unranked_type,
                                    input_opd,
                                    scale_opd,
                                    bias_opd,
                                    eps=eps,
                                    loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                    onnx_node.op_type)),
                                    ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_group_norm_op(self, onnx_node):
        assert (onnx_node.op_type == "GroupNormalization")
        assert (len(onnx_node.inputs) in (1, 2, 3))
        num_groups = onnx_node.attrs.get("num_groups")  # required
        eps = onnx_node.attrs.get("epsilon", 1e-05)
        input_opd = self.getOperand(onnx_node.inputs[0])
        scale_opd = self.mlir.none_op
        bias_opd = self.mlir.none_op
        if len(onnx_node.inputs) > 1:
            if not self.isScalar_(onnx_node.inputs[1], 1):
                scale_opd = self.getWeightOp(onnx_node.inputs[1])
        if len(onnx_node.inputs) > 2:
            if not self.isScalar_(onnx_node.inputs[2], 0):
                bias_opd = self.getWeightOp(onnx_node.inputs[2])
        new_op = top.GroupNormOp(self.unranked_type,
                                 input_opd,
                                 scale_opd,
                                 bias_opd,
                                 num_groups=num_groups,
                                 eps=eps,
                                 loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                 onnx_node.op_type)),
                                 ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_scatter_elements_op(self, onnx_node):
        assert (onnx_node.op_type == "ScatterElements")
        assert (len(onnx_node.inputs) == 3)
        input = self.getOp(onnx_node.inputs[0])
        indices = self.getOp(onnx_node.inputs[1])
        updates = self.getOp(onnx_node.inputs[2])
        axis = onnx_node.attrs.get("axis", 0)
        reduction = onnx_node.attrs.get("reduction", None)
        assert not reduction
        new_op = top.ScatterElementsOp(
            self.unranked_type,
            input,
            indices,
            updates,
            axis=axis,
            # reduction=reduction, # ??????????? no such param
            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_scatternd_op(self, onnx_node):
        assert (onnx_node.op_type == "ScatterND")
        assert (len(onnx_node.inputs) == 3)
        input_data = self.getOp(onnx_node.inputs[0])
        indices = self.getOp(onnx_node.inputs[1])
        updates = self.getOp(onnx_node.inputs[2])
        reduction = onnx_node.attrs.get("reduction", None)
        assert not reduction
        scatternd_op = top.ScatterNDOp(
            self.unranked_type,
            input_data,
            indices,
            updates,
            # reduction=reduction, # ??????????? no such param
            loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
            ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, scatternd_op)

    def convert_roi_align_op(self, onnx_node: OnnxNode):
        assert (onnx_node.op_type == "RoiAlign")
        assert (len(onnx_node.inputs) == 3)
        input = self.getOp(onnx_node.inputs[0])
        rois = self.getOp(onnx_node.inputs[1])
        batch_indices = self.getOp(onnx_node.inputs[2])
        output_name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        mode = onnx_node.attrs.get("mode", "Avg")
        if isinstance(mode, bytes):
            mode_str = str(mode, 'utf-8')
            if mode_str == "avg" or mode_str == "max":
                mode = mode_str.capitalize()
        output_height = onnx_node.attrs.get("output_height", 1)
        output_width = onnx_node.attrs.get("output_width", 1)
        sampling_ratio = onnx_node.attrs.get("sampling_ratio", 0)
        spatial_scale = onnx_node.attrs.get("spatial_scale", 1.0)
        if self.opset < 16:
            coord_transf_mode = "output_half_pixel"
        else:
            coord_transf_mode = onnx_node.attrs.get("coordinate_transformation_mode", "half_pixel")
            if isinstance(coord_transf_mode, bytes):
                coord_transf_mode = coord_transf_mode.decode('utf-8')
        align_corners = coord_transf_mode == "half_pixel"
        batch_indices_xpd = top.UnsqueezeOp(self.unranked_type,
                                            batch_indices,
                                            axes=[-1],
                                            loc=self.get_loc(output_name + "_unsqueeze"),
                                            ip=self.mlir.insert_point).output
        rois_xpd = top.ConcatOp(self.unranked_type, [batch_indices_xpd, rois],
                                axis=1,
                                loc=self.get_loc(output_name + "_concat"),
                                ip=self.mlir.insert_point).output
        new_op = top.RoiAlignOp(self.unranked_type,
                                input,
                                rois_xpd,
                                mode=StringAttr.get(mode),
                                output_height=output_height,
                                output_width=output_width,
                                sampling_ratio=sampling_ratio,
                                spatial_scale=spatial_scale,
                                align_corners=align_corners,
                                loc=self.get_loc(output_name),
                                ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_nonzero_op(self, onnx_node):
        assert (onnx_node.op_type == "NonZero")
        assert (len(onnx_node.inputs) == 1)
        input_data = self.getOp(onnx_node.inputs[0])
        new_op = top.NonZeroOp(self.unranked_type,
                               input_data,
                               order=StringAttr.get("RowMajor"),
                               loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                               ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_onehot_op(self, onnx_node):
        assert (onnx_node.op_type == "OneHot")
        assert (len(onnx_node.inputs) == 3)
        assert (len(onnx_node.outputs) == 1)
        indices = self.getOp(onnx_node.inputs[0])
        depth = self.getOp(onnx_node.inputs[1])  #  -depth <= indeces[i] <= depth-1
        values = self.getOp(onnx_node.inputs[2])
        axis = onnx_node.attrs.get("axis", -1)
        assert (axis == -1)
        output_name = "{}_{}".format(onnx_node.name, onnx_node.op_type)
        min_value = 0
        max_value = 0
        if (self.isWeight(values)):
            min_value = top.ReduceOp(self.unranked_type,
                                     self.getWeightOp(values),
                                     axes=[0],
                                     keepdims=1,
                                     mode=StringAttr.get("ReduceMin"),
                                     loc=self.get_loc(output_name + "_min"),
                                     ip=self.mlir.insert_point).output
            max_value = top.ReduceOp(self.unranked_type,
                                     self.getWeightOp(values),
                                     axes=[0],
                                     keepdims=1,
                                     mode=StringAttr.get("ReduceMax"),
                                     loc=self.get_loc(output_name + "_max"),
                                     ip=self.mlir.insert_point).output
        else:
            min_value = top.ReduceOp(self.unranked_type,
                                     values,
                                     axes=[0],
                                     keepdims=1,
                                     mode=StringAttr.get("ReduceMin"),
                                     loc=self.get_loc(output_name + "_min"),
                                     ip=self.mlir.insert_point).output
            max_value = top.ReduceOp(self.unranked_type,
                                     values,
                                     axes=[0],
                                     keepdims=1,
                                     mode=StringAttr.get("ReduceMax"),
                                     loc=self.get_loc(output_name + "_max"),
                                     ip=self.mlir.insert_point).output
        if (self.isWeight(indices)):
            ind_dims = list(self.getWeight(onnx_node.inputs[0]).shape)
            ind_unsq = list(self.getWeight(onnx_node.inputs[0]).shape)
            ind_dims.extend(self.getWeight(onnx_node.inputs[1]))
            ind_unsq.extend([1])
            padding_shape = np.array(ind_dims).astype(np.int64)
            input_data = top.ExpandOp(self.unranked_type,
                                      min_value,
                                      shape=padding_shape,
                                      loc=self.get_loc(output_name + "_expandmin"),
                                      ip=self.mlir.insert_point).output
            updates = top.ExpandOp(self.unranked_type,
                                   max_value,
                                   shape=ind_unsq,
                                   loc=self.get_loc(output_name + "_expandmax"),
                                   ip=self.mlir.insert_point).output
        else:
            depth_max = self.getWeightOp(onnx_node.inputs[1])
            depth_min = np.array([1], dtype=np.int64)
            depth_min_name = output_name + "_undates_concat_depth_min"
            self.addWeight(depth_min_name, depth_min)
            shape_op = top.ShapeOp(self.unranked_type,
                                   indices,
                                   start=0,
                                   loc=self.get_loc(output_name + "_shape"),
                                   ip=self.mlir.insert_point).output
            padding_shape = top.ConcatOp(self.unranked_type, [shape_op, depth_max],
                                         axis=-1,
                                         loc=self.get_loc(output_name + "_indata_concat"),
                                         ip=self.mlir.insert_point).output
            ind_unsq = top.ConcatOp(self.unranked_type,
                                    [shape_op, self.getWeightOp(depth_min_name)],
                                    axis=-1,
                                    loc=self.get_loc(output_name + "_undates_concat"),
                                    ip=self.mlir.insert_point).output
            input_data = top.ExpandOp(self.unranked_type,
                                      min_value,
                                      shapeT=padding_shape,
                                      loc=self.get_loc(output_name + "_expandmin"),
                                      ip=self.mlir.insert_point).output
            updates = top.ExpandOp(self.unranked_type,
                                   max_value,
                                   shapeT=ind_unsq,
                                   loc=self.get_loc(output_name + "_expandmax"),
                                   ip=self.mlir.insert_point).output
        indices_unsq = top.UnsqueezeOp(self.unranked_type,
                                       indices,
                                       loc=self.get_loc(output_name + "_indices_unsqeeze"),
                                       ip=self.mlir.insert_point,
                                       axes=[-1]).output
        new_op = top.ScatterElementsOp(self.unranked_type,
                                       input_data,
                                       indices_unsq,
                                       updates,
                                       axis=-1,
                                       loc=self.get_loc(output_name + "_scatter_elements"),
                                       ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def parse_subgraph(self, op, region_idx, graph_node):
        converted_nodes = list()
        for n in graph_node.node:
            node = OnnxNode(n)
            if n.op_type in ["Gather"]:
                input_shape = dict()
                for input in n.input:
                    input_shape[input] = self.get_shape_for_node(graph_node.input,
                                                                 graph_node.output,
                                                                 graph_node.value_info, input)
                output_shape = dict()
                for output in n.output:
                    output_shape[output] = self.get_shape_for_node(graph_node.input,
                                                                   graph_node.output,
                                                                   graph_node.value_info, output)
                node.shape_info["input"] = input_shape
                node.shape_info["output"] = output_shape
            converted_nodes.append(node)

        unsupported = set()
        for n in converted_nodes:
            if n.op_type not in self.onnxop_factory:
                unsupported.add(n.op_type)
        if unsupported:
            raise RuntimeError("Op not support:{}".format(unsupported))
        initializer_names = [x.name for x in graph_node.initializer]
        subgraph_input_names = list()

        region = op.regions[region_idx]
        arg_types = list()
        #add block argument to entry block
        for input in graph_node.input:
            if input.name not in initializer_names:
                shape = self.get_shape_from_value_info_proto(input)
                #if int64/int32/bool, replace it with int32
                if input.type.tensor_type.elem_type in [
                        onnx.TensorProto.INT64, onnx.TensorProto.INT32, onnx.TensorProto.BOOL
                ]:
                    dtype = "INT32"
                else:
                    dtype = "F32"
                arg_types.append(
                    self.mlir.get_tensor_type(shape if len(shape) > 0 else [1],
                                              self.mlir.mlir_type[dtype]))
                self.input_names.append(input.name)
                subgraph_input_names.append(input.name)
        self.mlir.buildBlock(region, arg_types)
        self.mlir.reconfig_insert_point(region.blocks[0])

        entry_block_args = list()
        for i in region.blocks[0].arguments:
            entry_block_args.append(i)
        #create subgraph's input op
        for idx, input in enumerate(graph_node.input):
            if input.name not in initializer_names:
                input_op = self.mlir.create_subgraph_input_op(input.name, arg_types[idx],
                                                              entry_block_args[idx], **{})
                self.addOperand(input.name, input_op)
        # add all weight
        self.subgraph_initializer = graph_node.initializer
        for tensor in graph_node.initializer:
            name = tensor.name
            data = numpy_helper.to_array(tensor).astype(np.float32)
            self.addWeight(name, data)
        self.get_output_name(graph_node)

        def NoneAndRaise(node):
            raise RuntimeError("{} Op not support now".format(node.op_type))

        for n in converted_nodes:
            self.onnxop_factory.get(n.op_type, lambda x: NoneAndRaise(x))(n)
        self.subgraph_initializer = None

        yield_op = list()
        #remove the input tensor from self.input_names
        for n in subgraph_input_names:
            self.input_names.remove(n)

        #Todo: remove the shape/tensor from self.shapes/self.tensors
        for output in graph_node.output:
            if not self.isWeight(output.name):
                self.output_names.remove(output.name)
                op = self.getOperand(output.name)
                yield_op.append(op)
            else:
                yield_op.append(self.getWeightOp(output.name))
        self.mlir.create_yield_op(yield_op)

    def convert_if_op(self, onnx_node):
        assert (onnx_node.op_type == "If")
        assert (len(onnx_node.inputs) == 1)
        input_data = self.getOp(onnx_node.inputs[0])
        p = {
            "name": [
                "{}_{}_{}".format(onnx_node.name, onnx_node.op_type, id)
                for id in range(len(onnx_node.outputs))
            ],
            "region":
            2,
        }
        new_op = self.mlir.create_if_op([input_data], [], **p)
        self.addOperand(onnx_node.name, new_op)
        for attr in onnx_node.node_proto.attribute:
            #attr.type == 5 : graph
            region_idx = 0 if attr.name == "then_branch" else 1
            if attr.type == 5:
                self.parse_subgraph(new_op.owner, region_idx, attr.g)
        #restore the insert_point
        self.mlir.restore_insert_point()

    def convert_loop_op(self, onnx_node):
        assert (onnx_node.op_type == "Loop")
        assert (len(onnx_node.inputs) >= 2)
        assert (len(onnx_node.outputs) >= 1)
        operands = list()
        out_shapes = list()
        for input in onnx_node.inputs:
            op = self.getOp(input)
            operands.append(op)
        for output in onnx_node.outputs:
            out_shapes.append([])
        p = {
            "name": [
                "{}_{}_{}".format(onnx_node.name, onnx_node.op_type, id)
                for id in range(len(out_shapes))
            ],
            "region":
            1,
        }
        new_op = self.mlir.create_loop_op(operands, out_shapes, **p)
        for idx, output in enumerate(onnx_node.outputs):
            self.addOperand(output, new_op[idx])
        for attr in onnx_node.node_proto.attribute:
            #attr.type: Graph
            if attr.type == 5:
                self.parse_subgraph(new_op[0].owner, 0, attr.g)
        #restore the insert_point
        self.mlir.restore_insert_point()

    def convert_grid_sampler_op(self, onnx_node):
        assert (onnx_node.op_type == "GridSample")
        assert (len(onnx_node.inputs) == 2)
        input_data = self.getOp(onnx_node.inputs[0])
        grid_data = self.getOp(onnx_node.inputs[1])
        align_corners = onnx_node.attrs.get("align_corners", 0)
        mode = onnx_node.attrs.get("mode", "bilinear")
        if mode == b"bilinear":
            mode = 0
        elif mode == b"nearest":
            mode = 1
        else:
            assert ("Unsupported interpolation mode of {}.".format(mode) and 0)
        padding_mode = onnx_node.attrs.get("padding_mode", "zeros")
        if padding_mode == b"zeros":
            padding_mode = 0
        elif padding_mode == b"border":
            padding_mode = 1
        elif padding_mode == b"reflection":
            padding_mode = 2
        else:
            assert ("Unsupported padding_mode of {}.".format(padding_mode) and 0)
        new_op = top.GridSamplerOp(self.unranked_type,
                                   input_data,
                                   grid_data,
                                   mode=mode,
                                   padding_mode=padding_mode,
                                   align_corners=align_corners,
                                   loc=self.get_loc("{}_{}".format(onnx_node.name,
                                                                   onnx_node.op_type)),
                                   ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_cumsum_op(self, onnx_node):
        assert onnx_node.op_type == "CumSum"
        if not self.isWeight(onnx_node.inputs[1]):
            raise ValueError("Currently, only constant axis is supported")
        axis = self.getWeight(onnx_node.inputs[1])
        operands = list()
        operands.append(self.getOperand(onnx_node.inputs[0]))
        operands.append(self.getWeightOp(onnx_node.inputs[1]))
        new_op = top.CumSumOp(self.unranked_type,
                              *operands,
                              axis=axis,
                              loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                              ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

    def convert_round_op(self, onnx_node):
        assert (onnx_node.op_type == "Round")
        operand = self.getOperand(onnx_node.inputs[0])
        new_op = top.RoundOp(self.unranked_type,
                             operand,
                             loc=self.get_loc("{}_{}".format(onnx_node.name, onnx_node.op_type)),
                             ip=self.mlir.insert_point).output
        self.addOperand(onnx_node.name, new_op)

