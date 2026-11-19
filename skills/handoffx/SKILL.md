---
name: handoffx
description: 记录项目交接或有界召回。正常写入只显示启动句与最终确认，不播报读文件、更新或检查进度；异常正常提醒。Use for /handoffx* commands, Dev Log / Decision / Gotcha and project recall.
---

🚀启动handoffX项目交接流程.

# HandoffX

启动时逐字提示「🚀启动handoffX项目交接流程.」一次；宿主已显示则不重复。执行中的异常、警告、阻断和必要确认应及时正常提醒，不受常规字数或单次回复限制，不必等到结束或用户要求详情；需要确认时暂停相应操作。不得泄露凭证，普通进度不输出。

启动提示与交接正文分开：`/handoffx` 的正常写入确认仍简短，**全部用户可见说明合计不超过200字**仅约束无异常的写入调用，最终确认原样转发 `handoff-runtime.sh finalize` 的≤120字输出。`/handoffx-recall` 默认保留项目方向、当前接手状态 + 最近6条有界摘要，完整保留当前待办；正文不受120/200字限制，不经过短确认门禁。末尾固定「从这里继续」（停点 → 下一步 → 当前TODO），之后不追加内容；采集预算与降级规则只见 recall 规范。必要提醒、异常详情及用户要求展开不受上述限制。不能控制宿主工具面板，不声称已隐藏。

读写前按命令规范执行context定位门禁；绑定失配立即停止。技能根就是当前 SKILL.md 所在目录；入口已给根时直接使用，不查找其他端安装、不递归列目录。路径失效则简短报错，禁止猜路径。只读命令对应的规范，不重复读取入口：

召回以准确接手、不偏离方向为目标。Project Overview唯一 `hx:continuity`（≤4096 UTF-8字节）是权威方向区，保存目标、成功标准、范围/非目标、约束与有效决策；recent保存阶段验收、停点/定位、改动、验证、阻塞与未知，pending为唯一当前TODO。缺失/冲突须报告，结构合法不代表语义齐全；不新增状态快照，recall不修文档。

## 触发与执行

| 命令 | 当前技能根内的规范 |
|---|---|
| `/handoffx` | `references/handoffx-write.md` |
| `/handoffx-recall [N]` | `references/handoffx-recall.md` |
| `/handoffx-init` | `references/handoffx-init.md` |
| `/handoffx-tidy` | `references/handoffx-tidy.md` |
| `/handoffx-memory` | `references/handoffx-memory.md` |

遵循 `references/layout-gate.md`：只有发现旧/混合布局时才读取升级细则；未确认不迁移。脚本一律通过 `bash` 调用当前技能根内的实际脚本，不 source lib。写入末尾独立调用 `handoff-runtime.sh finalize`（见 write 规范）。

硬约束：不读写 git；不保存明文凭证；交接记录时间只取 hx.sh now，事件执行时间只取原证据、缺失为unknown；Decision 只记录显式权衡；未知事实留未知，不编造验证或待办。recall 只读，默认6条；tidy不改语义。非交接的README/API写作和导出聊天不触发。
