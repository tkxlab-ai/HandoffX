# Contributing

感谢你考虑为 HandoffX Plugin 做贡献。本项目是纯 Bash + Markdown，约定简单。

## 开发环境

- macOS 或 Linux
- Bash 3.2+（macOS 默认版本）
- 测试依赖：shellcheck + ruby + unzip + zip + rsync + `LANG=C.UTF-8`（与 README 平台表一致；缺 shellcheck 时 `tests/test_shellcheck.sh` 直接失败）

## 本地验证

任何改动前后都跑一遍回归：

```bash
bash tests/run_all.sh
```

应输出 `All suites passed ✅`。Linux 复验（维护者工具，需 Docker/OrbStack）：`bash tests/linux-container.sh [--root] [--image ubuntu:22.04]`。

**分发契约**：全量验证需要 git 检出（checkout）——legacy-names 守卫用 `git ls-files` 枚举文件，发布契约的 scrub 段用 `git archive HEAD` 出包，dogfood 段读活的项目语料。在解压出来的源码包里这些段会打印 `➖ SKIPPED` 并写明原因，`run_all` 末尾汇报跳过计数；dogfood 段回退到 `tests/fixtures/p2-1-synthetic-v2/`（夹具以中性名 `legacy-main.md` / `legacy-gotchas.md` / `legacy-logs/` / `legacy-decisions/` 存放，因为 gitx 深度审计在源码包任意深度拒绝旧四件套名；`tests/common.sh` 的 `p21_materialize` 在沙箱里按旧名还原）。

## 目录结构约定

```
scripts/                     → 开发版 bash 脚本（与 skill 内副本字节级同步）
skills/handoffx/              → Skill 本体（install.sh 的唯一安装源）
  ├── SKILL.md               →   入口
  ├── references/            →   命令详细规范
  ├── command-shims/         →   slash shim 源（install.sh 拷到 ~/.claude/commands/；v2.1.3 起改名，原 `commands/`）
  ├── scripts/               →   随 skill 分发的脚本（与根 scripts/ 字节级同步）
  ├── assets/                →   新项目的 HANDOFFX.md 起点模板
  └── evals/                 →   评估场景定义
tests/                       → TDD 测试套件 + fixtures（38 套件 / 1636 断言点）
install.sh                   → 一键安装到 ~/.claude/skills/handoffx/
release.sh                   → 发版打包 + 安全扫描
```

> **Canonical template path**：`skills/handoffx/assets/HANDOFFX.template.md`（`install.sh` 从这里拷贝）。

- 脚本进 `scripts/` 且必须有同名 `tests/test_<feature>.sh`
- fixtures 放 `tests/fixtures/`，**禁止包含真实凭证**
- 任何 `#!/bin/bash` 脚本必须兼容 bash 3.2

## 代码风格

- 路径：**不要硬编码绝对路径**。用 `"$(cd "$(dirname "$0")" && pwd)"` 派生，或用 `$HOME` / `~` 引用用户目录
- 不依赖 git / 版本管理（handoffx 是用户需求工具，与 vcs 正交）
- grep 接用户输入时用 `grep -E -- "$pattern"`（见 HANDOFFX.md 的 Gotcha #1）
- 不使用 `set -u`，除非已验证所有数组路径（bash 3.2 空数组 bug）
- 中文注释 / 英文命令名 / 英文 commit message

## 提交规范

```
<type>: <summary>

<body（可选）>
```

type: `feat` / `fix` / `refactor` / `docs` / `test` / `chore`

## TDD 流程

1. 先写 `tests/test_<feature>.sh`（RED）
2. 跑 `bash tests/test_<feature>.sh`，确认失败
3. 最小实现到 GREEN
4. 重构（REFACTOR），保持 GREEN
5. 跑 `bash tests/run_all.sh` 确认无回归

## PR 前自检

- [ ] `bash tests/run_all.sh` 全绿
- [ ] `bash scripts/validate-handoff.sh HANDOFFX.md` 通过
- [ ] `bash scripts/scan-credentials.sh HANDOFFX.md` 通过
- [ ] 无绝对路径硬编码：新增/改动的代码与测试不得引入任何 `/Users/<name>/` / `/home/<name>/` 字面量（用 `$HOME` / `~` / `<dev-home>/` 占位）；存量历史 fixture（如 `tests/test_encode_cc_path.sh`）暂予保留，按需逐步迁移（见项目 `CLAUDE.md` 路径规则）。自查：`git diff -U0 | grep '^+' | grep '/Users/[A-Za-z]'` 无命中
- [ ] 更新了相关文档 / README
- [ ] 若改了命令定义（`skills/handoffx/command-shims/*.md`，v2.1.3 起改名，原 `commands/`），跑一次 `/handoffx` 和 `/handoffx-recall` 人工验证

## 发布

本项目仅维护主分支，按需打 tag（`vX.Y.Z`）。变更概要维护在根目录 `CHANGELOG.md`；发版用 `release.sh`，会自动在 `Release/CHANGELOG.md` 插入版本骨架供填写。
