# P2 — handoffx 整体改名 + 破坏性 schema 迁移大工程：分阶段设计

> 日期：2026-05-19 13:35 -0700
> 承载决策：`Handoff_Decisions/0020`（大工程范围 + 基线已锁，本文档 = 0020 open#3「独立分阶段设计」交付）
> 基线（绝对路径，逐份各自权威）：`Independent_Research/grillme/` GRILL-0019-CONSOLIDATED.md + CONTEXT.md + docs/spec-c-rename-allowlist.md + docs/adr/0001..0006
> 触发：Boss 明文「启动 P2」(2026-05-19)；brainstorming 三问已定（见 §0）

## §0 — Boss 已定参数（brainstorming 澄清）

- **Q1 自迁移范围**：P2 含本仓自身四件套迁移，作 P2.4 终阶
- **Q2 镜像边界**：P2 止于私有仓迁移；新洁净公开镜像（ADR-0001 Q5）= 独立 Boss 门控发版步骤，不在 P2
- **Q3 评审节律**：风险分级——P2.0/.1/.2/.4 强制三异构源；P2.3 两段审 + controller 机械对抗
- **骨架**：方案 A（护栏先行 → 造迁移器 → 改标识符 → 回归 → 终阶自迁移，5 阶段）

## §1 — 跨阶段不变式与执行契约

- **T1 RENAME/LEAVE token 三分类**（CONTEXT.md，按 token 角色非文件名）：RENAME = registered identifier + 四件套 slug（ADR-0005）+ 品牌串；LEAVE = `*.sh` 脚本基名 + `GOTCHAS.md` + 旧镜像 git 历史。一路径可双类（`skills/handoffx/scripts/handoff-postflight.sh` 目录 RENAME / 脚本基名 LEAVE）——不对称有意，禁"修正"。
- **T2 P-A allowlist 纪律**（ADR-0001）：实际改名 locus ⊆ P-A manifest；禁 blind `s/handoff/handoffx/g`；逐 locus 精确 Edit + 变更 manifest + 邻接陷阱 fixture，reviewer 可逐行 diff。
- **T3 hard-cut**（ADR-0001）：无 alias、零迁移提示、无 shim（避 Gotcha #5 重复注册）；旧 `/handoff*` 直接停解析。
- **T4 双源 bundle byte-equal**：`scripts/` 与 `skills/handoff(x)/scripts/` 全程逐字节一致；每阶段末 `diff -rq` 断言。
- **T5 31 套件全绿门 + 自指收敛**：每阶段末 run_all 0 失败方进下一阶段；测试码自身四件套 token = 改名 locus，改后机械重算静态断言点终值（Dev Log 0058/0059 范式，禁手工枚举——Gotcha #25）。
- **T6 git 正交 + §4 push 门**：handoff 与版本管理正交；任何 commit/push 须 Boss 逐 context 显式授权；remote 仅私有 `<private-git-host>:<private-org>/Handoff.git`，绝不公开镜像；无 `--no-verify`、无 `push --force main`。
- **T7 评审分离 + 风险分级**：authoring/review 不同 context；P2.0/.1/.2/.4 三源（opus + silent-failure-hunter + Codex 第3源，Gotcha #22/#24/#25）；P2.3 两段审 + controller。

## §2 — P2.0：护栏 schema-agnostic（耦合 b+c 前置去险）

**目的**：改名前把所有硬编码四件套路径的护栏/脚本改为 schema-中性（读配置常量非字面量），使 P2.2 改名落地时 guard 不静默失效。本阶段不改任何对外名，纯防御性重构，行为 byte-equal，完全可逆。

- **组件 1 — B① grammar lib 参数化（耦合 b，最关键）**：`scripts/lib/handoff-xref-grammar.sh`（+ bundle 镜像）现硬编码 `RL_XREF_LOGS_DIR="Handoff_Logs"` / `RL_XREF_DEC_DIR="Handoff_Decisions"` / `RL_PLACEHOLDER_ALLOWLIST='HANDOFF.md|<项目负责人>'` / CANONICAL `HANDOFF.md` 兄弟检测。抽**单一 schema 定义源**（`scripts/lib/handoff-schema.sh` 常量文件 + bundle 镜像），四件套名集中一处；grammar lib 全部引用常量，零字面量散落。Why：P2.2 只动 schema 源一处，grammar lib 逻辑零改 → B① 自动跟随，杜绝"改名瞬间对死路径 `Handoff_Logs/` 假绿"（Gotcha #25 母题 / grill 核心警告）。
- **组件 2 — LEAVE 脚本内嵌四件套字面量收口（耦合 c，高漏率）**：Decision 0020(c) 点名 `acquire_next_number`/`regenerate_pointers`/`scan-credentials` 目录模式/`handoff-postflight`/`handoff-lint`/`tidy-handoff`/`handoff-v2.sh`/`migrate-to-v2.sh` 等——脚本基名 LEAVE 但内部四件套路径字面量是 RENAME。同样改引用 schema 源；产出"耦合 c 逐条 manifest"机械 grep 全派生（禁手工挑——亲犯本 feature 要根除的母题，Gotcha #25）。
- **组件 3 — schema 源测试**：新增 `test_handoff_schema.sh`：(a) 机械 grep guard 断言无脚本散落四件套字面量（键 gate 判决非诊断 echo，load-bearing，未来回归即 FAIL）；(b) grammar lib 在"schema 常量被改成 Handoffx_*"的 fixture 下正确解析新路径（P2.2 预演证明，不真改名）。
- **数据流**：schema 源 → grammar lib + 全 LEAVE 脚本 import → 行为不变（常量值未变仍 Handoff_*）。唯一可观测变化 = 零硬编码散落；负控 = P2.0 前后 run_all 输出等价。
- **风险**：组件 2 漏一 sibling = P2.2 该脚本静默对死路径 → 组件 3 机械 grep guard 是 load-bearing 闸；三源审。

## §3 — P2.1：`/handoffx-tidy` schema 迁移器

**目的**：造旧四件套 → handoffx schema 的迁移器，**不碰真实仓**（真迁移是 P2.4）。

- **归属**：overload 改名后的 tidy 命令；脚本仍 `tidy-handoff.sh`（LEAVE，T1）。
- **契约**（循 `migrate-to-v2.sh` 先例）：幂等（已是 handoffx = no-op）、双平台（macOS bash3.2 + Linux mawk）、原子（`.partial` staging + `assert_dest_clear` + 失败回滚）、root-safe（Gotcha #15：chmod 类断言 EUID=0 skip 镜像 B7-a）、有测试。
- **功能**：`HANDOFF.md`→`HANDOFFX.md`、`Handoff_Logs/`→`Handoffx_Logs/`、`Handoff_Decisions/`→`Handoffx_Decisions/`，改写内部交叉引用（`Dev Log NNNN`/`Decision NNNN` 目标重指——由 P2.0 schema 源 + B① 文法驱动，有界枚举）；`GOTCHAS.md` 不动（无 token）。
- **检测**：旧 schema 存在（`HANDOFF.md` + `Handoff_Logs/` 兄弟）触发迁移；幂等。
- **测试**：合成 fixture + **真实仓四件套的拷贝快照**（Gotcha #20 真产物 dogfood，但对拷贝非 live 仓）+ 原子回滚负控（注入中途失败断言完整回退）。
- 三源审（迁移逻辑 = 不可逆类）。

## §4 — P2.2：标识符 + scope-edge 改名（hard-cut）

**目的**：执行 P-A allowlist 子集的 registered-identifier + scope-edge 改名。改名后**工具是 handoffx 但仍产 Handoff_***（自迁移留 P2.4）。

- **Loci**（逐 locus Edit，禁 blind sed，T2）：SKILL.md `name:`；skill 目录 `skills/handoff/`→`skills/handoffx/`；`command-shims/` + `references/` 基名 `handoff*.md`→`handoffx*.md`；install.sh 命令字面量 + Codex `$alias` + `skill:` 引用 + sweep glob；品牌串 → `HandoffX`；`.skill` 产物 `handoff-${VER}.skill`→`handoffx-${VER}.skill`；gitx 流水线；项目根目录名 `…/handoff`→`…/handoffx`。
- **不对称保留**：skill 目录内脚本 `handoff-` 基名 LEAVE（T1，有意，禁"修正"）。
- **hard-cut**：旧 `/handoff*` 停解析，无 shim（T3 / Gotcha #5）。
- **产物**：变更 manifest（reviewer 逐行 diff）+ 邻接陷阱 fixture（`skills/handoffx/scripts/handoff-postflight.sh` 双类路径）。
- 三源审（breaking）。

## §5 — P2.3：全回归 + 不变式核验

- run_all 31 套件全绿（改名后工具）；双源 bundle byte-equal（T4）。
- 自指收敛：测试码自身四件套 token 是改名 locus → 机械重算静态断言点终值（Dev Log 0058/0059 范式，禁手工枚举，T5）。
- install.sh 端到端跨 CLI（Claude Code / OpenCode / Codex）：改名 skill 注册成功、旧名彻底消失（hard-cut 验证，Gotcha #16 真机 probe）。
- 验证阶：两段审 + controller 机械对抗（可逆、有测覆盖，非三源）。

## §6 — P2.4：终阶自迁移（Boss 门控执行）

- **执行前（不可豁免门）**：对 live 仓新鲜拷贝跑 P2.1 迁移器 + 三源审其行为 + **Boss 明文执行授权**（§4 / Q3 / T6；controller 不从任何措辞推断）。
- **执行**：迁移器对本仓自身四件套真迁——`HANDOFF.md`→`HANDOFFX.md` + 59 `Handoff_Logs` + 24 `Handoff_Decisions` + 全历史 xref 语料重指。
- **执行后**：run_all 31 全绿（迁移后仓）；B① 对新 schema clean（**端到端证 P2.0 耦合 b 吸收成功**——ADR-0005 自招悬挂 xref 类在迁移规模被 B① 机械网兜住）；postflight 全绿；pointer 重生成对 `Handoffx_*`。
- **可逆性**：私有仓 git 可回退（规模极大）；迁移器原子回滚兜底。

## §7 — 耦合吸收 / 测试 / 回滚 / Open

- **耦合 (a)** P0 自举鸡蛋：已解（P0 review-loop 已 shipped，P2 跑其上）。
- **耦合 (b)** B① 跨边界 guard：P2.0 组件 1（schema 源单点）吸收 + 组件 3 测 + P2.4 端到端验。
- **耦合 (c)** LEAVE 脚本内嵌字面量：P2.0 组件 2 吸收（机械派生 manifest）。
- **耦合 (d)** postflight 争用：已解（P1 + 性能轨均 shipped，P2 仅经 schema 源重指 postflight 四件套字面量，无并发争用）。
- **测试**：每阶段 RED→GREEN + run_all 全绿门 + 双源 byte-equal + 自指收敛；P2.0/.1/.2/.4 三源。
- **回滚**：每阶段私有仓 git 可回退；迁移器原子；P2.2/P2.4 是 breaking 点，均门控。
- **Open（非 P2）**：新洁净公开镜像 born pure + 归档旧镜像（Q2 延后，独立 Boss 门控发版）；§4 push 门 + P2.4 执行门贯穿 P2 全程。

## §8 — 执行链

writing-plans（本设计 → 6 任务分阶段 plan，每任务 RED→GREEN 步骤级）→ subagent-driven-development（fresh implementer/任务 + 两段审 + controller 机械对抗 + P2.0/.1/.2/.4 三异构源）。spec 审门 = 本文档；§4 push 门 + P2.4 执行门非可豁免。
