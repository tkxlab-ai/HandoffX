# `/handoffx-init` — 最小初始化规范（v2 多文件布局）

## 目标

让首次使用者在 3 分钟内得到一份可接手的 v2 四件套布局起点：

```
<project root>/
├── HANDOFF.md            (含 v2 marker + 11 章节骨架 + 三组空 pointer 块)
├── GOTCHAS.md            (空知识库骨架)
├── Handoff_Logs/         (空目录，等 /handoffx 写入)
└── Handoff_Decisions/    (空目录，等 /handoffx 写入决策)
```

## 行为

1. 检查项目根状态
   - 已有 `HANDOFF.md`：不覆盖
     - 若含 `<!-- HANDOFF v2 schema -->` → 提示用 `/handoffx-recall` 查看现状或 `/handoffx-tidy` 对齐结构
     - 若是 v1 layout（无 marker + inline Dev Log 条目）→ 提示走 `/handoffx-tidy` 触发迁移而非 init
   - 不存在 `HANDOFF.md`：进入下一步
2. 复制四件套骨架（**全部**写到项目根）：
   - `HANDOFF.md` ← 来自 `<skill-path>/assets/HANDOFF.template.md`
   - `GOTCHAS.md` ← 来自 `<skill-path>/assets/GOTCHAS.template.md`
   - `Handoff_Logs/` ← `mkdir -p`（空目录）
   - `Handoff_Decisions/` ← `mkdir -p`（空目录）
3. 回显最小填写清单：
   - Project Overview：一句话定位、Goals、Non-Goals、Stakeholder
   - Current State：现在做到哪、验证状态、下一步
   - Build / Run / Test：最常用命令
   - Architecture：目录结构 / 关键模块（最少一段话）
   - 其他章节可选；首条 Gotcha 等踩到再写
4. 跑 `bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>`（v2 模式接受 dir 参数）
5. 汇报创建结果和验证结果

## 规则

- 不覆盖已有 `HANDOFF.md`（v1 或 v2 都不覆盖）
- 不自动追加 Dev Log（init 只创建空骨架，不写第一条 entry）
- 不读 git 状态
- 填不出写 `—`，不要编造
- 初始化只解决"有一个可信起点"，完整结构可之后用 `/handoffx-tidy` 扩展

## 输出模板

```
✅ 已创建 v2 布局：
   HANDOFF.md          (v2 marker + 骨架)
   GOTCHAS.md          (空知识库)
   Handoff_Logs/       (空)
   Handoff_Decisions/  (空)

先填这 5 块即可：
1. Project Overview（含 Goals / Non-Goals / Stakeholder）
2. Current State
3. Build / Run / Test
4. Architecture（最少一段）
5. Coding Conventions（如果与默认不同）

写第一条 Dev Log → 跑 /handoffx
新坑 → 直接 append 到 GOTCHAS.md
显式权衡 → /handoffx 会同时写 Handoff_Decisions/<NNNN>-<date>-<slug>.md

结构校验：✅ 通过 / ⚠️ <输出>
```

## v1 升级路径（不用 init，用 tidy）

项目已有 v1 HANDOFF.md：**不要**用 init（它会拒绝覆盖）。改用 `/handoffx-tidy`——它会检测 v1 layout 并提示是否迁移到 v2 四件套。
