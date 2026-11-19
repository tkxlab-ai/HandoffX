#!/bin/bash
# test_handoff_postflight_parallel.sh — 性能轨 Spec D：postflight 编排并行化 TDD。
# 不变式核心：并行后 fail-closed 聚合不退化（Gotcha #24 母题）。
source "$(dirname "$0")/common.sh"

PF="$SCRIPTS_DIR/handoff-postflight.sh"
WORK="$TMP_DIR/pf-par-$$"
rm -rf "$WORK"; mkdir -p "$WORK/$HX_LOGS_DIR" "$WORK/$HX_DEC_DIR"
trap 'rm -rf "$WORK"' EXIT

# 最小 v2 四件套 fixture（postflight 默认 file=$HX_MAIN_FILE，ROOT_DIR=dirname）
# $HX_MAIN_FILE 用 skill 模板：使 validate-handoff --readiness 过关（极简自写版缺
# Architecture / Development Log 等必填节 → readiness check 已 exit1 → 负控 A 空转）。
# Why 见 Gotcha #20 母题。
# Source and destination both follow $HX_MAIN_FILE: the shipped template is named after the main file it seeds
TEMPLATE="$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md"
assert_file_exists "skill template 存在" "$TEMPLATE"
cp "$TEMPLATE" "$WORK/$HX_MAIN_FILE"
printf '### Gotcha #1 — x [runtime]\nx\n' > "$WORK/$HX_GOTCHAS_FILE"

# Fix 2：为 $HX_LOGS_DIR/ 和 $HX_DEC_DIR/ 各加一个最小合规 dummy，
# 使 fixture 成为真实 v2 四件套——避免未来 Task 2/3 跑真实 postflight 时空目录
# 触发假绿（Gotcha #20/#24 母题）。文件名和 frontmatter 均遵循实际仓库惯例。
printf -- '---\nschema: 2\ntype: dev-log\ndate: 2026-05-18T00:00\nnumber: 0001\ntitle: fixture dummy log\n---\n\n### 2026-05-18 — fixture dummy\n\n**触发**：fixture\n\n**改动**：fixture\n\n**验证**：fixture\n\n**关联**：fixture\n' \
  > "$WORK/$HX_LOGS_DIR/0001-2026-05-18T0000-fixture-dummy-log.md"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-05-18\nnumber: 0001\ntitle: fixture dummy decision\n---\n\n### 2026-05-18 — fixture dummy\nx\n' \
  > "$WORK/$HX_DEC_DIR/0001-2026-05-18-fixture-dummy-decision.md"

assert_file_exists "postflight exists" "$PF"

# 标记：标识 postflight 已是并行编排版（Task 2 引入；此处先 RED）
# grep -c 无匹配打印 "0" 且 $() 自动剥尾换行，无需 `|| echo 0 | tr`。
assert_contains "postflight has parallel-orchestration marker" \
  "$(grep -c 'PARALLEL-ORCHESTRATION' "$PF" 2>/dev/null)" "1"

# 负控 A：真实注入坏 Dev Log → 整体 exit 1（fail-closed 并行下不退化）
# --files= 指向干净 dummy Dev Log（非模板 $HX_MAIN_FILE，后者含 <占位符> 会触发 B① xref-lint 误判）。
# 先断言 clean baseline exit 0（自锁：若 fixture 变脏，此断言先 RED，后续注入断言不再空转）。
# 注入后断言 exit 1：load-bearing 原因：bad.md 首行不是 `---`，
# lint_v2_entry 必报 "missing frontmatter"，handoff-lint exit 1。
GOODLOG="$WORK/$HX_LOGS_DIR/0001-2026-05-18T0000-fixture-dummy-log.md"
( bash "$PF" "$WORK/$HX_MAIN_FILE" --files="$GOODLOG" >/dev/null 2>&1 ); rc_clean=$?
assert_exit "负控A基线:clean fixture postflight 必 exit 0(否则后续注入断言空转)" 0 "$rc_clean"
bad="$WORK/$HX_LOGS_DIR/9999-2026-99-99T9999-bad.md"
printf 'x\n' > "$bad"
( bash "$PF" "$WORK/$HX_MAIN_FILE" --files="$GOODLOG" >/dev/null 2>&1 ); rc_bad=$?
assert_exit "负控A:注入坏 Dev Log → 整体 exit 1(并行下 fail-closed 不退化)" 1 "$rc_bad"
rm -f "$bad"

# 检查 5 对 v2 项目曾是空转：postflight 把 $FILE（$HX_MAIN_FILE）传给 archive-devlog
# → 文件模式 → v2 主文件内联条目恒 0 → 永远 exit 0，从不按年归档；而
# handoffx-write.md 步骤 5 承诺的是 `<project-root>` 目录模式。植一条 2023 的
# Dev Log：postflight 跑完它必须出现在 $HX_LOGS_DIR.archive/2023/。
OLDLOG="$WORK/$HX_LOGS_DIR/0000-2023-01-01T0000-ancient.md"
sed -e 's/^number: 0001$/number: 0000/' -e 's/^date: .*/date: 2023-01-01T00:00/' "$GOODLOG" > "$OLDLOG"
( bash "$PF" "$WORK/$HX_MAIN_FILE" --files="$GOODLOG" >/dev/null 2>&1 ); rc_arc=$?
assert_exit "检查5:含 2023 条目的 v2 fixture postflight 仍 exit 0" 0 "$rc_arc"
assert_file_exists "检查5:2023 条目被按年归档到 $HX_LOGS_DIR.archive/2023/" "$WORK/$HX_LOGS_DIR.archive/2023/0000-2023-01-01T0000-ancient.md"
# Codex stop-time（2026-10-29）：搬走条目后主文件指针若不刷新，下次 readiness 必炸。
# 归档后主文件的 最早一条 必须不再指向被搬走的 0000，共 N 条 必须等于剩余数。
assert_not_contains "检查5:归档后 最早一条 不再是被搬走的条目" "$(grep '^最早一条：' "$WORK/$HX_MAIN_FILE")" "0000-2023"
assert_contains "检查5:归档后 共 N 条 = 剩余 1 条" "$(grep -E '^共 [0-9]+ 条$' "$WORK/$HX_MAIN_FILE" | head -1)" "共 1 条"
rm -rf "$WORK/$HX_LOGS_DIR.archive" "$OLDLOG"

# 负控 B：聚合逻辑含 rc-缺失=失败 分支（worker 半死不能默认 pass）
assert_contains "聚合含 rc-缺失=失败 分支" \
  "$(grep -c 'no-rc' "$PF" | tr -d '\n')" "1"

# 负控 C：archive-devlog 在 wait 之后（mutating check 不与只读 check 竞争）
assert_contains "archive-devlog 在 wait 之后" \
  "$(awk '/^wait /{w=NR} /run_check 6 .*archive-devlog/{a=NR} END{print (a>w)?"yes":"no"}' "$PF")" "yes"

# ── 输出等价断言 ─────────────────────────────────────────────────────────────
# (a) --quiet 恰好输出一行，且含 postflight
q_out=$( bash "$PF" "$WORK/$HX_MAIN_FILE" --files="$GOODLOG" --quiet 2>&1 )
assert_exit "quiet 输出恰一行" 0 \
  "$([ "$(printf '%s\n' "$q_out" | grep -c .)" = 1 ] && echo 0 || echo 1)"
assert_contains "quiet 行含 postflight" "$q_out" "postflight"

# (b) verbose 回放顺序固定 123456（并行调度不抖动）。L4 (v4.1.1): 编号即执行顺序——
# 只读 1-4 与 xref-lint 5 并行、archive-devlog 6 串行殿后；旧编号印成 1 2 3 4 6 5
v_out=$( bash "$PF" "$WORK/$HX_MAIN_FILE" --files="$GOODLOG" 2>&1 )
order=$(printf '%s\n' "$v_out" | grep -oE '^→ [0-9]' | grep -oE '[0-9]' | tr -d '\n')
assert_contains "verbose 回放顺序固定 123456（显示序 = 执行序）" "$order" "123456"

# (c) 根/skill postflight byte-equal（独立佐证 test_scripts_sync）
assert_exit "根/skill postflight byte-equal" 0 \
  "$(diff -q "$SCRIPTS_DIR/handoff-postflight.sh" \
     "$(dirname "$SCRIPTS_DIR")/skills/handoffx/scripts/handoff-postflight.sh" \
     >/dev/null 2>&1; echo $?)"

summary
