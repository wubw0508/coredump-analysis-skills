# 全量崩溃分析完整流程

## 一、整体架构

```mermaid
graph TD
A([开始全量分析]) --> B
B[/检查 accounts.json/] --> C
B --> D
C[/创建时间戳工作目录/] --> E
D[/读取packages.txt<br/>24个包分析清单/] --> E
E[/循环: 对每个包执行/] --> F[步骤1: 下载崩溃数据]
F --> G[步骤2: 数据筛选去重]
G --> H[步骤3: 克隆源码]
H --> I[步骤4: 下载deb和dbgsym包]
I --> J[步骤5: 崩溃分析]
J --> K[下一个包]
K --> E
E -.-> L{24个项目全部完成?}
L -->|是| M[汇总所有项目报告]
M --> N[/可修复崩溃提交Gerrit/]
N --> O([全量分析完成])
```

---

## 二、单项目分析详细流程

```mermaid
graph TD
A([开始]) --> B
B[步骤1: coredump-data-download] --> C
C[/输出: 1.数据下载/] --> D
D[步骤2: coredump-data-filter] --> E
E1[/输出: 2.数据筛选-filtered CSV/] --> F
E2[/输出: 2.数据筛选-statistics JSON/] --> F
F[步骤3: coredump-code-management] --> G
G[/输出: 3.代码管理-git仓库/] --> H
H[步骤4: coredump-package-management] --> I
I1[/输出: 4.包管理-deb包/] --> J
I2[/输出: 4.包管理-dbgsym包/] --> J
J[步骤5: coredump-crash-analysis] --> K
K[/输出: 5.崩溃分析-分析报告/] --> L([完成])
```

---

## 三、步骤1~5数据流向

```mermaid
graph LR
A1[(Metabase)] -->|崩溃数据| B1[步骤1下载]
B1 -->|原始CSV| B2[步骤2筛选]
B2 -->|去重CSV| B3[步骤3源码]
B4[内部构建服务器] -->|deb包| B4a[步骤4下载包]
A2[(Gerrit)] -.->|备用| B3
B3 -->|源码| B5[步骤5分析]
B4a -->|已安装包| B5
B5 -->|分析报告| OUT
style A1 fill:#f9f,fill-opacity:0.3
style A2 fill:#bbf,fill-opacity:0.3
style B4 fill:#ffb,fill-opacity:0.3
```

---

## 四、崩溃分析内部流程

```mermaid
graph TD
A([开始分析]) --> B[读取去重后CSV]
B --> C[解析堆栈]
C --> D[识别信号类型]
D --> E{SIGSEGV?}
E -->|是| F1[空指针/野指针/越界]
D --> E2{SIGABRT?}
E2 -->|是| F2[assert失败/double-free]
D --> E3{SIGBUS?}
E3 -->|是| F3[内存对齐问题]
D --> E4{SIGFPE?}
E4 -->|是| F4[除零/整数溢出]
F1 --> G[定位应用层崩溃帧]
F2 --> G
F3 --> G
F4 --> G
G --> H{分类?}
H -->|应用层| I[生成修复建议]
H -->|系统库| J[/需上游修复/]
H -->|插件| K[/联系插件维护者/]
I --> L[使用addr2line定位行号]
L --> M{可提交?}
M -->|可提交| N[/切换分支提交Gerrit/]
M -->|不可提交| O[/跳过/]
N --> P[生成报告]
J --> P
K --> P
O --> P
P --> Q([分析完成])
```

---

## 五、全量汇总报告结构

```mermaid
graph TD
A([开始汇总]) --> B[收集24个项目报告]
B --> C[生成总体统计]
C --> D[总体统计-有崩溃-无崩溃-唯一崩溃总数]
C --> E[优先级分类]
E -->|高| E1[大于200次崩溃]
E -->|中| E2[50到200次]
E -->|低| E3[小于50次]
E -->|无| E4[无崩溃]
C --> F[信号分布-SIGSEGV-SIGABRT-SIGBUS-SIGFPE]
C --> G[可修复性分析]
G -->|可修复| G1[可修复项目列表]
G -->|需分析| G2[需进一步分析]
G -->|难度高| G3[修复难度高]
C --> H[建议修复优先级]
H -->|第一批| H1[立即修复]
H -->|第二批| H2[近期修复]
H -->|第三批| H3[规划修复]
D --> OUT[/6.总结报告-full_analysis_report.md/]
E1 --> OUT
E2 --> OUT
E3 --> OUT
E4 --> OUT
F --> OUT
G1 --> OUT
G2 --> OUT
G3 --> OUT
H1 --> OUT
H2 --> OUT
H3 --> OUT
OUT --> Z([汇总完成])
```

---

## 六、工作目录结构

```
~/coredump-workspace-YYYYMMDD-HHMMSS/
  1.数据下载/
    download_YYYYMMDD-HHMMSS/
      <package>_X86_crash_YYYYMMDD-HHMMSS.csv
  2.数据筛选/
    filtered_<package>_crash_data.csv
    <package>_crash_statistics.json
  3.代码管理/
    <package>/               (git仓库)
  4.包管理/
    downloads/
      <package>_<ver>_amd64.deb
      <package>-dbgsym_<ver>_amd64.deb
  5.崩溃分析/
    <package>_crash_analysis_report.md
  6.修复补丁/
  6.总结报告/
    full_analysis_report.md
```

---

## 七、账号检查流程

```mermaid
graph TD
A([启动分析]) --> B
B[/加载 accounts.json/] --> C{检测占位符?}
C -->|无占位符| D[继续执行分析]
C -->|有占位符| E[输出提示信息]
E --> F[/显示文件路径/]
F --> G[退出并等待人工配置]
G --> H[/重新加载 accounts.json/]
H --> C
D --> I([开始分析])
style E fill:#f96,fill-opacity:0.3
style F fill:#f96,fill-opacity:0.3
```

---

## 八、Git提交格式

```text
fix/feat/chore: 提交信息说明

崩溃信息:
- 崩溃版本: <version>
- 架构: <arch>
- 修复详细堆栈:
<full_stack_trace>

本次修复说明:
<fix_description>

Log: 基于产品说明本次修复内容
Influence: 影响哪些功能点
```
