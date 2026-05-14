---
schema: 2
type: dev-log
date: 2026-04-23T20:42
number: 0011
title: Experimental `/handoff-memory`：opt-in 把 CC auto-memory 固化到项目；6 轮循环 + 双重敏感信息护栏
---

### 2026-04-23 20:42 — Experimental `/handoff-memory`：opt-in 把 CC auto-memory 固化到项目；6 轮循环 + 双重敏感信息护栏

**触发**: 用户提出"能否把 Claude 的记忆和 session 也存到项目目录里，这样切换终端可以无缝开发"。分析 HANDOFF Non-Goals 后决定：session 不做（体积 + 安全），memory 做但作为 opt-in experimental；随后按 TDD 落地 + 6 轮循环测试找 bug + 敏感信息收尾。

**改动**:
- `scripts/encode-cc-path.sh` 新建 — 把项目绝对路径编码成 CC `~/.claude/projects/<...>` 里的目录名（`/_.` → `-`）；规范化末尾斜杠
- `scripts/sync-memory.sh` 新建 — `status|on|off|sync` 四子命令；逐文件 `rm -f → cp → chmod u+w` 防只读锁死；`[ -L "$f" ] && continue` 拒绝 symlink；同步完自动跑 `scan-credentials.sh` 对 `./memory/*.md`；首次 `on` + `.git/` 存在 + `memory/` 未在 `.gitignore` → 打印手动添加建议
- `skills/handoff/scripts/` 同步副本（下述元测试强制）
- `skills/handoff/commands/handoff-memory.md` 新建 slash shim（🧪 Experimental 在 description）
- `skills/handoff/references/handoff-memory.md` 新建行为规范（含 Non-Goal 例外论证 + 两道护栏说明）
- `skills/handoff/references/handoff-write.md` 末尾加"若 `./memory/.sync-enabled` 存在 → 调 `sync-memory.sh sync`"触发器 + 回显新增 `🧪 记忆同步` 行
- `skills/handoff/references/handoff-recall.md` 按需读列表加 `./memory/*.md`；报告模板加"项目记忆：N 文件可用"提示（仅在标志存在时）
- `install.sh:192` — shim 清单加 `handoff-memory.md`；`cleanup_legacy` / `--uninstall` 同步清理
- `install.sh:206` — 安装验证加 `handoff-memory.md` 断言
- `tests/common.sh:25,37` — **Gotcha #1 潜伏 bug 首次触发并修**：`assert_contains` / `assert_not_contains` 的 `grep -qF` 没加 `--`，被 encode test 的 `-a-b-c` 断言撞出
- `tests/test_encode_cc_path.sh` 新建（11 断言：6 种路径形态 + 末尾斜杠归一 + --help + 空参）
- `tests/test_sync_memory.sh` 新建（39 断言：状态机 + 幂等 + 只读源 + symlink 拒绝 + 凭证扫描 + gitignore 提示 + set -e 不阻断）
- `tests/test_scripts_sync.sh` 新建（11 断言）— **元测试**：`scripts/` 与 `skills/handoff/scripts/` 必须字节级一致 + 全部可执行，永久防止"只改 dev 版忘了同步 bundle 版"
- `tests/test_install.sh` +3 断言（C1 Claude / C3 OpenCode / C7 project-level 都装 `handoff-memory.md` shim）
- `README.md` 新增 `## 🧪 Experimental：/handoff-memory（记忆跟随项目走）` 整节 + TOC 链接
- `HANDOFF.md` Non-Goals 加一行"🧪 例外（opt-in experimental）"明示破例原则

**6 轮循环测试捕获的 bug**:
- Bug #6（R2 边界）: `encode-cc-path.sh` 末尾斜杠产生 `-foo-bar-`，错过真实 CC 源 → 修: `sed 's|/\{1,\}$||'`
- Bug #7（R3 安装，**高严重度**）: dev `scripts/` 与 `skills/handoff/scripts/` 双副本机制，我只加到 dev 版，installed bundle 缺两个新脚本 → `/handoff-memory` 在真实环境 command-not-found。修: 同步 + 永久性 `test_scripts_sync.sh` 兜底
- Bug #8（R6 安全）: CC 源 0400 只读文件 → `cp` 保留 mode → 下次 sync 触发 `Permission denied` 锁死。修: 预 `rm -f` + 显式 `chmod u+w`
- Bug #9（R6 防御性）: `cp` 默认 follow symlink，攻击者植入 `/etc/passwd` 等链接可被拷进 `./memory/`。修: `[ -L "$f" ] && skipped_symlink=$((skipped+1))`
- Bug #10（收尾阶段）: `set -e` + `do_sync; ec=$?` 序列在 scan 命中 return 1 时 set -e 先中断，`.gitignore` 提示永远打不印。修: 改用 `if do_sync; then ec=0; else ec=$?; fi`——if 上下文里 set -e 自动抑制

**走过的弯路**:
- 最初建议"在新电脑用脚本反查 CC 路径读历史 memory"（方案 2），用户纠正意图为"让记忆跟着项目文件夹走"，重定为落库方案——提醒自己区分"工具如何工作"与"用户想解决什么"
- R6.5 `$(rm -rf /tmp).md` 文件名：测试自己在 double-quote 下让 shell 先展开了命令替换，不是产品 bug；差点误报成严重漏洞。教训：测试 adversarial 输入时用 single-quote 赋值 + **存为变量**后 `"$var"` 引用，避免测试自己变成攻击载体
- R6.7 200 字符路径：撞到 macOS 单段文件名 ≤255 字节硬限，FS 限制非产品 bug
- 最初用 `do_sync || true; ec=$?` 规避 set -e，`||` 让 `$?` 变成 0 永远捕不到真实退出码；最终用 `if`-form 才两全

**验证**:
- `bash tests/run_all.sh` → 9 suites, **180 passed, 0 failed**（本轮前 124 → +56；含 11 encode + 39 sync + 11 scripts-sync + 3 install 扩展 + 2 common.sh 修复隐含回归）
- 实际项目 `./memory/` 从 1 文件（旧 `feedback_handoff_protocol.md`）→ 启用后 3 文件（MEMORY.md + `feedback_release_protocol.md` 实战固化）
- E2E 模拟 git 项目 + 植入 fake `ghp_...` token：三道信号按序触发（📦 sync → 🔴 credential warning → 💡 gitignore hint），退出码 1 正确传播到调用者

**关联**: Decision 2026-04-23（本次新增，见下）；Gotcha #1 首次实际触发；Gotcha #6 新增；HANDOFF Non-Goals opt-in 例外；Features 表新增行

**待办变动**:
- ✅ 关闭：experimental 记忆同步功能（6 轮循环 + 5 bug 修复 + 双护栏）
- 🆕 新增：真实跨机验证——切到另一台电脑打开本项目，确认 `./memory/` 被新机 Claude 直接读到
- 🆕 新增：下次发版（v1.2 候选）带本次改动：palette 单源 + experimental memory sync + 测试套件 124→180

