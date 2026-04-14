---
name: coredump-package-management
description: 下载和安装deb包及调试符号包。从内部构建服务器下载指定版本的deb包和dbgsym包，支持批量下载。用于：(1) 生成下载任务列表 (2) 下载deb包和调试包 (3) 安装deb包 (4) 批量下载多个包。触发词：下载deb包、下载调试包、dbgsym下载、安装包、dpkg安装。
---

# Coredump 包管理

下载和安装崩溃对应的 deb 包和调试符号包。

## 工作目录

设置环境变量（根据实际路径修改）：

```bash
export COREDUMP_WORKSPACE="/path/to/coredump/workspace"
cd $COREDUMP_WORKSPACE/4.包管理
```

或使用相对路径：

```bash
cd <workspace>/4.包管理
```

## 脚本位置

```bash
/home/wubw/.nvm/versions/node/v24.14.1/lib/node_modules/openclaw/skills/coredump-package-management/scripts/
├── generate_tasks.py      # 生成下载任务
└── scan_and_download.py  # 下载并安装包
```

## 工作流程

```
生成任务 → 下载包 → 安装包
```

## 1. 生成下载任务

从崩溃数据生成下载任务列表：

```bash
cd 下载包
python3 generate_tasks.py
```

**输入**: `../2.数据筛选/filtered_crash_data.csv`

**输出**: `download_tasks.json`

**任务文件格式**：
```json
{
  "generated_at": "2026-04-07T16:00:00",
  "total_tasks": 50,
  "total_files": 100,
  "tasks": [
    {
      "package": "dde-control-center",
      "version": "5.7.41.11",
      "arch": "amd64",
      "count": 45,
      "priority": "high",
      "status": "pending",
      "downloaded_files": []
    }
  ]
}
```

**优先级分配**：
- 🔴 高优先级：>=45次崩溃
- 🟡 中优先级：20-44次崩溃
- 🟢 低优先级：<20次崩溃

## 2. 下载包

### 从内部构建服务器下载（推荐）

```bash
python3 scan_and_download.py --batch download_tasks.json
```

**选项**：
- `--batch <file>`: 批量下载任务文件
- `--arch <arch>`: 架构（默认 amd64）
- `--output-dir <dir>`: 输出目录（默认 ./downloads）
- `-n <number>`: 扫描的最大task_id数量

**特点**：
- 无需 Cookie 认证
- 自动下载主包和 dbgsym 包
- 支持断点续传

### 从 Shuttle 下载（需要Cookie）

```bash
# 先获取Cookie
python3 get_cookie.py

# 然后下载
python3 download_from_shuttle_v2.py
```

### 单个包下载

```bash
python3 scan_and_download.py <package> <version>

# 示例
python3 scan_and_download.py dde-control-center 5.7.41.11
```

## 3. 安装包

### 手动安装

```bash
cd downloads

# 安装主包
sudo dpkg -i <package>_<version>_<arch>.deb

# 安装调试包
sudo dpkg -i <package>-dbgsym_<version>_<arch>.deb

# 修复依赖
sudo apt-get install -f
```

### 使用脚本安装

```bash
cd ../安装包
python3 install_package.py
```

## 输出文件

下载的文件保存在：
```
下载包/downloads/
├── dde-control-center_5.7.41.11_amd64.deb
├── dde-control-center-dbgsym_5.7.41.11_amd64.deb
├── dde-dock_5.7.16.1_amd64.deb
└── dde-dock-dbgsym_5.7.16.1_amd64.deb
```

## 配置

### 内部构建服务器

```bash
DEFAULT_BASE_URL = "http://10.0.32.60:5001"
DEFAULT_ARCH = "amd64"
DEFAULT_SUBDIR = "unstable-amd64"
```

### 下载日志

下载过程记录在 `download.log`：
```
2026-04-07 16:00:00 [INFO] 正在扫描 task_id 范围: 1000 ~ 50000
2026-04-07 16:00:05 [INFO] 找到 dde-control-center_5.7.41.11_amd64.deb
2026-04-07 16:00:06 [INFO] 下载完成: dde-control-center_5.7.41.11_amd64.deb
```

## 使用示例

### 完整流程

```bash
# 1. 生成任务
cd $COREDUMP_WORKSPACE/4.包管理/下载包
python3 generate_tasks.py

# 2. 批量下载
python3 scan_and_download.py --batch download_tasks.json

# 3. 安装包
cd downloads
sudo dpkg -i *.deb
```

### 下载指定包

```bash
cd $COREDUMP_WORKSPACE/4.包管理/下载包

# 下载单个包
python3 scan_and_download.py dde-control-center 5.7.41.11

# 批量下载（高优先级）
python3 scan_and_download.py --batch download_tasks.json
```

## 输出示例

### generate_tasks.py

```
读取崩溃数据: <workspace>/2.数据筛选/filtered_crash_data.csv

✅ 任务生成完成！
   总计: 50 个包版本
   文件数: 100（主包 + 调试包）

优先级分布:
   🔴 高优先级（>=45次崩溃）: 10
   🟡 中优先级（20-44次崩溃）: 15
   🟢 低优先级（<20次崩溃）: 25

📋 前10个任务:
    1. dde-control-center         v5.7.41.11       -  45 次 🔴
    2. dde-dock                   v5.7.16.1        -  32 次 🟡

文件已保存到: download_tasks.json
```

### scan_and_download.py

```
2026-04-07 16:00:00 [INFO] 开始批量下载...
2026-04-07 16:00:00 [INFO] 任务总数: 50
2026-04-07 16:00:01 [INFO] 正在从 http://10.0.32.60:5001/tasks/ 获取 task_id 列表...
2026-04-07 16:00:02 [INFO] 找到 50000 个 task_id
2026-04-07 16:00:03 [INFO] 范围: 1000 ~ 50000

[1/50] dde-control-center v5.7.41.11
  扫描 task_id: 50000 → 45000 → 40000 → ...
  找到: dde-control-center_5.7.41.11_amd64.deb
  下载中... ████████████████████ 100%
  找到: dde-control-center-dbgsym_5.7.41.11_amd64.deb
  下载中... ████████████████████ 100%
  ✅ 完成

下载统计:
  成功: 98 个文件
  失败: 2 个文件
  总大小: 500 MB
```

## 常见问题

**Q: 找不到指定版本的包**

检查版本号是否正确，尝试使用相似版本。

**Q: 下载速度慢**

内部构建服务器速度较快，优先使用 `scan_and_download.py`。

**Q: 安装失败，提示依赖问题**

使用 `sudo apt-get install -f` 修复依赖。

**Q: sudo 不可用**

跳过安装步骤，后续分析时手动安装。

## 注意事项

- 调试包（dbgsym）对于堆栈分析很重要
- 不同架构的包需要分别下载
- 安装调试包后可以用 addr2line 定位源码行号
