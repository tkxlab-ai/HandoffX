#!/bin/bash
# handoffx-upgrade.sh — THE standard upgrade flow for a project still on a
# legacy handoff layout: classify → run the one migrator that fits → post-check
# → list the other files that still name the legacy pieces → print what is
# left for the human.
# Usage: handoffx-upgrade.sh (--dry-run|--apply|--scan-only) [--root DIR] [--no-backup] [--quick] [--sync-paused]   (default root: .)
#        --quick skips the leftover scan (large trees); the checklist says so.
#        --scan-only runs only the leftover scan, on any layout (v4 included),
#        read-only: the full list goes to a temp file. It is the follow-up to
#        --apply --quick, whose tree a later --dry-run calls "already done".
#        --sync-paused: the human has paused the sync of a tree that carries a
#        sync marker (Syncthing / Dropbox / iCloud); without it --apply refuses.
# Exit:  0 done / nothing to upgrade; 1 migrated but a post-check failed, or the
#        rename committed but a legacy piece could not be removed — do not
#        retry; 2 usage error, a layout it refuses (mixed / unknown), a synced
#        tree without --sync-paused, a held project lock, or a pre-upgrade
#        backup it could not create and verify (nothing migrated); 3 the
#        migrator refused (its exit 1: a target already exists, a backup it
#        could not verify, a race) — nothing migrated, fix what it names and
#        rerun; else the migrator's own rc (the migrator has already rolled back).
# Why 3 and not the migrator's 1: 1 is this script's "migrated, do not retry",
# and a refusal read that way sent the AI to /handoffx-tidy on an untouched tree.
#
# Why a wrapper and not a third migrator: v1 and v3 already have atomic,
# rollback-proven migrators; what the /handoffx* commands lacked was one entry
# point that picks between them by content and finishes the job (checks +
# leftovers), so the skill layer can ask once and run one command.
# Why it never prompts: the ask belongs to the skill layer (the AI asks the
# user); a non-interactive script is what tests and CI can drive.
# Why it never runs git beyond one read-only probe: handoff work is orthogonal
# to version control (the skill's first constraint) — committing the rename is
# a listed human step. The probe (`rev-parse --is-inside-work-tree`) only
# decides whether git is the way back; outside a work tree a v3 rename keeps no
# copy, so the four legacy pieces are packed into a verified tarball first.
# Every four-piece name comes from lib/handoff-schema.sh (the only file under
# scripts/ allowed to spell them — tests/test_handoff_schema.sh).
#
# Test-only: HANDOFFX_UPGRADE_FAIL_AT=unreadable-main makes the migrated main
# unreadable before the post-checks (same contract as HANDOFFX_MIGRATE_FAIL_AT),
# so the "migrated but checks failed" path can be proven without a broken tree.
set -euo pipefail

SD="$(cd "$(dirname "$0")" && pwd)"
# Fail closed: without the constants every name below would expand empty.
[ -r "$SD/lib/handoff-schema.sh" ] || { echo "❌ handoffx-upgrade.sh: $SD/lib/handoff-schema.sh missing or unreadable" >&2; exit 2; }
. "$SD/lib/handoff-schema.sh"
# The v2 lib (regenerate_decision_index / regenerate_pointers) runs after the
# migration; bash-only, which this script is.
[ -r "$SD/lib/handoff-v2.sh" ] || { echo "❌ handoffx-upgrade.sh: $SD/lib/handoff-v2.sh missing or unreadable" >&2; exit 2; }
. "$SD/lib/handoff-v2.sh"

usage() { echo "Usage: $0 (--dry-run|--apply|--scan-only) [--root DIR] [--no-backup] [--quick] [--sync-paused]   (default root: .)"; }
MODE="" ROOT="." NO_BACKUP=0 QUICK=0 SYNC_PAUSED=0 BK="" LOCK="" FL="" SCAN_INCOMPLETE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|--apply|--scan-only)
            [ -z "$MODE" ] || { echo "❌ choose one of --dry-run / --apply / --scan-only" >&2; usage >&2; exit 2; }
            MODE="${1#--}" ;;
        --root)
            [ -n "${2:-}" ] || { echo "❌ --root requires a directory argument" >&2; usage >&2; exit 2; }
            ROOT="$2"; shift ;;
        --no-backup) NO_BACKUP=1 ;;
        --quick) QUICK=1 ;;
        --sync-paused) SYNC_PAUSED=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[ -n "$MODE" ] || { echo "❌ missing mode: --dry-run or --apply" >&2; usage >&2; exit 2; }
[ -d "$ROOT" ] || { echo "❌ not a directory: $ROOT" >&2; exit 2; }
# One absolute root for every later path (fix1 I1): a relative root was joined
# into the backup path and then used again inside `cd "$ROOT"`, so the archive
# resolved to root/root/… and every non-git apply with a relative --root
# refused. Logical, not -P: printed paths and the copy-paste line keep the
# user's spelling; sync_check walks the physical path as well.
ROOT=$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd) || { echo "❌ cannot enter: $ROOT" >&2; exit 2; }

# Leftover-scan noise filters. Why: in the field the listing was 306 hits from
# 44 files, nearly all of them backups, sync conflicts, session logs and a
# vendored copy of the old skill — the few real docs drowned. Pruned dirs are
# matched by name at any depth; HANDOFFX_SCAN_PRUNE="dirA dirB" appends more.
# The residual list and the pre-upgrade backup are this script's own output,
# so a rerun must not count them.
SCAN_PRUNE_DIRS=".git node_modules sessions logs venv .venv __pycache__ .pytest_cache cache sandboxes"
SCAN_SKIP_GLOBS="*.jsonl *.sync-conflict-* *.bak_* *.bak.* *.bak .claude-md-bak-* *.pre-v2-backup .handoffx-pre-upgrade-*.tar.gz .handoffx-upgrade-residuals.txt"
# Old registered names (Z4): the stem is built, so this file spells none of
# them (legacy-names guard). Report 4's real leftovers were command-only lines
# in rule files and permission entries pinned to the old skill path.
_HXO=hand; _HXO="${_HXO}off"
RESIDUALS=".handoffx-upgrade-residuals.txt"

# leftover_scan — every other text file under ROOT that still names a legacy
# piece. Why: the migrators rewrite references inside the four pieces only; a
# README, CI job or script pointing at the old paths breaks silently after the
# rename. Informational: it never changes the exit status.
# Excluded besides the noise filters above: the four new pieces, the legacy
# pieces (in a dry-run they still exist and naturally name themselves) and the
# root-level main-file family of both layouts (backups, tidy .bak, the v1
# overflow archive — copies of the main, not references to fix).
# Output: one line per file (hit count + first hit, cut to 120 bytes on a UTF-8
# boundary), most hits first, capped at 50 files; the complete untruncated
# list goes to $RESIDUALS under ROOT on --apply, to a temp file on --dry-run
# (a dry-run writes nothing into the project).
leftover_scan() {
    local e='s/[.[\*^$]/\\&/g' re hits errf lst rows n nf ntext dirs d g full tmpl=""
    local fargs
    re="\\b$(printf '%s' "$HX_LEGACY_MAIN_FILE" | sed "$e")\\b|\\b$(printf '%s' "$HX_LEGACY_LOGS_DIR" | sed "$e")\\b|\\b$(printf '%s' "$HX_LEGACY_DEC_DIR" | sed "$e")\\b"
    re="$re|(^|[^A-Za-z0-9_./-])/hand-?off(-(recall|tidy|init|memory))?([^A-Za-z0-9_-]|\$)|skills/${_HXO}/"
    dirs="$SCAN_PRUNE_DIRS${HANDOFFX_SCAN_PRUNE:+ $HANDOFFX_SCAN_PRUNE}"
    fargs=( \( -path "./$HX_LOGS_DIR" -o -path "./$HX_DEC_DIR" -o -path "./$HX_LEGACY_LOGS_DIR" -o -path "./$HX_LEGACY_DEC_DIR" )
    # set -f: the names and globs are find operands, not for the shell to expand.
    set -f
    for d in $dirs; do fargs+=( -o \( -type d -name "$d" \) ); done
    fargs+=( \) -prune -o -type f ! -path "./$HX_GOTCHAS_FILE" ! -path "./${HX_MAIN_FILE%.md}.*" ! -path "./${HX_LEGACY_MAIN_FILE%.md}.*" )
    fargs+=( ! -path "*/config-backups/*-${_HXO}*" )
    for g in $SCAN_SKIP_GLOBS; do fargs+=( ! -name "$g" ); done
    set +f
    # Codex C7: a temp dir that cannot be made skips the scan out loud; under
    # set -e it used to end the run with exit 1 — "migrated" — on a dry-run.
    # fix3 N5: --scan-only has no other job, so there the skip is a refusal.
    if ! errf=$(mktemp "${TMPDIR:-/tmp}/hxup.XXXXXX" 2>/dev/null) || ! lst=$(mktemp "${TMPDIR:-/tmp}/hxup.XXXXXX" 2>/dev/null); then
        rm -f "${errf:-}"
        if [ "$MODE" = "scan-only" ]; then
            echo "❌ 残留扫描未执行（临时目录不可用：${TMPDIR:-/tmp}）——修好临时目录后重跑 --scan-only" >&2
            exit 2
        fi
        echo "⚠️ 残留扫描未执行（临时目录不可用：${TMPDIR:-/tmp}）——修好后用 --scan-only 补看"
        return 0
    fi
    # Pass 1 lists the text files (grep -I skips binaries; -l '' stops at line
    # 1, so it is cheap) for the progress line; pass 2 greps only those.
    # /dev/null as an extra operand: grep always prints the file name, and an
    # empty file list never makes grep read stdin. Read errors are judged from
    # stderr (an unreadable subdirectory is skipped by find with only a stderr
    # line) AND from every stage's status (fix5 R3: a failing find, list write
    # or xargs used to vanish behind `|| true` with an empty stderr file and
    # read as a clean ✅). Only grep's rc 1 (no match) is normal: the sh -c
    # wrapper turns it into 0 per batch, so any non-zero xargs status is a
    # real failure. pipefail (set at the top) carries find's status out.
    local inc=0 nrc=0
    (cd "$ROOT" && find . "${fargs[@]}" -print0 2>>"$errf" \
        | LC_ALL=C xargs -0 sh -c 'grep -Il "" /dev/null "$@"; [ $? -le 1 ]' sh 2>>"$errf") > "$lst" || inc=1
    ntext=$(grep -c . "$lst") || nrc=$?
    [ "$nrc" -le 1 ] || inc=1
    echo "🔎 残留扫描：${ntext:-0} 个文本文件（跳过目录: ${dirs}）"
    hits=$(cd "$ROOT" && tr '\n' '\0' < "$lst" \
        | LC_ALL=C xargs -0 sh -c 'grep -InE -- "$0" /dev/null "$@"; [ $? -le 1 ]' "$re" 2>>"$errf" | sed 's#^\./##') || inc=1
    rm -f "$lst"
    if [ "$inc" -eq 1 ]; then
        SCAN_INCOMPLETE=1
        echo "⚠️ 残留扫描不完整：枚举 / 清单写入 / 扫描某一步失败，下面的结果可能缺项"
    fi
    if [ -s "$errf" ]; then
        echo "⚠️ 扫描不完整：以下路径读不了，残留清单可能缺项:"
        sed 's/^/   /' "$errf"
    fi
    if [ -z "$hits" ]; then
        if [ -s "$errf" ] || [ "$inc" -eq 1 ]; then
            echo "⚠️ 可读部分无旧名引用，但扫描不完整——不能确认项目无残留"
        else
            echo "✅ 项目其它文件无旧名引用"
        fi
        # A stale list from an earlier run would contradict this verdict.
        if [ "$MODE" = "apply" ]; then rm -f "$ROOT/$RESIDUALS"; fi
        rm -f "$errf"
        return 0
    fi
    rm -f "$errf"
    if [ "$MODE" = "apply" ]; then
        # X7: never write through whatever sits at the final name — a planted
        # symlink would redirect the list outside the project. Refuse a link or
        # non-regular file there; otherwise write a mktemp file (O_EXCL) and
        # rename it over the name (rename replaces, it does not follow).
        full="$ROOT/$RESIDUALS"
        if [ -L "$full" ] || { hx_present "$full" && [ ! -f "$full" ]; }; then
            echo "❌ 不写完整清单：${full} 是符号链接或不是普通文件（不跟随写入；检查并移走它后重跑）"
            full=""
        else
            tmpl=$(mktemp "$ROOT/.hx-residuals.XXXXXX") \
                && chmod "$(printf '%o' $((0666 & ~0$(umask))))" "$tmpl" \
                && printf '%s\n' "$hits" > "$tmpl" && mv -f "$tmpl" "$full" \
                || { rm -f "${tmpl:-}"; full=""; }
        fi
    else
        full=$(mktemp "${TMPDIR:-/tmp}/handoffx-upgrade-residuals.XXXXXX") && printf '%s\n' "$hits" > "$full" || full=""
    fi
    n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    # Rule files (CLAUDE.md / AGENTS.md / .claude settings and hooks / CI) sort
    # first: they steer the agent and the pipeline, so a stale name there
    # breaks things silently, while a stale doc only misleads a reader.
    # Byte classes for the UTF-8 boundary fix-up (LC_ALL=C: lengths are bytes
    # under mawk, BWK awk and gawk alike): a cut that lands inside a multibyte
    # character drops that character's partial bytes instead of printing junk.
    rows=$(printf '%s\n' "$hits" | LC_ALL=C awk -v W=120 \
            -v l2="$(printf '[\300-\337]')" -v l3="$(printf '[\340-\357]')" \
            -v l4="$(printf '[\360-\367]')" -v c="$(printf '[\200-\277]')" '
        function cut(s) {
            gsub(/\t/, " ", s)
            if (length(s) <= W) return s
            s = substr(s, 1, W)
            sub(l2 "$", "", s); sub(l3 c "?$", "", s); sub(l4 c "?" c "?$", "", s)
            return s
        }
        match($0, /:[0-9]+:/) {
            p = substr($0, 1, RSTART - 1)
            if (!(p in cnt)) { order[++k] = p; first[p] = "L" substr($0, RSTART + 1, RLENGTH - 2) ": " cut(substr($0, RSTART + RLENGTH)) }
            cnt[p]++
        }
        function rule(p) {
            return p ~ /(^|\/)(CLAUDE|AGENTS)\.md$/ || p ~ /(^|\/)\.claude\/settings[^\/]*\.json$/ \
                || p ~ /(^|\/)\.claude\/hooks\// || p ~ /(^|\/)\.github\/workflows\// || p ~ /\.ya?ml$/
        }
        END { for (i = 1; i <= k; i++) printf "%d\t%d\t%s\t%s\n", rule(order[i]) ? 0 : 1, cnt[order[i]], order[i], first[order[i]] }' \
        | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2nr -k3,3)
    nf=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    echo "⚠️ 其它文件仍引用旧名（需人工处理）：${nf} 个文件，${n} 处"
    # awk NR<=50, never head: under pipefail a reader that quits early kills
    # the writer with SIGPIPE once the listing outgrows the pipe buffer, and
    # the whole upgrade — a successful migration included — exited 141.
    printf '%s\n' "$rows" | awk -F '\t' '
        NR == 1 && $1 == 0 { print "   ── 规则文件（CLAUDE.md / AGENTS.md / .claude / CI）──"; grp = 1 }
        grp && $1 == 1 && !other && NR <= 50 { print "   ── 其它文件 ──"; other = 1 }
        NR <= 50 { printf "   %s: %s 处 — %s\n", $3, $2, $4 }'
    [ "$nf" -le 50 ] || echo "   …showing 50 of ${nf} files (${n} hits)"
    perm_block "$hits"
    if [ -n "$full" ]; then echo "📄 完整清单: $full"; fi
}

# order_ref — where the full upgrade order lives. Why not MIGRATION_GUIDE: the
# guide is not in the .skill, so an installed skill pointed users at a file
# they did not have; references/migration-order.md ships with it. The second
# path is this repo's own layout (scripts/ beside skills/handoffx/).
order_ref() {
    local r
    for r in "$SD/../references/migration-order.md" "$SD/../skills/handoffx/references/migration-order.md"; do
        if [ -f "$r" ]; then printf '%s\n' "$r"; return 0; fi
    done
    echo "MIGRATION_GUIDE_v2.md §5.6"
}

# perm_block <hits> — permission entries in .claude/settings*.json that pin
# the old skill path, each with a suggested prefix rule. Never edits them: a
# permission is a security decision, and the prefix form is broader than the
# exact rule it replaces.
perm_block() {
    local perm
    perm=$(printf '%s\n' "$1" | grep -F "skills/${_HXO}/" | grep -E '^([^:]*/)?\.claude/settings[^/:]*\.json:' || true)
    [ -n "$perm" ] || return 0
    echo "🔐 权限条目指向旧 skill 路径（请自行决定是否更新，不自动修改）:"
    printf '%s\n' "$perm" | awk -v old="skills/${_HXO}/" '{
        l = $0; gsub(/[[:space:]]+/, " ", l); print "   " l
        if (match($0, /Bash\([^)]*\)/)) {
            s = substr($0, RSTART, RLENGTH); sub(old, "skills/handoffx/", s)
            if (match(s, /\.sh[^)]*\)/)) s = substr(s, 1, RSTART + 2) ":*)"
        } else { s = $0; sub(/^[^:]*:[0-9]+:/, "", s); gsub(old, "skills/handoffx/", s) }
        print "     建议: " s
    }'
    echo "   ℹ️ 前缀规则（:*）比旧的精确规则更宽——每次 postflight 的 --files= 参数都不同，精确规则本来就会一次次失配"
}

# checklist — the human steps of the upgrade order this script cannot do.
# Pausing sync and installing v4 everywhere come first: a rename that races a
# sync, or a v3 skill still writing the old dirs, is how mixed trees are born.
checklist() {
    echo "📝 后续人工步骤（顺序详见 $(order_ref)）:"
    echo "   0a. 暂停本项目目录的同步（Syncthing / Dropbox / iCloud）"
    echo "   0b. 每台机器、每个 CLI 先装 v4"
    # %q: the line is meant to be copy-pasted, and a root with a space or a
    # quote would otherwise split into wrong arguments.
    [ "$MODE" = "dry-run" ] && echo "   1. 确认上面的清单后执行: bash $(printf '%q' "$0") --apply --root $(printf '%q' "$ROOT")${SYNC_HIT:+ --sync-paused}"
    if [ "$QUICK" -eq 1 ]; then
        echo "   2. 已跳过残留扫描（--quick）：之后跑 bash $(printf '%q' "$0") --scan-only --root $(printf '%q' "$ROOT")，处理旧名残留（README / CI / 脚本 / 配置）"
    else
        echo "   2. 处理上面的旧名残留清单（README / CI / 脚本 / 配置）"
    fi
    # Outside git there is nothing to commit; the backup is the way back.
    if in_git_tree; then
        echo '   3. 提交：先删 .handoffx-upgrade-residuals.txt（若有），再 git add -A、git commit（git 会识别为 rename，历史不断）'
    else
        echo '   3. 非 git 项目：确认后可删除 .handoffx-pre-upgrade-*.tar.gz（或移到别处保存）'
    fi
    echo "   4. 有发布链 / 公开镜像时：检查排除表与审计规则里写死的旧名"
    echo "   5. 恢复项目目录同步（Syncthing 等）"
    if [ -n "$BK" ]; then echo "   6. 升级前备份 ${BK}：确认无误后可删除"; fi
    # X4: said once, so a renamed old symptom text is not taken for corruption.
    if [ "$KIND" = v3 ]; then
        echo "   ℹ️ ${HX_GOTCHAS_FILE} 历史原文中的旧文件名已随迁移改写为新名（设计如此；原文见 git 历史或升级前备份）"
    fi
}

# lint_precheck — v4.1.1 X3: lint findings in the legacy corpus used to surface
# only after --apply, as a red postflight on an already-renamed tree. Runs on
# --dry-run before the migrator. handoff-lint reads the NEW sibling names, so a
# v3 corpus is linted through a throwaway mirror (symlinks under the new names
# in a temp dir); the project itself is only read. A v1 file is linted as is.
# Informational: never changes the exit status — a temp dir that cannot be
# made says the pre-check did not run instead (Codex C7).
lint_precheck() {
    local m out n rc=0 skip="⚠️ 迁移前 lint 预检未执行（临时目录不可用：${TMPDIR:-/tmp}）——apply 后的 postflight 仍会检查"
    if [ "$KIND" = v3 ]; then
        m=$(mktemp -d "${TMPDIR:-/tmp}/hxlint.XXXXXX" 2>/dev/null) || { echo "$skip"; return 0; }
        if ! { ln -s "$ROOT/$HX_LEGACY_MAIN_FILE" "$m/$HX_MAIN_FILE" \
            && ln -s "$ROOT/$HX_LEGACY_LOGS_DIR" "$m/$HX_LOGS_DIR" \
            && ln -s "$ROOT/$HX_LEGACY_DEC_DIR" "$m/$HX_DEC_DIR" \
            && ln -s "$ROOT/$HX_GOTCHAS_FILE" "$m/$HX_GOTCHAS_FILE"; } 2>/dev/null; then
            rm -rf "$m"; echo "$skip"; return 0
        fi
        out=$(bash "$SD/handoff-lint.sh" "$m/$HX_MAIN_FILE" 2>&1) || rc=$?
        rm -rf "$m"   # removes the links only; rm never follows them
    else
        out=$(bash "$SD/handoff-lint.sh" "$ROOT/$HX_LEGACY_MAIN_FILE" 2>&1) || rc=$?
    fi
    case "$rc" in
        0) echo "✅ 迁移前 lint 预检通过" ;;
        1)
            n=$(printf '%s\n' "$out" | grep -c '❌' || true)
            echo "⚠️ 迁移前 lint 预检：${n} 处问题（apply 后 postflight 会报；建议先修或接受）"
            printf '%s\n' "$out" | grep '❌' | awk 'NR <= 20 { print "   " $0 }'
            [ "$n" -le 20 ] || echo "   …只列出前 20 处" ;;
        *) echo "⚠️ 迁移前 lint 预检未能运行（rc=${rc}）——apply 后的 postflight 仍会检查" ;;
    esac
}

# sync_check — walk from ROOT up to / looking for a sync client's marker.
# Why: report 4 upgraded a Syncthing tree while sync ran; a rename racing the
# sync comes back as a mixed tree that v4 refuses. Named on every run; on
# --apply it refuses (exit 2, nothing written) until --sync-paused says the
# human has paused it. Sets SYNC_HIT for the checklist's copy-paste line.
# Both the logical and the physical ancestors are walked (Codex C5): a root
# reached through a symlink (/var → /private/var, a ~/Sync link) would
# otherwise skip a marker that sits above the real directory. A marker seen
# from both sides is named once.
SYNC_HIT="" _sync_seen=""
_sync_hit() {
    SYNC_HIT=1
    case "$_sync_seen" in *"|$1|"*) return 0 ;; esac
    _sync_seen="$_sync_seen|$1|"
    echo "⚠️ 检测到同步目录标记: $1"
}
_sync_walk() {
    local d="$1" m
    case "$d/" in
        */Library/Mobile\ Documents/*) _sync_hit "/Library/Mobile Documents/ at ${d%%/Library/Mobile Documents/*}" ;;
    esac
    while :; do
        for m in .stfolder .dropbox .dropbox.cache; do
            if hx_present "$d/$m"; then _sync_hit "$m at $d"; fi
        done
        # "." too: dirname of a relative path ends there, and dirname . is "."
        [ "$d" != / ] && [ "$d" != . ] && [ -n "$d" ] || break
        d=$(dirname "$d")
    done
}
sync_check() {
    local p
    _sync_walk "$ROOT"
    p=$(cd "$ROOT" && pwd -P) || p="$ROOT"
    [ "$p" = "$ROOT" ] || _sync_walk "$p"
    if [ -n "$SYNC_HIT" ] && [ "$MODE" = apply ] && [ "$SYNC_PAUSED" -ne 1 ]; then
        echo "❌ 项目在同步目录里：先暂停同步（Syncthing / Dropbox / iCloud），再加 --sync-paused 重跑 --apply；未写任何文件" >&2
        exit 2
    fi
    return 0
}

# in_git_tree — the read-only probe that decides whether git is the way back.
# A missing git, "not a repository" and any other error all mean "no".
in_git_tree() { [ "$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; }

# take_backup — pack the four legacy pieces (relative paths, from ROOT) and
# accept the archive only if its listing equals the tree it was made from.
# Fail closed: anything short of a verified archive removes what this function
# wrote and exits 2 before the migrator runs, so the project is untouched.
# COPYFILE_DISABLE: macOS tar would otherwise add ._ AppleDouble entries.
take_backup() {
    local want got errf
    BK="$ROOT/.handoffx-pre-upgrade-$(date +%Y%m%d-%H%M%S).tar.gz"
    if hx_present "$BK"; then
        echo "❌ 无法创建升级前备份：${BK} 已存在；未迁移任何文件" >&2; BK=""; exit 2
    fi
    errf=$(mktemp "${TMPDIR:-/tmp}/hxbk.XXXXXX" 2>/dev/null) || {
        echo "❌ 无法创建升级前备份：临时目录不可用（${TMPDIR:-/tmp}）；未迁移任何文件" >&2; BK=""; exit 2; }
    # The upgrade's own lock state (the mkdir lock dir and the writers' flock
    # file, which this run may have created empty) is left out of the archive
    # and its listing: a restore must not bring back a lock.
    if ! ( cd "$ROOT" && COPYFILE_DISABLE=1 tar czf "$BK" --exclude="$HX_LEGACY_LOGS_DIR/.lock.d" --exclude="$HX_LEGACY_LOGS_DIR/.lock" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR" "$HX_GOTCHAS_FILE" ) 2>"$errf"; then
        rm -f "$BK"
        echo "❌ 无法创建升级前备份 ${BK}（项目根不可写？）；未迁移任何文件:" >&2
        sed 's/^/   /' "$errf" >&2; rm -f "$errf"; BK=""; exit 2
    fi
    rm -f "$errf"
    want=$(cd "$ROOT" && find "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR" "$HX_GOTCHAS_FILE" \
        \( -path "$HX_LEGACY_LOGS_DIR/.lock.d" -o -path "$HX_LEGACY_LOGS_DIR/.lock" \) -prune -o -print | LC_ALL=C sort) || want=""
    got=$(tar tzf "$BK" 2>/dev/null | sed 's#/$##' | LC_ALL=C sort) || got=""
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        rm -f "$BK"
        echo "❌ 升级前备份校验失败（归档内容与旧四件套不一致）；已删除该归档，未迁移任何文件" >&2; BK=""; exit 2
    fi
    echo "🗄 升级前备份: ${BK}（$(printf '%s\n' "$want" | wc -l | tr -d ' ') 项，已校验）"
}

# release_lock — on every exit after the lock was taken. The migrator copies
# the legacy logs dir, lock included, so the copy under the new name goes too.
# Only the mkdir lock dirs: a flock FILE is never unlinked (fix3 N2). Once
# the new dir is published a v4 writer may already hold an fd on its copied
# .lock; unlinking it lets the next writer create a fresh inode and lock that
# one — two holders. An empty flock file is harmless, and the migrator's
# removal of the legacy dir already takes the original with it.
release_lock() {
    [ -n "$LOCK" ] || return 0
    hx_release_lock "$LOCK"
    hx_release_lock "$ROOT/$HX_LOGS_DIR/.lock.d"
}
trap release_lock EXIT

# --scan-only (Codex C10): the leftover scan alone, on any layout — the
# follow-up to --apply --quick, whose tree is v4 by then. Read-only.
if [ "$MODE" = "scan-only" ]; then
    leftover_scan
    if [ "$SCAN_INCOMPLETE" -eq 1 ]; then
        echo "❌ 残留扫描不完整——上面的清单不能当作完整结果；修好原因后重跑 --scan-only" >&2
        exit 2
    fi
    exit 0
fi

KIND=$(hx_legacy_layout_kind "$ROOT")
echo "📋 布局判定: $KIND"
case "$KIND" in v1|v3) sync_check ;; esac
case "$KIND" in
    none)
        if hx_present "$ROOT/$HX_MAIN_FILE"; then
            echo "✅ 已是 handoffx 布局，无需升级"
        else
            echo "ℹ️ 没有任何 handoff 文档，请用 /handoffx-init 初始化"
        fi
        exit 0 ;;
    v1)
        # Braces on every expansion next to CJK text: bash 3.2 reads UTF-8
        # lead bytes as identifier characters, so "$NAME）" is an unbound name.
        echo "   v1 单文件 ${HX_LEGACY_MAIN_FILE} → migrate-to-v2.sh 一步产出新布局（${HX_MAIN_FILE} + ${HX_LOGS_DIR}/ + ${HX_DEC_DIR}/ + ${HX_GOTCHAS_FILE}），原文件保留 .pre-v2-backup"
        MIGRATOR=(bash "$SD/migrate-to-v2.sh") ;;
    v3)
        echo "   旧四件套（${HX_LEGACY_MAIN_FILE} + ${HX_LEGACY_LOGS_DIR}/ + ${HX_LEGACY_DEC_DIR}/ + ${HX_GOTCHAS_FILE}）→ tidy-handoff.sh schema-upgrade 原子改名"
        if [ "$NO_BACKUP" -eq 1 ]; then
            echo "   --no-backup：不打升级前备份（回退自理）"
        elif in_git_tree; then
            echo "   git 工作树：不打包（靠 git 回退）"
        elif [ "$MODE" = "dry-run" ]; then
            echo "   非 git 项目：--apply 会先打包旧四件套到 .handoffx-pre-upgrade-<时间>.tar.gz 并校验，再迁移"
        fi
        # The numbering lock a /handoffx write takes (acquire_next_number),
        # held from before the backup to the end of the run. Writers use one
        # of two primitives on the logs dir they write to: flock on
        # <logs>/.lock where flock exists (Linux), the mkdir lock <logs>/.lock.d
        # elsewhere — so the upgrade holds both (Codex C4), and either one held
        # makes it refuse (exit 2). Both live in the legacy logs dir: that is
        # where a v3 writer on this tree looks. The exact guarantee (fix5 R2):
        # this stops v3 writers from TAKING A NUMBER; it is not mutual
        # exclusion of a whole write (the writer releases the lock as soon as
        # the number is returned). The migration copies the logs dir, .lock.d
        # included, and that copy is removed only when the upgrade exits — so
        # during the post-checks the new dir is closed to mkdir numbering too,
        # not to flock numbering (the flock is on the old inode). Running
        # handoff write sessions must be stopped before migrating
        # (migration-order.md steps 1-2).
        if [ "$MODE" = apply ]; then
            hx_take_lock "$ROOT/$HX_LEGACY_LOGS_DIR/.lock.d" handoffx-upgrade.sh || { echo "   未写任何文件" >&2; exit 2; }
            LOCK="$ROOT/$HX_LEGACY_LOGS_DIR/.lock.d"
            if command -v flock >/dev/null 2>&1; then
                FL="$ROOT/$HX_LEGACY_LOGS_DIR/.lock"
                # fd 9 stays open (and inherited by the migrator) until exit.
                if ! { exec 9>>"$FL"; } 2>/dev/null || ! flock -n 9; then
                    echo "❌ handoffx-upgrade.sh: lock held: $FL (flock；另一个写入正在进行)；未写任何文件" >&2; exit 2
                fi
            fi
            if [ "$NO_BACKUP" -ne 1 ] && ! in_git_tree; then take_backup; fi
        fi
        MIGRATOR=(bash "$SD/tidy-handoff.sh" schema-upgrade) ;;
    *)
        echo "   新旧并存或无法判定——不升级、不写任何文件，见下面的说明"
        hx_refuse_if_legacy_layout "$ROOT" handoffx-upgrade.sh || true
        exit 2 ;;
esac

if [ "$MODE" = "dry-run" ]; then lint_precheck; fi
rc=0; "${MIGRATOR[@]}" "--$MODE" --root "$ROOT" || rc=$?
if [ "$rc" -ne 0 ]; then
    # fix1 I2: the migrator's 1 is a refusal before any write; ours means
    # "migrated" — map it so the caller does not skip the retry. schema-upgrade's
    # own 3 (renamed, a legacy piece left behind) is the opposite: it migrated,
    # so it becomes our 1 and 3 keeps one meaning.
    if [ "$rc" -eq 3 ]; then
        echo "❌ 迁移已提交，但旧件未能删除（见上面的 ⚠️）；不要重试，按提示手工清理" >&2
        rc=1
    elif [ "$rc" -eq 1 ]; then
        echo "❌ 迁移器拒绝（exit 3）：未迁移任何文件，项目保持原样；按上面的输出处理后重跑" >&2
        rc=3
    else
        echo "❌ 迁移器失败（rc=${rc}）；迁移器已回滚，项目保持原样" >&2
    fi
    if [ -n "$BK" ]; then echo "   升级前备份仍在: $BK" >&2; fi
    exit "$rc"
fi

if [ "$MODE" = "dry-run" ]; then
    if [ "$QUICK" -eq 0 ]; then leftover_scan; fi
    checklist
    exit 0
fi

checks_ok=1
# Neither migrator writes the decision INDEX (only the first /handoffx write
# did), so a recall right after the upgrade found none; build it and refresh
# the pointer stats now, before the checks look at the tree.
if regenerate_decision_index "$ROOT" && regenerate_pointers "$ROOT/$HX_MAIN_FILE"; then
    echo "✅ 已生成 ${HX_DEC_DIR}/INDEX.md 并刷新主文件指针"
else
    echo "❌ 生成 ${HX_DEC_DIR}/INDEX.md 或刷新主文件指针失败"; checks_ok=0
fi
[ "${HANDOFFX_UPGRADE_FAIL_AT:-}" = "unreadable-main" ] && chmod 000 "$ROOT/$HX_MAIN_FILE"
if bash "$SD/validate-handoff.sh" --readiness "$ROOT"; then
    echo "✅ validate --readiness 通过"
else
    echo "❌ validate --readiness 未通过"; checks_ok=0
fi
bash "$SD/handoff-postflight.sh" --quiet "$ROOT/$HX_MAIN_FILE" || checks_ok=0
if [ "$QUICK" -eq 0 ]; then leftover_scan; fi
checklist
if [ "$checks_ok" -ne 1 ]; then
    echo "❌ 迁移已完成；后置检查未过，请看上面的输出"
    exit 1
fi
echo "✅ 升级完成"
