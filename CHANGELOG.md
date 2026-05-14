# Handoff — Release History

记录各版本的关键变化。最新版本在最上面。

## v2.0.0 — 2026-05-08

**Breaking change: 多文件架构（HANDOFF.md + GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/）**

### Why

v1 单文件 HANDOFF.md 在大型项目实测涨到 121K+，吃掉 47% LLM 上下文窗口（256K 模型下）。Dev Log 占主文件 64% 体积且持续增长。recall 默认全文件读 → 几百条 Dev Log 噪音淹没最近活动 + 单次烧 30K tokens。

v2 把内容按"设计 vs 知识库 vs 事件流 vs 决策"四个语义类切到四个文件 / 目录：

| 内容 | v1 | v2 | 大小 |
|---|---|---|---:|
| 设计 + 状态（Project Overview / Current State / 11 章节） | 主文件 | 主文件 | ~28K |
| Known Gotchas（知识库） | 主文件章节 | `GOTCHAS.md` 单文件 sibling | ~16K |
| Dev Log（事件流） | 主文件 inline | `Handoff_Logs/<NNNN>-<timestamp>-<slug>.md` per-file | ~2-3K each |
| Decision Log（权衡） | 主文件 inline | `Handoff_Decisions/<NNNN>-<date>-<slug>.md` per-file | ~1-2K each |

主文件压缩 **78%**；recall 默认 ~7 文件 / 5-7K tokens（v1 全读约 30K）。

### Key changes

- 🆕 `scripts/lib/handoff-v2.sh` — 共享 helpers：`slugify` / `acquire_next_number`（flock + mkdir spin-lock 双兜底） / `verify_v2_layout` / `regenerate_pointers` / `HANDOFF_V2_MARKER` 常量
- 🆕 `scripts/migrate-to-v2.sh` — 原子迁移工具：`--dry-run` 预览，`--apply` 执行；`.partial` 暂存 + 单个 atomic mv 串接 + EXIT trap 自动回滚（任何失败都还原到验证过的备份）
- 🆕 `assets/GOTCHAS.template.md` — 知识库骨架
- 🆕 `MIGRATION_GUIDE_v2.md`（顶层用户指南）
- 🆕 `tests/test_handoff_v2_schema.sh`（19 cases：slugify / acquire_next_number / verify_v2_layout / regenerate_pointers）
- 🆕 `tests/test_migrate_to_v2.sh`（58 cases：dry-run / per-file write / 主文件原子重写 / rollback 三种触发场景）
- 🆕 `tests/test_handoff_recall_v2.sh`（9 cases：四源读取 contract + frontmatter 验证）
- 🆕 `tests/fixtures/handoff-v1-sample.md`（v1 fixture）
- 🔄 `scripts/tidy-handoff.sh` — 检测到 v1 layout 自动触发 migrate（TTY 提示 / `HANDOFF_TIDY_AUTO_MIGRATE=1` 非交互 / 默认非交互不静默迁移）；新增 `detect_dup_numbers` 函数自动 renumber Syncthing race 留下的同号文件
- 🔄 `scripts/scan-credentials.sh` — directory mode：扫 HANDOFF.md + GOTCHAS.md + Handoff_Logs/* + Handoff_Decisions/*
- 🔄 `scripts/rotation-reminder.sh` — directory mode（resolve `<dir>/HANDOFF.md`）
- 🔄 `scripts/validate-handoff.sh` — directory mode + v2 marker integrity check（pointer stat 行存在性，软警告不阻断）
- 🔄 `scripts/archive-devlog.sh` — v2 directory mode 改为按年归档：`Handoff_Logs/<NNNN>-<YYYY>-*` 当 YYYY < 当前年-1 时移到 `Handoff_Logs.archive/<YYYY>/`；v1 单文件模式（>50 阈值）保留向后兼容
- 🔄 `install.sh` — 当 PWD 有 v1 HANDOFF.md 时打印 warning 引导用户跑 `/handoff-tidy`（非阻断；`HANDOFF_INSTALL_SKIP_V2_GATE=1` 静默）
- 🔄 `assets/HANDOFF.template.md` — 顶部加 `<!-- HANDOFF v2 schema -->` marker；Known Gotchas / Decision Log / Development Log 三段改为 pointer 块（`共 0 条；最新：(none)`）
- 📝 `references/handoff-write.md` 全面重写：per-file 写入 + frontmatter + regenerate_pointers 自动 stat
- 📝 `references/handoff-recall.md` 全面重写：HANDOFF.md + GOTCHAS.md + Handoff_Logs/ 最近 N 文件四源读取
- 📝 `references/handoff-init.md` 全面重写：四件套创建（HANDOFF + GOTCHAS + 两个空目录）

### Backward compatibility

- 旧脚本调用方式（`scan-credentials.sh HANDOFF.md`）仍工作——四个安全脚本自动 detect file vs directory
- v1 HANDOFF.md 在新 install 下仍能被读，只是新写入操作（`/handoff`）会拒绝写入并提示先跑 `/handoff-tidy` 迁移
- frontmatter `schema: 2` 字段为未来 v3 留扩展点

### 升级

```bash
cd <plugin-checkout> && bash install.sh   # 升级 skill 本体到 v2.0.0
cd <project> && /handoff-tidy             # 触发自动迁移
```

详见 `MIGRATION_GUIDE_v2.md`。

Artifacts: `Release/handoff-v2.0.0/`（待 K4 gitx-release 生成）

---

## v1.2.10 — 2026-05-06

**install.sh Codex install bug — `cleanup_codex_legacy_mirrors` set -e abort fix**

跨机安装 v1.2.9 时发现 install.sh 在本机 fresh Codex 配置上 abort 在 Codex 段。诊断结论：`cleanup_codex_legacy_mirrors` 函数末尾用 `[ "$removed" -gt 0 ] && echo "..."` 作通知输出条件，当 `removed=0`（无 legacy mirror 要清）时整个 `[ -gt ]` 测试返回 1，函数以非零退出码返回，`set -e` 在调用方触发整脚本 abort。这正是 HANDOFF.md Gotcha #6（"`cmd; ec=$?` + set -e" 陷阱）的孪生模式。

**触发条件**：用户装过 Codex CLI（`~/.codex/skills/` 已被其他 skill 创建）但**没装过旧版 handoff**（无 `handoff*` 子目录）→ removed=0 → set -e abort。任何 fresh Codex 用户首次装 handoff 都会踩。Pre-existing bug，从初始版本就在，本会话之前没真机跑过 `--codex` 才漏掉。

修复：

- 🔴 `install.sh`：`cleanup_codex_legacy_mirrors` 末尾改 `if [ ... ]; then; fi` 形式 + 显式 `return 0`
- ✅ `tests/test_install.sh` Case 4b：mock `~/.codex/skills/` 存在但无 legacy mirror 场景，断言 install 仍能 exit 0 完成；TDD 先红后绿（3 断言）
- 📝 `HANDOFF.md` Gotcha #13：cleanup 函数末尾"条件输出"是 set -e 隐式陷阱（与 Gotcha #6 同根，函数级触发面）

Artifacts: `Release/handoff-v1.2.10/`

---

## v1.2.9 — 2026-05-06

**Codex adversarial review round 3 — 项目树预 flight 闸门修补**

v1.2.8 跑第三轮 codex adversarial review，verdict needs-attention。**新发现 1 条 high**——架构层面：v1.2.7 引入的 `tests/test_release_artifact_content.sh` 的 "VERSION ≠ Release/latest 时 skip" 机制让该测试**永远在 release pipeline 的 preflight 阶段被跳过**——

```
preflight 时: VERSION=v1.2.X (新), Release/latest=v1.2.X-1 (旧)  → skip
release 完成: Release/latest 更新到 v1.2.X
下次跑测试: 此时已发版，事后兜底
```

结果是本会话三次发版（v1.2.6/v1.2.7/v1.2.8），artifact-content 测试**从未真正在 release pipeline 里检过 about-to-be-released 的 tarball**——靠运气没事，不是靠闸门。

修复：

- ✅ 新增 `tests/test_project_tree_forbidden.sh`：preflight 阶段扫**项目根**是否含 `Handoff_OldBackup_*` / `Handoff_planning_*` / `docs/superpowers/` 等"该被移出去的"路径。无 skip 逻辑，任何时候跑都有意义；TDD 双向验证（clean 绿 / 临时 symlink 红）
- 📝 设计哲学：source 闸门（项目树脏不让 release）+ post-build 兜底（artifact-content）双层；前者抵 99%，后者抓打包过程异常引入的边缘情况
- 📝 `HANDOFF.md` Gotcha #12：preflight 闸门必须基于"对当前可观测状态可断言"的事实，而不是"等 release 完成后回头看"——否则 skip 逻辑会把闸门倒空
- 修了一个 test 实现 bug：bash 字面路径展开不查存在性（无 glob 字符时即使路径不存在也返回字符串），加 `[ -e ]` 二次过滤

Artifacts: `Release/handoff-v1.2.9/`

---

## v1.2.8 — 2026-05-06

**Codex adversarial review round 2 — Codex 项目路径 + 内部规划文档泄漏**

v1.2.7 跑第二轮 codex adversarial review，确认前两条 high 已修，但**新发现 2 条 high**：

1. **Codex 项目路径假设错**：v1.2.7 shim wording 用 `<project>/.<cli>/skills/handoff/` placeholder，对 Claude (`.claude/`) 和 OpenCode (`.opencode/`) 正确，但 Codex 项目级实际是 `<project>/.agents/skills/handoff/`（`install.sh:405`），不是 `.codex/`。Codex 项目模式下 AI 会找空目录
2. **`docs/superpowers/{plans,specs}/` 仍在 release source tarball 里**：48 处 dev-time 绝对路径（开发者本地文件系统下的 Desktop 目录）泄漏。`.sanitize-ignore` 把这两目录加白名单只让扫描器豁免，**没阻止打包**；v1.2.7 新增的 artifact-content 测试只查路径名不查内容，没抓住

修复：

- 🟠 5 个 shim wording：删除通用 `<cli>` placeholder，显式枚举三家项目级路径（`.claude/`、`.opencode/`、`.agents/`）
- 🔧 `mv docs/superpowers ../Handoff_planning_0506/` —— 内部规划文档移出项目树（与 `Handoff_OldBackup_0504` 同手势），不丢数据但脱离打包作用域
- ✅ `tests/test_release_artifact_content.sh` 扩 forbidden 路径：`Handoff_planning_` / `(^|/)docs/superpowers/`，作为兜底（万一文档被重新拉回，测试会拒绝）
- 📝 `HANDOFF.md` Gotcha #11：跨 CLI 的项目级路径**必须显式枚举**而非 placeholder；`.sanitize-ignore` 与 release staging exclude 是**两件事**，前者只豁免扫描，后者才阻打包

Artifacts: `Release/handoff-v1.2.8/`

---

## v1.2.7 — 2026-05-06

**Codex adversarial review fixes — shim 文本 portable 化 + tarball 内容兜底闸门**

v1.2.6 发版后跑 codex adversarial review，揭示**两条 high-severity 残留 bug**：

1. **OpenCode shim 文本仍是 Claude-only**：5 个 shim 都硬编码 `~/.claude/skills/handoff/references/handoff-XXX.md` 或 `<project>/.claude/...` 作为执行参考，OpenCode 用户的 AI 读到这文本会被指向不存在的路径。v1.2.6 只修了**安装路径**没修**内容引用**。
2. **release source tarball 泄漏 `HANDOFF.md.bak.tidy-*`**：gitx-release wrapper 的 rsync exclude 用 `'HANDOFF.md.bak'`（无星号），匹配不到带后缀的 tidy 备份。v1.2.5 / v1.2.6 source tarball 都漏了这个 4 月底的旧 tidy 备份（含项目内部开发上下文）。

修复：

- 🟠 5 个 shim 文本 `~/.claude/skills/handoff/references/...` 改成 portable wording：枚举 Claude Code / OpenCode / Codex 三家路径 + 项目级 `<project>/.<cli>/skills/handoff/`，让 AI 不依赖单一 CLI 路径
- 🔧 删除 `HANDOFF.md.bak.tidy-20260430-2322`（4 月底旧 tidy 备份，已无引用）
- ✅ 新增 `tests/test_release_artifact_content.sh`：扫 `Release/latest/*-{source,full}.tar.gz` 内容，禁路径含 HANDOFF.md / HANDOFF.md.bak* / HANDOFF.archive* / memory/ / .tmp/ / .DS_Store / Handoff_OldBackup_*；TDD 先红后绿
- 📝 `HANDOFF.md` Gotcha #10：tarball staging 兜底闸门——不要全靠上游 wrapper 的 exclude pattern，本项目应有 artifact-content 测试

Artifacts: `Release/handoff-v1.2.7/`

---

## v1.2.6 — 2026-05-06

**OpenCode install path fix — `commands/`（复数）→ `command/`（单数） + 主命令 shim**

跨机验证 v1.2.5 安装时发现 OpenCode 用户报告 `/handoff` 等命令完全不出现。诊断结论：

- OpenCode 读 `~/.config/opencode/command/`（**单数**）；install.sh 写到 `commands/`（**复数**）—— 完全错位
- OpenCode 不像 Claude Code 那样从 SKILL.md `name:` 字段自动注册主命令——必须显式 shim `handoff.md`
- v1.2.5 及之前的 OpenCode 安装会留下 0 个有效 handoff 命令

修复：

- 🔧 `install.sh`：OpenCode 路径全 `commands/` → `command/`（全局 / 项目级 / uninstall 三处）
- 🔧 `install.sh`：`install_to_dir()` 对 `OpenCode` cli_name 例外，拷 `handoff.md` 到 commands；其他 CLI 仍按 Claude Code 规则跳过（避免 Gotcha #5 palette 重复）
- 🔧 `install.sh`：升级路径——清理 v1.2.5 误装到 `commands/`（复数）的残留 shim
- ✅ `tests/test_install.sh` Case 3：6 条断言改 `command/`（单数），新增 `handoff.md` 必须存在断言，旧 `commands/` 无残留断言；TDD 先红后绿
- 📝 `HANDOFF.md` Gotcha #9：OpenCode 命令注册的差异（与 #5 互为镜像）
- 📝 `HANDOFF.md` / `README.md` 顺手追平 v1.2.4 → v1.2.5 → v1.2.6 的双重漂移

Artifacts: `Release/handoff-v1.2.6/`

---

## v1.2.5 — 2026-05-05

**CodeRabbit Round 5 review fixes — 14 findings 全修 + 文档漂移补丁**

- 🔴 `tests/test_shellcheck.sh`：shellcheck 缺失分支补 `exit 1`，避免 summary 后继续执行 Test 2 引发崩溃；scripts glob 用 `nullglob` + 数组检测，防 `*.sh` 字面传给 shellcheck
- 🟠 `scripts/emit-sbom.sh` + bundle：新增 `json_escape()`（bash 参数展开实现，bash 3.2+ 兼容），对 `SKILL_NAME` / `VERSION` / artifact 名全量 JSON 转义（`\\ \" \b \f \n \r \t`），消除 SBOM heredoc 注入风险
- 🟡 `install.sh`：`--project` / `--template` 拒绝空值或 `-*` 开头参数，避免误吞下个 flag
- 🟡 `scripts/emit-token-usage.sh` + bundle：`basename` → `${f#"$SKILL_DIR/"}` 保留嵌套子目录路径
- 🟡 `tests/test_release_dry_run_audit.sh`：awk 改用 brace-depth 计数器，函数体提取在嵌套 `{}` 上不再断
- 🟡 `tests/test_bundle_sync.sh`：注释 "4 shims" → "5 shims"（与循环实际项数对齐）
- 🟡 `tests/fixtures/placeholder.md`：`AWS_SECRET` → `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`（贴近真实部署变量名）
- 🟡 `skills/handoff/SKILL.md`：License badge 改用 shields.io 图片 URL（之前是网页链接渲染坏的）
- 📝 文档漂移修复：HANDOFF.md / TEST-SCENARIOS.md 三端测试计数对齐到 19 套件 / 352 断言；`docs/superpowers/plans/2026-05-01-issue-resolution.md` 硬编码绝对路径 → `./.sanitize-ignore`
- 📝 v1.2.3 → v1.2.4 文档漂移补丁：HANDOFF.md / README.md 当前版本字段、Release/latest 引用、.skill 文件名全部对齐到 v1.2.4（v1.2.4 artifacts 已存在但无 CHANGELOG 条目，本版借此整体收口）
- ✅ 测试套件：19 suites / 352 passed / 0 failed；bundle parity 字节一致

Artifacts: `Release/handoff-v1.2.5/`

---

## v1.2.4 — 2026-05-04

**Documentation alignment — 把根 CHANGELOG / README / HANDOFF 引用追平 v1.2.3**

- 📚 根 `CHANGELOG.md`：补 v1.2.2 + v1.2.3 真实条目（之前 gitx-release 流程只写 `Release/CHANGELOG.md`，根 CHANGELOG 自 v1.2.0/v1.2.1 后未跟进）
- 🔧 `README.md`：Release 树形图 `latest → handoff-v1.2.3`，artifact 文件名同步更新
- 🔧 `HANDOFF.md`：Project Overview 当前版本 + Maintenance 阶段标注更新到 v1.2.3
- ✅ `test_doc_freshness.sh` 五个版本号检查全绿（README + HANDOFF 与 `Release/latest` 对齐）
- 📦 `.skill` / source tarball 现在包含完整版本历史，分发给同事拿到的就是最新文档

无功能性代码改动，所有脚本与 v1.2.3 二进制一致。

> 注：v1.2.4 走完了 release.sh 全流程并产生 `Release/handoff-v1.2.4/` 完整产物，但根 CHANGELOG.md 当时未同步入库——本条 entry 由 v1.2.5 回补登记。原始记录见 `Release/CHANGELOG.md`。

Artifacts: `Release/handoff-v1.2.4/`

---

## v1.2.3 — 2026-05-04

**Round 4 review fixes — 防御性修复 + 工具链兼容**

- 🐛 `scripts/archive-devlog.sh`：源 anchor 缺失时，`skip_until_anchor` 模式遇下一 `## ` 章节标题退出 skip 并 re-emit；防止 Dev Log 之后的章节被静默吞掉
- 🔧 `release.sh`：删除从未赋值的 `$SKILL_SRC` 死引用，简化 SKILL.md 拷贝路径（4 行 → 2 行）
- ✅ 测试套件：Case 8（3 断言）覆盖 archive-devlog 防御路径；总断言 349 → 352
- 🛠 `.sanitize-ignore`：白名单 `TEST-SCENARIOS.md`（Scenario 4.1/4.2 含 sanitizer 行为示例需要命中模式）
- 📦 `skills/handoff/scripts/archive-devlog.sh`：bundle 镜像同步保持 byte-identical

Artifacts: `Release/handoff-v1.2.3/`

---

## v1.2.2 — 2026-05-01

**测试套件完整化 + 文档审计 + 3 轮独立 review**

- ✅ 测试套件：解锁本地 shellcheck 套件（3 断言），全量 346 → **349 全绿**（19 套件）
- ✅ TDD 迭代：`test_tidy_handoff.sh` Case 14 短锚点幂等（14A/14B/14C）；`test_scan_credentials.sh` GitHub PAT label 收紧；`test_doc_freshness.sh` Test 13/14 对称漂移守卫（"8 种 → 11 种密钥前缀"）
- 📚 文档审计：14 处漂移修复（CHANGELOG 缺失、断言数过时、命令清单不全、路径写法统一）
- 🛠 `.sanitize-ignore`：白名单 `docs/superpowers/plans|specs`（内部规划文件含 dev-time 绝对路径，按设计豁免）
- 🔒 `release.sh`：`SKILL_STAGE` 初始化提前；EXIT trap 统一清理防内存泄漏
- 🔧 `tidy-handoff.sh` + bundle 镜像：awk 锚点检测 `/Development Log/` → `/Development Log[[:space:]]*$/` 防复合标题误匹配
- 🤝 3 轮独立 code review：Round 1 修复非对称守卫，Round 2/3 直接 Approved

Artifacts: `Release/handoff-v1.2.2/`

---

## v1.2.0 / v1.2.1 — 2026-04-30

**命令扩充 + 安全加固 + Codex 路径修正**

- ✨ `/handoff-init` 新命令：一键从模板初始化 `HANDOFF.md`，适用于首次接手项目
- 🧪 `/handoff-memory` 新命令（experimental）：opt-in 把 CC auto-memory 经验条目同步到项目 `./memory/`；默认关闭，`on` 后每次 `/handoff` 自动同步；双护栏（`.gitignore` 提示 + 凭证扫描）
- 🔒 Slash command 单源注册：`/handoff` 只经 `SKILL.md` name 注册，消除三源重复注册风险
- 🔒 Release sanitizer 强制门：不可通过 `FORCE=1` 绕过，含敏感信息的 release 直接中止
- 🔒 `validate-handoff.sh --readiness`：新增 recall-readiness 校验模式，供 `/handoff-recall` 前置检查使用
- 🔧 Codex 官方路径修正：安装目标从 `~/.codex/skills` 迁至 `~/.agents/skills`；legacy 路径自动清理
- ✨ Codex `$` aliases：`$handoff` / `$handoff-recall` / `$handoff-tidy` / `$handoff-init` / `$handoff-memory` 全套支持
- ✨ Release manifest：每次发版生成含 SHA-256 清单的 `RELEASE_MANIFEST.txt`
- ✨ 文档漂移防护：`test_doc_freshness.sh` 检测 README / HANDOFF 版本号是否跟随 `Release/latest`

Artifacts: `Release/handoff-v1.2.0/` / `Release/handoff-v1.2.1/`

---

## v1.1 — 2026-04-22

**多 CLI 适配 + 跨平台支持（macOS / Linux / Windows WSL）**

- ✨ `install.sh` 重写：自动检测并安装到 Claude Code / OpenCode / Codex CLI 三个 AI CLI
- ✨ `install.sh` 新增 `--claude` / `--opencode` / `--codex` 参数，支持选择性安装
- ✨ `install.sh` 自动平台检测（macOS / Linux / WSL / Git Bash）
- ✨ `install.sh` WSL 桥接：自动定位 Windows `%AppData%/Claude/` 路径
- ✨ `install.sh` 项目级安装 + `--uninstall` 同步清理三个 CLI

Artifacts: `Release/v1.1/`

---

## v1.0 — 2026-04-22

**正式版 v1.0 — Bug #13-#15 修复 + 安装体验全面提升**

- 🔧 Bug #13 修复：`release.sh` rsync 排除 `HANDOFF.md` / `HANDOFF.archive.md`
- 🔧 Bug #14 修复：`install.sh` `cleanup_legacy` 补上 `handoff-tidy.md`
- 🔧 Bug #15 修复：`release-audit.sh` §5 `workspace` 检查 pattern 精确匹配
- ✨ `install.sh` 安装后显示版本 + 自动验证关键文件
- ✨ `install.sh --uninstall` 清理完毕后提示检查项目级残留

Artifacts: `Release/v1.0/`

---

## v0.9.9 — 2026-04-21

**Audit 大幅加固：开源合规 + skill bundle 内容质量（129 checks）**

- ✨ `release-audit.sh` §2b/§6b/§11 新增 85 项：README/LICENSE/CONTRIBUTING/RELEASE_NOTES 内容质量 + skill bundle 结构检查 + 开源合规整体检查
- 🔧 audit 总 checks 从 47 → 129

Artifacts: `Release/v0.9.9/`

---

## v0.9.8 — 2026-04-21

**Audit 大幅加固：开源合规 + skill bundle 内容质量检查**

- ✨ `release-audit.sh` §2b/§6b/§11 三个新 audit 节
- ✨ skill bundle SKILL.md 结构、scripts 权限、references 标题全覆盖

Artifacts: `Release/v0.9.8/`

---

## v0.9.7 — 2026-04-21

**Release pipeline Round 2 验证 — 连续第二轮无新 bug**

- ✅ Round 1（v0.9.6）：47/47 PASS，原子回审全部通过
- ✅ 三脚本静态分析：语法全 OK，所有历史修复完整保留

Artifacts: `Release/v0.9.7/`

---

## v0.9.6 — 2026-04-21

**Release pipeline Round 1 验证**

- ✅ 三脚本静态分析：语法全 OK，修复（Bug #1-#12）完整保留
- ✅ audit 47 checks 覆盖范围确认

Artifacts: `Release/v0.9.6/`

---

## v0.9.5 — 2026-04-21

**文档修复：方式 B 安装缺少 slash commands 步骤**

- 🔧 Bug #12 修复：`INSTALL.md` 方式 B 补上 slash commands 复制步骤
- 🔧 `release-audit.sh` §10 新增：skill 有 `commands/` 时检查 RELEASE_NOTES 方式 B

Artifacts: `Release/v0.9.5/`

---

## v0.9.4 — 2026-04-21

**Release pipeline Round 2 验证 — 连续第二轮无新 bug**

- ✅ Round 1（v0.9.3）：46/46 PASS
- ✅ 三脚本静态分析：无新 bug，修复（Bug #7-#11）完整保留

Artifacts: `Release/v0.9.4/`

---

## v0.9.3 — 2026-04-21

**Slash commands 自包含 + release pipeline 系统性加固**

- 🔧 Bug #10 修复：slash command shims 迁入 `skills/handoff/commands/`，skill bundle 自包含
- 🔧 Bug #11 修复：rsync `--exclude='/commands'` 根目录锁定
- 🔧 `release-audit.sh` §5/§6/§8 新增检查项

Artifacts: `Release/v0.9.3/`

---

## v0.9.2 — 2026-04-21

**5 个脚本 UX 统一 — 无参数默认扫 `./HANDOFF.md`**（patch — 纯 DX 改进，无破坏变更）

- 🎨 `validate-handoff.sh` / `tidy-handoff.sh` / `rotation-reminder.sh` / `archive-devlog.sh` / `scan-credentials.sh` 五份脚本统一：
  - 无参数自动默认 `./HANDOFF.md`（之前会抛 bash `${1:?}` 难看的 `line 6: 1: Usage:` 错误）
  - 新增 `-h/--help` 输出清爽的 `Usage: $0 [file]` + `Exit: ...`
  - 文件不存在的错误消息统一为 `❌ file not found: <path>` + usage hint
- 🔧 `scan-credentials.sh` 保留 stdin pipe 分支，新增无参无 stdin 时回落到 `./HANDOFF.md`
- 🔧 同名脚本双副本（根 `scripts/` + `skills/handoff/scripts/`）byte-identical 同步——符合 v2.2 policy §4 #11（silent ghost release 护城河）

**背景**：v0.9.1 发布后用户在项目根跑 `./scripts/validate-handoff.sh` 直接碰到 bash 参数展开的原始错误格式，不符合"CLI 工具该有的体感"。

**测试**：`bash tests/run_all.sh` → All suites passed ✅（31/31）

Artifacts: `Release/v0.9.2/`

---

## v0.9.1 — 2026-04-21

**5-Expert Review 选择性修复 + validator 误警 bug 消除**（patch release — 全 bug 修复 + 测试补强 / 无新功能 / 无破坏变更）

- 🐛 `validate-handoff.sh` / `tidy-handoff.sh` `has_section` regex 右端锚定修复 — 复合标题 `## 📚 References & Docs Map` / `## 🗺 Milestones & Roadmap` / `## ✨ Features & Modules — 已交付全景` / `## 🧪 Testing — 详细测试状况` 不再被误判为 missing；同时保持 `Architecture Notes` 不会假匹配 `Architecture`。**影响**：template 自身从 3 条 RECOMMENDED 误警 → 0 warning
- 🔧 `SKILL.md`：脚本数 "四个" → "五个"（随 v0.8 加入 `tidy-handoff.sh` 后未同步）
- 🔧 `SKILL.md` ↔ `README.md` 9 条核心约束对齐 — 两文档之前清单分歧（一个含"时间戳 date 命令"、一个含"Token 成本节制"）已统一为 README 版；时间戳规则降级为「执行流程」操作步骤
- 🔧 `CHANGELOG.md`：v0.9 条目对 `TKX_Git_Release_policy_and_process.md` 的引用补注"仅源码仓库保留，`.skill` 分发包不含"
- 🔧 `CONTRIBUTING.md`：目录结构表重写，标注 canonical template path 为 `skills/handoff/assets/`；根目录 `templates/` 明确为 legacy 镜像
- ✨ `skills/handoff/references/handoff-write.md`：Dev Log 模板加入 "走过的弯路" 可选指引（捕获被放弃方案的默会知识）
- 🧪 `tests/test_tidy_handoff.sh` +Case 10 — **I9 invariant（tidy 只动结构不动内容）内容保全测试**：构造含中英混排 / 引号 / 代码块 / emoji 的脏样本，验证 tidy 后"非空非锚点行"字节级相等。最关键不变量从 0 测试 → 有回归
- 🧪 `tests/test_validate_handoff.sh` +2 用例 — 复合标题正向识别 + "Architecture Notes" 反向拒绝
- 📝 `HANDOFF.md` Dev Log & Decision Log：记录 5-Expert Review 选择性接受原则（成本 × 收益 × 不修代价三维筛选，4 条 P0/P1 显式拒绝）
- 📝 `HANDOFF.md`：redact 两处泄漏的绝对用户路径（归一为 `~/...` / `<sibling-project>/...` 形式）

**测试**：`bash tests/run_all.sh` → All suites passed ✅（tidy 10→12、validator 29→31，净增 4 用例）

Artifacts: `Release/v0.9.1/`

---

## v0.9 — 2026-04-21

**Tidy 命令正式随版发布 + 发布门禁强化 + 文档体系完整化**

- ✨ `/handoff-tidy` 命令随 v0.9 正式打包（v0.8 开发、v0.9 出货）：结构整理 + 最新 template 对齐 + 后置四连检查；只动结构不动内容；幂等
- ✨ `/handoff-recall` / `/handoff-tidy` 新增独立 slash shim（`commands/*.md`）避免被 fuzzy 匹配成 `/handoff`
- ✨ `release.sh` 引入 sanity gate：发布前双重扫描敏感信息（source staging + 解压 `.skill` 内容），任一失败即 abort
- ✨ 新增 `scripts/release-sanitize.sh`：阻断 6 类敏感信息（凭证 / 绝对用户路径 / 真实邮箱 / 公网 IP / MAC / SSH/GPG 指纹），含合理豁免白名单
- ✨ `release.sh` 把根目录核心文档（README/INSTALL/CHANGELOG/TEST-SCENARIOS/LICENSE/CONTRIBUTING）+ SKILL.md **平摊**到 `Release/<版本>/` 顶层，用户不解压即可浏览
- ✨ per-version 文件从错误的 `README.md` 重名改为 `RELEASE_NOTES.md`，不再和主 README 冲突
- ✨ 新建 `TEST-SCENARIOS.md`：Happy / 边界 / 错误 / 安全 / 幂等 五维验证场景手册（每场景 Setup/Action/Expected/Verify 四字段）
- ✨ 新建 `TKX_Git_Release_policy_and_process.md`：跨项目通用的发版政策与流程标准（10 章 + 约 25 条低级错误防呆清单）。*注：该文件只在源码仓库保留，`.skill` 分发包不包含。*
- ✨ README.md 重写为完整技能说明书：Philosophy（Norman / Dijkstra / Nonaka）/ Logical Model / 工作原理 / 核心约束
- ✨ INSTALL.md 重写为完整操作手册：安装 4 种方式 / 升级（含单文件升级 + 项目内 HANDOFF.md 同步）/ 卸载 / 验证 / 维护 / 排错
- ✨ SKILL.md 末尾追加 License section（MIT + TKXLAB.AI 版权 + 集成回链建议）
- 🔧 source tarball 排除 dev-only 目录（`skills/handoff-workspace/`、`commands/`）
- 📝 记录新规则：用户说 "release" 时自动决定下一个版本号并启动发布流程（不再每次问版本号）

Artifacts: `Release/v0.9/`

---

## v0.8 — 2026-04-20

**初代 Tidy 命令 + 单文件分发就绪**（注：v0.8 的 tidy 实现为 v0.9 的前身）

- ✨ 新增 `/handoff-tidy` 命令——对已有 HANDOFF.md 做结构整理与升级
  - 自动：压缩多余空行、补齐 Dev Log 锚点（真有改动才备份到 `.bak`）
  - 诊断：缺失章节、Dev Log 乱序、缺字段、> 50 条提示归档
  - AI 按严格规则修复：**只动结构不动内容**（不合并、不摘要、不改原文）
  - 跑 scan / validate / rotation / archive 后置四连检查
  - 幂等：连跑两次结果一致
- ✨ 新增 `release.sh` + `Release/` 目录，每个版本产出 `.skill` 和 source tarball
- ✨ 重写 `install.sh` 适配 skill 格式（v0.4 时代旧 commands/ 残留会被自动清理）
- ✨ 新增 `INSTALL.md` 完整分发指南（4 种安装方式 + 排错 + 文件位置速查）

Artifacts: `Release/v0.8/`

---

## v0.7 — 2026-04-20（合并进 v0.8，未单独打包）

**三专家审查修复**（Don Norman + Dijkstra + Nonaka 的 Philosophy / Logic / Tacit Knowledge 审查）

- 🔴 P0: `archive-devlog.sh` 原子性 + dedup——archive 先写再 mv、main 后 mv，避免 TOCTOU；dedup 保证重试幂等
- 🔴 P0: 反馈三态诚信——`rotation-reminder` 发现时 exit 1；`handoff-write.md` 回显区分 `✅ 通过 / ⚠️ 发现 / ➖ 跳过（脚本未找到）`
- 🟠 P1: 重复检测去 LLM 依赖——改为"改动文件集合精确相等 + 10 分钟窗口"可计算谓词
- 🟠 P1: Stakeholder 硬提问——5 个具体问题（谁批准架构 / 谁是隐性专家 / 最后深度贡献者 / 未来接手人 / 外部依赖联系）
- 🟠 P1: 新增 `## 🔍 Open Questions / Mysteries` 章节——承接未解的 tacit 知识
- 🟡 P2: 新增 `## 💬 Reader Notes` 章节——把文档从广播变对话（Nonaka Ba）
- 🟡 P2: Quick Start 命令表加"写入模式"列（Dev Log 追加 vs Current State 覆盖）
- 🔧 P3: `validate-handoff.sh` 正则右端锚定，拒绝 `Architecture Notes` 伪通过

---

## v0.6 — 2026-04-20（合并进 v0.8）

**长期可用性**

- ✨ `archive-devlog.sh`：Dev Log > 50 条自动移到 `HANDOFF.archive.md`
- ✨ Recall 改为"精华章节 + 最近 N 条 Dev Log"（默认 5），支持 `/handoff-recall 10` 覆盖
- ✨ 写入前重复检测：10 分钟内改动文件集合相等时询问用户

---

## v0.5 — 2026-04-20（合并进 v0.8）

**去 git 化**

- 💥 移除所有 git 相关功能——handoff 是用户级工作记忆，不依赖版本管理
- 🗑️ 删除 `install-hook.sh` / `uninstall-hook.sh` / `tests/test_install_hook.sh`
- 📝 `/handoff-recall` 不再读 git 状态、不做漂移检测

---

## v0.4 — 2026-04-18

**5-persona 审查补足**

- ✨ 凭证扫描（scan-credentials.sh）8 种前缀
- ✨ 凭证轮换提醒（rotation-reminder.sh）三级
- ✨ 结构校验（validate-handoff.sh）REQUIRED / RECOMMENDED
- ✨ 模板扩展至 15 章节（Goals / Non-Goals / Milestones / Features / Testing / References）
- ✨ Decision Log 独立章节

---

## v0.3 — 2026-04-18

**哲学审查后减法**

- 🗑️ 从 v0.2 膨胀版砍回实用主义

---

## v0.2 — 2026-04-18

**自动化 + 锚点追加**

- ✨ `date` 命令采集时间戳
- ✨ 锚点精确定位 Dev Log 追加位置

---

## v0.1 — 2026-04-18

**初版融合**

- ✨ 从两个内部项目抽取共同模式
- ✨ 两条 slash 命令：`/handoff` + `/handoff-recall`
