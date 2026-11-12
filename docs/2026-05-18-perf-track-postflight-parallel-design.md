# 性能轨 Spec D — postflight 编排层并行化（设计）

> Status: DESIGN（待 Boss 批准 → writing-plans）
> 母决策来源: Decision 0019 §9（性能轨 backlog）；本设计**校正**其 factual error（见 §2）
> Scope owner: Boss 已批准方向（"我觉得可以了"，2026-05-18）

## 1. 目标

把 `/handoff` 写入 / `/handoff-tidy` 后置的 `handoff-postflight.sh` 墙钟从实测 7.4s
降到 **≈ max(单 check)**，不引入正确性回归，**零触碰刚 P1.2 硬化的 fail-closed linter 内部逻辑**。

成功判据用**相对**而非绝对硬门（避免自相矛盾）：墙钟 ≥50% 下降（7.4s → ≤3.7s）。
注：并行物理下限 = 最慢单 check。validate-handoff 真实成本未验证（隔离测试短路成假值），
plan 第一步须先实测它；若它本身 >3.7s，则它即 §6 延后的下一杠杆，本 Spec D 判据降级为
"墙钟 = max(单 check) 且较串行求和显著下降"，不强求绝对秒数。

## 2. 背景与 §9 前提校正（Why this, not what §9 said）

Decision 0019 §9 *断言*："postflight 慢 = scan-credentials 全树扫 22K 文件 → 收窄即可"。

实测推翻该前提（claim≠fact，本 session 反复母题）：

- `scan-credentials.sh:93-103` 与 `handoff-lint.sh:169-182` **本来就已限域**到四件套
  （HANDOFF.md + GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/），**无任何全树扫**。
  先前抛出的 22,557 是 `find . -type f`，两个脚本谁都不跑它。
- 真实成本逐项 profile（实测）：

  | sub-check | 实测墙钟 | 成本性质 |
  |---|---|---|
  | validate-handoff | ~3.2s* | per-file walker（*postflight 内跑全程；隔离测试短路成 0.004s 是假值） |
  | handoff-lint | 2.7s | 78 文件 × 每文件 ~15 grep/sed 子进程 ≈ 1,200 spawn |
  | scan-credentials | 1.3s | 78 文件 × 多 regex PATTERN 嵌套循环 |
  | archive-devlog | 0.2s | 可忽略；**会移动文件** |
  | rotation-reminder | 0.02s | 可忽略 |

- 结论：postflight 慢 = 5 个 per-file walker **串行求和**；且 lint/validate 各自随
  Dev Log 数线性增长（现 78 条，每 session +1，只会恶化）。
- 因此正确杠杆 = **并行编排**（墙钟自动 = max(单 check)，无需知道哪个最慢），
  而非"收窄 scan 范围"（已限域，无事可做）。

## 3. 方案权衡（Linus 三问 + 推荐）

| 方案 | 改动面 | 效果 | 风险 |
|---|---|---|---|
| 改 lint/scan 内部 awk 化 | 重写已硬化 fail-closed linter | lint 2.7→0.4 | **高**：P1.2 刚硬化（Gotcha #24 地盘），重写=回归风险，双源+多源审翻倍 |
| **并行编排（推荐）** | 仅 `handoff-postflight.sh` 编排层 ~10 行 | 7.4s→max≈**2.7-3s**（降 ~63%） | **低**：不碰 linter 内部；唯一敏感点=并行退出码聚合，小且可直接 TDD |
| 增量/缓存 lint | 引入 mtime/hash 缓存 | O(changed) | **高**：缓存失效=新静默面，与 fail-closed 门交互（stale cache 说 clean = Gotcha #24 母题） |

- **真问题?** 是——串行求和 + 两份线性增长叠加，每 session 恶化。
- **更简?** 是——~10 行编排吃掉 63% 收益，零碰刚硬化的门。深层 per-file 重写延到证明必要（YAGNI / blast radius 控制）。
- **破坏什么?** `archive-devlog` 移动文件，与只读 check 并行 = race → 设计上串行殿后规避。

**推荐：并行编排。** 最大墙钟收益/单位风险；高风险重写延后。

## 4. 架构

单文件改动 `scripts/handoff-postflight.sh` + 其双源副本 `skills/handoff/scripts/handoff-postflight.sh`
（byte-equal 强制，NOT DEV_ONLY）。5 个 sub-check 脚本**零改动**。

### 4.1 数据流

```
mktemp -d → $TMP                           # trap 清理，早退不留垃圾
for c in scan-credentials validate-handoff handoff-lint rotation-reminder:
    ( run_check "$c" ... > $TMP/$c.out 2>&1; echo $? > $TMP/$c.rc ) &   # 4 只读并行
wait                                        # 墙钟 = max(单 check)
run_check archive-devlog ... > $TMP/archive-devlog.out 2>&1            # 串行殿后（移动文件，规避 race）
echo $? > $TMP/archive-devlog.rc
# 固定顺序回放 out（解决并行输出交错；保住一行汇总 + --quiet 语义）
for c in scan-credentials validate-handoff handoff-lint rotation-reminder archive-devlog:
    cat $TMP/$c.out
# fail-closed 聚合
overall=0
for c in <全部 5 个>:
    [ ! -f $TMP/$c.rc ] && overall=1            # ★ rc 缺失（worker 半死）= 失败，不默认 pass
    [ "$(cat $TMP/$c.rc 2>/dev/null)" != 0 ] && overall=1
exit $overall
```

### 4.2 错误处理 / 不变式（★ Gotcha #24 母题）

- **fail-closed 聚合**：`exit 1` 当 **任一 rc≠0 _或_ 任一 rc 文件缺失**。
  worker 因任何原因没写出 rc（被 kill / 子 shell 崩 / 磁盘满）必须当失败，**绝不默认 pass**。
- 现有"任一 check 失败 → 整体 exit 1"语义并行后**逐字节等价**，不退化。
- `--quiet` 仅出一行汇总——回放顺序固定保证汇总判定与现状一致。

### 4.3 兼容性

- bash 3.2（macOS 默认）：纯 `wait`（不用 `wait -n`）+ rc 文件（不用关联数组）。
- `trap 'rm -rf "$TMP"' EXIT`：早退 / 失败 / 信号均清理。

## 5. 测试策略（TDD 强判据，subagent-driven 可独立 loop）

1. **墙钟**：真实 repo postflight 7.4s → **≤3.7s**（≥50% 下降；相对判据，见 §1）。先实测 validate-handoff 真实单值锚定上限。
2. **负控·任一失败**：注入一个必失败 check（如临时破坏 fixture frontmatter）→ 整体 **exit 1**（并行下 fail-closed 不退化）。
3. **负控·rc 缺失**：模拟 worker 不写 rc（patch run_check 跳过 echo）→ 整体 **exit 1**。
4. **race 顺序**：archive-devlog 不与任一只读 check 时间重叠（顺序断言 / 或 archive 触发归档移动时只读 check 已全 wait 完成）。
5. **输出等价**：`--quiet` 与 `--verbose` 输出与改动前**逐字节一致**（回放顺序固定）。
6. **双源 byte-equal**：根 scripts/ 与 skills/handoff/scripts/ 的 postflight `diff` 空。

## 6. 范围外（显式 YAGNI）

- per-file 子进程扇出深层重写（lint/scan awk 化）：延到并行后 max(单 check) 仍嫌慢再**单独 brainstorming**
  （不在 P1.2 刚硬化 fail-closed linter 后立刻翻它）。
- HANDOFF.md 瘦身 / recall 分层（Decision 0019 §9 另两条杠杆）：本 Spec D 不含。
- v2.2.0 flock：与本设计正交，仍推延。

## 7. 关联

- 母决策 Decision 0019 §9（本设计校正其 factual error，须回填 Outcome + 可能新开 Decision 记录"§9 前提被实测推翻"）
- Gotcha #24（fail-open 母题——并行退出码聚合不变式直接继承）
- 既有双源契约（test_scripts_sync.sh 强制 postflight byte-equal）
