#!/bin/bash
# Default daily-command output stays small; no Python/runtime dependency.
source "$(dirname "$0")/common.sh"
SK="$ROOT_DIR/skills/handoffx"
mkdir -p "$ROOT_DIR/wip/tmp"
export TMPDIR="$ROOT_DIR/wip/tmp"
# Optional immutable HEAD reference for RED runs; never replace product docs.
RECALL_REF="${HRT_TEST_RECALL_REF:-$SK/references/handoffx-recall.md}"
char_count() { LC_ALL=C tr -cd '\000-\177\300-\377' | wc -c | tr -d ' '; }
for name in handoffx handoffx-recall handoffx-init handoffx-tidy handoffx-memory; do
    shim="$SK/command-shims/$name.md"
    n=$(char_count < "$shim")
    assert_exit "$name entire command expansion is <=200 Unicode characters" 0 "$([ "$n" -le 200 ] && echo 0 || echo 1)"
    ref="$name"; [ "$name" != handoffx ] || ref=handoffx-write
    assert_contains "$name points to its correct detailed reference" "$(cat "$shim")" "@HANDOFFX_ROOT@/references/$ref.md"
    assert_eq "$name has the exact common launch notice" "🚀启动handoffX项目交接流程." "$(sed -n '4p' "$shim")"
    assert_contains "$name preserves raw arguments" "$(cat "$shim")" '$ARGUMENTS'
done
assert_contains "skill keeps the short write-confirmation budget" "$(cat "$SK/SKILL.md")" "全部用户可见说明合计不超过200字"
assert_contains "write does not echo source snippets" "$(cat "$SK/references/handoffx-write.md")" "不贴代码、命令、entry片段"
assert_not_contains "write no longer asks for 5-10 lines of source" "$(cat "$SK/references/handoffx-write.md")" "粘贴刚写入的 5-10 行"
assert_exit "write uses finalize with per-operation project root and new log" 0 "$(grep -qE '^bash <skill-path>/scripts/handoff-runtime.sh --expect-root .* finalize --log Handoffx_Logs/' "$SK/references/handoffx-write.md"; echo $?)"
assert_contains "write delegates mechanical closeout to finalize" "$(cat "$SK/references/handoffx-write.md")" '不要再自行串接regen/recall/postflight/reply'
assert_contains "write forwards finalize output unchanged" "$(cat "$SK/references/handoffx-write.md")" '最终正常确认必须逐字使用 `finalize` 成功输出'
assert_contains "write finalize retains failure disclosure" "$(cat "$SK/references/handoffx-write.md")" '退出非0即没有成功确认'
assert_contains "postflight diagnostics remain brief" "$(cat "$SK/references/handoffx-write.md")" '`--brief` 只出一行、≤200字摘要'
assert_contains "write checks all conditional write targets" "$(cat "$SK/references/handoffx-write.md")" "必须全部加入"
assert_contains "recall normal empty project is not a tool error" "$(cat "$RECALL_REF")" "暂无交接日志"
assert_contains "recall preserves read-only semantics" "$(cat "$RECALL_REF")" "只读不写"
# The list intentionally scopes this shared policy check to write only.
# shellcheck disable=SC2043
for ref in handoffx-write; do
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$(printf '%s' "$line" | char_count)
        assert_exit "$ref quoted response example <=200 characters" 0 "$([ "$n" -le 200 ] && echo 0 || echo 1)"
    done < <(sed -n 's/^> //p' "$SK/references/$ref.md")
done
# These are document/template contract checks, not model-response validation.
recall=$(cat "$RECALL_REF")
for section in '交接时间与读取范围' '当前状态与近期交接' '从这里继续' '上次停在哪里' '下一步' '当前TODO'; do
    assert_contains "compact recall report includes $section" "$recall" "$section"
done
assert_contains "recall body is not subject to launch/write budget" "$recall" '正文不受120/200字限制'
assert_not_contains "recall must not collapse the todo list" "$recall" '不重复所有待办'
assert_not_contains "recall does not pass rich output through reply length gate" "$recall" 'reply --text'
assert_contains "recall does not infer unstarted work from unchecked tasks" "$recall" '未勾选不等于未开始'
assert_contains "recall labels inferred next steps" "$recall" '建议/待确认'
assert_contains "recall preserves unknown next steps" "$recall" '无安排写“未记录”'
assert_contains "recall does not infer a stopping point from titles" "$recall" '未记录则明确未知，不从历史标题推断'
assert_contains "recall has no trailing summary/source/risk/signoff" "$recall" '之后不追加总结、来源、风险或结束语'
assert_contains "current constraints precede the final handoff area" "$recall" '均放在末尾接手区之前'
assert_contains "pending remains the current TODO source of truth" "$recall" '当前TODO唯一事实源为 `hx:pending`'
assert_contains "old open tasks survive the recent-log limit" "$recall" '即使早于最近N条'
assert_contains "TODO ownership and blockers are not discarded" "$recall" '负责人、期限、依赖、阻塞、暂缓与用户门控'
assert_contains "history cannot replace current pending state" "$recall" '日志摘要不覆盖或替代pending'
assert_contains "linked task lists disclose unread gaps" "$recall" '须报告缺口，不默认递归补读'
for budget in 24576 12288 4096 2048; do
    assert_contains "recall documents byte limit $budget" "$recall" "$budget"
done
assert_contains "budgets count UTF-8 bytes rather than tokens" "$recall" 'UTF-8字节'
assert_contains "stdout cap includes metadata and newlines" "$recall" 'stdout总量（含元数据与换行）'
assert_contains "budget failure has no partial stdout" "$recall" '非零退出，stdout为空'
assert_contains "oversized legacy overview is never deferred" "$recall" '绝不整段延后'
assert_not_contains "old overview deferral contract is removed" "$recall" '| Project Overview | 2048 | 延后加载并明示 |'
assert_contains "short legacy logs alone may be replayed fully" "$recall" '全文≤2048字节才读全文'
assert_contains "long legacy logs degrade honestly" "$recall" '旧长日志仅返回编号、时间、有界标题及路径'
assert_contains "malformed summaries cannot silently fall back" "$recall" '不能降级冒充成功'
assert_contains "GOTCHAS body is excluded by default" "$recall" '默认不展开GOTCHAS正文'
assert_contains "larger N cannot bypass total budget" "$recall" '增加N仍受总预算限制'
assert_contains "budget failures cannot trigger full replay by another tool" "$recall" '禁止全文补读、分批拼回全文或更换工具绕预算'

# Semantic obligations are instructions for the reporting model, not a claim
# that a byte-bounded extraction or this static test proves semantic completeness.
for term in '总目标' '受益者与问题' '阶段目标' '成功标准' '阶段验收' '范围与非目标' \
    '技术/安全/兼容性约束与授权门控' '仍有效决策及原因/出处' \
    '工作定位' '未完成改动' '验证命令/日期/范围' '阻塞/依赖/风险与未知'; do
    assert_contains "recall requires coverage of $term" "$recall" "$term"
done
for term in 'continuity_status=explicit_unverified' 'continuity_status=legacy_unverified' \
    '全文原样保留' '结构合法不代表语义齐全' '最终报告逐项列出缺失、冲突或仅有占位的覆盖缺口' \
    '未知不等于没有' '不能从项目标题或TODO反推目标' '不能因时间较新就静默覆盖冲突' \
    '改变目标或不可逆操作前先询问确认' '不因此阻断每项无害任务' \
    '当前有效关键信息不得仅留在延后资料中' '不在别处重复同一可变事实' \
    '块重复、错位、未闭合或损坏拒绝' '不能跨章节' '围栏代码示例不算真实标记' \
    '空块或仅空白块拒绝' 'overview_outside_continuity_bytes' 'N>0时简要说明' \
    '不是整个主文件' '同级 `## Goals` 不属于Overview' 'recall不自动折叠/迁移标题' ; do
    assert_contains "recall continuity contract: $term" "$recall" "$term"
done
for ref in handoffx-write handoffx-init handoffx-tidy; do
    doc=$(cat "$SK/references/$ref.md")
    for term in 'hx:continuity' '4096' 'legacy_unverified' '绝不整段延后' \
        '结构合法不代表语义齐全' '阶段目标' '阶段验收' '工作定位' '未完成改动' \
        '验证命令/日期/范围' '第二份状态快照'; do
        assert_contains "$ref maintains continuity: $term" "$doc" "$term"
    done
done
assert_not_contains "recent no longer owns project constraints" "$recall" '当前有效关键约束应写在recent'
assert_contains "skill points to the single direction area" "$(cat "$SK/SKILL.md")" '权威方向区'
assert_contains "tidy does not automatically invent continuity" "$(cat "$SK/references/handoffx-tidy.md")" '默认tidy不自动提炼、迁移或补造'
for doc in README.md README_CN.md INSTALL.md; do
    for term in 'hx:continuity' '4096' 'explicit_unverified' 'legacy_unverified'; do
        assert_contains "$doc documents continuity: $term" "$(cat "$ROOT_DIR/$doc")" "$term"
    done
done
assert_not_contains "English README no longer defers legacy direction" "$(cat "$ROOT_DIR/README.md")" 'An oversized overview is deferred'
assert_not_contains "Chinese README no longer defers legacy direction" "$(cat "$ROOT_DIR/README_CN.md")" '概览过长则延后加载'
assert_not_contains "INSTALL does not cap recall to write-confirmation length" "$(cat "$ROOT_DIR/INSTALL.md")" '`/handoffx` and `/handoffx-recall` each reply once, with at most 200 characters'

# Static template shape check only: exactly one populated canonical block,
# within Overview, never crossing a level-two section. Runtime parser cases
# (fences, corruption, arbitrary inputs) belong to the runtime suite.
quiet_template_continuity_valid() {
    awk '
        /^## / {
            if (inside) bad=1
            overview=($0 ~ /Project Overview/)
        }
        /^<!-- hx:continuity -->$/ {
            if (!overview || inside || opens) bad=1
            opens++; inside=1; next
        }
        /^<!-- \/hx:continuity -->$/ {
            if (!inside || !overview) bad=1
            closes++; inside=0; next
        }
        inside && /[^[:space:]]/ { content=1 }
        END { if (bad || inside || opens!=1 || closes!=1 || !content) exit 1 }
    '
}
template=$(cat "$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md")
continuity=$(printf '%s\n' "$template" | sed -n '/^<!-- hx:continuity -->$/,/^<!-- \/hx:continuity -->$/p' | sed '1d;$d')
recent=$(printf '%s\n' "$template" | sed -n '/^<!-- hx:recent -->$/,/^<!-- \/hx:recent -->$/p')
# Preserve the final payload newline in the byte measurement.
bytes=$(printf '%s\n' "$continuity" | LC_ALL=C wc -c | tr -d ' ')
assert_exit "template canonical continuity is at most 4096 UTF-8 bytes" 0 "$([ "$bytes" -le 4096 ] && echo 0 || echo 1)"
ec=0; printf '%s\n' "$template" | quiet_template_continuity_valid || ec=$?
assert_exit "template has one populated continuity block inside Overview" 0 "$ec"
for field in 'Goals（总目标、受益者与问题）' '成功标准' '范围 / Non-Goals' '关键约束与授权门控' '仍有效决策（原因与出处）'; do
    assert_contains "canonical template area holds $field" "$continuity" "$field"
done
for field in '阶段目标' '阶段验收' '工作定位' '未完成改动' '上次停点' '下一步' '命令 / 结果 / 日期 / 验证范围 / 未验证部分' '阻塞与未知'; do
    assert_contains "recent template area holds $field" "$recent" "$field"
done
assert_not_contains "template recent does not duplicate project constraints" "$recent" '**关键约束**'
assert_not_contains "template no longer hides direction above old limit" "$template" '超限时默认召回延后加载'
assert_contains "template warns unknown is not none" "$template" '未知不等于没有'
assert_contains "template milestone only references canonical phase/tasks" "$template" '不另存阶段状态或TODO副本'
ec=0; printf '%s\n%s\n' "$template" '<!-- hx:continuity -->' | quiet_template_continuity_valid || ec=$?
assert_exit "negative control: duplicate canonical block rejected" 1 "$ec"
ec=0; printf '%s\n' "$template" | sed '/^<!-- \/hx:continuity -->$/d' | quiet_template_continuity_valid || ec=$?
assert_exit "negative control: unclosed canonical block rejected" 1 "$ec"
ec=0; printf '%s\n' "$template" | sed 's/## 📦 Project Overview/## Other/' | quiet_template_continuity_valid || ec=$?
assert_exit "negative control: canonical block outside Overview rejected" 1 "$ec"
ec=0; printf '%s\n' "$template" | sed '/^<!-- hx:continuity -->$/,/^<!-- \/hx:continuity -->$/d' | quiet_template_continuity_valid || ec=$?
assert_exit "negative control: missing template canonical block rejected" 1 "$ec"
ec=0; printf '%s\n' '## Project Overview' '<!-- hx:continuity -->' '   ' '<!-- /hx:continuity -->' | quiet_template_continuity_valid || ec=$?
assert_exit "negative control: empty template canonical block rejected" 1 "$ec"

assert_contains "unanchored state context is not dropped" "$recall" 'Current State锚点外说明有界保留'
assert_contains "orphan task guard covers other main-file sections" "$recall" '主文件其他位置（含其他章节）'
assert_contains "checked parents cannot complete residual prose" "$recall" '不能假设遗留说明也已完成'
assert_contains "recall directory is not proof of code worktree identity" "$recall" '前者不证明后者身份'
assert_contains "unclosed log fences cannot silently degrade" "$recall" '日志代码围栏未闭合'

assert_contains "pending omission compatibility count is zero" "$recall" 'pending_completed_items_omitted=0'
assert_contains "unmarked legacy fence degradation is explicit" "$recall" 'legacy_unclosed_fence_metadata_only'

# Static instruction-presence/placement checks only: they do not execute a model
# or prove faithful attribution. The root-proof-002 raw output requires separate
# semantic review; these checks may pass while a model disobeys the document.
collection=$(sed -n '/^## 一次采集与预算$/,/^## 交接时间与时效$/p' "$RECALL_REF")
semantics=$(sed -n '/^## 语义覆盖与冲突检查$/,/^## 最终结果$/p' "$RECALL_REF")
result_intro=$(sed -n '/^## 最终结果$/,/^## 从这里继续$/p' "$RECALL_REF")
todo_contract=$(sed -n '/^### 当前TODO$/,$p' "$RECALL_REF")
assert_contains "doc: complete pending includes checked context" "$collection" 'hx:pending完整保留所有行'
assert_contains "doc: only explicit done block is excluded" "$collection" '只有明确的 `hx:done` 默认不读'
assert_contains "doc: retained checked context does not become open work" "$collection" '不列为开放TODO、不改checkbox、不改变父子归属'
assert_contains "doc: checked context belongs before tail or with original context" "$collection" '放在末尾接手区前或其原关联上下文中'
assert_contains "doc: full pending still fails closed at original budget" "$collection" '超限须先显式整理，不能删行或增加预算'
assert_not_contains "doc: no obsolete standalone checked omission rule" "$collection" 'pending只排除'
assert_not_contains "doc: no invented positive omission display" "$collection" 'N>0只在'
assert_contains "doc: compatibility metadata is not user-visible proof" "$collection" '不展示，不证明语义完整'
assert_contains "doc: total test count is not reassigned to one feature" "$semantics" '不能合成“该功能6项测试通过”'
assert_contains "doc: an already-misattributed recent claim is disclosed" "$semantics" '不照抄为阶段验收事实，也不静默改写来源'
assert_contains "doc: attribution uncertainty does not fabricate subset results" "$semantics" '不猜子集通过数'
assert_contains "doc: counters and completeness statements precede resume area" "$result_intro" '计数与完整性说明也只放前文'
assert_contains "doc: TODO permits original task context, not new commentary" "$todo_contract" '仅列任务及其原有上下文'
assert_contains "doc: final task and context terminate the reply" "$todo_contract" '最后一项及其原有上下文结束即结束回复'
assert_contains "doc: TODO does not end with metadata or completeness claims" "$todo_contract" '不附省略计数或“清单完整”等说明'

quiet_tail_valid() {
    # The reference ends with this exact outline. Normal task prose is allowed;
    # any new heading after Current TODO would violate the terminal-area rule.
    awk '
        /^## 从这里继续$/ { if(step!=0) bad=1; step=1; next }
        step && /^#+ / {
            if(step==1 && $0=="### 上次停在哪里") step=2
            else if(step==2 && $0=="### 下一步") step=3
            else if(step==3 && $0=="### 当前TODO") step=4
            else bad=1
        }
        END { if(step!=4 || bad) exit 1 }
    '
}
tail_outline=$(sed -n '/^## 从这里继续$/,$p' "$RECALL_REF")
ec=0; printf '%s\n' "$recall" | quiet_tail_valid || ec=$?
assert_exit "final handoff outline is ordered and terminal" 0 "$ec"
ec=0; printf '%s\n\n## 来源\nextra\n' "$tail_outline" | quiet_tail_valid || ec=$?
assert_exit "negative control: appended sources heading rejected" 1 "$ec"
ec=0; printf '%s\n' "$tail_outline" | sed 's/^### 下一步$/### 当前TODO/' | quiet_tail_valid || ec=$?
assert_exit "negative control: reordered or duplicate TODO heading rejected" 1 "$ec"
ec=0; printf '%s\n' "$tail_outline" | sed '/^### 上次停在哪里$/d' | quiet_tail_valid || ec=$?
assert_exit "negative control: missing stopping-point section rejected" 1 "$ec"
ec=0; printf '%s\n%s\n' "$tail_outline" "$tail_outline" | quiet_tail_valid || ec=$?
assert_exit "negative control: duplicate final handoff area rejected" 1 "$ec"
T=$(mktemp -d "$TMPDIR/quiet-output.XXXXXX"); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/$HX_LOGS_DIR" "$T/$HX_DEC_DIR"
cp "$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md" "$T/$HX_MAIN_FILE"
printf '# Known Gotchas\n' > "$T/$HX_GOTCHAS_FILE"
ec=0; out=$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --brief "$T/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "brief successful check preserves exit0" 0 "$ec"
n=$(printf '%s' "$out" | char_count)
assert_exit "brief success <=200 characters" 0 "$([ "$n" -le 200 ] && echo 0 || echo 1)"
printf '%s\n' 'bad entry' > "$T/$HX_LOGS_DIR/0001-2020-01-01T0000-bad.md"
ec=0; out=$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --brief "$T/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "brief failing check does not hide failure" 1 "$ec"
n=$(printf '%s' "$out" | char_count)
assert_exit "brief failure <=200 characters" 0 "$([ "$n" -le 200 ] && echo 0 || echo 1)"
assert_file_exists "brief failing check does not archive bad input" "$T/$HX_LOGS_DIR/0001-2020-01-01T0000-bad.md"
summary
