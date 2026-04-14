---
name: coredump-crash-analysis
description: 分析崩溃堆栈，定位崩溃原因，提供修复建议。识别SIGSEGV/SIGABRT/SIGBUS等信号类型，定位应用层崩溃函数，判断项目内/外崩溃，生成GDB调试命令和addr2line定位指令。用于：(1) 分析崩溃堆栈 (2) 定位崩溃代码 (3) 判断崩溃类型 (4) 提供修复建议 (5) 生成调试命令。触发词：崩溃分析、堆栈分析、GDB调试、addr2line、崩溃定位。
---

# Coredump 崩溃分析

分析崩溃堆栈，定位问题原因，提供修复建议。

## 目录结构

```
coredump-crash-analysis/
├── SKILL.md                          # 本文件
├── scripts/
│   └── analyze_crash_final.py         # 崩溃分析脚本
├── centralized/                      # 通用分析模块
│   ├── __init__.py                   # 包导出
│   ├── models.py                     # 通用数据模型
│   ├── base_config.py                # 通用系统库/插件库配置
│   ├── gerrit_client.py              # 通用Gerrit SSH客户端
│   ├── crash_classifier.py           # 通用崩溃分类器
│   ├── fix_mapper.py                 # 通用崩溃→修复映射器
│   └── report_generator.py            # 通用报告生成器
└── references/
```

## 快速开始

### 完整流程分析

```bash
cd /home/wubw/skills/coredump-full-analysis/scripts
bash analyze_crash_complete.sh --package dde-dock --workspace /home/wubw/workspace
```

### 单独运行崩溃分析

```bash
cd /home/wubw/skills/coredump-crash-analysis/scripts
python3 analyze_crash_final.py --package dde-dock --workspace /home/wubw/workspace
```

## 通用模块 (centralized/)

通用崩溃分析模块，可被多个 coredump-* skills 复用。

### 模块说明

| 模块 | 功能 | 使用方式 |
|------|------|---------|
| `models.py` | 数据模型 (CrashRecord, FixMapping等) | `from centralized import CrashRecord` |
| `base_config.py` | 系统库/插件库列表配置 | `from centralized import SYSTEM_LIBRARIES` |
| `gerrit_client.py` | Gerrit SSH 客户端 | `GerritClient(project="dde-dock")` |
| `crash_classifier.py` | 崩溃分类 (app/system/plugin) | `CrashClassifier.for_package("dde-dock")` |
| `fix_mapper.py` | 崩溃→修复映射 | `FixMapper.create_for_dde_dock()` |
| `report_generator.py` | Markdown 报告生成 | `ReportGenerator("dde-dock")` |

### 使用示例

```python
from centralized import (
    CrashClassifier,
    FixMapper,
    GerritClient,
    ReportGenerator,
    CrashRecord,
)

# 1. 创建分类器（自动适配包名）
classifier = CrashClassifier.for_package("dde-dock")
# 或者手动配置
classifier = CrashClassifier(ClassifierConfig(
    app_layer_patterns=["dde-dock", "AppDragWidget"],
    app_name_in_stack="dde-dock"
))

# 2. 分类崩溃
app_crashes, sys_crashes, plugin_crashes = classifier.classify_batch(records)

# 3. 创建修复映射器
fix_mapper = FixMapper.create_for_dde_dock()

# 4. 查询Gerrit
gerrit = GerritClient()
change_url = gerrit.get_change_url("3d9fef0", project="dde-dock")

# 5. 生成报告
report_gen = ReportGenerator("dde-dock")
report = report_gen.generate_report(version_analyses, statistics, all_fixes, gerrit)
```

## 分析流程

```
读取CSV → 解析堆栈 → 识别信号类型 → 定位关键帧 → 判断崩溃类型 → 关联Gerrit修复 → 生成报告
```

## 信号类型说明

| 信号 | 含义 | 常见原因 | 修复建议 |
|------|------|----------|----------|
| SIGSEGV | 段错误 | 空指针、野指针、越界访问 | 添加空指针检查、使用智能指针 |
| SIGABRT | 主动终止 | assert失败、内存分配失败 | 检查assert条件、添加错误处理 |
| SIGBUS | 总线错误 | 内存对齐问题 | 检查内存对齐、使用aligned属性 |
| SIGFPE | 浮点异常 | 除零、整数溢出 | 添加除零检查、使用安全运算 |

## 崩溃定位方法

### 1. 识别应用层崩溃帧

从堆栈中找到第一个应用层函数（排除系统库）：

```python
from centralized import SYSTEM_LIBRARIES

# 找到第一个非系统库的帧
for frame in frames:
    if not any(lib in frame['library'] for lib in SYSTEM_LIBRARIES):
        key_frame = frame
        break
```

### 2. 判断崩溃类型

**项目内崩溃**：
- 堆栈主要在目标包的代码中
- 如 `dde-dock`, `dde-session-shell` 等
- **处理方式**：提交修复到 Gerrit

**项目外崩溃**：
- 堆栈在系统库或第三方库
- 如 `libQt5Core.so.5`, `libdbus-1.so.3` 等
- **处理方式**：记录到本地日志

## 崩溃分类 (CrashClassifier)

```python
from centralized import CrashClassifier

# 根据包名自动适配
classifier = CrashClassifier.for_package("dde-dock")
classifier = CrashClassifier.for_package("dde-session-shell")

# 分类单条记录
result = classifier.classify(crash_record)
# 返回: "app_layer" | "system" | "plugin"

# 批量分类
app_crashes, sys_crashes, plugin_crashes = classifier.classify_batch(records)
```

## 崩溃→修复映射 (FixMapper)

```python
from centralized import FixMapper

# 创建 dde-dock 专用映射器
fix_mapper = FixMapper.create_for_dde_dock()

# 映射崩溃到修复
fixes = fix_mapper.map_crash_to_fixes(crash_record)
for fix in fixes:
    print(fix.commit_hash)      # "3d9fef0"
    print(fix.description)      # "修复多处空指针崩溃问题"
    print(fix.get_gerrit_url()) # "https://gerrit.uniontech.com/c/dde-dock/+/{change_number}"

# 获取所有已知修复
all_fixes = fix_mapper.get_all_fixes()
```

## Gerrit 集成 (GerritClient)

```python
from centralized import GerritClient, GerritConfig

# 创建客户端
gerrit = GerritClient()

# 查询 commit 对应的 change URL
url = gerrit.get_change_url("3d9fef0", project="dde-dock")

# 批量查询
results = gerrit.batch_get_changes(["3d9fef0", "5801d11"], project="dde-dock")
```

## 报告生成 (ReportGenerator)

```python
from centralized import ReportGenerator

report_gen = ReportGenerator("dde-dock")
report = report_gen.generate_report(
    version_analyses=analyses,
    statistics=stats,
    all_fix_mappings=fixes,
    gerrit_client=gerrit
)

# 生成崩溃-修复对应报告
crash_report = report_gen.generate_crash_fix_mapping_report(
    crashes=crashes,
    fix_mappings=fixes,
    gerrit_client=gerrit
)
```

## 输出内容

### 崩溃分析报告

```
================================================================================
[记录 1] 崩溃分析
================================================================================
  ID:       12345678-1234-1234-1234-123456789abc...
  时间:     2026-04-07T15:30:00
  包:       dde-control-center
  版本:     5.7.41.11
  信号:     SIGSEGV (段错误 - 非法内存访问)
  系统:     Deepin 1070

[3.5节方法] 崩溃定位分析
--------------------------------------------------------------------------------
✓ 已定位到应用层崩溃帧: 帧 #2
  库文件:  dde-control-center
  符号:    QWidget::show()

------------------------------------------------------------
步骤1: 安装调试符号包
------------------------------------------------------------
  sudo apt-get install dde-control-center-dbgsym
  sudo apt-get install libqt5core5a-dbgsym

------------------------------------------------------------
步骤2: 使用GDB分析coredump
------------------------------------------------------------
  gdb /usr/bin/dde-control-center -c <coredump_path>
  (gdb) bt full          # 查看完整堆栈
  (gdb) frame 2          # 切换到关键帧
  (gdb) info locals      # 查看局部变量
  (gdb) info args        # 查看参数

------------------------------------------------------------
步骤3: 使用addr2line定位源代码行号
------------------------------------------------------------
  build-id: abc123def456...
  addr2line -e /usr/lib/debug/.build-id/ab/c123def456... <地址>

------------------------------------------------------------
修复建议
------------------------------------------------------------
  针对 SIGSEGV:
    1. 添加空指针检查: if (obj) { obj->method(); }
    2. 使用智能指针避免野指针
    3. 数组访问前检查边界

堆栈跟踪 (前8帧):
--------------------------------------------------------------------------------
  ► #0 0x000055c65fa3409b QWidget::show()
       库: dde-control-center
    #1 0x00007f1234567890 QMetaObject::activate()
       库: libQt5Core.so.5
    #2 0x00007f1234567abc0 QTimer::timeout()
       库: libQt5Core.so.5
    #3 0x00007f1234560000 g_main_context_iteration()
       库: libglib-2.0.so.0
```

## GDB 常用命令

```bash
# 加载 coredump
gdb /usr/bin/<exe> -c <coredump_file>

# 查看完整堆栈
(gdb) bt
(gdb) bt full

# 切换栈帧
(gdb) frame 2
(gdb) up
(gdb) down

# 查看变量
(gdb) info locals
(gdb) info args
(gdb) print variable_name

# 查看寄存器
(gdb) info registers

# 查看内存
(gdb) x/10x address

# 查看源码
(gdb) list
(gdb) list function_name
```

## addr2line 使用

```bash
# 基本用法
addr2line -e /usr/lib/debug/.build-id/<aa>/<bbbb...> <address>

# 示例
addr2line -e /usr/lib/debug/.build-id/ab/c123def456.debug 0x000055c65fa3409b
# 输出: /path/to/source.cpp:123

# 显示函数名
addr2line -e /usr/lib/debug/.build-id/ab/c123def456.debug -f 0x000055c65fa3409b
# 输出: QWidget::show()
#       /path/to/source.cpp:123
```

## 注意事项

- 确保已安装调试符号包（dbgsym）
- 项目外崩溃需要等待上游修复
- 修复代码需要切换到正确的版本分支
- 提交时包含完整的崩溃信息和分析
- centralized/ 通用模块可被其他 coredump-* skills 复用

## 相关 Skills

| Skill | 功能 | 配合使用 |
|-------|------|---------|
| coredump-full-analysis | 完整流程自动化 | 一站式分析 |
| coredump-data-filter | 数据去重筛选 | 提供分析数据 |
| coredump-data-download | 数据下载 | 提供崩溃原始数据 |
| coredump-code-management | 源码管理 | 提供源码定位 |
| coredump-package-management | 包管理 | 提供调试符号 |
