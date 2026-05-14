---
schema: 2
type: dev-log
date: 2026-04-21T21:18
number: 0003
title: Release 模拟循环 Round 1：捕获并修复 Git_Release_Skill 2 个 bug
---

### 2026-04-21 21:18 — Release 模拟循环 Round 1：捕获并修复 Git_Release_Skill 2 个 bug

**触发**: 用户要求读取 `Git_Release_Skill`，对 Handoff 进行模拟 release，原子级回审，发现 bug 即修正，循环至连续两轮回审无问题。Round 1 执行目标版本 v0.9.3。

**改动**:
- `Git_Release_Skill/scripts/release.sh` — **Bug #1 修复**：CHANGELOG 平摊顺序错误
  - 步骤 2.6 的 for 循环中移除 `CHANGELOG.md`（原来拷贝根目录旧 CHANGELOG）
  - 新增步骤 5.1：在步骤 5（Release/CHANGELOG.md accumulate + gate）之后，单独将 `Release/CHANGELOG.md` 拷贝到 release 目录，确保平摊版本含新版本条目
- `Git_Release_Skill/scripts/release.sh` — **Bug #2 触发源**：步骤 5 增加 CHANGELOG gate（policy §4 #5 落地）
  - 若 `Release/CHANGELOG.md` 无当前版本条目 → 自动创建 TODO 脚手架并 `exit 1`，提示用户先填写
  - 若版本条目存在但含 `<!-- TODO` → `exit 1` 阻断，提示填写真实内容
  - 正确情形（条目存在且无 TODO）→ 继续执行
- `Git_Release_Skill/scripts/release-audit.sh` — **Bug #2 修复**：§3 CHANGELOG 对比源修正
  - 原逻辑对比平摊 CHANGELOG 与 `$PROJECT_ROOT/CHANGELOG.md`（根目录）—— 两者本就不同，必然 fail
  - 修改为对比平摊 CHANGELOG 与 `$PROJECT_ROOT/Release/CHANGELOG.md`（积累版），语义正确

**验证**:
- Round 1 首跑：`exit 1`，42 项中 2 项失败（§4 顶部版本号 / §4 本版本条目非空）
- Bug #1 修复 + CHANGELOG 填写真实内容后重跑：`exit 1`，1 项失败（§3 CHANGELOG 与根目录 diff）
- Bug #2 修复后第三次运行：**`🎉 Deep Audit PASS (42/42)`** ✅
- 走过的弯路：最初误以为只需移动 CHANGELOG 平摊顺序，但发现 audit §3 的对比源也是错的（根目录 vs 积累版），必须同时修两处

**关联**: `Git_Release_Skill/scripts/release.sh` + `release-audit.sh`；Handoff Release/v0.9.3 产物已就绪

**待办变动**:
- 🆕 新增：进行 Round 2 模拟 release（v0.9.4），验证修复是否完整，寻找新 bug

