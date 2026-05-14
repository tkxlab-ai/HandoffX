# Handoff v1 → v2.0.0 Migration Guide

## TL;DR

```bash
# 1. 升级 skill 本体到 v2.0.0
cd <plugin-checkout> && bash install.sh

# 2. 在每个项目根跑 tidy；它会检测 v1 并提示是否迁移
cd <your-project>
/handoff-tidy
```

迁移过程**原子**——任何中途失败都会自动回滚到原始 v1 状态。成功后历史 Dev Log / Decision Log / Gotchas 全量分流到 sibling 文件，主文件压到 ~28K。

---

## 1. 为什么要迁移

v1 把所有内容放在单文件 `HANDOFF.md`：

| 问题 | 实测表现 |
|---|---|
| **主文件膨胀** | 本项目实测 121K；用户其他项目超过 200K |
| **吃光 LLM 上下文** | 256K 模型窗口下，单文件占 47%，留给对话的预算锐减 |
| **AI recall 噪音** | 几百条 Dev Log 全读 → 老旧条目淹没最近活动 |
| **Token 成本高** | 每次 recall 烧 30K+ tokens |

v2 拆四件套后：

| 文件 | 估算大小 | recall 默认读 |
|---|---:|---|
| `HANDOFF.md` | ~28K | ✅ 全文 |
| `GOTCHAS.md` | ~16K | ✅ 全文（知识库 integrated reading） |
| `Handoff_Logs/` per-file | 每个 ~2-3K | ✅ 最近 5 条（约 12K） |
| `Handoff_Decisions/` per-file | 每个 ~1-2K | ❌ 按需读（用户问到才打开） |

主文件压缩 **78%**；recall 默认 ~7 文件 / 5-7K tokens（v1 全读约 30K）。

---

## 2. 迁移流程（最常用：`/handoff-tidy` 自动）

### 2.1 检测

`/handoff-tidy` 启动时调 `verify_v2_layout HANDOFF.md`：

- 含 `<!-- HANDOFF v2 schema -->` 标记 → v2，跳过迁移直接进 tidy 流程
- 不含标记 + 主文件含 inline `### YYYY-MM-DD` Dev Log 条目 → **v1**，触发迁移流程

### 2.2 提示

| 场景 | 行为 |
|---|---|
| 交互式 TTY | 显示 `migrate-to-v2.sh --dry-run` 预览 → 提示 `Apply migration now? (y/N)` |
| **`--apply` CLI flag**（v2.1.0+，CI / agent 推荐）| 直接 apply；`bash tidy-handoff.sh --apply HANDOFF.md`——位置自由（GNU 风格） |
| `HANDOFF_TIDY_AUTO_MIGRATE=1` env var | 直接 apply（v2.0.0 旧路径；v2.1.0 保留向后兼容） |
| 非交互 + 都没设 | 警告 + exit 0（不静默迁移，防误删） |

### 2.3 应用（atomic）

确认后跑 `migrate-to-v2.sh --apply --root <project-root>`：

1. 把 HANDOFF.md 复制到 `HANDOFF.md.pre-v2-backup`（rollback source-of-truth）
2. 主文件三大区段被分流：
   - `## 📜 Development Log` 下每个 `### date — title` 条目 → `Handoff_Logs.partial/<NNNN>-<timestamp>-<slug>.md`（含 frontmatter）
   - `## 🧭 Decision Log` 下每个 `### date — title` 条目 → `Handoff_Decisions.partial/<NNNN>-<date>-<slug>.md`
   - `## 🐛 Known Gotchas` 整段 → `GOTCHAS.md.partial`
3. 主文件原子重写（`HANDOFF.md.new` + `mv`）：
   - 顶部插入 `<!-- HANDOFF v2 schema -->` + `<!-- Migrated: <UTC timestamp> -->` 标记
   - 三大区段替换为 pointer block + stat 行（最近条 / 最早条 / 总数）
   - 其余 11 个章节原样保留
4. 四个 partial 路径原子 rename 到最终名（`Handoff_Logs.partial → Handoff_Logs`，等等）
5. `MIGRATE_DONE=1` flag flip → EXIT trap 不再回滚
6. 删 `HANDOFF.archive.md`（v1 归档；内容已分流到 Handoff_Logs/）

### 2.4 回滚（自动）

任何步骤 1-4 失败：

- EXIT trap 调 `cleanup_and_maybe_rollback`
- 移除所有 `*.partial` 文件 / 目录
- 若 HANDOFF.md 被改过 → 从已验证的 backup 还原
- 删除 backup 文件（项目状态 = 没运行过）

### 2.5 验证

迁移完成后建议跑：

```bash
bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>
```

期望：
- `✅ HANDOFF.md structure OK`
- 无 `pointer stat lines missing` 警告
- v2 directory mode 扫四件套全绿

---

## 3. 迁移后的项目结构

迁移前（v1）：

```
<project>/
├── HANDOFF.md                  # 121K（含全部 Dev Log / Decision / Gotchas）
└── HANDOFF.archive.md          # 旧 Dev Log 归档（>50 条时）
```

迁移后（v2）：

```
<project>/
├── HANDOFF.md                  # ~28K，顶部 v2 marker，含 11 个设计章节 + 三组 pointer stat
├── HANDOFF.md.pre-v2-backup    # 原始 v1 文件（保留作 audit trail，可手动删除）
├── GOTCHAS.md                  # 知识库（所有 Known Gotchas）
├── Handoff_Logs/               # Dev Log per-file
│   ├── 0001-2026-04-18T2030-grep-dash-prefix.md
│   ├── 0002-2026-04-18T2200-...md
│   └── ...
└── Handoff_Decisions/          # Decision per-file
    ├── 0001-2026-04-23-experimental-memory.md
    └── ...
```

---

## 4. 入门概念差异（给已经习惯 v1 的用户）

### 4.1 写入流程变了

**v1**：`/handoff` 把新 Dev Log 条目插入 HANDOFF.md 顶部（在 `<!-- 🚨 AI 注意：... -->` 锚点之上）。

**v2**：`/handoff` 写**新文件** `Handoff_Logs/<NNNN>-<timestamp>-<slug>.md`，主文件只更 Current State + 三组 pointer stat（自动重写）。

详见 `references/handoff-write.md`。

### 4.2 Recall 默认读什么变了

**v1**：HANDOFF.md 三个章节（Project Overview / Current State / Known Gotchas）+ 主文件 Dev Log 最近 N 条。单文件，~30K tokens。

**v2**：HANDOFF.md（精华 + pointer stats）+ GOTCHAS.md（整文件）+ `Handoff_Logs/` 最近 N 个 sibling 文件。约 7 文件 / 5-7K tokens。

详见 `references/handoff-recall.md`。

### 4.3 归档策略变了

**v1**：Dev Log 累积 > 50 条时，`archive-devlog.sh` 把最旧的（N - 50）条整段移到 `HANDOFF.archive.md`。

**v2**：按年归档。`Handoff_Logs/<NNNN>-<YYYY>-*.md` 当 YYYY < (当前年 - 1) 时移到 `Handoff_Logs.archive/<YYYY>/`。当年和上年保留全量。

### 4.4 命名 + race 防护

**v1**：Dev Log 时间戳 = 真人时间，无机器编号。同时间多机写入有可能冲突。

**v2**：每个文件有 `<NNNN>` sequential number（单机用 `flock` / `mkdir` spin-lock 取下一编号）。Cross-machine race（Syncthing）由 `/handoff-tidy` 的 `detect_dup_numbers` 自动 renumber 兜底。

### 4.5 Gotchas 仍是单文件

唯一**不切片**的内容是 Known Gotchas——它是知识库，多文件切分会增加遗漏风险。整合读取（`cat GOTCHAS.md`）最安全。

---

## 5. 升级时的兼容性保证

### 5.1 旧脚本接口仍能工作（向后兼容）

```bash
# v1 调用方式（单文件）
bash scan-credentials.sh HANDOFF.md
bash validate-handoff.sh --readiness HANDOFF.md
bash rotation-reminder.sh HANDOFF.md

# v2 推荐调用方式（项目目录，自动多文件）
bash scan-credentials.sh <project-root>
bash validate-handoff.sh --readiness <project-root>
bash rotation-reminder.sh <project-root>
bash archive-devlog.sh <project-root>
```

四个脚本都自动检测 arg：是文件 → 单文件模式；是目录 → v2 多文件模式。

### 5.2 install.sh 不强制升级

`install.sh` 在目标项目有 v1 HANDOFF.md 时**仅警告**，不阻断。这样允许：

- 旧项目可以继续用 v1 直到用户主动跑 `/handoff-tidy`
- 新项目 init 直接得到 v2 layout
- 升级窗口不强制——按项目节奏推进

`HANDOFF_INSTALL_SKIP_V2_GATE=1` 可静默警告（CI 用）。

### 5.3 frontmatter schema 字段 = 2

每个迁移后的 entry 文件顶部带：

```yaml
---
schema: 2
type: dev-log    # 或 decision
date: 2026-05-08T00:10
number: 0030
title: <一句话标题>
---
```

`schema: 2` 给未来 v3 留扩展点；当前所有工具读到 `schema: 2` 即用 v2 解析路径。

---

## 6. 常见问题 FAQ

### Q1：迁移失败会丢数据吗？

**不会**。`migrate-to-v2.sh` 设计为 atomic：失败时 EXIT trap 自动回滚——partial 输出被清理，HANDOFF.md 还原到验证过的备份。项目状态 = 没运行过迁移。

### Q2：`HANDOFF.md.pre-v2-backup` 要保留吗？

迁移成功后是 audit trail；用户可以核对内容后手动删除。tidy 不会自动清理（避免误删）。

### Q3：旧的 `HANDOFF.archive.md` 怎么办？

迁移过程会自动**删除**它——内容已经分流进 `Handoff_Logs/`。如果你的 archive 含特殊内容希望保留，迁移**前**先备份。

### Q4：可以从 v2 回退到 v1 吗？

v2.0.0 是 breaking change，没有官方 v2 → v1 工具。如果真的需要：

```bash
cp HANDOFF.md.pre-v2-backup HANDOFF.md
rm -rf Handoff_Logs/ Handoff_Decisions/ GOTCHAS.md
# 然后停留在 v1.2.10 (最后一个 v1 版本)
```

### Q5：跨机同步（Syncthing / Dropbox）会出问题吗？

v2 设计原生支持：
- 每个 entry 是独立文件 → 同步冲突局限到单文件级别
- 编号同号冲突 → `/handoff-tidy` 的 `detect_dup_numbers` 自动 renumber
- `Handoff_Logs/.lock` / `.lock.d` 是单机互斥锁，不进同步

### Q6：自然语言触发还能用吗？

可以。"做一次交接" / "整理一下交接文档" / "接手这个项目" 等触发词不变。Handoff_v2.0.0 skill description / SKILL.md 强化了 v2 上下文，AI 更容易识别。

---

## 7. 升级前 checklist

- [ ] 项目 `git status` 干净（提交未保存改动，避免迁移触发误判）
- [ ] 备份 `HANDOFF.md`（脚本会自动创建 `.pre-v2-backup`，手动副本是双保险）
- [ ] 升级 skill：`bash <plugin>/install.sh`
- [ ] 项目根：`/handoff-tidy` 触发自动迁移
- [ ] 迁移完成后跑 `validate-handoff.sh --readiness <project-root>` 确认结构 OK
- [ ] 跑一次 `/handoff-recall` 验证 AI 能正确读 v2 layout
- [ ] 第一次新 entry 用 `/handoff` 验证写入流程（应在 `Handoff_Logs/` 下生成新 `<NNNN>-*.md` 文件）

---

## 8. 引用资料

- 设计 spec：[../Handoff_planning_0506/specs/2026-05-07-handoff-v2-design.md](../Handoff_planning_0506/specs/2026-05-07-handoff-v2-design.md)（项目内部规划文档；外部用户可忽略）
- 实施 plan：[../Handoff_planning_0506/plans/2026-05-07-handoff-v2.md](../Handoff_planning_0506/plans/2026-05-07-handoff-v2.md)
- 命令规范：`skills/handoff/references/handoff-{write,recall,tidy,init}.md`
- v2 lib：`scripts/lib/handoff-v2.sh`（slugify / acquire_next_number / verify_v2_layout / regenerate_pointers）
- 迁移工具：`scripts/migrate-to-v2.sh`

---

## License

This project is licensed under the MIT License.

Copyright (c) 2026 TKXLAB.AI - https://github.com/tkxlab-ai
