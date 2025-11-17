Writing by Jabari

[TOC]

# 	第一章.基本语法

## 1.1C++数据类型

### 1.1.1标识符

​	程序中的每一个数据都需要有一个唯一的标识。

​	例如x = 10;y = 20;就是用x代表是10，y代表20。

​	标识符的命名规则：

​		（1）由字母、数字、下划线组成。

​		（2）不能以数字开头

​		（3）不能与系统关键字重复

​		（4）区分大小写

### 1.1.2数据类型

**整型**	

​	就是整数的类型，描述的是整数数字。

| 数据类型 | 关键字    | 空间大小                                                     | 数据范围                                                   |
| -------- | --------- | ------------------------------------------------------------ | ---------------------------------------------------------- |
| 短整型   | short     | 2byte                                                        | [-2^15,2^15 - 1]                                           |
| 整型     | int       | 4byte                                                        | [-2^31,2^31 - 1]                                           |
| 长整型   | long      | windows：4byte<br />非windows 32位：4byte<br />非windows64位：8byte | [-2^31,2^31 - 1]<br />[-2^31,2^31 -1]<br />[-2^63,2^63 -1] |
| 长长整型 | long long | 8byte                                                        | [-2^63,2^63 - 1]                                           |

**浮点型**

| 数据类型     | 关键字 | 空间大小 | 精确范围       |
| ------------ | ------ | -------- | -------------- |
| 单精度浮点型 | float  | 4byte    | 小数点后面7位  |
| 双精度浮点型 | double | 8byte    | 小数点后面15位 |

**布尔型**

​	布尔型是用来描述真假的数据类型，使用关键字bool，只占用一个字节。布尔型只有两个值true和false。

**字符型**

​	字符是用来描述一个文本内容中最小组成单位的，使用char关键字，只占用一个字节

**字符串型**

​	字符串是由若干个字符组成的一个有序的字符序列

### 1.1.3变量常量

​	变量可以修改值，常量不可以修改值。常量的关键字是const。

### 1.1.4转义字符

![image-20250622082421224](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250622082421224.png)

### 1.1.5数据类型转换

​	数据类型转换有两种：自动类型转换、强制类型转换。

​	自动类型转换：由取值范围小的数据类型，向取值范围大的数据类型转换，转换的过程不需要进行额外的操作，直接赋值就可以了，且转型完成后，不存在值的精度丢失的情况。此外，byte、short、char 类型的数据参与运算的时候，结果会自动的提升为 int 类型。

```cpp
short x = 10;
int y = x;
```

​	强制类型转换：由取值范围大的数据类型，向取值范围小的数据类型转换，转换的过程中需要进行强制的类型转换操作，且转型完成后，可能会出现精度丢失的情况。

```cpp
int x = 96;
char c = x;
```



### 1.1.6**宏定义**

​	宏定义就是在文件的头部，使用#define来定义一个标识符，用来描述一个字符串。这个标识符就被称为是宏定义，在程序中用到这个宏定义的时候，会直接替换成宏定义描述的字符串。

​	例如

```cpp
#include <iostream>

#define SUCCESS_CODE 0
#define EXPR1 2+2
#define EXPR2 (2+2)

int main()
{
	// std::cout << 0 << std::endl;
	std::cout << SUCCESS_CODE << std::endl;

	// std::cout << 2+2 << std::endl;
	std::cout << EXPR1 << std::endl;

	//std::cout << 2+2*2+2 << std::endl;
	std::cout << EXPR1 * EXPR1 << std::endl;
	
	//std::cout << (2+2) * (2+2) << std::endl;
	std::cout << EXPR2 * EXPR2 << std::endl;

	return 0;
}
```



### 1.1.7命名空间

在c++中，名称（name）可以是符合常量、变量、函数、结构、枚举、类和对象等。工程越大，名称相互冲突的可能性越大。另外，使用多个厂商的类库是，也可能导致名称冲突。因此，为了避免名称冲突，c++引入关键字namespace（命名空间）来更好的控制标识符的作用域。

例如

```cpp
#include <iostream>

namespace a 
{
	int num1 = 10;
	//命名空间可以嵌套命名空间
	namespace a1
	{
		std::string str = "hello world";
	}
}
namespace b
{
	int num1 = 20;
}
//命名空间是开放的，可以随时随地向一个命名空间中添加成员
namespace a
{
	int num2 = 30;
}

namespace constant1
{
	int MAX_SCORE = 100;
}

namespace constant2
{
	int MAX_SCORE = 150;
}

int main()
{
	//1.命名空间基础的使用
	std::cout << a::num1 << std::endl;
	std::cout << b::num1 << std::endl;
	std::cout << a::a1::str << std::endl;
	std::cout << a::num2 << std::endl;

	//2.using关键字
	using a::num1;
	std::cout << num1 << std::endl;
	std::cout << a::num2 << std::endl;

	//3.using命名空间
	using namespace a;
	std::cout << num1 << std::endl;
	std::cout << num2 << std::endl;

	using namespace std;
	cout << num1 << endl;
	cout << num1 << endl;

	//4.注意事项
	//	1.如果引用的命名空间中存在和当前命名空间中同名字的成员，默认使用当前的命名空间中的成员
	//	2.如果引用的多个命名空间中存在相同名字的成员，且当前命名空间中没有这个成员，此时会发生二义性
	const int MAX_SCORE = 200;
	cout << MAX_SCORE << endl;
	using namespace constant1;
	cout << MAX_SCORE << endl;
	cout << constant1::MAX_SCORE << endl;
	//using namespace constant1;		
	//using namespace constant2;
	//cout << MAX_SCORE << endl;		这样的话MAX_SCORE指向不明确

	return 0;
}
```



## 	1.2运算符

### 		**1.2.1.算术运算符**

​	算术运算符，可以对两个数据进行算术运算。

| 运算符 | 含义                       |
| ------ | -------------------------- |
| +      | 对两个数字进行相加的计算   |
| _      | 对两个数字进行相减的计算   |
| *      | 对两个数字进行相乘的计算   |
| /      | 对两个数字进行相除的计算   |
| %      | 对两个数字进行求余数的计算 |

​	注意事项，整型与整型的计算结果还是一个整型。例如10/3结果为3。

​	在进行计算是，结果会进行类型的提升，并将结果提示为取值范围大的数据类型。

​	（1）int与int计算结果是int

​	（2）int与long的计算结果是long

​	（3）float与long的计算结果是float

​	（4）float与double的计算结果是double

等等...

### 		**1.2.2赋值运算符**

​	赋值运算符很简单，就是一个等于号即=。例如a = 10，就是将10赋值给变量a。

### 		**1.2.3关系运算符**

​	对两个变量进行大小关系的比较，有 >,  <,  >=,  <=,  ==,  !=六种。注意关系运算后的结果是一个布尔变量。

### 		**1.2.4逻辑运算符**

​	逻辑运算，是对两个布尔类型的变量进行的逻辑操作。常见逻辑运算如下：

| 符号 | 描述                                           |
| ---- | ---------------------------------------------- |
| &    | 与运算，两真即为真，任意一个为假，结果即为假   |
| \|   | 或运算，两假即为假，任意一个为真，结果即为真   |
| !    | 非运算，非真即假，非假即真                     |
| ^    | 异或运算，相同为假，不同为真                   |
| &&   | 短路与，左边的结果为假，右边的表达式不参与运算 |
| \|\| | 短路或，左边的结果为真，右边的表达式不参与运算 |

### 		**1.2.5位运算符**

​	位运算，是作用与两个整型数字的运算，将参与运算的每一个数字计算出补码，对补码中的每一位进行类似于逻辑运算的操作，1相当于True，0相当于False。

| 符号 | 描述         |
| ---- | ------------ |
| &    | 位与运算     |
| \|   | 位或运算     |
| ^    | 位异或运算   |
| -    | 按位取反运算 |
| <<   | 位左移运算   |
| >>   | 位右移运算   |

### 		**1.2.6三目运算符**

​	三目运算符语法格式为 condition ? value1 : value2。其中condition是一个布尔类型的变量，运算逻辑是如果condition的值是True，结果是value1，condition的值是False，结果是value2.

## 1.3流程控制

### 1.3.1分支结构

​	**if**

​	语法为

```cpp
if(/*条件判断 true or false*/)
{
	//条件为true执行大括号内语句
}
```

​	**if-else**

​	条件为ture执行代码段1，条件为false执行代码段2

```cpp
if(condition)
{
	//代码段1
}
else
{
	//代码段2
}
```

​	**else if**

​	

```cpp
if(condition)
{
	//代码段1
}
else if
{
	//代码段2
}
else if
{
	//代码段3
}
else if ....		//可以有很多个
else
{}
```

​	**switch**

```cpp
switch(variable)
{
	case const1:
		statement1;
		break;
    case const2:
        statement2;
        break;
    ... ...
    case constN:
        statementN;
        break;
    default:
        statement_default;
        break;
}
```



### 1.3.2循环结构

​	**while**

​	注意要避免死循环

```
while(条件表达式)
{
	循环体
}
```

​	**do-while**

​	与while基本相同，唯一不同的是do-while先执行一次循环体再判断。

```
do
{
	循环体
}while(条件表达式)
```

**for**

​	for循环的小括号中的每一个部分都可以省略不写。但是分号不能省略。

```
for(循环起点; 循环条件; 循环步长)
{
	循环体
}
```

**break**

​	break语句用于终止某个语句块的执行。如果是循环中，作用是跳出所在的循环，如果是在switch中，作用为跳出所在的switch语句。

**continue**

​	continue作用是跳出本次循环，执行下一次循环，如果有多重循环则默认继续执执行离自己最近的循环。只能在循环结构中使用。

## 	1.4函数

### 		1.4.1函数的介绍



​	**函数的概念**

​	函数，指一段可以直接被另一端程序或代码引用的程序或代码。一个较大的程序一般应分为若干个程序块，每一个模块用来实现一个特定的功能。面向过程语言中，整个程序就是由函数（相互调用）组成的，面向对象语言中，函数就是类的组成部分，整个程序是由很多类组成的。

​	**函数的组成**

​	函数的组成要素有返回值、函数名、参数、函数体



### 		1.4.2函数的基础使用

​		**函数的定义**

```cpp
//函数定义的语法为：
//返回值类型 函数名字（参数列表）
//{
//	函数体
//}
//返回值类型：表示函数执行的结果
//函数名字：遵循标识符的命名规则
//参数列表：定义若干个参数的部分
//函数体：函数的功能实现
//例如
void sayHello()
{
    cout << "Hello!" << endl;
}
```

**	**函数的调用****

函数在定义完成后，不会自动的执行，需要去调用这个函数才能执行。例如

```cpp
#include <iostream>

using namespace std;

void sayHello()
{
	cout << "Hello!" << endl;
}
int main()
{
	sayHello();
	return 0;
}
```

​		**参数的介绍**

​	有时候在调用函数时需要有一些数据的传入，调用方必须传入指定的数据，才能够完成对应的功能。如果需要将函数之外的一些数据带入到函数内部中，最常见的做法就是直接通过参数来实现。

**		**参数的定义****

​	参数其实就是一个变量，只不过，这个变量有一些不同：

​		（1）定义的位置不同，参数是定义在函数的参数列表小括号中的。

​		（2）明确的数据类型，即便是相同类型的参数，也需要为每一个参数明确自己的类型。

​	例如

```cpp
void add(int num1, int num2)
{
    cout << num1 << num2 << num1 + num2
}
```

如果一个函数时有参的函数，那么在调用时必须要明确参数的值是什么。例如

```cpp
void add(int num1, int num2)
{
    cout << num1 << num2 << num1 + num2
}

int main()
{
	add(10,20);		//调用的时候必须带上参数
	
	return 0;
}
```

形参：在定义函数的时候，小括号中定义的参数。

实参：在调用函数的时候，小括号中定义的参数。

传参：在调用函数的时候，用实参给形参赋值，这样的过程叫做传参。

**	**返回值的介绍****

​	可以借助返回值来将函数内的数据返回到函数外。

例如下面代码，这个函数的返回值就是一个int数据。

```cpp
//设计一个函数，计算一个数字的绝对值
int abs(int number)
{
	return number > 0 ? number : -number;
}
```

在函数中return的作用有：

​	（1）后面跟上一个值，作为函数的执行结果，也就是返回值。

​	（2）结束一个函数的执行。

注意事项：

​	（1）在返回值不是void的函数中，函数执行结束之前，必须要使用return明确一个返回的结果

​	（2）在返回值是void的函数中，可以使用return关键字，此时仅表示结束函数的执行

### 		1.4.3函数的高阶使用

**	**函数的参数默认值****

​	在定义一个函数时，可以给参数设置一个默认的值，例如下面代码，这里num2是有默认值的，在调用函数时，可以不给num2设置实参，也可以设置。如果不设置就是默认值。

```cpp
int add(int num1, int num2 = 10)
{
	return num1+num2
}
int main()
{
    add(10);		//不给num2设置实参，此时num2是10
    add(10,20);		//给num2设置实参，此时num2是20
    
    return 0 ;
}
```

这里需要注意的是，有默认值的参数必须放在参数列表的末尾。例如下面代码就是错误的。

```cpp
int add(num1 = 10,num2)
{
	return num1 + num2;
}
int main()
{
	add(10);		//这里就有问题了，因为系统不知道这个10是赋值给num1还是num2
	return 0;
}
```

​	**函数的重载Overload**

​	如果在一个类中的多个函数，满足函数名相同，参数不同(数量，类型不同)的条件，则这两个函数就构成了重载关系。重载只与函数的名字、参数有关系，与返回值没有关系。例如

```cpp
//重载函数定义
int add(int num1, int num2)
{
	return num1 + num2;
}
double add(double num1,double num2)
{
	return num1 + num2;
}
double add(double num1,int num2)
{
	return num1 + num2;
}
int main()
{
    //区分调用不同的重载方法，应该从实参入手
    cout << add(10,20) << endl;
    cout << add(10.0,20.0) << endl;
    cout << add(10.0,20) << endl;
    
    return 0;
}
```

**调用其他文件中的函数**

​	一般大型的项目不止一个文件来组成，很多时候需要跨文件的调用、访问的。由于.cpp中的文件无法直接跨文件访问，因此我们需要添加一个.h的头文件，在头文件中添加函数的声明部分即可。需要使用的时候，直接使用#include来包含指定的头文件即可调用。例如

```cpp
//头文件
//文件名：qwe.h
int qwe_abs(int num);
int qwe_sum(int num1, int num2);
```

```cpp
//执行函数的文件
//文件名: qwe.cpp
int qwe_abs(int num)
{
    return return num >= 0 ? num : -num;
}
int qwe_sum(int num1,int num2)
{
    return num1 + num2;
}
```

```cpp
//在该文件中调用qwe.cpp中的函数
//文件名：test.cpp
#include <iostream>
#include "qwe.h"		//导入头文件的时候，如果需要导入自己定义的，只能用双引号

using namespace std;

int main()
{
	cout << qwe_abs(-10);
    cout << qwe_sum(10,20);

	return 0;
}
```



## 	1.5指针与引用

### 		**1.5.1指针的介绍**

​	每一个开辟的内存空间都是有一个唯一的地址的，这样的地址就称为指针。它存储的是另一个变量的内存地址，而不是直接存储数据值。

### 		1.5.2指针变量的定义

```cpp
#include <iostream>

using namespace std;

int main()
{
    int num = 10;
    int* p = &num;			//可以用&来访问变量的地址
    cout << p << endl;		//输出的结果是一个地址
    cout << *p << endl;		//输出的结果是10
    *p = 20;				//修改指针变量指向的地址中的值
    cout << *p <<endl;		//输出的结果是20
    
    return 0;
}
```

### 		1.5.3空指针与野指针

​	空指针指的是没有储存任何内场地址的指针变量，一般用NULL来表示一个空的地址。通常情况下空指针可以对指针变量进行初始化。

```cpp
int* p = NULL;
```

​	野指针是指指针中储存有一个内存地址，但是这个地址指向的空间已经不存在了的指针。这种情况下指针中储存的地址已经没有任何意义了，因此称为野指针。

```cpp
int* p = (int*)0x1234;
cout << p << endl;		//输出结果为地址0x1234	
cout << *p2 << endl;	//无法输出，因为这个地址的内存空间不存在
```

​	程序设计时一般要避免空指针和野指针

### 		**1.5.5常量指针与指针常量**

​	常量指针：

​		（1）const放在*之前，表示常量指针，即常量的指针

​		（2）指针的指向是可以修改的，但是不能通过指针来修改指向空间的值

​	指针常量：

​		（1）const放在*之后，表示指针常量，即指针是一个常量。

​		（2）可以通过指针来修改指向空间的值，但是不能修改指针的地址指向。

```cpp
#include <iostream>

using namespace std;

int main()
{
	int num1 = 10;
	int num2 = 20;
    //常量指针：
    const int* p = &num1;
	cout << *p << endl;
	p = &num2;
	cout << *p << endl;
    //*p = 200;		//这条语句错误
    //指针常量：
    int* q = &num1;
	cout << *q << endl;
	*q = 200;
	cout << *q << endl;
	//q = &num2;		//这条语句错误
    
    	return 0;
}
```

### 		1.5.6引用

​	引用是变量的别名，它提供了一种方式让不同的标识符指向同一个内存地址。引用常用于函数参数传递、操作符重载和简化代码。基本语法为  Type& ref = val；

​	注意：

​		（1）&在引用中不是求地址运算，而是起标识符作用。

​		（2）类型标识符是目标变量的类型。

​		（3）必须在声明引用变量是进行初始化。

​		（4）引用初始化之后不能改变。

​		（5）不能有NULL引用，必须确保引用是和一块合法的存储单元关联。

​		（6）可以建立对数组的引用。

```c++
#include <iostream>

using namespace std;

int main()
{
	int num = 10;
	int& a = num;								//num是int型，所有这里是int& a
	cout << "a = " << a << " num = " << num << endl;//输出a与num的值，输出结果相同
	cout << "&a = " << &a << " &num = " << &num << endl;//输出a与num地址，输出结果相同
	num = 100;												//修改num的值
	cout << "a = " << a << " num = " << num << endl;	//修改num的值后a的值也会改变

	return 0;
}
```

​		引用的本质实际上就是一个指针常量

```cpp
int main()
{
	int n = 10;
	
	int& p = n;		//这里相当于是int* const p = &n;因此p和n引用的是同一块空间，并且为什么p不能修改
	
	return 0;
}
```



## 	1.6数组

### 			1.6.1数组的介绍

​		数组其实就是一个数据容器，里面可以存储若干个相同的数据类型。它的特性有以下两点：（1）数组可以用来存储任意数据类型的数据，但是所有的数据需要时相同的数据类型。（2）数组是一个定长的容器，一旦完成初始化，长度将不能改变。

​		数组中存储的每一个数据称为数组中的元素。数组的容量称为长度，即数组中可以存储多少个元素。遍历是指依次获取数组中的每一个元素。

### 			1.6.2数组的基础使用

​		数组的定义方式

```cpp
int array1[10];		//这种定义方式是不安全的，未初始化。
int array2[10] = {1,2,3,4,5,6,7,8,9,10};	//定义了一个长度为10的数组并填充数据
int array3[10] = {1,2,3,4,5};	//定义一个长度为10的数组，前五个填充1,2,3,4,5，后面的默认为0.
int array4[] = {1,2,3,4,5};		//定义一个数组未指明长度，但是填充了5个元素，因此长度为5
```

​		数组的元素访问

```cpp
int array[10] = {1,2,3,4,5};
int len = sizeof(array)/sizeof(int);		//计算数组的长度
for(i = 0; i <= 9; i++)
{
	cout << array[i] << endl;		//访问数组中的元素，注意使用下标访问数组元素时，一定不要越界，比如array[10]就越界了
}
```

### 			**1.6.3数组的内存分析**

​		数组在内存中进行空间开辟时，并不是开辟一个整体的空间，而是开辟了若干个连续的空间。

```cpp
	
//定义一个长度为10的数组
//这里array表示的是数组中首元素的内存地址，可以通过*array来访问数组中的首元素即第0个元素
//由于是一个int数据类型的数组，因此数组中每个元素的大小是4个字节，所以可以通过array的内存地址+ 1来访问第1个元素。之所以不 + 4是因为c++将这一个元素的内存占用空间作为一个单位。
int main()
{
	int array[10] = { 1,2,3,4,5 };
	
	for (int i = 0; i <= 9; i++)//遍历数组中的元素的地址,可以发现相邻元素间地址差4个字节
	{
		cout << &array[i] << endl;
	}

	cout << *array << endl;		//访问数组中的首元素即第0个元素
    cout << *array + 4			//访问数组中的第1个元素
	
	return 0;
}

```

​	注意，当数组作为参数传递到一个函数中的时候，传递的只是首元素的地址！也就是一个指针。

```cpp
void printArray(int* array)			//或者void printArray(int array[])	
{
	cout << sizeof(array) / sizeof(int);
}
int main()
{
    int array[5] = {1,2,3,4,5} ;
    printArray(array);						//输出结果是2，因为一个指针的大小是8个字节
    
    return 0;
}
```

### 			1.6.4数组的浅拷贝与深拷贝

​		浅拷贝：也就是地址拷贝，拷贝到的是数组的首元素地址。由于拷贝的只是地址，因此得到的数组与原来的数组指向的其实是同一块空间。所有对任何一个数组中的元素进行操作，都会对另一个数组产生同样的影响。

​		深拷贝：定义一个新的数组，长度与原来的数组相同，将原来数组中的每一个元素依次拷贝到新的数组中。深拷贝得到的是一个全新的数组，只不过这个数组里的元素与原来数组的元素相同，但是并不是同一块空间。

```cpp
int array[] = {1,2,3,4,5};		//定义一个长度为5的数组
int* array_copy1 = array;		//浅拷贝
int array_copy2[5];				//深拷贝
for(int i = 0; i < 5; i++)	
{
	array_copy2[i] = array[i];
}
```

### 			1.6.5二维数组

​		数组其实就是一个容器，存储着若干的数据。数组可以存储任意类型的元素，如整数、浮点数、字符串，因此数组当然也可以存储数组。一个数组中存储的元素类型是数组，那么这样的数组就是二维数组。

​		通常二维数组可以比作一个行列矩阵，二维数组有多少元素就相当于有多少行，二维数组里的一维数组有多少个元素就相当于有多少列。二维数组的定义方式有

```cpp
int main()
{
	//定义二维数组
	//数据类型 标识符[行数][列数]
	int array1[3][5];

	//数据类型 标识符[行数][列数] = {{vla1,vla2,vla3,...}, {vla1,vla2,vla3,...}, ...};
	int array2[3][5] = {
						{1,2,3,4,5},
						{1,2,3},		//后面补0
						{1,2,3,4,5} 
						};

	//数据类型 标识符[行数][列数] = {vla1,vla2,vla3,...}
	int array3[3][5] = { 1,2,3,4,5,10,20,30,40,50,100,200,300,400,500 };
    //如果元素不够的情况下，后面的元素自动补0

	//数据类型 标识符[][列数] = {val1,val2,val3...}
	int array4[][5] = { 1,2,3,4,5,10,20,30,40,50,100,200,300,400,500 };
	
	//访问二维数组和一维数组相同，使用下标。
	cout << array4[1][2] << endl;
```





# 第二部分 面向对象

## 			2.1面向对象介绍

### 				**2.1.1面向对象与面向过程**

​		面向过程：着眼于问题是如何一步步解决的，然后亲力亲为的解决问题。

​		面向对象：着眼于找到一个能够帮助解决问题的实体，然后委托这个实体来解决问题。

### 				**2.1.2类与对象**

​		在面向对象编程思想中，着眼于找到一个能够帮助解决问题的实体，然后委托这个实体来解决问题。在这里，这个具有特定的功能，能够解决特定问题的实体，就是一个对象，有若干个具有相同的特征和行为的对象组成的集合，就是一个类。类是对象的集合，对象是类的个体。

## 			2.2类的设计与对象的建立

### 				**2.2.1类的设计**

```cpp
#include <iostream>

using namespace std;

//使用关键字class来描述一个类
//类是若干个具有相同的特征和功能的对象的集合，在类中写所有的对象共有的特征和行为
//，其中特征使用变量来定义，在这里称为属性，行为用函数来表示。

//访问权限：
//用来修饰属性、行为可以在什么位置访问。
//private:私有权限，只能够在当前的类中访问，其他位置都不可以访问。
//protected:保护权限、类外不能访问，可以在当前类和子类中访问。
//public:公开权限，可以在任意位置访问。

//注意事项：
//	类中定义的属性和行为默认都是私有权限的。
//	如果要在类外访问，需要修改其权限为public。
class Person
{
public:
	string name;
	int age;
	string gender;
	int score;

	void eat()
	{
		cout << "人类都会吃饭" << endl;
	}

	void sleep()
	{
		cout << "人类都会睡觉" << endl;
	}
protected:
private:
};
```

### 				2.2.2对象的创建

```cpp
int main()
{
	//创建对象：从一个类中，找到一个个体
	// 1.直接创建对象，隐式调用
	Person xiaohong;
	//2.显示调用
	Person xiaoming = Person();
	//3.关键字new
	Person* xiaoli = new Person();

	return 0;
}
```

|            | 使用new                | 没有使用new    |
| ---------- | ---------------------- | -------------- |
| 内存方面   | 在堆空间开辟           | 在栈空间开辟   |
| 内存管理   | 需要手动使用delete销毁 | 不需要手动销毁 |
| 属性初始化 | 自动有默认的初始值     | 没有初始值     |
| 语法       | 需要用类*来接受变量    | 不需要使用*    |
| 成员访问   | 通过->访问             | 通过.访问      |

### 				2.2.3成员访问

​			访问类中的成员，如属性、函数。

```cpp
//成员访问:访问类中的成员（属性、函数）
//需要使用对象来访问
xiaoming.name = "xiaoming";
xiaoming.age = 23;
xiaoming.gender = "male";
xiaoming.score = 100;
cout << xiaoming.name << endl;
cout << xiaoming.age << endl;
cout << xiaoming.gender << endl;
cout << xiaoming.score << endl;
xiaoming.sleep();
xiaoming.eat();

(*xiaoli).name = "xiaoli";		//如果是一个对象指针的话，可以先通过*找到堆空间，在通过.访问
xiaoli->age = 18;
cout << xiaoli->name << endl;
cout << (*xiaoli).age << endl;
```

### 				**2.2.4类是一种自定义的数据类型**

​			可以在一个类的属性中添加另一个类的对象

```cpp
class Dog
{
public:
	string name;
	int age;
};

//类是一种自定义的数据类型
class Person
{
public:
	string name;
	int age;
	Dog pet;		//Person的属性中又pet对象

	//如果用对象指针作为一个类的属性，需要注意空间问题，这里的otherPet只是一个空指针。
	Dog* otherPet;
};
int main()
{
    Person xiaoming;
    cout << xiaoming.otherPet << endl;		//输出为0000000000000000，一个空指针
    xiaoming.otherPet = new Dog();	//给xiaoming.otherPet开辟一个空间
    
    return 0;
}
```

### 				2.2.5在类外或其他文件实现类函数

​			在类外定义类函数

```cpp
class Person
{
public:
	void sleep();
};

//类外定义类函数
void Person::sleep()		//语法格式为 type class::函数名()
{
	cout << "Person sleep" << endl;
}
```

​			在其他文件中实现类函数，这有点类似于1.5.3.4调用其他文件中的函数。首先新建一个C++类，然后会自动生成头文件和一个cpp文件。![image-20250618223232514](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250618223232514.png)

​			在头文件中可以定义类的属性，类中的函数的具体实现可以在刚才自动生成的cpp文件中定义。例如

![image-20250618223342168](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250618223342168.png)

![image-20250618223417839](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250618223417839.png)

​			然后就可以在文件中调用了。

```cpp
#include <iostream>
#include "Dog.h"		//和1.5.3.4中调用文件外函数一样

using namespace std;

int main()
{
	Dog xiaobai;
	xiaobai.bark();

	return 0;
}
```

### 				2.2.6静态

​			**静态**

​		我们在类中定义成员的时候（函数、属性），可以使用关键字static来修饰，表示静态。在一个类中被static修饰的成员成为静态成员，可以分为静态属性、静态函数。

 			**静态属性**

​		静态的属性内存是开辟在全局区的，与对象无关，并不隶属于对象。在程序编译的时候就已经完成了空间的开辟与初始化的赋值操作，并且在程序运行的整个过程中是始终保持的。

​		静态属性的空间开辟早于对象的创建，并且静态属性不隶属于对象，而是被对象所共享。所有，如果希望一个属性时可以被所有对象共享的，就可以设置为静态的属性。

```cpp
#include <iostream>

using namespace std;

class A {};

class MyNumber
{
public:
	//在类中定义的静态成员，必须在类内定义，类外进行初始化赋值
	static int a;
	//static int a = 10;		这句错误
	//若果是静态常量，且数据类型是整型{int, short, long, long long,char,bool}
	//允许在定义的时候就初始化赋值
	const static int b = 1;
	//const static double c = 1.3;  这句错误
	const static double c;

	static void show()
	{
		cout << "静态函数被调用了" << endl;
	}
};
//在类外，对静态成员进行初始化操作
int MyNumber::a = 10;
const double MyNumber::c = 1.3;

int main()
{
	//如何访问静态成员
	//1.可以使用对象来访问，但是切记不同的对象访问到的其实是同一块空间。
	MyNumber number1;
	MyNumber number2;
	cout << number1.a << endl;		//输出值相同
	cout << number2.a << endl;
	cout << &number1.a << endl;		//会发现这俩地址一样
	cout << &number2.a << endl;
	
	//修改number1.a后number2.a也会改变
	number1.a = 100;
	cout << number1.a << endl;
	cout << number2.a << endl;
	
	number1.show();

	//2.可以使用类来访问。
	MyNumber::a = 1000;
	cout << MyNumber::a << endl;
	cout << &MyNumber::a << endl;
	MyNumber::show();

	return 0;
}
```

## 		2.3构造与析构

### 					2.3.1构造函数的介绍

​		构造函数是一个比较特殊的函数，我们在使用一个类的对象的时候，需要为其分配空间。分	配空间完成之后，一般会对创建的对象的属性进行初始化操作，而这个过程就可以在构造函数中	来完成了。构造函数时一个函数，是在对象创建时触发，用来对对象的属性进行初始化操作。

​	**2.3.2构造函数的定义**

​		（1）构造函数的名字必须和类的名字相同。（2）构造函数不能写返回值类型。（3）构造函数可以有不同的重载。

```cpp
#include <iostream>

using namespace std;

class Person
{
public:
	Person()
	{
		cout << "Person类的无参构造函数执行了" << endl;
	}
	Person(int age)				//重载
	{
		cout << "Person类的有参构造函数执行了" << endl;
	}
	Person(int age, int score)	//重载
	{
		cout << "Person(int int)构造函数执行了" << endl;
	}
};
```

### 			2.3.3构造函数的使用

```cpp
int main()
{
	//构造函数的调用是在创建对象的时候调用的
	//显示调用
	Person xiaoming1 = Person();
	Person xiaoming2 = Person(10);
	Person xiaoming3 = Person(10, 20);
	//缩写方式
	Person xiaoming4;		//使用缩写的方式调用无参的构造函数创建对象，不能写小括号。
	Person xiaoming5 = (10);
	Person xiaoming6 =  (10, 20 );
	
	//隐式调用	不需要写Person()，直接将所有参数写入一对大括号中
	//系统会根据大括号中的实参的数量和类型，找到与之匹配的构造函数调用
	Person xiaoming7 = {};
	Person xiaoming8 = { 10 };
	Person xiaoming9 = { 10,20 };

	return 0;
}
```

​		执行结果为![image-20250619001909799](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250619001909799.png)

​		explicit关键字是用来修饰构造函数的，写在构造函数之前，表示无法通过隐式调用来访问这个构造函数。

```cpp
class Person
{
public:
	explicit Person(int age)		//这个构造函数就无法通过隐式调用来访问了。
	{
		cout << "Person类的有参构造函数执行了" << endl;
	}
};
```

​		注意事项：

​			（1）如果我们没有在一个类中写任何的构造函数，系统会为其添加一个public权限的无参构造函数，可以让我们创建对象。

​			（2）如果我们给一个类写构造函数了，此时系统将不再提供任何默认的构造函数。

### 			2.3.4构造函数的初始化列表

```cpp
#include <iostream>

using namespace std;

class Person
{
public:
	string name;
	int age;
	string gender;
	int score;

	Person() : name(""), age(0), gender(""), score(0) {}
        //小括号里是形参，小括号外是属性，例如name（n）
	Person(string n, int a, string g, int s) : name(n), age(a), gender(g), score(s) {}
     //小括号里是形参，小括号外是属性，例如name（name）
	Person(string name, int age, string gender) : name(name), age(age), gender(gender) {}

};

int main()
{
	Person xiaoming("xiaoming", 19, "male", 100);
	cout << xiaoming.name << endl;
	cout << xiaoming.age << endl;
	cout << xiaoming.gender << endl;
	cout << xiaoming.score << endl;

	Person xiaohong("xiaohong", 18, "famale");
	cout << xiaohong.name << endl;
	cout << xiaohong.age << endl;
	cout << xiaohong.gender << endl;

	return 0;
}
```

### 			2.3.5拷贝构造函数

​		c++中的构造函数按照参数可以分为有参构造和无参构造，按照类型可以分为普通构造和拷贝构造。

​		拷贝构造就是根据一个对象，拷贝出另外一个对象。新的对象与原来的对象的地址不同，但是属性值是相同的。系统会自动提供拷贝构造函数，当然也可以自己写。

```cpp
#include <iostream>
using namespace std;
class Person
{
public:
	string name;
	int age;
	Person() {}
	Person(string name, int age) : name(name), age(age) {}

	//自己写的构造函数
	//Person(const Person& p)			//引用
	//{
	//	cout << "拷贝构造函数被调用了" << endl;;
	//	name = p.name;
	//	age = p.age + 1;
	//}
};
int main()
{
	Person xiaoming("xiaoming", 19);
	//创建了一个新的对象xiaohong，xiaohong和xiaoming指向不同空间，但是属性值相同
	//类似于int x = 10;  int y = x;
	Person xiaohong = xiaoming;
	cout << xiaoming.name << endl;
	cout << xiaoming.age << endl;
	cout << xiaohong.age << endl;
	cout << xiaohong.name << endl;
	cout << &xiaoming << endl;
	cout << &xiaohong << endl;
	return 0;
}
```

### 			2.3.6析构函数

​		析构函数时对象生命周期的终点，在对象空间被销毁之前调用。在析构函数中，一般进行资源的释放，堆内存的销毁。

​		析构函数使用~开头，并且不能有参数。

```cpp
#include <iostream>
using namespace std;
class Person
{
public:
	int a;
	int* p;
	//析构函数：使用~开头，并且不能有参数
	~Person()
	{
		cout << "Person类的析构函数被调用了" << endl;
	}
};
void test()
{
	Person person;
}
int main()
{
	test();				//test执行完后person就被释放了
	system("pause");
	return 0;
}
```

### 		2.3.7浅拷贝与深拷贝

​		浅拷贝：在拷贝构造函数中，直接完成属性的值拷贝操作。

​		深拷贝：在拷贝构造函数中，创建出来新的空间，使得属性中的指针指向的是一个新的空间。

## 	2.4this指针

### 		2.4.1this是什么

​			在C++中，this是一个指针，用来指向当前对象的。

​			一个类可以有多个对象，非静态属性时属于对象的，那么不同的对象的非静态属性可能不同，那在调用函数时到底要返回到那个对象的非静态属性呢？这时就可以用this指针。

```cpp
#include <iostream>
using namespace std;
//this：是一个用来指向当前对象的指针
//当前对象：谁调用这个函数，this就指向谁
//理论上来说，在类的内部，访问当前类中的（非静态）成员时，应该都用this->来访问
//实际上，绝大多数情况下，this->都是可以省略不写的。
//this只有在一种情况下不能省略：在一个函数内出现了局部变量和属性同名字的情况。
//为了区分局部变量和属性，需要显式的使用this->来访问属性。
class Person
{
public:
	int age;
	Person()
	{
		age = 0;
	}
	Person(int age) : age(age) {}
	int getAge()		//调用函数时，返回当前对象的age
	{
		return this->age;
	}
};
int main()
{
	Person xiaoming(20);
	cout << xiaoming.getAge() << endl;
	Person xiaohong(18);
	cout << xiaohong.getAge() << endl;
	return 0;
}
```

### 		 2.4.2设计函数返回对象本身

​			可以使用this来设计函数，返回对象本身。 

```cpp
#include <iostream>

using namespace std;

class MyNumber
{
private:
	int n;

public:
	MyNumber() : n(0) {}
	MyNumber(int n) : n(n) {}

	//设计一个函数，累加上一个数字，返回对象本身
	MyNumber& add(int n)
	{
		this->n += n;
		return *this;	//this是一个指针，指向当前对象，通过*this解引用，返回对象本身
	}

	MyNumber& minus(int n)
	{
		this->n -= n;
		return *this;
	}

	void display()
	{
		cout << n << endl;
	}
};

int main()
{
	MyNumber num;
	//每一次函数调用，都得到了对象本身
	num.add(10).add(1).minus(5).add(1).display();

	return 0;
}
```

### 		2.4.3常函数与常对象

​			const可以修饰类中的成员函数，表示这个函数是一个常函数。在一个函数的参数括号后面加上const就表示常函数。

​			常对象是在创建对象时使用关键字const。常对象可以读取任意属性的值，但是不允许修改。常对象只能调用常函数，不能调用普通函数。

​			如果非要在常函数中修改属性，或者在常对象中修改属性，那么可以使用mutable。mutable是用来修饰属性的，表示可变。例如 mutable int score;这时就可以在常函数或常对象中对属性score进行修改了。

```cpp
#include <iostream>

using namespace std;

class Person
{
public:
	string name;
	int age;
	int score;

public:
	Person() :name(""), age(0), score(0) {}
	Person(string name, int age, int score) :name(name), age(age), score(score) {}

	//定义一个常函数
	void fixPerson(string newName, int newAge, int newScore) const
	{
		//name = newName;		//下面四行代码会报错，因为这是一个常函数
		//age = newAge;			//在常函数中不允许修改属性值
		//score = newScore;		//常函数中不允许调用普通函数，只能调用其他常函数
		//display();
	}

	void display()
	{
		cout << "name = " << name << ",age = " << age << ",score = " << score << endl;
	}

};

int main()
{
	const Person xiaoming("xiaoming", 20, 100);	//定义一个常对象
	//试图修改常对象的属性，会报错,调用常函数也会报错
	//xiaoming.age = 22;
	//xiaoming.name = "xiaohong";
	//xiaoming.score = 200;
	//xiaoming.display();

	return 0;
}
```



## 2.5友元

### 2.5.1友元是什么

​	类的主要特点之一是数据隐藏，即类中不是public部分的成员在类的外部无法访问。但是有的时候需要在类的外部访问类的私有成员，这时就可以使用友元。

​	友元函数是一种特权函数，c++允许这个特权函数访问类的私有成员。

### 2.5.2全局函数做友元

```cpp
#include <iostream>

using namespace std;

class Home
{
	//将一个全局函数作为友元
	friend void goToBedRoom(Home* home);

public:
	string livingRoom = "客厅";

private:
	string bedRoom = "卧室";

};

//全局函数
void goToBedRoom(Home* home)
{
	cout << home->livingRoom << endl;
	//也可以访问私有成员
	cout << home->bedRoom << endl;
}

int main()
{
	//创建对象
	Home home;
	goToBedRoom(&home);

	return 0;
}
```

### 2.5.3成员函数做友元			

```cpp
#include <iostream>

using namespace std;

//这里要提前声明有Home类，因为GoodFriend中的函数用到了Home
class Home;

class GoodFriend
{
public:
	//函数的内容要在外部添加，因为要访问的BedRoom在这个类的下面，在Home类中
	//在这里添加的话，编译器会不通过
	void visitBedRoom(Home* home);
};

class Home
{

	//将GoodFriend中的成员函数作为友元
	friend void GoodFriend::visitBedRoom(Home* home);

public:
	string livingRoom = "客厅";

private:
	string bedRoom = "卧室";

};

void GoodFriend::visitBedRoom(Home* home)
{
	cout << home->bedRoom << endl;
}

int main()
{
	Home home;
	GoodFriend xiaoming;
	xiaoming.visitBedRoom(&home);

	return 0;
}
```



### 2.5.4类做友元

​	类作为友元，这个类中的所有成员函数都可以访问另一个类的私有成员。

```cpp
#include <iostream>

using namespace std;

class Home
{
	//将类作为友元
	friend class Friend;
public:
	string livingRoom = "客厅";

private:
	string bedRoom = "卧室";

};

class Friend
{
public:

	void visit1(Home* home)
	{
		cout << home->livingRoom << endl;
		cout << home->bedRoom << endl;
	}

	void visit2(Home* home)
	{
		cout << home->livingRoom << endl;
		cout << home->bedRoom << endl;
	}

};

int main()
{
	Home home;
	Friend xiaoming;
	xiaoming.visit1(&home);		//两个函数都可以访问私有成员
	xiaoming.visit2(&home);

	return 0;
}
```

## 2.6运算符重载

### 	2.6.1什么是运算符重载

​		运算符重载就是对已有的运算符进行重新定义，赋予其另一种功能，以适应不同的数据类型。它只是一种语法上的方便，实际上是一种函数的调用方式。

​		定义重载的运算符就像定义函数，只是该函数的名字是 operator@，这里的 @代表了被重载的运算符。

### 	2.6.2可重载的运算符

​		几乎所有的运算符都可以重载，但运算符重载的使用时相当受限制。特别是不能改变运算符优先级，不能改变运算符的参数个数。

![image-20250622112456329](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250622112456329.png)

### 2.6.3重载运算符+

​		这里实例重载运算符+，重载其他运算符是一样的道理。

```cpp
#include <iostream>
using namespace std;

class Point
{
public:    
    int x;
    int y;
    
    Point():x(0),y(0){}
    Point(int x, int y) : x(x),y(y){}
    
    //重载运算符+
    //在类内以成员函数的形式重载运算符，参数的数量应该少一个。此时参与运算的是this， p
    Point operator+(const Point& p)
    {
        return Point(x+p.x,y+p.y);
    }
};

//全局函数重载运算符+
Point operator+(Point& p1, Point& p2)
{
    return Point(p1.x + p2.x, p1.y + p2.y);
}

int main()
{
    //创建两个Point对象
    Point p1(10,20);
    Point p2(20,30);
    
    Point p3 = p1 + p2;
    cout << p3.x << endl;
    cout << p3.y << endl;
    
    return 0;
}
```



## 2.7封装

​	面向对象编程思想中有三大特性：封装、继承、多态。

​	广义上的封装：将一些功能相近的类放入一个模块中。

​	狭义上的封装：通过对具体属性的封装实现，把对成员变量的访问进行私有化，让他只能在类内部可见，通过公共的方法简介实现访问。这样做可以提高代码的安全性、复用性和可读性。例如

```cpp
#include <iostream>

using namespace std;

class Person
{
//将age属性私有化，不希望外界可以访问，但是可以通过公共方法访问
private:
	int age;

public:
	Person() : age(20) {};

	//获取年龄函数
	void getAge()
	{
		cout << this->age << endl;
	}
	
	//修改年龄函数
	void setAge(int age)
	{
		if (age >= 0 && age <= 150)		//判断年龄是否合理
		{
			this->age = age;
		}
	}
};

int main()
{
	Person xiaoming;
	xiaoming.getAge();				//输出为20
	xiaoming.setAge(30);			//年龄合理
	xiaoming.getAge();				//输出为30
	xiaoming.setAge(100000);		//年龄不合理，年龄不会修改
	xiaoming.getAge();				//输出为30

	return 0;
}
```

## 2.8继承

### 2.8.1继承是什么

​	C++中通过继承来提高代码的复用性、拓展性。程序中的继承，是类与类之间的特征和行为的一种赠予或获取。一个类可以将自己的属性和方法赠予其他的类，一个类也可以从其他的类中获取他们的属性和方法。

​	两个类之间的继承，必须满足 is a 的关系。两个类之间，A类将属性和特征赠予B类，此时A类是父类，B类是子类，两者关系是子类继承自父类。

### 2.8.2继承的语法

​	继承的语法：	class 子类类名: 继承方式 父类类名

```cpp
#include <iostream>

using namespace std;

class Animal
{
public:
	int age;
	void walk()
	{
		cout << "Animal Walk" << endl;
	}
};
//继承的语法：	class 子类类名: 继承方式 父类类名
class Dog : public Animal
{};

int main()
{
	Dog wangcai;
	wangcai.walk();		//输出Animal Walk
	return 0;
}
```

### 2.8.3继承的特点

​	（1）父类中所有的非静态成员（除构造函数和析构函数）都可以继承给子类。

​	（2）一个类可以被多个类同时继承。

​	（3）在C++中一个类可以有多个父类，称为多继承

​	（4）一个类在继承了父类的同时，也可以被他的子类继承，这是子类的子类也会继承父类的成员。

```cpp
//一个类可以被多个类同时继承
class A {};
class B: public A {};
//多继承
class C {};
class D {};
class E: public C, public D {};
//
class Dog
{
public:
    void bark()
    {
        cout << "汪汪汪" << endl;
    }
}
class BigDog : public Dog {};
class Labuladuo : public BigDog {};

int main()
{
    Labuladuo whiteLabuladuo;
    whiteLabuladuo.bark();
}
```

### 2.8.4三种继承的方式

​	在C++中，继承有三种方式：公共继承、保护继承、私有继承。其实这是一个 访问权限的问题。在C++中，默认使用的是私有权限。

​	公共继承：继承到父类中的属性（函数），保留原有的访问权限。

​	保护继承：继承到父类中的属性（函数），超过protected权限部分，将降为protected权限。

​	私有权限：继承到父类中的属性（函数），访问权限都为private权限。

### 2.8.5继承中的构造和析构函数

​	子类对象创建时需要先调用父类中的构造函数，来初始化继承的成员。默认调用是父类中的无参构造函数。例如下面的代码会先输出Animal类中的无参构造函数被执行了，再输出Dog类中的无参构造函数被执行了。

```cpp
#include <iostream>
using namespace std;
class Animal
{
public:
	int age;
	//Animal的无参构造函数
	Animal() : age(0) 
	{
		cout << "Animal类中的无参构造函数被执行了" << endl;
	}
	//Animal的有参构造函数
	Animal(int age) : age(age) 
	{
		cout << "Animal类中的有参构造函数被执行了" << endl;
	}
};
class Dog : public Animal
{
public:
	Dog()
	{
		cout << "Dog类中的无参构造函数被执行了" << endl;
	}
};
int main()
{
	Dog dog;
	return 0;
}
```

​	如果说父类中没有无参构造函数，或者父类中的无参构造函数是私有的，这时会报错。因为子类对象在创建时需要默认先调用父类中的无参构造函数。一般有两种解决方法。一是给父类添加无参构造函数或者修改访问权限，二是在子类的构造函数中，显式调用父类中存在的对象。第二种方法如下面代码所示。

```cpp
class Animal
{
public:
	int age;
	//Animal的有参构造函数
	Animal(int age) : age(age) 
	{
		cout << "Animal类中的有参构造函数被执行了" << endl;
	}
};

class Dog : public Animal
{
public:
	Dog() : Animal(10)		//显式调用
	{
		cout << "Dog类的无参构造函数被执行了" << endl;
	}
};
```

​	子类对象在销毁的时候，先调用自己的析构函数，再调用父类的析构函数。

### 2.8.6父类子类中出现同名字的成员

​	如果父类子类中出现了同名字的成员（函数、属性），子类会将从父类继承到的成员隐藏起来，子类对象直接访问，访问的是子类中的成员。如果想要访问父类中继承下来的成员，需要显式指定。

```cpp
#include <iostream>

using namespace std;

class Animal
{
public:
    int age = 10;

    void showAge()
    {
        cout << "父类中的age = " << age << endl;
    }
};
class Dog : public Animal
{
public:
    int age = 20;
    void showAge()
    {
        cout << "子类中的age = " << age << endl;
    }
};
int main()
{
    Dog wangcai;
   //调用子类中的成员
    cout << wangcai.age << endl;
    wangcai.showAge();

    //调用父类中的成员	显式指定
    cout << wangcai.Animal::age << endl;
    wangcai.Animal::showAge();
    
    return 0;
}
```

## 2.9多态

### 2.9.1多态的基本概念

**什么是多态**

​	在程序中，一个类的引用指向另外一个类的对象，从而产生多种形态。当二者存在直接或者间接的继承关系时，父类引用指向子类的对象，即形成多态。

**多态的分类**

​	编译时多态（静态多态）和运行时多态（动态多态），运算符重载和函数重载就是编译时多态，而派生类和虚函数实现是运行时多态。

​	静态多态和动态多态的区别是早绑定（静态联编）还是晚绑定（动态联编）

### **2.9.2对象转型**

​	对象可以作为自己的类或者作为它的父类的对象来使用，还能通过父类的地址来操作它。取一个对象的地址（指针或引用），并将其作为父类的地址来处理，这种称为向上类型转换。

​	也就是说：父类引用或指针可以指向子类对象，通过父类指针或者引用来操作子类对象。

```cpp
#include <iostream>

using namespace std;

//对象转型
//多态的前提条件：父类的引用/指针指向子类对象
//对象转型成为父类的引用或指针后，将只能访问父类中存在的成员，不能访问在子类中定义的成员。

class Animal
{
public:
	void bark()
	{
		cout << "Animal Bark" << endl;
	}
};

class Dog : public Animal
{
    int age;
    void bark()
    {
        cout << "Dog Bark" << endl;
    }
};

int main()
{
	//父类的引用指向子类对象
	Dog dog;
	Animal& animal = dog;
	animal.bark();		//通过父类引用来操作子类对象
    //cout << animal.age;		//此句错误，因为对象转型成为父类的引用或指针后，将只能访问父类中存在的成员，不能访问在子类中定义的成员。
    
	//父类的指针指向子类的对象
	Dog* xiaobai = new Dog();
	Animal* xiaohei = xiaobai;
	xiaohei->bark();	//通过父类指针来操作子类对象
    //cout << xiaohei->age;	//此句错误，因为对象转型成为父类的引用或指针后，将只能访问父类中存在的成员，不能访问在子类中定义的成员。
    
	return 0;
}
```

### 2.9.3虚函数

​	2.9.2中的代码运行结果是Animal bark。这说明执行的是父类中的bark函数，而不是子类中的bark函数。但我们知道的是Animal的引用实际上是一个Dog对象，那为什么执行的是父类中的bark函数呢？这就涉及到了绑定的概念。

​	把函数体与函数调用相联系称为绑定(binding)。

​	当绑定在程序运行之前(由编译器和连接器)完成时，称为早绑定。上述问题就是由早绑定引起的。编译器在只有Animal地址时并不知道要调用的正确函数。编译是根据指向对象的指针或引用的类型来选择函数调用，由于调用函数的时候使用的是Animal类型，编译器确定了应该调用的bark是Animal::bark，而不是真正传入的对象Dog::bark。同理，无法通过Animal.age来访问Dog中的age属性。

​	对于这个问题的解决方法是晚绑定(动态绑定、迟绑定、运行时绑定、last bingding)，这种绑定可以根据对象的实际类型来完成。

​	C++的动态多态性是通过虚函数来实现的，虚函数允许子类重新定义父类成员函数，而子类重新定义父类虚函数的做法称为覆盖(override)或者称为重写。对于特定的函数进行动态绑定，C++要求在基类中声明这个函数的时候使用virtual关键字，动态绑定也就对virtual函数起作用。

​	注意事项：

​		（1）为创建一个需要动态绑定的虚成员函数，可以简单在这个函数声明前面加上virtual关键字。

​		（2）如果一个函数在基类中被声明为virtual，那么在所有派生类中它都是virtual的。

​		（3）在派生类中virtual函数的重定义称为重写（override）

​		（4）virtual关键字只能修饰成员函数，构造函数不能为虚函数。

```cpp
#include <iostream>

using namespace std;

//对象转型
//多态的前提条件：父类的引用/指针指向子类对象
//对象转型成为父类的引用/指针之后，将只能够访问父类中存在的成员，不能访问在子类中定义的成员

//virtual:
//		修饰函数，表示是一个虚函数
//		虚函数可以在子类中进行重新实现，将子类中重新实现从父类继承到的虚函数的过程称为重写(override)
//		父类的引用或指针，来调用父类中的函数的时候，如果子类已经完成了重写，最终实现的是子类中的重写实现


class Animal
{
public:
	//虚函数定义
	virtual void bark()
	{
		cout << "Animal Bark" << endl;
	}
};

class Dog : public Animal
{
public:
	int age;

	//重写函数
	void bark() override
	{
		cout << "Dog Bark" << endl;
	}
};

int main()
{
	//父类的引用指向子类对象
	Dog dog;
	Animal& animal = dog;
	animal.bark();		//输出Dog bark


	//父类的指针指向子类的对象
	Dog* xiaobai = new Dog();
	Animal* xiaohei = xiaobai;
	xiaohei->bark();	//输出Dog bark

	return 0;
}
```

### 2.9.4多态的案例

```cpp
#include <iostream>

using namespace std;

class SF
{
public:
	void sendPackage()
	{
		cout << "顺丰快递为您快速发送包裹" << endl;
	}
};

class EMS
{
public:
	void sendPackage()
	{
		cout << "EMS快递为您发送包裹，哪里都能送达" << endl;
	}
};

class JDL
{
public:
	void sendPackage()
	{
		cout << "京东快递为您发送包裹，最快当日可达" << endl;
	}
};


void send(string s)				//这里就违背了程序设计原则之一：开闭原则
{								//开闭原则：对拓展开放，对修改关闭，当有新功能增加时，可以直接拓展模块来实现，不能修改已有代码
	if (s == "SF")				//如果有新的快递公司，那么就需要增加新的判断，就违背了开闭原则
	{
		SF().sendPackage();
	}
	else if (s == "EMS")
	{
		EMS().sendPackage();
	}
	else if (s == "JDL")
	{
		JDL().sendPackage();
	}
}

int main()
{
	send("EMS");

	return 0;
}
```

```cpp
#include <iostream>

using namespace std;

class ExpressCompany		//创建一个父类，在父类中定义一个虚函数。
{
public:
	virtual void sendPackage()
	{};

};

//每个不同的快递公司继承自父类，然后重写父类中的虚函数
class SF : public ExpressCompany
{
public:
	void sendPackage()	override
	{
		cout << "顺丰快递为您快速发送包裹" << endl;
	}
};

class EMS : public ExpressCompany
{
public:
	void sendPackage() override
	{
		cout << "EMS快递为您发送包裹，哪里都能送达" << endl;
	}
};

class JDL : public ExpressCompany
{
public:
	void sendPackage() override
	{
		cout << "京东快递为您发送包裹，最快当日可达" << endl;
	}
};
void send(ExpressCompany& company)		//传入父类引用
{
	company.sendPackage();		//调用子类中重写的sendPackage函数
}

//新加快递公司
class YT : public ExpressCompany
{
public:
	void sendPackage() override
	{
		cout << "圆通快递为您发送包裹" << endl;
	}
};

int main()
{
	EMS ems;		//创建一个EMS对象
	send(ems);		//将EMS对象ems传入
	YT yt;
	send(yt);

	return 0;
}

//这样就解决了新的快递公司加入时需要重写代码的问题，符合开闭原则
```

### 2.9.5纯虚函数和抽象类

​	在2.9.4的案例中，基类里的虚函数的实现部分并没有任何作用，因此可以不用写其实现部分。这是sendPackage就是个纯虚函数，ExpressCompany类就是个抽象类。

​	在设计程序时，常常希望基类仅仅作为其派生类的一个接口。这就是说，仅想对基类进行向上类型转换，使用它的接口，而不希望用户实际创建一个基类的对象。同时创建一个纯虚函数允许接口中放置成员原函数，而不一定要提供一段可能对这个函数毫无意义的代码。

```cpp
#include <iostream>
using namespace std;
//纯虚函数：如果一个虚函数的实现部分被设置为了0，那么这样的函数就是纯虚函数。纯虚函数只有声明，没有实现
//抽象类：如果一个类中包含了纯虚函数，那么这个类就是抽象类。抽象类不能创建对象。
class TrafficTool
{
public:
	//纯虚函数
	virtual void transport() = 0;
};
//如果一个类继承自一个抽象类，此时这个类中必须重写所有纯虚函数，不然他也是一个抽象类，无法创建对象
class Bus : public TrafficTool
{
public:
	void transport() override
	{
		cout << "公交车运输乘客" << endl;
	}
};
class Bike : public TrafficTool
{
public:
	void transport() override
	{
		cout << "自行车运输乘客" << endl;
	}
};
void test(TrafficTool& t)		//抽象类不能实例化，但是可以引用或定义指针
{
	t.transport();
}
int main()
{
	Bus bus;
	test(bus);
	Bike bike;
	test(bike);
	return 0;
}
```

### 2.9.6纯虚函数和多继承

​	绝大多数面向对象语言都不支持多继承，但是绝大多数面向对象语言都支持接口的概念，c++中没有接口的概念，但是可以通过纯虚函数来实现接口。

​	接口类中只有函数原型定义，没有任何数据定义。

​	多重继承接口不会带来二义性和复杂性的问题。接口类只是一个功能声明，并不是功能实现，子类需要根据功能说明定义功能实现。注意：出来析构函数外，其他声明都是纯虚函数。

```cpp
#include <iostream>

using namespace std;

//定义厨师的接口类
class Cooker
{
public:
	virtual void cook() = 0;		//厨师做饭功能
	virtual void buyfood() = 0;		//厨师买菜功能
	virtual void washfood() = 0;	//厨师洗菜功能
};

//定义保姆的接口类
class Maid
{
public:
	virtual void cook() = 0;		//保姆做饭功能
	virtual void clean() = 0;		//保姆打扫功能
};

class Person : public Cooker, public Maid		//创建一个Person类，是其具有厨师和保姆的功能
{
public:
	void cook() override
	{
		cout << "做饭" << endl;
	}
	void buyfood() override
	{
		cout << "买菜" << endl;
	}
	void washfood() override
	{
		cout << "洗菜" << endl;
	}
	void clean() override
	{
		cout << "打扫" << endl;
	}
};

void funcCooker(Cooker& c)
{
	c.cook();
	c.buyfood();
	c.washfood();
}

void funcMaid(Maid& m)
{
	m.cook();
	m.clean();
}

int main()
{
	Person xiaoming;
	funcCooker(xiaoming);
	funcMaid(xiaoming);


	return 0;
}
```

### 2.9.7多态案例

```cpp
#include <iostream>

using namespace std;

//假设：
//顺丰快递发空运和陆运
//EMS快递只能发陆运
//圆通快递只能发空运

//现在需要发送快递，设计两个函数一个用来发空运，一个用来发陆运。

//接口类设计：空运的能力
class AirTransportation
{
public:
	virtual void sendPackageOnAir() = 0;
};

//接口类设计：陆运的能力
class LandTransportation
{
public:
	virtual void sendPackageOnLand() = 0;
};

//顺丰快递，继承空运和陆运能力两个接口类
class SF : public AirTransportation, public LandTransportation
{
public:
	void sendPackageOnAir() override
	{
		cout << "顺丰为您发送空运包裹" << endl;
	}
	void sendPackageOnLand() override
	{
		cout << "顺丰为您发送陆运包裹" << endl;
	}
};

//EMS快递，继承陆运能力接口类
class EMS : public LandTransportation
{
public:
	void sendPackageOnLand() override
	{
		cout << "EMS为您发送陆运包裹" << endl;
	}
};

//圆通快递，继承空运能力接口类
class YT : public AirTransportation
{
public:
	void sendPackageOnAir() override
	{
		cout << "圆通为您发送空运包裹" << endl;
	}
};

void sendOnAir(AirTransportation& expressCompany)
{
	expressCompany.sendPackageOnAir();
}

void sendOnLand(LandTransportation& expressCompany)
{
	expressCompany.sendPackageOnLand();
}

int main()
{
	SF sf;
	EMS ems;
	YT yt;

	sendOnAir(sf);
	sendOnAir(yt);
	//sendOnAir(ems);		ems没有空运能力，此语句错误

	sendOnLand(sf);
	sendOnLand(ems);
	//sendOnLand(yt);		yt没有陆运能力，此语句错误

	return 0;
}
```

## 2.10结构体

​	结构体也是一种自定义的数据类型，基本与类相同。结构体与类唯一不同的一点就是，类中的成员默认是private权限的，结构体中的成员默认是public权限的。

```cpp
#include <iostream>
using namespace std;
struct Student
{
	//结构体中可以定义属性
	string name;
	int age;
	int score;

	//结构体中可以定义构造函数
	Student() : name(""), age(0), score(0) {}

	Student(string name, int age, int score) : name(name), age(age), score(score) {}

	//结构体中可以定义函数
	void study()
	{
		cout << "我爱学习" << endl;
	}

	//结构体中可以定义析构函数
	~Student()
	{
		cout << "Student中的析构函数被执行了" << endl;
	}
};

int main()
{
	//结构体对象创建，创建结构体对象时，关键字struct可以省略不写。
	struct Student xiaobai;
	struct Student xiaohei = Student("xiaohei", 20, 100);
	struct Student* xiaohong = new Student();
	Student xiaolv;

	//结构体成员访问
	xiaobai.name = "xiaobai";
	xiaobai.study();
	xiaohong->age = 18;

	return 0;
}
```

## 2.11模板

### 2.11.1模板的介绍

​	函数模板，实际上是建立一个通用函数，其函数类型和形参类型不具体定制，用一个虚拟的类型来代表。这个通用函数就称为函数模板。凡是函数体相同的函数都可以用这个模板代替，不必定义多个函数，只需在模板中定义一次即可。在调用函数时系统会根据实参的类型来取代模板中的虚拟类型，从而实现不同函数的功能。

​	例如，要编写一个两数相加的函数。这两个数既可以是int int，也可以是int double，又或者double float等多种组合。编写时总不可能为每一种可能都去定义一个函数，虽然可以重载，但是那样也还是太麻烦了。这时就可以使用函数模板。

​	C++提供两种模板机制：函数模板和类模板。

​	总结：模板把函数或类要处理的数据类型参数化，表现为参数的多态性，成为类属。模板用于表达逻辑结构相同，但具体元素类型不同的数据对象的通用行为。

### 2.11.2函数模板

**函数模板的定义及使用**

```cpp
#include <iostream>

using namespace std;


//template:定义模板的关键字
//typename：定义虚拟类型的关键字，可以被替换为class
//T、M定义的虚拟类型
//虚拟类型可以有默认的类型，例如typename M = int
template <typename T, typename M>
void add(T n1, M n2)
{
	cout << n1 + n2 << endl;
}

template <typename T>
void mySwap(T& n1, T& n2)
{
	T tmp = n1;
	n1 = n2;
	n2 = tmp;
}

template<typename R, typename T1, typename T2>
R calculate(T1 x, T2 y)
{
	return (R)(x + y);
}

int main()
{
	//函数模板的使用，有两种方式
	//1.显式指定类型
	add<int, double>(10, 3.345);
	add<int, int>(10, 3);
	add<char, char>('a', 'b');

	//2.可以根据实参进行类型自动推导
	add(1.0, 2.0);
	add(1, 2);
	add(1.3232312323, 2.343);

	//注意事项：在进行类型推导的时候，需要注意一致性的问题，对于同样的虚拟类型，不能推导出不同的实际类型
	double x = 10;
	double y = 20;
	mySwap(x, y);
	cout << x <<'t' << y << endl;

	//3.调用函数模板的时候，如果手动指定虚拟类型的实际类型，此时可以不完全指定
	//	实际给的类型，按照虚拟类型列表中的顺序去指定，没有指定的虚拟类型，将按照是实参的类型来推到
	add<int>(10, 3.14);
	
	//返回值使用虚拟类型
	//如果虚拟类型是使用在返回值部分，必须手动指定。
	calculate<int>(3.14, 9.23);

	return 0;
}
```

**函数模板和普通函数**

​	函数模板和普通函数在调用时需要注意一下两点。

​		（1）普通函数调用，是可以发送自动类型转换的。函数模板的调用不会发生数据类型转换。

​		（2）如果在调用函数的时候，实参即可以匹配普通函数，也可以匹配函数模板，那么优先调用普通函数。

```cpp
#include <iostream>

using namespace std;

template<typename T>
int add(T n1, T n2)
{
	cout << "函数模板被调用了" << endl;
	return n1 + n2;
}

int add(int n1, int n2)
{
	cout << "普通函数被调用了" << endl;
	return n1 + n2;
}

int main()
{
	int n = 10;
	char c = 'a';
	add(n, c); //这里调用了普通函数，发生了类型转换，c转换为了int
	
	add(10, 20);//这里实参类型符合普通函数，也符合函数模板，但是调用的是普通函数

}
```

### 2.11.3类模板

**类模板的定义**

​	类模板和函数模板的定义和使用基本是一样的，如何定义函数模板就如何定义类模板。类模板与函数模板的区别就是类模板不能自动类型推导。

**类模板的使用**

```cpp
#include <iostream>

using namespace std;

template<typename T1, typename T2>
class NumberCalculator
{
public:
	T1 n1;
	T2 n2;

	NumberCalculator() {}
	NumberCalculator(T1 n1, T2 n2) : n1(n1), n2(n2) {}

	void showAddResult()
	{
		cout << n1 + n2 << endl;
	}

	void showMinusResult()
	{
		cout << n1 - n2 << endl;
	}
};

//普通函数中，使用到类模板作为参数，类模板必须要明确类型
void useCalculator(NumberCalculator<int, int>& op)
{
	op.showAddResult();
}

//函数模板中，使用到类模板作为参数的时候，类模板可以明确类型，也可以使用函数模板中的虚拟类型
template<typename X1, typename X2>
void useCalculator02(NumberCalculator<X1, X2>& op)
{
	op.showMinusResult();
}

int main()
{
	//创建对象
	//类模板创建的时候，必须手动指定类型，不能通过推导的方式来确定类型
	NumberCalculator<int, int> cal1(10, 20);
	NumberCalculator<double, double> cal2(10.3, 20.2);
	cal1.showAddResult();
	cal2.showMinusResult();

	useCalculator(cal1);	//这里传入cal2的话会报错，因为useCalculator的形参是int int型

	useCalculator02(cal1);	//useCalculator02自动将类型推导为int int
	useCalculator02(cal2);	//useCalculator02自动将类型推导为double double

	return 0;
}
```

**类模板的继承**

```cpp
#include <iostream>

using namespace std;

//类模板中的虚拟类型是不能够继承的
template <typename T>
class Animal
{
public:
	T arg;

};

//普通的类来继承类模板，需要指定父类中的虚拟类型
class Dog : public Animal<int> {};

//类模板来继承类模板
template<typename E>
class Cat : public Animal<E> {};	//可以使用虚拟类型，也可以自己指定类型，如int

int main()
{
	Dog xiaobai;
	xiaobai.arg = 10;

	Cat<string> xiaohei;
	xiaohei.arg = "qwe";

	return 0;
}
```

# 第三部分 STL标准模板库

## 3.1STL概述

### 3.1.1STL基本概念

​	STL（标准模板库）是惠普实验室开发的一系列软件的统称，现在主要出现在C++中。

​	STL从广义上分为：容器（container）、算法（algorithm）、迭代器（iterator），容器和算法之间通过迭代器进行无缝衔接。STL几乎所有代码都采用了模板类或者模板函数。这比传统的由函数和类组成的库来说提供了更好的代码重用机会。

### 3.1.2STL六大组件

## 3.2STL三大组件

### 3.2.1容器

​	STL容器将运用最广泛的一些数据结构实现出来。常见的数据结构有数组（array）、链表（list）、树(tree)、栈（stack）、队列（queue）、集合（set）、映射表（map），根据数据在容器中的排列特性，这些数据可以分为序列式容器和关联式容器。

​	序列式容器：强调值的排序，序列式容器中的每个元素均有固定的位置，除非用删除或插入的操作来改变这个位置。Vector容器、Deque容器、List容器等。

​	关联式容器：非线性的树结构。各元素之间没有严格的物理上的顺序关系，也就是说元素在容器中并没有保存元素置入容器时的逻辑顺序。关联式容器另一个显著特点是：在值中选择一个值作为关键字key，这个关键字对值起到索引的作用，方便查找。Set/multise容器，Map/multimap容器。

​	容器可以嵌套容器。

### 3.2.2算法

​	算法是以有限的步骤，解决逻辑或数学上的问题。广义而言，我们所编写的每一个程序都是一个算法，其中的每一个函数也都是一个算法。STL收录的算法经过了数学上的效能分析与证明，是极具复用价值的，包括常用的排序、查找等等。特定的算法往往搭配特定的数据结构，算法与数据结构相辅相成。

​	算法分为质变算法和非质变算法。

​	质变算法是指运算过程中会更改区间内的元素的内容。例如拷贝、替换、删除等等。

​	非质变算法是指运算过程中不会更改区间内的元素内容，例如查找、计数、遍历、寻找极值等等。

### 3.2.3迭代器

​	迭代器（iterator）是一种抽象的设计概念，现实程序语言中并没有直接对应于这个概念的实物。它的定义是提供一种方法，使之能够依序寻访某个容器所含的各个元素，而又无需暴露该容器的内部表示方式。

​	STL的中心思想是将容器和算法分开，彼此独立设计，最后再将其撮合在一起。

​	迭代器的种类有：

| 输入迭代器     | 提供对数据的只读访问                                         | 只读，支持++、==、！=                   |
| -------------- | ------------------------------------------------------------ | --------------------------------------- |
| 输出迭代器     | 提供对数据的只写访问                                         | 只写，支持++                            |
| 前向迭代器     | 提供读写操作，并能向前推进迭代器                             | 读写，支持++、==、！=                   |
| 双向迭代器     | 提供读写操作，并能向前和向后操作                             | 读写，支持++、--                        |
| 随机访问迭代器 | 提供读写操作，并能以跳跃的方式访问容器的任意数据，是功能最强的迭代器 | 读写，支持++、--、[n]、-n、<、<=、>、>= |

## 3.3常用容器

### 3.3.1string容器

​	**string容器基本概念**

​	C++中，string是一个类，内部封装了char*，用来管理这个容器。string类中封装了很多功能函数，例如find、copy、delete、replace、insert等。C++中字符串不用考虑内存释放和越界的问题。

​	**string容器的构造与赋值**

​		string构造函数

```cpp
string(); //创建一个空的字符串 例如：string str
string(const string& str); //使用一个string对象初始化另一个string对象
string(const char* s);	//使用字符数组s初始化
string(int n , char c); //使用n个字符c初始化
```

```cpp
void test01()
{
	//无参构造，创建一个空字符串
	string str1 = string();

	//通过一个字符串，构造另外一个字符串
	string str2 = string("hello world");

	//通过一个字符数组，构造一个字符串
	const char* array = "hello world";	//创建字符数组
	string str3 = string(array);
	cout << str3 << endl;	//输出为hello world

	//通过指定数量的指定字符，构造一个字符串
	string str4 = string(5, 'A');
	cout << str4 << endl;	//输出为AAAAA

}
```

​		string基本赋值操作

```cpp
string& operator=(const char* s);	//char*类型字符串赋值给当前字符串
string& operator=(const string &s);	//把字符串s赋值给当前字符串
string& operator=(char c);	//字符赋值给当前的字符串
string& assign(const char *s);	//把字符串s赋值给当前的字符串
string& assign(const char *s, int n);	//把字符串s的前n个字符赋值给当前的字符串
string& assign(const string &s);	//把字符串s赋值给当前字符串
string& assign(int n , char c);	//用n个字符c赋值给当前字符串
string& assign(const string &s, int start, int n);	//将s从start开始n个字符赋值给字符串

//以上语句返回的都是字符串的引用，这样就可以链式操作
```

```cpp
void test02()
{
	string str;

	//通过等号进行赋值，等号已经被string进行了运算符重载
	//通过字符串进行赋值
	str = "hello world";
	cout << str << endl;

	//通过字符数组进行赋值
	const char* array = "qwe";
	str = array;
	cout << str << endl;

	//通过字符进行赋值
	str = 'a';
	cout << str << endl;

	//assign方式
	str.assign("hello world");
	cout << str << endl;

	str.assign(array);
	cout << str << endl;

	str.assign(8, 'B');
	cout << str << endl;

	//string& assign(const char* s, int n);		把字符串s的前n个字符赋值给当前的字符串
	str.assign(array, 2);
	cout << str << endl;

	//string& assign(const string & s, int start, int n);	将s从start开始n个字符赋值给字符串
	str.assign(array, 1, 2);
	cout << str << endl;
}
```

​		string存取字符操作

```cpp
char& operator[](int n); //通过[]方式获取字符
char& at(int n);	//通过at方法获取字符
```

```cpp
void test03()
{
	//通过"下标"，从一个字符串中获取到指定位的字符，或者是可以修改指定下标位的字符
	//char& operator[](int n);	//通过[]方式获取字符
	//char& at(int n);	//通过at方法获取字符

	string str = "hello world";
	cout << str[4] << endl;		//输出为o
	cout << str.at(3) << endl;	//输出为l

	//使用字符引用返回值，存储字符串中指定下标位字符的引用
	char& c = str[4];
	//修改引用的值
	//因为这里引用的是字符串中的字符数组中的指定下标位的元素，所以这里c发生变更，也会影响到数组中的元素。
	c = 'q';
	cout << str << endl;		//输出为hellq world

}
```

​		string拼接

```cpp
string& operator+=(const string& str);	//重载+=运算符
string& operator+=(const char* str);	//重载+=运算符
string& operator+=(const char c);	//重载+=运算符
string& append(const char *s);	//把字符串s连接到当前字符串结尾
string& append(const char *s, int n);	//把当前字符串s的前n个字符连接到当前字符串结尾
string& append(const string &s);	//同operator+=()
string& append(const string &s,int pos, int n);	//把字符串s中从pos开始的第n个字符连接到当前字符串结尾
string& append(int n, char c);	//在当前字符串结尾添加n个字符c
```

```cpp
void test04()
{
	string str = "hello";

	//+
	str = str + " world";
	cout << str << endl;

	//+=
	str += " hello";
	cout << str << endl;

	//append
	str.append(" earth");
	cout << str << endl;

	str.append(" hello China", 7);
	cout << str << endl;

	str.append("hello China ", 6, 7);
	cout << str << endl;

	str.append(5, 'h');
	cout << str << endl;

}
```

​		string查找和替换

```cpp
int find(const string& str, int pos = 0) const;	//查找str第一次出现的位置，从pos开始查找
int find(const char* s, int pos = 0) const;	//查找s第一次出现的位置，从pos开始找
int find(const char* s, int pos, int n) const;	//从pos位置查找s的前n个字符第一次位置
int find(const char c, int pos = 0) const;	//查找字符c第一次出现的位置
int rfind(const string&, int pos = npos) const;	//查找str最后一次位置，从pos开始查找
int rfind(const char* s, int pos = npos) const;	//查找s最后一次出现位置，从pos开始查找
int rfind(const char* s, int pos, int n) const;	// 从pos查找s的前n个字符最后一次位置
int rfind(const char* c, int pos = 0) const;	//查找字符c最后一次出现位置
string& replace(int pos, int n, const string& str);	//替换从pos开始第n个字符为字符串str
string& replace(int pos, int n, const char* s);	//替换从pos开始的第n个字符为字符串s
```

```cpp
void test05()
{
	//查找：查找一个字符串或者是一个字符在指定字符串中出现的下标，如果找不到返回-1
	//替换：将一个字符串中指定下标范围的部分，替换成新的字符串

	string str = "C++ is the most popular, most useful programing language in the world";

	cout << str.find("most") << endl;
	cout << str.find("most", 20) << endl;
	cout << str.find("most useful", 20, 4) << endl;
	cout << str.find('s') << endl;

	//rfind和find差不多，只不过是查找的最后一次
	cout << str.rfind("most") << endl;		
	
	//这里输出11，这是因为rfind实际上是从后往前遍历，因此他是从popular开始往左遍历的
	cout << str.rfind("most", 20) << endl;
	cout << str.rfind("most useful", 20, 4) << endl;
	cout << str.rfind('s') << endl;

	//替换
	cout << str.replace(11, 25, "best") << endl;
	cout << str << endl;	//这里字符串就发生改变了

}
```

​		string的比较操作

```cpp
void test06()
{
	//字符串大小比较规则：比的是ASCII码
	//		依次比较字符串中的每一位字符，如果字符相同，继续比较后面的一位字符，直到某一次比较可以比出大小
	//字符串的比较可以使用 > < >= <= == !=来比较，但这种方法有局限性
	//		局限性就是这种方法比较返回的结果是一个bool类型，只有两种结果，因此不能反应出三种大小关系
	//		因此，字符串提供了一个compare函数，返回值是一个int类型
	//		如果左边比右边大，返回1；小，返回-1；相等返回0
	
	string	str1 = "qwertyuio";
	string  str2 = "qwertauio";
	string  str3 = "qwertzuio";
	string  str4 = "qwertyuio";
	cout << str1.compare(str2) << endl;
	cout << str1.compare(str3) << endl;
	cout << str1.compare(str4) << endl;
}
```

​		string子串的获取

```cpp
void test07()
{
	//pos: 起始下标，从什么下标开始获取子串，默认的值是0
	//n ： 长度，获取多少个字符，默认的值是字符串的长度
	//string substr(int pos = 0, int n = npos);		//返回由pos开始的第n个字符组成的字符串
	
	string str = "hello";
	cout << str.substr(2, 2) << endl;;

	//注意事项：1.下标pos不要越界。n的长度可以过长，会将字符串中剩余的所有部分返回给你
	//			2.截取字符串的操作，不会对字符串本身产生影响，它返回给你的是一个新的字符串
	//cout << str.substr(7, 20);		这里pos越界了会报错
	cout << str.substr(2, 20) << endl;;		//n越界没问题
	cout << str << endl;
}
```

​		string的插入和删除操作

```cpp
void test08()
{
	//string& insert(int pos, const char* s);	//从pos开始，插入字符串
	//string& insert(int pos, const string& str); //从pos开始，插入字符串
	//string& insert(int pos, int n. char c); //在指定位置插入n个字符c
	//string& erase(int pos, int n = npos); //删除从Pos开始的n个字符串

	string str = "HAHAHAHAHAHA";

	//插入
	str.insert(4, "hello");
	cout << str << endl;

	str.insert(4, 5, 'Q');
	cout << str << endl;

	//删除
	str.erase(4, 5);
	cout << str << endl;
}
```

### 3.3.2vector容器

​	vector的数据安排以及操作方式，与array非常相似，两者的唯一差别在于空间的运用的灵活性。Array是静态空间，一旦配置了就不能改变。如果要换大一点或者小一点的空间需要配置一块新的空间，然后将旧空间的数据搬往新空间，再释放原来的空间。vector是动态空间，随着元素的加入，它的内部机制会自动扩充空间以容纳新元素。因此vector的运用对于内存的合理利用与运用的灵活性有很大的帮助。

​	**vector容器的遍历**

```cpp
#include <iostream>
#include <vector>		//使用vector的时候，需要先引入头文件

//vector容器的遍历
void test_1()
{
	//1.构造一个vector对象,通过vector的无参构造，构造出来一个空的vector容器
	vector<int> v;

	//2.添加若干个元素
	v.push_back(1);
	v.push_back(2);
	v.push_back(3);

	//3.迭代器：使用普通指针，依次指向vector中的每一个元素
	//		begin():获取到的是vector容器中的首元素的地址
	//		end():获取到的是vector容器中的最后一位元素的下一位的指针
	//vector<int>::iterator it = v.begin();
	//cout << *it << endl;		//这里it指向的是vector中的第一个元素
	//
	//it++;						//指向第二个元素
	//cout << *it << endl;
	//
	//it++;						//指向第三个元素
	//cout << *it << endl;

	//it++；						//越界了，因为vector中只有3个元素

	//以上这种方式太麻烦，因此可以使用循环
	for (vector<int>::iterator it = v.begin(); it != v.end(); it++)
	{
		//直接输出指针指向元素
		cout << *it << endl;
		//可以通过指针，修改元素
		if (*it == 2)
		{
			*it = 20;
		}
	}

	//使用迭代器遍历vector容器
	for (vector<int>::iterator it = v.begin(); it != v.end(); it++)
	{
		cout << *it << endl;		//这时已经被修改了
	}

	//使用迭代器遍历容器的时候，可以缩写
	//依次将v容器中的每一个元素给ele进行赋值
	//但是这样无法通过ele修改v中的值。如果想修改应该使用引用for(int& ele : v)
	for (int ele : v)
	{
		cout << ele << endl;
	}


	//倒叙遍历容器
	for (vector<int>::iterator it = v.end(); it != v.begin(); )
	{
		it--;
		cout << *it << endl;
	}
	vector<int> ::iterator it = v.end() - 1;
}
```

​		**vector的构造函数**

```c++
	//1.无参构造函数
	vector<int> v1;

	//2.vector(n, ele)
	vector<int> v2(10, 5);		//表示用10个5来填充v2

	//3.vector(const vector& v)   拷贝构造函数

	//4.vector(v.begin(), v.end())		//通过两个指针来实现拷贝构造函数
	vector<int> v3(v2.begin(), v2.end());	//此时v3里是10个5
	vector<int> v3(v2.begin(), v2.end() - 5);		//此时v3里是5个5
```

​		**vector的赋值函数**

```cpp
void test_3()
{
	//assign(beg,end);	将[beg,end)区间中的数据拷贝赋值给本身，注意区间是前闭后开
	int arr[] = { 1,2,3,4,5,6,7,8,9,0 };
	vector<int> v1;		//vector对象建立
	v1.assign(arr, arr + 6);	//此时v1中元素为1,2,3,4,5,6

	//assign(n, ele);	将n个ele拷贝赋值给本身
	vector<int> v2;
	v2.assign(4, 5);		//v2中元素为4个5

	//vector& operator = (const vector& vec);	//重载等号运算符
	vector<int> v3;
	v3 = v2;	//将v2中的元素赋值给v3

	//swap(vec);	//将vec与本身的元素互换
	v3.swap(v1);	//此时v3中元素为1,2,3,4,5,6	v1中元素为4个5

}
```

​		**关于vector容器大小的操作**

```cpp
void test_4()
{
	vector<int> v(10, 5);	//创建容器

	//返回容器中有多少个元素
	cout << "size = " << v.size() << endl;

	//判断容器是否为空
	cout << "empty = " << v.empty() << endl;

	//返回容器的容量
    //capacity：在内存上开辟了多少空间
    //size：实际容器中存放的元素数量
	cout << "capacity = " << v.capacity() << endl;

	//重新指定容器的长度,如果指定的长度小于原来的长度，则保留容器中前指定元素个数量
	v.resize(5);		//此时元素为5,5,5,5,5
	//重新指定容器长度，如果指定长度大于原来的长度，填充默认元素，即0
	v.resize(15);		//此时元素为5,5,5,5,5,5,5,5,5,5,0,0,0,0,0
	//重新指定容器长度，如果指定长度大于原来的长度，填充指定元素
	v.resize(15, 6);	//此时元素为5,5,5,5,5,5,5,5,5,5,6,6,6,6,6

}
```

​	**vector的存取操作**

```cpp
//vector的数据存取操作
void test_5()
{
	//at(int idx);	//返回索引idx所指的数据，如果idx越界，则抛出out of range异常
	int array[] = { 1,2,3,4,5,6,7,8,9,0 };
	vector<int> v(array,array+sizeof(array)/sizeof(int));	//赋值
	int& ele1 = v.at(3);		//这里用的是引用，因此可以修改vector中的值
	cout << ele1 << endl;		//输出4
	ele1 = 40;
	cout << v.at(3) << endl;	//输出40

	//operator[];	//中括号重载，返回索引idx所指的数据，越界则运行报错
	int& ele2 = v[5];
	cout << ele2 << endl;		//输出6

	//front();	//返回容器中第一个元素
	cout << v.front() << endl;		//输出1

	//back();	//返回容器中最后一个元素
	cout << v.back() << endl;		//输出0
}
```

​	**vector容器删除和插入操作**

```cpp
void test_6()
{
	int array[] = { 1,2,3,4,5 };
	vector<int> v(array, array + (sizeof(array) / sizeof(int)));

	//insert(const_iterator pos, int count ,ele);	//迭代器指定位置pos插入count个元素ele
	v.insert(v.begin() + 3, 5, 0);	//此时v中元素为1,2,3,0,0,0,0,0,4,5

	//push_back();	//尾部插入元素ele
	v.push_back(6);		//此时v中元素为1,2,3,0,0,0,0,0,4,5

	//pop_back();	 删除最后一个元素
	v.pop_back();		//此时v中元素为1,2,3,0,0,0,0,0,4,5

	//erase(const_iterator start, const_iterator end);	删除迭代器从start到end之间的元素
	//注意区间为[start,end)前闭后开
	v.erase(v.begin() + 5, v.begin() + 8);		//此时v中元素为1,2,3,0,0,4,5

	//erase(const_iterator pos);	删除迭代器指向元素
	v.erase(v.begin() + 3);		//此时v中元素为1,2,3,0,4,5

	//clear();	删除容器中所有元素
	v.clear();
}

```

### 3.3.3deque容器

​	**deque容器的基本概念**

​		Vector是单向开口的连续内存空间，deque则是一种双向开口的连续线性空间。双向开口是指可以在头尾两端分别做元素的插入和删除操作。![](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250621055232438.png)

​		deque容器和vector容器最大的差异有两点。

​		一是deque运行对头端进行元素的插入和删除操作。使用push_front()和pop_front().

​		二是deque没有容量的概念，它是以动态的分段连续空间组合而成，随时可以增加一段新的空间并链接起来。

​		deque的语法和vector一样，可以参考上一节。

​		一般情况下，很少使用deque，都是使用vector。

### 3.3.4stack容器

​	stack是一种先进后出(FILO)的数据结构，它只有一个出口。stack容器允许新增元素，移除元素，取得栈顶元素，但是这都是对于最顶端来说的。stack没有办法存取stack的其他元素，也就是不允许有遍历行为。stack也不提供迭代器。![image-20250621055837150](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250621055837150.png)

```cpp
#include <iostream>
#include <stack>

using namespace std;

int main()
{
	//构造函数：只有两个，一是无参构造，而是拷贝构造函数
	stack<int> s1;

	//压栈
	s1.push(10);
	s1.push(20);
	s1.push(30);

	//获取栈顶元素
	int& ele = s1.top();
	cout << ele << endl;		//输出30

	//出栈
	s1.pop();
	cout << s1.top() << endl;	//输出20

	//大小
	cout << s1.empty() << endl;	//返回false
	cout << s1.size() << endl;	//输出2

	return 0;
}
```

### 3.3.5queue容器

​	queue是一种先进先出(FIFO)的数据结构，也就是队列。它有两个出口，queue容器运行从一段新增元素，从另一端移除元素。queue容器没有迭代器，所有元素的进出都必须符合FIFO，只有queue的顶端元素，才有机会被外界取用。queue不提供遍历功能。

![image-20250621060857657](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250621060857657.png)

```cpp
#include <iostream>
#include <queue>

using namespace std;

int main()
{
	//构造函数：无参构造函数，拷贝构造函数
	queue<int> q;

	//新增一个元素到队列
	q.push(10);
	q.push(20);
	q.push(30);

	//获取队头的元素
	cout << q.front() << endl;		//输出10

	//获取队尾元素
	cout << q.back() << endl;		//输出30

	//从队列中移除元素，注意移除的是队头
	q.pop();
	cout << q.front() << endl;		//输出20,20是新的队头

	//大小
	cout << q.empty() << endl;		//返回flase
	cout << q.size() << endl;	//输出2

	return 0;
}
```

### 3.3.6list容器

​	**list容器的基本概念**

​		list容器是一种双向链表。链表是非连续，非顺序的存储结构，数据元素的逻辑顺序是通过链表中的指针链接次序实现的。链表由一系列节点（链表中的每一个元素称为节点）组成，节点可以在运行时动态生成。每个节点包括两个部分：一是存储数据元素的数据域，另一个是存储下一个节点地址的指针域。

​		list容器的优点是每次插入或删除一个元素，就配置或释放一个元素的空间。因此，list对于空间的运用有着绝对的精准，不会发生浪费。它的缺点是空间和时间额外耗费较大。

​		对于元素的增删操作较频繁可以使用list容器，对于元素的取值操作较频繁可以使用vector容器。

![image-20250622050015737](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250622050015737.png)

​		**list容器的一些函数**

```cpp
#include <iostream>
#include <list>

using namespace std;

void printList(list<int>& l)
{
	for (int& ele : l)
	{
		cout << ele << ", ";
	}
	
}

int main()
{
	//构造函数
	int arr[10] = { 0,1,2,3,4,5,6,7,8,9 };
	list<int> l(arr, arr + 10);
	printList(l);		//输出0,1,2,3,4,5,6,7,8,9
	cout << endl;

	//元素的插入和删除操作
	l.push_back(10);		//在末尾添加元素
	printList(l);			//输出0,1,2,3,4,5,6,7,8,9,10
	cout << endl;
	l.push_front(20);		//在首位添加元素
	printList(l);			//输出20,0,1,2,3,4,5,6,7,8,9,10
	cout << endl;


	l.pop_back();			//移除最后的元素
	printList(l);			//输出20,0,1,2,3,4,5,6,7,8,9
	cout << endl;
	l.pop_front();			//移除最开头的元素
	printList(l);			//输出0,1,2,3,4,5,6,7,8,9
	cout << endl;

	list<int>::iterator it = l.begin();		//声明一个迭代器it，指向l.begin()
	l.insert(it, 10);		//在it指向的位置处也就是0处插入10
	printList(l);			//输出10,0,1,2,3,4,5,6,7,8,9
	cout << endl;			
	//l.insert(it + 5, 10);	这条语句错误，因为list的迭代器是双向迭代器，只能支持++或--

	l.insert(it++, 20);		//在it++位置插入20，此时it指向0，插入后it指向1
	printList(l);			//输出10,20,0,1,2,3,4,5,6,7,8,9
	cout << endl;

	l.insert(++it, arr + 3, arr + 8);	//在++it处也就是2处插入arr的第3个元素到第8个元素即3, 4, 5, 6, 7
	printList(l);						//输出10, 20, 0, 1, （3, 4, 5, 6, 7）, 2, 3, 4, 5, 6, 7, 8, 9,	括号里是插入的arr
	cout << endl;						//这个区间是前比后开，[arr+3, arr + 8)

	l.erase(it);						//删除元素，此时it指向2这个元素
	printList(l);						//输出10, 20, 0, 1, 3, 4, 5, 6, 7, 3, 4, 5, 6, 7, 8, 9,
	cout << endl;

	//删除区间[3,6)内的元素
	list<int>::iterator start = l.begin();
	for (int i = 0; i < 3; i++)		//start自增3次指向第三位元素
	{
		start++;
	}
	list<int>::iterator end = l.begin();
	for (int i = 0; i < 6; i++)		//end自增6次指向第六位元素
	{
		end++;
	}
	l.erase(start, end);
	printList(l);					//输出10, 20, 0, 5, 6, 7, 3, 4, 5, 6, 7, 8, 9,
	cout << endl;

	l.remove(8);			//移除指定的值，输出10, 20, 0, 5, 6, 7, 3, 4, 5, 6, 7, 9,
	printList(l);
	cout << endl;

	//大小操作
	cout << l.size() << endl;
	cout << l.empty() << endl;

	//翻转操作
	l.reverse();
	printList(l);
	cout << endl;

	//排序
	l.sort();
	printList(l);
	cout << endl;

	l.clear();		//清除所有值
	printList(l);
	cout << endl;
	
	return 0;
}
```

### 3.3.7set/multiset容器

​	**set/multiset容器基本概念**

​		Set的特性是所有的元素都会根据元素的值自动被排序，且set不允许有两个元素相同的值。

​		不能通过迭代器来改变set元素的值，因为set元素值关系到set元素的排序规则，任意改变的话会严重破坏set组织。

​		set拥有和list某些相同的性质，当对容器中的元素进行插入操作或者删除操作的时候，操作之前所有的迭代器在操作之后依然有效。

​		multiset特性及用法和set完全相同，唯一的差别在于它允许值重复。set和multiset的底层实现是红黑树，红黑树为平衡二叉树的一种。

​	**树的简单知识**

​		二叉树就是任何节点最多只允许有两个子节点，分别是左子结点和右子节点。

![image-20250622062307221](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250622062307221.png)	

​		二叉搜索树是指二叉树中的节点按照一定的规则进行排序，使得对二叉树中元素访问更加高效。二叉搜索树的放置规则是任何节点的元素值一定大于其左子树中的每一个节点的元素值，并且小于右子树的每一个节点的元素的值。因此，从根节点一直往左走，走到无路可走便可得到最小值，从根节点一直往右走，走到无路可走便可得到最大值。

![image-20250622062540800](C:\Users\admin\AppData\Roaming\Typora\typora-user-images\image-20250622062540800.png)

​		平衡二叉树不是完全平衡，是左子树和右子树的高度差的绝对值不超过1。

​	**set容器的使用**

```cpp
#include <iostream>
#include <set>

using namespace std;

void printSet(set<int>& s)		//set的遍历函数
{
	for (set<int>::iterator it = s.begin(); it != s.end(); it++)
	{
		cout << *it << ", ";
	}
	cout << endl;
}

int main()
{
	//构造函数
	set<int> s;
	multiset<int> ms;

	//插入元素
	s.insert(234);
	s.insert(123);
	s.insert(678);
	s.insert(123);
	printSet(s);		//输出123, 234, 678 可见其发生了排序和去重操作

	//删除元素
	set<int>::iterator it = s.begin();
	s.erase(it);
	printSet(s);		//输出234, 678
	//set也支持范围删除[begin，end）

	//查找:set容器中没有下标的概念
	set<int>::iterator target = s.find(234);	//查找元素是否存在，如果存在s.find()返回这个元素的迭代器，不存在返回set.end()
	cout << s.count(678) << endl;		//查找元素的个数，set中是1，因为不允许重复，但是multiset运行重复
	set<int>::iterator res1 = s.lower_bound(234);	//返回大于等于指定元素即789的第一个元素的迭代器
	set<int>::iterator res2 = s.upper_bound(567);	//返回大于指定元素即567的第一个元素的迭代器
	cout << *res1 << endl;		//输出234
	cout << *res2 << endl;		//输出678

	//大小
	cout << s.size() << endl;
	cout << s.empty() << endl;

	//multiset的使用与set一致

	return 0;
}
```

### **3.3.8map容器**

```cpp
#include <iostream>
#include <map>

using namespace std;

//pair介绍
void func_pair()
{
	//pair:将两个数据整合到一起，成为一个整体。
	//		这两个数据的数据类型可以不同，两个数据一个称为键（key），一个称为值（value）
	//第一种方式构建pair
	pair<string, int> p1("C++", 100);
	cout << p1.first << endl;
	cout << p1.second << endl;

	//第二种方式构建pair
	pair<string, int> p2 = make_pair("Python", 100);
	cout << p2.first << endl;
	cout << p2.second << endl;
}

//map存储的特点：
//	1.存储的元素一个个的pair
//	2.map中存储的键值对，会按照key进行排序
//	3.map容器中不允许出现重复的键。
//	4.map可以通过迭代器修改值，但是不允许修改键。

void printMap(map<string, int>& m)
{
	for (map<string, int>::iterator it = m.begin(); it != m.end(); it++)
	{
		cout << "key =  " << (*it).first << ", value = " << (*it).second << "\t";
	}
}

int main()
{
	//1.构造函数
	map<string, int> m;

	//2.插入元素,4种方式
	m.insert(pair<string, int>("Chinese", 99));
	m.insert(make_pair("Math", 100));
	m.insert(map<string, int>::value_type("English", 87));
	m["History"] = 93;		//map重载了运算符[]
	printMap(m);		//这里输出的顺序与添加元素的顺序不同，因为Map容器按照key来排序了
	m["Math"] = 120;	//如果添加的键值对，键已经存在了，那么此时就是一个修改操作
	printMap(m);		//输出中的Math对应值为120

	//删除操作
	m.erase(m.begin());
	printMap(m);		//Chinese 被删除了
	m.erase("History");	//按照键进行删除，删除一个键值对
	printMap(m);

	//查找操作
	map<string, int>::iterator p = m.find("English");	//查找的具有指定的键的键值对的迭代器
	
	//大小操作
	cout << m.size() << endl;
	cout << m.empty() << endl;

	return 0;
}

```

​	以上这些常用容器的操作很多都相同。

## 3.4算法

### 3.4.1函数对象

​	重载  **函数调用操作符即小括号（）**的类，其对象常称为函数对象，即它们是行为类似函数的对象，也叫仿函数（functor）。其实就是重载了（）操作符，使得类对象可以像函数那样调用。

​	注意函数对象是一个类，不是一个函数。

```cpp
#include <iostream>

using namespace std;

//定义自己的仿函数		也就是重载了()操作符的类
class MyPrint
{
public:
	int num;

	MyPrint() : num(0) {}

	void operator()(int n)		//第一个小括号表示我要重载()这个运算符，第二个小括号表示重载的运算符有几个参数
	{
		cout << n << endl;
	}
};

int main()
{
	MyPrint my;
	my(10);		//这里的小括号已经被重载了	输出10

	return 0;
}
```

### 3.4.2谓语的使用

​	谓语Predicate也是一种函数对象（仿函数）。如果一个函数对象（仿函数）中，重载的（）的返回值类型是bool类型，这样的函数对象（仿函数）其实就是谓语。

```cpp
#include <iostream>
#include <vector>
#include <algorithm>

using namespace std;

class Student
{
private:
	string _name;
	int _age;

public:
	Student() {};
	Student(string name, int age) : _name(name), _age(age) {};

	int age()
	{
		return _age;
	}

	void desc()
	{
		cout << "name = " << _name << ", age = " << _age << endl;
	}
};

class Yonger		//一元谓语
{
public:
	bool operator()(Student & s) const
	{
		return s.age() < 18;
	}

};

class MyComparator
{
public:
	bool operator()(Student& s1, Student& s2)
	{
		return s1.age() < s2.age();
	}


};

int main()
{
	vector<Student> v;
	v.push_back(Student("小红", 19));
	v.push_back(Student("小橙", 20));
	v.push_back(Student("小黄", 23));
	v.push_back(Student("小绿", 21));
	v.push_back(Student("小青", 16));
	v.push_back(Student("小蓝", 17));
	v.push_back(Student("小紫", 17));

	//需求：从容器中找到第一个未成年学生
	//find_if(start,end,predicate):从给定的范围中，查询满足条件的元素。如果找到了，返回这个元素的迭代器，如果没有找到，返回end
	vector<Student>::iterator it = find_if(v.begin(), v.end(), Yonger());

	if (it == v.end())
	{
		cout << "没有找到元素" << endl;
	}
	else
	{
		(*it).desc();
	}


	//需求2：将容器中的元素进行排序（按照年龄，进行升序排序）
	//sort(start,end,predicate);	使用指定的大小比较规则，对指定范围的元素进行排序
	sort(v.begin(), v.end(), MyComparator());

	for (Student& s : v)
	{
		s.desc();
	}

	return 0;
}
```

### 3.4.3系统内置仿函数

6 个算数类函数对象，除了 negate 是一元运算，其他都是二元运算。

template<class T> T plus<T>// 加法仿函数
template<class T> T minus<T>// 减法仿函数
template<class T> T multiplies<T>// 乘法仿函数
template<class T> T divides<T>// 除法仿函数
template<class T> T modulus<T>// 取模仿函数
template<class T> T negate<T>// 取反仿函数

6 个关系运算类函数对象，每一种都是二元运算。

template<class T> bool equal_to<T>// 等于
template<class T> bool not_equal_to<T>// 不等于
template<class T> bool greater<T>// 大于
template<class T> bool greater_equal<T>// 大于等于
template<class T> bool less<T>// 小于
template<class T> bool less_equal<T>// 小于等于

逻辑运算类函数对象，not 为一元运算，其余为二元运算。

template<class T> bool logical_and<T>// 逻辑与
template<class T> bool logical_or<T>// 逻辑或
template<class T> bool logical_not<T>// 逻辑非

例如

```c++
#include <iostream>
#include <functional>

using namespace std;

int main()
{
    negate<int> n;
    cout << n(5) << endl;	//输出-5
    
    minus<int> m;
    cout << m(10,3) << endl;	//输出7
    
    return 0;
}
```

### 3.4.4常用遍历算法

**for_each**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

vector<int> getVector()
{
	vector<int> v;
	for (int i = 0; i < 10; i++)
	{
		v.push_back(i);
	}
	return v;
}

/*
	遍历算法 遍历容器元素
	@param beg 开始迭代器
	@param end 结束迭代器
	@param_callback 函数回调或者函数对象
	@return 函数对象
*/
//for_each(iterator beg, iterator end, _callback);

class MyPrint 
{
public:
	void operator()(int i)
	{
		cout << i << ", ";
	}
};

void print(int i)
{
	cout << i << ", ";
}

void test01()
{
	//获取到需要遍历的数据容器
	vector<int> v = getVector();

	//使用for_each算法进行遍历，使用到的是函数对象（仿函数）
	for_each(v.begin(), v.end(), MyPrint());

	//使用for_each算法进行遍历，使用到的是普通函数
	for_each(v.begin(), v.end(), print);
}

int main()
{
	test01();

	return 0;
}
```

**transform**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

/*
	transform算法	将指定容器区间的元素搬运到另一容器中
	注意：transform不会自动给目标容器分配内存，所以需要我们提取分配好内存
	@param beg1	源容器开始迭代器
	@param end1 源容器结束迭代器
	@param beg2 目标容器开始迭代器
	@param _callback 回调函数或者函数对象
	@return 返回目标容器迭代器
*/

class NumberOperate
{
public:
	int operator()(int i)
	{
		return i + 100;
	}
};

class Print		//遍历仿函数
{
public:

	void operator()(int i)
	{
		cout << i << ", ";
	}
};

int main()
{
	vector<int> v1;		//创建源容器
	for (int i = 0; i < 10; i++)
	{
		v1.push_back(i);
	}

	vector<int> v2;		//创建目标容器
	v2.resize(v1.size());	//目标容器开辟空间

	//元素拷贝操作
	transform(v1.begin(), v1.end(), v2.begin(), NumberOperate());

	for_each(v2.begin(), v2.end(), Print());	//输出100, 101, 102, 103, 104, 105, 106, 107, 108, 109,

	return 0;
}
```

### 3.4.5查找算法

**find**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

/*
	find算法 查找元素
	@param beg 容器开始迭代
	@param end 容器结束迭代
	@param value 查找的元素
	@return 返回查找元素的迭代器

	find(iterator beg, iterator end, value)
*/

void test1()
{
	vector<int> v1;
	for (int i = 0; i < 10; i++)
	{
		v1.push_back(i);
	}

	//从这个容器中查找6
	vector<int>::iterator it1 = find(v1.begin(), v1.end(), 6);

	if (it1 == v1.end())
	{
		cout << "没有找到这个元素" << endl;
	}
	else
	{
		cout << "找到了指定元素" <<  *(it1) << endl;
	}

}

class Person
{
public:
	string name;
	int age;

	Person() {}
	Person(string n, int a) : name(n), age(a) {}

	bool operator==(const Person& p)
	{
		return (name == p.name) && (age == p.age);
	}


};

void test2()
{
	vector<Person> v2;
	v2.push_back(Person("小红", 19));
	v2.push_back(Person("小橙", 20));
	v2.push_back(Person("小黄", 23));
	v2.push_back(Person("小绿", 21));
	v2.push_back(Person("小青", 16));
	v2.push_back(Person("小蓝", 17));
	v2.push_back(Person("小紫", 17));

	vector<Person>::iterator it2 = find(v2.begin(), v2.end(), Person("小蓝", 17));
	if (it2 == v2.end())		//这里要在Person中重载==运算符，因为两个Person对象不能比较
	{
		cout << "没有找到这个人" << endl;
	}
	else
	{
		cout << "找到这个人了" << endl;
	}


}

int main()
{
	test1();		//输出 找到了指定元素6
	test2();		//输出 找到了这个人

	return 0;
}
```

**adjacent_find**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

//版本一
/*
	adjacent_find算法 查找相邻重复元素
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@return 返回相邻元素的第一个位置的迭代器
*/

//版本二
/*
	adjacent_find算法 查找相邻重复元素
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param _callback 回调函数或者谓语（返回值为bool类型的函数对象）
	@return 返回相邻元素的第一个位置的迭代器
*/


class Person
{
public:
	string name;
	int age;

	Person() {}
	Person(string n, int a) : name(n), age(a) {}
};

struct PersonEqualPredicate		//二元谓语，定义比较规则
{
	bool operator() (const Person & p1, const Person & p2)
	{
		return (p1.name == p2.name) && (p1.age == p2.age);
	}
};

void test_2()
{
	vector<Person> v2;
	v2.push_back(Person("小红", 19));
	v2.push_back(Person("小橙", 20));
	v2.push_back(Person("小红", 19));
	v2.push_back(Person("小黄", 23));
	v2.push_back(Person("小黄", 23));
	v2.push_back(Person("小绿", 21));
	v2.push_back(Person("小青", 16));
	v2.push_back(Person("小蓝", 17));
	v2.push_back(Person("小紫", 17));
	v2.push_back(Person("小青", 16));

	vector<Person>::iterator it2 = adjacent_find(v2.begin(), v2.end(), PersonEqualPredicate());

	if (it2 == v2.end())
	{
		cout << "没有找到" << endl;
	}
	else
	{
		cout << "找到了" << " name = " << it2->name << " age = " << it2->age << endl;
	}
}

void test_1()
{
	vector<int> v1;
	v1.push_back(1);
	v1.push_back(2);
	v1.push_back(3);
	v1.push_back(2);
	v1.push_back(5);
	v1.push_back(5);
	v1.push_back(6);
	v1.push_back(1);

	vector<int>::iterator it1 = adjacent_find(v1.begin(), v1.end());
	if (it1 == v1.end())
	{
		cout << "没有找到" << endl;
	}
	else
	{
		cout << "找到了" << *it1 << endl;
	}
}

int main()
{
	test_1();		//输出找到了5
	test_2();		//输出找到了 name = 小黄 age = 23

	return 0;
}
```

**binary_search**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

/*
	binary_search算法  二分查找法
	注意：必须在有序序列中使用
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param value 查找的元素
	@return bool 找到返回true，否则返回false
	bool binary_search(iterator beg, iterator end, value);
*/

int main()
{
	vector<int> v;
	v.push_back(1);
	v.push_back(3);
	v.push_back(4);
	v.push_back(6);
	v.push_back(12);
	v.push_back(95);
	v.push_back(923);
	v.push_back(2876);		//注意要是有序序列

	cout << binary_search(v.begin(), v.end(), 95) << endl;		//输出1
	cout << binary_search(v.begin(), v.end(), 95213) << endl;	//输出0

	return 0;
}
```

**count算法**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

/*
	count算法  统计元素出现次数
	如果比较的是自定义的类型，例如类、结构体等，此时需要配合==运算符重载，和find里一样
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param value 回调函数或者谓语（返回bool类型的函数对象）
	@return int 返回元素个数
	count(iterator beg, iterator end, value);
*/

/*
	count_if算法  统计元素出现次数
	如果比较的是自定义的类型，例如类、结构体等，此时需要配合==运算符重载，和find里一样
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param callback 回调函数或者谓语（返回bool类型的函数对象）
	@return int 返回元素个数
	count(iterator beg, iterator end, _callback);
*/

struct oddPredicate
{
	bool operator()(int n)
	{
		return n % 2 == 1;
	}

};
int main()
{
	int arr[] = { 1, 2, 3, 4, 5, 6, 7, 2, 3, 3, 2, 2, 3, 4, 9 };
	vector<int> v(arr, arr + sizeof(arr) / sizeof(int));

	//查找3出现了多少次
	cout << count(v.begin(), v.end(), 3) << endl;		//输出4

	//查找出现了多少次奇数
	cout << count_if(v.begin(), v.end(), oddPredicate());	//输出8

	return 0;
}
```

**3.4.6排序算法**

**sort**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>
using namespace std;
/*
	sort算法  容器排序算法
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param _callback 回调函数或者谓语（返回bool类型的函数对象）
	sort(iterator beg, iterator end, _callback);
*/
struct Print
{
	void operator()(int n)
	{
		cout << n << ", ";
	}
};

class Student
{
public:
	string name;
	int age;
	Student() {}
	Student(string n, int a) : name(n), age(a) {}
};
struct StudentCompare		//定义谓语
{
	bool operator()(const Student& p1, const Student& p2)
	{
		return p1.age < p2.age;
	}
};
void test_01()
{
	int arr[] = { 1,3,5,7,9,0,2,4,6,8 };
	vector<int> v(arr, arr + sizeof(arr) / sizeof(int));

	//对元素进行排序
	sort(v.begin(), v.end());
	for_each(v.begin(), v.end(), Print());
	cout << endl;

	//降序排序
	sort(v.begin(), v.end(), greater<int>());	//greater是内置的函数对象
	for_each(v.begin(), v.end(), Print());
	cout << endl;
}
void test_02()
{
	vector<Student> v;
	v.push_back(Student("小红", 19));
	v.push_back(Student("小橙", 20));
	v.push_back(Student("小红", 19));
	v.push_back(Student("小黄", 23));
	v.push_back(Student("小黄", 23));
	v.push_back(Student("小绿", 21));
	v.push_back(Student("小青", 16));
	v.push_back(Student("小蓝", 17));
	v.push_back(Student("小紫", 17));
	v.push_back(Student("小青", 16));
	sort(v.begin(), v.end(), StudentCompare());
	for (Student& s : v)
	{
		cout << s.name << ", " << s.age << endl;
	}
}
int main()
{
	test_01();
	test_02();

	return 0;
}
```

**merge**

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

/*
	merge算法 容器元素合并，并存储到另一容器中
	注意两个容器必须是有序的
	@param beg1 容器1开始迭代器
	@param end1 容器1结束迭代器
	@param beg2 容器2开始迭代器
	@param end2 容器2结束迭代器
	@param dest 目标容器开始迭代器

	merge(iterator beg1, iterator end1, iterator beg2, iterator end2, iterator dest)
*/

void Print(int i)
{
	cout << i << ", ";
}

int main()
{
	int arr1[] = { 1,3,5,7,9 };
	int arr2[] = { 0,2,4,6,8 };
	vector<int> v1(arr1, arr1 + sizeof(arr1) / sizeof(int));
	vector<int> v2(arr2, arr2 + sizeof(arr2) / sizeof(int));
	vector<int> v3;
	v3.resize(v1.size() + v2.size());
	merge(v1.begin(), v1.end(), v2.begin(), v2.end(), v3.begin());
	for_each(v3.begin(), v3.end(), Print);	//使用普通函数做参数
    //输出0,1,2,3,4,5,6,7,8,9


	return 0;
}
```

### 3.4.6拷贝替换算法

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

struct Print
{
	void operator()(int i)
	{
		cout << i << ", ";
	}

};

/*
	copy算法 将容器内指定范围的元素拷贝到另一容器中
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param dest 目标起始迭代器

	copy(iterator beg, iterator end, iterator dest)
*/

void test01()
{
	vector<int> v1;
	v1.push_back(10);
	v1.push_back(12);
	v1.push_back(15);
	v1.push_back(16);
	v1.push_back(13);
	v1.push_back(18);
	vector<int> v2;
	v2.resize(v1.size());

	//元素拷贝
	copy(v1.begin(), v1.end(), v2.begin());
	for_each(v2.begin(), v2.end(), Print());
	cout << endl;
}

/*
	replace算法 将容器内指定范围的旧元素修改为新元素
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param oldvalue 旧元素
	@param oldvalue 新元素

	replace(iterator beg, iterator end, oldvalue, newvalue)
*/

void test02()
{
	vector<int> v1;
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(2);
	v1.push_back(5);
	//需求：将容器中的1都替换成100
	replace(v1.begin(), v1.end(), 1, 100);
	for_each(v1.begin(), v1.end(), Print());
	cout << endl;
}

/*
	replace_if算法 将容器内指定范围满足条件的元素替换为新元素
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param callback 回调函数或者谓词(返回Bool类型的函数对象)
	@param oldvalue 新元素

	replace_if(iterator beg, iterator end, _callback, newvalue)
*/

struct Odd
{
	bool operator()(int i)
	{
		return i % 2 != 0;
	}

};

void test03()
{
	vector<int> v1;
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(1);
	v1.push_back(2);
	v1.push_back(5);

	//需求：将容器中的奇数都替换成100
	replace_if(v1.begin(), v1.end(), Odd(), 100);
	for_each(v1.begin(), v1.end(),Print());
	cout << endl;

}

/*
	swap算法 互换两个容器的元素
	@param c1 容器1
	@param c2 容器2

	swap(container c1, container c2)
*/

void test04()
{
	int arr1[] = { 1,3,5,7,9 };
	int arr2[] = { 0,2,4,6,8 };
	vector<int> v1(arr1, arr1 + sizeof(arr1) / sizeof(int));
	vector<int> v2(arr2, arr2 + sizeof(arr2) / sizeof(int));
	swap(v1, v2);
	for_each(v1.begin(), v1.end(), Print());
	cout << endl;
	for_each(v2.begin(), v2.end(), Print());

}

int main()
{
	test01();
	test02();
	test03();
	test04();

	return 0;
}
```

### 3.4.7算术生成算法

```cpp
#include <iostream>
#include <algorithm>
#include <vector>
#include <numeric>

using namespace std;

struct Print
{
	void operator()(int i)
	{
		cout << i << ", ";
	}
};

/*
accumulate算法 计算容器元素累计总和
@param beg 容器开始迭代器
@param end 容器结束迭代器
@param value 累加值

accumulate(iterator beg, iterator end, value)
*/

int main()
{
	/*
	accumulate算法 计算容器元素累计总和
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param value 累加值
	
	accumulate(iterator beg, iterator end, value)
	*/

	vector<int> v1(5, 10);
	cout << accumulate(v1.begin(), v1.end(), 10);		//输出60,5个10 再加10
	cout << endl;

	/*
	fill算法 向容器中添加元素
	@param beg 容器开始迭代器
	@param end 容器结束迭代器
	@param value 填充元素

	fill(iterator beg, iterator end, value)
	*/

	vector<int> v2(5, 10);
	fill(v2.begin(), v2.end(), 100);
	for_each(v2.begin(), v2.end(), Print());


	return 0;
};
```

### 3.4.8常用集合算法

```cpp
#include <iostream>
#include <algorithm>
#include <vector>

using namespace std;

struct Print
{
	void operator()(int n)
	{
		cout << n << ", ";
	}

};


int main()
{
	/*
	set_intersection算法 求两个set集合的交集
	注意:两个集合必须是升序序列
	@param beg1 容器1开始迭代器
	@param end1 容器1结束迭代器
	@param beg2 容器2开始迭代器
	@param end2 容器2结束迭代器
	@param dest 目标容器开始迭代器
	@return 目标容器的最后一个元素的迭代器地址
	set_intersectionion(iterator beg1, iterator end1, iterator beg2, iterator end2, iterator dest)
	*/

	int arr1[] = { 1,2,3,4,5,6,7,8 };
	int arr2[] = { 1,2,3,5,6,8,9 };
	vector<int> v1(arr1, arr1 + sizeof(arr1) / sizeof(int));
	vector<int> v2(arr2, arr2 + sizeof(arr2) / sizeof(int));
	vector<int> res1;
	res1.resize(min(v1.size(), v2.size()));

	vector<int>::iterator it1 = set_intersection(v1.begin(), v1.end(), v2.begin(), v2.end(), res1.begin());
	for_each(res1.begin(), it1, Print());
	cout << endl;

	/*
	set_union算法 求两个set集合的并集
	注意:两个集合必须是升序序列
	@param beg1 容器1开始迭代器
	@param end1 容器1结束迭代器
	@param beg2 容器2开始迭代器
	@param end2 容器2结束迭代器
	@param dest 目标容器开始迭代器
	@return 目标容器的最后一个元素的迭代器地址
	set_union(iterator beg1, iterator end1, iterator beg2, iterator end2, iterator dest)
	*/

	vector<int> res2;
	res2.resize(v1.size() + v2.size());
	vector<int>::iterator it2 = set_union(v1.begin(), v1.end(), v2.begin(), v2.end(), res2.begin());
	for_each(res2.begin(), it2, Print());
	cout << endl;

	/*
	set_difference算法 求两个set集合的差集
	注意:两个集合必须是升序序列
	@param beg1 容器1开始迭代器
	@param end1 容器1结束迭代器
	@param beg2 容器2开始迭代器
	@param end2 容器2结束迭代器
	@param dest 目标容器开始迭代器
	@return 目标容器的最后一个元素的迭代器地址
	set_difference(iterator beg1, iterator end1, iterator beg2, iterator end2, iterator dest)
	*/

	int	arr3[] = { 1,2,3,4,5,6,7,8,9 };
	int	arr4[] = { 1,3,5,7,9,11 };
	vector<int> v3(arr3, arr3 + sizeof(arr3) / sizeof(int));
	vector<int> v4(arr4, arr4 + sizeof(arr4) / sizeof(int));

	vector<int> res3;
	res3.resize(max(v3.size(), v4.size()));

	vector<int>::iterator it3 = set_difference(v3.begin(), v3.end(), v4.begin(), v4.end(), res3.begin());
	for_each(res3.begin(), it3, Print());
	cout << endl;

	return 0;
}
```

