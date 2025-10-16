HTML 学习指南



一、HTML 基础认知



### 1.1  HTML&#xA;

HTML（HyperText Markup Language）即超文本标记语言，是用于创建网页的标准标记语言。它通过一系列标签来描述网页的结构和内容，比如文字、图片、链接等元素。


### 1.2 HTML 的作用&#xA;



*   定义网页的结构，确定不同内容的布局和层级关系。


*   标记文本的语义，如标题、段落、列表等，让浏览器能正确解析和展示。


*   实现网页中的超链接、图片嵌入等基本功能。


二、HTML 基本结构



一个完整的 HTML 文档具有固定的基本结构，如下所示：




```
\<!DOCTYPE html>


\<html>

\<head>

&#x20;   \<meta charset="UTF-8">

&#x20;   \<title>页面标题\</title>

\</head>

\<body>

&#x20;   \<!-- 网页内容在这里 -->

&#x20;   \<h1>欢迎学习 HTML\</h1>

&#x20;   \<p>这是一个段落。\</p>

\</body>

\</html>
```



*   `<!DOCTYPE html>`：声明文档类型，告知浏览器这是一个 HTML5 文档。


*   `<html>`：根元素，包裹整个 HTML 文档的内容。


*   `<head>`：包含文档的元数据，如字符集、标题等，这些内容不会直接显示在网页上。


*   `<meta charset="UTF-8">`：指定文档的字符编码为 UTF-8，确保能正确显示各种语言的字符。


*   `<title>`：定义网页的标题，会显示在浏览器的标题栏或标签页上。


*   `<body>`：包含网页的可见内容，如文本、图片、链接等。


三、常用 HTML 标签



### 3.1 文本标签&#xA;



*   `<h1>` 到 `<h6>`：用于定义标题，`<h1>` 是最大的标题，`<h6>` 是最小的标题。




```
\<h1>一级标题\</h1>


\<h2>二级标题\</h2>
```



*   `<p>`：定义段落。




```
\<p>这是一个段落内容。\</p>
```



*   `<br>`：用于换行。




```
\<p>这是第一行\<br>这是第二行\</p>
```



*   `<strong>` 和 `<em>`：`<strong>` 用于强调文本，使文本加粗；`<em>` 用于斜体强调文本。




```
\<p>这是\<strong>加粗\</strong>的文本，这是\<em>斜体\</em>的文本。\</p>
```

### 3.2 链接标签&#xA;

`<a>` 标签用于创建超链接，通过 `href` 属性指定链接的目标地址。




```
\<a href="https://www.example.com">访问示例网站\</a>
```

`target` 属性可指定链接的打开方式，`_blank` 表示在新窗口打开。




```
\<a href="https://www.example.com" target="\_blank">在新窗口打开示例网站\</a>
```

### 3.3 图片标签&#xA;

`<img>` 标签用于嵌入图片，`src` 属性指定图片的路径，`alt` 属性为图片添加替代文本（当图片无法显示时显示）。




```
\<img src="image.jpg" alt="这是一张示例图片">
```

### 3.4 列表标签&#xA;



*   无序列表 `<ul>`，列表项用 `<li>` 表示。




```
\<ul>


&#x20;   \<li>列表项 1\</li>

&#x20;   \<li>列表项 2\</li>

\</ul>
```



*   有序列表 `<ol>`，列表项同样用 `<li>` 表示，会自动编号。




```
\<ol>


&#x20;   \<li>第一步\</li>

&#x20;   \<li>第二步\</li>

\</ol>
```

### 3.5 表格标签&#xA;

`<table>` 用于创建表格，`<tr>` 表示表格行，`<td>` 表示表格单元格，`<th>` 表示表头单元格（通常加粗居中显示）。




```
\<table border="1">


&#x20;   \<tr>

&#x20;       \<th>姓名\</th>

&#x20;       \<th>年龄\</th>

&#x20;   \</tr>

&#x20;   \<tr>

&#x20;       \<td>张三\</td>

&#x20;       \<td>20\</td>

&#x20;   \</tr>

\</table>
```

`border` 属性用于设置表格边框的宽度。


四、HTML 表单



表单用于收集用户输入的数据，`<form>` 标签用于创建表单，常用的表单元素有：




*   `<input type="text">`：单行文本输入框。


*   `<input type="password">`：密码输入框，输入的内容会被隐藏。


*   `<input type="radio">`：单选按钮，`name` 属性相同的单选按钮为一组，只能选择其中一个。


*   `<input type="checkbox">`：复选框，可选择多个。


*   `<select>` 和 `<option>`：下拉选择框，`<option>` 表示选项。


*   `<textarea>`：多行文本输入框。


*   `<input type="submit">`：提交按钮，用于提交表单数据。


示例：




```
\<form action="/submit" method="post">


&#x20;   \<label for="name">姓名：\</label>

&#x20;   \<input type="text" id="name" name="name">\<br>


&#x20;  &#x20;


&#x20;   \<label for="age">年龄：\</label>


&#x20;   \<input type="number" id="age" name="age">\<br>


&#x20;  &#x20;


&#x20;   \<input type="submit" value="提交">


\</form>
```

`action` 属性指定表单数据提交的地址，`method` 属性指定提交方式（`get` 或 `post`）。


五、HTML 语义化



语义化是指使用合适的 HTML 标签来表达内容的含义，而不是仅仅为了样式。语义化的好处：




*   提高代码的可读性和可维护性。


*   有助于搜索引擎优化（SEO），让搜索引擎更好地理解网页内容。


*   方便屏幕阅读器等辅助设备解析网页，提升 accessibility（可访问性）。


常用的语义化标签：




*   `<header>`：定义网页或 section 的头部，通常包含标题、导航等。


*   `<nav>`：定义导航链接区域。


*   `<main>`：定义网页的主要内容区域，一个页面通常只有一个 `<main>`。


*   `<section>`：定义文档中的节、区域，通常包含一个主题的内容。


*   `<article>`：定义独立的、完整的内容，如博客文章、新闻报道等。


*   `<aside>`：定义与主要内容相关的辅助信息，如侧边栏。


*   `<footer>`：定义网页或 section 的底部，通常包含版权信息、联系方式等。


六、HTML5 新特性



HTML5 引入了许多新的特性和标签，除了上述的语义化标签外，还有：




*   多媒体标签 `<video>` 和 `<audio>`，用于嵌入视频和音频。




```
\<video src="video.mp4" controls>您的浏览器不支持视频播放\</video>


\<audio src="audio.mp3" controls>您的浏览器不支持音频播放\</audio>
```

`controls` 属性用于显示播放控制按钮。




*   本地存储 `localStorage` 和 `sessionStorage`，可在客户端存储数据。


*   画布 `<canvas>`，用于绘制图形、动画等。


七、学习资源与实践建议



### 7.1 学习资源&#xA;



*   **在线教程**：W3Schools（[https://www.w3schools.com/html/](https://www.w3schools.com/html/)）、MDN Web Docs（[https://developer.mozilla.org/zh-CN/docs/Web/HTML](https://developer.mozilla.org/zh-CN/docs/Web/HTML)）。


*   **书籍**：《HTML & CSS：设计与构建网站》、《Head First HTML 与 CSS》。


*   **视频课程**：慕课网、网易云课堂等平台的 HTML 相关课程。

