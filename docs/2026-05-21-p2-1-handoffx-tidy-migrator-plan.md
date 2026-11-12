# P2.1 `/handoffx-tidy` Schema Migrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 造 `/handoffx-tidy` schema 迁移器：把 v2 旧四件套（HANDOFF.md + Handoff_Logs/ + Handoff_Decisions/）迁到 handoffx schema，含全 .md 内字面路径串重写；幂等、双平台、原子回滚、root-safe；不碰真仓（合成 fixture + real-repo 拷贝快照）。

**Architecture:** subcommand `tidy-handoff.sh schema-upgrade`（Q1, 2026-05-21 Boss 拍板）→ source helper `scripts/lib/handoffx-tidy-migrate.sh` 含迁移核心（detect/preflight/rename/text-rewrite/atomic-staging/rollback）→ 全 .md 字面路径串扫描重写（Q2）→ `.partial` staging + EXIT trap rollback（循 `migrate-to-v2.sh` 范式）。新 command-shim `handoffx-tidy.md`。Decision 0019/0020 + 0025 5 阶段方案 A，P2.1 = 不可逆类。

**Tech Stack:** Bash 3.2+ / mawk-safe；TDD（RED→GREEN）；T4 双源 bundle byte-equal；run_all 32(→34) 全绿门；P2.0 baseline-ratchet guard 持续守门（任何新四件套字面量散落即 RED）。

**设计源**：master design `docs/2026-05-19-p2-handoffx-megaprogram-design.md` §3 P2.1 + Decision `Handoff_Decisions/0025-2026-05-20-p2-0-phased-plan-5-stage-approach-a.md` 5 阶段方案 A + 2026-05-21 Boss 拍板（Q1=subcommand / Q2=全扫重写）。

---

## 不变式（全任务遵守）

- **T2** 不 blind sed；逐 locus 精确 Edit；P-A allowlist 子集（schema-source values 为唯一改名 locus）。
- **T4** `scripts/` 与 `skills/handoff/scripts/` byte-equal；每任务末 `diff -rq`。
- **T5** 每任务末 `bash tests/run_all.sh` 0 失败；新增测试触发 self-ref 收敛即机械重基线（per-suite-count-drift-guard-plan Task 5 范式）。
- **T6** 任何 `git push` 须 Boss 逐 context 显式授权；本地 commit 频繁。
- **T7** 全 6 任务 = 两段审（spec→quality） + controller 机械对抗；P2.1 终阶 = 三异构源（opus + silent-failure-hunter + Codex Boss-triggered，P2.1 不可逆类 Q3 强制）。
- **Karpathy#3 surgical** + **Tacit#3 idiom**（subcommand dispatch 沿用 tidy-handoff 既有 for-loop case；atomic rollback 沿用 migrate-to-v2 既有 `.partial` + EXIT trap）。
- **Gotcha #15 root-safe**：chmod 类负控 `[ "${EUID:-$(id -u)}" -eq 0 ]` skip 镜像 B7-a / per-suite c5。
- **Gotcha #20 dogfood**：合成 fixture **必须** 配 real-repo 拷贝快照（不碰 live 仓）。
- **Gotcha #25**：guard 键 gate 判决非诊断 echo；机械派生禁手工枚举。

## 文件结构

- **Modify** `scripts/tidy-handoff.sh`(+bundle) — 添加 first-arg `schema-upgrade` 子命令 dispatch（在现 `for arg in "$@"` 前；不动既有逻辑）。
- **Create** `scripts/lib/handoffx-tidy-migrate.sh`(+bundle) — 迁移核心：`detect_schema_state` / `preflight_check` / `migrate_apply` / `rewrite_path_strings` / `cleanup_partials` / EXIT trap。LEAVE 类脚本基名（T1）。
- **Create** `skills/handoff/command-shims/handoffx-tidy.md` — `/handoffx-tidy` 命令 shim 调 `tidy-handoff.sh schema-upgrade`。
- **Create** `tests/test_handoffx_tidy.sh` — migrate-to-v2 风格的迁移测试套件。
- **Create** `tests/fixtures/p2-1-synthetic-v2/...` — 合成 v2 旧 schema fixture（最小化：1 HANDOFF.md + 2 Dev Log + 1 Decision + 1 Gotcha + 内部 xref 字面路径串）。
- **Modify** `scripts/lib/handoff-schema.sh`(+bundle) — **不动**（HX_* 常量值此期仍 v2 旧，仅 P2.2 才 swap）；迁移器目标路径 = 当前的 v2 旧（Handoff_Logs 等），新路径 = 派生自 schema swap 假设（HANDOFFX.md / Handoffx_Logs/ 等）。**关键**：迁移器接受 `--target-schema-source` 参数（默认 `schema-swapped 副本`），P2.4 终阶才传 live schema source；P2.1 测试用临时 swapped fixture。

## 阶段依赖

- P2.0 已 ship（schema 单源 + load-bearing baseline-ratchet guard）→ P2.1 跑在其上
- P2.1 ship 后 → P2.2 改名 hard-cut（仍 gated 待 Boss）
- P2.4 终阶自迁移用本 P2.1 产物（仍 gated）

---

## 阶段任务

### Task 1：subcommand dispatch 骨架 + 新测试套件起点

**Files:** Modify `scripts/tidy-handoff.sh`(+bundle)；Create `tests/test_handoffx_tidy.sh`、`skills/handoff/command-shims/handoffx-tidy.md`

- [ ] **Step 1: 写失败测试** `tests/test_handoffx_tidy.sh`

```bash
#!/bin/bash
# P2.1 /handoffx-tidy schema 迁移器测试。
ROOT=$(cd "$(dirname "$0")/.." && pwd); . "$ROOT/tests/common.sh"
SCRIPT="$ROOT/scripts/tidy-handoff.sh"
SHIM="$ROOT/skills/handoff/command-shims/handoffx-tidy.md"
assert_file_exists "tidy-handoff.sh 存在" "$SCRIPT"
# 1. subcommand 识别 + --help 输出
out=$("$SCRIPT" schema-upgrade --help 2>&1) || true
assert_contains "$out" "schema-upgrade" "subcommand identifies itself in --help"
assert_contains "$out" "handoffx" "help references handoffx schema"
# 2. command-shim 存在
assert_file_exists "handoffx-tidy shim 存在" "$SHIM"
# 3. shim 指向 schema-upgrade subcommand
assert_contains "$(cat "$SHIM")" "tidy-handoff.sh schema-upgrade" "shim invokes subcommand"
summary
```

- [ ] **Step 2: 跑验证失败** `bash tests/test_handoffx_tidy.sh` → Expected: FAIL（schema-upgrade 未识别 + shim 缺失）

- [ ] **Step 3: 在 `scripts/tidy-handoff.sh` 添加 subcommand dispatch**

在现 `APPLY_FLAG=0` 行之前（约 line 25）插入：

```bash
# P2.1 subcommand dispatch：`tidy-handoff.sh schema-upgrade ...` → handoffx schema migrator
# (P2.1, Decision 0019/0020/0025；Boss 2026-05-21 Q1 拍板 subcommand 模式)
if [ "${1:-}" = "schema-upgrade" ]; then
    shift
    . "$(dirname "$0")/lib/handoffx-tidy-migrate.sh"
    handoffx_tidy_main "$@"
    exit $?
fi
```

- [ ] **Step 4: 创建占位 helper lib** `scripts/lib/handoffx-tidy-migrate.sh`（Task 2 实现）

```bash
#!/bin/bash
# handoffx-tidy-migrate.sh — schema 迁移核心：v2 旧四件套 → handoffx schema。
# Sourced by tidy-handoff.sh schema-upgrade subcommand. LEAVE class basename.
# Decision 0019/0020/0025 P2.1。

handoffx_tidy_main() {
    case "${1:-}" in
        -h|--help|"")
            cat <<'EOF'
Usage: tidy-handoff.sh schema-upgrade [--dry-run|--apply] [--root <dir>]
       tidy-handoff.sh schema-upgrade --help

P2.1 schema 迁移：v2 旧四件套（HANDOFF.md/Handoff_Logs/Handoff_Decisions/）→ handoffx
schema（值由 schema source 派生；P2.2 改名后自动跟随）。仅 v2 schema marker 存在时触发；
已 handoffx → no-op（幂等）。

Options:
  --dry-run    报告将做的迁移，不动文件（默认）
  --apply      原子应用迁移（.partial staging + EXIT-trap rollback）
  --root DIR   项目根（默认 PWD）
Exit: 0 ok or no-op / 1 preflight fail / 2 mid-migration fail (rolled back)
EOF
            return 0
            ;;
    esac
    echo "❌ Task 2 实现中" >&2; return 1
}
```

- [ ] **Step 5: 创建 command-shim** `skills/handoff/command-shims/handoffx-tidy.md`

```markdown
# /handoffx-tidy — P2.1 schema 迁移器

把 v2 旧四件套（HANDOFF.md / Handoff_Logs/ / Handoff_Decisions/）迁移到 handoffx schema
（HANDOFFX.md / Handoffx_Logs/ / Handoffx_Decisions/；GOTCHAS.md 不变 ADR-0005 LEAVE）。

由 `tidy-handoff.sh schema-upgrade` subcommand 实现（Q1 2026-05-21 Boss 拍板 subcommand 模式；
脚本基名 `tidy-handoff.sh` LEAVE T1）。

调用：
```bash
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --help
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --dry-run --root <project-dir>
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --apply --root <project-dir>
```

约束：幂等 / 双平台 / 原子回滚 / root-safe（Gotcha #15）。详见 `docs/2026-05-21-p2-1-...plan.md`。
```

- [ ] **Step 6: 镜像 bundle** `cp scripts/tidy-handoff.sh skills/handoff/scripts/tidy-handoff.sh; cp scripts/lib/handoffx-tidy-migrate.sh skills/handoff/scripts/lib/handoffx-tidy-migrate.sh`

- [ ] **Step 7: 跑验证通过** `bash tests/test_handoffx_tidy.sh` → 4/4 GREEN；`bash tests/run_all.sh` → 33 套件（新加 test_handoffx_tidy）；机械重基线 510→新值（per-suite-count-drift-guard-plan Task 5 范式）。

- [ ] **Step 8: commit**

```bash
git add scripts/tidy-handoff.sh scripts/lib/handoffx-tidy-migrate.sh \
  skills/handoff/scripts/tidy-handoff.sh skills/handoff/scripts/lib/handoffx-tidy-migrate.sh \
  skills/handoff/command-shims/handoffx-tidy.md \
  tests/test_handoffx_tidy.sh \
  <rebaselined files per git status>
git commit -m "feat(p2.1): tidy-handoff schema-upgrade subcommand skeleton + handoffx-tidy shim (Q1 subcommand mode)"
```

### Task 2：迁移核心 + 合成 fixture（detect / preflight / rename / atomic staging）

**Files:** Modify `scripts/lib/handoffx-tidy-migrate.sh`(+bundle)；Create `tests/fixtures/p2-1-synthetic-v2/...`；Extend `tests/test_handoffx_tidy.sh`

- [ ] **Step 1: 创建合成 fixture** `tests/fixtures/p2-1-synthetic-v2/`

最小化 v2 旧 schema 树（mkdir + 写 HANDOFF.md + 写 2 Dev Log + 1 Decision + 1 Gotcha + 内部 xref 字面路径串）；带 v2 marker `<!-- HANDOFF v2 schema -->`。

- [ ] **Step 2: 加 detect/preflight/dry-run 测试**

```bash
# Task 2 / Step 2: dry-run 报告应列出 4 类迁移 locus，不动 fixture
FX=$(mktemp -d); cp -r tests/fixtures/p2-1-synthetic-v2/. "$FX/"
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX" 2>&1); rc=$?
assert_exit "dry-run exit 0 on v2 fixture" 0 "$rc"
assert_contains "$out" "HANDOFF.md → HANDOFFX.md" "dry-run 报主文件改名"
assert_contains "$out" "Handoff_Logs/ → Handoffx_Logs/" "dry-run 报 logs dir 改名"
[ -f "$FX/HANDOFF.md" ] || fail "dry-run 不应改 fixture"
[ ! -d "$FX/Handoffx_Logs" ] || fail "dry-run 不应建 Handoffx_Logs/"
rm -rf "$FX"
# 幂等：已 handoffx schema 树 → 报 no-op
FX2=$(mktemp -d); mkdir -p "$FX2/Handoffx_Logs" "$FX2/Handoffx_Decisions"
touch "$FX2/HANDOFFX.md"; echo '<!-- HANDOFFX v3 schema -->' > "$FX2/HANDOFFX.md"
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX2" 2>&1); rc=$?
assert_exit "已迁移 → no-op exit 0" 0 "$rc"
assert_contains "$out" "no-op" "幂等：已 handoffx 报 no-op"
rm -rf "$FX2"
```

- [ ] **Step 3: 实现 `detect_schema_state` + `preflight_check`**

`handoffx-tidy-migrate.sh` 加：
- `detect_schema_state(root)`: 检 `<!-- HANDOFF v2 schema -->` marker + 兄弟目录存在；分三态 `OLD-V2 / ALREADY-HANDOFFX / UNKNOWN`。
- `preflight_check(root)`: 验 4 类源路径全在；目标路径全不存在（`assert_dest_clear` 范式）；权限可写。

- [ ] **Step 4: 实现 dry-run 输出**

`handoffx_tidy_main` 解析 `--dry-run`/`--apply`/`--root`；调 detect+preflight；dry-run 模式仅 echo 计划，不动盘。

- [ ] **Step 5: 跑验证**：dry-run + 幂等测试 GREEN；既有套件不回归；双源 byte-equal；机械重基线（若 assert 数变）。

- [ ] **Step 6: commit** `git commit -am "feat(p2.1): schema-upgrade detect+preflight+dry-run with synthetic fixture (idempotent no-op verified)"`

### Task 3：apply 模式 — 原子 rename + .partial staging + EXIT trap rollback

**Files:** Modify `scripts/lib/handoffx-tidy-migrate.sh`(+bundle)；Extend `tests/test_handoffx_tidy.sh`

- [ ] **Step 1: 加 apply + rollback 测试**

```bash
# Task 3 / Step 1: apply on synthetic fixture → HANDOFFX.md/Handoffx_*/ 都到位
FX=$(mktemp -d); cp -r tests/fixtures/p2-1-synthetic-v2/. "$FX/"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX" 2>&1); rc=$?
assert_exit "apply on v2 fixture exit 0" 0 "$rc"
[ -f "$FX/HANDOFFX.md" ] || fail "apply 应产生 HANDOFFX.md"
[ -d "$FX/Handoffx_Logs" ] || fail "apply 应产生 Handoffx_Logs/"
[ -d "$FX/Handoffx_Decisions" ] || fail "apply 应产生 Handoffx_Decisions/"
[ ! -f "$FX/HANDOFF.md" ] || fail "apply 应移走旧 HANDOFF.md"
[ ! -d "$FX/Handoffx_Logs.partial" ] || fail "apply 完成后应清掉 .partial"
rm -rf "$FX"
# rollback：注入 mid-migration 失败 → 旧四件套不变
FX2=$(mktemp -d); cp -r tests/fixtures/p2-1-synthetic-v2/. "$FX2/"
# inject: 让 Decisions 目录改名失败（pre-create collision）
mkdir -p "$FX2/Handoffx_Decisions"; touch "$FX2/Handoffx_Decisions/_collision"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX2" 2>&1); rc=$?
[ "$rc" -ne 0 ] || fail "rollback: 注入冲突应 exit 非零"
[ -f "$FX2/HANDOFF.md" ] || fail "rollback: 旧 HANDOFF.md 应保留"
[ -d "$FX2/Handoff_Logs" ] || fail "rollback: 旧 Handoff_Logs/ 应保留"
[ ! -f "$FX2/HANDOFFX.md" ] || fail "rollback: 不应留下半迁移 HANDOFFX.md"
rm -rf "$FX2"
```

- [ ] **Step 2: 实现 `migrate_apply` + `cleanup_and_maybe_rollback`**

镜像 `migrate-to-v2.sh:56-140` 范式：
- `*.partial` staging（先把所有目标产物造在 `.partial` 路径）
- `MIGRATE_DONE` 标志位
- `trap cleanup_and_maybe_rollback EXIT`（trap **安装在 preflight 之后**，避免 preflight-only abort 误触发回滚）
- 成功后 `mv .partial → final`，flip `MIGRATE_DONE=1`
- 失败时 trap 删除 `.partial`、恢复源文件

- [ ] **Step 3: stale `.partial` 清理**（preflight 时检测前次 killed-run 残留）

`preflight_check` 找到 `${HX_*}.partial` / `*.new` 残留时报错并指引用户清理；不自动 rm（用户可能正在 inspect）。

- [ ] **Step 4: 跑验证**：apply happy + rollback 注入冲突 + stale-partial 检出 全 GREEN；run_all 全绿。

- [ ] **Step 5: commit** `git commit -am "feat(p2.1): schema-upgrade apply mode with atomic .partial staging + EXIT-trap rollback (migrate-to-v2 范式)"`

### Task 4：全 .md 字面路径串重写（Q2 全扫范围）

**Files:** Modify `scripts/lib/handoffx-tidy-migrate.sh`(+bundle)；Extend `tests/test_handoffx_tidy.sh`、`tests/fixtures/p2-1-synthetic-v2/...`

- [ ] **Step 1: 扩 fixture 加 内部 xref 字面路径串**

在 HANDOFF.md prose 与 Dev Log/Decision 内容加：
- `详见 Handoff_Logs/0001-2026-04-20-foo.md`
- `Decision: Handoff_Decisions/0001-2026-04-20-bar.md`
- `HANDOFF.md` 字面（如 `修改了 HANDOFF.md 第 N 行`）
- `HANDOFF.archive.md`（archive 派生）

- [ ] **Step 2: 加 xref 重写测试**

```bash
# Task 4 / Step 2: apply 后 .md 内字面路径串重写
FX=$(mktemp -d); cp -r tests/fixtures/p2-1-synthetic-v2/. "$FX/"
"$SCRIPT" schema-upgrade --apply --root "$FX" >/dev/null 2>&1
grep -q "Handoffx_Logs/0001-2026-04-20-foo.md" "$FX/HANDOFFX.md" \
  || fail "HANDOFFX.md prose 应含 Handoffx_Logs/ 重写后的引用"
grep -q "Handoffx_Decisions/0001-2026-04-20-bar.md" "$FX/HANDOFFX.md" \
  || fail "HANDOFFX.md prose 应含 Handoffx_Decisions/ 重写后的引用"
! grep -q "Handoff_Logs/" "$FX/HANDOFFX.md" \
  || fail "HANDOFFX.md prose 不应残留旧 Handoff_Logs/ 字面"
# Dev Log 内容也应重写（per Q2 全扫）
grep -q "Handoffx_Logs/" "$FX/Handoffx_Logs/0001-"*.md \
  || fail "Dev Log 内字面路径串应重写"
# GOTCHAS.md 不动（ADR-0005 LEAVE，无 handoff token 但若含字面路径串也重写）
[ -f "$FX/GOTCHAS.md" ] || fail "GOTCHAS.md 应保留原名"
rm -rf "$FX"
```

- [ ] **Step 3: 实现 `rewrite_path_strings`**

机械扫所有 `*.md`（root + Handoffx_Logs/ + Handoffx_Decisions/ + 必要时 docs/）：
- `Handoff_Logs/` → `Handoffx_Logs/`（substring，无 word-boundary，因路径分隔符 `/` 已是非词字符）
- `Handoff_Decisions/` → `Handoffx_Decisions/`
- `HANDOFF.archive.md` → `HANDOFFX.archive.md`（必须先匹配，因 `HANDOFF.md` 是 substring！）
- `HANDOFF.md` → `HANDOFFX.md`（后匹配）
- 用 `sed -i.bak`（macOS+Linux 兼容）+ trap 清 `.bak`；保留 GOTCHAS.md 字面（无 token）。

写入应在 `.partial` 阶段（Task 3 的 staging 内），与 rename 同事务。

- [ ] **Step 4: 跑验证**：xref 重写 + 既有 apply/rollback 全 GREEN；run_all 全绿。

- [ ] **Step 5: commit** `git commit -am "feat(p2.1): full .md sweep path-string rewrite (Q2 Boss-decided; xref accuracy preserved)"`

### Task 5：real-repo 拷贝快照 dogfood（Gotcha #20）

**Files:** Extend `tests/test_handoffx_tidy.sh`

- [ ] **Step 1: 加 dogfood 测试**

```bash
# Task 5 / Step 1: real-repo 拷贝快照（不动 live；Gotcha #20）
DOGFOOD=$(mktemp -d)
# 仅拷四件套（不拷整 repo——避免 binary/big 文件干扰）
cp "$ROOT/HANDOFF.md" "$DOGFOOD/"
cp "$ROOT/GOTCHAS.md" "$DOGFOOD/"
cp -r "$ROOT/Handoff_Logs" "$DOGFOOD/"
cp -r "$ROOT/Handoff_Decisions" "$DOGFOOD/"

out=$("$SCRIPT" schema-upgrade --apply --root "$DOGFOOD" 2>&1); rc=$?
assert_exit "real-repo 拷贝 apply exit 0" 0 "$rc"
[ -f "$DOGFOOD/HANDOFFX.md" ] || fail "real-repo dogfood: HANDOFFX.md 应在"
[ -d "$DOGFOOD/Handoffx_Logs" ] || fail "real-repo dogfood: Handoffx_Logs/ 应在"
# 数量等价
local_logs=$(ls "$ROOT/Handoff_Logs" | wc -l)
moved_logs=$(ls "$DOGFOOD/Handoffx_Logs" | wc -l)
[ "$local_logs" -eq "$moved_logs" ] || fail "real-repo dogfood: Dev Log 数量不一致 $local_logs vs $moved_logs"
# xref 重写完整：HANDOFFX.md 不应残留任何 'Handoff_Logs/'
! grep -q "Handoff_Logs/" "$DOGFOOD/HANDOFFX.md" \
  || fail "real-repo dogfood: HANDOFFX.md 仍含 Handoff_Logs/ 残留"
rm -rf "$DOGFOOD"
```

- [ ] **Step 2: 跑验证**：dogfood 测试 GREEN；run_all 全绿；机械重基线（若 assert 数变）。

- [ ] **Step 3: root-safe 测试**（Gotcha #15）：若涉 chmod 类负控（如 readonly root 测 preflight 失败），用 `[ "${EUID:-$(id -u)}" -eq 0 ]` skip 镜像 B7-a。

- [ ] **Step 4: commit** `git commit -am "test(p2.1): real-repo snapshot dogfood (Gotcha #20 mandate) + root-safe Gotcha #15 skip"`

### Task 6：三异构源评审 + 阶段收口（Boss 门，强 P2.1 不可逆类）

- [ ] **Step 1: controller 机械对抗全链**
  - schema-swap 端到端：用 fixture + temp swap schema source 试模拟 P2.4 真迁移路径，验迁移器输出与预期匹配
  - reverse-migration mutation：让 fixture 含 corrupted state（半 Handoffx_Logs + 半 Handoff_Logs） → preflight 应 RED
  - dual-platform spot check：mawk regex / bash 3.2 / sed `-i.bak` macOS+Linux 一致
  - P2.0 baseline-ratchet guard 验：新代码引入的字面 `Handoff_Logs` 等（在新 helper lib + 测试 fixture）必须 (a) 在 schema source 派生范畴 或 (b) 在 fixture 路径下（test fixtures 不在 gen_stray scope，但若 helper lib 含字面则会被抓）。控制：helper lib 全用 `$HX_*` 派生 + fixture 内字面 OK。

- [ ] **Step 2: opus code-reviewer**（cumulative P2.1 diff）：正确性 / Tacit#3 idiom / 双源 byte-equal / Karpathy#3 surgical / migrate-to-v2 范式对齐。

- [ ] **Step 3: silent-failure-hunter**：fail-open lens；特别审 atomic rollback 路径（Gotcha #24 母题：half-migrated state 静默 GREEN 风险）+ stale `.partial` 检测路径。

- [ ] **Step 4: Codex 第3源**（`disable-model-invocation`，**controller 不能自调，须 Boss 触发**——诚实声明）：挑战 approach / assumption（特别：subcommand vs 独立脚本 / 全扫 vs LIVE-state-only / atomic rollback 边界）。

- [ ] **Step 5: 每 finding TDD 闭 + controller 独立机械复现** + run_all 全绿 + baseline-ratchet 持续守门 0 leaks。

- [ ] **Step 6: P2.1 收口报告 + Boss 门**（**用户指令硬门覆盖 continuous-execution**）：
  - 暂停等 Boss 授权 commit/push T6（migrate-to-v2 范式：P2.1 = 不可逆类 = 推 private Git host 私有需明文）
  - 暂停等 Boss 进 P2.2（标识符 + scope-edge 改名 hard-cut；Decision 0019/0020 锁定序，controller 不从「continue」推断）

---

## Self-Review

**1. Spec coverage**：
- master design §3 P2.1 契约（subcommand / 幂等 / 双平台 / 原子回滚 / root-safe / 有测试 / GOTCHAS.md 不动 / xref 重写）→ Task 1（subcommand 骨架 + shim）/ Task 2（detect+preflight+dry-run 幂等）/ Task 3（apply+atomic+rollback）/ Task 4（xref 重写 Q2）/ Task 5（dogfood）覆盖完。
- Q1 subcommand 决策 → Task 1 Step 3+5 显式实现。
- Q2 全扫重写 → Task 4 全程聚焦。
- Decision 0025 5 阶段方案 A 中 P2.1 contract → 全任务对齐。
- T1-T7 不变式 + Gotcha #15/#20/#25 → 不变式节 + Task 5/6 显式覆盖。
**2. Placeholder scan**：每 Task step 含真实代码块/命令/期望；无 TBD/TODO。
**3. Type consistency**：函数名 `handoffx_tidy_main` / `detect_schema_state` / `preflight_check` / `migrate_apply` / `rewrite_path_strings` / `cleanup_and_maybe_rollback` 跨任务一致；`$HX_*` 派生常量沿用 P2.0 schema-source。
**4. 修复**（inline）：Task 4 Step 3 强调 `HANDOFF.archive.md` 必须先于 `HANDOFF.md` 替换（否则 substring 先匹配会把 `HANDOFF.archive.md` 改成 `HANDOFFX.archive.md` 再被 `HANDOFF.md→HANDOFFX.md` 误踩——已 inline 注明替换顺序）。

---

## 执行链

writing-plans（本 plan，2026-05-21）→ subagent-driven-development（6 任务 fresh implementer/任务 + 两段审 + controller 机械对抗 + Task 6 三异构源）。spec 审门 = 本 plan + Decision 0025 + master design §3；§4 push 门 + P2.2 进阶门非可豁免（Boss 明文）。
