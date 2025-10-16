#

## Linux 系统操作全面指南

> 💡 **推荐资源**：
>
> - [Linux教程/Linux命令导航（中文版）](https://www.runoob.com/linux/linux-command-manual.html)
> - [Linux命令行教程](https://linuxcommand.org/)
> - [命令速查表](https://cheatography.com/davechild/cheat-sheets/linux-command-line/)

掌握 Linux 系统操作是每个开发者和系统管理员的必备技能。以下是 Linux 核心操作的详细指南：

---

### 一、基础文件操作

1. **查看目录内容**：

   ```bash
   ls           # 简单列表
   ls -l        # 详细列表（权限/大小/时间）
   ls -a        # 显示隐藏文件（以.开头）
   ```

2. **目录导航**：

   ```bash
   pwd          # 显示当前目录
   cd ~         # 返回家目录
   cd /path     # 进入绝对路径
   cd ..        # 返回上级目录
   ```

3. **文件操作**：

   ```bash
   touch file.txt     # 创建空文件
   cp file.txt copy/  # 复制文件
   mv file.txt new/   # 移动/重命名文件
   rm file.txt        # 删除文件（谨慎使用！）
   ```

---

### 二、文本处理（核心技能）

1. **查看文件内容**：

   ```bash
   cat file.txt      # 显示全部内容
   head -n 5 file    # 显示前5行
   tail -f log.log   # 实时监控日志文件
   less file         # 分页浏览（支持搜索）
   ```

2. **文本搜索**：

   ```bash
   grep "error" *.log  # 在日志中搜索"error"
   grep -r "pattern" /dir  # 递归搜索目录
   ```

3. **文本编辑**：

   ```bash
   nano file       # 简单编辑器
   vim file        # 高级编辑器（学习曲线陡峭）
   ```

---

### 三、系统管理

1. **权限管理**：

   ```bash
   chmod 755 script.sh   # 设置可执行权限
   chown user:group file  # 修改文件所有者
   sudo command           # 以管理员权限执行
   ```

2. **进程管理**：

   ```bash
   ps aux          # 查看所有进程
   top             # 实时进程监控
   kill 1234       # 终止进程ID为1234的进程
   killall chrome  # 终止所有Chrome进程
   ```

3. **磁盘管理**：

   ```bash
   df -h           # 查看磁盘使用情况
   du -sh dir      # 查看目录大小
   free -h         # 查看内存使用
   ```

---

### 四、网络操作

1. **连接测试**：

   ```bash
   ping google.com      # 测试网络连通性
   traceroute google.com # 跟踪网络路径
   ```

2. **端口检查**：

   ```bash
   netstat -tuln       # 查看监听端口
   ss -tuln            # 更现代的替代方案
   ```

3. **文件传输**：

   ```bash
   scp file user@server:/path  # 安全复制
   wget https://example.com/file.zip  # 下载文件
   ```

---

### 五、软件管理（包管理器）

| 系统 | 命令 | 功能 |
|------|------|------|
| **Debian/Ubuntu** | `sudo apt update` | 更新软件源列表 |
| | `sudo apt install package` | 安装软件 |
| | `sudo apt remove package` | 移除软件 |
| **CentOS/RHEL** | `sudo yum update` | 更新系统 |
| | `sudo yum install package` | 安装软件 |
| **Arch** | `sudo pacman -Syu` | 更新系统 |
| | `sudo pacman -S package` | 安装软件 |

---

### 六、Shell 脚本基础

1. **创建脚本**：

   ```bash
   #!/bin/bash
   echo "Hello, $USER!"
   date
   ```

2. **执行脚本**：

   ```bash
   chmod +x myscript.sh  # 添加执行权限
   ./myscript.sh         # 执行脚本
   ```

3. **实用技巧**：

   ```bash
   $?          # 上条命令的退出码（0=成功）
   $1, $2      # 脚本参数
   $#          # 参数个数
   ```

---

### 七、实用技巧

1. **历史命令**：

   ```bash
   history     # 查看命令历史
   !23         # 执行历史记录中第23条命令
   Ctrl+R      # 反向搜索历史命令
   ```

2. **任务管理**：

   ```bash
   command &   # 后台运行
   jobs        # 查看后台任务
   fg %1       # 将任务1调到前台
   ```

3. **文件查找**：

   ```bash
   find / -name "*.conf"  # 全盘查找配置文件
   locate filename        # 快速查找（需先运行updatedb）
   ```

---

### 八、学习路径建议

1. **新手阶段**：
   - 掌握基础命令：`ls`, `cd`, `cat`, `grep`
   - 学习文件权限管理
   - 练习文本编辑（建议从nano开始）

2. **进阶阶段**：
   - 掌握管道操作：`|`
   - 学习正则表达式
   - 编写自动化脚本

3. **高手阶段**：
   - 掌握sed/awk高级文本处理
   - 学习系统调优和内核参数
   - 掌握容器化技术（Docker）

通过系统学习和持续实践，你将逐步掌握Linux系统的强大功能，提高工作效率和解决问题的能力。