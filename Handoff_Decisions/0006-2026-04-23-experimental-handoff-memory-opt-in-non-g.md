---
schema: 2
type: decision
date: 2026-04-23
number: 0006
title: Experimental `/handoff-memory`：opt-in 例外绕开 Non-Goal"不做对话历史导出"
---

### 2026-04-23 — Experimental `/handoff-memory`：opt-in 例外绕开 Non-Goal"不做对话历史导出"

- **背景**：HANDOFF Non-Goals 明写"不做 AI 对话历史导出/重放"。但用户场景：切电脑时，机器本地的 CC auto-memory（feedback / project / reference / user 四类压缩经验）不跟项目走，跨机器丢失。与"对话历史"不同，memory 是**压缩后的经验条目**，不是原始会话。
- **选项**:
  - A. **不做**，保持 Non-Goal 纯粹性；建议用户按 HANDOFF.md 手抄重要经验
  - B. **opt-in experimental**：新增 `/handoff-memory [status|on|off|sync]`，默认关闭；`on` 后每次 `/handoff` 覆盖式从 `~/.claude/projects/<encoded>/memory/*.md` 拷到项目 `./memory/`
  - C. **默认开启**：无条件在 `/handoff` 写入后 sync
- **选择**: B
- **拒绝 A 的原因**：手抄成本高到实际没人做；memory 与"对话原文"是两回事——Non-Goal 的精神是反对"导出对话 transcript"，不反对"复制经验条目"。用户切电脑场景是高频真实需求
- **拒绝 C 的原因**：违反 YAGNI + 隐式改变既有行为；部分用户 memory 含客户名 / 内部 URL / token，默认同步会悄悄泄漏；Non-Goal 是硬原则，破例必须**显式 opt-in**
- **反悔代价**：低——纯新增，默认关闭路径下行为不变；回滚只需删两脚本 + 删 shim + 撤 install 改动
- **不变量**：
  - `./memory/.sync-enabled` 不存在 = 所有 handoff 行为 100% 不变
  - 敏感信息双护栏：首次 on + `.git/` → `.gitignore` 手动添加提示；每次 sync 后自动 `scan-credentials.sh`，命中 → 🔴 警告 + 非零退出（不撤销文件，决策交用户）
  - Symlink 在 CC 源一律拒绝（防攻击者植入 `/etc/passwd` 链接被拷走）
  - 不自动写 `.gitignore`——记忆是否入版本由项目自己决定
- **派生原则**：Experimental 功能标配三件套——(1) shim frontmatter 带 🧪 标记，(2) README 独立"🧪 Experimental"章节写明"API 可能变"，(3) HANDOFF Non-Goals 显式记录例外（不静默破例）

