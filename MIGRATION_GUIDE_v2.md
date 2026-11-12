# HandoffX v1 → v2.0.0 Migration Guide

## TL;DR

```bash
# 1. 升级 skill 本体到 v2.0.0
cd <plugin-checkout> && bash install.sh

# 2. 在每个项目根跑 tidy；它会检测 v1 并提示是否迁移
cd <your-project>
/handoffx-tidy
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

## 2. 迁移流程（最常用：`/handoffx-tidy` 自动）

### 2.1 检测

`/handoffx-tidy` 启动时调 `verify_v2_layout HANDOFF.md`：

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

迁移后（v2 结构，下列为当前迁移器的实际产出名——v4.0.0 起产出新名，见 §5；本文 §1–§4 其余部分按 v1 → v2 历史原貌保留旧名）：

```
<project>/
├── HANDOFFX.md                 # ~28K，顶部 v2 marker，含 11 个设计章节 + 三组 pointer stat
├── HANDOFF.md.pre-v2-backup    # 原始 v1 文件（保留作 audit trail，可手动删除）
├── GOTCHAS.md                  # 知识库（所有 Known Gotchas）
├── Handoffx_Logs/              # Dev Log per-file
│   ├── 0001-2026-04-18T2030-grep-dash-prefix.md
│   ├── 0002-2026-04-18T2200-...md
│   └── ...
└── Handoffx_Decisions/         # Decision per-file
    ├── 0001-2026-04-23-experimental-memory.md
    └── ...
```

---

## 4. 入门概念差异（给已经习惯 v1 的用户）

### 4.1 写入流程变了

**v1**：`/handoffx` 把新 Dev Log 条目插入 HANDOFF.md 顶部（在 `<!-- 🚨 AI 注意：... -->` 锚点之上）。

**v2**：`/handoffx` 写**新文件** `Handoff_Logs/<NNNN>-<timestamp>-<slug>.md`，主文件只更 Current State + 三组 pointer stat（自动重写）。

详见 `references/handoffx-write.md`。

### 4.2 Recall 默认读什么变了

**v1**：HANDOFF.md 三个章节（Project Overview / Current State / Known Gotchas）+ 主文件 Dev Log 最近 N 条。单文件，~30K tokens。

**v2**：HANDOFF.md（精华 + pointer stats）+ GOTCHAS.md（整文件）+ `Handoff_Logs/` 最近 N 个 sibling 文件。约 7 文件 / 5-7K tokens。

详见 `references/handoffx-recall.md`。

### 4.3 归档策略变了

**v1**：Dev Log 累积 > 50 条时，`archive-devlog.sh` 把最旧的（N - 50）条整段移到 `HANDOFF.archive.md`。

**v2**：按年归档。`Handoff_Logs/<NNNN>-<YYYY>-*.md` 当 YYYY < (当前年 - 1) 时移到 `Handoff_Logs.archive/<YYYY>/`。当年和上年保留全量。

### 4.4 命名 + race 防护

**v1**：Dev Log 时间戳 = 真人时间，无机器编号。同时间多机写入有可能冲突。

**v2**：每个文件有 `<NNNN>` sequential number（单机用 `flock` / `mkdir` spin-lock 取下一编号：有 `flock`（Linux）用 flock，macOS 默认无 flock 走 `mkdir` 锁 `.lock.d`，约 5 秒拿不到锁即报错返回 1（flock 分支无超时）；崩溃遗留的 `.lock.d` 不会自动清理，需手动 `rmdir`）。Cross-machine race（Syncthing）由 `/handoffx-tidy` 的 `detect_dup_numbers` 自动 renumber 兜底。

### 4.5 Gotchas 仍是单文件

唯一**不切片**的内容是 Known Gotchas——它是知识库，多文件切分会增加遗漏风险。整合读取（`cat GOTCHAS.md`）最安全。

---

## 5. v3 → v4：四件套改名（HandoffX v4.0.0）

### 5.1 改了什么

产出文件的三个名字变了，`GOTCHAS.md` 不变：

| 旧名（v2 / v3） | 新名（v4.0.0） |
|---|---|
| `HANDOFF.md` | `HANDOFFX.md` |
| `Handoff_Logs/` | `Handoffx_Logs/` |
| `Handoff_Decisions/` | `Handoffx_Decisions/` |

模板资产同步为 `assets/HANDOFFX.template.md`。命令名（`/handoffx`、`/handoffx-recall` …）和脚本基名（`handoff-lint.sh`、`migrate-to-v2.sh` …）都不改。v2 schema 标记 `<!-- HANDOFF v2 schema -->` 是内容不是文件名，也不改。

### 5.2 为什么

工具名早已是 `handoffx`，产出文件还叫 `HANDOFF`，两边对不上；v4.0.0 让文件名跟着工具名走。这是破坏性发布（major bump）：旧名不再被识别为当前布局。

### 5.3 怎么升级

升级由你显式触发，工具不会替你改名。在项目根先跑 `/handoffx-tidy`——它按内容判定布局并给出该跑的命令。旧四件套（v2 / v3 布局）：

```bash
/handoffx-tidy schema-upgrade --dry-run      # 只报告将做什么，不动文件
/handoffx-tidy schema-upgrade --apply        # 原子应用
```

等价的脚本形式：`bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --dry-run|--apply [--root DIR]`；`--root DIR` 指定项目根（默认当前目录）。应用过程原子——先写 `.partial` 暂存，任何提交点前的失败都会回滚，源文件原样保留。若项目里同时存在旧名与新名的部分文件（混合树），升级会拒绝并点名两边各有哪些，需你先决定保留哪一套、移除另一套，再重跑。

### 5.4 不迁移会怎样

v4 不会静默在旧布局上工作：

- `tidy-handoff.sh`、`validate-handoff.sh`、`handoff-postflight.sh` 遇到旧布局 exit 2，并在错误信息里点名该跑的命令；
- `install.sh` 只警告并继续（skill 本体照常安装）；
- `install.sh --template` 拒绝旧布局的目标目录。

Why 这样设计：在旧布局旁边悄悄新建新名文件，会让一个项目同时有两套交接文档。

### 5.5 v1 用户：直接到 v4

仍是 v1 单文件 `HANDOFF.md` 的项目不必先迁 v2 再改名：`migrate-to-v2.sh --dry-run` / `--apply`（可加 `--root <project-dir>`）一步产出 v4 的新名四件套。成功后保留 `HANDOFF.md.pre-v2-backup`；若 v1 旁边有溢出归档，也保留 `HANDOFF.archive.md.pre-v2-backup`。失败会整体回滚；脚本打印的 Restore 行可重建出与原 v1 完全一致的目录树。

### 5.6 固定升级顺序（多机 / 多 CLI 项目照此执行）

> 本节同时随 skill 发布为 `skills/handoffx/references/migration-order.md`（两处逐字一致，测试守护），`handoffx-upgrade.sh` 的清单指向那一份。

1. 停掉项目目录的同步（Syncthing / Dropbox / iCloud）——否则一边改名一边同步回来就是混合树，v4 拒绝处理。`handoffx-upgrade.sh` 从项目根往上找同步标记（`.stfolder`、`.dropbox` / `.dropbox.cache`、路径含 `/Library/Mobile Documents/`），找到就点名；`--apply` 时拒绝（exit 2、不写任何文件），暂停同步后加 `--sync-paused` 重跑。项目根经符号链接进入时，逻辑路径与真实路径的上级都会查。只认这几种标记——检测不到不等于没在同步，照样先暂停。建议把 `Handoffx_Logs/.lock.d` 与 `Handoffx_Logs/.lock` 加进 `.stignore`（单机取号锁：macOS 等无 `flock` 处用前者，Linux 写入用后者，升级在旧目录上两把都拿；不该同步到别的机器）。锁的保证范围：升级期间持有旧目录上的取号锁：阻止 v3 写入者**取号**，不保证整次写入互斥（取号锁在返回编号时即释放）；mkdir 分支下 `.lock.d` 会随目录复制进新目录、直到升级退出才删除，所以新目录在后置检查阶段对 mkdir 取号也是关的，对 flock 取号不关；迁移前必须先停止正在运行的 handoff 写入会话（§5.6 第 1–2 步）。
2. 所有机器、所有 CLI（Claude Code / Codex / OpenCode）先重装 v4 的 skill——留一个 v3 skill 它会继续往旧目录写。装完在每台机器跑一次 `bash <skill-path>/scripts/handoffx-upgrade.sh --scan-home`：只读检查本机 `~/.claude`（CLAUDE.md、rules、commands、skills）、`~/.codex`（AGENTS.md、prompts/、skills/）、`~/.agents/skills`、`~/.config/opencode` 里仍引用旧名的规则 / 命令和仍会被加载的旧名 skill（含链接进来的目录），按根列出（扫描深度 ≤ 6，skill 目录 ≤ 3；本 skill 自身与 install.sh 装的 shim 跳过）；`⚠️ 扫描不完整`（exit 2）表示有根读不了或有悬空 / 循环链接，结果不能当作干净。
3. `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>` 看清单（判定布局、将改什么、残留扫描）——先看再动，dry-run 不写任何文件。
4. `--apply`：原子迁移，失败自动回滚；旧四件套（v3）原地改名不留副本——git 工作树靠 git 回退，非 git 项目（如只靠 Syncthing 同步）脚本会先把四件套打包成项目根下的 `.handoffx-pre-upgrade-<时间>.tar.gz` 并逐项校验，备份建不成或校验不过就 exit 2、不迁移任何文件（`--no-backup` 显式跳过）；完成后自动跑 validate / postflight，并列出项目里其它文件仍引用旧名的位置——迁移器只管四件套本身，项目其它文件里的旧路径要靠这份清单找出来。清单按文件聚合（每文件一行：处数 + 首处，最多 50 个文件），完整清单写到项目根 `.handoffx-upgrade-residuals.txt`；备份件、同步冲突件、会话日志等噪音目录默认跳过，`HANDOFFX_SCAN_PRUNE="dirA dirB"` 可追加；大树可加 `--quick` 跳过残留扫描（之后用 `--scan-only` 补看——那时已是新布局，dry-run 只会说无需升级；`--scan-only` 任何布局都可跑，只读）。脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续——迁移本身已成功，回滚只会把要修的问题藏起来。exit 3 = 迁移器拒绝（如目标件已存在），未迁移任何文件：按输出处理后重跑。
5. 处理残留清单（README / CI / 脚本 / 配置里的旧路径），先删 `.handoffx-upgrade-residuals.txt`（残留清单，不该进提交），再 `git add -A && git commit`（git 会识别为 rename，历史不断）——改名与引用修正放进同一个提交，任何一个提交点上项目都自洽。
6. 若有发布链 / 公开镜像：检查其排除表或审计规则里写死的旧名——这些规则不在项目文档里，残留扫描能看到文件却看不懂规则意图，需要人判断。
7. 恢复同步——此时各机都是 v4 skill、项目是新布局，同步回来的只会是新名。

`/handoffx`、`/handoffx-recall`、`/handoffx-tidy`、`/handoffx-init` 发现旧布局时会先给出 dry-run 清单并询问，确认后执行第 3–4 步；第 1–2、5–7 步仍要人做。`handoffx-upgrade.sh` 本身不交互、不提交：唯一的 git 调用是只读的 `git rev-parse --is-inside-work-tree`（决定要不要打升级前备份）；按 `hx_legacy_layout_kind` 判定 v1 → `migrate-to-v2.sh`、旧四件套 → `tidy-handoff.sh schema-upgrade`，新旧并存或无法判定则拒绝（exit 2）且不写文件；已是新布局时 `--apply` 直接 exit 0。

---

## 6. 升级时的兼容性保证

### 6.1 旧脚本接口仍能工作（向后兼容）

```bash
# 单文件调用方式（传主文件 HANDOFFX.md）
bash scan-credentials.sh HANDOFFX.md
bash validate-handoff.sh --readiness HANDOFFX.md
bash rotation-reminder.sh HANDOFFX.md

# 推荐调用方式（项目目录；各脚本实际读取范围见下）
bash scan-credentials.sh <project-root>
bash validate-handoff.sh --readiness <project-root>
bash rotation-reminder.sh <project-root>
bash archive-devlog.sh <project-root>
```

四个脚本都接受文件或目录参数，但只有 `scan-credentials.sh` 真正区分模式：文件 → 只扫该文件；目录 → 扫 HANDOFFX.md + GOTCHAS.md + Handoffx_Logs/*.md + Handoffx_Decisions/*.md（含 Handoffx_Logs.archive/、Handoffx_Decisions.archive/ 递归）。`validate-handoff.sh` / `rotation-reminder.sh` 传目录时只解析为 `<dir>/HANDOFFX.md`（`validate-handoff.sh --readiness` 另经 handoff-lint 校验 sibling 文件；`rotation-reminder.sh` 只读主文件）。`archive-devlog.sh` 对目录（其 HANDOFFX.md 含 v2 marker）或带 v2 marker 的主文件走按年归档；主文件无 marker 时仍走 v1 的 >50 条计数归档。

### 6.2 install.sh 不强制升级

`install.sh` 在目标项目有旧布局（旧版 `HANDOFF.md`）时**仅警告**，不阻断。这样允许：

- 旧项目的文件原样保留，直到用户主动跑 `/handoffx-tidy`（它按内容判定并给出升级命令；v4 的 tidy / validate / postflight 在旧布局上 exit 2，不会静默工作）
- 新项目 init 直接得到 v2 layout
- 升级窗口不强制——按项目节奏推进

`HANDOFF_INSTALL_SKIP_V2_GATE=1` 可静默警告（CI 用）。

### 6.3 frontmatter schema 字段 = 2

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

## 7. 常见问题 FAQ

### Q1：迁移失败会丢数据吗？

**不会**。`migrate-to-v2.sh` 设计为 atomic：失败时 EXIT trap 自动回滚——partial 输出被清理，HANDOFF.md 还原到验证过的备份。项目状态 = 没运行过迁移。

### Q2：`HANDOFF.md.pre-v2-backup` 要保留吗？

迁移成功后是 audit trail；用户可以核对内容后手动删除。tidy 不会自动清理（避免误删）。

### Q3：旧的 `HANDOFF.archive.md` 怎么办？

迁移成功后它被移走，内容已分流进 `Handoffx_Logs/`；v4 起迁移器会先把它备份为 `HANDOFF.archive.md.pre-v2-backup` 并在成功后保留，不再需要手动先备份。

### Q4：可以从 v2 回退到 v1 吗？

v2.0.0 是 breaking change，没有官方 v2 → v1 工具。如果真的需要：

```bash
cp HANDOFF.md.pre-v2-backup HANDOFF.md
rm -rf HANDOFFX.md Handoffx_Logs/ Handoffx_Decisions/ GOTCHAS.md
# 然后停留在 v1.2.10 (最后一个 v1 版本)
```

### Q5：跨机同步（Syncthing / Dropbox）会出问题吗？

v2 设计原生支持：
- 每个 entry 是独立文件 → 同步冲突局限到单文件级别
- 编号同号冲突 → `/handoffx-tidy` 的 `detect_dup_numbers` 自动 renumber
- `Handoffx_Logs/.lock` / `.lock.d` 是单机互斥锁，不进同步

### Q6：自然语言触发还能用吗？

可以。"做一次交接" / "整理一下交接文档" / "接手这个项目" 等触发词不变。Handoff_v2.0.0 skill description / SKILL.md 强化了 v2 上下文，AI 更容易识别。

---

## 8. 升级前 checklist

- [ ] 项目 `git status` 干净（提交未保存改动，避免迁移触发误判）
- [ ] 备份 `HANDOFF.md`（脚本会自动创建 `.pre-v2-backup`，手动副本是双保险）
- [ ] 升级 skill：`bash <plugin>/install.sh`
- [ ] 项目根：`/handoffx-tidy`——它按内容判定旧布局，exit 2 并点名该跑的命令（v1 → `migrate-to-v2.sh`，旧四件套 → `schema-upgrade`），再按命令执行
- [ ] 迁移完成后跑 `validate-handoff.sh --readiness <project-root>` 确认结构 OK
- [ ] 跑一次 `/handoffx-recall` 验证 AI 能正确读 v2 layout
- [ ] 第一次新 entry 用 `/handoffx` 验证写入流程（应在 `Handoffx_Logs/` 下生成新 `<NNNN>-*.md` 文件）

---

## 9. 引用资料

- 设计 spec：[../Handoff_planning_0506/specs/2026-05-07-handoff-v2-design.md](../Handoff_planning_0506/specs/2026-05-07-handoff-v2-design.md)（项目内部规划文档；外部用户可忽略）
- 实施 plan：[../Handoff_planning_0506/plans/2026-05-07-handoff-v2.md](../Handoff_planning_0506/plans/2026-05-07-handoff-v2.md)
- 命令规范：`skills/handoffx/references/handoffx-{write,recall,tidy,init}.md`
- v2 lib：`scripts/lib/handoff-v2.sh`（slugify / acquire_next_number / verify_v2_layout / regenerate_pointers）
- 迁移工具：`scripts/migrate-to-v2.sh`

---

## License

This project is licensed under the MIT License.

Copyright (c) 2026 TKXLAB.AI - https://github.com/tkxlab-ai
