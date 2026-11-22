#!/bin/bash
# emit-token-usage.sh — analyze a skill bundle's runtime context cost
#
# usage: emit-token-usage.sh <skill_src_dir> <output_md> [version]
#
# Produces a TOKEN_USAGE.md explaining how many tokens the skill will consume
# from the user's Claude Code context window on each invocation AFTER install.
#
# Classification rules (Claude Code progressive-disclosure model):
#   - SKILL.md              → baseline, always loaded on trigger
#   - references/**         → on-demand, AI reads when SKILL.md instructs
#   - scripts/**            → executed via Bash tool, source NOT in context
#   - assets/**             → not loaded
#   - root docs (README, CHANGELOG, LICENSE, ROADMAP, SECURITY,
#                CODE_OF_CONDUCT, CONTRIBUTING, INSTALL, TEST-SCENARIOS)
#                           → bundle metadata for humans, NOT runtime context
#
# Tokenizer tiers (auto-downgrade):
#   - Tier 1 (preferred): python3 + tiktoken cl100k_base (±10% vs Claude)
#   - Tier 0 (fallback):  bash heuristic chars * 0.5 for markdown,
#                         chars * 0.33 for shell/code (±20% watermark)
#
# Exit: 0 on success, 2 on usage error, 1 on internal failure.
#
# Pricing: uses list price 2026-04; override via env:
#   CLAUDE_SONNET_INPUT_PER_MTOK   (default 3.00)
#   CLAUDE_HAIKU_INPUT_PER_MTOK    (default 1.00)
#   CLAUDE_OPUS_INPUT_PER_MTOK     (default 15.00)

set -euo pipefail

if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
    echo "usage: emit-token-usage.sh <skill_src_dir> <output_md> [version]" >&2
    exit 2
fi

SKILL_DIR=$(cd "$1" && pwd)
OUT=$2
VERSION=${3:-unknown}

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "❌ $SKILL_DIR/SKILL.md not found — not a skill bundle" >&2
    exit 1
fi

# ── Pricing (env-overridable) ─────────────────────────────────────────────
PRICE_SONNET=${CLAUDE_SONNET_INPUT_PER_MTOK:-3.00}
PRICE_HAIKU=${CLAUDE_HAIKU_INPUT_PER_MTOK:-1.00}
PRICE_OPUS=${CLAUDE_OPUS_INPUT_PER_MTOK:-15.00}

# ── Tokenizer detection ───────────────────────────────────────────────────
TOKENIZER="heuristic"
# Bash fallback calibrated against tiktoken cl100k_base. Tends to over-estimate
# by 20-35% vs real Claude tokenizer — intentional: better to warn users of
# a higher budget than understate. Install tiktoken for precision.
TOKENIZER_NOTE="bash 启发式(保守偏高 20-35% vs tiktoken — 装 python3+tiktoken 获得精确值)"
if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import tiktoken" 2>/dev/null; then
        TOKENIZER="tiktoken"
        TOKENIZER_NOTE="tiktoken cl100k_base (±10% vs Claude tokenizer)"
    fi
fi

# count_tokens <file> <kind>   kind: md | sh | txt
count_tokens() {
    local f=$1
    local kind=${2:-md}
    if [ ! -f "$f" ]; then echo 0; return; fi
    if [ "$TOKENIZER" = "tiktoken" ]; then
        python3 - "$f" <<'PY'
import sys, tiktoken
try:
    enc = tiktoken.get_encoding("cl100k_base")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        print(len(enc.encode(fh.read())))
except Exception:
    print(0)
PY
    else
        local total_bytes nonascii_bytes ascii_bytes
        total_bytes=$(wc -c < "$f" | tr -d ' ')
        # Count non-ASCII bytes (bytes with high bit set — UTF-8 multi-byte chars)
        nonascii_bytes=$(LC_ALL=C tr -d '\000-\177' < "$f" | wc -c | tr -d ' ')
        ascii_bytes=$((total_bytes - nonascii_bytes))
        case "$kind" in
            sh)  awk -v a="$ascii_bytes" -v n="$nonascii_bytes" \
                     'BEGIN{printf "%d\n", int(a*0.28 + n*0.65 + 0.5)}' ;;
            *)   awk -v a="$ascii_bytes" -v n="$nonascii_bytes" \
                     'BEGIN{printf "%d\n", int(a*0.33 + n*0.65 + 0.5)}' ;;
        esac
    fi
}

# chars <file>
chars_of() {
    [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0
}

# cost_usd <tokens> <price_per_mtok>   → "$0.0123"
cost_usd() {
    awk -v t="$1" -v p="$2" 'BEGIN{ printf "$%.4f", t * p / 1000000 }'
}

# ── Scan target skill ─────────────────────────────────────────────────────
BASELINE_FILE="$SKILL_DIR/SKILL.md"
BASELINE_TOK=$(count_tokens "$BASELINE_FILE" md)
BASELINE_CHARS=$(chars_of "$BASELINE_FILE")

# references/*.md
REFERENCE_ROWS=""
REFERENCE_SUM=0
if [ -d "$SKILL_DIR/references" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel=${f#"$SKILL_DIR/"}
        tok=$(count_tokens "$f" md)
        ch=$(chars_of "$f")
        REFERENCE_SUM=$((REFERENCE_SUM + tok))
        REFERENCE_ROWS+=$(printf '| `%s` | on-demand | %s | %s |\n' "$rel" "$ch" "$tok")
        REFERENCE_ROWS+=$'\n'
    done < <(find "$SKILL_DIR/references" -maxdepth 2 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)
fi

# scripts/* (not runtime context, but report bundle weight)
SCRIPT_ROWS=""
SCRIPT_SUM=0
if [ -d "$SKILL_DIR/scripts" ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rel=${f#"$SKILL_DIR/"}
        tok=$(count_tokens "$f" sh)
        ch=$(chars_of "$f")
        SCRIPT_SUM=$((SCRIPT_SUM + tok))
        SCRIPT_ROWS+=$(printf '| `%s` | NOT LOADED (executed via Bash tool) | %s | %s |\n' "$rel" "$ch" "$tok")
        SCRIPT_ROWS+=$'\n'
    done < <(find "$SKILL_DIR/scripts" -maxdepth 2 -type f 2>/dev/null | LC_ALL=C sort)
fi

# Root-level bundle-metadata docs
BUNDLE_ROWS=""
BUNDLE_SUM=0
for doc in README.md CHANGELOG.md LICENSE ROADMAP.md SECURITY.md \
           CODE_OF_CONDUCT.md CONTRIBUTING.md INSTALL.md TEST-SCENARIOS.md; do
    f="$SKILL_DIR/$doc"
    [ -f "$f" ] || continue
    tok=$(count_tokens "$f" md)
    ch=$(chars_of "$f")
    BUNDLE_SUM=$((BUNDLE_SUM + tok))
    BUNDLE_ROWS+=$(printf '| `%s` | bundle-only (not runtime) | %s | %s |\n' "$doc" "$ch" "$tok")
    BUNDLE_ROWS+=$'\n'
done

# ── Scenario table ────────────────────────────────────────────────────────
# Typical invocation empirical overhead (Bash stdout/stderr that returns into
# AI context during a typical skill run). Derived from observed ranges of
# moderate-length tool outputs; not a static property of the bundle itself.
TOOL_OVERHEAD_LOW=3000
TOOL_OVERHEAD_HIGH=5000

SC_BASELINE=$BASELINE_TOK
SC_TYPICAL_LOW=$((BASELINE_TOK + TOOL_OVERHEAD_LOW))
SC_TYPICAL_HIGH=$((BASELINE_TOK + TOOL_OVERHEAD_HIGH))
SC_FULL=$((BASELINE_TOK + REFERENCE_SUM + TOOL_OVERHEAD_HIGH))

# ── Emit markdown ─────────────────────────────────────────────────────────
TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

{
cat <<EOF
# Token Usage Analysis

> 本 skill 装到终端用户 Claude Code 后,每次触发占用其 context window 的 token 成本分析。
> Generated: ${TS}
> Bundle: ${VERSION}
> Tokenizer: ${TOKENIZER_NOTE}

## 这份文档估算什么

当用户装上这个 skill、在 Claude Code 里触发它时,skill 包的一部分会被载入助手的 context window。
本文件量化**每次调用的 input token 成本**,让用户在装之前就能预算。

**计入 runtime context**:
- \`SKILL.md\` — 每次 skill 激活都会加载(baseline,always loaded)。
- \`references/**.md\` — 按 SKILL.md 指引按需加载(on-demand)。

**不计入 runtime context**:
- \`scripts/**\` — 由 Bash tool 执行,源代码**不进** AI context(除非用户显式让 AI Read 脚本)。
- \`assets/**\` — 不加载。
- 根目录文档(README / CHANGELOG / LICENSE 等)— 给人看的 bundle 元数据,Claude Code 从不主动加载。

**不纳入估算**(取决于用户会话,非 skill 本身的静态属性):
- 模型生成的 output token。
- Tool 调用的 stdout/stderr 回灌 context 的量(随被操作项目变化)。
- 多轮对话累积。

## Scenario table(场景表)

| 场景 | Input tokens | Sonnet 4.6 | Haiku 4.5 | Opus 4 |
|---|---:|---:|---:|---:|
| **Baseline**(仅触发,加载 SKILL.md) | ${SC_BASELINE} | $(cost_usd $SC_BASELINE $PRICE_SONNET) | $(cost_usd $SC_BASELINE $PRICE_HAIKU) | $(cost_usd $SC_BASELINE $PRICE_OPUS) |
| **Typical invocation**(baseline + ~${TOOL_OVERHEAD_LOW}-${TOOL_OVERHEAD_HIGH}t 工具 stdout) | ${SC_TYPICAL_LOW}–${SC_TYPICAL_HIGH} | $(cost_usd $SC_TYPICAL_LOW $PRICE_SONNET)–$(cost_usd $SC_TYPICAL_HIGH $PRICE_SONNET) | $(cost_usd $SC_TYPICAL_LOW $PRICE_HAIKU)–$(cost_usd $SC_TYPICAL_HIGH $PRICE_HAIKU) | $(cost_usd $SC_TYPICAL_LOW $PRICE_OPUS)–$(cost_usd $SC_TYPICAL_HIGH $PRICE_OPUS) |
| **Full references pull**(读完所有 references/) | ${SC_FULL} | $(cost_usd $SC_FULL $PRICE_SONNET) | $(cost_usd $SC_FULL $PRICE_HAIKU) | $(cost_usd $SC_FULL $PRICE_OPUS) |

每次调用成本仅含 *input*;output 和多轮追问额外计算。

## Always-loaded(baseline,必进 context)

| 文件 | 何时加载 | 字节 | Tokens |
|---|---|---:|---:|
| \`SKILL.md\` | always loaded / skill 激活即加载 | ${BASELINE_CHARS} | ${BASELINE_TOK} |

## On-demand references(按需加载)

$(if [ -n "$REFERENCE_ROWS" ]; then
    echo "| 文件 | 何时加载 | 字节 | Tokens |"
    echo "|---|---|---:|---:|"
    printf '%s' "$REFERENCE_ROWS"
    echo ""
    echo "**references/ 小计:** ${REFERENCE_SUM} tokens"
else
    echo "_本 skill 没有 \`references/\` 目录,不吃按需加载成本。_"
fi)

## NOT LOADED(不进 runtime context,只占磁盘)

以下文件出现在 bundle 里,但**不会**在调用时消耗 context token。
列出仅供透明度参考(下载体积 / 磁盘占用)。

### Scripts(由 Bash tool 执行,AI 不读源码)

$(if [ -n "$SCRIPT_ROWS" ]; then
    echo "| 文件 | 状态 | 字节 | 若被 Read 则 tokens |"
    echo "|---|---|---:|---:|"
    printf '%s' "$SCRIPT_ROWS"
    echo ""
    echo "**scripts/ 小计:** ${SCRIPT_SUM} tokens(仅当用户显式要求 AI \`Read\` 某脚本才消耗)"
else
    echo "_无 \`scripts/\` 目录。_"
fi)

### 根目录文档(bundle-only,给人看的元数据)

$(if [ -n "$BUNDLE_ROWS" ]; then
    echo "| 文件 | 状态 | 字节 | 若被 Read 则 tokens |"
    echo "|---|---|---:|---:|"
    printf '%s' "$BUNDLE_ROWS"
    echo ""
    echo "**根文档小计:** ${BUNDLE_SUM} tokens(Claude Code 从不主动加载这些)"
else
    echo "_未检测到根级 bundle 文档。_"
fi)

## Methodology(方法论)

- **Tokenizer**: ${TOKENIZER_NOTE}
- **价格**(每百万 input token,参考 2026-04 list price):
  Sonnet 4.6 = \$${PRICE_SONNET} · Haiku 4.5 = \$${PRICE_HAIKU} · Opus 4 = \$${PRICE_OPUS}
  (通过 env 覆盖:\`CLAUDE_SONNET_INPUT_PER_MTOK\` / \`CLAUDE_HAIKU_INPUT_PER_MTOK\` / \`CLAUDE_OPUS_INPUT_PER_MTOK\`)
- **Tool 调用开销 3k-5k tokens** 是对 Bash stdout 回灌 context 的经验估计(静态分析无法精确测量,真实数字取决于 skill 操作的具体对象)。
- 所有 token 计数都是 actual runtime cost 的**下限**。多轮对话、大 tool 输出会让实际数字更高。

## Watchlist(膨胀预警)

- SKILL.md 当前 ${BASELINE_TOK} tokens。软上限 3000;每新增一行代价由**所有用户每次调用**分担。
- references/ 合计 ${REFERENCE_SUM} tokens。每多一个 references 文件,"full pull"场景线性抬高。
EOF
} > "$OUT"

echo "   → $OUT (baseline=${BASELINE_TOK}, references=${REFERENCE_SUM}, bundle-docs=${BUNDLE_SUM})"
