# OrderFlow — Project Handoff

## 🚀 Quick Start

```bash
cd <project-root>
pnpm install
pnpm dev
```

## 📦 Project Overview

| 字段 | 值 |
|------|-----|
| 定位 | 电商订单中台，处理支付回调 + 发货编排 |
| 语言 / 栈 | TypeScript + NestJS + PostgreSQL + Redis |
| 目标平台 | AWS ECS |
| 当前版本 | v2.3.1 |
| 项目阶段 | Beta（双 11 前必须 GA） |
| 构建状态 | ⚠️ CI flaky，payment-webhook 集成测试间歇挂 |

### 🎯 Goals
- 取代旧 PHP 单体，新架构支撑 10x 流量
- 支付 / 库存 / 物流三方事件可追溯
- p99 延迟 < 200ms

### 🚫 Non-Goals
- 不做客服工单系统（那是 CRM 的事）
- 不做商品管理（那是 PIM 的事）

## 🏗 Architecture

```
orderflow/
├── apps/api/         # NestJS HTTP 入口
├── apps/worker/      # BullMQ 异步任务
├── libs/domain/      # 领域模型 + 聚合根
└── libs/infra/       # 数据库 / 缓存 / 外部 API
```

## 🔑 Coding Conventions

- 命名：PascalCase 类 / camelCase 函数 / kebab-case 文件
- 测试：Vitest + Testcontainers
- 提交：conventional commits

## 🎯 Current State

**最近改动区域**：`libs/infra/payment/`
**验证状态**：✅ 单测绿 / ⚠️ 集成测试 flaky

### 待办
- [ ] 修 payment-webhook flaky test（Gotcha #2）
- [ ] 给 refund 流加幂等 key
- [ ] 压测：10k rps 下的 Redis 热点

## 🐛 Known Gotchas

### Gotcha #1 — `[data]` PostgreSQL enum 迁移锁表
- **症状**：生产改 `order_status` enum 值会锁 `orders` 表 ~30s
- **方案**：用 check constraint 替代 enum，或分步 ADD VALUE

### Gotcha #2 — `[runtime]` payment-webhook flaky test
- **症状**：CI 约 15% 概率挂在 `expect(webhookReceived).toBe(true)`
- **根因**：Stripe mock 的 async 事件和 vitest 的 timer fake 冲突
- **方案**：暂未修，用 `--retry 3` 绕过

### Gotcha #3 — `[perf]` Redis pub/sub 连接泄漏
- **症状**：worker 跑 48h 后 Redis 连接数稳步增长
- **根因**：BullMQ 的 blocking connection 没在 worker close 时 quit
- **方案**：已修（2026-03-10 commit），但生产还没部署

## 🧭 Decision Log

### 2026-03-05 — 选 BullMQ 而非 Temporal
- **背景**：需要异步任务编排 + 重试 + 死信队列
- **选项**：A BullMQ / B Temporal / C 自己搭
- **选择**：A
- **拒绝 B**：Temporal 学习曲线陡，团队 3 人 hold 不住
- **拒绝 C**：不造轮子
- **反悔代价**：中（换引擎要改 worker 全部作业定义）

## 📜 Development Log

### 2026-04-15 14:22 — Redis pub/sub 连接泄漏修复

**触发**: 生产 Redis 连接数每 48h 稳步增长，已触发告警两次。

**改动**:
- `libs/infra/queue/bullmq-worker.ts:87` — worker close 时 await blockingConnection.quit()
- `tests/integration/worker-lifecycle.test.ts` — 新增 3 用例验证关闭路径

**验证**:
- 本地压测：跑 24h 连接数稳定在 12
- 预发环境：跑 6h 连接数平稳

**关联**: Gotcha #3

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
