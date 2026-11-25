# P2.4 — 终阶自迁移：实现计划（2026-10-31，v4：Codex 三轮共 27 条已吸收；第 3 轮 6.8 未过线，Boss 裁定中——见 Dev Log）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 工具默认产出 `HANDOFFX.md` / `Handoffx_Logs/` / `Handoffx_Decisions/`（`GOTCHAS.md` 不动），两个迁移器能把 v1 / v3 布局升到 v4，本仓自迁移，P2.2 守卫退役换永久旧名守卫，真切 v4.0.0。

**Architecture:** 单一 schema 源 `scripts/lib/handoff-schema.sh` 翻四常量并新增 `HX_LEGACY_*`（唯一持旧名处）；脚本已 schema-agnostic（P2.0），本阶段把测试码也变成读常量；迁移器旧名取 `HX_LEGACY_*`、新名取 `HX_*`；发布链加项目侧 `scripts/scrub-tarball.sh` + 根锚定的 `.gitattributes`。顺序：T0 翻常量（run_all 进入**有账本的红**）→ T1 迁移器与防呆 → T2 测试码 → T3 文档/模板/发布链 + **版本号 v4.0.0 一并提交** → T4 守卫换代 + 克隆终演（迁移后 commit 再测）+ 三源审 → **T5 Boss 门控真仓迁移（commit 后再测）+ 三家重装 v4.0.0** → T6 CHANGELOG 定稿 + 真切。

**Tech Stack:** bash 3.2 / mawk；git archive；gitx-release v1.13.0 scrub 钩子（`[ -x scripts/scrub-tarball.sh ]` 才选用）。

**Spec:** `docs/2026-10-31-p2-4-self-migration-design.md`（§4b 优先）；Decision 0032。

## Global Constraints
- 常量：`HX_MAIN_FILE="HANDOFFX.md"` `HX_LOGS_DIR="Handoffx_Logs"` `HX_DEC_DIR="Handoffx_Decisions"` `HX_GOTCHAS_FILE="GOTCHAS.md"`；`HX_LEGACY_MAIN_FILE="HANDOFF.md"` `HX_LEGACY_LOGS_DIR="Handoff_Logs"` `HX_LEGACY_DEC_DIR="Handoff_Decisions"`。**脚本字面量守卫**（`test_handoff_schema`）：`scripts/**/*.sh` 除 `scripts/lib/handoff-schema.sh` 外不得出现 `Handoffx_Logs|Handoffx_Decisions|HANDOFFX\.md|HANDOFFX\.archive\.md|Handoff_Logs|Handoff_Decisions|HANDOFF\.md|HANDOFF\.archive\.md|GOTCHAS\.md`（注释也算——T0 顺手清掉 `handoffx-tidy-migrate.sh:39,82` 等现存命中）。
- 测试码只用 `$HX_*` / `$HX_LEGACY_*`；例外：`tests/fixtures/` 输入数据；`tests/test_handoff_schema.sh` 对常量**值**的断言。
- **预期红账本**：T0 跑完 run_all 后把每条 ❌ 的「套件 + 断言名 + 归因（迁移前依赖活仓旧布局 / 计数漂移 / 模板改名 / 守卫退役）」写入 `/tmp/p24-red-ledger.md`；此后每任务对照账本：账本之外的任何 ❌ 阻塞，账本内的随任务收敛必须**从账本划掉**（T2 末、T3 末各复核一次）。**账本扩展规则**：某任务新建的门禁若在 T5 之前对活仓必然红（如 T4 的旧名守卫、T3 翻版本号后的 artifact 在途 ➖），由**该任务**在账本追加「预登记」行，注明激活任务与到期任务（T5 / T6），并由该任务的审查者确认；到期未转绿 → 阻塞。
- **分发契约**：完整套件验证要求 **git 检出**（旧名守卫用 `git ls-files`、scrub 契约段用 `git archive HEAD`）；在解压的源码包里（无 `.git`），这两处以 `➖ SKIPPED（原因：不是 git 工作树）` 明示跳过并 exit 0，`run_all` 汇总行必须列出 ➖ 数；dogfood 块在活仓两种布局皆缺时回退到 `tests/fixtures/p2-1-synthetic-v2/` 作语料（仍是真迁移，只是尺度小）。T4 在 git 树外解压一次 scrub 产物跑 run_all 核：0 ❌，➖ 恰为上述几处。CONTRIBUTING 写明此契约。
- 双源字节相等；dev-only 清单；Gotcha #26；每个新 gate 做「中性化保留诊断」变异（#25）。
- **HEAD 一致性**：任何基于 `git archive HEAD` / `git ls-files` 的测试在跑之前先 commit 候选；克隆终演与 T5 真仓迁移都是 `--apply` → `git add -A && git commit` → 再跑 run_all；T4 三源审的修复先 commit 再重演。
- **真仓迁移（T5）之前**：T4 克隆终演 37 套件 0 失败（允许恰 1 个 ➖ = artifact 门禁在途态）；三源审 CLEARED；`git tag p2.4-pre-migrate`；**Boss 明文「执行」**。T5 之后先三家重装（此时 VERSION 已是 v4.0.0，T3 提交）再写 Dev Log。
- 每任务 checkpoint commit；不 push、不打发布标签。
- 计数：套件 38 → 37（删 `test_p2_2_rename_manifest.sh`、`test_p2_2_rename_bguard.sh`，加 `test_legacy_names_guard.sh`）；静态断言点机械重算；五份文档 + TEST-SCENARIOS。数量（Dev Log/Decision 条数等）一律**机械派生**（`ls | wc -l`），不写死。

## Review Focus
1. 迁移器三态（OLD-V2 / ALREADY / MIXED）在翻常量后正确 → T1 三条断言 + MIXED 中性化变异；v1→v4 成功态 = 旧主文件已退役、detect 为 ALREADY。
2. `migrate-to-v2.sh` v1→v4 的回滚在 **preflight 之后**失败时保原状 → T1 用测试专用 `HANDOFFX_MIGRATE_FAIL_AT` 三个注入点（`new-main` / `final-mv` / `retire-legacy`），根 immune；**输出不再与输入同名，`$HX_MAIN_FILE` 必须进 preflight 占用检查并在终段 mv 前复查**（已有普通文件 / 目录 / 符号链接 → 非零、既有目标与旧输入原样保留、不留备份），`FINALIZED_PATHS` 只登记本次创建的目标。
3. v4 遇 v3 布局：tidy/validate/postflight **exit 2** 且按内容给对应命令（v1 → migrate-to-v2，v3 → schema-upgrade，混合 → 拒绝并点名）；install 普通安装**警告继续**（S:60 契约）、`--template` 在 `txn_begin` 之前拒绝且全局零写入 → T1。
4. scrub：`-x` 模式位、`set -euo pipefail` + **显式失败分支**（`if ! git archive … | gzip -n > tmp; then rm -f tmp; exit 1; fi; mv tmp out`——`&&` 链里 errexit 不触发、清理成功会把退出码洗成 0）、无效 ref 非零且无残留；根锚定 export-ignore 不伤 `tests/fixtures/p2-1-synthetic-v2/`；切后 tarball `CHANGELOG.md` == `Release/CHANGELOG.md` → T3/T6。
5. 旧名守卫：放行表（下）之外零命中；`scripts/handoff-lint.sh` 类基名不红；放行表空/畸形/不可读 → ❌；处理文件数 > 0；**逐文件读错契约**（枚举失败 / 不可读的跟踪文件 / grep rc 2 ≠ 无匹配，一律 ❌，GOTCHAS #334-338 同范式）→ T4。

## 放行表 `tests/fixtures/legacy-names-allow.txt`（已审定；格式 `glob<TAB>reason`，根锚定 glob）
```
Handoffx_Logs/*	历史日志按设计保留旧名引用
Handoffx_Decisions/*	历史决策
GOTCHAS.md	知识库历史
CHANGELOG.md	版本史
docs/*	历史计划/设计/评估
tests/fixtures/*	输入数据（v1 样本、合成 v2、守卫基线）
MIGRATION_GUIDE_v2.md	v1→v2 历史 + v3→v4 指引
scripts/lib/handoff-schema.sh	HX_LEGACY_* 常量（唯一持旧名处）
skills/handoffx/scripts/lib/handoff-schema.sh	双源孪生
tests/test_handoff_schema.sh	断言常量值
skills/handoffx/SKILL.md	「有 HANDOFF.md 而无 HANDOFFX.md → 先跑 /handoffx-tidy 按内容分流」指引
skills/handoffx/command-shims/*.md	同上指引
skills/handoffx/references/handoffx-init.md	同上
skills/handoffx/references/handoffx-tidy.md	同上
scripts/release-layout.sh	旧产物前缀（P2.2b）
tests/test_release_layout_contract.sh	同上
install.sh	OLD_* 清扫操作数 + 旧布局提示
tests/test_install.sh	种旧残留
tests/test_handoffx_tidy.sh	消息断言含旧名
tests/test_migrate_to_v2.sh	v1 夹具
```
（两个迁移器**不在表内**：它们只用 `$HX_LEGACY_*`，不得出现字面量。）

---

### Task 0: 翻常量 + 旧名常量 + 测试基座 + 预期红账本 — **完成（8e2bb5d）**
**Files:** `scripts/lib/handoff-schema.sh`（+ bundle）、`tests/common.sh`、`tests/test_handoff_schema.sh`、`tests/fixtures/p2_fourpiece_stray_baseline.txt`（头注释）、`scripts/lib/handoffx-tidy-migrate.sh:39,82`（+ bundle）
- [x] **Step 1: RED** 四条 baseline 断言改新值 + 三条 `HX_LEGACY_*` 断言；`gen_stray` 九项；三处翻转预演改第三名（`Handoffz_*` / `HANDOFFZ.md`，只 sed 新常量）；注释含旧名的现状红。
- [x] **Step 2: 实现**；`tests/common.sh` 在 `SCRIPTS_DIR` 之后 source schema 库。
- [x] **Step 3: GREEN + 账本** `/tmp/p24-red-ledger.md`（16 套件 / 220 行：fixture-literal 154、doc-count 28、other 26 = 迁移器派生、live-repo-old-layout 10、guard-retire 2）。
- [x] **Step 4: Commit**

### Task 1: 迁移器方向固定 + v1→v4 + 旧布局防呆
**Files:** `scripts/lib/handoffx-tidy-migrate.sh`、`scripts/migrate-to-v2.sh`、`scripts/tidy-handoff.sh`、`scripts/validate-handoff.sh`、`scripts/handoff-postflight.sh`、`install.sh`（各 + bundle）；`tests/test_handoffx_tidy.sh`、`tests/test_migrate_to_v2.sh`、`tests/test_tidy_handoff.sh`、`tests/test_validate_handoff.sh`、`tests/test_handoff_postflight.sh`、`tests/test_install.sh`
**Produces:** `detect_schema_state` 旧=`$HX_LEGACY_*` 新=`$HX_*`；`migrate-to-v2.sh`：输入 `$HX_LEGACY_MAIN_FILE`（+ `${HX_LEGACY_MAIN_FILE%.md}.archive.md`），输出 `$HX_MAIN_FILE` + `$HX_LOGS_DIR` + `$HX_DEC_DIR`，备份 `${HX_LEGACY_MAIN_FILE}.pre-v2-backup`（成功保留、回滚删除），新主文件 `.new` → 终段 `mv` 到新名并登记 `FINALIZED_PATHS` → **退役旧主文件**（最后一步，紧接 `MIGRATE_DONE=1`）；**成功态契约**：旧主文件不存在、备份与输入字节相等、四件套齐、`detect_schema_state` = `ALREADY-HANDOFFX`（绝不 MIXED）；EXIT-trap 在旧主文件缺失**或**不同时都从备份还原；**占用检查**：`$ROOT/$HX_MAIN_FILE` 进 preflight 的目标占用列表（备份与装 trap 之前）并在终段 `mv` 前以 `assert_dest_clear` 复查，`FINALIZED_PATHS` 只登记本次创建的目标；测试专用 `HANDOFFX_MIGRATE_FAIL_AT=<new-main|final-mv|retire-legacy>`（同 `install.sh` `HANDOFFX_INSTALL_FAIL_AT` 范式）；`tidy-handoff.sh` 默认文件缺失且旧主文件存在 → 按内容分流：v1（inline `### YYYY-MM-DD`）提示 `migrate-to-v2.sh --dry-run/--apply`，v3（旧四件套齐）提示 `schema-upgrade`，混合（新旧并存）拒绝并点名两者，exit 2；`validate-handoff.sh --readiness` 与 `handoff-postflight.sh` 同条件 ❌ exit 2；`install.sh` source 根旁 `scripts/lib/handoff-schema.sh`（缺则 ❌ exit 1）；`warn_if_legacy_layout`（v1 / v3，**警告继续** rc 0，S:60）；`--template <dir>`：在参数校验阶段、**`txn_begin` 之前**，解析后的目标含 `$HX_LEGACY_MAIN_FILE` 或旧目录 → ❌ exit 1、全局零写入（目标与三家安装根都不变）、提示 schema-upgrade；正常 `--template` 的**目标文件名**在本任务改为 `$HX_MAIN_FILE`（模板资产 `HANDOFF.template.md` 的改名与派生留 T3），`test_install` C9 随之常量化并在本任务转绿。
- [ ] **Step 1: RED** 夹具改常量；三态断言（MIXED = 同时有 `$HX_LEGACY_LOGS_DIR` 与 `$HX_LOGS_DIR`）；v1→v4 正向 + 成功态契约四断言；三注入点各一组断言（非零；旧主文件与夹具字节相同；无 `$HX_MAIN_FILE`/`.new`/`.partial`/新目录；备份已删）——`retire-legacy` 证明新主文件的 `FINALIZED_PATHS` 登记真被用到；**占用负控**：直接调用迁移器时 `$HX_MAIN_FILE` 已是普通文件 / 目录 / 符号链接 → 非零、既有目标字节与类型不变、旧输入不变、无备份残留；防呆：tidy/validate/postflight v1 与 v3 各断言**具体命令名**，混合树拒绝；install 普通安装警告且 rc 0；`--template` 对含旧布局目标（PWD ≠ 目标）exit 1、目标与安装根 `ls -la` 前后一致；dogfood 块按存在性三选一：活仓仍旧名 → 直接拷；活仓已新名 → 反向改名**并反向改写内容**到临时快照（helper 函数，今天就用微型合成新布局树单测：快照里存在旧引用、与四件套无关的哨兵文件未改）；两者皆缺 → 合成夹具。跑六套件 → 红。
- [ ] **Step 2: 实现**；报错文案常量派生。
- [ ] **Step 3: GREEN** 六套件 ✅；`test_handoff_schema` / `test_scripts_sync` / shellcheck ✅；变异：MIXED 判定中性化 → 红；回滚 `rm -rf` 去掉 → `final-mv` 与 `retire-legacy` 注入红；`.md` 内容 sweep 中性化 → dogfood 残留断言红。账本复核：这六套件的条目划掉。
- [ ] **Step 4: Commit**

### Task 2: 其余测试码 schema-agnostic + 发布链字面量
**Files:** `tests/test_handoff_lint.sh`、`test_handoff_xref_lint.sh`、`test_handoff_v2_schema.sh`、`test_scan_credentials.sh`、`test_archive_devlog.sh`、`test_handoff_postflight_parallel.sh`、`test_doc_freshness.sh`、`test_handoff_recall_v2.sh`、`test_doc_freshness_bguard.sh`、`test_rotation_reminder.sh`、`test_release_artifact_content.sh`、`test_project_tree_forbidden.sh`、`test_release_layout_contract.sh`；`release.sh:77-125,165-175`；`skills/handoffx/evals/files/sample-HANDOFF.md` → `sample-HANDOFFX.md` + `evals.json`；`.sanitize-ignore`、`.gitignore` 注释
- [ ] **Step 1** 逐套件常量化；`test_release_artifact_content`：先剥掉唯一发布前缀，再只禁**根级** `HANDOFF\.md|HANDOFFX\.md|HANDOFF\.archive\.md|HANDOFFX\.archive\.md|Handoff_Logs/|Handoffx_Logs/|Handoff_Decisions/|Handoffx_Decisions/|GOTCHAS\.md|CLAUDE\.md`（`^<prefix>/…`）——**「合成夹具在包内」的正向断言不在这里加**（现行 `latest`=v3.0.1 是 gitx rsync 产物、未锚定排除把夹具也排了，会制造账本外新红），放到 T3 与版本号翻转同 commit；`release.sh` 排除表/禁止路径由两套常量派生且根锚定；契约测试 sandbox 加根级断言 + **夹具保留断言**（sandbox 产物由本仓 release.sh 生成，可立即核）；evals 改名；`test_doc_freshness_bguard.sh` 的 `_mk_fx`（:12-13 从活仓拷主文件、`2>/dev/null` 吞掉失败）改为**自包含**：活仓主文件存在则拷，否则从测试内生成带 v2 marker / Current State / `### 最近完成` 结构与计数行的最小主文件；两条路径都断言拷贝/生成成功且注入真的改了文件（不再 `2>/dev/null`）——否则源码包里负控套件静默失效（分发契约）。
- [ ] **Step 2: GREEN** 各套件 ✅；run_all 对照账本：剩余红只能是「活仓旧布局依赖」「计数」「模板改名」「守卫退役」四类且每条在账本内。
- [ ] **Step 3: Commit**

### Task 3: 文档 / 模板 / shims / scrub / 版本号 v4.0.0
**Files:** `git mv skills/handoffx/assets/HANDOFF.template.md HANDOFFX.template.md`；`install.sh` 模板名派生、`command-shims/handoffx-init.md`、`references/handoffx-init.md`；文档 166 处（README×2、INSTALL、CONTRIBUTING、TEST-SCENARIOS、SKILL.md、references、shims）；`MIGRATION_GUIDE_v2.md` 加「v3 → v4」节；`CHANGELOG.md` 新节 **`## v4.0.0 — 2026-10-31`**（标题必须是门禁可识别的 `## v<VERSION> ` 形态——`test_doc_freshness` Test21 用 `awk '/^## v4.0.0 /,/^---$/'` 切段，`[Unreleased]` 会切出空段而红；段内首行注明「未发布，T6 真切时定稿」，以 `---` 收尾；T6 只更新日期/内容）；Create `.gitattributes`、`scripts/scrub-tarball.sh`（**git mode 100755**）；Modify `tests/test_scripts_sync.sh`、`tests/test_release_layout_contract.sh`、`tests/test_release_artifact_content.sh`（夹具在包内断言）；`VERSION`、`skills/handoffx/VERSION` → v4.0.0 + README 徽章与 :177、INSTALL 横幅与 `VER=`、SOP 示例、主文件版本行
- [ ] **Step 1: RED** 契约 scrub 段：(a) `[ -x scripts/scrub-tarball.sh ]`；(b) 先 `git commit` 候选（本任务流程：改完 → commit → 跑 scrub 测试 → 红则改、再 commit）；`bash scripts/scrub-tarball.sh <tmp>/x.tar.gz handoffx-v9.9.9 HEAD` → 根 `handoffx-v9.9.9/`；`tar tzf` 常规文件集合 == `git ls-tree -r --name-only HEAD` 减去 export-ignore 根锚定路径；含 `.sanitize-ignore`、`tools/review-loop.sh`、`tests/fixtures/p2-1-synthetic-v2/GOTCHAS.md`；不含根级 `HANDOFFX.md`、`Handoffx_Logs/`、`CLAUDE.md`；两次产出 `cmp` 相同；(c) 无效 ref → 非零且输出文件与 `.tmp` 都不存在；输出目录不可写 → 非零；**(d) 失败分支变异**：把 `if ! …; then rm -f tmp; exit 1; fi` 改回 `… && mv` 形态 → (c) 红。不是 git 工作树（在 mktemp 里拷一份无 `.git` 的树跑）→ scrub 段 ➖ 且 exit 0。跑 → 红。
- [ ] **Step 2: 实现** `.gitattributes`（根锚定 7 条）；`scripts/scrub-tarball.sh`：`set -euo pipefail`，三参校验，显式失败分支（见 Review Focus 4）；`chmod +x` 并确认 `git ls-files -s` 为 100755；DEV_ONLY += `scrub-tarball.sh`；文档改写——SKILL.md / 四 shim / init 与 tidy references 的指引改为**内容分流**：「根下有 `HANDOFF.md` 而无 `HANDOFFX.md` → 先跑 `/handoffx-tidy`，它按内容判 v1（→ `migrate-to-v2.sh`）/ v3（→ `schema-upgrade`）给命令；都没有 → `/handoffx-init`；新旧并存 → 先处理冲突」；CONTRIBUTING 加「分发契约」段；版本号 v4.0.0；`test_release_artifact_content` 加「合成夹具在包内」断言（此时 VERSION ≠ latest → 门禁 ➖，T6 切后实跑）并在账本**预登记**该 ➖（到期 T6）。
- [ ] **Step 3: GREEN** 契约 ✅；`test_scripts_sync` ✅；`test_doc_freshness` 可能因计数红（T4 收）；账本复核：模板改名类划掉。
- [ ] **Step 4: Commit**

### Task 4: 守卫换代 + 计数 + 克隆终演 + 三源审
**Files:** Delete 7 个：`tests/test_p2_2_rename_manifest.sh`、`tests/test_p2_2_rename_bguard.sh`、`tests/lib/p2_2_rename_inventory.sh`、`tests/fixtures/p2_2_rename_{manifest,exceptions,refactored,relocations}.txt`；Create `tests/test_legacy_names_guard.sh`、`tests/fixtures/legacy-names-allow.txt`（上表）；五份计数文档 + TEST-SCENARIOS；CONTRIBUTING（若 T3 未写分发契约）
- [ ] **Step 1: RED** 守卫：`git ls-files -z`（rc 非零 → ❌）→ 每个跟踪常规文件 `[ -r ]` 否则 ❌（缺失/不可读都算）→ `grep -Il` 判文本 → grep 旧注册名（`(^|[^A-Za-z0-9_./-])/handoff(-recall|-tidy|-memory|-init)?([^A-Za-z0-9_-]|$)`、`skills/handoff/`、`handoff-(recall|tidy|memory|init|write)\.md`、`\$handoff\b`、`^name: handoff$`、`\.(claude|agents|codex)/skills/handoff\b`、`opencode/skills/handoff\b`）与旧四件套名 `\bHANDOFF\.md\b|\bHandoff_Logs\b|\bHandoff_Decisions\b`，grep rc 2 → ❌（区别于 rc 1 无匹配）；放行表根锚定 glob、每行须有理由、空/畸形/不可读 → ❌；处理文件数 0 → ❌；命中且不在表 → ❌ 列 file:line；verdict 行；不是 git 工作树 → ➖ exit 0。正负控**在干净的迁移后夹具上**（克隆终演产物）：README 植入 `Handoff_Logs/` → 红；`scripts/handoff-lint.sh` 不红；**非 root 下 chmod 000 一个跟踪文件且其余可读 → verdict ❌**（root 下 ➖，#15 范式）；变异：中性化判决保留诊断 → 红。活仓（T5 前）该守卫红 → 由本任务在账本**预登记**（到期 T5）。
- [ ] **Step 2: 退役 + 计数** 删 7 文件；TEST-SCENARIOS 删两行加一行；37 套件；静态断言点重算；**`tests/run_all.sh` 加 ➖ 汇总**（现只计失败套件；改为同时统计各套件输出中的 `➖` 行数并在汇总行打印 `skipped: N`，0 失败且 N>0 仍 exit 0——分发契约与 M11 的「恰 1 个 ➖」靠它机械核）；commit（**T4 候选 commit**）。
- [ ] **Step 3: 克隆终演** `R=$(mktemp -d)`（每次重演都新开，记录路径与候选 commit）；`git clone --local . "$R/clone"`；`mkdir -p "$R/clone/Release" && cp -R Release/handoffx-v3.0.1 "$R/clone/Release/" && ln -s handoffx-v3.0.1 "$R/clone/Release/latest"`；在克隆：`schema-upgrade --dry-run` → `--apply` → `git add -A && git commit -m rehearsal` → `bash tests/run_all.sh` → **37 套件 0 失败，➖ 恰 1（artifact 在途）**；守卫绿；`bash scripts/scrub-tarball.sh` 出包核内容；**git 树外**解压该包到 `$R/pkg` 跑 run_all → 0 ❌、➖ 恰为「artifact 在途 + 守卫 + scrub 段」；机械比对迁移前后编号文件清单（`ls Handoff_Logs/[0-9]*.md | wc -l` == `Handoffx_Logs/`）。
- [ ] **Step 4: 三源审**：opus 全分支（`p2.4-start`…HEAD + 克隆日志）、silent-failure-hunter、Codex `[CODE REVIEW REQUEST]`；修 → **commit** → 限域复审 → **重做 Step 3 终演（新 mktemp）**。
- [ ] **Step 5: Commit**

### Task 5: 真仓自迁移（**Boss 门控**）
- [ ] **Step 1** `git status` 干净；`git tag p2.4-pre-migrate`；`schema-upgrade --dry-run --root .` 输出贴给 Boss；**停下等 Boss「执行」**。
- [ ] **Step 2** `--apply --root .` → `git add -A` → 机械比对编号文件清单 → **`git commit`（迁移本体）** → 三家重装（`./install.sh --journal-only` → `./install.sh`；三根 `VERSION` = v4.0.0、`handoff-schema.sh` 常量为新名）→ 用已装 skill：`regenerate_pointers HANDOFFX.md`、`regenerate_decision_index .`、postflight、xref → `bash tests/run_all.sh` **37 套件 0 失败、➖ 恰 1（artifact 在途）**；守卫绿（账本预登记到期划掉）。
- [ ] **Step 3: Commit**（指针/索引再生的增量）

### Task 6: v4.0.0 真切 + 收口
- [ ] **Step 1** `CHANGELOG.md` `## v4.0.0 — <date>` 段去掉「未发布」注记、定稿内容、`---` 收尾；`Release/CHANGELOG.md` 同节；commit；`git status` 干净。
- [ ] **Step 2** gitx dry-run → 真切（scrub 路径首次：`tar tzf` 不含根级四件套/`CLAUDE.md`、含 `CHANGELOG.md` 且与 `Release/CHANGELOG.md` 字节一致、含 `.sanitize-ignore` 与合成夹具）→ `latest → handoffx-v4.0.0`；`test_release_artifact_content` 实跑全绿（账本预登记到期划掉）；run_all **0 ➖**；`bash tests/linux-container.sh` 非 root 37/0/0；`opencode debug skill` 7 项。
- [ ] **Step 3** Dev Log（`Handoffx_Logs/`）、Decision 0032 Outcome、0025/0020 Outcome（P2 收口）、`HANDOFFX.md` Current State；commit。**tag/push 留 Boss。**
