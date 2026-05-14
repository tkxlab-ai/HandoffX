---
schema: 2
type: decision
date: 2026-05-11
number: 0016
title: v2.1.2 — Linux 兼容性选 C 全修 38 断言，拒 A 仅文档化 / B 部分修
---

### 2026-05-11 — v2.1.2 — Linux 兼容性选 C 全修 38 断言，拒 A 仅文档化 / B 部分修

**背景**

v2.1.1 实战观察期决策刚定（Dev Log 0041），Boss 问"是否支持 Linux 安装"——HANDOFF.md "目标平台"行明文写"macOS（主测）/ Linux（兼容：bash 3.2+ / BSD grep / date）"。读现场后判定：代码层声称 + 用户文档静音 + 测试层零真机覆盖（"靠 fallback 代码 + 理论推断"）。Boss 选 b "做虚拟机真机测试"——Mac mini M4 (10 核 / 24 GB / 800 GB) + OrbStack（已装但停）支持，启动后 docker pull ubuntu:22.04 实测。

第一轮（缺 deps）：8 套件挂。第二轮（装 shellcheck/ruby/unzip）：6 挂。第三轮（locale C.UTF-8 + rsync）：5 挂 / 38 断言。识别单一根因：**Ubuntu 默认 awk = mawk，不支持 regex interval `{N}`**——14 处 `[0-9]{4}` 在 mawk 失配。

**触发**

Boss 看完 5 套件失败明细后选 **C — 全修 38 断言发 v2.1.2 Linux compat release**。

**选项**

- **A** — 仅文档化（"Linux 实测：基本功能 OK，migrate/archive/lint 三块有已知 bug；用户撞到再报"）。+Gotcha #15 + HANDOFF "目标平台"行诚实声明 + 5 个 suite 入 v2.2.0 backlog。不发版。工时 ~30 分钟。**拒**——HANDOFF 长期声明"Linux 兼容"已经是部分谎言，再加文档承认只是修辞修复不是真修复。任何 Linux 用户跑 run_all 仍会撞 38 fail。
- **B** — 修最严重的 1-2 个（lint out-of-order / archive trim）发 v2.1.2 patch，其余推 v2.2.0。**拒**——这 38 个断言全部源于**单一根因**（mawk regex interval 不支持），分批修等于把同一个根因散到两个 release 里没意义；找到根因后做半套修复是技术债，不是 surgical。
- **C（选）** — 全修：14 处 awk regex POSIX 化 + B7-a skip-on-root + 完整知识资产沉淀（Gotcha #15 + Decision 0016 + CHANGELOG v2.1.2 + Linux deps 清单）+ Ubuntu 22.04 容器 24/24 + macOS 24/24 双绿验证 + 发 v2.1.2 release。工时 ~2h。**优势**：根因一次性消灭 + Linux 用户首次能真实 "bash install.sh + bash tests/run_all.sh" 全绿 + HANDOFF "目标平台"行从"兼容（理论推断）"升级成"实测过 Ubuntu 22.04 容器 24/24 ✅"——文档从修辞变物理。
- **D**（未选）— 把 Linux 从 supported platforms 撤回。**拒**——倒退；M4 上 OrbStack 实测证明 Linux 兼容性差距很小（1 个根因 + 测试环境一个适配点）。

**理由（为何 C）**

1. **Linus #1 真问题**：38 个断言全挂在单一根因（mawk vs BSD/gawk regex interval），不是 38 个分散小 bug——这是**编译期级别**的兼容性盲点（看起来 POSIX 但实际依赖 BSD/GNU 扩展）。同样根因还可能埋在未来新写的 awk 里——修一次 + 一条 Gotcha #15 设计教训，长期防止回归比"靠用户撞"高出一个数量级
2. **Linus #2 简单**：根因找到后修法机械（4 个文件 × 几次 replace_all = 14 个 regex literal 改写）；测试侧 B7-a 一个 if 块。工时 ~2h 含完整 release pipeline
3. **Linus #3 不破坏**：POSIX 显式重复 `[0-9][0-9][0-9][0-9]` 在 BSD awk / gawk / mawk **三家一致行为**——macOS 跑 run_all 24/24 ✅ 验证无回归
4. **Karpathy#2 simplicity-first**：不引入 awk fallback chain（"先试 gawk 不行再 mawk"）这类复杂度；直接消除依赖
5. **Karpathy#3 surgical**：只动 awk 内部 regex（14 处）+ 1 个测试条件分支；不动 sed -E / grep -E（这两个所有平台支持 `{N}`）/ scan-credentials 的 `{20,}` 等
6. **Tacit#4 Why > How**：Gotcha #15 不光记"怎么改"，更记 "**机械验证 > 理论推断**"的设计教训——未来跨平台兼容性声明都该 docker run 一次再说
7. **实战观察期理念一致**：实战观察期是"用真实痛点驱动修复"。Linux smoke test 找到的 38 断言就是真实痛点（任何 Linux 用户首次 bash tests/run_all.sh 都会撞）；不是凭空预设 race fix 那种 YAGNI 风险

**反方观点（为完整性记录）**

C 的代价：工时 + 多发一个 patch 版本号 + 把"实战观察期"的状态打破（v2.1.1 刚 ship、v2.1.2 又紧接着）。但是：
- 工时实际花 ~2h，可接受
- 版本号是免费资源
- 实战观察期的本意是"不凭空发版"，不是"不发版"——找到真痛点就该发，否则观察期变拖延期

**结论**

选 C。落地（按时间顺序）：
1. Phase 1：诊断单一根因（mawk regex interval 不支持）
2. Phase 2：14 处 awk regex POSIX 化 + B7-a skip-on-root
3. Phase 3：macOS 24/24 ✅ + Ubuntu 22.04 容器 24/24 ✅ 双绿
4. Phase 4：v2.1.2 VERSION bump + README/HANDOFF 同步 + CHANGELOG + Gotcha #15 + Decision 0016
5. Phase 5：gitx-release v2.1.2 + audit 209/0/0 + commit + tag + push private Git host + /handoff Dev Log 0042

**关联**：Gotcha #15（mawk regex interval 限制 + 跨平台 awk 通用规则 + Linux deps 清单）；Dev Log 0042（v2.1.2 实施 + Ubuntu 22.04 真机验证）；Decision 0013（v2.2.0 race fix 推延保持有效，本周期只动 Linux compat）；HANDOFF.md "目标平台"行从"理论推断"升级"实测证据"
