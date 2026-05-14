#!/bin/bash
# test_project_tree_forbidden.sh — 项目根禁止驻留 stale archive / planning 目录
#
# 历史故障：v1.2.6 leak HANDOFF.md.bak*；v1.2.7 leak docs/superpowers/{plans,specs}/——
# 都是项目根累积的内部 artifact 被 gitx-release wrapper 不完美的 rsync exclude 漏过去
# 进了 source tarball。
#
# 这个测试在 preflight 阶段（run_all.sh 走之前）扫项目根，发现禁路径**直接 fail
# 阻止 release**。和 test_release_artifact_content.sh 互补：
#   - 本测试：源头闸门——project tree 不该有的东西不能存在
#   - artifact-content 测试：post-build 兜底——已生成 tarball 不该含的东西
#
# 注：HANDOFF.md.bak* 不在禁列——tidy-handoff.sh 会临时生成 .bak.tidy-*；rely on
# artifact-content 测试和发版前手动清理。其他真"该移出项目"的目录用本测试管控。
source "$(dirname "$0")/common.sh"

# 禁存路径（glob pattern；展开为 0 个或多个真实条目）
FORBIDDEN_GLOBS=(
    "$ROOT_DIR/Handoff_OldBackup_"*
    "$ROOT_DIR/Handoff_planning_"*
    "$ROOT_DIR/docs/superpowers"
)

shopt -s nullglob

# 用 nullglob 展开 + 检查是否有真实匹配
# 注：FORBIDDEN_GLOBS 在 source 时还没 nullglob 状态，所以已经被早期 shell 展开
# 改用临时变量 + 显式展开
declare -a EXISTING

# Method: re-expand each label individually under nullglob
declare -a LABELS=(
    "Handoff_OldBackup_*"
    "Handoff_planning_*"
    "docs/superpowers"
)

for label in "${LABELS[@]}"; do
    # 展开 ROOT_DIR/<label>。nullglob 仅对真有 glob 字符的 pattern 有效；字面路径
    # 即使不存在也会作为字符串返回，所以再用 [ -e ] 过滤一次确保是真实存在条目。
    matches=( "$ROOT_DIR"/$label )
    existing=()
    for m in "${matches[@]}"; do
        [ -e "$m" ] && existing+=("$m")
    done
    if [ "${#existing[@]}" -gt 0 ]; then
        echo "  ❌ 项目根禁止路径存在：$label"
        for m in "${existing[@]}"; do
            echo "      $m"
        done
        FAIL=$((FAIL+1))
    else
        echo "  ✅ 项目根无 $label"
        PASS=$((PASS+1))
    fi
done

shopt -u nullglob

summary
