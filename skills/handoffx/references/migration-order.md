# 固定升级顺序（多机 / 多 CLI 项目照此执行）

> 与仓库 `MIGRATION_GUIDE_v2.md`（完整发行包）§5.6 逐字一致（本文件随 skill 发布，安装后也能读到）；`handoffx-upgrade.sh` 的「后续人工步骤」清单指向本文件。

1. 停掉项目目录的同步（Syncthing / Dropbox / iCloud）——否则一边改名一边同步回来就是混合树，v4 拒绝处理。`handoffx-upgrade.sh` 从项目根往上找同步标记（`.stfolder`、`.dropbox` / `.dropbox.cache`、路径含 `/Library/Mobile Documents/`），找到就点名；`--apply` 时拒绝（exit 2、不写任何文件），暂停同步后加 `--sync-paused` 重跑。项目根经符号链接进入时，逻辑路径与真实路径的上级都会查。只认这几种标记——检测不到不等于没在同步，照样先暂停。建议把 `Handoffx_Logs/.lock.d` 与 `Handoffx_Logs/.lock` 加进 `.stignore`（单机取号锁：macOS 等无 `flock` 处用前者，Linux 写入用后者，升级在旧目录上两把都拿；不该同步到别的机器）。锁的保证范围：升级期间持有旧目录上的取号锁：阻止 v3 写入者**取号**，不保证整次写入互斥（取号锁在返回编号时即释放）；mkdir 分支下 `.lock.d` 会随目录复制进新目录、直到升级退出才删除，所以新目录在后置检查阶段对 mkdir 取号也是关的，对 flock 取号不关；迁移前必须先停止正在运行的 handoff 写入会话（§5.6 第 1–2 步）。
2. 所有机器、所有 CLI（Claude Code / Codex / OpenCode）先重装 v4 的 skill——留一个 v3 skill 它会继续往旧目录写。
3. `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>` 看清单（判定布局、将改什么、残留扫描）——先看再动，dry-run 不写任何文件。
4. `--apply`：原子迁移，失败自动回滚；旧四件套（v3）原地改名不留副本——git 工作树靠 git 回退，非 git 项目（如只靠 Syncthing 同步）脚本会先把四件套打包成项目根下的 `.handoffx-pre-upgrade-<时间>.tar.gz` 并逐项校验，备份建不成或校验不过就 exit 2、不迁移任何文件（`--no-backup` 显式跳过）；完成后自动跑 validate / postflight，并列出项目里其它文件仍引用旧名的位置——迁移器只管四件套本身，项目其它文件里的旧路径要靠这份清单找出来。清单按文件聚合（每文件一行：处数 + 首处，最多 50 个文件），完整清单写到项目根 `.handoffx-upgrade-residuals.txt`；备份件、同步冲突件、会话日志等噪音目录默认跳过，`HANDOFFX_SCAN_PRUNE="dirA dirB"` 可追加；大树可加 `--quick` 跳过残留扫描（之后用 `--scan-only` 补看——那时已是新布局，dry-run 只会说无需升级；`--scan-only` 任何布局都可跑，只读）。脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续——迁移本身已成功，回滚只会把要修的问题藏起来。exit 3 = 迁移器拒绝（如目标件已存在），未迁移任何文件：按输出处理后重跑。
5. 处理残留清单（README / CI / 脚本 / 配置里的旧路径），先删 `.handoffx-upgrade-residuals.txt`（残留清单，不该进提交），再 `git add -A && git commit`（git 会识别为 rename，历史不断）——改名与引用修正放进同一个提交，任何一个提交点上项目都自洽。
6. 若有发布链 / 公开镜像：检查其排除表或审计规则里写死的旧名——这些规则不在项目文档里，残留扫描能看到文件却看不懂规则意图，需要人判断。
7. 恢复同步——此时各机都是 v4 skill、项目是新布局，同步回来的只会是新名。

`/handoffx`、`/handoffx-recall`、`/handoffx-tidy`、`/handoffx-init` 发现旧布局时会先给出 dry-run 清单并询问，确认后执行第 3–4 步；第 1–2、5–7 步仍要人做。`handoffx-upgrade.sh` 本身不交互、不提交：唯一的 git 调用是只读的 `git rev-parse --is-inside-work-tree`（决定要不要打升级前备份）；按 `hx_legacy_layout_kind` 判定 v1 → `migrate-to-v2.sh`、旧四件套 → `tidy-handoff.sh schema-upgrade`，新旧并存或无法判定则拒绝（exit 2）且不写文件；已是新布局时 `--apply` 直接 exit 0。
