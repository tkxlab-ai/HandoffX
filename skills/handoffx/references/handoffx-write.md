# `/handoffx` — 写入规范（v2 多文件布局）

## 文件布局速查

把当前对话里刚刚完成的工作写入项目根。v2.0.0 起 Dev Log / Decision Log / Gotchas 是三件事，存到三个不同位置：

| 内容 | 位置 | 文件 |
|---|---|---|
| 设计与状态（Project Overview / Current State 等 11 章节） | 主文件 | `HANDOFFX.md`（顶部带 `<!-- HANDOFF v2 schema -->` 标记） |
| Dev Log 条目（事件流） | per-file | `Handoffx_Logs/<NNNN>-<timestamp>-<slug>.md` |
| Decision Log 条目（权衡记录） | per-file | `Handoffx_Decisions/<NNNN>-<date>-<slug>.md` |
| Known Gotchas（知识库） | 单文件 | `GOTCHAS.md` |

> 项目处于旧布局（旧版 `HANDOFF.md`：v1 单文件，或 v3 旧四件套）时**不要**直接走本文档，先走下面的检测与询问；升级完成后再写新条目。

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 根下存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，判定与清单原样给用户看。
2. 问：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 确认 → `--apply`，回显结果、残留清单与后续动作；未确认 → 不写任何文件。exit 1 = 迁移已完成但后置检查未过：不重试、不回滚，用 `/handoffx-tidy` 补章节再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑。
4. 新旧并存 / 无法判定 → 脚本拒绝并点名，转述给用户，不猜。
5. 用户本轮已明确要求升级 → 直接 --dry-run 再 --apply，不再重复询问（清单照样给用户看；脚本拒绝或要求 --sync-paused 时仍停下转述）。

## 采集

本流程的每个机械步骤都只调 `bash <skill-path>/scripts/hx.sh <子命令>`（在项目根执行，下文简称 `hx.sh`）。hx.sh 自带 bash shebang，AI 的工具 shell 是 zsh 也照常工作。

- `hx.sh now` — 用命令取时间戳，别自己推测。一次输出三行：`human=YYYY-MM-DD HH:MM`（正文标题）/ `fm=YYYY-MM-DDTHH:MM`（frontmatter `date:`）/ `fn=YYYY-MM-DDTHHMM`（文件名）
- 从对话上下文提取：改动的文件路径、验证方式、关联的 Decision / Gotcha
- **不读** `git branch` / `git log` / `git status`——本命令与版本管理正交

## 重复检测（写入前）

跑 `hx.sh dup-check --files <本次改动文件,逗号分隔>`。它计算的是一个**可计算谓词**，而非模糊相似度：

1. 取 `Handoffx_Logs/` 下文件名最大的条目（`[0-9]*.md` 排序取末位）；目录不存在或为空 → stdout `first-entry`，exit 0（本次为首条）
2. 读其 frontmatter `date:`（`YYYY-MM-DDTHH:MM`）转 epoch；距现在 ≥ 600 秒（10 分钟）→ stdout `ok`，exit 0
3. 两边路径集合同一规整（所以条目里的**路径须在反引号里**，否则这一步看不到它）：上一条取 `**改动**` / `**Changes**` 段（到下一个 `**字段**` 行为止）里反引号包裹的 token，本次取 `--files`；去掉 `:行号` 尾巴与结尾 `/`，只保留相对项目根**真实存在**的文件或目录（仓库名、commit SHA、分支名自然滤掉）
4. 两集合都空 → `ok`；非空且 **100% 相等** → 疑似重复，stderr 打印下面的 ⚠️ 三行，exit 3；否则 `ok`
5. 日志目录存在但读不了、`date:` 缺失或不是 `YYYY-MM-DDTHH:MM`（如 `T2144`）→ stderr `❌ 无法判定：…`，exit 2——绝不当作 `ok`

只有 exit 3 才问用户：
```
⚠️ 检测到可能重复：
  上一条: <X> 分钟前 "<旧标题>" 改动文件: {a, b, c}
  本次:   改动文件: {a, b, c}  ← 完全相同
选 (a) **替换**（覆盖该 entry 文件）/ (b) **追加**（写新文件，声明这是不同工作） / (c) 取消？
```

exit 0 直接写入新文件，不询问；exit 2（及其它非零）把 ❌ 原因转述给用户，由用户决定是否继续。

## 写入 Dev Log entry（per-file）

1. **取下一编号**：`hx.sh next-number logs`（stdout 只有四位编号；失败时 stdout 为空、非零退出，不要自己编号）。单机互斥：有 `flock`（Linux）用 flock；否则（macOS 默认无 flock）退化为 `mkdir` 锁 `Handoffx_Logs/.lock.d`，约 5 秒拿不到锁即报错——进程崩溃遗留的 `.lock.d` 不会自动清理，需手动 `rmdir`。扫描现有 `[0-9]{4}-*.md` 取 max + 1，零填充到 4 位。Cross-machine race（Syncthing）由 `/handoffx-tidy` 的 `detect_dup_numbers` 兜底
2. **生成 slug**：`hx.sh slug "<title>"`。ASCII 标题 → lowercase + dash-join，最多 40 字符；非 ASCII 标题 → `entry-<sha1[:8]>` 回退
3. **构造文件名**：`<NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md`（时间段用 `hx.sh now` 的 `fn=`）
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
- `<文件:行号>` — <变化>
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

1. 取下一 Decision 编号：`hx.sh next-number decisions`
2. slug = `hx.sh slug "<决策标题>"`
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
   - 有 `<!-- hx:recent -->` … `<!-- /hx:recent -->` 锚点 → 把新的最近改动 / 验证状态行写进临时文件，跑 `hx.sh block set recent --from <临时文件>`（只换锚点之间的内容，块外不动；exit 2 / 4 = 文件或锚点有问题、目标未改，按 ❌ 提示处理，不要退回手编整节）。`hx:done` / `hx:pending` 块由你在块内直接编辑
   - 无 `hx:recent` 锚点（老项目）→ 先跑 `bash <skill-path>/scripts/tidy-handoff.sh HANDOFFX.md` 补锚点（它总会生成 `hx:recent`），再 `hx.sh block set recent`；**永不**整节覆盖（会抹掉已有的 `hx:done` / `hx:pending` 块）
2. **三组 pointer stat 行**（每个 section 末尾的 1–3 行）：

   - `## 📜 Development Log` 段尾：`最近一条`/`最早一条`/`共 N 条`
   - `## 🐛 Known Gotchas` 段尾：`共 N 条；最新：<Gotcha #N 标题>`
   - `## 🧭 Decision Log` 段尾：`共 N 条；最新：<最新 Decision 文件名>`

   这三组 stat 与 `Handoffx_Decisions/INDEX.md` 由 `hx.sh regen` 自动重写；不要手编。

   等价手工命令（仅供调试 hx.sh 本身；lib 必须在 bash 下加载，zsh 下拒绝加载）：`bash -c '. <skill-path>/scripts/lib/handoff-v2.sh && regenerate_pointers HANDOFFX.md && regenerate_decision_index .'`

> 主文件**不再**承载 Dev Log 条目正文 / Decision 条目正文 / Gotcha 条目正文。所有内容存在 sibling 文件，主文件只负责"地图 + 指针"。

## 后置五连检查（v2.1.0 起聚合）

**推荐**一行调用聚合脚本（v2.1.0+）：

```bash
bash <skill-path>/scripts/handoff-postflight.sh --files=HANDOFFX.md,Handoffx_Logs/<刚写的NNNN文件> HANDOFFX.md
```

聚合脚本跑 5 个检查并按固定顺序回放结果（传 `--files=` 时加跑 handoff-xref-lint，即检查 5 / B①；archive-devlog 是检查 6）+ 一行 PASS/FAIL 汇总；任一失败整体 exit 1；`--quiet` 仅出汇总（CI 用），`--help` 自我文档化。

`--files=` 传本次写入集（write-target set，ADR-0004；各项相对项目根，不随当前目录变）：B① 仅扫本次改动文件，非 git diff 非全树（Decision 0019 ① 限域）；tidy/手动 postflight 省略 `--files=` 时 B① 自动 no-op。位置参数须是 `HANDOFFX.md` 文件本身（postflight 由它的 dirname 推项目根）；传目录会在任何检查之前 exit 2。

**调试需要时**可单独跑某个脚本定位问题。根据退出码判定三态：

| 退出码 | 含义 | 回显 |
|--------|------|------|
| 0 | 脚本运行，没有发现问题 | `✅ 通过` |
| ≥1 | 脚本运行，**发现问题**，阻断继续（scan-credentials/validate-handoff/handoff-lint）或警告（rotation-reminder）| `⚠️ 发现...` 或 `❌ 阻断...` |
| 127 / ENOENT | **脚本不存在** | `❌ 脚本未找到`——postflight 记该项失败（`❌ exit=127`）并整体 exit 1；不能伪装成通过，也不算跳过 |

5 个底层脚本（`<skill-path>` = 全局 skill 安装目录，详见 SKILL.md）：

1. `bash <skill-path>/scripts/scan-credentials.sh <project-root>` — 多文件凭证扫描：HANDOFFX.md + GOTCHAS.md + Handoffx_Logs/* + Handoffx_Decisions/*（含两者的 .archive/ 子目录，递归）；非 0 **硬阻断**，要求改成 `$ENV_VAR` 或 `vault://`。表格里表头标为密码 / password / token / secret 的列同样只能放 `$VAR` / `vault://` 引用或占位符（纯数字或含非 ASCII 字符的值不算明文，如 token 用量、中文说明）；SSH 私钥只写路径
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

项目根是旧版 `HANDOFF.md`（v1.x 安装、缺 v2 marker 的单文件，或 v3 旧四件套）而没有 `HANDOFFX.md`：按本文顶部「旧布局检测 → 询问 → 标准升级」处理——先 dry-run 给用户看、问、确认后 `--apply`；用户不确认就停止，不写任何文件。升级后所有历史 Dev Log / Decision / Gotchas 会被分流到对应文件，主文件留 pointer。多机 / 多 CLI 项目的固定升级顺序见 `references/migration-order.md`。
