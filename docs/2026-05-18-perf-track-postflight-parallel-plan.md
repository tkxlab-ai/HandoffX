# Postflight 编排层并行化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `handoff-postflight.sh` 的 6 个 sub-check 从串行求和改为「5 个只读 check 并行 + archive-devlog 串行殿后」，墙钟较串行显著下降，fail-closed 聚合零退化。

**Architecture:** 仅改 `scripts/handoff-postflight.sh`（+ 其 repo 内双源副本 byte-equal），5 个 sub-check 脚本零改动。`run_check` 现已把每 check 输出缓冲到 `mktemp` 文件——改为：rc 写 `$TMP/<n>.rc`、out 留 `$TMP/<n>.out` 不即删；read-only check {1,2,3,4,6} 后台并行；mutating check {5 archive-devlog} 在 `wait` 后串行殿后（规避与只读 check 读同目录 race）；固定顺序回放 out；聚合 `exit 1` 当任一 rc≠0 _或_ 任一 rc 文件缺失。

**Tech Stack:** bash 3.2（macOS 默认，纯 `wait` + rc 文件，不用 `wait -n`/关联数组）；`mktemp -d` + `trap` 清理；test harness = `tests/common.sh`（`assert_exit`/`assert_contains`），run_all 自动发现 `test_*.sh`（`tests/run_all.sh:4`）。

**Spec:** `docs/2026-05-18-perf-track-postflight-parallel-design.md`（Boss 已批准）。注：spec §2 基线（7.4s/5 check）测自陈旧已安装副本；真实 repo 内脚本是 6 check（含 B① xref-lint，conditional on `--files=`），plan Task 1 先对正确 in-repo 脚本重锚基线。

---

### Task 1: 测试骨架 + 真实基线锚定 + fail-closed 不变式 RED

**Files:**
- Create: `tests/test_handoff_postflight_parallel.sh`
- Reference (read-only): `scripts/handoff-postflight.sh`（当前串行版）

- [ ] **Step 1: 写 fail-closed 不变式失败测试**

创建 `tests/test_handoff_postflight_parallel.sh`：

```bash
#!/bin/bash
# test_handoff_postflight_parallel.sh — 性能轨 Spec D：postflight 编排并行化 TDD。
# 不变式核心：并行后 fail-closed 聚合不退化（Gotcha #24 母题）。
source "$(dirname "$0")/common.sh"

PF="$SCRIPTS_DIR/handoff-postflight.sh"
WORK="$TMP_DIR/pf-par-$$"
rm -rf "$WORK"; mkdir -p "$WORK/Handoff_Logs" "$WORK/Handoff_Decisions"
trap 'rm -rf "$WORK"' EXIT

# 最小 v2 四件套 fixture（postflight 默认 file=HANDOFF.md，ROOT_DIR=dirname）
printf '<!-- HANDOFF v2 schema -->\n# H\n## 📦 Project Overview\nx\n## 🎯 Current State\nx\n' > "$WORK/HANDOFF.md"
printf '### Gotcha #1 — x [runtime]\nx\n' > "$WORK/GOTCHAS.md"

assert_file_exists "postflight exists" "$PF"

# 标记：标识 postflight 已是并行编排版（Task 2 引入；此处先 RED）
assert_contains "postflight has parallel-orchestration marker" \
  "$(grep -c 'PARALLEL-ORCHESTRATION' "$PF" 2>/dev/null || echo 0 | tr -d "\n")" "1"
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `bash tests/test_handoff_postflight_parallel.sh`
Expected: FAIL — "postflight has parallel-orchestration marker"（当前脚本无该标记）

- [ ] **Step 3: 锚定真实串行基线（测量，非断言）**

Run（正确调用：positional=HANDOFF.md，含 B① 写目标）：
```bash
nl=$(ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -1)
{ time bash scripts/handoff-postflight.sh HANDOFF.md --files="HANDOFF.md,$nl" --quiet ; } 2>&1 | tail -2
```
Expected: 记录 `real` 秒数为基线 B_serial（写进 commit message）。同时 `time` 单测每个 check 取最慢单值 M_max。成功目标 = 并行墙钟 ≤ max(M_max, B_serial×0.55)（相对判据，spec §1）。

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_postflight_parallel.sh
git commit -m "test(perf): postflight parallel-orchestration RED + serial baseline anchor

baseline B_serial=<秒> M_max=<最慢单 check 秒>(in-repo 6-check 脚本,非陈旧已安装副本)
fail-closed 不变式测试先 RED — Spec D docs/2026-05-18-perf-track-postflight-parallel-design.md"
```

---

### Task 2: 并行编排 + 归档殿后 + fail-closed 聚合（GREEN）

**Files:**
- Modify: `scripts/handoff-postflight.sh:84-134`（`run_check` + check 调用段 + 聚合段）
- Mirror: `skills/handoff/scripts/handoff-postflight.sh`（Task 4 做 byte-equal 同步）

- [ ] **Step 1: 改 `run_check` 为 rc/out 落文件、不即删**

把 `scripts/handoff-postflight.sh:84-103` 的 `run_check()` 替换为（保留 verbose/quiet 行为，新增 rc/out 持久化到 `$PF_TMP`）：

```bash
PF_TMP=$(mktemp -d)
trap 'rm -rf "$PF_TMP"' EXIT

# PARALLEL-ORCHESTRATION: rc/out 落 $PF_TMP，不即删，供 wait 后回放+聚合
run_check() {
    local n="$1" name="$2"
    shift 2
    local ec=0
    "$@" >"$PF_TMP/$n.out" 2>&1 || ec=$?
    echo "$ec" > "$PF_TMP/$n.rc"
    echo "$name" > "$PF_TMP/$n.name"
}
```

- [ ] **Step 2: 改 check 调用段为「只读并行 + 归档殿后」**

把 `scripts/handoff-postflight.sh:105-124`（5 个 run_check + B① 块）替换为：

```bash
# 只读 check 后台并行（1 scan-credentials / 2 validate / 3 lint / 4 rotation）
run_check 1 "scan-credentials"  bash "$SCRIPT_DIR/scan-credentials.sh"  "$ROOT_DIR" &
run_check 2 "validate-handoff"  bash "$SCRIPT_DIR/validate-handoff.sh"  --readiness "$FILE" &
run_check 3 "handoff-lint"      bash "$SCRIPT_DIR/handoff-lint.sh"      "$FILE" &
run_check 4 "rotation-reminder" bash "$SCRIPT_DIR/rotation-reminder.sh" "$FILE" &

# B① xref-lint（只读 lint，可并行）。空 --files= = broken caller，须 fail-fast
# 先于并行结束（保留当前 exit 2 语义，不进聚合）
if [ "${FILES_CSV_SET:-0}" = "1" ] && [ -z "$FILES_CSV" ]; then
    echo "❌ postflight: --files= given but empty (broken write-target set)" >&2
    wait; rm -rf "$PF_TMP"; trap - EXIT
    exit 2
fi
if [ -n "${FILES_CSV:-}" ]; then
    _IFS_SAVE=$IFS; set -f; IFS=','; set -- $FILES_CSV; set +f; IFS=$_IFS_SAVE
    run_check 6 "xref-lint(B①)" bash "$SCRIPT_DIR/handoff-xref-lint.sh" "$@" &
fi

wait   # 墙钟 = max(单只读 check)，非 sum

# archive-devlog 串行殿后：它 mv Dev Log 文件，与只读 check 读同目录会 race
run_check 5 "archive-devlog"    bash "$SCRIPT_DIR/archive-devlog.sh"    "$FILE"
```

- [ ] **Step 3: 改聚合段为 fail-closed（rc 缺失=失败）**

把 `scripts/handoff-postflight.sh:126-134` 替换为：

```bash
[ "$QUIET" = "0" ] && echo

fail_count=0
fail_list=""
# 固定顺序回放 + 聚合。rc 文件缺失 = worker 半死 → 当失败，绝不默认 pass
for n in 1 2 3 4 6 5; do
    [ -f "$PF_TMP/$n.rc" ] || { [ "$n" = 6 ] && [ -z "${FILES_CSV:-}" ] && continue; }
    if [ ! -f "$PF_TMP/$n.rc" ]; then
        fail_count=$((fail_count + 1)); fail_list="$fail_list check#$n(no-rc)"; continue
    fi
    nm=$(cat "$PF_TMP/$n.name" 2>/dev/null || echo "check#$n")
    rc=$(cat "$PF_TMP/$n.rc")
    if [ "$QUIET" = "0" ]; then
        echo "→ ${n}. ${nm}"
        if [ "$rc" = "0" ]; then echo "   ✅"
        else echo "   ❌ exit=$rc"; [ -s "$PF_TMP/$n.out" ] && sed 's/^/   /' "$PF_TMP/$n.out"; fi
    fi
    [ "$rc" = "0" ] || { fail_count=$((fail_count + 1)); fail_list="$fail_list $nm"; }
done

rm -rf "$PF_TMP"; trap - EXIT

if [ "$fail_count" = "0" ]; then
    echo "✅ postflight: all checks passed"
    exit 0
else
    echo "❌ postflight: $fail_count check(s) failed:$fail_list"
    exit 1
fi
```

- [ ] **Step 4: 删旧的内联聚合残留 + 跑 Task 1 测试确认 GREEN**

确认 `scripts/handoff-postflight.sh` 不再有旧 `fail_count`/`fail_list` 早定义（原 76-79 行块删除，仅保留并行版聚合）。

Run: `bash tests/test_handoff_postflight_parallel.sh`
Expected: PASS — parallel-orchestration marker 命中

- [ ] **Step 5: Commit**

```bash
git add scripts/handoff-postflight.sh tests/test_handoff_postflight_parallel.sh
git commit -m "perf(postflight): parallelize 5 read-only checks, archive-devlog serial殿后

7.4s 串行求和 → max(单 check)。fail-closed 聚合:任一 rc≠0 或 rc 缺失→exit 1
(Gotcha #24 母题:worker 半死不默认 pass)。archive-devlog mv 文件→串行规避 race。
Spec docs/2026-05-18-perf-track-postflight-parallel-design.md"
```

---

### Task 3: 负控——并行下 fail-closed 不退化

**Files:**
- Modify: `tests/test_handoff_postflight_parallel.sh`（追加负控断言，在 Task 1 内容之后、`summary` 之前）

- [ ] **Step 1: 写两条负控失败测试**

在 `tests/test_handoff_postflight_parallel.sh` 末尾追加：

```bash
# 负控 A：注入一个必失败 check → 整体仍 exit 1（并行下 fail-closed）
bad="$WORK/Handoff_Logs/9999-2026-99-99T9999-bad.md"   # 非法日期 → handoff-lint 必报
printf 'x\n' > "$bad"
( cd "$WORK" && bash "$PF" HANDOFF.md --files="HANDOFF.md" >/dev/null 2>&1 ); rc_bad=$?
assert_exit "并行下 lint 失败 → 整体 exit 1" 1 "$rc_bad"
rm -f "$bad"

# 负控 B：模拟 worker 不写 rc（patch 一个临时 wrapper 让 check 3 跳过 rc）
# 用 PF_TMP 注入观测：postflight 跑后若人为删 rc 文件不可行（进程内）；
# 改为断言聚合逻辑显式存在 no-rc 分支
assert_contains "聚合含 rc-缺失=失败 分支" \
  "$(grep -c 'no-rc' "$PF" | tr -d "\n")" "1"

# 负控 C：archive-devlog 串行殿后（不与只读 check 并行）
assert_contains "archive-devlog 在 wait 之后" \
  "$(awk '/^wait$/{w=NR} /archive-devlog/{a=NR} END{print (a>w)?"yes":"no"}' "$PF")" "yes"
```

- [ ] **Step 2: 跑确认全 PASS**

Run: `bash tests/test_handoff_postflight_parallel.sh`
Expected: PASS — 负控 A（真实注入坏文件 → exit 1）、B（no-rc 分支存在）、C（顺序断言）全绿。负控 A 是 load-bearing：回退 Task 2 的并行段到串行版它仍应 PASS（fail-closed 是语义不变式，非并行引入），但回退聚合段去掉 no-rc 分支 → B RED（证 B load-bearing）。

- [ ] **Step 3: Commit**

```bash
git add tests/test_handoff_postflight_parallel.sh
git commit -m "test(perf): negative controls — parallel fail-closed 不退化

A 真实注入坏 Dev Log→exit 1 / B no-rc 分支存在(worker 半死=失败) / C 归档殿后顺序断言"
```

---

### Task 4: 输出逐字节等价 + 双源 byte-equal 同步

**Files:**
- Modify: `tests/test_handoff_postflight_parallel.sh`（追加等价断言）
- Mirror: `skills/handoff/scripts/handoff-postflight.sh` ← `scripts/handoff-postflight.sh`

- [ ] **Step 1: 写输出等价 + 双源测试**

追加到 `tests/test_handoff_postflight_parallel.sh`：

```bash
# --quiet 仅一行汇总（回放顺序固定保证汇总判定不变）
q_out=$( cd "$WORK" && bash "$PF" HANDOFF.md --files="HANDOFF.md" --quiet 2>&1 )
assert_exit "quiet 仅汇总单行" 1 "$([ "$(printf '%s\n' "$q_out" | grep -c .)" = 1 ] && echo 0 || echo 1)"
assert_contains "quiet 汇总含 postflight" "$q_out" "postflight:"

# verbose 固定顺序：1→2→3→4→6→5（回放顺序，不随并行调度抖动）
v_out=$( cd "$WORK" && bash "$PF" HANDOFF.md --files="HANDOFF.md" 2>&1 )
order=$(printf '%s\n' "$v_out" | grep -oE '^→ [0-9]' | grep -oE '[0-9]' | tr -d '\n')
assert_contains "verbose check 顺序确定 = 12346...5 尾" "$order" "5"
assert_exit "verbose 首四 check 顺序 1234" 0 \
  "$([ "$(printf '%s' "$order" | cut -c1-4)" = "1234" ] && echo 0 || echo 1)"

# 双源 byte-equal（test_scripts_sync 已强制；此处独立佐证）
assert_exit "根/skill postflight byte-equal" 0 \
  "$(diff -q "$SCRIPTS_DIR/handoff-postflight.sh" \
            "$(dirname "$SCRIPTS_DIR")/skills/handoff/scripts/handoff-postflight.sh" >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: 同步双源副本**

Run:
```bash
cp scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh
diff -q scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh && echo IDENTICAL
bash tests/test_scripts_sync.sh && echo "sync suite PASS"
```
Expected: IDENTICAL + sync suite PASS

- [ ] **Step 3: 跑确认 PASS + 全量 run_all**

Run: `bash tests/run_all.sh 2>&1 | tail -3`
Expected: All suites passed ✅（新 suite 已被 `run_all.sh:4` 自动发现）

- [ ] **Step 4: Commit**

```bash
git add scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh tests/test_handoff_postflight_parallel.sh
git commit -m "test(perf): output byte-equivalence + dual-source sync

--quiet 单行汇总 + verbose 固定回放顺序(并行调度不抖动) + 根/skill byte-equal"
```

---

### Task 5: 计数 locus 重同步 + 真实 dogfood 终验

**Files:**
- Modify: 计数 canonical loci（执行时先 grep 现总数确认行号，再 +N 新断言数）

- [ ] **Step 1: 数本 suite 新增断言数**

Run: `grep -cE '^\s*assert_' tests/test_handoff_postflight_parallel.sh`
记为 N_new。当前总数（执行时实测，勿凭记忆）：
```bash
grep -roE '[0-9]{3,4} (assertions|断言|tests)' HANDOFF.md README.md README_CN.md CONTRIBUTING.md TEST-SCENARIOS.md 2>/dev/null
```

- [ ] **Step 2: 同步全部 canonical loci**

对上一步 grep 命中的每个 locus，把旧总数替换为 旧+N_new + suite 数 +1。loci 集（执行时以 grep 实际命中为准，行号会漂）：`HANDOFF.md`（Testing 段 + Current State）、`README.md`、`README_CN.md`（中文镜像，勿漏）、`CONTRIBUTING.md`、`TEST-SCENARIOS.md`。每改一处 `grep` 复核落地。

- [ ] **Step 3: 真实 repo dogfood（Gotcha #20 强制）**

Run（对真实 repo，非合成 fixture）：
```bash
nl=$(ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -1)
{ time bash scripts/handoff-postflight.sh HANDOFF.md --files="HANDOFF.md,$nl" ; } 2>&1 | tail -3
```
Expected: ① `✅ postflight: all checks passed` exit 0 ② `real` ≤ max(M_max, B_serial×0.55)（Task 1 锚定的相对判据；若 validate-handoff 单值本身 >B_serial×0.55 则降级为「= max(单 check) 且较 B_serial 显著降」并记 §6 延后下一杠杆）③ 输出与改动前 verbose 内容等价（check 全绿、仅时序变）

- [ ] **Step 4: 全量回归 + 负控复核**

Run: `bash tests/run_all.sh 2>&1 | tail -2`
Expected: All suites passed ✅。再独立重跑一次确认非测量瞬态（claim≠fact：复合命令重叠会假报 Failing，干净重跑 ×2 才算数）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(perf): count-locus resync +N_new + real-repo dogfood 终验

postflight 墙钟 B_serial=<秒>→<秒>(降 X%);run_all 全绿;真实 repo exit 0 不退化"
```

---

### Task 6: 多源独立审（Gotcha #22/#24，§4 authoring/review 分离）

**Files:** 无（review-only）

- [ ] **Step 1: 源 1 — opus code-reviewer**

Dispatch `pr-review-toolkit:code-reviewer`（或 `code-reviewer` agent），focus = `git diff <Task1 前 SHA>..HEAD`。重点：并行 `wait` 退出码聚合是否真 fail-closed、`PF_TMP` trap 在 exit 2 早退路径是否清理、回放顺序是否真确定、双源是否 byte-equal、有无 scope 蔓延。

- [ ] **Step 2: 源 2 — silent-failure-hunter**

Dispatch `pr-review-toolkit:silent-failure-hunter`（fail-open 同 lens，异构）。重点对抗：worker 被 kill / 子 shell 崩 / 磁盘满 / `$PF_TMP` 不可写 / B① 空 --files= 早退 / archive-devlog 殿后失败——逐一确认 fail-closed（绝不静默 pass）。这是 Gotcha #24 直系地盘，必过。

- [ ] **Step 3: 源 3 — Codex stop-time**

`disable-model-invocation`，controller 无法自调（诚实声明，不伪称）。合并路径：Boss 可 `/codex:adversarial-review git diff <base>..HEAD` 补第 3 异构源。

- [ ] **Step 4: finding 处置纪律（§4 / Gotcha #19）**

reviewer finding 若严于本 plan scope 且属前序架构 → `git log <base>..HEAD -- <file>` 机械溯源，非本轮引入则升级 Decision 不 mid-cycle 修；属本并行编排自身逻辑洞 → scope 内修+负控。判据 = 机械溯源，不自我批准。

- [ ] **Step 5: 全绿后转 finishing**

全部 finding 闭合 + run_all 绿 + 真实 dogfood 达标 → 用 `superpowers:finishing-a-development-branch` 收尾（本仓直接在 main 工作流，按既有 §4 push 分离纪律：commit 本地，push 待 Boss 显式授权）。

---

## Self-Review（writing-plans 自查，已执行）

**1. Spec coverage:** spec §4.1 数据流 → Task 2；§4.2 fail-closed 不变式 → Task 2 Step 3 + Task 3；§4.3 兼容（bash3.2/trap）→ Task 2 Step 1；§5 六条测试判据 → Task 1（墙钟锚）/3（负控 A·B）/3 Step1 负控 C（race 顺序）/4（输出等价·双源）；§6 YAGNI 延后 → Task 6 Step 4 升级纪律 + Task 5 Step 3 判据降级路径。无 gap。

**2. Placeholder scan:** 无 TBD/TODO；N_new/B_serial/M_max 是执行时实测量（非占位，已给精确 grep/time 命令获取），符合「先实测不凭记忆」。计数 loci 行号显式标注「执行时 grep 实际命中为准」（行号确会漂，非偷懒）。

**3. Type consistency:** `PF_TMP`/`run_check n/name/rc/out` 命名 Task 2→3→4 一致；回放顺序 `1 2 3 4 6 5` 在 Task 2 Step 3 与 Task 4 Step 1 断言一致；`B_serial×0.55` 判据 Task 1/5 一致。

