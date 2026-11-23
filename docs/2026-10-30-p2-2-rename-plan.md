# P2.2 — 标识符 + scope-edge 改名 hard-cut：阶段计划（v4，Codex 三轮评审后拆分为 P2.2a / P2.2b）

> 日期：2026-10-30 · 触发：Boss 明文「P2.2启动」· 承载：Decision 0025（方案 A 阶段 3）+ design §1/§4 · 基线：`../Independent_Research/grillme/docs/spec-c-rename-allowlist.md` + CONTEXT.md（T1；T3 hard-cut :32-34）
> v3→v4（Boss 2026-10-30 拍板）：**拆分**——P2.2a = 工具改名 + 事务安装器 + 守卫 + 文档 + 本机 dogfood（本机可全验）；P2.2b = 发布链 canonical 布局（Codex 第 3 轮第 1–2 条：release.sh 调 run_all 递归、checksums/sbom 由外部 gitx-release 生成、`latest` 目标）在 gitx-release 可用的机器上做；P2.2 收口以 2b 完成为准。第 3 轮第 3–5 条吸收进 §2/Task 2：宽口径发现、occurrence 级正向断言、跨 CLI 顺序测试。**Boss 已授权本阶段每任务 checkpoint commit。**
> v2→v3：清单改为「路径 + 内容」两遍盘点、逐 occurrence 分类、未分类即 FAIL；守卫加正向断言（改名目标存在 / LEAVE 基名存在）+ 外置变异 harness；`handoffx-tidy` 旧/新集合去重叠；安装改为**事务**（journal + 备份目录，整次调用成功才提交）；沙箱复用 test_install helper（HOME + XDG + WSL 全隔离）；本机备份清单**派生自同一 journal**；仓库检查点 = Boss 授权的 checkpoint commit；发布布局声明 canonical + 不跳过的契约测试。
> 执行：subagent-driven（fresh implementer / task + controller 机械对抗）→ 三异构源 → Boss 门进 P2.3

## 0. 契约
工具 `handoff`→`handoffx`；产物四件套与 `scripts/lib/handoff-schema.sh` 常量**不动**（P2.4）。hard-cut：删精确列出的旧名；无 alias / shim / 迁移提示 / 兼容文案。

## 1. 角色分类（逐 occurrence；谓词覆盖所有已知句法形态）
R1 skill 目录段：`skills/handoff(/|$|\b)`（含无尾斜杠：install.sh:22；ZIP 根 `handoff/` release.sh:203）→ `skills/handoffx` · R2 注册命令：`/handoff(-recall|-tidy|-memory|-init)?\b` · R3 Codex 选择器 / `Use skill: handoff` / `skill: handoff`（`.md .txt .yml` 与 install.sh 文案；排除 `.sh` 内 `$handoff` 变量）· R4 shim/reference **裸基名**：`\bhandoff(-recall|-tidy|-memory|-init|-write)?\.md\b`（install.sh:298、references/handoff-write.md:174、模板 :302）→ `handoffx…`（**例外**：四件套 `HANDOFF.md` 大写不在此类）· R5 name/品牌：`^name: handoff$`、`# Handoff —`、`Handoff Plugin`、`Handoff version`（bug.yml:16）、横幅 `handoff v` · R6 产物：`handoff-\$\{?(VER|VERSION|v)\}?`、`handoff\.skill`、`handoff-\*\.skill`、`Release/handoff-`、`source_root: handoff-`、`handoff-\$VERSION` · R7 `agents/codex-commands.txt` 五行 · R8 安装路径：`\.claude/(skills|commands)/handoff\b`、`opencode/(skills|commands?)/handoff\b`、`\.agents/skills/handoff\b`、`\.codex/skills/handoff\b`
LEAVE：L1 `*.sh`/`test_*.sh` 基名、函数名、`.sh` 内 `$handoff` 变量 · L2 四件套 slug + `HX_*=` · L3 历史散文（逐段登记）· L4 清扫操作数（OLD_* 定义行、种植旧残留的测试行）· L5 守卫/harness/例外表自身 · L6 `tests/fixtures/handoff-v1-sample.md`、`tests/fixtures/p2-1-synthetic-v2/` · L7 backfill 历史输入
**宽口径发现（第 3 轮第 3 条）**：先对所有已跟踪 + 未跟踪文件做 `grep -nio 'handoff'`（大小写不敏感、不预设形态）与路径段扫描得到**候选全集**，再对每个候选套 R/L 谓词归类；任何候选既非 R 也非 L → `UNCLASSIFIED` → 守卫 FAIL，必须人工归类（补谓词或登记例外）后方可冻结。已知会落入此类的形态作 fixture：`handoff-*-source.tar.gz` 裸文本（INSTALL.md:114 / install.sh:146）、`# Handoff $VERSION — Release Notes`（release.sh:277）。

## 2. 清单生成器 + 守卫（Task 0）
- `tests/lib/p2_2_rename_inventory.sh`：输出 `tests/fixtures/p2_2_rename_manifest.txt`（每行 `path:line:col:role:old→new`，路径类行 `path::<role>:old→new`）——**完整清单文件**；诊断只打前 20 行 + 总数。
- `tests/test_p2_2_rename_manifest.sh` 判决（exit + `❌ manifest` verdict 行，诊断分离）：(a) R 类命中且不在例外表 = 0；(b) **正向（occurrence 级）**：manifest 每条 `path:line:col:old→new` 用稳定上下文锚点（该行去掉 token 后的前后 12 字符）定位改后的行，断言锚点处出现新 token——同文件两处同 token 漏改一处必红；路径行 `test -e`；(c) **LEAVE 正向**：`skills/handoffx/scripts/handoff-postflight.sh` 等 L1 清单文件存在、`HX_MAIN_FILE=HANDOFF.md` 四常量原值；(d) 例外表每行仍命中原 token（ratchet）且例外表行数 = 冻结值（防增删）；(e) `UNCLASSIFIED=0`；(f) 旧 shim 文件名在 `skills/handoffx/command-shims/` 不存在（精确 OLD_SHIMS 集合）。
- 外置变异 harness `tests/test_p2_2_rename_bguard.sh`（0058 bguard 范式，对 fixture 副本跑真实守卫）：(i) 回植旧 token → RED；(ii) 改名 `handoff-postflight.sh` → RED（命中 (c)）；(iii) 守卫内 `violations=0` 强制、诊断保留 → bguard RED；(iv) 删/加例外行 → RED；(v) 删一条 `→new` 目标 → RED（命中 (b)）；(vi) 同文件两处同 token 只回退一处 → RED（occurrence 级 (b)）。
- 改名前：守卫 RED，manifest 文件 = 本阶段冻结范围（reviewer + Boss 过目）；例外表行格式 `path:line:role:reason`，occurrence 级。

## 3. 任务（前置：**Boss 一次性授权本阶段 checkpoint commit**——每任务末 `git commit -m "p2.2(taskN): …"`，含新文件；`git tag p2.2-start` 打在授权后的干净提交上。回滚 = `git reset --hard <tag>` + §3 Task 2 安装侧 journal 还原。未授权则改用 out-of-tree 快照 `tar` 整个工作树含未跟踪文件）

### Task 0 — 盘点 + 例外表 + 守卫 RED（§2）；commit。
### Task 1 — skill 包（R1 R2 R3 R4 R5 R7）
`git mv skills/handoff skills/handoffx`；SKILL.md；四 shim `git mv`；tidy 合并（§4）；references `git mv` + 互引；`agents/codex-commands.txt`；`assets/*.template.md` 命令/引用（文件名与 slug 不动）；`.github/ISSUE_TEMPLATE/bug.yml`。测试跟随：`test_skill_metadata_budget` `test_handoffx_tidy`（合并 shim 行为断言：默认整理段 + 显式 schema-upgrade 段）`test_no_legacy_templates` `test_recommended_consistency` `common.sh`；T4 = `test_scripts_sync` DEV_ONLY 政策。
### Task 2 — 事务式 install.sh + sync-codex-skills.sh（R8 L4）
- 名集合（在 install.sh 顶部，附自检 `assert_disjoint OLD_* NEW_*`，test_install 断言之）：`NEW_SKILL=handoffx`；`NEW_SHIMS=(handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md)`（OpenCode 另加主命令 `handoffx.md`；Claude 不装主命令 shim，Gotcha #5）；`NEW_CODEX_ALIASES=(handoffx-recall handoffx-tidy handoffx-memory handoffx-init)`。`OLD_SKILL_DIRS=(handoff)`；`OLD_SHIMS=(handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md hand-off.md)`；`OLD_CODEX_ALIASES=(handoff handoff-recall handoff-tidy handoff-memory handoff-init)` + 前缀集 `source-command-handoff-*`；`OLD_MISC=(.claude/handoff-scripts)`。**`handoffx-tidy` 不在 OLD 集**：Codex 安装时以新内容**原子覆盖**该 alias（写 `.new` + mv），其他 CLI 不碰它。
- 根矩阵：`$HOME/.claude`、`${XDG_CONFIG_HOME:-$HOME/.config}/opencode/{command,commands,skills}`、`$HOME/.agents/skills`、legacy `$HOME/.codex/skills`、WSL（`HANDOFF_TEST_WSL_APPDATA` / 枚举）两处、`--project` 三子根；跨根 OLD_* 清理独立于 CLI 选择；卸载同矩阵。
- **事务**：一次调用一个 journal `$HOME/.handoffx-install/journal.<ts>`（每行 `op path [backup]`：`bak`=旧物移到 `$HOME/.handoffx-install/bak.<ts>/<相对路径>`、`new`=本次创建）。顺序：解析全部目标 → 把所有 OLD_* 与将被覆盖的目标 `mv` 入 bak → 拷贝/生成 → 逐项验证 → **全部 CLI 成功后**才删 bak + journal；任一步失败 → 按 journal 逆序还原（删 `new`、`bak` 移回）→ exit 1。`--journal-only`：只解析并打印将发生的 op 清单（供 Task 6 备份与 reviewer 审）。test_install：种植 OLD_* 全集 + 无关 `handoff-something-else` skill + 已有正确的 Codex `handoffx-tidy`；注入失败点（清扫后、skill 拷贝、shim 拷贝、alias 生成、第二家 CLI）各一例 → 断言旧安装**完整还原** + exit≠0；成功路径：旧全没、无关保留、新齐全、重装幂等、`--claude` 不产生 `commands/handoffx.md`、`--project` 不动全局；**跨 CLI 顺序**：先 `--codex` 成功并快照四个 alias 内容与 `handoffx` skill 树 → 再跑 `--claude` 与 `--opencode` → 断言 Codex 侧 byte-identical 且完整。
### Task 3 — 发布链最小改动（P2.2a 内）+ P2.2b 契约（延后）
P2.2a 只做让发布脚本**不坏**的改动：`release.sh:197,203` 打包路径 `skills/handoff`→`skills/handoffx`、`.sanitize-ignore` / `release-sanitize-public.sh` 的 DEV_ONLY 路径；产物名与 `Release/` 布局**暂留** `handoff-<ver>`（阶段内声明的过渡不一致，R6 occurrence 全部登记进例外表 `role=L8-deferred-to-P2.2b`，守卫 ratchet 看守）。
**P2.2b（gitx-release 可用的机器上执行，Boss 另行明文）**：canonical `Release/handoffx-<ver>/handoffx-<ver>.{skill,-source.tar.gz}`；`release.sh` 加 `--sandbox <ver>` 生产者模式（不调 run_all、不动 `Release/latest`）；生产 `checksums.txt` + `sbom.cyclonedx.json`（与外部 gitx-release 产物同格式）；`latest` 指向新目录；publisher :40,180-192,262,385-396 与 backfill `BACKFILL_RENAME_FROM=v3.0.0` 门限；不跳过的契约测试 `test_release_layout_contract.sh`（沙箱 `--sandbox` 产物 → publisher 只读 preflight 抽函数，新旧版本各一）；SOP 示例；去掉 L8 例外。
### Task 4 — 文档（R1 R2 R5 R8；L3 逐段例外）
INSTALL / README / README_CN / CONTRIBUTING / SECURITY / MIGRATION_GUIDE_v2 / TEST-SCENARIOS / HANDOFF.md 现行段 / SOP。CHANGELOG `[Unreleased] v3.0.0`：事实（identifier、安装路径、产物名改为 handoffx），**无**迁移/兼容指引（T3）。
### Task 5 — 守卫 GREEN + bguard 六项 RED + 自指收敛（套件 35→37：manifest / bguard；layout-contract 随 P2.2b）+ run_all 全绿；commit。
### Task 6 — 分级 dogfood + 三源 + 落盘
(a) 沙箱：复用 test_install helper（`HOME` + `XDG_CONFIG_HOME` + `HANDOFF_TEST_WSL_APPDATA` 全指向沙箱；断言 `--journal-only` 解析出的每个根都在沙箱内才真跑）；`--claude/--opencode/--codex/默认` 各一轮；(b) 本机：先 `install.sh --journal-only` 得真实 op 清单 → 按清单备份到 `~/.handoffx-p2.2-backup/<ts>/`（含「原不存在」标记）→ 真装 → 验证；回滚 = 按清单还原（删本次 `new`、移回 `bak`）+ `git reset --hard p2.2-start`；(c) 三源：opus（manifest + 例外表逐行）/ silent-failure-hunter（事务还原、清扫 fail-open）/ Codex stop-time；(d) Dev Log 0064 + Decision 0028（tidy 合并、backfill 门限、canonical 布局、根目录名 Boss 执行）+ Current State；**暂停等 Boss 进 P2.3**。

## 4. tidy 合并
`/handoffx-tidy` = 原结构整理（默认）+ 显式 `schema-upgrade --dry-run|--apply --root`（不自动触发；自迁移 = P2.4）。ADR-0005:18 一致。

## 5. 不做 / 边界
四件套 slug、schema 常量（P2.4）；真机跨 CLI 发现 probe（P2.3）；公开镜像发版（Q2）；private Git host 远端名；git 历史；脚本基名；**项目根目录名 `…/Handoff→…/Handoffx` = Boss 收口后自行执行**（§6 v1 命令同）。

## 6. 退出
P2.2a：run_all 37 套件 0 失败 + T4（DEV_ONLY 政策）+ 守卫正向/负向 + bguard 六 RED + 沙箱矩阵 + 本机事务安装（journal 备份）+ 三源闭 → 落盘 → **等 Boss 定 P2.2b 时机**（gitx 机器）；P2.2 整体收口 = 2b 完成后 → **等 Boss「进 P2.3」**。
