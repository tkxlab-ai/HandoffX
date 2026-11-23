# P2.2b — 发布链 canonical 布局 + 真切 v3.0.0：设计稿（2026-10-31）

> 承载：计划 v4 §3 Task 3「P2.2b」段 + Decision 0028 决策 1；Boss 2026-10-31「3.0.0 没问题」「没有异议，继续」+ autopilot 授权。
> 评审节律（设计 §1 T7）：P2.2 属三源阶（opus + silent-failure-hunter + Codex）；plan 先过 Codex（Peer Review Framework）。

## 0. 意图与 Why

P2.2a 把**工具**改成了 `handoffx`，但产物与 `Release/` 布局故意留在 `handoff-<ver>`（88 处登记为例外表 `L8`，守卫 ratchet 看守）。P2.2b 把发布链翻到 canonical 名，并在这台机器上**真切 v3.0.0**：根目录已是 `Handoffx`、gitx-release v1.13.0 已装好且 dry-run 跑通，`PROJECT_NAME` 自动探测得 `handoffx`——canonical 名是自动落出来的，不需要传参。切完后 P2.2 整体收口，等 Boss「进 P2.3」。

v3.0.0 带出去的是设计 §4 写明的中间态：工具叫 `handoffx`，项目文件仍是 `HANDOFF.md / Handoff_Logs/ / Handoff_Decisions/`。P2.4 翻四件套常量时是第二次 breaking，另起 v4.0.0（我的判断，Boss 无异议）。

## 1. 目标 / 非目标 / 反目标

- **目标**：(a) 本仓所有生产者与消费者按 `handoffx-<ver>` 命名；(b) 旧版本（< v3.0.0）产物仍可被 publisher / backfill 读到，门限由版本号决定、单点定义；(c) 布局契约**不依赖 gitx 在场**即可测、**不跳过**；(d) gitx 真切 `Release/handoffx-v3.0.0/`，`latest` 翻过去，`test_release_artifact_content` 对新树实跑；(e) 88 条 L8 例外全部退掉，守卫 a–f 清。
- **非目标**：不改四件套名与 `handoff-schema.sh` 常量（P2.4）；不改 gitx-release 本身；不做公开镜像发版（Q2，独立 Boss 门控）；不给旧名产物加 alias / 兼容探测（§0 hard-cut）；不 push、不打 tag（Boss 明文）。
- **反目标**（做成了也算失败）：契约测试在没有 gitx 的机器上 ➖ 跳过（#12 闸门三准则）；publisher 与 backfill 各自一份 `verify_release_integrity` 继续漂移；根 `release.sh` 的 `--sandbox` 长成第二套发布流水线；为让守卫绿而把例外表"重生成"带进百行无关 diff（0066 教训：例外表不是当前树的纯函数，只换碰过的文件的行）。

## 2. 约束

- bash 3.2（macOS 主目标）+ mawk/POSIX（Linux）；`sort -V` 不可用，版本比较自己写。
- `scripts/` 与 `skills/handoffx/scripts/` 字节相等（T4）；dev-only 脚本进 `tests/test_scripts_sync.sh` 的 `DEV_ONLY`。
- gitx 真切会跑 `tests/run_all.sh`（含 K4 对 `Release/latest` 的临时毒值——K4 自己还原，gitx 最后才翻 `latest`）；`Release/` 整目录 gitignored，`Release/CHANGELOG.md` 是 gitx 的 CHANGELOG 闸门真相源并被注入 tarball。
- 测试静态断言点由五份文档计数守卫（Test 15/18/20）机械派生；新套件须补 TEST-SCENARIOS 行。
- 改名守卫 (b) 锚点：碰到含 `handoffx` token 的行要保持其前后 12 字节；例外表 `# frozen-rows:` 须等于行数。

## 3. 已定的 How（按决定的方式）

### 3.0 前置：让 gitx 的双源闸能过（Codex 计划评审 H1，实测确认）
gitx `check_dual_source` / audit §9 对 `diff -rq scripts/ skills/handoffx/scripts/` 只放行 `Only in scripts: release-*` 与 `scrub-tarball.sh`，**不读**本仓 `tests/test_scripts_sync.sh` 的 `DEV_ONLY`；当前树的 `scripts/review-loop.sh`、`scripts/lib/review-ledger.sh`（0050 起，晚于 v2.2.2）已经会让任何真切在此闸失败（禁 FORCE）。处置：(a) 新 lib 命名 `scripts/release-layout.sh`（根层 `release-*`，与 publisher 同处，gitx 放行）；(b) `scripts/review-loop.sh` → `tools/review-loop.sh`、`scripts/lib/review-ledger.sh` → `tools/lib/review-ledger.sh`（`git mv`；`review-loop.sh` 改为从 `$SCRIPT_DIR/../scripts/lib/handoff-schema.sh` 取 schema；`test_review_loop.sh` 两处路径、`DEV_ONLY` 清单、`test_shellcheck` 扫描范围加 `tools/`）。备选是 gitx 侧加项目允许清单——那是 gitx 仓的决定（Boss），本仓的挪动与之兼容、可逆。

### 3.1 单点：`scripts/release-layout.sh`（dev-only，publisher / backfill / 根 release.sh / 契约测试共用）
- `release_prefix <vX.Y.Z>` → `handoff`（< `RENAME_FROM`）/ `handoffx`（≥）；`RENAME_FROM` 默认 `v3.0.0`，可用环境变量覆盖（只为测试）。版本比较：拆三段按数值比，格式不合法 → return 2。
- `release_dir_for <ver>` → `Release/<prefix>-<ver>`；`release_asset <ver> skill|source|full` → 文件名。
- `verify_release_integrity <dir> <ver>`：从 publisher 原样搬出（五个非空文件、`unzip -t`、`tar tzf`、SBOM `bomFormat`、`shasum -c checksums.txt`），文件名经 `release_asset` 派生。backfill 删掉自己那份副本改调 lib；`tests/test_release_publish_gates.sh` 比对集合加入 `verify_release_integrity`，并断言两脚本都不再内嵌同名函数。

### 3.2 根 `release.sh`：加 `--sandbox <ver> <outdir>`，legacy 路径对齐命名
- `--sandbox`：在 `<outdir>/<prefix>-<ver>/` 生成 `.skill`（ZIP 根 `handoffx/`）、`-source.tar.gz`（根 `<prefix>-<ver>/`，复用 `stage_source`）、`RELEASE_NOTES.md`、`sbom.cyclonedx.json`（调 `scripts/emit-sbom.sh <dir> handoffx <ver> handoffx`）、`checksums.txt`（gitx 2.8 同格式：`<sha256>  <name>`，覆盖两产物 + sbom）。**不**跑 run_all、不 sanitize/audit、不碰 `Release/`、不写 CHANGELOG。它是契约测试的生产者，不是发布路径——文件头注释写明。
- legacy 路径只做：目录 `Release/$VERSION` → `release_dir_for`；21 处 A 行按 `release_prefix` 派生；`latest` 由 `rm -f && ln -s` 改 `ln -sfn`（原子，与 gitx 同形；Gotcha #8 同根）。不补 checksums/sbom（gitx 才是真生产者）。
- `-full.tar.gz` 只有 gitx 产；`--sandbox` 不产，契约测试不要求它（publisher preflight 也不要求）。

### 3.3 publisher / backfill
- `RELEASE_DIR` 与 12 处 B 行改用 lib 派生；7 处 A 行身份串（`git config user.name` / commit msg / tag msg / `--title` / 日志）统一 `HandoffX`，line 333 的作者断言随之；SOP 对应行同步（#23 对称 loci）。
- backfill 对 < v3.0.0 的版本自然得旧前缀——不需要额外开关；计划里的 `BACKFILL_RENAME_FROM` 即 `RENAME_FROM`，一个名字。

### 3.4 `install.sh` bootstrap
- 三处 glob `handoff-*` → `handoffx-*`（`handoff-*` 本来就匹配不到 `handoffx-*`，不存在"顺带兼容"）；两行提示文案；`EXTRACTED_ROOT` 与 `release.sh` tarball 根一致。`test_install` C10 现场打包改名 `handoffx-v0.0.0-test.skill`，去掉"暂留至 P2.2b"注释。

### 3.5 契约测试 `tests/test_release_layout_contract.sh`（不跳过）
- 前置：`zip`/`tar`/`shasum|sha256sum` 缺任一 → ❌ FAIL（是 Linux 已声明依赖，不是 ➖）。
- 正向：`release.sh --sandbox v3.0.0 <tmp>` → 目录名、五文件、ZIP 根 `handoffx/`、tarball 根 `handoffx-v3.0.0/`、`shasum -c` 过、SBOM 含 `bomFormat`；`verify_release_integrity` 对它 PASS。`release.sh --sandbox v2.9.9 <tmp>` → `handoff-v2.9.9/…`，`verify_release_integrity` 同样 PASS（旧布局消费路径）。
- `release_prefix` 边界：`v2.2.2`→handoff、`v2.10.0`→handoff、`v3.0.0`→handoffx、`v10.0.0`→handoffx、`3.0.0`/`v3`/`v3.0.0-rc1` → return 2；`RENAME_FROM=v9.0.0` 时 `v3.0.0`→handoff（证门限 load-bearing）。
- 负向（判决键 = exit / 消息，非 echo）：删 `checksums.txt` → FAIL；给 `sbom.cyclonedx.json` 追加一个空格（字节与 hash 变、`bomFormat` 仍在、zip/tar 不受影响）→ 只因 `shasum -c` 陈旧而 FAIL；目录内资产改成旧前缀名后 `verify … v3.0.0` → FAIL（校验器按版本派生文件名；目录 basename 不在校验范围，由 `release_dir_for` 单独断言）；空 tarball → FAIL。
- 变异证明（Gotcha #25，「中性化判决、保留诊断」）：`release_prefix` 分支恒 `handoffx`（`v2.2.2` 断言红）；数值比较退化为字符串比较（`RENAME_FROM=v2.9.0` 下 `v2.10.0` 应为 `handoffx`，字符串比较给 `handoff` → 红）；`verify_release_integrity` 的 checksums 分支 `rc=1`→`rc=0` 保留 echo（篡改 sbom 断言红）；sandbox「目标已存在」检查删除（二次运行断言红）。

### 3.6 版本 / 文档 / CHANGELOG / 守卫
- `VERSION`、`skills/handoffx/VERSION`、README/README_CN 徽章与 :177、INSTALL 横幅与 `VER=`、HANDOFF.md:35 → `v3.0.0` / `handoffx-v3.0.0`；INSTALL §6 两条命令去掉 `PROJECT_NAME=handoff SKILL_NAME=handoff`（两者自动探测；注一句"根目录名与 `skills/<dir>` 即名字"）。
- 根 `CHANGELOG.md` `[Unreleased] — v3.0.0` → `## v3.0.0 — 2026-10-31`，正文补"产物与 `Release/` 布局改 `handoffx-<ver>`；publisher/backfill 按版本门限读旧布局"；`Release/CHANGELOG.md`（本机、gitignored、gitx 闸门真相源）同节同文、标题改 `HandoffX`。
- INSTALL 13 行、SOP 17 行（含 2 条示例输出随身份串改）、README:177 按侦察表改。
- 例外表：删 88 条 L8；碰过的文件按谓词派生只换其行（0066 方法）；`# frozen-rows:` 同步；L7（backfill）20 行因 lib 化会减少，同法处理。

### 3.7 真切 v3.0.0（gitx）
- 顺序（Codex H4）：3.0–3.6 全 GREEN → **三源审在切之前**（对发布输入提交做，源码级修复全部闭合后再切）→ 记录发布输入 commit → `--dry-run` → 真切 → 切后只做验证与落盘（Dev Log / HANDOFF.md 不入 tarball；Handoff_Logs 随下次发布）。切后若发现必须改发布面代码：删 `Release/handoffx-v3.0.0/`、把 `latest` 指回 `handoff-v2.2.2`（Gotcha #8：不留悬空）、修 → 全部后置断言重跑 → 重切，Dev Log 记两次。
- 前置：run_all 全绿（**切前 `test_release_artifact_content` 因 VERSION=v3.0.0 ≠ `latest` 而 ➖ 1 项是预期的在途态，切后必须 2/0**）、`diff -rq scripts/ skills/handoffx/scripts/` 经 gitx 过滤后为空、`Release/CHANGELOG.md` 有 `## v3.0.0 ` 且无 TODO、工作树干净（gitx preflight 对未提交/未跟踪一律拒绝，dry-run 亦然——实测第一道闸是 sidecar `skills/handoffx/VERSION` 与传入版本一致）。
- 命令：`PROJECT_ROOT="$PWD" bash ~/.agents/skills/gitx-release/scripts/release.sh v3.0.0`（直接调底层；wrapper 有 VERSION 自校验 quirk，0066）。`--dry-run` 不跑 run_all / 不做 audit，只验 preflight / VERSION / CHANGELOG 闸 / 双源——判据是 exit 0 且无 `❌`，不是 `Artifacts:` 字样。
- 预期：`Release/handoffx-v3.0.0/{handoffx-v3.0.0.skill,-source.tar.gz,-full.tar.gz,checksums.txt,sbom.cyclonedx.json,TOKEN_USAGE.md,RELEASE_NOTES.md,…}`，audit 过后 `Release/latest → handoffx-v3.0.0`。
- 后置：`test_release_artifact_content` 2/0（不是 ➖）；K4 1/0；run_all 0 跳过；`verify_release_integrity` 对真树 0；Dev Log + Decision 0028 Outcome 回填；`git tag v3.0.0` 与 push **留 Boss**。
- 失败处置：gitx 自己 cleanup 半成品；`latest` 未翻就还是 `handoff-v2.2.2`——不手工 `ln`。

## 4. 留给 builder 的

- `release.sh --sandbox` 内部复用哪些现有函数（`stage_source` / `emit_release_manifest` 的签名）、`RELEASE_NOTES.md` 模板是否原样复用。
- 版本比较的实现形态（awk 一行或纯 bash）——只要求三段数值、非法即 2。
- 契约测试里"篡改一字节"的可移植写法（`printf '\0' | dd … conv=notrunc`）。
- 例外表派生命令：`P22_ROOT="$PWD" bash -c '. tests/lib/p2_2_rename_inventory.sh; p22_inventory | p22_exception_seed'`，只取碰过文件的行。

## 4b. builder check 的回答（独立 builder 读稿后提出，以下为我的裁定）

- **永久旧前缀字面量的守卫归类**：`scripts/release-layout.sh` 与 `tests/test_release_layout_contract.sh` 的职责就是知道旧前缀，其中的 `handoff` 不是"延后"而是永久。在 `tests/lib/p2_2_rename_inventory.sh` 加**按路径限定**的角色 `L11: version-gated legacy prefix`（只匹配这两个路径，置于 R3/L8/L10 规则之前）；不加形态谓词（会重分类冻结清单里的既有 L8 行，破坏 bguard 的 `2afca49` 可重现性断言——两个新路径在该提交不存在，故安全）。退出判据「L8 = 0」不变，L11 是显式的新家。
- **`verify_release_integrity` 可移植性**：不原样搬。sha 校验走分派（`sha256sum -c` ‖ `shasum -a 256 -c`，与 `emit-sbom.sh` 同法）；`bomFormat` 用 `grep -q '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"'`，不引入 python3。契约测试前置只要求 `zip` / `unzip` / `tar` / (`sha256sum`|`shasum`)——都在已声明的 Linux 依赖内，文档依赖清单不扩。
- **提交节律**：gitx preflight 要求工作树无未提交改动与未跟踪文件（dry-run 亦然）。Decision 0028 决策 2 的 checkpoint-commit 授权覆盖整个 P2.2（本阶段已沿用），每任务末 commit，本设计稿与 plan 一并提交；真切前树必须干净。push / tag 仍留 Boss。
- **backfill 身份串**：与 publisher 同步改 `HandoffX`（公开镜像从此一个身份；身份是"谁发布"，不是历史产物名）；对应 L7 行与 SOP 行一并处理。
- 采纳 builder 两条自决：`--sandbox` 给 `emit-sbom.sh` 传**当版前缀**作 `<project_name>`（否则旧版 SBOM 零组件）；根 `release.sh` 版本正则收紧为 `vX.Y.Z`（publisher 已要求；CI 用 `v999.999.999`）。

## 5. 退出

run_all 38 套件 0 失败 0 跳过 + 守卫 a–f 清（L8 = 0）+ `Release/latest → handoffx-v3.0.0` + artifact 门禁实跑 + 三源闭 → Dev Log → **等 Boss：tag / push / 「进 P2.3」**。
