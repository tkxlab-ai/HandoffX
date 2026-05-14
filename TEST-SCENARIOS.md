# Test Scenarios — Handoff Skill

> 用户或贡献者在本地验证 "这技能真的能用" 的操作手册。
> 每个场景必填 **Setup / Action / Expected / Verify** 四字段。

---

## 📖 目录

- [0. 前置条件](#0-前置条件)
- [1. Happy Path](#1-happy-path)
- [2. 边界场景](#2-边界场景)
- [3. 错误路径](#3-错误路径)
- [4. 安全场景](#4-安全场景)
- [5. 幂等性](#5-幂等性)
- [6. 回归核对](#6-回归核对)

---

## 0. 前置条件

- 装好 skill（`./install.sh` 或解压 `.skill`）
- 有一个测试项目目录，例如 `/tmp/test-project`
- 在该项目根已有 `HANDOFF.md`（从 `~/.claude/skills/handoff/assets/HANDOFF.template.md` 复制）
- 在 Claude Code 里打开测试项目

---

## 1. Happy Path

### Scenario 1.1 — 写入第一条 Dev Log

**Setup**:
```bash
mkdir -p /tmp/test-project
cp ~/.claude/skills/handoff/assets/HANDOFF.template.md /tmp/test-project/HANDOFF.md
# 在 Claude Code 里打开 /tmp/test-project
```

**Action**（在 Claude Code 里输入）:
```
/handoff
> 刚给项目加了 src/foo.ts 和 tests/foo.test.ts，4 个单测全绿
```

**Expected**:
- `HANDOFF.md` 顶部新增一条 `### YYYY-MM-DD HH:MM — ...` 条目
- 条目含 `**触发**` / `**改动**` / `**验证**` / `**关联**` 四字段
- 锚点 `<!-- 🚨 AI 注意 -->` 保留在新条目下方
- 回显 5-10 行摘要 + 三态检查结果

**Verify**:
```bash
head -30 /tmp/test-project/HANDOFF.md | grep -cE "^### $(date +%Y-%m-%d)"
# 预期: 1
grep -c "🚨 AI 注意" /tmp/test-project/HANDOFF.md
# 预期: 1
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh /tmp/test-project/HANDOFF.md
# 预期: exit 0
```

---

### Scenario 1.2 — Recall 默认 5 条

**Setup**: 在一个已有 6+ 条 Dev Log 的项目里。

**Action**:
```
/handoff-recall
```

**Expected**:
- 第一行明示本次读取范围（`📖 本次读取：...`）
- 汇报 4 段：最近一次工作 / 待办 / 相关 Gotcha / 建议下一步
- **Dev Log 只读最近 5 条**（不读第 6 条往前）
- 不调用 `date`、不追加任何内容

**Verify**:
```bash
md5_before=$(md5 -q /tmp/test-project/HANDOFF.md)
# [跑 /handoff-recall]
md5_after=$(md5 -q /tmp/test-project/HANDOFF.md)
[ "$md5_before" = "$md5_after" ] && echo "✅ 未改动" || echo "❌ 被改了"
```

---

### Scenario 1.3 — Recall 参数 N=10

**Action**:
```
/handoff-recall 10
```

**Expected**:
- 第一行: `📖 本次读取：... + 最近 10 条 Dev Log`
- 读 10 条（文件不足时读所有现有）

---

### Scenario 1.4 — Tidy 整理乱序文档

**Setup**: 手工把 `HANDOFF.md` 的 Dev Log 条目顺序打乱，插入 3 个连续空行。

**Action**:
```
/handoff-tidy
```

**Expected**:
- 自动：空行压缩、锚点补齐；备份到 `HANDOFF.md.bak`
- AI 修复：条目重排为倒序
- 回显诊断摘要 + 四连检查三态

**Verify**:
```bash
ls /tmp/test-project/HANDOFF.md.bak && echo "✅ 有备份"
# Dev Log 倒序验证
grep -nE "^### [0-9]{4}-[0-9]{2}-[0-9]{2}" /tmp/test-project/HANDOFF.md | head -5
# 日期应递减
# 连续空行检查
awk 'BEGIN{c=0} /^$/{c++; if(c>2){print "❌"; exit 1}} !/^$/{c=0}' /tmp/test-project/HANDOFF.md && echo "✅ 无 > 2 连续空行"
```

---

## 2. 边界场景

### Scenario 2.1 — Dev Log 达到 50 条阈值

**Setup**: 构造一个有 51 条 Dev Log 的 HANDOFF.md。

**Action**:
```
/handoff
> 加了一个小修复
```

**Expected**:
- 新条目写入（总数→52）
- `archive-devlog.sh` 自动触发：主文件留最新 50 条，其余 2 条移到 `HANDOFF.archive.md`
- 回显 `📦 已归档 2 条到 HANDOFF.archive.md`

**Verify**:
```bash
grep -cE "^### [0-9]{4}-" /tmp/test-project/HANDOFF.md
# 预期: 50
grep -cE "^### [0-9]{4}-" /tmp/test-project/HANDOFF.archive.md
# 预期: 2
```

---

### Scenario 2.2 — Recall 参数 N=0 / 负数

**Action**:
```
/handoff-recall 0
/handoff-recall -5
```

**Expected**: 拒绝并明确提示"请给一个正整数，例如 /handoff-recall 10"；不要回退到默认 N=5。

---

### Scenario 2.3 — HANDOFF.md 不存在

**Setup**: 删掉 `HANDOFF.md`。

**Action**:
```
/handoff-recall
```

**Expected**: Claude 提示"此项目尚未初始化 HANDOFF.md"，引导用户从 template 创建。不应崩溃。

---

## 3. 错误路径

### Scenario 3.1 — Dev Log 锚点被手工删除

**Setup**: 手工把 `<!-- 🚨 AI 注意 -->` 锚点删掉。

**Action**:
```
/handoff
> 做了一点改动
```

**Expected**: `/handoff` 检测锚点缺失，在文件末尾新建 Dev Log 章节 + 补锚点，然后正常写入。

**Verify**:
```bash
grep -c "🚨 AI 注意" /tmp/test-project/HANDOFF.md
# 预期: 1
```

---

### Scenario 3.2 — 脚本文件缺失（只安装了 SKILL.md）

**Setup**: 手工删掉 `~/.claude/skills/handoff/scripts/scan-credentials.sh`。

**Action**:
```
/handoff
> 加了个功能
```

**Expected**: 写入继续，但回显显示 `🔐 凭证扫描：➖ 跳过（脚本未找到）`——**不得**伪装成 `✅ 通过`。

---

### Scenario 3.3 — 非 Git 仓库 / 无网络

**Setup**: 在一个没 `git init` 的目录。

**Action**: `/handoff-recall`

**Expected**: 正常工作，**不**尝试读 git。

**Verify**: AI 回复里不应包含分支名、commit hash 等 git 信息。

---

## 4. 安全场景

### Scenario 4.1 — 阻断明文凭证写入

**Setup**: 干净的 `HANDOFF.md`。

**Action**:
```
/handoff
> 把 Supabase service role key sbp_1234567890abcdef1234567890abcdef 写到 Credentials 章节
```

**Expected**:
- AI **拒绝**写明文
- 建议改用 `$ENV_VAR` 或 `vault://` 引用
- 若 AI 硬写，后置 `scan-credentials.sh` 阻断（退出码 1）
- 最终文件里**不含**原始 `sbp_...` 串

**Verify**:
```bash
grep -c "sbp_1234567890abcdef1234567890abcdef" /tmp/test-project/HANDOFF.md
# 预期: 0
bash ~/.claude/skills/handoff/scripts/scan-credentials.sh /tmp/test-project/HANDOFF.md
# 预期: exit 0
```

---

### Scenario 4.2 — Release sanity gate 阻断敏感信息

**Setup**: 在一个测试项目里，往 README.md 插入 `cd /Users/alice/project`（绝对用户路径）。

**Action**:
```bash
./release.sh v-dryrun
```

**Expected**: sanity 扫描报告 `ABSOLUTE USER PATHS`，release abort，退出码 1。

**Verify**:
```bash
echo $?
# 预期: 1
ls Release/v-dryrun/ 2>/dev/null
# 预期: 目录不存在
```

---

### Scenario 4.3 — 凭证到期提醒

**Setup**: 在 `HANDOFF.md` 的 Credentials 章节加一条到期日期 < 7 天的条目。

**Action**:
```bash
bash ~/.claude/skills/handoff/scripts/rotation-reminder.sh /tmp/test-project/HANDOFF.md
```

**Expected**: 输出 `🟠 N 天内过期: <服务名>`，退出码 **1**（不是 0）。

**Verify**:
```bash
bash ~/.claude/skills/handoff/scripts/rotation-reminder.sh /tmp/test-project/HANDOFF.md
echo "exit=$?"
# 预期: exit=1
```

---

## 5. 幂等性

### Scenario 5.1 — /handoff-tidy 连跑两次

**Action**:
```
/handoff-tidy
/handoff-tidy
```

**Expected**: 第二次应报告 `✅ 结构干净`，文件 hash 不变。

**Verify**:
```bash
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh /tmp/test-project/HANDOFF.md
sha1=$(md5 -q /tmp/test-project/HANDOFF.md)
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh /tmp/test-project/HANDOFF.md
sha2=$(md5 -q /tmp/test-project/HANDOFF.md)
[ "$sha1" = "$sha2" ] && echo "✅ 幂等" || echo "❌ 非幂等"
```

---

### Scenario 5.2 — archive-devlog 超阈值后再跑

**Setup**: Dev Log 已经被归档过一次（主文件 50 条 + archive 有若干）。

**Action**: 再跑 `archive-devlog.sh`。

**Expected**: 主文件和归档文件 hash 都不变。

**Verify**: 同上 md5 比对。

---

### Scenario 5.3 — install.sh 重复执行

**Action**:
```bash
./install.sh
./install.sh
./install.sh
```

**Expected**: 每次都输出成功信息，`~/.claude/skills/handoff/` 状态一致，不堆积垃圾。

---

## 6. 回归核对

### 自动测试套件

```bash
bash tests/run_all.sh
```

**当前覆盖率：352 断言 / 19 套件 / 100% 通过**（shellcheck 需本地安装，CI 自动安装），分布：

| 套件 | 断言数 | 覆盖 |
|------|-------|------|
| `test_archive_devlog.sh` | 18 | 小文件幂等 / 大文件归档 / 边界 / 追加归档 / 自定义阈值 / 错误路径 / duplicate header |
| `test_bundle_sync.sh` | 26 | commands/ + references/ 存在性 / frontmatter / 内容完整性 / install.sh 引用 |
| `test_ci_workflow.sh` | 6 | GitHub Actions 触发 / shellcheck / 全量测试 / release dry-run audit |
| `test_doc_freshness.sh` | 14 | 文档版本号 / 测试用例数 / 命令面 / shim 安装说明一致性 / recall 语义 / 文档指纹 / 凭证前缀数量双向守护（禁旧值 + 验新值）|
| `test_encode_cc_path.sh` | 11 | 路径编码 / 末尾斜杠 / --help |
| `test_handoff_lint.sh` | 10 | Dev Log anchor / 倒序 / 必填字段 / 浮动条目 / recall-readiness |
| `test_install.sh` | 75 | 四平台安装 / 卸载 / 项目级 / .skill 自举 / shim 单源注册 / WSL 模拟 / Codex $ aliases |
| `test_no_legacy_templates.sh` | 5 | templates/ 清理验证 / 旧引用清理 |
| `test_recommended_consistency.sh` | 10 | validate/tidy RECOMMENDED 列表一致 + template 章节覆盖 + bundle 同步 |
| `test_release_dry_run_audit.sh` | 12 | staging 安全 / forbidden files / command shims / release manifest / no artifact writes |
| `test_rotation_reminder.sh` | 14 | 过期 / 7d / 30d / far future / 占位符 / 三态退出码 / 模板 schema |
| `test_scan_credentials.sh` | 21 | 11 种凭证前缀（含 github_pat\_ / hf\_）+ 白名单 + stdin 模式 + label 断言 |
| `test_scripts_sync.sh` | 16 | dev 与 bundle 脚本字节级一致 + 可执行权限 |
| `test_shellcheck.sh` | 3 | 脚本静态分析（dev + bundle；需本地安装 shellcheck） |
| `test_skill_metadata_budget.sh` | 3 | skill metadata 字段预算校验 |
| `test_sync_codex_skills.sh` | 7 | ~/.agents/skills → ~/.codex/skills 全量同步 + command alias |
| `test_sync_memory.sh` | 43 | 状态机 / 幂等 / symlink / 凭证 / git 提示 / .sync-enabled 语义 |
| `test_tidy_handoff.sh` | 21 | 空行压缩 / 锚点补齐 / 乱序诊断 / 缺字段诊断 / 幂等 / I9 内容保全 / post-Dev-Log section anchor / short-form anchor no-op |
| `test_validate_handoff.sh` | 34 | 所有 REQUIRED + RECOMMENDED 章节 + readiness / 复合标题 + false positive 防御 |

### 手动验收矩阵

发布前在一个**干净的测试项目**上跑完 Scenario 1-5 所有主要场景，全部 ✅ 才能 release。

### CI 建议

建议在 GitHub Actions 加：

```yaml
- run: bash tests/run_all.sh
- run: ./release.sh v-dryrun || true  # 非 tag 不真发布
- run: bash scripts/release-sanitize.sh .
```

---

## 📌 如何新增场景

1. 找到对应分类（1-5）
2. 按 Setup/Action/Expected/Verify 四字段写
3. 机器可验证优先（shell 脚本），人工验证次之
4. 提 PR 时附在 commit message 里："新增 Scenario X.Y — <简述>"

---

**Copyright (c) 2026 TKXLAB.AI** — 按 MIT 许可分发。
