# Known Gotchas

> All gotchas accumulated during the project lifetime. Each entry: 症状 / 根因 / 方案 / 教训 / 关联.
> Read by /handoff-recall by default. Add new entries to the bottom; keep `### Gotcha #N` header pattern.


### Gotcha #1 — `[build]` grep pattern 以 `-` 开头会被当成选项
- **症状**：`-----BEGIN PRIVATE KEY-----` 永远匹配不到
- **根因**：grep 解析到 `-----` 当 option flags
- **方案**：所有 pattern-based grep 用 `grep -E -- "$pattern"`（`--` 显式结束选项）
- **教训**：用户输入或变量做 grep pattern 时，默认加 `--`
- **关联 Dev Log**：2026-04-18 v0.4 Round 1

### Gotcha #2 — `[build]` 数组字段分隔符与正则 metachar 冲突
- **症状**：`sk-ant-(api|admin)` 里的 `|` 被字段切分 primary，pattern 变 `sk-ant-(api`，报 "parentheses not balanced"
- **根因**：用 `|` 作字段分隔符 + 正则也含 `|` = 二义性
- **方案**：用两个并行数组（PATTERNS + LABELS），索引同步
- **教训**：分隔符必须是 regex 语法中的非 meta 字符，或用多数组
- **关联 Dev Log**：2026-04-18 v0.4 Round 1

### Gotcha #3 — `[runtime]` bash 3.2（macOS 默认）+ `set -u` + 空数组 = unbound variable
- **症状**：`set -u` 下 `"${empty_array[@]}"` 抛 "unbound variable"
- **根因**：bash 3.2 对空数组的展开 bug
- **方案**：去掉 `set -u`，或用 `"${arr[@]:-}"`（但会插入空串）
- **教训**：macOS 默认 bash 3.2；想要严格模式就要测试空数组路径
- **关联 Dev Log**：2026-04-18 v0.4 Round 3

### Gotcha #4 — `[runtime]` macOS `date -v+-30d` 语法错
- **症状**：测试辅助函数 `date_add -30` 打出 `date: illegal option -- d`
- **根因**：`date -v+${n}d` 中 n=-30 → `date -v+-30d` 不是合法语法
- **方案**：检测 n 正负，正用 `-v+${n}d`，负用 `-v${n}d`（n 带自己的 `-`）
- **教训**：shell 变量插值前先规范化符号

### Gotcha #6 — `[runtime]` bash `set -e` + `cmd; ec=$?` 序列会提前中断

- **症状**：`sync-memory.sh` 的 `on` 子命令里 `do_sync` 返回 1（凭证扫描命中）时，后面的 `maybe_suggest_gitignore` 永远执行不到——`.gitignore` 提示神秘消失
- **根因**：`set -e` 对 `cmd; captured=$?` 的"捕获退出码"模式**先行生效**——cmd 非 0 立刻 abort 整个脚本，根本到不了 `captured=$?` 那行
- **方案**：改用 `if cmd; then captured=0; else captured=$?; fi`——`if` 的测试语境里 set -e 自动抑制，同时 `$?` 在 else 分支能正确捕获 cmd 的真实退出码
- **教训**：任何"调子函数 + 根据返回码做后续决策"的 set -e 脚本段，都必须用 `if` 形式；`cmd; ec=$?` 在 set -e 下是隐式陷阱。`cmd || true; ec=$?` 更糟——`||` 把 `$?` 永远变成 0
- **关联 Dev Log**：2026-04-23 20:42

### Gotcha #5 — `[build]` Claude Code 从三处注册 slash command，同名重复即 palette 重复
- **症状**：palette 里 `/handoff` 出现 3–4 条（所有项目通见，用户级作用域）
- **根因**：Claude Code 扫三个来源并全部登记：(1) `~/.claude/skills/*/SKILL.md` 的 `name:` 字段，(2) `~/.claude/commands/*.md`，(3) 任何 `~/.claude/skills/*/commands/*.md`（skill 目录下的嵌套 commands 子目录也被当成有效命令源）。没有跨源去重。
- **方案**：每条 slash 恰有一个注册源。`/handoff` 仅靠 SKILL.md `name:` 注册；`install.sh` `rm -rf` skill 目录里的 `commands/` 子目录；shim 目录只放 recall/tidy（防 fuzzy-match 吞进 `/handoff`），并主动删旧版留下的 `handoff.md`。
- **教训**：打包 skill 时不要把 slash shim **既作为源码镜像留在 skill 目录**、**又同时装到 shim 目录**——后者是 Claude Code 读的，前者会重复登记。install 脚本必须在拷贝后**剥离** skill 内的 `commands/`。
- **关联 Dev Log**：2026-04-23 09:15
- **关联 Decision**：2026-04-23
- **关联 Dev Log**：2026-04-18 v0.4 Round 4

### Gotcha #7 — `[runtime]` Codex `$` selector 以官方 skill 目录为准，不能只生成 `.codex/skills` alias
- **症状**：`$handoff-recall` 等 selector 可能可见但行为落到旧占位 alias；本机 `.codex/skills/handoff-recall` 是新版完整 alias，而 `.agents/skills/handoff-recall` 仍只有"Activate handoff and run command"短占位。
- **根因**：项目 installer / sync 脚本把 Codex 目标建模为 `~/.codex/skills`，但 OpenAI Codex skills 官方文档指向 `$HOME/.agents/skills`；当前测试也编码了旧路径假设，导致绿测不能证明真实 Codex selector 行为正确。
- **方案**：下一轮 TDD 把 `.agents/skills` 设为 Codex 主安装路径；若保留 `.codex/skills`，只作为兼容镜像，并让真实安装态 metadata / alias 验证覆盖 `.agents/skills`。
- **教训**：CLI selector 可用性必须用官方发现路径和真实安装态验证，不能只靠项目内 `agents/codex-commands.txt` 或旧目录镜像说明。
- **关联 Dev Log**：2026-04-30 03:58

### Gotcha #8 — `[build]` 重建当前 release 时不能让 `Release/latest` 指向已删除目录
- **症状**：删除 `Release/handoff-v1.2.1` 后立刻重跑 release，`tests/test_install.sh` 的 `.skill bootstrap` 用例可能从 dangling `Release/latest` 或旧目录集合里拿到错误/不存在的包，导致 commands shim 安装断言失败。
- **根因**：release 重建流程会先删目标目录再跑全量测试；旧测试用 `ls Release/*/handoff-*.skill | head -1`，对新旧 release 布局和 dangling symlink 都不稳。
- **方案**：`tests/test_install.sh` Case 10 优先使用有效的 `Release/latest/handoff-*.skill`，latest 无效时回退到现存最新 `.skill`；重建时如需手动稳定前置条件，可先临时指回上一版。
- **教训**：release tests 不能依赖正在被重建的产物目录；测试 fixture 必须来自已存在且有效的 release artifact。
- **关联 Dev Log**：2026-04-30 23:54

### Gotcha #13 — `[runtime]` cleanup 函数末尾"条件输出"是 set -e 的隐式陷阱
- **症状**：v1.2.9 跨机安装时 `bash install.sh --codex` 在本机 fresh Codex 配置下 abort——脚本走到 Codex 段、调 `cleanup_codex_legacy_mirrors`、清理 0 个 mirror（用户没装过旧版）→ 函数末尾 `[ "$removed" -gt 0 ] && echo "..."` 测试为假返回 1 → set -e 抓到 → 整脚本退出。Pre-existing bug 从初始版本就在，本会话之前没在 fresh Codex 机器跑过 `--codex` 才漏掉
- **根因**：bash 函数末尾 `[ X ] && do-something` 模式——条件不成立时整个表达式 exit 1，函数继承这个 exit code 返回。set -e 在调用方（无 `if`、无 `||`）会把"非零返回"视为错误 abort。这是 Gotcha #6（`cmd; ec=$?`）的**孪生兄弟**：触发面在函数级而非语句级
- **方案**：
  - cleanup 函数末尾**永远**显式 `return 0`（除非真的有错要冒泡）
  - 把"可选输出"从 `[ X ] && echo` 改成 `if [ X ]; then echo; fi`——`if` 测试语境本身就吃掉 set -e；写法也更醒目
  - 加 regression test：sandbox 里 mock"清理对象不存在"场景，断言 install 仍能 exit 0（test_install.sh Case 4b 已落地）
- **教训**：
  - `set -e` + 函数最后一行**条件返回**是隐式陷阱。审 cleanup / log / notify 类函数时检查"末尾是不是 `[ X ] && ...` 或类似"
  - 跨平台/跨配置场景下，"清 0 个东西"和"清 N 个东西"是两条不同代码路径——必须真机或 sandbox 测两种
  - 同一类陷阱（set -e + 条件返回）有多种触发面：Gotcha #6 是语句级（`cmd; ec=$?`），#13 是函数级（末尾 `[ X ] && ...`）。本质相同
- **关联 Dev Log**：2026-05-06 12:22（v1.2.10 发版）
- **关联 Gotcha**：#6（同根，set -e + 条件返回）

### Gotcha #12 — `[build]` Preflight 闸门不能依赖"未来才存在的 artifact"——必须断言**当前可观测状态**
- **症状**：v1.2.7 引入的 `tests/test_release_artifact_content.sh` 加了 "Release/latest 版本号 ≠ dev VERSION 时 skip" 机制（看似聪明：避免 release-in-flight 时 preflight 误判），但实际后果是 release pipeline preflight 时 dev VERSION 已 bump（v1.2.X 新）而 Release/latest 还指向 v1.2.X-1（旧）→ 永远 skip。本会话三次发版（v1.2.6/v1.2.7/v1.2.8）该闸门**从未实际检过 about-to-be-released 的 tarball**。事后跑测试虽然会发现，但 release 已发出去——是马后炮不是闸门。
- **根因**：测试设计的 mental model 错——把"避免误报"放在"建立可信闸门"之上。skip 逻辑等价于关闘门。codex Round 3 review 才点出这个架构问题。
- **方案**：双层闸门
  1. **Source 层（preflight）**：新增 `tests/test_project_tree_forbidden.sh` 扫**项目根**是否含 `Handoff_OldBackup_*` / `Handoff_planning_*` / `docs/superpowers/`——这些都是"该被移出去的"东西，存在即闸门触发。无 skip 逻辑（项目树是当前可观测状态，任何时候都可断言）
  2. **Post-build 层（artifact-content）**：保留现有 `test_release_artifact_content.sh` 作事后兜底——验证打包过程没异常引入新东西
- **教训**：
  - **闸门三准则**：(a) 检查的对象必须是当前可观测的事实；(b) 失败必须真阻塞下游；(c) 不能有 skip-when-X 让闸门退化为 noop
  - skip 逻辑是 anti-pattern——加之前问"如果跳过的条件正好就是阻断阶段，会发生什么"
  - 配套测试不替代主测试——artifact-content 是兜底，project-tree 才是真闸门
- **关联 Dev Log**：2026-05-06 14:23（v1.2.9 发版）
- **关联 Gotcha**：#11（artifact-content 测试本身的来源）

### Gotcha #11 — `[build]` 跨 CLI 项目级路径必须显式枚举；`.sanitize-ignore` ≠ release staging exclude
- **症状**：v1.2.7 给 5 个 shim 改 portable wording 时用 `<project>/.<cli>/skills/handoff/` placeholder——对 Claude Code（`.claude/`）和 OpenCode（`.opencode/`）正确，但 Codex 项目级实际是 `<project>/.agents/skills/handoff/`（不是 `.codex/`）。Codex 项目模式 AI 会找空目录。同时 `docs/superpowers/{plans,specs}/` 在 v1.2.7 source tarball 里泄漏 48 处 dev-time 绝对路径——`.sanitize-ignore` 把这两目录列了白名单，但**那只豁免 release-sanitize.sh 的扫描，不阻止 release.sh stage 把文件打包进 tarball**。两件事一直被混淆。
- **根因**：
  1. 三家 CLI 的安装路径**不能用 `<cli>` 单名字 placeholder 推导**：Claude → `.claude/`，OpenCode → `.opencode/`，Codex → `.agents/`（不是 `.codex/`）。这是上游约定，不可枚举到字面映射就只能错
  2. `.sanitize-ignore` 是**扫描器** allowlist（让 sanitizer 不报错），`release.sh stage_source` 的 `--exclude` 是**打包**过滤器（让 rsync 不拷）。给前者加白名单不让 sanitizer 报警，但文件依然会被打包进 tarball——表象是发布通过、内里仍泄漏
- **方案**：
  - shim wording 显式枚举三家全局路径 + 三家项目级路径，不用 `<cli>` placeholder
  - 内部规划文档（`docs/superpowers/`）移出项目树（→ `../Handoff_planning_0506/`），与 `Handoff_OldBackup_0504` 同手势
  - artifact-content 测试扩 forbidden patterns 加 `Handoff_planning_` / `(^|/)docs/superpowers/`，作为兜底（万一文档被重新拉回项目树，测试拒绝发版）
- **教训**：
  - 跨 CLI 抽象的 placeholder 必须可机械推导；推导不出就**显式枚举**比"看似简洁"重要
  - **打包 ≠ 扫描**：`.sanitize-ignore` 加项 ≠ "这条不会进 release"。要双闸门：sanitizer 只挡内容、staging exclude 只挡路径，缺一不可
  - "把内部文档加白名单"是**反模式**——不该让分发产物含开发上下文，根因是不该打包
- **关联 Dev Log**：2026-05-06 14:06（v1.2.8 发版）
- **关联 Gotcha**：#10（shim portable wording 起点）

### Gotcha #10 — `[build]` shim 文本不能硬编码单一 CLI 路径；release tarball 必须有 artifact-content 兜底闸门
- **症状**：v1.2.6 修了 OpenCode shim **安装路径**（`commands/` → `command/` 单数 + 含 `handoff.md`），但 5 个 shim **内容**仍写"严格按 `~/.claude/skills/handoff/references/handoff-XXX.md` 或 `<project>/.claude/skills/handoff/...` 的规范执行"——OpenCode AI 读到这文本会被指向不存在路径。同时 `gitx-release` wrapper 的 rsync exclude pattern `'HANDOFF.md.bak'`（无星号）漏掉了 `HANDOFF.md.bak.tidy-20260430-2322`，v1.2.5/v1.2.6 source tarball 全部泄漏 4 月底旧 tidy 备份内容。
- **根因**：
  1. shim 是为单 CLI（Claude Code）设计的；跨 CLI 移植时**只想到了路径**没想到**内容引用也得 portable**
  2. wrapper 的 rsync exclude pattern 错（实践证明，gitx-release 全局 wrapper 不归本项目维护，本项目无法靠改 wrapper 兜底）；项目级 release.sh 的 `'/HANDOFF.md.bak*'` 是对的但 gitx-release 不调它
- **方案**：
  - shim 文本 portable wording：枚举 Claude Code / OpenCode / Codex 三家 skill 路径 + 项目级 `<project>/.<cli>/skills/handoff/`，让 AI 知道路径随 CLI 变
  - 删除 `HANDOFF.md.bak.tidy-20260430-2322` 旧 tidy 备份（已无引用，让上游 wrapper 的不完美 exclude 也能漏不出去）
  - **核心防御**：新增 `tests/test_release_artifact_content.sh` 扫 `Release/latest/*-{source,full}.tar.gz` 内容，禁路径 `(^|/)HANDOFF\.md$` / `HANDOFF\.md\.bak` / `HANDOFF\.archive` / `(^|/)memory/` / `\.tmp/` / `\.DS_Store$` / `Handoff_OldBackup_`；测试自带"Release/latest 版本号 ≠ dev VERSION 时跳过"避免 release 进行中 preflight 误判
- **教训**：
  - 跨 CLI 移植不止改路径常量——**所有路径引用文本（含 docs / shims）都得 portable**。codex adversarial review 是这种细节漏洞的有效兜底
  - **不要相信上游 skill 的 exclude pattern**——本项目应有自己的 artifact-content 测试。Codex 建议"add an artifact-level test that inspects every generated tarball"，已落地
- **关联 Dev Log**：2026-05-06 12:46（v1.2.7 发版）
- **关联 Gotcha**：#9（OpenCode 命令路径 commands/→command/，与本条互补）

### Gotcha #9 — `[build]` OpenCode 命令注册：单数 `command/` + 必须显式 shim 主命令
- **症状**：v1.2.5 装到 OpenCode 后，`/handoff` / `/handoff-recall` / `/handoff-tidy` / `/handoff-memory` / `/handoff-init` 全都不出现在 OpenCode 命令面板。`~/.config/opencode/skills/handoff/` 是新版 v1.2.5 没错；`~/.config/opencode/commands/` 里也有 4 个 shim——但 OpenCode 看不到它们。
- **根因**：两条互锁的差异，每条单独都会让命令消失：
  1. **路径约定**：OpenCode 读 `~/.config/opencode/command/`（**单数**），install.sh 写到 `commands/`（**复数**）。OpenCode 自带的 68 条预存命令都在 `command/`；`commands/` 是 install.sh 自创的不存在的目录
  2. **主命令注册**：Claude Code 从 `SKILL.md` `name: handoff` 字段自动注册 `/handoff`（Gotcha #5 的另一面），所以 install.sh 故意不拷 `handoff.md` 进 commands 以防 palette 重复；但 **OpenCode 不会从 skill name 自动注册主命令**，必须显式拷 `handoff.md` 进 `command/`
- **方案**：
  - `install.sh` 三处 OpenCode 路径全部 `commands/` → `command/`（全局 / 项目级 / uninstall）
  - `install_to_dir()` 用 `case "$cli_name" in *OpenCode*) cmds+=(handoff.md);; esac` 让 OpenCode 例外保留主命令 shim；其他 CLI 维持原逻辑（避免 Gotcha #5 重复）
  - 升级路径：v1.2.6 的 install/uninstall 同时清理旧 `commands/`（复数）路径下的 handoff*.md 残留
  - `tests/test_install.sh` Case 3 断言全部改为 `command/`（单数），新增 `handoff.md` 必须存在断言，旧 `commands/` 无残留断言
- **教训**：每个 CLI 的 slash command 注册都得**真机验证**，不能从 Claude Code 的行为外推。OpenCode 的命令目录是 `command/` 单数，跟 Claude Code 的 `~/.claude/commands/` 复数恰好相反。Gotcha #5（Claude Code 从三处注册）和 #9（OpenCode 必须显式 shim）是镜像对称的两个雷区。
- **关联 Dev Log**：2026-05-06 09:17（v1.2.6 发版）

### Gotcha #14 — `[release]` Pre-release gate 的版本真相源必须是项目当前状态，不能是 release pipeline 末端的产物状态
- **症状**：v2.0.0（Dev Log 0031）和 v2.1.0（Dev Log 0039）两次 release 都撞到——`tests/run_all.sh` 跑 `test_doc_freshness.sh` 时 root README/HANDOFF 已 bump 到 v-next 但 `Release/latest` 还指 v-prev → Test 4 `README.md Release/latest 引用` + Test 5 `HANDOFF.md Current State 版本号` 双双判 stale。临时 workaround：revert root README/HANDOFF 回 v-prev → 跑 release（成功翻 latest）→ 升回 v-next → re-commit。后果：release tarball 内 `Release/handoff-v-next/README.md` 锁死 v-prev snapshot，gitx-release audit `§3_sync` 立刻发现 `diff root/README.md vs Release/handoff-v-next/README.md` 不一致（v2.1.0 audit 实测 208 ✅ / 1 ❌ 卡在此条）。
- **根因**：测试设计层把"README/HANDOFF 引用的版本"和"`Release/latest` symlink 当前指向"绑死，但 release pipeline 的时间线本质上不可同步：
  1. 开发期：root VERSION + docs 在工作树上 = v-next（即将发的版本）
  2. Pre-release gate（`run_all.sh`）：此刻 `Release/latest` 仍 → v-prev（上次发的版本，下面才会翻）
  3. Release pipeline：staging + 平摊文档 → tarball；最后才 `ln -sfn handoff-v-next Release/latest`
  时间线 step 1 和 step 2 间必然存在窗口期 root != Release/latest——把这两者强行同步等于禁止 README 引用即将发的版本。本质是测试断言错了真相源。
- **方案**：
  - 真相源切换：`test_doc_freshness.sh` 的 `$LATEST_VERSION` 改为读 root `VERSION` 文件（项目当前/目标版本），不读 `Release/latest` symlink。语义对齐"README 描述自己所在版本的发版状态"，不是"描述当前 deployed 状态"
  - Helper 重命名：`get_latest_release_version()` → `get_project_version()`，标签更新为"与 root VERSION 一致"
  - 加 regression test：`tests/test_doc_freshness_k4_chicken_egg.sh` 用 `ln -sfn handoff-v0.0.1-stale Release/latest`（trap 恢复）+ subprocess 跑 `test_doc_freshness.sh` 断言全 14/0 绿，防止未来回退到 `Release/latest` 真相源
- **教训**：
  - **Pre-release gate 的真相源必须是项目当前状态**（VERSION 文件 / source tree / 工作树），不能是 release pipeline 末端的产物状态（`Release/latest` symlink / 已发 tarball）。这是 Gotcha #12 "闸门检查的对象必须是当前可观测的事实"的细化形态——产物侧虽然也"可观测"，但**时间线滞后于工作树**，pre-release 阶段必然 stale
  - "暂时 revert → release → 升回"的 workaround **看似无害实则毒化 artifact**：tarball 平摊取的是工作树 snapshot，revert 期间的 snapshot 被永久封进 release。下游 gitx-release audit `§3_sync` 会发现，但已经发出去了——是马后炮不是闸门
  - 同一类陷阱（gate 真相源错位）跟 Gotcha #12（skip-when-X 让闸门 noop）本质相同——都是"测试假装在测，实际在配合 release pipeline 摆样子"。审 release-gate 类测试时问"它检查的是工作树事实还是产物事实？"
- **关联 Dev Log**：0041（v2.1.1 K4 root-cause fix）；0031（v2.0.0 K4 manual workaround，本条根因事件）；0039（v2.1.0 K4 manual workaround 第二次）
- **关联 Decision**：0015（为何选改测试真相源而非移除断言或 procedural workflow）
- **关联 Gotcha**：#12（闸门三准则，同根；#14 是其 "fact source"细化）

---
