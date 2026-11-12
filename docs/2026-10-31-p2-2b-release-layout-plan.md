# P2.2b — 发布链 canonical 布局 + 真切 v3.0.0：实现计划（2026-10-31，v3.2：Codex 三轮共 11 + 6 + 4 条已吸收）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本仓发布链全部按 `handoffx-<ver>` 命名、旧版本按版本门限仍可读、布局契约无 gitx 也能测且不跳过，然后用 gitx-release 真切 `Release/handoffx-v3.0.0/` 并翻 `latest`。

**Architecture:** 一个 dev-only 库 `scripts/release-layout.sh`（根层 `release-*`，gitx 双源闸放行）单点定义「前缀由版本决定」+ 目录/资产名 + 完整性校验；根 `release.sh`、publisher、backfill、契约测试四个消费者改调它。根 `release.sh` 加 `--sandbox` 只为契约测试造同形产物；真发布由外部 gitx-release 完成（`PROJECT_NAME` 由根目录名 `Handoffx` 自动探测）。前置：把 gitx 本就拒绝的开发工具 `review-loop.sh`/`review-ledger.sh` 挪出 `scripts/`。

**Tech Stack:** bash 3.2 / mawk-POSIX；zip/unzip/tar/(sha256sum‖shasum)；gitx-release v1.13.0。

**Spec:** `docs/2026-10-31-p2-2b-release-layout-design.md`（§3.0 前置、§3 How、§4b builder 裁定）。

## Global Constraints

- 版本格式 `vX.Y.Z`，校验用 `[[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]`（bash 3.2 支持，模式不加引号）；`RENAME_FROM` 默认 `v3.0.0`，两个操作数都校验，非法 → return 2（不是"小于"）。
- 旧前缀字面量只允许出现在 `scripts/release-layout.sh` 与 `tests/test_release_layout_contract.sh`（守卫角色 `L11`，按路径限定）；全程自检（从起点锚起、按**路径**排除，不是按行内容）：`git diff -U0 p2.2b-start..HEAD -- . ':!scripts/release-layout.sh' ':!tests/test_release_layout_contract.sh' ':!Handoff_Logs' ':!Handoff_Decisions' ':!docs/2026-10-31-p2-2b-release-layout-design.md' ':!docs/2026-10-31-p2-2b-release-layout-plan.md' | grep '^+' | grep -v '^+++' | grep -E 'handoff-(v|\$|\*)|"Handoff |Handoff <noreply'` 为空（`handoff-schema.sh` 基名不在此模式内）。对照实验用**基线对工作树**的形式（`git diff -U0 p2.2b-start -- . <同样的 pathspec>`，未提交改动可见）：含 `handoff-v9.9.9` 的临时改动分别放进允许文件与禁止文件各试一次，只对后者非空，然后撤销；提交区间形式（`p2.2b-start..HEAD`）在 Task 5 最后一次 commit **之后**再跑一次作终检；两种形式都先 `|| echo DIFF-FAILED` 确认 `git diff` 本身成功，空输出才算干净。
- 子进程调 lib 的统一写法：`/bin/bash -c '. "$1" || exit $?; shift; "$@"' _ "$LIB" <fn> <args…>`（`LIB` 不导出；`.` 失败显式传播）。
- sha 工具分派一律 if/else：`if command -v sha256sum >/dev/null 2>&1; then sha256sum -c …; else shasum -a 256 -c …; fi`，绝不 `a && b || c`。
- 契约测试：`zip`/`unzip`/`tar`/sha 工具缺任一 → ❌（不 ➖）；不调 gitx、不调 run_all、不碰 `Release/`。
- 变异证明按「中性化判决、保留诊断」做：对**副本仓**（`cp -R` 到 mktemp，含 tests/ scripts/ release.sh）改源，再在副本里跑套件，先 `grep -n` 确认改的是副本。
- `${VAR}（` 全角标点前一律花括号（#26）；每任务末 checkpoint commit（Decision 0028 决策 2）；**不 push、不 tag**。
- 例外表只换碰过文件的行；`# frozen-rows:` = 行数；冻结清单 `p2_2_rename_manifest.txt` 与谓词**不**重生成/放宽；确需改写含 `handoffx` token 行时，把该 manifest 行登记进受审表 `tests/fixtures/p2_2_rename_refactored.txt`（ratchet，附理由）。

## Review Focus

1. `release_prefix v2.10.0` = `handoff`，且 `RENAME_FROM=v2.9.0` 时 `v2.10.0` = `handoffx`（数值比较）→ Task 1。
2. `checksums.txt` 陈旧（资产变了、zip/tar 仍合法）→ 只有 `shasum -c` 这一道能抓 → Task 2 负向 + 变异。
3. `--sandbox` 目标已存在 → exit 1 不覆盖 → Task 2。
4. 两个消费者的 lib 挂接：`. "$ROOT/scripts/release-layout.sh"` 这一行坏了（路径错/文件缺）→ 必须有测试红 → Task 3。
5. 切前 `test_release_artifact_content` 因在途版本 ➖ 1 项是**预期**；切后必须 2/0、run_all 0 跳过；真切失败 `latest` 不得手工动 → Task 6。

---

### Task 0: 挪开 gitx 双源闸拒绝的开发工具（spec §3.0）+ 守卫搬迁映射

**Files:** `git mv scripts/review-loop.sh tools/review-loop.sh`；`git mv scripts/lib/review-ledger.sh tools/lib/review-ledger.sh`；Modify `tools/review-loop.sh:10`、`tests/test_review_loop.sh:5-6`、`tests/test_scripts_sync.sh:16-18`、`tests/test_shellcheck.sh:21,74-76`；Create `tests/fixtures/p2_2_rename_relocations.txt`；Modify `tests/test_p2_2_rename_manifest.sh:44-46,156-164`、`tests/test_p2_2_rename_bguard.sh:37-40` + 新用例 (vii)–(x)

**Why the mapping:** 冻结清单行 `scripts/review-loop.sh:3:40:R1:skills/handoff→skills/handoffx`（manifest:3702）让守卫 (b) 打开原路径；受审表只容忍锚点变化，不容忍文件消失；冻结清单不可改（bguard 从 `2afca49` 重现）。守卫 (b) 已有 `pathmap`（清单 R 路径行 old→new），把受审搬迁表并进去即可。

- [ ] **Step 0: 起点锚**：`git tag p2.2b-start`（本地，不 push）。
- [ ] **Step 1: RED** `tests/test_review_loop.sh:5-6` 改 `LIB="$ROOT_DIR/tools/lib/review-ledger.sh"`、`CLI="$ROOT_DIR/tools/review-loop.sh"`；跑 → 红。
- [ ] **Step 2: 挪动** 两个 `git mv`；`tools/review-loop.sh:10` 改 `. "$SCRIPT_DIR/../scripts/lib/handoff-schema.sh"`（:12 的 `lib/review-ledger.sh` 不变，shellcheck source 注释同步）；`DEV_ONLY` 去掉两项、:16 注释指向 `tools/`；`test_shellcheck.sh:21` `SCRIPTS_GLOB` 加 `"$ROOT_DIR"/tools/*.sh "$ROOT_DIR"/tools/lib/*.sh`，:74-76 文件表加 `tools/*.sh tools/lib/*.sh`。跑 `test_review_loop` 179/0、`test_scripts_sync`、`test_shellcheck` ✅；`diff -rq scripts/ skills/handoffx/scripts/ | grep -v 'Only in scripts: release-'` 为空。此时 `test_p2_2_rename_manifest` 必红：`refactored row lost its rename`/`anchor-missing … scripts/review-loop.sh:3`（记录原文 = 本步 RED）。
- [ ] **Step 3: 搬迁表** 新建 `tests/fixtures/p2_2_rename_relocations.txt`：`# frozen-rows: 1` + 注释「guard-only path relocation old→new; the frozen manifest keeps the original path」+ 行 `scripts/review-loop.sh→tools/review-loop.sh`。守卫 (b)（:44-46）生成 `pathmap` 后追加 `grep -v '^#' "$RELOC" | grep -v '^$' | sed 's/→/\t/' >> "$W/pathmap"`；(d) 加 ratchet：行数 = 其 `# frozen-rows:`（缺头/不等 → 诊断 `relocations: …` + FAIL）。跑 → a–f 清（(d) 例外表行数差异在 Task 5 收：若此刻 (d) 因例外表红，记录并继续）。
- [ ] **Step 4: bguard** `:37-40` 的拷贝清单加搬迁表。注意 fixture 副本 `$BASE` 是从**冻结树**按清单文件表 tar 出来的，里面仍有旧路径 `scripts/review-loop.sh`（冻结内容），守卫在副本上能直接打开原路径、不会走 fallback；(ix)–(xii)（现有用例到 (viii)，`tests/test_p2_2_rename_bguard.sh:176-212`，不改编号）各自先把副本改成"已搬迁"形态：`rm "$BASE/scripts/review-loop.sh"; mkdir -p "$BASE/tools"; cp "$RT/tools/review-loop.sh" "$BASE/tools/"`（从**活树**取），再跑真实守卫：(ix) 原样 → 守卫对 manifest 行 3702 不报；(x) 把副本 `tools/review-loop.sh:3` 的 `skills/handoffx` 改回旧 token → RED `anchor-missing`；(xi) 删副本 `tools/review-loop.sh` → RED；(xii) 删搬迁表那一行（头改 0）→ RED（原路径打不开且无映射）。每例用独立 `fresh_mut` 副本，不累积改基线。`manifest reproduces byte-for-byte from frozen tree` 断言不变。跑 bguard → 运行计数 17→21（静态点另算：`grep -cE '^[[:space:]]*assert_'`，Task 5 写进表）。
- [ ] **Step 5: Commit** `git add -A tools scripts tests && git commit -m "p2.2b(task0): move the maintainer-only review loop out of scripts/ — gitx's dual-source gate only tolerates root-level release-* there (no FORCE), so any real cut was already blocked since 0050; guard (b) learns reviewed path relocations"`

### Task 1: `scripts/release-layout.sh` + 契约测试 lib 段 + 守卫角色 L11

**Files:** Create `scripts/release-layout.sh`、`tests/test_release_layout_contract.sh`；Modify `tests/test_scripts_sync.sh:18`（`DEV_ONLY` 加 `release-layout.sh`）、`tests/lib/p2_2_rename_inventory.sh`（分类函数最前加路径规则）

**Interfaces（Produces）:**
- `release_ver_ge <vA> <vB>` → 0 A≥B / 1 A<B / 2 任一非法（`=~` 校验后 `IFS=. read` 三段 `-gt/-lt`）
- `release_prefix <ver>` → stdout `handoff` | `handoffx`；非法或 `RENAME_FROM` 非法 → 无输出 return 2
- `release_dir_for <ver>` → `Release/<prefix>-<ver>`；`release_asset <ver> skill|source|full` → `<prefix>-<ver>.skill|-source.tar.gz|-full.tar.gz`，未知 kind → return 2（两者对非法版本亦 return 2）
- `verify_release_integrity <dir> <ver>` → 0/1：五文件非空 → `unzip -t` → `tar tzf` → `grep -q '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"'` → `(cd dir && <sha -c checksums.txt>)`；每条失败 `echo "❌ …"` 并 `rc=1`（与 publisher :177-201 同形，资产名经 `release_asset`）；guard `_RL_LAYOUT_SOURCED`

- [ ] **Step 1: RED** 写 `tests/test_release_layout_contract.sh`（`source common.sh`；`LIB="$SCRIPTS_DIR/release-layout.sh"`；`run_lib() { /bin/bash -c '. "$1" || exit $?; shift; "$@"' _ "$LIB" "$@"; }`）：前置工具四项（缺即 ❌）；`release_prefix`：`v2.2.2`/`v2.10.0`→`handoff`，`v3.0.0`/`v10.0.0`→`handoffx`；`3.0.0`/`v3`/`v3.0.0-rc1` → exit 2 且空；`RENAME_FROM=v9.0.0` 时 `v3.0.0`→`handoff`；`RENAME_FROM=v2.9.0` 时 `v2.10.0`→`handoffx`；`RENAME_FROM=bogus` → exit 2；`release_dir_for v3.0.0`=`Release/handoffx-v3.0.0`；`release_asset v2.2.2 skill`=`handoff-v2.2.2.skill`、`v3.0.0 full`=`handoffx-v3.0.0-full.tar.gz`、`v3.0.0 bogus`→2；`verify_release_integrity "$WORK/nope" v3.0.0` → 1 且含 `missing dir`。
- [ ] **Step 2: 跑 RED**（lib 缺 → `.` 失败 exit ≠ 0，断言全红）。
- [ ] **Step 3: 实现 lib**。
- [ ] **Step 4: GREEN**；`shellcheck -s bash scripts/release-layout.sh` 无 warning。
- [ ] **Step 5: 守卫** inventory 分类函数首行加 `if (path == "scripts/release-layout.sh" || path == "tests/test_release_layout_contract.sh") { ROLE = "L11"; return }`；`DEV_ONLY` 加 `release-layout.sh`；跑 `test_scripts_sync` ✅、`test_p2_2_rename_bguard` 21/0；`test_p2_2_rename_manifest` 此时 (e)=0，(d) 行数差异预期（Task 5 收）。
- [ ] **Step 6: Commit** `p2.2b(task1): release-layout lib …`

### Task 2: 根 `release.sh` 的 `--sandbox` + legacy 对齐 + 契约测试端到端

**Files:** Modify `release.sh`（:3、:14-27、:31、:160-174、:191-253、:274-335、:337-340）；Modify `tests/test_release_layout_contract.sh`

**Produces:** `./release.sh --sandbox <vX.Y.Z> <outdir>` → `<outdir>/<prefix>-<ver>/` 内 `<prefix>-<ver>.skill`（zip 直打 `skills/handoffx`，根 `handoffx/`，排除 `handoffx/evals/*`）、`<prefix>-<ver>-source.tar.gz`（根 `<prefix>-<ver>/`，`stage_source`+`audit_staged_source`）、`RELEASE_NOTES.md`（抽函数 `write_release_notes <dir>`，标题 `# HandoffX $VERSION — Release Notes`，产物名经 `release_asset`）、`sbom.cyclonedx.json`（`scripts/emit-sbom.sh <dir> <prefix> <ver> handoffx`）、`checksums.txt`（`<sha256>  <name>` 三行：skill / source / sbom，用与 lib 同样的 if/else 分派生成）；目标目录已存在 → `❌ … already exists` exit 1；无 outdir/版本非法 → exit 1；不跑 run_all/sanitize/audit/CHANGELOG/latest；成功末行 `✅ sandbox layout → <dir>`。legacy：`RELEASE_DIR="$ROOT/$(release_dir_for "$VERSION")"`，所有 `handoff-$VERSION` 经 lib 派生，版本正则 `vX.Y.Z`，`latest` 改 `ln -sfn "$(basename "$RELEASE_DIR")" latest`；CHANGELOG 脚手架 `:359` 的 `Artifacts: \`Release/$VERSION/\`` 改为 `$(release_dir_for "$VERSION")/`，`:382` 的布局注释同步。

- [ ] **Step 1: RED** 追加（测试内 `sha_check() { if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1"; else shasum -a 256 -c "$1"; fi; }`）：
  - `--sandbox v3.0.0 "$WORK/sb"` exit 0；目录存在；五文件非空；`unzip -l` 首条目以 `handoffx/` 开头；`tar tzf | head -1` 以 `handoffx-v3.0.0/` 开头；checksums 3 行；`(cd dir && sha_check checksums.txt)` 0；`run_lib verify_release_integrity dir v3.0.0` 0。
  - `--sandbox v2.9.9 "$WORK/sb"` → `handoff-v2.9.9/handoff-v2.9.9.skill` 存在；verify 0。
  - 二次 `--sandbox v3.0.0 "$WORK/sb"` → exit 1，原 `checksums.txt` 内容不变（先 `cp` 留副本再 `cmp`）。
  - `--sandbox v3.0 "$WORK/sb2"` → 1；`--sandbox` 无参 → 1。
  - 负向（各在 `cp -R` 副本上）：neg1 删 `checksums.txt` → verify 1 含 `missing or empty`；neg2 `printf ' ' >> sbom.cyclonedx.json` → 先断言 `unzip -t` 仍 0、`grep bomFormat` 仍命中、sha 与原不同，再 verify 1 且含 `checksums.txt`；neg3 把目录内 `handoffx-v3.0.0.skill` 与 `-source.tar.gz` 改名为 `handoff-v3.0.0.*`（目录名不动）→ verify … v3.0.0 → 1 含 `missing or empty`；neg4 `: > handoffx-v3.0.0-source.tar.gz` → 1 含 `missing or empty`。
- [ ] **Step 2: 跑 RED**。
- [ ] **Step 3: 实现**。
- [ ] **Step 4: GREEN**；`bash release.sh --dry-run-audit v999.999.999` exit 0；`test_ci_workflow` ✅；shellcheck 无新 warning。
- [ ] **Step 4b: dry-run 负控跟随 canonical 目录** `tests/test_release_dry_run_audit.sh:8,36-41` 现在只看旧路径 `Release/v999.999.999`——改为同时断言 `Release/v999.999.999` 与 `Release/handoffx-v999.999.999` 都不存在（`rm -rf` 两者在前，判定在后；不改其余断言）；变异：对副本 `release.sh` 在 dry-run 分支里插一行 `mkdir -p "$RELEASE_DIR"` → 该套件红。
- [ ] **Step 5: 变异**（副本仓）：① `release_prefix` 分支恒 `handoffx` → `v2.2.2` 断言红；② 数值比较改字符串比较（`[ "$a" \> "$b" ]` 形）→ `RENAME_FROM=v2.9.0` 的 `v2.10.0` 断言红；③ `verify_release_integrity` checksums 分支 `rc=1`→`rc=0` 保留 echo → neg2 红；④ sandbox 已存在检查删除 → 二次运行断言红。结果写进任务报告。
- [ ] **Step 6: Commit** `p2.2b(task2): release.sh --sandbox …`

### Task 3: publisher + backfill 改调 lib、身份 `HandoffX`、挂接 load-bearing

**Files:** Modify `scripts/release-publish-github.sh`（:37 之后插 `. "$ROOT/scripts/release-layout.sh"`；:40、:44、:177-201 删函数、:180-192、:240、:248、:262、:323、:330、:333、:385-396、:417）；`scripts/release-publish-github-backfill.sh`（`ROOT` 初始化（:30-38）之后插同一行；:193-206 删副本；:215、:235、:249、:265、:304、:307、:355、:380-390、:409）；`tests/test_release_publish_gates.sh`

- [ ] **Step 1: RED** 在 `test_release_publish_gates.sh`：保留三函数 parity 循环不变；新增「挂接」段：对 `$PUB` 与 `$BACKFILL` 各取 `hook=$(grep -oE '^\. "\$ROOT/scripts/release-layout\.sh"' "$f")`，断言非空；在沙箱 `ROOT="$ROOT_DIR" /bin/bash -c "$hook; declare -f verify_release_integrity | grep -q . && verify_release_integrity \"\$1\" \"\$2\"" _ <fixture> <ver>`——fixture 由 Task 2 的 `--sandbox v3.0.0` 与 `--sandbox v2.9.9` 现场生成各一，期望 0；无效 fixture（删 checksums）期望 1；再断言 `grep -c '^verify_release_integrity() {' $f` = 0。跑 → 红。
- [ ] **Step 2: 实现**：两脚本插 source 行；删内嵌函数；`RELEASE_DIR="$(release_dir_for "$VER")"`、资产名 `$(release_asset "$VER" skill|source)`、backfill 三处 `Release/handoff-${V}` 同法；身份串 `user.name "HandoffX"`、`release: handoffx ${VER}`、tag 消息 `HandoffX ${VER}`、作者断言 `HandoffX <noreply@github.com>`、`--title "HandoffX ${VER}"`、两条日志。
- [ ] **Step 3: GREEN**；`bash -n` 两脚本；shellcheck 无新 warning；`grep -nE 'handoff-(v|\$|\*)|"Handoff |Handoff <noreply' scripts/release-publish-github*.sh` 为空。
- [ ] **Step 4: Commit** `p2.2b(task3): …`

### Task 4: `install.sh` 自举 glob + `test_install` C10

**Files:** `install.sh:193,194,214,226,227`；`tests/test_install.sh:333-339`

- [ ] **Step 1: RED** C10 现场包改名 `handoffx-v0.0.0-test.skill`（:338-339）；:333 注释改为「现场打包，不用 Release/ 里的旧版包：旧包 ZIP 根是旧 skill 名」（不含旧产物字面量），:335 去掉「暂留至 P2.2b」；跑 `test_install` → C10 红。
- [ ] **Step 2: 实现** 三处 glob `handoffx-*…`；两行提示。
- [ ] **Step 3: GREEN** `test_install` 272/0；shellcheck 套件 ✅；`grep -n 'handoff-' install.sh tests/test_install.sh` 为空。
- [ ] **Step 4: Commit**

### Task 5: v3.0.0 + 文档 + 两份 CHANGELOG + 测试前缀 + 例外/受审表 + 计数

**Files:** `VERSION`、`skills/handoffx/VERSION`、`README.md:8,177`、`README_CN.md:8,177`、`INSTALL.md:91,99,111,116,140,141,155,156,210,316-320`、`docs/GITHUB_RELEASE_SOP.md`（17 行）、`HANDOFF.md:35`、`CHANGELOG.md:6`、`Release/CHANGELOG.md`（本机）、`tests/test_doc_freshness.sh:19,126,128,139`、`tests/test_doc_freshness_k4_chicken_egg.sh:5,17,39`、`tests/fixtures/p2_2_rename_exceptions.txt`、`tests/fixtures/p2_2_rename_refactored.txt`、五份计数文档、`TEST-SCENARIOS.md`

- [ ] **Step 1: 测试前缀** `test_doc_freshness.sh:19` → `handoffx-$v`，:126/:128/:139 → `(handoffx-)?`；K4 `POISON="handoffx-v0.0.1-stale"`、:5/:39 文案。跑两套件 → 红。
- [ ] **Step 2: 版本与文档** `VERSION`/sidecar → `v3.0.0`；README/README_CN 徽章、:177 `unzip -o handoffx-v3.0.0.skill …`；INSTALL 横幅两处、`VER=v3.0.0`、七处产物路径、§6 两条命令去掉 `PROJECT_NAME=… SKILL_NAME=…` 并加一句自动探测说明；HANDOFF.md:35 `handoffx-v3.0.0`；SOP 15+2 行，且其可执行示例整体改到 v3.0.0（`:43` `export VER=v3.0.0`、`:51` 期望输出、版本表示例）——示例若留 `v2.2.1`，替换成新前缀后会与门限矛盾（`handoff-v2.2.1` 才是真目录）。
- [ ] **Step 3: 受审表** INSTALL 横幅行是冻结清单行 `INSTALL.md:97:9:R5`（锚点含 `v2.2.2`）：按受审表格式 `path:line:col:ROLE:reason`（键 = 原 manifest 行）登记 `INSTALL.md:97:9:R5:version bump v3.0.0`，其 `# frozen-rows:` 92→93；守卫 (b) 报出的其他锚点失配行同法登记（只登记，不改谓词/清单）。
- [ ] **Step 4: CHANGELOG** 根 `CHANGELOG.md:6` → `## v3.0.0 — 2026-10-31`，第三 bullet 末句改「产物与 `Release/` 布局自本版起为 `handoffx-<ver>`；publisher/backfill 按版本门限（v3.0.0）读旧布局」；`Release/CHANGELOG.md` 标题 `# HandoffX — Release History`，`## v2.2.2` 前插同节同文。
- [ ] **Step 5: 例外表** 对 Task 0–5 碰过的文件派生行并替换其旧行，其余不动；`# frozen-rows:` = 行数；**先** `P22_ROOT="$PWD" bash -c '. tests/lib/p2_2_rename_inventory.sh; p22_inventory' | grep ':L8:'` 必须为空——若非空，是漏改的 occurrence，回去改文本，不删例外行。`test_p2_2_rename_manifest` a–f 清；bguard 21/0。
- [ ] **Step 6: 计数** 套件 37→38；静态断言点按 `_count_static_asserts_one` 谓词重算**每个被改过的套件**：`test_release_layout_contract`、`test_release_publish_gates`、`test_p2_2_rename_bguard`（:393 行现为 9）、`test_release_dry_run_audit`、`test_install`、`test_doc_freshness*`、`test_review_loop`（挪动不改数）→ 五份文档 `37 套件 / 846` 全部 token（README:9 徽章 `37%20suites…846%2B`、:101、:199；README_CN 同；HANDOFF:15、:37、:365；CONTRIBUTING:32；TEST-SCENARIOS:353）；TEST-SCENARIOS 表加 `` | `test_release_layout_contract.sh` | N | 发布布局契约：前缀门限 / sandbox 产物 / verify_release_integrity 新旧布局 + 负向（dev-only，不跳过） | ``（文件名**必须带反引号**，Test 20 的解析器按此匹配），`test_release_publish_gates` 行更新；加完先单跑 `test_doc_freshness` 确认 Test 20 认到新行。
- [ ] **Step 7: GREEN** `bash tests/run_all.sh > /tmp/p2_2b-run_all.log 2>&1`（日志放仓库外，`log` 不在 `.gitignore`）38 套件 0 失败（`run_all` 不统计跳过；判据 `grep -c '➖' /tmp/p2_2b-run_all.log` **恰为 1**，且该行来自 `test_release_artifact_content` 的在途态——记录原文；本机非 root，root 下另有合法跳过不在此判据内）；新契约套件 0 ➖；gitx 过滤后双源无漂移；§Global 自检：对照实验（基线对工作树）通过；commit 后再跑提交区间形式为空。
- [ ] **Step 8: Commit**；`git status --short` 为空。

### Task 6: 切前三源审 → 真切 v3.0.0 → 后置验证 → 落盘

- [ ] **Step 1: 切前三源审**（§4 分离；给 diff `p2.2-pre-task6`…HEAD + 设计稿，不给结论）：opus code-reviewer 逐行；silent-failure-hunter（sandbox / verify / prefix / 两消费者挂接）；Codex `[CODE REVIEW REQUEST]`（经 `codex:codex-rescue`）。发现 RED→GREEN + 变异，每轮 commit，直到三源 CLEARED。记下**发布输入 commit** SHA。
- [ ] **Step 2: dry-run** `PROJECT_ROOT="$PWD" bash ~/.agents/skills/gitx-release/scripts/release.sh v3.0.0 --dry-run` → exit 0 且输出无 `❌`（它验 preflight / VERSION / CHANGELOG 闸 / 双源，并**会跑 `docs-audit.sh` 文档审计**；不跑 run_all、不做产物 deep audit——文档审计红也是真红，按提示修）。任一闸红 → 修、commit、重跑。
- [ ] **Step 3: 真切** 同命令去 `--dry-run`；末尾 `✅ Release/latest → handoffx-v3.0.0`。失败：`readlink Release/latest` 必须仍 `handoff-v2.2.2`，不手工 `ln`；按提示修后重跑。
- [ ] **Step 4: 后置断言** `readlink Release/latest` = `handoffx-v3.0.0`；目录含 `.skill`、`-source.tar.gz`、`-full.tar.gz`、`checksums.txt`、`sbom.cyclonedx.json`、`TOKEN_USAGE.md`、`RELEASE_NOTES.md`；`(cd Release/handoffx-v3.0.0 && <sha -c checksums.txt>)` 0；`/bin/bash -c '. "$1" || exit $?; shift; "$@"' _ "$PWD/scripts/release-layout.sh" verify_release_integrity "$PWD/Release/handoffx-v3.0.0" v3.0.0` → 0（自包含，不依赖测试内助手）；`unzip -l …skill | head -4` 根 `handoffx/`；`test_release_artifact_content` 2/0 非 ➖；K4 1/0；`bash tests/run_all.sh > /tmp/p2_2b-post-cut.log 2>&1` 38 套件 0 失败且 `grep -c '➖'` = 0。
- [ ] **Step 5: 重切协议**（仅当后置断言或切后发现要求改发布面代码）：`rm -rf Release/handoffx-v3.0.0 && ln -sfn handoff-v2.2.2 Release/latest` → 修（RED→GREEN）→ commit → 回 Step 2；Dev Log 记两次切与原因。
- [ ] **Step 6: 落盘** Dev Log 0070（三源结果、发布输入 commit、产物清单与 `latest` 证据、切前 ➖1 / 切后 0 跳过）、Decision 0028 Outcome 回填「2b 完成」、HANDOFF.md Current State（下一步：Boss `git tag v3.0.0` / push / 「进 P2.3」；gitx 侧 DEV_ONLY 允许清单是否要做由 Boss 定）；handoff 批 commit。**不 push、不 tag。**
