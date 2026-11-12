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

## 旧布局升级路径（不用 init，用 tidy）

**布局分流**（按内容判定，不按文件名猜）：
- 项目根有旧版 `HANDOFF.md` 而无 `HANDOFFX.md` → 先跑 `/handoffx-tidy`：它按内容判定并给出命令（v1 单文件 → `migrate-to-v2.sh`；旧四件套 → `schema-upgrade`）
- 新旧文件并存 → 先解决冲突（保留权威的一套、移除另一套），再重跑
- 两者都没有 → 跑 `/handoffx-init`
