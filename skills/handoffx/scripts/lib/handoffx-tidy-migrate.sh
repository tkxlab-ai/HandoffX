#!/bin/bash
# handoffx-tidy-migrate.sh — schema 迁移核心：v2 旧四件套 → handoffx schema。
# Sourced by tidy-handoff.sh schema-upgrade subcommand. LEAVE class basename.
# Decision 0019/0020/0025 P2.1。
#
# Why: 本 helper 的 --help 描述四件套路径串时**必须**派生自 \$HX_* schema source，
# 不得用裸字面（否则 P2.0 baseline-ratchet guard test_handoff_schema.sh
# `current stray EQUALS frozen baseline` 会把本文件当 NEW leak 抓住——baseline
# 是 strict-zero terminal）。tidy-handoff.sh 在 subcommand dispatch 前已 source
# schema lib，故本壳已可见 \$HX_*。heredoc 用裸 EOF（非 'EOF'）以允许展开。
#
# M2 (Task 1 code review Minor): self-guard against direct sourcing without
# schema lib pre-sourced. Helper is contractually sourced via tidy-handoff.sh
# dispatch which sources schema first; this assertion fails-noisy if used
# directly (e.g., `bash -c '. handoffx-tidy-migrate.sh && handoffx_tidy_main ...'`).
: "${HX_MAIN_FILE:?handoffx-tidy-migrate.sh requires schema lib pre-sourced via tidy-handoff.sh dispatch}"

# detect_schema_state — output exactly one of: MIXED | OLD-V2 | ALREADY-HANDOFFX | UNKNOWN
#
# Why MIXED 必须先判（Source 2 S2-A Critical / S2-B High）：旧版只看 new-side
# 三件齐 → ALREADY-HANDOFFX，根本不看 old-side 是否还在。若 old+new 同存
# （上次迁移 rm-source 阶段半失败 / 用户手工恢复旧目录搞出 split-brain），
# 静默走 no-op = 数据孤儿。MIXED 显式 fail-loud 是唯一安全语义——任意一边
# 存在「数据」就要人介入分清主从。
#
# Why 计数而非短路：旧 `&&` 链一旦看到 new-main 缺就只回 false，看不到 old-side
# 三件可能齐——MIXED 判定需要看「两边各有几件」。计数 + 双 >0 → 一目了然。
#
# Why [-r] 在 grep 前：Gotcha #24 母题——文件 -f 存在但无读权限 (perm 000 /
# root-owned 600) → grep 静默回 1（无匹配），detect 判 UNKNOWN，用户得到「不是
# v2」错信息而非「权限不够」。-r 显式分层。
detect_schema_state() {
    local root="$1"
    local new_main="$root/${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    local new_logs="$root/${HX_LOGS_DIR/Handoff_/Handoffx_}"
    local new_dec="$root/${HX_DEC_DIR/Handoff_/Handoffx_}"
    local has_new=0 has_old=0
    # MEDIUM-G (2026-06-07 audit): 计数用 [ -e ]（存在即计）而非 [-f]/[-d] 类型限定。
    # 若同名工件类型不符（如 HANDOFFX.md 是目录 / Handoffx_Logs 是文件——上次半失败
    # 或用户手工误建留下），类型限定会漏计 → 误判 OLD-V2 而非 MIXED，把 split-brain
    # 当可迁。存在即需人介入分清主从，正是 MIXED 的设计意图（preflight 的 [ ! -e ]
    # 是第二道防线，detect 这里 -e 是第一道，不依赖单点）。
    [ -e "$new_main" ] && has_new=$((has_new+1))
    [ -e "$new_logs" ] && has_new=$((has_new+1))
    [ -e "$new_dec" ] && has_new=$((has_new+1))
    [ -e "$root/$HX_MAIN_FILE" ] && has_old=$((has_old+1))
    [ -e "$root/$HX_LOGS_DIR" ] && has_old=$((has_old+1))
    [ -e "$root/$HX_DEC_DIR" ] && has_old=$((has_old+1))
    if [ "$has_new" -gt 0 ] && [ "$has_old" -gt 0 ]; then
        echo "MIXED"
    elif [ "$has_new" -eq 3 ]; then
        echo "ALREADY-HANDOFFX"
    elif [ "$has_old" -eq 3 ] && [ -r "$root/$HX_MAIN_FILE" ] \
         && grep -qF -- '<!-- HANDOFF v2 schema -->' "$root/$HX_MAIN_FILE" 2>/dev/null; then
        echo "OLD-V2"
    else
        echo "UNKNOWN"
    fi
}

# preflight_check — validate sources present + targets clear + writable.
# Echoes problems to stderr; returns 0 ok, 1 fail.
# Why: detect 已确认 OLD-V2 后再进 preflight；这里专管 "能迁吗"（目标位空、
# .partial 无残留、root 可写）—— Codex review #6 母题（stale partial 不灵敏）
# 同源对策。
preflight_check() {
    local root="$1"
    local rc=0
    local new_main="$root/${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    local new_logs="$root/${HX_LOGS_DIR/Handoff_/Handoffx_}"
    local new_dec="$root/${HX_DEC_DIR/Handoff_/Handoffx_}"
    # Sources must exist (detect 已保证，但 preflight 显式再校以独立可调用)
    [ -f "$root/$HX_MAIN_FILE" ] || { echo "❌ preflight: $HX_MAIN_FILE missing in $root" >&2; rc=1; }
    [ -d "$root/$HX_LOGS_DIR" ] || { echo "❌ preflight: $HX_LOGS_DIR/ missing" >&2; rc=1; }
    [ -d "$root/$HX_DEC_DIR" ] || { echo "❌ preflight: $HX_DEC_DIR/ missing" >&2; rc=1; }
    # Targets must NOT exist (assert_dest_clear pattern — migrate-to-v2 同源)
    [ ! -e "$new_main" ] || { echo "❌ preflight: target $new_main already exists" >&2; rc=1; }
    [ ! -e "$new_logs" ] || { echo "❌ preflight: target $new_logs/ already exists" >&2; rc=1; }
    [ ! -e "$new_dec" ] || { echo "❌ preflight: target $new_dec/ already exists" >&2; rc=1; }
    # Stale .partial check (Codex review #6 pattern from migrate-to-v2).
    # Why target-side names: Task 3's migrate_apply stages on TARGET-side .partial
    # (HANDOFFX.md.partial / Handoffx_*.partial), unlike migrate-to-v2.sh which
    # stages on same-name .partial because v1→v2 doesn't rename dirs. A stale
    # target-side .partial would be silently clobbered by `cp` in migrate_apply;
    # explicit refuse-and-guide is the Gotcha #25 母题 prevention.
    for p in \
        "$root/${HX_MAIN_FILE/HANDOFF/HANDOFFX}.partial" \
        "$root/${HX_LOGS_DIR/Handoff_/Handoffx_}.partial" \
        "$root/${HX_DEC_DIR/Handoff_/Handoffx_}.partial"; do
        [ ! -e "$p" ] || { echo "❌ preflight: stale partial $p — inspect & manual cleanup" >&2; rc=1; }
    done
    # Writability
    [ -w "$root" ] || { echo "❌ preflight: $root not writable" >&2; rc=1; }
    return $rc
}

# dry_run_report — emit planned rename actions to stdout (no side effects)
dry_run_report() {
    local root="$1"
    echo "📋 schema-upgrade dry-run (root=$root):"
    echo "  $HX_MAIN_FILE → ${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    echo "  $HX_LOGS_DIR/ → ${HX_LOGS_DIR/Handoff_/Handoffx_}/"
    echo "  $HX_DEC_DIR/ → ${HX_DEC_DIR/Handoff_/Handoffx_}/"
    echo "  $HX_GOTCHAS_FILE: LEAVE name (ADR-0005); content swept (Q2 全扫所有 .md)"
    echo "  + .md text sweep: literal path strings rewritten (Q2 全扫范围, Task 4 + Fix E 实现)"
}

# ─── Migration state (file-scope; trap reads these) ──────────────────────────
# Initialized here so `set -u` in tidy-handoff.sh doesn't unbind-trap the EXIT
# callback if it fires before migrate_apply set them (e.g., preflight abort).
#
# _HX_MIGRATE_COMMIT_POINT — Source 2 S2-A Critical 修正：commit-point 语义。
# 旧版 cleanup_and_maybe_rollback 在 DONE=0 时一律「条件式 rm 已落地目标」——但若
# 失败发生在 rm-source 阶段（所有 mv 已成功，源仍在），trap 会因「源还在 + 目标也
# 在」而 rm 掉目标 → 数据丢失（mixed-schema wedge）。COMMIT_POINT=1 表示 mv 三件
# 全成 = 目标已成为真相，trap 此后只允许「报告残留源」，绝不动目标。
_HX_MIGRATE_DONE=0
_HX_MIGRATE_COMMIT_POINT=0
_HX_MIGRATE_ROOT=""
_HX_NEW_MAIN_PARTIAL=""
_HX_NEW_LOGS_PARTIAL=""
_HX_NEW_DEC_PARTIAL=""
# Fix E (Source 1 Important): $HX_GOTCHAS_FILE 文件名 LEAVE（ADR-0005），但
# 内容里的字面路径串需随 sweep 改写（Q2「全扫所有 .md」拍板）。同 .partial-
# staging 路径，原子性靠 sweep-on-staging + mv-into-place 一致语义。
_HX_NEW_GOTCHAS_PARTIAL=""

# cleanup_and_maybe_rollback — EXIT trap callback (migrate-to-v2.sh:76-107 范式).
#
# 三态决策树（Source 2 S2-A Critical + S2-C Medium 修正）：
#   DONE=1                       → 完全成功；只做 defensive .partial 清扫
#   COMMIT_POINT=1 且 DONE=0     → 三 mv 已成（目标=真相），rm-source 阶段失败；
#                                  绝不动目标；报告「残留源待清」即可
#   COMMIT_POINT=0 且 DONE=0     → mv 半途/cp 半途失败；源仍是真相，目标半残；
#                                  rm 掉 .partial + rm 掉与残源并存的目标
#
# Why 旧版 BUG（S2-A）：旧版无 COMMIT_POINT 概念，DONE=0 即触发条件式 rm 目标。
# 但若 mv 全成 → 进入 rm-source → rm 第一个源后 trap 因任意理由触发（信号 / 后续
# rm 失败），「源 #2 还在 + 目标 #2 也在」满足条件式 → rm 目标 #2 → 数据丢失。
# COMMIT_POINT 把「目标已成真相」这一不变量显式标出，trap 越过 = 只读上报。
#
# Why 旧版 BUG（S2-C）：旧版「rolled back」消息无条件 echo，即使 DONE=1 / 部分提交
# 也喊回滚 → 用户行动错位。现按三态分别消息，准确指引。
cleanup_and_maybe_rollback() {
    [ -n "$_HX_MIGRATE_ROOT" ] || return 0  # trap fired without apply having started
    # HIGH-C (2026-06-07 audit): 清理失败必须可观测，绝不静默吞（Gotcha #24/#25 母题
    # ——回滚类函数的判决须键在「真清掉了吗」，不能无条件喊「rolled back / sources
    # preserved」而把「清理失败有残留」伪装成干净态）。residue 累积任一 rm 失败，末尾
    # 据此区分「干净回滚」vs「回滚不完整有残留」两种诚实消息。
    # 逐路径 + [ -n ] 守护（同时修 LOW：原裸 `rm -rf "$a" "$b" …` 多参一行无守护）：
    # trap 可能在 partials 发布前触发（root 已设、partials 仍 ""，见 migrate_apply
    # 发布顺序），空串跳过既安全又免去 ${var:?} 在该合法空态下崩 trap。
    local residue=0 rp
    for rp in "$_HX_NEW_MAIN_PARTIAL" "$_HX_NEW_LOGS_PARTIAL" "$_HX_NEW_DEC_PARTIAL" "$_HX_NEW_GOTCHAS_PARTIAL"; do
        [ -n "$rp" ] || continue            # trap fired before partials published
        [ -e "$rp" ] || continue            # 成功路径已 mv 走 / 从未建 → 无需清
        rm -rf "$rp" || { echo "  ⚠️ schema-upgrade: 残留 .partial 未能清除: $rp" >&2; residue=1; }
    done
    if [ "$_HX_MIGRATE_DONE" = "1" ]; then
        [ "$residue" = "0" ] || echo "⚠️ schema-upgrade: 迁移已成功但上列 .partial 残留未清，请手工清理 $_HX_MIGRATE_ROOT" >&2
        return 0  # clean success（数据已就位；残留仅 .partial 噪声，非数据风险）
    fi
    if [ "$_HX_MIGRATE_COMMIT_POINT" = "1" ]; then
        # 越过 commit point：目标是真相，源是残留。绝不动目标，只提示人工清源。
        echo "⚠️ schema-upgrade: COMMIT COMPLETE but stale source artifacts may remain at $_HX_MIGRATE_ROOT — manual cleanup required (targets HANDOFFX*/Handoffx_*/ are authoritative)" >&2
        return 0
    fi
    # Pre-commit-point 失败：源还是真相，回退半残目标。条件式 `源在 && 目标在`
    # 是双重防御——理论上 COMMIT_POINT=0 时必然源仍在，但若先决条件意外破坏，
    # 条件式至少保证不在源已消失时 rm 唯一一份目标数据。半建目标的 rm 失败同样
    # 计入 residue（不再 2>/dev/null 吞——HIGH-C）。
    local new_main="$_HX_MIGRATE_ROOT/${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    local new_logs="$_HX_MIGRATE_ROOT/${HX_LOGS_DIR/Handoff_/Handoffx_}"
    local new_dec="$_HX_MIGRATE_ROOT/${HX_DEC_DIR/Handoff_/Handoffx_}"
    if [ -f "$_HX_MIGRATE_ROOT/$HX_MAIN_FILE" ] && [ -e "$new_main" ]; then
        rm -rf "$new_main" || { echo "  ⚠️ schema-upgrade: 半建目标未能清除: $new_main" >&2; residue=1; }
    fi
    if [ -d "$_HX_MIGRATE_ROOT/$HX_LOGS_DIR" ] && [ -e "$new_logs" ]; then
        rm -rf "$new_logs" || { echo "  ⚠️ schema-upgrade: 半建目标未能清除: $new_logs" >&2; residue=1; }
    fi
    if [ -d "$_HX_MIGRATE_ROOT/$HX_DEC_DIR" ] && [ -e "$new_dec" ]; then
        rm -rf "$new_dec" || { echo "  ⚠️ schema-upgrade: 半建目标未能清除: $new_dec" >&2; residue=1; }
    fi
    if [ "$residue" = "0" ]; then
        echo "⚠️ schema-upgrade rolled back (pre-commit-point failure; sources preserved at $_HX_MIGRATE_ROOT)" >&2
    else
        echo "⚠️ schema-upgrade 回滚不完整：源已保留于 ${_HX_MIGRATE_ROOT}，但上列 .partial/半建目标残留未清——请手工清理后重试（stale-partial guard 会阻止下次 --apply 直到清净）" >&2
    fi
}

# rewrite_path_strings — sweep all .md files in target .partial paths,
# substituting literal four-piece path-strings to handoffx names (Q2 全扫范围,
# Boss 2026-05-21 拍板). 调用点：migrate_apply 的 cp 与 mv 之间——重写发生在
# .partial 暂存树内，落地随 mv 原子提交；失败 return 2 触发 Task 3 EXIT-trap
# 回滚机制。
#
# Why 派生而非裸字面：本文件落在 scripts/lib/，被 test_handoff_schema.sh 的
# baseline-ratchet 守门扫描 scripts/**/*.sh 内任何旧四件套字面 token；baseline
# 已是 terminal-zero（schema 源外零字面）。所有 sed 模式必须从 $HX_* + 参数
# 展开派生，否则 NEW leak 即时 RED。这也是 Decision 0020 coupling-c "单一真相
# 源" 在迁移器内部的同源贯彻——连本注释亦不能拼出旧 token，故下文引用一律
# 用 schema-source 变量名（$HX_MAIN_FILE / $HX_LOGS_DIR / 等）指代。
#
# Why 替换顺序 archive 先于 main（诚实版，MEDIUM-H 2026-06-07 audit 修正）：
# 当前命名下顺序**完全惰性**——main 模式 `${main_old//./\.}`(= 形如 `…\.md`) 因尾部
# `.md` 锚定，无法匹配 archive 字串（archive 形态在 main 名之后接的是 `.archive.md`，
# `…\.md` 要求 `HANDOFF` 紧跟 `.md`，而此处紧跟的是 `.archive`）。故 main-first 与
# archive-first 在当前命名等价，本顺序不防任何**现行** corruption（原注释「main 会把
# archive 前缀替掉一半」的机制描述有误，已更正）。保留 archive-first 仅作**防御性**
# 排序：若未来 archive 后缀变动致两模式产生前缀重叠，最长最具体优先是路径替换通行
# 原则。注意：本顺序不变式当前无负控守护（要守须构造 main 会吃掉 archive 前缀的命名
# 场景），属 YAGNI 延后——勿在测试里宣称已守护顺序（Gotcha #25：主张须匹配真实覆盖）。
#
# Why sed 用 `|` 分隔符：路径含 `/`，避免转义。`|` 在两侧字串都不出现（schema
# 常量及目标值均 ASCII 字母数字下划线点）→ 安全。
#
# Why find -print0 + read -d ''：fixture 名虽 ASCII，但 helper 契约不假设；
# 含空格/换行的路径不破组分（防御性，Tacit#4 honest comment）。
#
# Why $HX_GOTCHAS_FILE 现在 in sweep（Fix E / Source 1 Important）：ADR-0005
# 的 LEAVE 语义针对**文件名**（$HX_GOTCHAS_FILE 不改名），不针对**内容**——
# Boss Q2 2026-05-21 拍板「全扫重写所有 .md 内字面路径串」明确包含 gotchas
# 文件内的旧四件套路径引用（$HX_LOGS_DIR / $HX_DEC_DIR 等形态）。本函数
# 遍历 .partial 树时若 $_HX_NEW_GOTCHAS_PARTIAL 已暂存（migrate_apply 负责
# cp 进来），自然带上。落地仍用 mv $_HX_NEW_GOTCHAS_PARTIAL →
# $root/$HX_GOTCHAS_FILE（同名覆写）。
#
# Why 本注释也不能拼出旧四件套字面 token：baseline-ratchet
# (test_handoff_schema.sh) 扫描 scripts/**/*.sh 内任何旧四件套字面——含注释——
# baseline 为 terminal-zero（schema 源外零字面）。改用 schema source 变量名
# 指代是 Decision 0020 coupling-c「单一真相源」在 helper 内部的同源贯彻。
rewrite_path_strings() {
    # M2 (Task 4 code-review): self-guard — staging-state vars must be published
    # by migrate_apply 前。同 file-head `${HX_MAIN_FILE:?...}` 自检 idiom：直接
    # 调用本函数（绕过 migrate_apply）一律 fail-noisy，避免静默 sweep 全空集。
    : "${_HX_NEW_MAIN_PARTIAL:?rewrite_path_strings requires staging state (call from migrate_apply only)}"

    # 派生迁移前后形态——全部来自 $HX_* schema source（不能写裸字面）。
    local logs_old="$HX_LOGS_DIR" \
          logs_new="${HX_LOGS_DIR/Handoff_/Handoffx_}" \
          dec_old="$HX_DEC_DIR" \
          dec_new="${HX_DEC_DIR/Handoff_/Handoffx_}" \
          main_old="$HX_MAIN_FILE" \
          main_new="${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    # archive 形态派生 = ${main%.md}.archive.md，与 migrate-to-v2.sh:174 /
    # archive-devlog.sh:93 / test_handoff_schema.sh:86-93 同 idiom。
    local arc_old="${main_old%.md}.archive.md" \
          arc_new="${main_new%.md}.archive.md"
    # I1 (Task 4 code-review): pre-escape `.` in LHS regex patterns to neutralize
    # BRE any-char metachar. 注释里说的 "最长最具体优先" 在 `.` 匹配任意字符时
    # 形同失语——必须修机制（escape）本身，而非仅靠注释。logs_old / dec_old
    # 派生自 $HX_LOGS_DIR / $HX_DEC_DIR，schema 常量内无 `.`（纯字母下划线），
    # 故无需转义；只有含 `.` 的 main_old / arc_old 派生才需要。
    # NB: 不在本注释里拼出含点的旧四件套字面以免触发 baseline-ratchet（schema
    # 源外零字面 terminal-zero）。下行 ${VAR//./\\.} 即 "把 VAR 内每个点转义"。
    local main_old_re="${main_old//./\\.}"
    local arc_old_re="${arc_old//./\\.}"

    # 收集 .partial 暂存树内的 .md 目标文件（cp 后、mv 前的状态）。
    local targets=() f
    [ -f "$_HX_NEW_MAIN_PARTIAL" ] && targets+=("$_HX_NEW_MAIN_PARTIAL")
    # Fix E: ${HX_GOTCHAS_FILE}.partial 同样进入 sweep（文件名 LEAVE 但内容随
    # 迁），落地用 mv → 原名覆写（不改 basename）。
    [ -f "$_HX_NEW_GOTCHAS_PARTIAL" ] && targets+=("$_HX_NEW_GOTCHAS_PARTIAL")
    if [ -d "$_HX_NEW_LOGS_PARTIAL" ]; then
        while IFS= read -r -d '' f; do targets+=("$f"); done \
            < <(find "$_HX_NEW_LOGS_PARTIAL" -type f -name '*.md' -print0)
    fi
    if [ -d "$_HX_NEW_DEC_PARTIAL" ]; then
        while IFS= read -r -d '' f; do targets+=("$f"); done \
            < <(find "$_HX_NEW_DEC_PARTIAL" -type f -name '*.md' -print0)
    fi

    # 逐文件 sed 重写。顺序：archive → logs → decisions → main（最长最具体优先）。
    # macOS sed / GNU sed `-i` 旗参数差异——绕道 tmpf + mv，跨平台安全。
    local tmpf
    for f in "${targets[@]}"; do
        tmpf="${f}.rewrite.tmp"
        sed -e "s|${arc_old_re}|${arc_new}|g" \
            -e "s|${logs_old}/|${logs_new}/|g" \
            -e "s|${dec_old}/|${dec_new}/|g" \
            -e "s|${main_old_re}|${main_new}|g" \
            "$f" > "$tmpf" || { rm -f "$tmpf"; return 1; }
        mv "$tmpf" "$f" || return 1
    done
    return 0
}

# migrate_apply — perform schema migration atomically. Returns 0 on success,
# 2 on mid-migration failure (trap rolls back). Mirrors migrate-to-v2.sh:56-140
# pattern: .partial staging via cp (sources preserved) → atomic rename(2) per mv
# → final rm of sources only after every target is committed.
#
# Trap timing: installed INSIDE this function, after preflight has already run
# in the caller. A preflight-only abort therefore never triggers spurious
# rollback (the trap is uninstalled when the function frame exits / not yet set
# when preflight ran). Matches migrate-to-v2.sh:140 idiom.
migrate_apply() {
    local root="$1"
    local new_main="$root/${HX_MAIN_FILE/HANDOFF/HANDOFFX}"
    local new_logs="$root/${HX_LOGS_DIR/Handoff_/Handoffx_}"
    local new_dec="$root/${HX_DEC_DIR/Handoff_/Handoffx_}"

    # Publish trap state BEFORE installing trap (trap reads these).
    # M3 (Task 4 code-review cosmetic): DONE flag first, then root, then
    # partials —— 失败语义自顶向下读起来更顺（DONE=0 ⇒ rollback；root ⇒ 范围；
    # partials ⇒ 清扫目标）。Trap callback 早期短路 `[ -n $_HX_MIGRATE_ROOT ]`
    # 仍正确处理任意发布顺序，故为纯整理。
    _HX_MIGRATE_DONE=0
    _HX_MIGRATE_COMMIT_POINT=0
    _HX_MIGRATE_ROOT="$root"
    _HX_NEW_MAIN_PARTIAL="$root/${HX_MAIN_FILE/HANDOFF/HANDOFFX}.partial"
    _HX_NEW_LOGS_PARTIAL="$root/${HX_LOGS_DIR/Handoff_/Handoffx_}.partial"
    _HX_NEW_DEC_PARTIAL="$root/${HX_DEC_DIR/Handoff_/Handoffx_}.partial"
    # Fix E: $HX_GOTCHAS_FILE 同名 in-place 改写——staging 用
    # ${HX_GOTCHAS_FILE}.partial 走标准 cp → sweep → mv 原子三步
    # （避免直接 sed -i 跨平台差异 + 失败半残）。
    _HX_NEW_GOTCHAS_PARTIAL="$root/${HX_GOTCHAS_FILE}.partial"

    trap cleanup_and_maybe_rollback EXIT

    # Stage: cp (NOT mv) sources to .partial — preserves sources for rollback.
    cp "$root/$HX_MAIN_FILE" "$_HX_NEW_MAIN_PARTIAL" || return 2
    cp -r "$root/$HX_LOGS_DIR" "$_HX_NEW_LOGS_PARTIAL" || return 2
    cp -r "$root/$HX_DEC_DIR" "$_HX_NEW_DEC_PARTIAL" || return 2
    # Fix E: $HX_GOTCHAS_FILE 也进暂存（文件名不变，落地用 mv 覆写原名——见
    # 下方 commit 段）。
    cp "$root/$HX_GOTCHAS_FILE" "$_HX_NEW_GOTCHAS_PARTIAL" || return 2

    # Task 4: full .md sweep — rewrite literal path-strings inside the .partial
    # staging tree (Q2 全扫范围). 失败 return 2 ⇒ EXIT trap 触发 .partial 清扫
    # 回滚（Task 3 机理）。
    rewrite_path_strings || return 2

    # Commit phase: rename .partial → final. Each mv is atomic per rename(2);
    # if mid-sequence mv fails, trap rolls back per the conditional guard.
    mv "$_HX_NEW_LOGS_PARTIAL" "$new_logs" || return 2
    mv "$_HX_NEW_DEC_PARTIAL" "$new_dec" || return 2
    mv "$_HX_NEW_MAIN_PARTIAL" "$new_main" || return 2
    # Fix E: $HX_GOTCHAS_FILE 原地覆写——mv 同 root 内 rename(2) 原子，与三件套
    # 同语义。顺序放在三件之后（main 已 mv 完才动 gotchas）：commit-point 在此
    # 之后翻转，确保 gotchas 也算入「目标已成真相」边界内。
    mv "$_HX_NEW_GOTCHAS_PARTIAL" "$root/$HX_GOTCHAS_FILE" || return 2

    # Commit point: 三个 mv 全成，目标已成真相。Source 2 S2-A Critical 修正：
    # 越过此点后 trap 绝不动目标，rm-source 阶段任何失败按「残留源待清」处理
    # （rc=3，distinct from 0 干净 / 2 半途回滚），目标完整性已确立。
    _HX_MIGRATE_COMMIT_POINT=1

    # Remove sources (last — only after all targets committed).
    # M1 SC2115 fold: ${var:?} parameter expansion defensively aborts shell if
    # $root or $HX_* unset/empty — prevents `rm -rf /` 类灾难（schema lib 已
    # guard 4 常量非空 via :? on source；这里再加 root，纵深防御 + shellcheck
    # SC2115 显式关闭）。
    #
    # rc=3 语义（Source 2 S2-A）：rm-source 失败 ≠ 数据丢失，而是「目标已成 +
    # 源残留待人工清理」。退出码独立于 rc=2（半途回滚）让脚本调用方可分辨。
    rm -f  "${root:?}/${HX_MAIN_FILE:?}" || { echo "⚠️ schema-upgrade: targets COMMITTED but source rm failed: $root/$HX_MAIN_FILE — manual cleanup required" >&2; return 3; }
    rm -rf "${root:?}/${HX_LOGS_DIR:?}"  || { echo "⚠️ schema-upgrade: targets COMMITTED but source rm failed: $root/$HX_LOGS_DIR — manual cleanup required" >&2; return 3; }
    rm -rf "${root:?}/${HX_DEC_DIR:?}"   || { echo "⚠️ schema-upgrade: targets COMMITTED but source rm failed: $root/$HX_DEC_DIR — manual cleanup required" >&2; return 3; }

    _HX_MIGRATE_DONE=1
    echo "✅ schema-upgrade applied: $root migrated to handoffx schema"
    return 0
}

handoffx_tidy_main() {
    local mode="dry-run"
    local root="$PWD"
    while [ "${1:-}" != "" ]; do
        case "$1" in
            -h|--help)
                cat <<EOF
Usage: tidy-handoff.sh schema-upgrade [--dry-run|--apply] [--root <dir>]
       tidy-handoff.sh schema-upgrade --help

P2.1 schema 迁移：v2 旧四件套（${HX_MAIN_FILE}/${HX_LOGS_DIR}/${HX_DEC_DIR}/）→ handoffx
schema（值由 schema source 派生；P2.2 改名后自动跟随）。仅 v2 schema marker 存在时触发；
已 handoffx → no-op（幂等）。

Options:
  --dry-run    报告将做的迁移，不动文件（默认）
  --apply      原子应用迁移（.partial staging + EXIT-trap rollback）—— Task 3 实装
  --root DIR   项目根（默认 PWD）
Exit: 0 ok or no-op / 1 preflight fail or MIXED split-brain / 2 mid-migration fail (rolled back) / 3 targets committed but source rm failed (manual cleanup)
EOF
                return 0
                ;;
            --dry-run) mode="dry-run" ;;
            --apply)   mode="apply" ;;
            --root)
                [ -n "${2:-}" ] || { echo "❌ --root requires a directory argument" >&2; return 1; }
                root="$2"; shift
                ;;
            *)  # M1 (Task 1 code review): distinguish unknown arg from preflight fail
                # (preflight 返回 1 表示 "已识别 v2 但不可迁"；这里 1 表示 "用法错")
                echo "❌ schema-upgrade: unknown arg: $1" >&2
                echo "   Run --help for usage." >&2
                return 1
                ;;
        esac
        shift
    done

    local state
    state=$(detect_schema_state "$root")
    case "$state" in
        MIXED)
            # Source 2 S2-A Critical / S2-B High：split-brain。任何一边动手都可能
            # 把上次半成功迁移留下的「主」当成「副」rm 掉。fail-loud 拒绝，人工
            # 检阅两边内容确认主从后再操作。
            echo "❌ schema-upgrade: $root has BOTH old four-piece (Handoff_*) AND new handoffx layout coexisting — schema split-brain. Manual triage required: inspect $root, verify which set has authoritative data, manually remove the other set, then re-run." >&2
            return 1
            ;;
        ALREADY-HANDOFFX)
            echo "✅ schema-upgrade: already handoffx schema in $root — no-op (idempotent)"
            return 0
            ;;
        OLD-V2)
            preflight_check "$root" || return 1
            if [ "$mode" = "dry-run" ]; then
                dry_run_report "$root"
                return 0
            else
                migrate_apply "$root"
                return $?
            fi
            ;;
        UNKNOWN)
            echo "❌ schema-upgrade: $root does not contain a v2 handoff schema (no v2 marker or missing four-piece dirs)" >&2
            return 1
            ;;
    esac
}
