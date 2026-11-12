# `/handoffx-memory` — 实验性项目记忆同步规范

> 🧪 **Experimental**：API 可能变。默认关闭，用户显式 `on` 才启用。

## 背景：为什么要这个命令

Claude Code 的 "auto-memory"（feedback / project / reference / user 四类记忆）默认存在 **机器本地**：

```
~/.claude/projects/<encoded-path>/memory/
```

其中 `<encoded-path>` 由项目绝对路径派生（`/` `_` `.` → `-`）。这意味着：

- ✅ 同一台电脑上 Claude 能持续记住本项目的经验
- ❌ 换电脑 / 换同事 / 换 AI 工具时，记忆**不跟着项目走**——项目文件夹里没有任何痕迹

`/handoffx-memory` 是一个 opt-in 的桥：**把 CC 的 auto-memory 固化到项目 `./memory/` 目录**，这样项目文件夹打包带走，记忆就跟着走。

这与 HANDOFFX.md 的核心原则（Non-Goal：不做对话历史导出/重放）**并不冲突**——记忆是压缩过的经验条目，不是对话原文，且本功能是 opt-in 例外。

## 子命令

| 命令 | 行为 |
|------|------|
| `/handoffx-memory` | 显示状态（enabled/disabled + 已同步文件数 + 源路径） |
| `/handoffx-memory on` | 启用：创建 `./memory/.sync-enabled` 标志 + 立即跑一次同步 |
| `/handoffx-memory off` | 关闭：删除标志文件；**已同步的 .md 文件保留**（用户想清掉自己 `rm -rf ./memory/`） |
| `/handoffx-memory sync` | 不看标志，强制同步一次（手动触发，或供 `/handoffx` 自动调用） |

## 执行流程

1. **定位脚本**：`<skill-path>/scripts/sync-memory.sh`（`<skill-path>` = `~/.claude/skills/handoffx/` 或项目内 `.claude/skills/handoffx/`）
2. **首次 `on` 前的确认**（只在首次，即标志文件不存在时）：
   ```
   ⚠️ 这是实验性功能。启用后：
     • 会在项目根创建 ./memory/ 目录
     • 把 ~/.claude/projects/<encoded>/memory/*.md 复制到 ./memory/
     • 之后每次 /handoffx 会自动重新同步（覆盖式）
     • 换电脑时项目文件夹带 ./memory/ 就能继续有记忆
   继续？（y/N）
   ```
   如果用户在命令里已经明确写了 `on`，视为已确认，直接执行。
3. **调用脚本**：`bash <skill-path>/scripts/sync-memory.sh <subcommand>`
4. **回显输出**：原样转发脚本 stdout/stderr，别包装得看不清证据

## 与 `/handoffx` 写入流程的集成

如果 `./memory/.sync-enabled` 存在，`/handoffx` 在后置四连检查之后、回显之前**额外**跑：

```bash
bash <skill-path>/scripts/sync-memory.sh sync
```

并把输出追加到回显段：

```
🧪 记忆同步：📦 已同步 N 条记忆 → ./memory/
```

若标志不存在 → 跳过，`/handoffx` 行为和今天 100% 一样。

## 与 `/handoffx-recall` 的关系

`/handoffx-recall` **不**主动加载 `./memory/*.md` 正文——context 太贵。但会在报告头部多一行：

```
🧪 项目记忆：N 文件可用于 ./memory/（输入"读记忆"查看正文）
```

仅在 `./memory/.sync-enabled` 存在时显示。用户想看时说"读记忆"或"load memory"，AI 再读。

## 规则

- **只操作 `./memory/`** —— 不碰 HANDOFFX.md，不碰 git，不碰 `~/.claude/`（只读 CC 源）
- **覆盖式同步，不做镜像** —— 项目本地多出的 .md 文件不会被删（用户可能手写了一些本地记忆）
- **源不存在不是错误** —— CC 没记忆就是没记忆，脚本 exit 0，打印提示即可
- **不把 `./memory/` 加 .gitignore** —— 是否入版本由项目自己决定；但**首次 `on` 且检测到 `.git/`** 时会提示用户考虑手动加入（见下）
- **每次 `on` 都跑一次 sync** —— 新项目首次启用，或换机器后首次启用都能立刻吃到记忆
- **实验性标记要保留** —— 命令描述、报告输出都带 🧪 / "experimental"，提示 API 可能变
- **拒绝 symlink** —— CC 源里的 symlink 一律跳过（防攻击者植入 `/etc/passwd` 等链接被当作记忆同步进项目）
- **同步后自动跑凭证扫描** —— 用 `scan-credentials.sh` 扫新同步的文件；发现 → 警告 + `sync` 返回非 0；**不撤销已同步的文件**（决策权交给用户）

## 敏感信息保护（自动化）

### 同步后凭证扫描

每次 `sync` / `on` 动作在复制完成后，会自动对 `./memory/*.md` 逐个跑 `scan-credentials.sh`。若发现 11 种已知密钥前缀（OpenAI / Anthropic / GitHub × 4（含 fine-grained PAT）/ AWS / Slack / Supabase / HuggingFace / PEM 头）中任何一种：

```
🔴 凭证扫描：./memory/ 中检测到疑似凭证！
   • feedback_xxx.md

   建议：编辑上述文件把明文密钥换成 $ENV_VAR 或 vault://；
   然后重跑 /handoffx-memory sync。或 /handoffx-memory off 关闭同步。
```

`sync` 子命令此时退出码为 1，让 `/handoffx` 的后置回显能看到并标红。

扫描**无法进行**时不按 clean 处理：`scan-credentials.sh` 缺失，或某个已同步文件读不到（`scan-credentials` exit 2），`sync` 退出码为 2 并明说"无法验证 / 无法扫描"——这不是"发现凭证"，但也不能当作干净（Gotcha #24）。

### `.gitignore` 提示（仅首次 on）

第一次 `on`（标志文件本来不存在）且项目根有 `.git/`，且 `.gitignore` 没包含 `memory/`：

```
💡 检测到 .git/ 仓库。本项目的 ./memory/ 即将随 commit 进入版本管理。
   如果记忆里可能含客户名 / 内部 URL / token 等敏感内容，建议加入 .gitignore：

     echo 'memory/' >> .gitignore

   （这只是提醒，不会自动添加——记忆是否入版本由你决定）
```

非 git 仓库、已忽略、或第二次 on → 静默不打扰。

## 别名

`handoffx-memory` / `/handoffx-mem` / `/记忆同步` 一律按 `/handoffx-memory` 执行。
