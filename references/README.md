# references 目录说明

本目录用于存放主 `SKILL.md` 之外的补充资料，定位是“专题说明 / 设计文档 / 策略变更记录”。

使用原则：
- `SKILL.md` 负责说明“怎么用、默认怎么跑、入口在哪里”
- `references/*.md` 负责说明“为什么这样做、内部如何实现、有哪些历史坑”
- 已经稳定、需要长期复用的结论，应优先沉淀到本目录，而不是只留在外部 skill 缓存或一次性会话里

当前文件说明：

1. `enhanced-analysis.md`
- 类型：增强分析模块设计说明
- 关注点：addr2line、source context、objdump、git blame、DWARF 损坏降级策略
- 适用场景：修改 `enhanced_analysis.py`、排查增强分析结果不足

2. `automatic-deep-dive-policy.md`
- 类型：策略变更记录
- 关注点：自动二次深挖的触发条件、默认帧数、报告呈现
- 适用场景：调整 deep dive 规则、验证默认值与报告字段

3. `fixer-architecture.md`
- 类型：自动修复体系架构说明
- 关注点：cluster/spec 两条路径、fallback 提交、fixer 覆盖面
- 适用场景：扩 fixer、分析为什么没有生成真实代码修复

维护建议：
- 新增专题前，先判断是否已适合沉淀为长期文档，而不是临时排障记录
- 如果仓库文档与 `~/.hermes/skills/devops/coredump-analysis/references/` 出现分叉，应以 git 仓库版本为准，再同步到外部 skill 缓存
- 修改主流程、默认值、触发条件后，应同时检查相关 reference 是否需要更新
