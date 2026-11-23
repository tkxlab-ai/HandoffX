# `/handoffx-memory` — 跨电脑记忆备份规范

启动时仅提示「🚀启动handoffX项目交接流程.」一次；宿主已显示则不重复。执行中的异常、警告、阻断和必要确认应及时正常提醒，不受常规字数或单次回复限制，不必等到结束或用户要求详情；需要确认时暂停相应操作。不得泄露凭证，正常进度不反复播报。

> 默认开启。交接时**导出本机备份**，召回时**读取其他电脑的备份**。

## 背景

Claude Code 的 auto-memory 存在**机器本地** `~/.claude/projects/<encoded-path>/memory/`（`<encoded-path>` 由项目物理绝对路径派生，`/` `_` `.` → `-`；安装器的 `CLAUDE_CONFIG_DIR` 不改变这个源路径，`HOME_OVERRIDE` 仅为测试 hook）。项目文件夹在几台电脑间同步时，记忆不跟着走。

本功能在项目里放一个**备份与跨机读取区** `.agent-sessions-sync-hx/`：

```
.agent-sessions-sync-hx/
  .sync-disabled                    ← 存在即关闭（默认没有 = 开启）
  machines/<机器名>/
    claude-code/memory/*.md         ← 本机记忆的单向备份（先扫凭证）
    sessions.md                     ← 本机本项目的会话清单（只有元数据）
```

- **机器名**：macOS 用 `scutil --get LocalHostName`，其他系统用 `hostname -s`；转小写，非 `[a-z0-9-]` 换成 `-`。
- **每台电脑只写自己的子目录**：一个文件只有一个写入方，Syncthing 等同步工具不会出现两台同时改同一文件。
- **客户端名单独一层**（`claude-code/`）：以后可接入其他客户端，目前只备份 Claude Code。
- **会话清单** `sessions.md`：表头 `| 客户端 | 界面 | 会话 ID | 开始 | 结束 |`，按开始时间排序；只取每个会话文件首尾 64KB 里的时间与入口字段，**不含任何对话内容**。

## 这个目录不是什么

- **不是任何客户端的运行目录**：不改 `autoMemoryDirectory` 等客户端配置，Claude Code 照常读写本机 `~/.claude`。
- **不导入**：别的电脑的记忆不会写进本机 `~/.claude`，也没有 import 命令；召回读到的内容只进入本次会话。
- **不同步原始会话**：会话记录里可能有凭证，体量大，路径编码还随用户名变，只记元数据清单。

## 子命令

| 命令 | 行为 |
|------|------|
| `/handoffx-memory` | 显示状态：开启/关闭、机器名、已备份文件数、会话数、源路径、备份路径 |
| `/handoffx-memory on` | 删除 `.sync-disabled` 并立即备份一次 |
| `/handoffx-memory off` | 创建 `.sync-disabled`；已有备份保留（要清掉请自行删除本机子目录） |
| `/handoffx-memory sync` | 不看开关，立即备份一次 |

脚本另有 `auto`（未关闭才备份），供交接收尾自动调用，用户无需手动执行。

## 执行流程

1. **定位脚本**：使用当前生效技能的 `<skill-path>/scripts/sync-memory.sh`。安装位置与记忆源位置不是同一个配置项。
2. **调用脚本**：在用户明确的项目物理根执行，禁止以父目录或仅凭当前 cwd 猜目标；每个子命令都校验根：`bash <skill-path>/scripts/sync-memory.sh --expect-root "<已确认项目绝对路径>" <subcommand>`
3. **回显输出**：原样转发脚本 stdout/stderr，不包装证据。

## 与 `/handoffx` 写入流程的集成

`handoff-runtime.sh finalize` 在后置检查成功后自动执行 `sync-memory.sh auto`，Agent 不再单独调用。备份失败只在 stderr 给一行「⚠️ 跨电脑备份未更新（交接已保存）：…」，交接照常成功，退出码与确认文字不变。出现这行警告时如实转告用户，不重复其它正常进度。

## 与 `/handoffx-recall` 的关系

召回在日志之后追加只读的**跨机段**（只有存在其他电脑的备份时才出现），不读本机自己的子目录：

```
--- cross-machine backups (.agent-sessions-sync-hx, read-only) ---
current_machine=<本机>
machine=<另一台> last_session_end=<UTC|unknown> sessions=<n> memory_files=<k> new_or_changed=<d>
--- <另一台>/claude-code/memory/<文件> (not on this machine|differs from this machine) ---
<正文>
```

- 只带入本机没有、或内容不同的记忆；按内容去重，`MEMORY.md` 索引只计数不读。
- 跨机段 ≤4096 字节，且整体仍受召回 24576 字节预算约束：放不下的记忆只列名字（`omitted: budget`）；再不够只保留每台电脑一行；仍不够写 `cross_machine=deferred_budget`。
- symlink、不可读文件一律跳过，不让召回失败。召回不写任何文件。

## 规则

- **只写本机子目录** `machines/<本机>/`，不碰 HANDOFFX.md、不碰 git、不写 `~/.claude/`（只读源）。
- **覆盖式备份，不做镜像**：先暂存并验证，成功后逐文件替换同名副本；备份目录里多出的 `.md` 不删除，但纳入发布前扫描。
- **没有源数据不建目录**：本机没有记忆、也没有会话时，脚本 exit 0，不创建 `.agent-sessions-sync-hx/`。
- **拒绝 symlink**：源里的 symlink 跳过；备份路径上任何一级是 symlink 时拒绝写入。
- **旧版 `./memory/` 迁移**：只有带 `./memory/.sync-enabled` 标志（本技能旧版所建）时才迁移进本机子目录；同名同内容直接去掉旧副本，同名不同内容另存 `<名>.legacy.md`，仍冲突的留在原处并警告。没有标志的 `./memory/` 不碰。
- **是否入版本由项目决定**：首次 `on` 且新建了备份目录、项目有 `.git/` 时，提示考虑把 `.agent-sessions-sync-hx/` 加入 `.gitignore`，不自动添加。

## 敏感信息保护

每次备份按下列顺序执行：

1. 源目录不存在：提示并跳过记忆部分。源目录不可读/不可遍历：exit 2。
2. 在备份目录所在文件系统内暂存源中的普通、非隐藏 `.md` 文件；不跟随 symlink。暂存失败 exit 2，旧副本不变。
3. 用 `scan-credentials.sh` 扫描**暂存的新文件 + 不会被替换的已有备份 `.md`**。扫描器识别 14 类凭证模式及敏感表头列启发式，覆盖边界以其 `--help` 为准；未命中不代表不存在任何敏感内容。
4. 整批扫描通过才逐文件发布。每个文件独立替换，**不是整批事务**：中途失败返回 exit 2 并报告已发布数量，此前已发布的不回滚。

凭证命中时尚未发布任何文件，旧副本不变。应修改 Claude Code 记忆源（或命中的已有备份文件）后重试，不要只改临时副本，也不要把失败解释为备份成功。

| 退出码 | 含义 |
|--------|------|
| `0` | 备份完成，或没有可备份的数据；以实际输出区分，不能凭 exit 0 宣称复制了文件 |
| `1` | 发布前凭证命中，未发布、旧副本保留；未知子命令/部分用法错误也返回 1 |
| `2` | I/O、发布失败，或扫描器缺失/文件无法扫描；发布阶段失败可能已完成部分文件 |

记忆、会话清单、旧版迁移三步互不阻断，返回其中最差的退出码。

## 别名

`handoffx-memory` / `/handoffx-mem` / `/记忆同步` 一律按 `/handoffx-memory` 执行。
