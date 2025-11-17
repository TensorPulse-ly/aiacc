# github内SMC代码个人运行流程及测试结果

下载地址：https://github.com/seclabBupt/aiacc.git

## 1 使用流程

### 1.1 文件传输

本人采用Xfpt8进行文件传输，该软件是一个免费软件，可到官网上下载，下载完成后让其与本地虚拟机进行连接，连接成功后即可传输。

### 1.2 fp16_to_fp32_multiplier 代码运行

该代码的运行流程是根据Sunny学长发在群内的名为**Berkeley SoftFloat库**的文件进行，再加上本人对一些运行过程中会出现的问题的解决措施。

首先要进入到berkeley-softfloat-3-master里面的Linux-x86_64-GCC文件内，个人的具体路径为：
```Linux
cd /home/five/Desktop/aiacc-main/SMC/berkeley-softfloat-3-master/build/Linux-x86_64-GCC
```
可根据自己的路径进行修改。

#### 第一个可能会出现的错误：

之后在在makefile中加入fPIC，其代码具体为：
```
COMPILE_C = \
	gcc -c -Werror-implicit-function-declaration -DSOFTFLOAT_FAST_INT64 \
		$(SOFTFLOAT_OPTS) $(C_INCLUDES) -O2 -fPIC -o $@
MAKELIB = ar crs $@
```
之后在终端里输入make即可编译SoftFloat库。

**注**：如果直接复制"**Berkeley SoftFloat库**"这个文件内的代码会产生错误，错误为：
```
//错误原因
[five@eda1 Linux-x86_64-GCC]$ make
  gcc -c -Werror-implicit-function-declaration -DSOFTFLOAT_FAST_INT64     -DSOFTFLOAT_ROUND_ODD -DINLINE_LEVEL=5 -DSOFTFLOAT_FAST_DIV32TO16 -DSOFTFLOAT_FAST_DIV64TO32 -I. -I../../source/8086-SSE -I../../source/include -O2 -fPIC -o s_eq128.o ../../source/s_eq128.c
make:  : Command not found
make: *** [s_eq128.o] Error 127
```
该错误的具体原因Makefile规则使用了​​空格缩进​​而不是​​制表符(Tab)​​。Make工具严格要求命令必须以制表符开头（而不是空格），否则会报Command not found错误。简单来说就是应该用Tab进行缩进，但是这个文件里的代码用了空格导致出现这个问题。

#### 第二个可能会出现的错误：

之后运行:
```
g++ -shared -o libruntime.so softfloat_dpi.o -L/home/five/Desktop/aiacc-main/SMC/berkeley-softfloat-3-master/build/Linux-x86_64-GCC/ -lsoftfloat
```
将softfloat_dpi.c编译为共享库libruntime.so，并链接softfloat.a。不过SMC内的文件似乎以及进行了链接，所以不需要进行这步操作，当然也可以运行，但是会报错，具体原因是：
```
//需运行代码
[five@eda1 Linux-x86_64-GCC]$ g++ -shared -o libruntime.so softfloat_dpi.o -L/home/five/Desktop/aiacc-main/SMC/berkeley-softfloat-3-master/build/Linux-x86_64-GCC/ -lsoftfloat
//错误原因
bash: g++ -shared -o libruntime.so softfloat_dpi.o -L/home/five/Desktop/aiacc-main/SMC/berkeley-softfloat-3-master/build/Linux-x86_64-GCC/ -lsoftfloat: No such file or directory
```
不过这个其实不是什么大问题，因为以及进行了链接，所以这是不需要操作的。

如果是下载的github内的SMC文件，之后的包括代码的增加是不需要进行的。一直到第五步使用run_sim.sh脚本编译和运行仿真前都是不需要操作的。

#### 第三个可能会出现的错误：

之后当你运行：
```
//需运行代码
./run_sim.sh
```
会报错，错误原因为：
```
//错误原因
[five@eda1 fp16_to_fp32_multiplier]$ ./run_sim.sh
bash: ./run_sim.sh: Permission denied
```
具体原因为是没有权限执行run_sim.sh脚本。因此在运行该代码前需要先运行：
```
//解决方法
chmod +x run_sim.sh
```
这样就可以获得权限了。

#### 第四个可能会出现的错误：

之后运行仍然会报错，具体原因为：
```
//错误原因
[five@eda1 fp16_to_fp32_multiplier]$ ./run_sim.sh
使用一体化脚本编译 DPI-C 文件...
./run_sim.sh: line 31: /home/Sunny/SMC/compile_softfloat_dpi.sh: No such file or directory
错误: DPI-C 文件编译失败
```
这个错误原因是run_sim.sh文件的31行没有改他的文件路径，打开这个文件后有两处需要更改，更改完成后重新运行该代码。

#### 第五个可能会出现的错误：

不过还会报错，报错原因为：
```
//错误原因
[five@eda1 fp16_to_fp32_multiplier]$ chmod +x run_sim.sh
[five@eda1 fp16_to_fp32_multiplier]$ ./run_sim.sh
使用一体化脚本编译 DPI-C 文件...
./run_sim.sh: line 31: /home/five/Desktop/aiacc/SMC/compile_softfloat_dpi.sh: Permission denied
错误: DPI-C 文件编译失败
```
这个原因是**compile_softfloat_dpi.sh**文件没有权限，应该新增一行代码：
```
//解决方法
chmod +x /home/five/Desktop/aiacc-main/SMC/compile_softfloat_dpi.sh
```
改代码可以获得compile_softfloat_dpi.sh的权限。

之后再次运行就可以获得运行结果了。


### 1.3 fp32_adder_tree 代码运行

具体流程和1.2的fp16_to_fp32_multiplier运行流程一样。

```
//需运行代码
chmod +x run_sim_softfloat.sh
./run_sim_softfloat.sh
```

#### 第一个可能会出现的错误：

不过会显示错误：
```
//错误原因
[five@eda1 adder_8]$ ./run_sim_softfloat.sh
清理之前的仿真文件...
./run_sim_softfloat.sh: line 9: /home/Sunny/SMC/compile_softfloat_dpi.sh: No such file or directory
错误: DPI-C 文件编译失败
```
这个错误原因和上一个的类似，都是调用的文件路径有问题，改成自己的就可以了。

#### 第二个可能会出现的错误：

之后再次运行会报错：
```
//错误原因
[five@eda1 adder_8]$ ./run_sim_softfloat.sh
清理之前的仿真文件...
[信息] === 一体化 SoftFloat DPI-C 编译脚本 ===
[信息] 源文件: ../softfloat_fp32_dpi.c
[信息] 输出库: libruntime.so
[信息] 第一步: 检测和设置 Berkeley SoftFloat-3
[错误] 未找到 Berkeley SoftFloat 目录
[信息] 请确保 berkeley-softfloat-3-master 目录存在于以下位置之一:
  - /home/Sunny/SMC/berkeley-softfloat-3-master
  - ./berkeley-softfloat-3-master
  - ../berkeley-softfloat-3-master
  - ../../berkeley-softfloat-3-master
错误: DPI-C 文件编译失败
```

这个问题和上一个一样，也是文件路径有错误，修改**compile_softfloat_dpi.sh**文件里的文件路径即可。

#### 第三个可能会出现的错误：

之后再次运行会报错：
```
//错误原因
[信息] 编译目标文件: ../softfloat_fp32_dpi.o
../softfloat_fp32_dpi.c: In function ‘fp32_add_array_softfloat’:
../softfloat_fp32_dpi.c:61:5: error: ‘for’ loop initial declarations are only allowed in C99 mode
     for (int i = 1; i < num_inputs; i++) {
     ^
../softfloat_fp32_dpi.c:61:5: note: use option -std=c99 or -std=gnu99 to compile your code
[错误] 目标文件编译失败
错误: DPI-C 文件编译失败
```
这个错误原因是代码用了C99标准的循环变量声明方式（for(int i = ...）)，而默认的C编译模式不支持这种写法，因此需要手动添加权限，具体添加方法为：

在**compile_softfloat_dpi.sh**文件中找到以下代码：
```
# 编译 DPI-C 源文件为目标文件
gcc -c -fPIC \
    -I"$SOFTFLOAT_INCLUDE" \
    "$DPI_SOURCE" \
    -o "$OBJ_FILE"
```
将其修改为：
```
//解决方法
# 修改后 - 确保每行末尾没有空格
gcc -c -fPIC \
    -I"$SOFTFLOAT_INCLUDE" \
    -std=c99 \
    "$DPI_SOURCE" \
    -o "$OBJ_FILE"
```
修改后再次运行开始的两行代码就可以得到结果了。


