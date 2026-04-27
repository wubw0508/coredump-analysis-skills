# 规则接入说明

`rules/` 目录用于承载崩溃分析的规则模块。

## 约定

- 通用规则放在 `common.py`
- 包级规则文件名使用包名规范化后的结果
- 规范化规则与 `package_rules.normalize_package_name()` 一致
- 例如:
  - `dde-launcher` -> `dde_launcher.py`
  - `dde-session-ui` -> `dde_session_ui.py`

## 可选接口

规则模块可以按需实现以下函数:

```python
def get_patterns() -> List[Dict]:
    ...

def get_ai_explanations() -> Dict[str, Dict[str, str]]:
    ...
```

## `get_patterns()` 返回字段

- `name`: 模式名
- `match`: 需要同时命中的小写 token 列表
- `fixable`: `True` / `False` / `"uncertain"`
- `reason`: 修复性判断原因
- `fix_type`: 建议修复方向
- `fix_code`: 可选示例代码
- `confidence`: `high` / `medium` / `low`

## `get_ai_explanations()` 返回字段

key 为 `pattern name`，value 支持:

- `analysis`: 报告中的分析描述
- `cause`: 可能原因
- `suggestion`: 修复建议
- `category`: 用于 AI 汇总中的根因分类

## 设计边界

- 包级细节只放在对应包的规则模块
- 通用脚本只负责解析、匹配、聚合和兜底
- 如果新增一个包需要修改通用脚本，通常说明规则分层还不够干净
