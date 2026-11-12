# `/handoffx-init` — 最小初始化规范（v2 多文件布局）

## 目标

让首次使用者在 3 分钟内得到一份可接手的 v2 四件套布局起点：

```
<project root>/
├── HANDOFFX.md            (含 v2 marker + 11 章节骨架 + 三组空 pointer 块)
├── GOTCHAS.md             (空知识库骨架)
├── Handoffx_Logs/         (空目录，等 /handoffx 写入)
└── Handoffx_Decisions/    (空目录，等 /handoffx 写入决策)
```

## 行为

1. 检查项目根状态
   - 已有 `HANDOFFX.md`：不覆盖
     - 若含 `<!-- HANDOFF v2 schema -->` → 提示用 `/handoffx-recall` 查看现状或 `/handoffx-tidy` 对齐结构
   - 不存在 `HANDOFFX.md`：若有旧版 `HANDOFF.md` 则停止，按文末「旧布局升级路径」分流；否则进入下一步
2. 复制四件套骨架（**全部**写到项目根）：
   - `HANDOFFX.md` ← 来自 `<skill-path>/assets/HANDOFFX.template.md`
   - `GOTCHAS.md` ← 来自 `<skill-path>/assets/GOTCHAS.template.md`
   - `Handoffx_Logs/` ← `mkdir -p`（空目录）
   - `Handoffx_Decisions/` ← `mkdir -p`（空目录）
3. 回显最小填写清单：
   - Project Overview：一句话定位、Goals、Non-Goals、Stakeholder
   - Current State：现在做到哪、验证状态、下一步
   - Build / Run / Test：最常用命令
   - Architecture：目录结构 / 关键模块（最少一段话）
   - 其他章节可选；首条 Gotcha 等踩到再写
4. 跑 `bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>`（v2 模式接受 dir 参数）
5. 汇报创建结果和验证结果

## 规则

- 不覆盖已有 `HANDOFFX.md`；旧版 `HANDOFF.md` 也不覆盖、不在旁边新建 `HANDOFFX.md`（走下文「旧布局升级路径」）
- 不自动追加 Dev Log（init 只创建空骨架，不写第一条 entry）
- 不读 git 状态
- 填不出写 `—`，不要编造
- 初始化只解决"有一个可信起点"，完整结构可之后用 `/handoffx-tidy` 扩展

## 输出模板

```
✅ 已创建 v2 布局：
   HANDOFFX.md          (v2 marker + 骨架)
   GOTCHAS.md          (空知识库)
   Handoffx_Logs/       (空)
   Handoffx_Decisions/  (空)

先填这 5 块即可：
1. Project Overview（含 Goals / Non-Goals / Stakeholder）
2. Current State
3. Build / Run / Test
4. Architecture（最少一段）
5. Coding Conventions（如果与默认不同）

写第一条 Dev Log → 跑 /handoffx
新坑 → 直接 append 到 GOTCHAS.md
显式权衡 → /handoffx 会同时写 Handoffx_Decisions/<NNNN>-<date>-<slug>.md

结构校验：✅ 通过 / ⚠️ <输出>
```

## 旧布局升级路径（不用 init，走检测与询问）

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 项目根存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先跑 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，把判定结果与清单原样给用户看
2. 问用户：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup 备份，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 用户确认 → 跑 `--apply`，回显结果、残留清单与后续动作；未确认 → 停止，不写任何文件；脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑
4. 新旧并存 / 无法判定 → 脚本会拒绝并点名，转述给用户，不猜
5. 用户在本轮对话里已明确要求升级 → 直接跑 --dry-run 再 --apply，不再重复询问（dry-run 结果照样原样给用户看；脚本拒绝或 --apply 要求 --sync-paused 时仍按上面停下转述）

- 两者都没有 → 跑 `/handoffx-init`
