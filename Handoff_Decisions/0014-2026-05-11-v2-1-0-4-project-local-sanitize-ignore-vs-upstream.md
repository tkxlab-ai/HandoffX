---
schema: 2
type: decision
date: 2026-05-11
number: 0014
title: v2.1.0 #4 — 项目本地 `.sanitize-ignore` vs 上游 gitx-release skill patch
---

### 2026-05-11 — v2.1.0 #4 — 项目本地 `.sanitize-ignore` vs 上游 gitx-release skill patch

- **背景**: v2.1.0 UX backlog 第 4 件原本写"给上游 `~/.claude/skills/gitx-release/scripts/release.sh` 提 patch 加 `Handoff_Logs/` / `Handoff_Decisions/` / `GOTCHAS.md` / `HANDOFF.md.pre-v2-backup` / `NEXT_SESSION_NOTES.md` 到 rsync exclusion list"。开工调研发现 gitx-release **已经存在** `.sanitize-ignore` 项目级 escape hatch（line 71-100 in `release-sanitize.sh`），原以为要改全局，实际只需写项目本地配置。是关键的"先调研再动"收益
- **选项**:
  - A. 给 `~/.claude/skills/gitx-release/scripts/release.sh` 提 patch，硬编码 v2 layout 在 rsync exclusion / sanitize bypass 里——影响 Boss 所有项目，作为 gitx-release skill 的 first-class feature
  - B. 项目本地 `.sanitize-ignore` 加 6 行 pattern——只影响本项目，使用 gitx-release 已设计好的 escape hatch
  - C. 写项目本地 pre-release wrapper 脚本 mv 文件到 stash 再恢复——和 K4 手动 workaround 等价但自动化
- **选择**: **B**
- **拒绝 A 的原因**:
  - (i) **侵犯全局 skill**：gitx-release 是 user-level skill，跨所有 Boss 项目用。硬编码 "Handoff_Logs/" 这种 Handoff-specific 名字在 sanitize bypass 里，污染了通用工具的语义
  - (ii) **违反 CLAUDE.md §4** "No Self-Installing Plugins / Skills" 精神——虽然不是 install，但等价的全局副作用 / 跨项目影响应该需要 S-level approval
  - (iii) **已有正确机制**：gitx-release 设计了 `.sanitize-ignore` 就是为了"项目自己的特定情况"。绕过它去 patch 主 script 是用错抽象
  - (iv) **维护成本**：每个新 layout 都得改 gitx-release source 一次，反过来 gitx-release 上游若变形可能 break 我们的 patch
- **拒绝 C 的原因**:
  - (i) wrapper 是把 K4 手动操作变成脚本——不是真正解决问题，只是把痛苦自动化
  - (ii) 引入新脚本 = 新 surface area + 双副本同步 + 新测试，远比"加 6 行配置"贵
  - (iii) wrapper 必须知道 v2 layout 文件列表，hardcode 在脚本里 = 同样的 layout-coupling 反模式
- **反悔代价**: 极低——`.sanitize-ignore` 是 plain text 配置，加错就改回。如果后续发现 gitx-release 真该有 v2 layout 智能识别（比如检测 `<!-- HANDOFF v2 schema -->` marker 自动 bypass），随时可以叠加 A 方案，B 不冲突
- **延伸推论**:
  - 这次调研收益是"先看现有机制"——CLAUDE.md "执行前先调研" / Linus "是真问题？" 落地。原 backlog 写法是基于不完整信息的猜测；调研后省了一次大改
  - 这条经验值得记 Gotcha 或文档：**"上游 skill 改"的 backlog 项要先调研是否已有 project-local escape hatch**
- **关联**: Dev Log 0038（执行 #4 + #5）；CLAUDE.md §4 No Self-Installing；K4 原手动 workaround（Dev Log 0031）；v2.1.0 backlog 完结
