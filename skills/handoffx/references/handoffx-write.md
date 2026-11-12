# `/handoffx` — 写入规范（v2 多文件布局）

## 文件布局速查

把当前对话里刚刚完成的工作写入项目根。v2.0.0 起 Dev Log / Decision Log / Gotchas 是三件事，存到三个不同位置：

| 内容 | 位置 | 文件 |
|---|---|---|
| 设计与状态（Project Overview / Current State 等 11 章节） | 主文件 | `HANDOFFX.md`（顶部带 `<!-- HANDOFF v2 schema -->` 标记） |
| Dev Log 条目（事件流） | per-file | `Handoffx_Logs/<NNNN>-<timestamp>-<slug>.md` |
| Decision Log 条目（权衡记录） | per-file | `Handoffx_Decisions/<NNNN>-<date>-<slug>.md` |
| Known Gotchas（知识库） | 单文件 | `GOTCHAS.md` |

> 项目处于旧布局（旧版 `HANDOFF.md`：v1 单文件，或 v3 旧四件套）时**不要**直接走本文档。先跑 `/handoffx-tidy`，它按内容判定并给出升级命令；升级完成后再用 `/handoffx` 写新条目。

## 采集

- `date "+%Y-%m-%d %H:%M"` — 用命令取时间戳，别自己推测
- 从对话上下文提取：改动的文件路径、验证方式、关联的 Decision / Gotcha
- **不读** `git branch` / `git log` / `git status`——本命令与版本管理正交

## 重复检测（写入前）

用**可计算谓词**判断，而非模糊相似度：

1. 取 `Handoffx_Logs/` 目录下文件名最大的（`ls -1 Handoffx_Logs/[0-9]*.md | sort | tail -1`），读其 frontmatter 的 `date:` 字段
2. 用 `date +%s` 取当前 epoch；与该 date 的 epoch 差 `< 600` 秒（10 分钟）
3. 提取上一条 entry `**改动**:` 段落中的文件路径集合（每行 `-` 后第一个 `path` 或 `path:line` 串）
4. 提取本次要写的文件路径集合
5. **两集合 100% 相等** 且 **时间差 < 10 分钟** → 判定为疑似重复

若判定为疑似重复，向用户确认：
```
⚠️ 检测到可能重复：
  上一条: <X 分钟前> "<旧标题>" 改动文件: {a, b, c}
  本次:   改动文件: {a, b, c}  ← 完全相同
选 (a) **替换**（覆盖该 entry 文件）/ (b) **追加**（写新文件，声明这是不同工作） / (c) 取消？
```

若任一条件不满足（时间差 ≥ 10 分钟，或文件集合有差异），直接写入新文件，不询问。

`Handoffx_Logs/` 不存在或为空 → 跳过重复检测，本次为首条。

## 写入 Dev Log entry（per-file）

1. **取下一编号**：调用 `acquire_next_number Handoffx_Logs/`（来自 `<skill-path>/scripts/lib/handoff-v2.sh`）。函数单机互斥：有 `flock`（Linux）用 flock；否则（macOS 默认无 flock）退化为 `mkdir` 锁 `Handoffx_Logs/.lock.d`，约 5 秒拿不到锁即报错返回 1——进程崩溃遗留的 `.lock.d` 不会自动清理，需手动 `rmdir`。扫描现有 `[0-9]{4}-*.md` 取 max + 1，零填充到 4 位。Cross-machine race（Syncthing）由 `/handoffx-tidy` 的 `detect_dup_numbers` 兜底
2. **生成 slug**：`slugify "<title>"`（同 lib）。ASCII 标题 → lowercase + dash-join，最多 40 字符；非 ASCII 标题 → `entry-<sha1[:8]>` 回退
3. **构造文件名**：`<NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md`
4. **写文件**：

```markdown
---
schema: 2
type: dev-log
date: 2026-05-08T00:10
number: 0031
title: <一句话标题>
---

### 2026-05-08 00:10 — <一句话标题>

**触发**: <为什么做这件事>

**改动**:
- <文件:行号 — 变化>
- <若走过弯路 / 失败尝试 / 被放弃的方案，写一行 `走过的弯路: <一句话 + 为什么不行>`——这类默会知识最值钱也最易丢>

**验证**:
- <build / test / 手动验证结果（带可复现的证据：命令、CI URL、截图路径）>

**关联**: <Gotcha #N / Decision <NNNN>-<date>-<slug> | 无>
```

填不出写 `—`，不要编造。

**字段名接受英文别名**（v2.1.0+）：`**触发**`≡`**Trigger**` / `**改动**`≡`**Changes**` / `**验证**`≡`**Verification**` / `**关联**`≡`**Related**`。同一条目内可混用；handoff-lint 和 handoffx-tidy 都识别两种。新条目维持原条目语言风格（避免一个文件中英文混杂）。

frontmatter 之下的 `### date — title` 行 + 必填字段格式与 v1 完全一致——这是为了 grep / human-read 的兼容性。

## Decision Log 分流（per-file）

若本次对话含**显式权衡**（"考虑了 A 和 B，选了 A 因为..."），**额外**写一个 Decision 文件：

1. 取下一 Decision 编号：`acquire_next_number Handoffx_Decisions/`
2. slug = `slugify "<决策标题>"`
3. 文件名：`Handoffx_Decisions/<NNNN>-<YYYY-MM-DD>-<slug>.md`（决策按天，不带时间）
4. 内容：

```markdown
---
schema: 2
type: decision
date: 2026-05-08
number: 0012
title: <决策标题>
---

### 2026-05-08 — <决策标题>
- **背景**: <约束>
- **选项**: A / B / C
- **选择**: A
- **拒绝 B/C 的原因**: <...>
- **反悔代价**: <低 | 中 | 高>
```

并在 Dev Log entry 的 `关联` 字段填 `Decision <NNNN>-<date>-<slug>`（用文件 stem 引用，便于 grep）。

## Known Gotchas（追加到 GOTCHAS.md）

新坑写到 `GOTCHAS.md` **底部**，编号继承（`Gotcha #N` 全项目单调递增）：

```markdown
### Gotcha #N — `[build|runtime|data|security|perf]` <一句话症状>
- **症状**: <...>
- **根因**: <...>
- **方案**: <...>
- **教训**: <...>
- **关联**: <Dev Log 文件 stem | Decision 文件 stem>
```

> Gotchas 累积保留，不清理。

## 同步主 HANDOFFX.md（最少改动）

主文件**只**改两处：

1. **Current State 章节**：用对话上下文 **覆盖**（不是追加）。保留"最近改动区域 / 验证状态 / 待办列表"三部分；旧 pending 做完就划掉，新的加上，别堆积
2. **三组 pointer stat 行**（每个 section 末尾的 1–3 行）：

   - `## 📜 Development Log` 段尾：`最近一条`/`最早一条`/`共 N 条`
   - `## 🐛 Known Gotchas` 段尾：`共 N 条；最新：<Gotcha #N 标题>`
   - `## 🧭 Decision Log` 段尾：`共 N 条；最新：<最新 Decision 文件名>`

   这三组 stat 由 `regenerate_pointers` + `regenerate_decision_index` helper 自动重写（见 `lib/handoff-v2.sh`）；不要手编。

> 主文件**不再**承载 Dev Log 条目正文 / Decision 条目正文 / Gotcha 条目正文。所有内容存在 sibling 文件，主文件只负责"地图 + 指针"。

## 后置五连检查（v2.1.0 起聚合）

**推荐**一行调用聚合脚本（v2.1.0+）：

```bash
bash <skill-path>/scripts/handoff-postflight.sh --files=HANDOFFX.md,Handoffx_Logs/<刚写的NNNN文件> HANDOFFX.md
```

聚合脚本跑 5 个检查并按固定顺序回放结果（传 `--files=` 时加跑第 6 个 handoff-xref-lint，即 B①）+ 一行 PASS/FAIL 汇总；任一失败整体 exit 1；`--quiet` 仅出汇总（CI 用），`--help` 自我文档化。

`--files=` 传本次写入集（write-target set，ADR-0004）：B① 仅扫本次改动文件，非 git diff 非全树（Decision 0019 ① 限域）；tidy/手动 postflight 省略 `--files=` 时 B① 自动 no-op。

**调试需要时**可单独跑某个脚本定位问题。根据退出码判定三态：

| 退出码 | 含义 | 回显 |
|--------|------|------|
| 0 | 脚本运行，没有发现问题 | `✅ 通过` |
| ≥1 | 脚本运行，**发现问题**，阻断继续（scan-credentials/validate-handoff/handoff-lint）或警告（rotation-reminder）| `⚠️ 发现...` 或 `❌ 阻断...` |
| 127 / ENOENT | **脚本不存在** | `❌ 脚本未找到`——postflight 记该项失败（`❌ exit=127`）并整体 exit 1；不能伪装成通过，也不算跳过 |

5 个底层脚本（`<skill-path>` = 全局 skill 安装目录，详见 SKILL.md）：

1. `bash <skill-path>/scripts/scan-credentials.sh <project-root>` — 多文件凭证扫描：HANDOFFX.md + GOTCHAS.md + Handoffx_Logs/* + Handoffx_Decisions/*（含两者的 .archive/ 子目录，递归）；非 0 **硬阻断**，要求改成 `$ENV_VAR` 或 `vault://`
2. `bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>` — v2 schema 校验：检查 v2 marker、三组 pointer stat 行存在、Handoffx_Logs/ 文件 frontmatter 合法、必填字段
3. `bash <skill-path>/scripts/handoff-lint.sh HANDOFFX.md` — v2 per-file frontmatter + body field（触发/改动/验证/关联，支持英文同义词）严格校验
4. `bash <skill-path>/scripts/rotation-reminder.sh <project-root>` — 凭证轮换：只读主文件（传目录时解析为 `<project-root>/HANDOFFX.md`，不扫 sibling 文件）；发现到期时 exit 1
5. `bash <skill-path>/scripts/archive-devlog.sh <project-root>` — v2 改为按年归档：`Handoffx_Logs/<NNNN>-<2025-*>` 移到 `Handoffx_Logs.archive/2025/`，主目录只保留当年与上一年。未超阈值 exit 0 幂等

## 🧪 Experimental：记忆同步（opt-in）

如果存在 `./memory/.sync-enabled` 标志文件，**在后置五连检查之后、回显之前**额外跑：

```bash
bash <skill-path>/scripts/sync-memory.sh sync
```

详见 `handoffx-memory.md`。

## 回显（Norman: 缩短 Gulf of Evaluation）

写入后，把**新追加的 Dev Log entry 文件路径** + **片段** 回显给用户，不要只说"已更新"。格式：

```
✅ Dev Log 追加 → Handoffx_Logs/0031-2026-05-08T0010-handoff-v2-rollback.md
<粘贴刚写入的 5-10 行（不含 frontmatter）>

（如有）✅ Decision Log 追加 → Handoffx_Decisions/0012-2026-05-08-some-decision.md
<粘贴>

主文件更新：Current State + 三组 pointer stat 已重写

后置检查（三态：通过 / 发现问题 / 失败；脚本缺失记失败，不记跳过）：
🔐 凭证扫描：✅ 通过 | ❌ 阻断（发现 X）| ❌ 无法扫描（exit 2：输入不可读 / 用法错误）| ❌ 脚本未找到（exit 127）
📐 结构校验：✅ 通过 | ⚠️ 缺 RECOMMENDED | ❌ 缺 REQUIRED / 缺 v2 marker | ❌ 脚本未找到（exit 127）
🔄 轮换提醒：✅ 无到期 | ⚠️ <rotation 输出> | ❌ 脚本未找到（exit 127）
📦 归档：➖ 未触发 | ✅ 已归档 M 条到 Handoffx_Logs.archive/<year>/ | ❌ 失败（exit 2–6：不可读 / 写入失败 / 指针刷新失败）| ❌ 脚本未找到（exit 127）
🧪 记忆同步：➖ 未启用 | 📦 已同步 N 条 → ./memory/ | ❌ 发现凭证（exit 1）| ❌ 无法验证（exit 2：扫描器缺失或文件读不到）| ➖ 跳过（experimental，详见 /handoffx-memory）
```

## 别名

`handoffx` / `/交接` 一律按 `/handoffx` 执行，不质疑拼法。

## 首次使用（HANDOFFX.md 不存在）

走 `/handoffx-init` 流程——它会生成 v2 marker、Handoffx_Logs/、Handoffx_Decisions/、空 GOTCHAS.md，然后再跑一次 `/handoffx` 写首条 Dev Log。详见 `handoffx-init.md`。

## 旧布局项目升级路径

项目根是旧版 `HANDOFF.md`（v1.x 安装、缺 v2 marker 的单文件，或 v3 旧四件套）而没有 `HANDOFFX.md`：先跑 `/handoffx-tidy`——旧版 `HANDOFF.md`（v1 单文件或 v3 旧四件套）会让脚本 exit 2 并打印确切的升级命令；agent 原样转述给用户后停止，不自行迁移。升级后所有历史 Dev Log / Decision / Gotchas 会被分流到对应文件，主文件留 pointer。
