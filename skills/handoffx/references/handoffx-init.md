# `/handoffx-init` — 最小初始化规范（v2 多文件布局）

启动时仅提示「🚀启动handoffX项目交接流程.」一次；宿主已显示则不重复。执行中的异常、警告、阻断和必要确认应及时正常提醒，不受常规字数或单次回复限制，不必等到结束或用户要求详情；需要确认时暂停相应操作。不得泄露凭证，正常进度不反复播报。

初始化不新增第二份状态快照，schema 2不变。已有主文件不自动加块或改写；无块旧Overview≤4096 UTF-8字节全文保留为legacy_unverified，超限非零且stdout为空，绝不整段延后。模板占位不是项目事实；缺失/冲突报告“未记录/待确认”，结构合法不代表语义齐全。改变目标或不可逆操作前确认，不从标题/TODO猜方向；当前有效关键信息不得仅在按需资料中。

## 目标

让首次使用者在 3 分钟内得到一份可接手的 v2 四件套布局起点：

```
<project root>/
├── HANDOFFX.md            (含 v2 marker + 完整章节骨架 + 三组空 pointer 块)
├── GOTCHAS.md             (空知识库骨架)
├── Handoffx_Logs/         (空目录，等 /handoffx 写入)
└── Handoffx_Decisions/    (空目录，等 /handoffx 写入决策)
```

## 行为

1. 先在用户/宿主明确指定的项目根执行 `bash <skill-path>/scripts/handoff-runtime.sh context --root "<项目绝对路径>" --skill-root "<技能绝对路径>"`；失败停止，不从父目录/Git根猜目标。然后检查项目根状态
   - 已有 `HANDOFFX.md`：不覆盖
     - 若含 `<!-- HANDOFF v2 schema -->` → 检查三件套：只补缺失目录和 GOTCHAS.md（使用模板），已有任何内容不覆盖；路径为符号链接或类型不符时拒绝并报告。完整布局才提示用 `/handoffx-recall`。
   - 不存在 `HANDOFFX.md`：若有旧版 `HANDOFF.md` 则停止，按文末「旧布局升级路径」分流；否则进入下一步
2. 运行 `bash <skill-path>/scripts/handoff-runtime.sh --expect-root "<已确认项目绝对路径>" init`，由工具补齐四件套骨架（**全部**写到项目根，不手工绕过根检查）：
   - `HANDOFFX.md` ← 来自 `<skill-path>/assets/HANDOFFX.template.md`
   - `GOTCHAS.md` ← 来自 `<skill-path>/assets/GOTCHAS.template.md`
   - `Handoffx_Logs/` ← `mkdir -p`（空目录）
   - `Handoffx_Decisions/` ← `mkdir -p`（空目录）
3. 回显最小填写清单：
   - Project Overview：在唯一 `<!-- hx:continuity -->` … `<!-- /hx:continuity -->` 块内填写总目标/受益者与问题、Goals、成功标准、范围/Non-Goals、关键技术/安全/兼容性约束与授权门控、有效决策及原因/出处；最多4096 UTF-8字节。它是权威方向区，不在其他章节重复同一可变事实，长背景才放块外按需读取
   - Current State：recent写阶段目标与阶段验收、停点与工作定位、未完成改动、既定下一步、验证命令/日期/范围、阻塞/依赖/风险与未知；项目约束引用continuity；pending完整保留当前未完成事项（含阻塞、暂缓、负责人、依赖及用户门控），是当前TODO唯一事实源
   - Build / Run / Test：最常用命令
   - Architecture：目录结构 / 关键模块（最少一段话）
   - 其他章节可选；首条 Gotcha 等踩到再写
4. 跑 `bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>`（v2 模式接受 dir 参数）
5. 执行 `bash <skill-path>/scripts/handoff-runtime.sh recall ""` 做有界召回预检（预算见 `handoffx-recall.md`）；失败如实报告部分状态，不全文补读、不自动整理或迁移。
6. 汇报创建结果与各项检查结果；写后预检不代表多文件事务或自动回滚

## 规则

- 不覆盖已有 `HANDOFFX.md`；旧版 `HANDOFF.md` 也不覆盖、不在旁边新建 `HANDOFFX.md`（走下文「旧布局升级路径」）
- 不自动追加 Dev Log（init 只创建空骨架，不写第一条 entry）
- 不读 git 状态
- 填不出写 `—`，不要编造
- 初始化只解决"有一个可信起点"，完整结构可之后用 `/handoffx-tidy` 扩展

## 输出模板

```
✅ 已创建 v2 布局：
   HANDOFFX.md          (v2 marker + 骨架)
   GOTCHAS.md          (空知识库)
   Handoffx_Logs/       (空)
   Handoffx_Decisions/  (空)

先填这 5 块即可：
1. Project Overview（唯一continuity：目标/受益者/问题、成功标准、范围/非目标、约束/授权门控、有效决策原因/出处）
2. Current State（recent：阶段目标/验收、定位/未完成改动、验证日期/范围、阻塞/未知；pending：完整TODO）
3. Build / Run / Test
4. Architecture（最少一段）
5. Coding Conventions（如果与默认不同）

写第一条 Dev Log → 跑 /handoffx
新坑 → 直接 append 到 GOTCHAS.md
显式权衡 → /handoffx 会同时写 Handoffx_Decisions/<NNNN>-<date>-<slug>.md

结构校验：✅ 通过 / ⚠️ <输出>
```

## 旧布局升级路径（不用 init，走检测与询问）

先执行 `<skill-path>/references/layout-gate.md` 的共享安全门；无旧布局时静默继续，不展示规则。

- 两者都没有 → 跑 `/handoffx-init`
- 多机 / 多 CLI 项目的固定升级顺序见 `references/migration-order.md`
