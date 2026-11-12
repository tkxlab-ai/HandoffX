# P2.4 — 终阶自迁移：四件套改名 + 本仓真迁 + v4.0.0：设计稿（2026-10-31）

> 承载：设计 `docs/2026-05-19-p2-handoffx-megaprogram-design.md` §6（P2.4）+ Decision 0020/0025；Boss 2026-10-31「直接进 P2.4」「继续有序的执行」+ autopilot 授权；守卫处置由 Boss 委托我裁定（见 §3.6）。预演证据：Dev Log 0073 B 段（迁移器对本仓新鲜拷贝 72/31 干净落地；翻常量后 run_all 有 15 个测试套件共 193 项红；文档 166 处旧 token）。
> 评审节律（§1 T7）：P2.4 三源阶（opus + silent-failure-hunter + Codex）；plan 先过 Codex；**对真仓执行自迁移那一步须 Boss 明文授权（Q3/T6，不可豁免）**。

## 0. 意图与 Why

工具已叫 `handoffx`（v3.0.x），但它产出的项目文件仍叫 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`。P2.4 把这三样改成 `HANDOFFX.md` / `Handoffx_Logs/` / `Handoffx_Decisions/`（`GOTCHAS.md` 不动，ADR-0005），让工具默认产出新名，并拿本仓（截至 `p2.4-start` 73 条 Dev Log、32 条 Decision——数量以 `ls | wc -l` 机械派生为准、全部交叉引用）做第一个真实迁移——证明 P2.1 造的迁移器在真实规模下安全。对用户是第二次 breaking（项目文件名变），另起 **v4.0.0**；老项目不自动改，用户显式跑 `/handoffx-tidy schema-upgrade`（Decision 0028 决策 3）。

## 1. 目标 / 非目标 / 反目标

- **目标**：(a) `scripts/lib/handoff-schema.sh` 四常量翻到新名，所有脚本随常量走（P2.0 已 schema-agnostic）；(b) 迁移器在常量翻转后仍能正确识别"旧四件套 → 新四件套"；(c) 测试码对四件套名 schema-agnostic（读常量，不写字面量）；(d) 本仓自迁移完成、`HANDOFFX.md` 成为主文件、postflight/xref/B① 对新 schema clean；(e) 文档/模板/脱敏配置/发布链跟随；(f) P2.2 守卫退役，换轻量永久守卫；(g) run_all 全绿（macOS + Linux 容器）；(h) 真切 v4.0.0，三家重装到 v4。
- **非目标**：不自动迁移用户项目；不改 `GOTCHAS.md` 名；不改 gitx；不做公开镜像发布（Boss 已跳过）；不改 `handoff-*.sh` 脚本基名、函数名、`HX_*` 变量名（L1/L2，ADR-0005 稳定接口）。
- **反目标**：翻完常量后脚本里仍有任何一处四件套**新名**字面量（`test_handoff_schema` 零散落 baseline 必须对新名成立）；迁移器把"新名"当"旧名"；源码包把 `HANDOFFX.md`/`Handoffx_*` 发出去；守卫退役后旧注册名/旧四件套名可以悄悄回流。

## 2. 约束

- bash 3.2 / mawk；`scripts/` ↔ `skills/handoffx/scripts/` 字节相等；dev-only 清单；Gotcha #26；每个新 gate 做「中性化保留诊断」变异（#25）。
- 自迁移是对**真仓**的写操作：先在新鲜拷贝预演（0073 已做一次，plan 内再做一次带全部 P2.4 改动的终演）、三源审 CLEARED、**Boss 明文「执行」**后才对真仓 `--apply`；git 可回退（`git tag p2.4-pre-migrate`）。
- 自迁移之后本会话写 Dev Log 必须用**新 schema**：先三家重装 v4 的 skill（否则已装的 v3 skill 会写到 `Handoff_Logs/`）。重装装的必须真是 v4：`VERSION`/sidecar 在 T3 随文档一并提交为 v4.0.0，T5 迁移结果 commit 后再重装；T6 调 gitx 时工作树必须干净（gitx 从 HEAD 打包）。
- 计数守卫：套件数 38 → 37（退 2 加 1）；静态断言点机械重算；五份文档 + TEST-SCENARIOS 表跟随。

## 3. 已定的 How

### 3.1 常量翻转（单点）
`scripts/lib/handoff-schema.sh`（+ bundle 孪生）：`HX_LOGS_DIR="Handoffx_Logs"`、`HX_DEC_DIR="Handoffx_Decisions"`、`HX_MAIN_FILE="HANDOFFX.md"`；`HX_GOTCHAS_FILE` 不变。`tests/test_handoff_schema.sh` 的 baseline 断言同步到新名；其"脚本零散落字面量"guard 的扫描集合改为**新名**（旧名字面量只允许出现在 §3.2 的迁移器与 §3.6 的放行表所列文件）。

### 3.2 迁移器方向固定（`scripts/lib/handoffx-tidy-migrate.sh`）
现状：旧名 = `$HX_*`，新名 = `${HX_*/Handoff_/Handoffx_}`——常量一翻就新旧不分（0073 预演是在翻常量**之前**跑的才干净）。改为：旧名取 schema 库新增的 `HX_LEGACY_*` 常量（§4b-1；唯一允许持有旧四件套名的位置），新名 = `$HX_*`。`detect_schema_state`（MIXED/OLD-V2/ALREADY-HANDOFFX/UNKNOWN）、preflight、`.partial` staging、回滚、.md 文本 sweep 全部按此二元组；`test_handoffx_tidy.sh` 的夹具由"建旧名"改为"建 `$HX_LEGACY_*`"（夹具本就是旧布局，语义不变）。`migrate-to-v2.sh` 的 v1→v4 改动见 §4b-1。

### 3.3 测试码 schema-agnostic（T5 自指收敛）
`tests/common.sh` source `scripts/lib/handoff-schema.sh`（导出 `HX_*`）。20 个含四件套字面量的套件逐一改为 `$HX_MAIN_FILE` / `$HX_LOGS_DIR` / `$HX_DEC_DIR`（夹具建目录、路径断言、消息断言）。例外：(i) `test_handoffx_tidy.sh` / `test_migrate_to_v2.sh` 里**代表旧布局输入**的字面量改用 `$HX_LEGACY_*`；(ii) `tests/fixtures/` 下的 v1 样本与合成 v2 夹具目录（`p2-1-synthetic-v2/` 含 `Handoff_Logs/`）是**输入数据**，保留旧名、由迁移器测试消费；(iii) `test_release_artifact_content.sh` 的 forbidden 模式同时列旧名 `HANDOFF\.md` 与新名 `HANDOFFX\.md`（两者都永不进包）。`tests/lib/p2_2_rename_inventory.sh` 随守卫退役删除（§3.6）。

### 3.4 本仓自迁移（Boss 门控执行）
`git tag p2.4-pre-migrate` → `bash scripts/tidy-handoff.sh schema-upgrade --dry-run --root .` → Boss「执行」→ `--apply` → `git add -A`（rename 识别）→ 用**已重装的 v4 skill** 跑 `regenerate_pointers HANDOFFX.md` / `regenerate_decision_index .` / postflight / xref / validate → run_all 全绿。迁移器的 .md sweep 只改四件套内部引用与 GOTCHAS；产品文档由 §3.5 单独改。

### 3.5 文档 / 模板 / 配置 / 发布链
- 模板：`skills/handoffx/assets/HANDOFF.template.md` → `HANDOFFX.template.md`；`install.sh --template` 与 `handoffx-init.md` 引用改为由 `$HX_MAIN_FILE` 派生（`${HX_MAIN_FILE%.md}.template.md`）；`handoff-xref-lint.sh` 的 `*assets/*.template.md` 跳过规则不变。
- 文档 166 处：README×2、INSTALL、CONTRIBUTING、TEST-SCENARIOS、SKILL.md、5 个 references、4 个 command-shims、`.sanitize-ignore`（`Handoffx_Logs/*` 等）、`.gitignore` 注释 → 新名；`MIGRATION_GUIDE_v2.md` 保留为 v1→v2 历史但加一节「v3 → v4：`/handoffx-tidy schema-upgrade`」并把示例目录改新名；CHANGELOG `## [Unreleased] — v4.0.0`（事实陈述）。
- **发布链**：gitx 的 rsync 排除表硬编码旧四件套名，改名后 `HANDOFFX.md`/`Handoffx_*` 会进源码包。新增项目侧 `scripts/scrub-tarball.sh`（gitx 钩子契约：`<tar> <prefix> <ref>`；gitx 以 `[ -x ]` 选用，git mode 必须 100755 否则静默回落 rsync；`set -euo pipefail`，`git archive --worktree-attributes --prefix=<prefix>/ <ref> | gzip -n` 先写 `<tar>.tmp` 再 `mv`，无效 ref / 输出不可写 → 非零且无残留）+ `.gitattributes`（**根锚定**条目，最终集合见 §4b-2；`tools/`、`.sanitize-ignore`、`.github/workflows/` 都不排除——workflows 由公开脱敏删，源码包保留）。效果：进包 = git 跟踪且未 export-ignore 的文件，Gotcha #30 根治；`scripts/scrub-tarball.sh` 是根层 dev-only（`release-*`/`scrub-tarball.sh` 由 gitx 双源过滤放行；进 `DEV_ONLY`）。契约测试加一节：scrub 产物根为 `<prefix>/`、不含 export-ignore 文件、与 `git ls-files` 差集恰为 export-ignore 集。
- `Release/CHANGELOG.md`（本机）同步 v4.0.0 节 + `---`。

### 3.6 守卫：退役 P2.2 套件，立永久轻量守卫（Boss 委托我裁定）
- **删除**：`tests/test_p2_2_rename_manifest.sh`、`tests/test_p2_2_rename_bguard.sh`、`tests/lib/p2_2_rename_inventory.sh`、`tests/fixtures/p2_2_rename_{manifest,exceptions,refactored,relocations}.txt`。Why：它证明的是 2026-10-30 那次注册名改名已落地（occurrence 级正向 + ratchet），该改名已随 v3.0.x 发出；翻常量后它报 810 处（四件套 token 从 LEAVE 变成需重分类），再适配 = 重做 P2.2a Task 0；而 P2.4 自己的"落地证明"由迁移器（原子、有测）+ 改完夹具的 run_all + 新守卫给出。代价：失去"该改的行被删了而不是改了"这一类检测——低风险，Decision 记录。
- **新增** `tests/test_legacy_names_guard.sh`（永久）：对 `git ls-files` 的文本文件 grep **旧注册名形态**（`/handoff\b`、`skills/handoff/`、`handoff-(recall|tidy|memory|init|write)\.md`、`\$handoff\b`、`^name: handoff$`、`\.(claude|agents|codex)/skills/handoff\b`、`opencode/skills/handoff\b`）与**旧四件套名**（`\bHANDOFF\.md\b`、`\bHandoff_Logs\b`、`\bHandoff_Decisions\b`），任一命中且不在放行表 → ❌。放行表 `tests/fixtures/legacy-names-allow.txt`（根锚定路径 glob + 一行理由，受审、不可空、不可读/畸形 → ❌；处理文件数为 0 → ❌）。**审定后的完整表以 plan 的「放行表」节为准**：在上面列过的基础上加 schema 库及其 bundle 孪生（`HX_LEGACY_*` 唯一持旧名处）、`tests/test_handoff_schema.sh`（断言常量值）、SKILL.md / 四个 shim / init 与 tidy references（「有 `HANDOFF.md` 而无 `HANDOFFX.md` → 先 schema-upgrade」指引必然写旧名）；**两个迁移器不在表内**——它们只用 `$HX_LEGACY_*`，不得出现字面量。负控：临时在 README 植入 `Handoff_Logs/` → 红（变异证明）。

### 3.7 v4.0.0 真切与收口
VERSION/sidecar/徽章/横幅/SOP 示例 → v4.0.0；两份 CHANGELOG；gitx dry-run → 真切（scrub 路径首次启用：核 tarball 不含 export-ignore 文件、含 CHANGELOG）；`test_release_artifact_content` 实跑；三家重装 v4（`--journal-only` → 真装）；`opencode debug skill` 7 项；Linux 容器 `tests/linux-container.sh`；Dev Log（**用新 schema 写进 `Handoffx_Logs/`**）；Decision 0032（守卫退役）+ 0025/0020 Outcome 回填；tag/push 留 Boss。

## 4. 留给 builder 的
- `tests/common.sh` source 常量的位置与 `set -u` 交互；套件里哪些字面量是"消息文案断言"而非路径（逐条判断，消息若由脚本用常量拼出则断言也用常量）。
- `.gitattributes` 是否对 `Release/`（已 gitignored）无影响（是）；`git archive --worktree-attributes` 在 bash 3.2 下调用形态。
- 守卫放行表的匹配实现（`case` glob 或 `grep -f`），要求每行带理由且空表 = ❌。
- 退役 P2.2 守卫后 `tests/run_all.sh` 自动少两个套件；TEST-SCENARIOS 两行删除、新行加入。

## 4b. builder check 的回答（独立 builder 读稿后 6 问，以下为裁定；与 §3 冲突处以本节为准）
1. **旧名常量进 schema 库**：`scripts/lib/handoff-schema.sh` 新增 `HX_LEGACY_MAIN_FILE="HANDOFF.md"`、`HX_LEGACY_LOGS_DIR="Handoff_Logs"`、`HX_LEGACY_DEC_DIR="Handoff_Decisions"`（有注释：唯一允许持有旧四件套名的位置；`test_handoff_schema` 的零散落 guard 对新名与旧名都扫，白名单 = 这一个文件）。`handoffx-tidy-migrate.sh` 与 `migrate-to-v2.sh` 都从它取旧名、从 `HX_*` 取新名。**`migrate-to-v2.sh`（v1 单文件 → 四件套）改为：输入 `HANDOFF.md`（+ `HANDOFF.archive.md`）用旧名，输出 `HANDOFFX.md` + `Handoffx_*` 用新名**——v1 用户一步到 v4，多一次主文件改名；备份文件名保持 `HANDOFF.md.pre-v2-backup`（历史语义）；trap/回滚把新主文件的 `.new` 与改名纳入；`test_migrate_to_v2.sh` 断言按此重写（这是实质改动，不是补文档）。`tidy-handoff.sh` 默认文件 = `$HX_MAIN_FILE`；缺失但 `$HX_LEGACY_MAIN_FILE` 存在 → 按内容判 v1（单文件 inline Dev Log → 提示 `migrate-to-v2`/`--apply`）或 v3（旧四件套 → 提示 `schema-upgrade`），exit 2 不静默。
2. **`.sanitize-ignore` 随包发出**（gitx 的 staging 脱敏读 tarball 内那份白名单），从 export-ignore 集里去掉；`.gitattributes` 只列**根锚定**的 `/HANDOFFX.md`、`/Handoffx_Logs/`、`/Handoffx_Decisions/`、`/GOTCHAS.md`、`/CLAUDE.md`、`/memory/`、`/graphify-out/`（不加前导 `/` 会把 `tests/fixtures/p2-1-synthetic-v2/{HANDOFF.md,GOTCHAS.md}` 也排掉，合成夹具的测试在源码包里直接红）；产物断言同理只禁**根级**四件套，并显式断言合成夹具在包内。
3. **根 `release.sh`**：`stage_source` 排除表、`audit_staged_source` 与 `emit_release_manifest` 的禁止路径改为由 `$HX_*` 与 `$HX_LEGACY_*` 派生（新旧四件套都排除、都禁止），保留 rsync；不改走 scrub（sandbox 要能对工作树打包）。契约测试加「sandbox tarball 不含新旧四件套」断言。
4. **v4 遇 v3 布局的防呆**（在范围内，数据安全）：`tidy-handoff.sh`（见 1）、`validate-handoff.sh --readiness` 与 `handoff-postflight.sh` 在 `$HX_MAIN_FILE` 缺失且旧主文件存在时打印「检测到旧四件套布局，请先 `/handoffx-tidy schema-upgrade`」exit 2；`install.sh` 的 `warn_if_v1_layout` 扩成 `warn_if_legacy_layout`（v1 单文件 / v3 旧四件套两种提示；普通安装**警告后继续**、rc 0——S:60 契约，不 exit 2；`--template <dir>` 对**解析后的目标目录**（不是 PWD）做同样检测，命中则拒绝且零写入）；`migrate-to-v2.sh` 的回滚测试要在 **preflight 之后**注入失败（新主文件生成失败、终段改名失败）而不只是复用 B7-b 的 preflight 拒绝先例，且新主文件的改名登记进 `FINALIZED_PATHS`；SKILL.md「若项目根没有主文件 → init」改为**内容分流**：「有 `HANDOFF.md` 而无 `HANDOFFX.md` → 先跑 `/handoffx-tidy`，它按内容判 v1（单文件 inline Dev Log → `migrate-to-v2.sh`）/ v3（旧四件套 → `schema-upgrade`）并给出命令；都没有 → init；新旧并存 → 拒绝并点名冲突」（不能笼统写「→ schema-upgrade」：v1 单文件会被 `schema-upgrade` 以缺 v2 marker/目录拒绝），四个 shim 同步。各有测试，且两条分流各断言具体命令名。
5. **`test_handoffx_tidy.sh` 的真仓 dogfood 块**：从活仓新布局**反向改名**合成旧布局到临时目录再喂迁移器（保留实尺度回归；迁移器仍是所有 v3 用户的升级路径）。
6. **`tools/` 不 export-ignore**（ADR-0003 ⑦ 只排除 `.skill`）；§5 退出条件相应改为「tarball 不含四件套与 `CLAUDE.md`」。**分发契约**（Codex 第 2 轮 #4）：完整套件验证要求 git 检出——旧名守卫用 `git ls-files`、scrub 契约段用 `git archive HEAD`、dogfood 用活仓语料；解压的源码包里这两处以 ➖ 明示原因跳过（结构性前提「不是 git 工作树」，非 #12 的 skip-when-X 退化），dogfood 回退到合成 v2 夹具；CONTRIBUTING 写明，T4 在 git 树外解压一次验证。
- 回滚注入（Codex 第 2 轮 H5）：预建 `.new` 会被 preflight 当残留拒绝、`mv 文件 已存在目录` 会移进目录而非失败——改用测试专用 `HANDOFFX_MIGRATE_FAIL_AT=<new-main|final-mv|retire-legacy>`（`install.sh` 的 `HANDOFFX_INSTALL_FAIL_AT` 同范式）；v1→v4 成功态契约：旧主文件退役（最后一步）、备份保留且字节相等、detect 为 ALREADY。`install.sh --template` 的拒绝在 `txn_begin` 之前（否则 skill 已装完才拒绝，「零写入」不成立）。
- 备注采纳：守卫的 `/handoff` 形态收窄为 `(^|[^A-Za-z0-9_./-])/handoff(-recall|-tidy|-memory|-init)?([^A-Za-z0-9_-]|$)`（不命中 `scripts/handoff-lint.sh` 等 L1 基名）；`skills/handoffx/evals/files/sample-HANDOFF.md` → `sample-HANDOFFX.md` 并改 `evals.json`；迁移器 `:165` 报错文案中的新名字面改为常量派生。

## 5. 退出
run_all 37 套件 0 失败 0 跳过（macOS + 容器非 root）；`HANDOFFX.md` 为主文件且 postflight/xref/validate 全绿；新守卫绿且负控红；`Release/latest → handoffx-v4.0.0`、tarball 不含四件套与 `CLAUDE.md`（含 `tools/`、`.sanitize-ignore`，见 §4b）；三家 skill v4；Dev Log 写在 `Handoffx_Logs/`；→ 等 Boss tag/push、「P2 收口」。
