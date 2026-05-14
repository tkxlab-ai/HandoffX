---
schema: 2
type: decision
date: 2026-05-11
number: 0017
title: v2.1.3 — 一起做 OpenCode dir 迁复数 + skill spec compliance polish（拒 B 仅文档 / C 不动）
---

### 2026-05-11 — v2.1.3 — 一起做 OpenCode dir 迁复数 + skill spec compliance polish（拒 B 仅文档 / C 不动）

**背景**

v2.1.2 实战观察期决策刚定（Dev Log 0042，"等真实痛点"），同会话 Boss 让对照官方 Skill Creator 文档检查 handoff 架构合规性。fetch `code.claude.com/docs/en/skills` + `github.com/anthropics/skills` 后发现 ~3 处偏离 official idiom（B1 commands/ 命名误导 / B2 agents/ 误用 / C frontmatter 未尽用）。同时 OpenCode 用户报告"commands/ 目录为空"——Gotcha #9（2026-05-06，v1.2.6 era）记录"OpenCode 单数 command/"在 v1.14.41 已经过时（官方文档只提复数 commands/）。

两条独立线索汇成同一根问题：**项目对照官方现行规范缺乏周期性校准**。Boss 选"C 迁复数 发 v2.1.3"，后追加"A 一起做 B+C 发 v2.1.3 skill spec compliance polish"——把两个 polish 任务捆进同一 release。

**触发**

Boss 看完两轮分析后明示双 scope：
1. OpenCode commands/ 迁复数（functional：上游 convention drift）
2. skill spec compliance polish（cosmetic：B1 + B2 + C frontmatter）

**选项**

- **B** — 仅文档：在 Gotcha #9 加 obsolete 标记 + 写 Gotcha #16 说"考虑过 spec polish 但未做"；零 code 改动；后期撞用户问题再做。**拒**——B 留着既有不一致状态（install.sh 沿用过时 Gotcha 结论 / skill 内 commands/ + agents/ 命名误导），未来每个新接触项目的同事/AI 都要重新被这层"为什么 install.sh 写单数但官方文档说复数"卡一下；功能差距实际可观（OpenCode 不去重 = 双写就 palette 重复）
- **C** — 都不动：当前 100% legacy-compatible（install.sh + 旧路径都工作），属 cosmetic / discoverability，等真用户报问题再驱动。**拒**——A 这条**已经是真实痛点报告**（Boss 转述 OpenCode 警告 + 自己跑机械 probe 验证）；C 等价于"我承认有问题但选择沉默"
- **D（选）** — 全套 polish 发 v2.1.3：
  - A: install.sh OpenCode target `command/` → `commands/`（全局 + 项目级双线）；同时清旧单数残留
  - B1: `skills/handoff/commands/` → `skills/handoff/command-shims/` git mv + install.sh 5 处引用更新 + test_install.sh / test_bundle_sync.sh 引用更新 + release.sh dry-run-audit 引用更新 + bootstrap-time 自动 commands → command-shims 迁移（向后兼容旧 .skill 包）
  - B2: `skills/handoff/agents/codex-commands.txt` → `skills/handoff/assets/codex-commands.txt` git mv；agents/ 空目录删除
  - C: SKILL.md frontmatter 加 `when_to_use` 多行 trigger 关键词；description 适度扩展但保持 ≤160 chars 项目 budget
  - 验证：macOS bash 3.2 24/24 ✅ + Ubuntu 22.04 mawk 24/24 ✅（v2.1.2 双绿基线保持）
  - 知识资产：Gotcha #9 标 obsolete + 引用 #16；新增 Gotcha #16 "对照官方现行规范定期重新校准"（两个 case study）+ 跨 CLI 双路径迁移模板 + skill spec compliance 模板；Decision 0017（本文件）

**理由（为何 D）**

1. **Linus #1 真问题**：双线都是 — A 是用户报告的 functional drift；B1+B2+C 是 cosmetic drift 但累积起来给同事/AI 增加认知负担。两者根因同：**项目对照官方规范缺乏周期性校准**。Gotcha #16 沉淀这条规律。
2. **Linus #2 简单**：D 看起来工作量大，实际可分解为机械批量：
   - A：~5 spots install.sh + ~10 spots test_install.sh，每个都是 path string 替换
   - B1：1 git mv + ~10 spots refs replace_all
   - B2：1 git mv（无引用更新）
   - C：1 SKILL.md frontmatter edit
   实工时 ~1.5h 符合 ROI
3. **Linus #3 不破坏**：
   - install.sh 加 bootstrap-time `commands → command-shims` migration → 旧 .skill 包仍可 install
   - OpenCode 安装时双路径清理 → 旧版残留不会 palette 重复
   - macOS + Linux 真测双绿 = backward compat 验证
4. **Karpathy#3 surgical**：每处改动可追溯到具体 spec 文档行（`code.claude.com/docs/en/skills` 第 X 节）或具体 probe 证据（OpenCode `debug config` output）—— 不存在 "顺便重构相邻代码"
5. **Tacit#4 Why > How**：Gotcha #16 不光记"怎么改"，更记"为什么周期性校准官方规范"——这条规律已经在 Gotcha #14（K4 chicken-egg "机械验证 > 理论推断"）+ Gotcha #15（mawk POSIX "看起来 POSIX 的 regex ≠ 真 POSIX"）反复验证。**实战观察期 ≠ 静默期** —— 找到真实痛点（OpenCode 报告 + spec 偏离）就该发版
6. **bootstrap 兼容性**：v2.1.3 install.sh 必须能从 v2.1.2 .skill 自举（Release/handoff-v2.1.2.skill 还内含旧 commands/ 命名）—— C10 .skill bootstrap 测试是这条 invariant 的机械验证。加 6 行 fallback rename 完整解决

**反方观点（为完整性记录）**

D 的代价：
- 工时 ~1.5h（vs B 仅文档 5 分钟 / C 都不动 0 分钟）
- 多发一个 patch 版本号 v2.1.3（同 day 第三个：v2.1.0 → v2.1.1 K4 → v2.1.2 Linux → v2.1.3 polish）
- 实战观察期连发三个 patch 看起来"违反"观察期理念

但实战观察期理念是"用真实痛点驱动修复"，**不是"不发版"**。今天 3 个 patch 全是真实痛点：
- v2.1.1：K4 audit 实测发现的 tarball drift
- v2.1.2：Boss 询问 Linux 引发的 OrbStack 真测 38 断言挂
- v2.1.3：Boss 转述 OpenCode 警告 + spec 文档对照

观察期理念实际**正常运行**——找到痛点立即修，比"凭空预测 v2.2.0 race fix" 高出一个 quality 等级。

**结论**

选 D。落地（按时间顺序）：
1. **Phase 1**: 机械 probe OpenCode v1.14.41 commands/（复数）可读 ✅
2. **Phase 2**: install.sh OpenCode target 切复数 + commands/ → command-shims/ git mv + agents/codex-commands.txt → assets/ + SKILL.md frontmatter 扩展（when_to_use）
3. **Phase 3**: 双平台 install.sh + run_all 24/24 ✅ ✅
4. **Phase 4**: Gotcha #9 标 obsolete + Gotcha #16（两 case study）+ Decision 0017（本文件）+ HANDOFF.md pointer counters
5. **Phase 5**: gitx-release v2.1.3 + audit 209/0/0 + commit + tag + push private Git host + Dev Log 0043

**关联**：Gotcha #16（对照官方现行规范定期重新校准 + 双路径迁移模板 + skill spec compliance 模板）；Gotcha #9（obsolete since v2.1.3）；Dev Log 0043（v2.1.3 实施记录）；Dev Log 0042（v2.1.2 Linux compat，实战观察期决策的同会话延续）；Decision 0013（v2.2.0 race fix 推延保持有效，本周期只动 dir convention + skill spec）；`code.claude.com/docs/en/skills`（官方 spec 证据）+ `opencode.ai/docs/commands`（OpenCode 官方文档证据）
