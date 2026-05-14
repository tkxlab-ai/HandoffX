# INSTALL — 完整安装 / 升级 / 卸载 / 维护命令参考

> README.md 介绍**这个 skill 是什么**。本文档介绍**怎么装、怎么升、怎么删、怎么修**——每条命令都有注解。

---

## 📖 目录

- [0. 文件位置速查表](#0-文件位置速查表)
- [1. 安装](#1-安装)
  - [1.1 方式 A — 源码 + install.sh（推荐）](#11-方式-a--源码--installsh推荐)
  - [1.2 方式 B — 单文件 `.skill`](#12-方式-b--单文件-skill)
  - [1.3 方式 C — 手动复制目录](#13-方式-c--手动复制目录)
  - [1.4 方式 D — curl 一行命令](#14-方式-d--curl-一行命令)
  - [1.5 远程机器 / SSH 部署](#15-远程机器--ssh-部署)
- [2. 首次为某个项目初始化 HANDOFF.md](#2-首次为某个项目初始化-handoffmd)
- [3. 升级](#3-升级)
- [4. 卸载](#4-卸载)
- [5. 验证 / 自检](#5-验证--自检)
- [6. 发版（开发者）](#6-发版开发者)
- [7. 日常维护命令](#7-日常维护命令)
- [8. 排错](#8-排错)

---

## 0. 文件位置速查表

```
~/.claude/
├── skills/handoff/              # Skill 本体（全局安装后）
│   ├── SKILL.md                 # skill 入口
│   ├── references/*.md          # 命令详细规范
│   ├── scripts/*.sh             # 安全扫描 / 结构整理 / 内存同步等脚本
│   ├── commands/*.md            # slash command shims
│   └── assets/HANDOFF.template.md
└── commands/                    # Slash shims（让各子命令不被 fuzzy 成 /handoff）
    ├── handoff-recall.md        #   /handoff 本身由 skill name 注册，无需 shim
    ├── handoff-tidy.md
    ├── handoff-memory.md
    └── handoff-init.md

<项目根>/
├── HANDOFF.md                   # 主文件（顶部带 <!-- HANDOFF v2 schema --> 标记）
├── GOTCHAS.md                   # Known Gotchas 知识库（v2 sibling）
├── Handoff_Logs/                # Dev Log per-file（v2）
│   └── <NNNN>-<timestamp>-<slug>.md
├── Handoff_Decisions/           # Decision Log per-file（v2）
│   └── <NNNN>-<date>-<slug>.md
├── Handoff_Logs.archive/        # 按年归档（v2 替代 HANDOFF.archive.md）
│   └── <YYYY>/
└── .claude/skills/handoff/      # (可选) 项目级安装；覆盖全局
```

> **v1 用户升级**：项目根跑 `/handoff-tidy`——它会检测 v1 layout 并提示是否迁移，原子迁移失败自动回滚。详见 `MIGRATION_GUIDE_v2.md`。

---

## 1. 安装

### 1.1 方式 A — 源码 + install.sh（推荐）

适用：有 git / 想长期维护升级 / 团队部署。

```bash
# 拉取源码
git clone https://github.com/tkxlab-ai/handoff.git
cd handoff

# 全局安装（推荐）
./install.sh
# → 把 skill 装到 ~/.claude/skills/handoff/
# → 把 shims 装到 ~/.claude/commands/handoff*.md
# → 所有 Claude Code 会话生效

# 或：项目级安装（仅该项目可见）
./install.sh --project /path/to/your-project
# → 装到 <project>/.claude/skills/handoff/

# 或：安装 + 自动在目标项目创建 HANDOFF.md
./install.sh --template /path/to/your-project
# → 只创建 HANDOFF.md（不装 skill 本体，适合已经全局装好的情况）

# 或：两者合一
./install.sh --project /path --template /path

# 查看帮助
./install.sh --help
```

**脚本做的事（幂等，可重复执行）**：
1. 清理老版本（避免残留）
2. 复制 `skills/handoff/` 到 `~/.claude/skills/handoff/`
3. 给 `scripts/*.sh` 添加可执行权限
4. 只复制 `handoff-recall.md` / `handoff-tidy.md` / `handoff-memory.md` / `handoff-init.md` 到 `~/.claude/commands/`（`/handoff` 由 skill name 注册）
5. Codex 目标会生成 `$handoff-recall` / `$handoff-tidy` / `$handoff-memory` / `$handoff-init` skill aliases
6. 清理 v0.4 时代的旧格式残留

---

### 1.2 方式 B — 单文件 `.skill`

适用：不想 clone、只想一个文件拷过去。

在 `handoff-v<版本>.skill` 所在目录执行：

```bash
# 创建目录
mkdir -p ~/.claude/skills ~/.claude/commands

# 解压 .skill（本质是 zip）
unzip -o ./handoff-v<版本>.skill -d ~/.claude/skills/
# -o  覆盖现有文件
# -d  目标目录

# 给脚本执行权限
chmod +x ~/.claude/skills/handoff/scripts/*.sh

# 安装 slash command shims（/handoff 由 skill name 注册，其余入口从 command-shims/ 复制；v2.1.3 起改名，原 commands/）
cp ~/.claude/skills/handoff/commands/handoff-{recall,tidy,memory}.md ~/.claude/commands/
cp ~/.claude/skills/handoff/commands/handoff-init.md ~/.claude/commands/
```

> v0.9.3+ 起，`.skill` 内已内置 `commands/`，直接复制即可，无需手动写文件。

---

### 1.3 方式 C — 手动复制目录

最透明但最原始。在源码根目录：

```bash
# 全局
cp -r skills/handoff ~/.claude/skills/handoff
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp skills/handoff/commands/handoff-{recall,tidy,memory}.md ~/.claude/commands/
cp skills/handoff/commands/handoff-init.md ~/.claude/commands/

# 项目级
cp -r skills/handoff /path/to/project/.claude/skills/handoff
chmod +x /path/to/project/.claude/skills/handoff/scripts/*.sh
```

---

### 1.4 方式 D — curl 一行命令

适用：完全信任的源、快速装机。

```bash
curl -fsSL https://raw.githubusercontent.com/tkxlab-ai/handoff/main/install.sh | bash
```

> ⚠️ 这种方式跳过了代码审查。生产/团队环境建议先 clone 再 `./install.sh`。

---

### 1.5 远程机器 / SSH 部署

#### 传源码
```bash
# 本机
scp -r /path/to/Handoff user@remote:~/handoff-src

# 远程
ssh user@remote
cd ~/handoff-src && ./install.sh
```

#### 传 `.skill` 文件
```bash
# 本机
scp Release/handoff-v<版本>.skill user@remote:~/

# 远程
ssh user@remote
mkdir -p ~/.claude/skills
unzip -o ~/handoff-v<版本>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
```

---

## 2. 首次为某个项目初始化 v2 四件套

Skill 本身只需装一次。每个要用 handoff 的项目需要一组 v2 四件套：`HANDOFF.md` + `GOTCHAS.md` + `Handoff_Logs/` + `Handoff_Decisions/`。

### 2.1 让 Claude 建（最自然）

在 Claude Code 里打开项目：
```
/handoff-init
```
Claude 会复制 v2 模板（含 `<!-- HANDOFF v2 schema -->` 标记 + 三组 pointer 块）+ 创建空 GOTCHAS.md + 空 Handoff_Logs/ 和 Handoff_Decisions/ 目录，然后引导你填 Project Overview / Architecture。

### 2.2 install.sh 同时创建

```bash
./install.sh --template /path/to/project
```

> 如果项目已有 v1 单文件 HANDOFF.md（无 v2 marker + inline Dev Log entries），**不要**用 init——改用 `/handoff-tidy`，它会检测 v1 layout 并触发自动迁移。

### 2.3 手动复制

```bash
cp ~/.claude/skills/handoff/assets/HANDOFF.template.md /path/to/project/HANDOFF.md
```

---

## 3. 升级

### 3.1 源码用户

```bash
cd ~/handoff-src
git pull                  # 拉最新
./install.sh              # 覆盖安装（幂等）
```

然后在 Claude Code 里：
```
/reload-plugins           # 或退出重开
```

### 3.2 `.skill` 单文件用户

在新版 `handoff-vX.Y[.Z].skill` 所在目录：

```bash
unzip -o ./handoff-v<版本>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp ~/.claude/skills/handoff/commands/handoff-{recall,tidy,memory}.md ~/.claude/commands/
cp ~/.claude/skills/handoff/commands/handoff-init.md ~/.claude/commands/
```

然后 `/reload-plugins`。

### 3.3 已有项目 HANDOFF.md 同步新 template

Skill 升级后，项目里的 `HANDOFF.md` 不会自动重写。建议在项目根目录打开 Claude Code，执行：

```
/handoff-tidy
```

它会：
- 补缺失的章节到最新 template
- 整理 Dev Log 倒序 + 缺失字段
- 跑 scan / validate / rotation / archive 后置四连检查
- 备份原文到 `HANDOFF.md.bak`

### 3.4 升级后验证

```bash
# 对比版本
cat ~/.claude/skills/handoff/SKILL.md | head -5

# 跑自检
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh ~/.claude/skills/handoff/assets/HANDOFF.template.md
# 应输出: ✅ HANDOFF.md structure OK
```

---

## 4. 卸载

### 4.1 完全卸载（保留项目数据）

```bash
cd ~/handoff-src
./install.sh --uninstall
```

会清除：
- `~/.claude/skills/handoff/`
- `~/.claude/commands/handoff.md` / `handoff-recall.md` / `handoff-tidy.md` / `handoff-memory.md` / `handoff-init.md`
- v0.4 时代的 `~/.claude/handoff-scripts/` 残留

**保留**：各项目根目录里的 `HANDOFF.md`（你的数据）。

### 4.2 仅清理项目级安装

```bash
rm -rf /path/to/project/.claude/skills/handoff
```

### 4.3 彻底删掉某个项目的文档（慎用）

```bash
rm -f /path/to/project/HANDOFF.md /path/to/project/HANDOFF.archive.md /path/to/project/HANDOFF.md.bak
```

---

## 5. 验证 / 自检

### 5.1 Claude Code 里验证

```
/          # 看命令列表，应出现 /handoff /handoff-recall /handoff-tidy /handoff-memory
```

或自然语言：
```
帮我做一次交接      # 应触发 handoff skill
```

### 5.2 命令行自检

```bash
# 检查文件布局
ls ~/.claude/skills/handoff/SKILL.md && echo "✅ skill ok" || echo "❌ 未装"
ls ~/.claude/commands/handoff-recall.md && echo "✅ shim ok" || echo "❌ shim 缺失"

# 验证脚本可执行
bash ~/.claude/skills/handoff/scripts/scan-credentials.sh /dev/null; echo "scan-credentials exit=$?"
# 期望: exit=2（文件空）或 exit=0

# 验证 template 结构
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh \
     ~/.claude/skills/handoff/assets/HANDOFF.template.md
# 期望: ✅ HANDOFF.md structure OK
```

---

## 6. 发版（开发者）

### 6.1 一条命令发版

```bash
./release.sh v<版本>         # 跑回归 + 安全扫描 + 打 .skill + 打 tarball
# 或直接说 "release" 给 Claude，它会自动递增版本号并执行
```

### 6.2 release.sh 做的事

1. **跑回归测试**（`bash tests/run_all.sh`）——失败就 abort
2. **打 `.skill`** 到 `Release/<版本>/handoff-<版本>.skill`
3. **预发布 sanity 扫描**（`release-sanitize.sh`，由 `release.sh` 的 `locate_tool` 从外部 `Release_pipeline` 定位，不在本仓 `scripts/`）——扫 6 类敏感信息：
   - 凭证前缀（11 种）
   - 绝对用户路径
   - 真实邮箱（豁免 example.com 等）
   - 公网 IP（豁免私网段 / 常见公共 DNS）
   - MAC 地址
   - SSH/GPG 指纹
4. **staging + `.skill` 双扫描** —— 两层都过才继续
5. **打源码 tarball**（排除 `.git` / `Release/` / `handoff.skill` / dev-only 目录）
6. **生成 per-version `RELEASE_NOTES.md`**（同时把主 `README.md` 复制到版本目录供不解压直接浏览）
7. **更新 `Release/latest` 软链接**
8. **在 `CHANGELOG.md` 顶部插入新版本骨架**（用户填真实说明）

### 6.3 sanity 不可绕过

release sanity 是硬安全门。若 staging 或 `.skill` 扫描发现敏感信息，必须修复后重新发布。

---

## 7. 日常维护命令

### 7.1 手动跑一次完整检查

```bash
cd /path/to/project
bash ~/.claude/skills/handoff/scripts/scan-credentials.sh HANDOFF.md
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh --readiness HANDOFF.md
bash ~/.claude/skills/handoff/scripts/rotation-reminder.sh HANDOFF.md
bash ~/.claude/skills/handoff/scripts/archive-devlog.sh HANDOFF.md
```

### 7.2 强制归档 Dev Log（自定义阈值）

```bash
bash ~/.claude/skills/handoff/scripts/archive-devlog.sh HANDOFF.md 20
# 保留最新 20 条，其余进 HANDOFF.archive.md
```

### 7.3 整理 HANDOFF.md 结构（不进 Claude）

```bash
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh HANDOFF.md
# 修：多余空行 / 锚点缺失
# 报告：缺章节 / Dev Log 乱序 / 缺字段（AI 来修）
```

### 7.4 跑完整回归测试（开发者）

```bash
cd ~/handoff-src
# bash tests/run_all.sh      # 当前：17 套件 / 296 断言全过
bash tests/run_all.sh
```

### 7.5 清理旧 Codex 镜像入口

```bash
bash ~/.claude/skills/handoff/scripts/sync-codex-skills.sh
```

Codex 官方用户 skills 路径是 `~/.agents/skills`。此脚本只清理旧版本曾生成的重复镜像入口，避免 `$` selector 出现双份命令；不会再创建 Codex 专用镜像目录。

---

## 8. 排错

### 8.1 `/handoff` 不出现在命令列表

```bash
# 检查安装
ls -la ~/.claude/skills/handoff/SKILL.md

# 检查 Claude Code 版本（需支持 skills）
claude --version

# 重载或重启 Claude Code
# 在 Claude Code 里: /reload-plugins
```

### 8.2 脚本报 "permission denied"

```bash
chmod +x ~/.claude/skills/handoff/scripts/*.sh
```

### 8.3 `/handoff-recall` 被误匹配成 `/handoff`

确认 shims 装好：

```bash
ls ~/.claude/commands/handoff*.md
# 应看到: handoff-recall.md  handoff-tidy.md  handoff-memory.md  handoff-init.md
# （/handoff 本身由 skill name 注册，无需 shim）
```

如果缺，跑 `./install.sh` 重装。

### 8.4 旧版命令和新版冲突

```bash
./install.sh --uninstall    # 清除所有残留
./install.sh                # 重新装
```

### 8.5 HANDOFF.md 结构错乱

在 Claude Code 里：
```
/handoff-tidy
```

或命令行：
```bash
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh /path/to/project/HANDOFF.md
```

### 8.6 归档后主文件丢数据（极罕见）

`archive-devlog.sh` 是原子操作，正常情况下不会丢。如果出事：

```bash
# 主文件备份（tidy 时自动创建）
ls /path/to/project/HANDOFF.md.bak

# archive 文件保留了移动的条目
cat /path/to/project/HANDOFF.archive.md
```

两者合并即可恢复。

---

更多设计哲学和工作原理见 [README.md](./README.md)。
