# P1.2 — B① fail-closed 硬化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: 用 superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans 逐任务实施。步骤用 checkbox(`- [ ]`)跟踪。
> **沟通语言**：本项目 `CLAUDE.md` 强制中文散文(代码/标识符/路径/无中文对应技术名词除外)。

**目标**：把 B① 这个 doc-integrity gate 从 fail-open(不可读文件 / 全 typo 路径 / 零文件处理 → 仍打印 `✅ clean` exit 0,真实 dangling ref 静默 ship)改为 fail-closed(无法检查 = 显式报错非零,绝不计 clean)。

**架构**:修复全部落在 gate 策略层 `scripts/handoff-xref-lint.sh`(+ 其双源副本)。grammar 纯解析器 `handoff-xref-grammar.sh` 的 `[ -f "$f" ] || return 0` **保留不动**(Decision 0022 明示:grammar 层 absent=合法跳过;fail-closed 是 caller/gate 层职责)——仅给 `_rl_strip_code_spans` 的 `2>/dev/null` 补一行不变式注释(over-flag 安全 / under-flag 绝不可)。postflight 已「取 5 检查最差退出码」,gate 退出码修好后 fail-closed 自动端到端传播,**postflight 不改**(最小 scope)。

**技术栈**:Bash 3.2 / mawk-safe + markdown。无 git(§1)。TDD via `tests/common.sh`;`tests/run_all.sh` 自动发现 `test_*.sh`。

**Spec 真相源(Boss 已授权,勿重开 brainstorming)**：
- `Handoff_Decisions/0022-2026-05-17-b1-fail-open-gate-escalation-p1-2.md`(决策 A + Linus 三问 + P1.2 scope 提案四项 + 反悔代价)
- `Handoff_Logs/0054-*.md`(silent-failure-hunter I-1'/I-2' 实测复现 + 机械溯源)
- `GOTCHAS.md` #24(fail-open gate 母题:`[ -f ]`≠`[ -r ]` / 零处理=clean / `2>/dev/null`+无 pipefail;须异构多源)+ #18/#20(假绿比红危险)

**Scope lock**：仅 Decision 0022 四项 —— ① `handoff-xref-lint.sh` 加 `set -o pipefail`;② per-file 可读性闸(存在但不可读 → 报错非零,绝不 clean);③ unprocessable / 零处理计数(给了非模板 arg 却零处理 → 报错非零);④ grammar lib `2>/dev/null` 非对称不变式注释。**Out of scope**:grammar 解析逻辑、`[ -f ]||return 0`(Decision 0022 明示保留)、postflight、P2、性能轨、P1.1 已 shipped 三项 grammar。

**双源(同 P1/P1.1,与 P0 相反)**：`scripts/handoff-xref-lint.sh` 与 `skills/handoff/scripts/handoff-xref-lint.sh` 必须 byte-identical(`test_scripts_sync.sh` 强制,**不在 DEV_ONLY**);grammar lib 注释改动同理双源。测试文件 `tests/test_*.sh` 不双源。

**Coupling 提醒(本计划不实现)**:grammar lib 路径常量是唯一 P2 改名 locus(coupling b);P1.2 仅给 lib 加注释、不碰常量、不碰 grammar fn 逻辑。

**多源审(Gotcha #22 / #24,Boss 已定)**:self-hosted review-loop(耦合 a)+ 独立 opus + **Codex stop-time 由 Boss 触发作第 3 源**(P1.1 时 Codex 留给 P1.2,Boss Q3 决)。每 finding TDD RED→GREEN→controller 对抗复现,不信「看似修好」。

---

## 文件结构

| 文件 | 职责 | 类别 |
|------|------|------|
| `scripts/handoff-xref-lint.sh` + `skills/handoff/scripts/handoff-xref-lint.sh` | gate 层 fail-closed:`set -o pipefail` + 可读性闸 + unprocessable/零处理计数 + 非零退出 + stderr 诊断 | Modify(双源) |
| `scripts/lib/handoff-xref-grammar.sh` + 双源副本 | 仅 `_rl_strip_code_spans` 上方加 `2>/dev/null` 非对称不变式注释。grammar fn 逻辑/常量不动 | Modify(双源,注释 only) |
| `tests/test_handoff_xref_lint.sh` | fail-open RED→fail-closed GREEN + 合法跳过(template/absent-aggregate)回归 | Modify |

无其它文件改动。

---

## Task 1: RED — fail-open 复现(不可读 / 零处理 / 合法跳过边界)

**Files:** Test: `tests/test_handoff_xref_lint.sh`(append 在最后 `summary` 之前)

- [ ] **Step 1: 写失败测试**

在 `tests/test_handoff_xref_lint.sh` 末尾 `summary` 行之前插入(用既有 `$LINT`/`$TMP_DIR`):

```bash
# --- P1.2 fail-closed: gate 无法检查时绝不报 clean(Decision 0022 / Gotcha #24)---
P12_W="$TMP_DIR/p12-$$"; rm -rf "$P12_W"; mkdir -p "$P12_W/Handoff_Logs" "$P12_W/assets"
# (a) 存在但不可读 → 必须非零 + 不得打印 clean(I-1')
ur="$P12_W/UNREAD.md"; printf 'see Decision 9999 real dangling\n' > "$ur"; chmod 000 "$ur"
p12a_ec=$(bash "$LINT" "$ur" >/dev/null 2>&1; echo $?)
p12a_out=$(bash "$LINT" "$ur" 2>&1)
chmod 644 "$ur"
assert_exit "P1.2a: 不可读文件 → 非零退出(非 clean)" 0 "$([ "$p12a_ec" != "0" ] && echo 0 || echo 1)"
assert_not_contains "P1.2a: 不可读绝不打印 write-target set clean" "$p12a_out" "write-target set clean"
# (b) 全部 typo/absent 路径 → 零处理,必须非零(I-2',不得 ✅ clean)
p12b_ec=$(bash "$LINT" "$P12_W/NOPE_A.md" "$P12_W/NOPE_B.md" >/dev/null 2>&1; echo $?)
p12b_out=$(bash "$LINT" "$P12_W/NOPE_A.md" "$P12_W/NOPE_B.md" 2>&1)
assert_exit "P1.2b: 全 absent 路径 → 非零(零处理不算 clean)" 0 "$([ "$p12b_ec" != "0" ] && echo 0 || echo 1)"
assert_not_contains "P1.2b: 零处理绝不打印 clean" "$p12b_out" "write-target set clean"
# (c) 合法跳过边界:仅 template arg → 仍 exit 0(template 是 deliberate skip,非 fail)
tmpl="$P12_W/assets/HANDOFF.template.md"; printf 'Owner: <项目负责人>\n' > "$tmpl"
assert_exit "P1.2c: 仅 template arg → 仍合法 exit 0" 0 "$(bash "$LINT" "$tmpl" >/dev/null 2>&1; echo $?)"
# (d) 正常 clean 仍 exit 0(无回归)
mkdir -p "$P12_W/Handoff_Decisions"; printf 'x\n' > "$P12_W/Handoff_Logs/0042-2026-01-01-x.md"
ok="$P12_W/ok.md"; printf 'see Dev Log 0042\n' > "$ok"
assert_exit "P1.2d: 正常可读 clean 文件 → exit 0(无回归)" 0 "$(bash "$LINT" "$ok" >/dev/null 2>&1; echo $?)"
# (e) 真实 finding 仍 exit 1(无回归)
ng="$P12_W/ng.md"; printf 'see Dev Log 7777\n' > "$ng"
assert_exit "P1.2e: 真实 dangling → 仍 exit 1(无回归)" 1 "$(bash "$LINT" "$ng" >/dev/null 2>&1; echo $?)"
rm -rf "$P12_W"
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `cd <dev-home>/tkbox/Cloud_Coding/Handoff && bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E 'P1.2|passed|failed'`
预期 FAIL:`P1.2a`(不可读现 exit 0 + 打印 clean)、`P1.2b`(零处理现 exit 0 + clean)。`P1.2c/d/e` 应已 GREEN(现状对合法/正常/finding 已正确——证明只补 fail-closed 不伤既有)。

- [ ] **Step 3:(RED only,无实现)**

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.2): RED — B① gate 不可读/零处理必须 fail-closed(Decision 0022)"
```

---

## Task 2: GREEN — `handoff-xref-lint.sh` fail-closed(双源)

**Files:**
- Modify: `scripts/handoff-xref-lint.sh`
- Modify: `skills/handoff/scripts/handoff-xref-lint.sh`(byte-identical)

- [ ] **Step 1: 改 `scripts/handoff-xref-lint.sh`**

把第 6 行 `set -u` 改为 `set -u`(保留)并在其后新增一行 `set -o pipefail`(防御:管道内 `sed`/`grep` 失败不再被末命令退出码掩蔽)。

把第 30–48 行(`findings=0` 到文件末尾 `exit 1`)整体替换为:

```bash
findings=0
processed=0
unprocessable=0
for f in "$@"; do
    case "$f" in
        *assets/*.template.md) continue ;;   # deliberate skip:模板占位合法
    esac
    # fail-closed:不存在 OR 存在但不可读 = gate 无法检查 → 计 unprocessable,
    # 绝不当作 clean(Decision 0022 / Gotcha #24:假绿比红危险)。grammar 层
    # 仍保留 absent=skip 语义(纯解析器);此处是 gate 策略层的兜底。
    if [ ! -e "$f" ]; then
        echo "❌ xref-lint: 写入目标不存在,无法检查: $f" >&2
        unprocessable=$((unprocessable + 1))
        continue
    fi
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "❌ xref-lint: 写入目标不可读/非常规文件,无法检查: $f" >&2
        unprocessable=$((unprocessable + 1))
        continue
    fi
    root="$(_find_repo_root "$(cd "$(dirname "$f")" && pwd)")"
    out="$(rl_xref_unresolved "$root" "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
    out="$(rl_residual_placeholders "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
    processed=$((processed + 1))
done

# fail-closed 汇总:任一不可达 → 失败;给了非模板 arg 却零处理 → 失败
# (区分:仅 template arg 时 processed=0 但 unprocessable=0 → 合法 clean)。
if [ "$unprocessable" -gt 0 ]; then
    echo "❌ xref-lint: $unprocessable 个写入目标无法检查 — gate 拒绝报 clean" >&2
    exit 1
fi
if [ "$processed" -eq 0 ] && [ "$#" -ge 1 ]; then
    # 走到这:所有 arg 都是 template(deliberate skip)→ 合法 clean;
    # 否则上面 unprocessable 已 >0 退出。无歧义。
    echo "✅ xref-lint: write-target set clean(仅 template,无可检目标)"
    exit 0
fi
if [ "$findings" = "0" ]; then
    echo "✅ xref-lint: write-target set clean"
    exit 0
fi
echo "❌ xref-lint: unresolved cross-refs or residual placeholders above" >&2
exit 1
```

注:`[ ! -e "$f" ]`(absent)与 `[ ! -r "$f" ]`(present-unreadable)都计 unprocessable → 任一 >0 即 exit 1。所有 arg 均 template 时 `processed=0 && unprocessable=0 && $#≥1` → 显式合法 clean exit 0(P1.2c)。bash 3.2 算术 `$((...))` safe。`set -o pipefail` + `set -u` 兼容(无空数组路径)。

- [ ] **Step 2: 双源 byte-identical**

```bash
cp scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh
diff scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh && echo "DUAL-SOURCE OK"
```

- [ ] **Step 3: 跑 Task1 + 全回归 GREEN**

```bash
bash tests/test_handoff_xref_lint.sh 2>&1 | tail -3
bash tests/run_all.sh 2>&1 | tail -3
shellcheck -S error scripts/handoff-xref-lint.sh && echo SHELLCHECK_OK
```
预期:`P1.2a..e` 全 GREEN;`… passed, 0 failed`;`All suites passed ✅`;`SHELLCHECK_OK`。

- [ ] **Step 4: Commit**

```bash
git add scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh tests/test_handoff_xref_lint.sh
git commit -m "fix(p1.2): B① gate fail-closed — 不可读/零处理非零退出 + pipefail(Decision 0022,双源)"
```

---

## Task 3: GREEN — grammar lib `2>/dev/null` 非对称不变式注释(双源)

**Files:** Modify `scripts/lib/handoff-xref-grammar.sh` + 双源副本(仅注释)

- [ ] **Step 1: 在 `_rl_strip_code_spans` 定义上方加注释**

在 `_rl_strip_code_spans() {` 那一行之前插入:

```bash
# 不变式(Decision 0022 ④ / Gotcha #24):本 lib 内所有 `2>/dev/null` 仅可
# 掩蔽「over-flag 方向」失败(误报安全——多报一个待人工排除);**绝不可**
# 让「under-flag 方向」失败(漏报)被静默——文件可达性/可读性的 fail-closed
# 兜底由 gate 层 handoff-xref-lint.sh 负责,grammar 纯解析器维持 absent=skip。
# 改动本 lib 任一 `2>/dev/null` 前,先确认其失败方向是 over-flag。
```

- [ ] **Step 2: 双源**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo "DUAL-SOURCE OK"
```

- [ ] **Step 3: 回归(注释不改行为)**

```bash
bash tests/run_all.sh 2>&1 | tail -3
shellcheck -S error scripts/lib/handoff-xref-grammar.sh && echo SHELLCHECK_OK
```
预期:`All suites passed ✅`(断言数不变——纯注释);`SHELLCHECK_OK`。

- [ ] **Step 4: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
git commit -m "docs(p1.2): grammar lib 加 2>/dev/null 非对称不变式注释(Decision 0022 ④,双源)"
```

---

## Task 4: 端到端 dogfood — postflight 经不可读 fixture fail-closed + 真实仍 ✅

**Files:** Test: `tests/test_handoff_xref_lint.sh`(append before `summary`)

验证 gate 退出码经 postflight「取最差」正确 fail-closed 传播(postflight 不改,验传播)。

- [ ] **Step 1: 写端到端断言**

```bash
# --- P1.2 端到端:postflight 经不可读写入目标必须 fail-closed 传播 ---
P12E="$TMP_DIR/p12e-$$"; rm -rf "$P12E"; mkdir -p "$P12E/Handoff_Logs" "$P12E/Handoff_Decisions"
PF="$SCRIPTS_DIR/handoff-postflight.sh"
printf '<!-- HANDOFF v2 schema -->\n' > "$P12E/HANDOFF.md"
ur2="$P12E/Handoff_Logs/0001-2026-01-01T0000-x.md"; printf 'see Decision 9999\n' > "$ur2"; chmod 000 "$ur2"
# postflight --files= 含不可读目标 → 整体非零(不得 all passed)
pfe_ec=$(bash "$PF" --files="$P12E/HANDOFF.md,$ur2" "$P12E/HANDOFF.md" >/dev/null 2>&1; echo $?)
chmod 644 "$ur2"
assert_exit "P1.2 端到端:postflight 含不可读写入目标 → 非零(fail-closed 传播)" 0 "$([ "$pfe_ec" != "0" ] && echo 0 || echo 1)"
rm -rf "$P12E"
```

- [ ] **Step 2: GREEN + 真实 repo dogfood 无回归**

```bash
bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E 'P1.2 端到端|passed|failed'
bash scripts/handoff-xref-lint.sh HANDOFF.md "$(ls -1 Handoff_Logs/[0-9]*.md|sort -r|head -1)" "$(ls -1 Handoff_Decisions/[0-9]*.md|sort -r|head -1)"; echo "EXIT=$?"
bash tests/run_all.sh 2>&1 | tail -3
```
预期:端到端断言 GREEN;真实 repo 仍 `✅ clean EXIT=0`(P1.1 成果无回归);`All suites passed ✅`。

- [ ] **Step 3: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.2): 端到端 — postflight 经不可读写入目标 fail-closed 传播"
```

---

## Task 5: 断言总数 + per-suite 计数重同步(确定性重算)

**Files:** `HANDOFF.md` / `README.md` / `README_CN.md` / `CONTRIBUTING.md` / `TEST-SCENARIOS.md`

复发 backlog:断言总数无结构化 guard。**确定性重算,绝不猜 magic number**。

- [ ] **Step 1: 确定性重算**

```bash
NEW=$(bash tests/run_all.sh 2>&1 | grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s}')
XR=$(bash tests/test_handoff_xref_lint.sh 2>&1 | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
echo "AUTHORITATIVE total=$NEW xref=$XR (P1.1 基线 744/49;P1.2 加 Task1 5 + Task4 1 = 预计 750/55,以实际为准)"
```

- [ ] **Step 2: 全 locus 更新**

`grep -rn '744\|xref-lint 49/0\|`xref_lint.sh` | 49 ' HANDOFF.md README.md README_CN.md CONTRIBUTING.md TEST-SCENARIOS.md` 列出每处;把 `744`→`$NEW`、xref `49`→`$XR`(HANDOFF.md:15/37/185/306;README.md:101/197;README_CN.md:101/197;CONTRIBUTING.md:32;TEST-SCENARIOS.md:353 headline + 384 xref 行)。Release/ Handoff_Logs/ Handoff_Decisions/ docs/2026-05-17-p1* 不动(不可变/计划)。套件数仍 28(无新测试文件)。

- [ ] **Step 3: 验证**

```bash
bash tests/test_doc_freshness.sh 2>&1 | tail -1
bash tests/run_all.sh 2>&1 | tail -2
grep -rn '\b744\b' HANDOFF.md README.md README_CN.md CONTRIBUTING.md TEST-SCENARIOS.md   # 预期无输出
```

- [ ] **Step 4: Commit**

```bash
git add HANDOFF.md README.md README_CN.md CONTRIBUTING.md TEST-SCENARIOS.md
git commit -m "docs(p1.2): 断言总数 + xref per-suite 计数重同步(确定性重算)"
```

---

## Task 6: 多源独立审 + Dev Log + Decision 0022 Outcome 回填(controller 编排)

Gotcha #22/#24:gate 类改动须**多异构独立源**;§4 authoring/review 分离,controller 不自批。

- [ ] **Step 1: self-hosted review-loop(耦合 a)**：用已 shipped `scripts/review-loop.sh` 驱动独立 opus 审 P1.2 diff(每轮 content_hash + file:line;严格 3-连-PASS 同 hash 收敛,否则诚实 CAPPED,不伪造)。
- [ ] **Step 2: 独立 opus code-reviewer(异构源 1)**：fresh context,审 fail-closed 正确性——尤其反向:新逻辑是否引入**false-positive**(合法 absent-only 但全 template 场景误判 / 正常 clean 回归)、`set -o pipefail` 是否破坏 grammar fn 既有 `return 0`(应不——fn 不依赖 $? 且显式 return 0)、bash 3.2 算术/`-e`/`-r`/`-f` 边界、双源 byte-identity。
- [ ] **Step 3: silent-failure-hunter(异构源 2)**:确认 fail-open 真闭(不可读 / 全 typo / 混合可读+不可读 / symlink-to-unreadable / 仅 template),且无新静默面。
- [ ] **Step 4: Codex stop-time(异构源 3,Boss 触发)**:报告 controller 无法自调(`disable-model-invocation`);列出 `git diff <P1.1-tip>..HEAD` 范围,提示 Boss 可 `/codex:adversarial-review` 补第 3 源(Q3 合并路径)。诚实声明未跑,不伪称。
- [ ] **Step 5: 每 finding TDD RED→GREEN→controller 对抗复现**(真实不可读 fixture 实跑,不信「看似修好」——session 母题 claim≠fact)。
- [ ] **Step 6: Dev Log**（事件流 What）：`acquire_next_number Handoff_Logs/`,写 `Handoff_Logs/<NNNN>-<TZ时间戳>-p1-2-b1-fail-closed-hardening-shipped.md`(schema-2 frontmatter,`date: YYYY-MM-DDTHH:MM` **带冒号**——Dev Log 0054 曾因缺冒号被 handoff-lint 拒,勿重犯)。记:四项 scope 落点;多源审结果;findings 及 TDD 闭合;plan-vs-actual delta(0017 惯例)。
- [ ] **Step 7: Decision 0022 Outcome 回填**：append `**Outcome(回填)**` 段到 `Handoff_Decisions/0022-*.md`:四项是否如 scope 落地、退出码语义最终选择(复用 exit 1=gate 失败,未新增 exit 4——Karpathy#2)、postflight 未改而靠「取最差」传播验证、Codex 第 3 源状态。
- [ ] **Step 8: 覆盖 HANDOFF.md Current State + regenerate**：`date "+%Y-%m-%d %H:%M %z"`;不变式表述无 commit 计数(Gotcha #10);`regenerate_pointers HANDOFF.md` + `regenerate_decision_index "$(pwd)"`;`bash scripts/handoff-postflight.sh HANDOFF.md`(位置参 = HANDOFF.md **文件**,绝不传目录——Gotcha #23)→ 期望 `✅ all checks passed`。
- [ ] **Step 9: 终检 + commit(不 push)**：

```bash
bash tests/run_all.sh 2>&1 | tail -3
diff scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh && echo DUAL-OK
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo LIB-DUAL-OK
git add -A && git commit -m "docs(handoff): Dev Log <NNNN> — P1.2 B① fail-closed 硬化 shipped + 多源审 + Decision 0022 Outcome"
```
push 是单独步骤,须 Boss 显式授权(§4 不顺延)。**本任务不 push**。

---

## 自审

**1. Spec 覆盖(Decision 0022 四项)**:① pipefail → Task2 ✅;② 可读性闸 → Task2 ✅;③ unprocessable/零处理计数 → Task2 ✅(含 template-only 合法 clean 边界 P1.2c);④ `2>/dev/null` 不变式注释 → Task3 ✅。端到端传播 → Task4 ✅。多源审(含 Codex Boss 触发)+ §4 → Task6 ✅。计数漂移 → Task5 确定性重算 ✅。
**2. 占位扫描**:无 TBD/TODO;每代码步给完整函数体/精确命令/预期。✅
**3. 类型/命名一致**:`processed`/`unprocessable`/`findings`/`$LINT`/`$PF`/`$SCRIPTS_DIR` 跨任务一致;退出码语义统一(0 clean / 1 gate-fail-or-finding / 2 usage,不新增码——Karpathy#2)。✅
**4. Scope 纪律**:grammar fn 逻辑/`[ -f ]||return 0`/路径常量/postflight **未动**(Decision 0022 明示 + coupling-b 最小面);仅 gate 层 + lib 注释。✅

---

## 执行交接

**计划已存 `docs/2026-05-17-p1-2-b1-fail-closed-hardening-plan.md`。两种执行:**
**1. Subagent 驱动(推荐)** —— fresh subagent/任务 + controller 真实-fixture 对抗复现 + 多源审(Task6),沿用 P1/P1.1 已证纪律(Gotcha #20/#22/#24)。
**2. Inline** —— 本会话 executing-plans 批量带检查点。
**选哪个?**(默认按推荐 Subagent 驱动,Boss 已两轮选此 + Decision 0022 mandate)

---
