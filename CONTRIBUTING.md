# Contributing

感谢你考虑为 Handoff Plugin 做贡献。本项目是纯 Bash + Markdown，约定简单。

## 开发环境

- macOS 或 Linux
- Bash 3.2+（macOS 默认版本）
- 无其他依赖

## 本地验证

任何改动前后都跑一遍回归：

```bash
bash tests/run_all.sh
```

应输出 `All suites passed ✅`。

## 目录结构约定

```
scripts/                     → 开发版 bash 脚本（与 skill 内副本字节级同步）
skills/handoff/              → Skill 本体（install.sh 的唯一安装源）
  ├── SKILL.md               →   入口
  ├── references/            →   命令详细规范
  ├── command-shims/         →   slash shim 源（install.sh 拷到 ~/.claude/commands/；v2.1.3 起改名，原 `commands/`）
  ├── scripts/               →   随 skill 分发的脚本（与根 scripts/ 字节级同步）
  ├── assets/                →   新项目的 HANDOFF.md 起点模板
  └── evals/                 →   评估场景定义
tests/                       → TDD 测试套件 + fixtures（26 套件 / 591 断言）
install.sh                   → 一键安装到 ~/.claude/skills/handoff/
release.sh                   → 发版打包 + 安全扫描
```

> **Canonical template path**：`skills/handoff/assets/HANDOFF.template.md`（`install.sh` 从这里拷贝）。

- 脚本进 `scripts/` 且必须有同名 `tests/test_<feature>.sh`
- fixtures 放 `tests/fixtures/`，**禁止包含真实凭证**
- 任何 `#!/bin/bash` 脚本必须兼容 bash 3.2

## 代码风格

- 路径：**不要硬编码绝对路径**。用 `"$(cd "$(dirname "$0")" && pwd)"` 派生，或用 `$HOME` / `~` 引用用户目录
- 不依赖 git / 版本管理（handoff 是用户需求工具，与 vcs 正交）
- grep 接用户输入时用 `grep -E -- "$pattern"`（见 HANDOFF.md 的 Gotcha #1）
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
- [ ] `bash scripts/validate-handoff.sh HANDOFF.md` 通过
- [ ] `bash scripts/scan-credentials.sh HANDOFF.md` 通过
- [ ] 无绝对路径硬编码（`grep -r "/Users/" .` 无命中）
- [ ] 更新了相关文档 / README
- [ ] 若改了命令定义（`skills/handoff/command-shims/*.md`，v2.1.3 起改名，原 `commands/`），跑一次 `/handoff` 和 `/handoff-recall` 人工验证

## 发布

本项目仅维护主分支，按需打 tag（`vX.Y.Z`）。变更概要维护在根目录 `CHANGELOG.md`；发版用 `release.sh`，会自动在 `Release/CHANGELOG.md` 插入版本骨架供填写。
