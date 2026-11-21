#!/usr/bin/env python3
"""Opt-in REAL handoff -> independent-session recall for codex/claude/opencode.

NOT run by run_all.sh. Normal runs use existing host authentication and may cost
money. --prepare-only installs fixtures and runs six local tests, but starts NO
model. Requires Python 3.9+, bash, git, and the selected host executables.

Example (output MUST be new and inside this checkout's wip/):
  python3 -B tests/manual_handoff_roundtrip.py --host codex --host claude \
    --host opencode --output wip/roundtrip/run-001

--source is the HandoffX installation source, NOT a fixture to copy. Installation
HOME/XDG/temp are isolated inside output ONLY for installation. Model processes
inherit the actual user HOME and authentication environment; Codex also loads the
existing user/provider configuration. The driver does not read credentials or
modify that configuration. Hosts may maintain global session/cache state. This
is NOT a clean-home, clean-config or OS-level containment test. Model-process
TMPDIR/TMP/TEMP/NODE_COMPILE_CACHE point to evidence/host-runtime-<phase>/,
outside the fixture but still under this checkout's wip/. That cache is measured
separately; ALL fixture files (including wip/) remain in the read-only check.
Claude/OpenCode recall is instruction/tool-policy constrained and checked by
snapshots; unchanged snapshots do not prove absence
of transient writes. No permission-bypass flags, commits, subagents or publishing.

Exit 0 means mechanical checks passed, NEVER semantic acceptance. Heuristics
and a human-review checklist are saved separately. Raw stdout/stderr are never
rewritten. No retry/repair of model output or failed saved state is performed.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import signal
import subprocess
import sys
import time
import traceback

ENTRY_SCOPE = "Prompt-directed installed project skill; not native slash registration/expansion acceptance."
CHECKOUT = Path(__file__).resolve().parents[1]
HOST_ROOTS = {"codex": ".agents", "claude": ".claude", "opencode": ".opencode"}
CLAUDE_RECALL_ARGV_LIMIT = 150 * 1024  # Full argv bytes, including NULs; never truncate rules.
TARGET = "TASK-FILTER"
RESIDUAL = {
    "TASK-OLD": "- [ ] [P1] TASK-OLD：补非法输入契约；负责人林；依赖用户提供坏样本；期限未定；来源合成日志0001。",
    "TASK-GATE": "- [ ] [P0] TASK-GATE：生产灰度；负责人吴；等待用户明确批准，当前未批准；批准前禁止部署；依赖TASK-OLD验收。",
    "TASK-LATER": "- [ ] [暂缓] TASK-LATER：增加导出；负责人陈；等灰度稳定且用户重新确认范围后再做；期限未定。",
}
CONTINUITY = """项目总目标：给离线值班人员提供可靠的任务筛选，避免漏任务和重复处理。
受益者与问题：值班人员网络不稳定，必须能离线查阅已有任务。
长期成功标准：开放项与完成项正确分离；保留输入顺序、重复ID与原对象，不修改输入。
范围与非目标：只做本地Python筛选，不做云同步、计费或采购。
关键约束：仅Python标准库，无网络依赖；不得记录令牌；部署必须另获用户明确批准。
有效决策与原因：Decision 0001选择列表筛选而非按ID建字典，因为重复ID可能代表独立事件，字典会丢数据；选择标准库而非外部依赖，因为现场可能离线安装。来源：Handoffx_Decisions/0001-2026-01-01-filter.md（合成场景，非真实历史）。
"""
BASE_CODE = '''"""Offline task filtering; a synthetic roundtrip fixture."""


def open_tasks(tasks):
    """Preserve ordering, duplicate IDs and objects without modifying input."""
    return [task for task in tasks if not task["done"]]
'''
FEATURE_CODE = '''

def completed_tasks(tasks):
    """Preserve ordering, duplicate IDs and objects without modifying input."""
    return [task for task in tasks if task["done"]]
'''
BASE_TESTS = '''import unittest
from taskboard import open_tasks


class OpenTaskTests(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(open_tasks([]), [])

    def test_mixed(self):
        rows = [{"id": "a", "done": False}, {"id": "b", "done": True}]
        self.assertEqual(open_tasks(rows), [rows[0]])

    def test_order_duplicates_no_mutation(self):
        rows = [{"id": "b", "done": False}, {"id": "a", "done": False},
                {"id": "b", "done": False}]
        before = [dict(row) for row in rows]
        result = open_tasks(rows)
        self.assertEqual(result, before)
        self.assertEqual(rows, before)
        self.assertTrue(all(a is b for a, b in zip(result, rows)))
'''
FEATURE_TESTS = '''

class CompletedTaskTests(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(completed_tasks([]), [])

    def test_mixed(self):
        rows = [{"id": "a", "done": False}, {"id": "b", "done": True}]
        self.assertEqual(completed_tasks(rows), [rows[1]])

    def test_order_duplicates_no_mutation(self):
        rows = [{"id": "b", "done": True}, {"id": "a", "done": True},
                {"id": "b", "done": True}]
        before = [dict(row) for row in rows]
        result = completed_tasks(rows)
        self.assertEqual(result, before)
        self.assertEqual(rows, before)
        self.assertTrue(all(a is b for a, b in zip(result, rows)))
'''
# Intentionally never obtains a clock or uses TextTestRunner's timed summary.
# This is the runner's original output, NOT sanitized/edited unittest output.
TEST_RUNNER = '''import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path.cwd()))

class Result(unittest.TestResult):
    def __init__(self):
        super().__init__()
        self.passed = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.passed.append(test.id())

suite = unittest.defaultTestLoader.discover("tests")
result = Result()
suite.run(result)
report = {"runner": "unittest.TestResult (no timing)",
          "tests_run": result.testsRun, "passed": result.passed,
          "failures": [(t.id(), text) for t, text in result.failures],
          "errors": [(t.id(), text) for t, text in result.errors],
          "skipped": [(t.id(), why) for t, why in result.skipped],
          "successful": result.wasSuccessful()}
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(0 if result.wasSuccessful() and result.testsRun == 6
         and len(result.passed) == 6 else 1)
'''
REVIEW = """# Human review REQUIRED — exit 0 is not a semantic pass

Snapshot scope: ALL project descendants, including wip/, dotfiles, .git/ and
host-created .serena/; no .gitignore, graph-index or directory exclusions apply.
File bytes/hash/mode/mtime and directory/link metadata are recorded. Symlinks are
recorded without following their targets. atime is deliberately ignored. The
sibling evidence/ and installer-home/ are outside the recall project snapshot
(installer-home has its own snapshot); other global host state is not monitored.
For MODEL HOST processes only, TMPDIR/TMP/TEMP/NODE_COMPILE_CACHE are directed to
sibling evidence/host-runtime-<phase>/, still under this checkout's wip/. Exact
values are recorded in <phase>-host-runtime-environment.json and phase status.
Cache before/after manifests and changed paths are separate from fixture checks;
raw cache files are retained there. They are observations of the host-runtime
area, NOT proof that the model/skill could not write there. The host environment
may also be inherited by its child tools. Model instructions still require its
own temporary files in fixture/wip/tmp. No fixture/wip or .serena exclusions,
extra sandbox writable roots, permission bypass or auth/config changes are made.
Installers, driver tests and validators keep their existing environment policy.
Only the INSTALLER uses isolated HOME/XDG. Model processes inherit actual user
HOME/authentication; Codex retains user/provider configuration. This is NOT
clean-home or clean-config isolation. The driver does not inspect credentials
or modify user configuration; CLI sandbox/approval restrictions still apply.
Transient writes/deletes between snapshots cannot be ruled out. Native host
artifacts are retained, never silently cleaned up or excluded from differences.

Entry scope: prompt-directed installed project skill, NOT native slash-command
registration or expansion acceptance. Write-only display preference is explicit
user input; no fixed success text or recalled TODO answers are supplied.

Read each host's *raw* write/recall.stdout.jsonl and stderr, visible-text.json,
visible.md, tool-events.jsonl, session observations, and saved project snapshots.
Extracted text is a convenience view, not a substitute for the raw stream.
Required-stage and presentation reports use passed/failed/unknown; unknown never
turns the mechanical verdict green. Unsupported shell constructs need manual
review, not a permission change. A set-e/AND-chain proof is an inference, never
per-subcommand native exit telemetry. Exceptions to quiet/length rules remain
visible and require review; keywords alone neither exempt nor condemn them.
Native host usage fields are retained verbatim with event scope; overlapping
meters are not summed. Missing usage is unknown. Collector/file/transport bytes
are never reported as session tokens.

- Verify actual local skill/runtime execution, not merely claims or copied text.
  Follow the installed current SKILL.md/references; no assumed future guard API.
  Confirm no subagents, git commands, network/deploy/publish, tests or TODO execution
  by models; all development/test execution belongs to the driver before handoff.
- Write must append exactly one new real log; old eight SYNTHETIC logs stay intact.
  Goal/constraints/reasons remain unchanged. FILTER is done, all three residual
  tasks retain their priority/owner/dependency/deferred state and approval gate.
- Review new log AND recent AND recall for attribution: six tests really ran in
  the driver; model must not claim its own verification. Actual test execution
  date/time/duration was NOT supplied. File mtime, handoff time, session start,
  driver wall clock and synthetic log dates are NOT evidence of test-run time.
  Both recent and the new log must contain performed_at: unknown, sourced as
  runner_report, with not_provided time basis/evidence; format is not truth.
- Recall must use the new log in a genuinely different observed session, remain
  read-only, and preserve old TASK-OLD despite its origin lying outside last six.
- Check beneficiary/problem, long-term success criteria, scope/non-goals,
  constraints, both explicit decision REASONS and source; not just decision names.
- Check stage/acceptance, concrete stop point/files/uncommitted work, validation
  command/evidence/scope/unknown time, blockers/risks/unknowns, handoff timestamp
  vs execution time, actual bounded reading scope and semantic coverage gaps.
- The final handover tail is stop point -> complete current TODO -> next step;
  nothing follows it. Completed FILTER is not TODO. No fabricated next actions.
- For NORMAL successful write, count ALL visible commentary + final text (not
  only the final sentence), <=200 Unicode characters. Final confirmation <=120.
  write-final.txt and status.actual_final retain the actual final text;
  write-reply-consistency.json must match it to proven reply/finalize output.
  A short runtime-checked reply followed by an expanded final is not success.
  finalize can prove regen/recall/postflight/reply only through a strict native
  successful invocation; context remains separate. Printed markers are not proof.
  wrong-project-check.json is a DRIVER negative in project/wip/tmp/.../sibling,
  never a parent-directory cd or a host external_directory permission grant.
  system.permission_denied/string messages and tool_result.is_error are retained
  in native_errors/host_messages, even if the final result envelope says success.
  A permission-blocked recall is incomplete HOST evidence, not a product failure.
  An overall shell/tool exit 1 remains a native error even when its stdout says
  earlier subcommands returned 0; never normalize the outer failure to success.
  Codex command_execution with nonzero exit_code is an error even when its
  status is completed. Zero exits alone do not prove recall actually ran.
  Early write errors remain failures, but a clean host exit + valid saved state
  may admit session 2 with recall_from_write_with_errors=true. This is an
  independent test, not repaired state or an upgraded write/overall verdict.
  Errors/warnings/necessary confirmation are exempt, but require human assessment;
  the counter cannot decide this exemption. Never auto-trim/rewrite an answer.
- Inspect native host errors even when the process returns 0. Missing session IDs
  or unknown event shapes mean evidence is incomplete, NOT a presumed pass.

Machine keyword/heading heuristics can have false positives/negatives. They do
not certify meaning, safety, execution, or complete visibility. No automatic
repair or model-answer templates are used. A reviewer must record the verdict.
"""


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def snapshot(root, copy_to=None):
    """ALL descendants, including wip/dotfiles; no ignores, no symlink following."""
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            key = path.relative_to(root).as_posix()
            st = path.lstat()
            row = {"mode": st.st_mode, "mtime_ns": st.st_mtime_ns}
            if path.is_symlink():
                row.update(kind="symlink", target=os.readlink(path))
            elif path.is_dir():
                row.update(kind="directory")
            elif path.is_file():
                data = path.read_bytes()
                row.update(kind="file", sha256=hashlib.sha256(data).hexdigest(), size=len(data))
                if copy_to is not None:
                    dest = copy_to / key
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(data)
            else:
                row.update(kind="special")
            result[key] = row
    return result


def checkpoint(project, evidence, label):
    manifest = snapshot(project, evidence / "snapshots" / label)
    save(evidence / (label + "-manifest.json"), manifest)
    return manifest


def changed(before, after):
    return sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))


def block(text, name):
    matches = re.findall(r"<!-- hx:" + re.escape(name) + r" -->(.*?)<!-- /hx:"
                         + re.escape(name) + r" -->", text, re.S)
    return matches[0] if len(matches) == 1 else None


def environment(project, home=None):
    env = dict(os.environ)
    # An inherited git worktree/index override must not defeat the fixture root.
    for key in list(env):
        if key.startswith("GIT_"):
            del env[key]
    temp = project / "wip/tmp"
    temp.mkdir(parents=True, exist_ok=True)
    env.update(PWD=str(project), TMPDIR=str(temp), TMP=str(temp), TEMP=str(temp),
               PYTHONDONTWRITEBYTECODE="1", PYTHONPYCACHEPREFIX=str(temp / "pycache"))
    if home is not None:
        home.mkdir(parents=True, exist_ok=True)
        env["HOME"] = str(home)
        for key, suffix in (("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
                            ("XDG_DATA_HOME", "data"), ("XDG_STATE_HOME", "state"),
                            ("CODEX_HOME", "codex"), ("CLAUDE_CONFIG_DIR", "claude")):
            env[key] = str(home / suffix)
    return env


def execute(command, project, evidence, label, timeout, env=None, clock=True):
    """Original bytes go straight to disk, including partial output on timeout."""
    metadata = {"command": command, "cwd": str(project), "PWD": str(project),
                "exit_code": None, "timeout": False}
    start = time.monotonic() if clock else None
    try:
        with (evidence / (label + ".stdout.jsonl")).open("wb") as out, \
                (evidence / (label + ".stderr")).open("wb") as err:
            proc = subprocess.Popen(command, cwd=project, env=env or environment(project),
                                    stdout=out, stderr=err, stdin=subprocess.DEVNULL,
                                    start_new_session=True)
            metadata["pid"] = proc.pid
            save(evidence / (label + "-process.json"), metadata)
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                metadata["timeout"] = True
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    proc.wait()
            metadata["exit_code"] = proc.returncode
    except OSError as exc:
        metadata["launch_error"] = repr(exc)
    if clock:
        metadata["process_wall_seconds"] = round(time.monotonic() - start, 3)
        metadata["timing_scope"] = "this process only; NOT development test execution time"
    save(evidence / (label + "-status.json"), metadata)
    return metadata


def succeeded(status):
    return status.get("exit_code") == 0 and not status.get("timeout") and not status.get("launch_error")


def seed(project):
    project.mkdir(parents=True)
    (project / "Handoffx_Logs").mkdir()
    (project / "Handoffx_Decisions").mkdir()
    main = """<!-- HANDOFF v2 schema -->
# Taskboard — Project Handoff (SYNTHETIC TEST FIXTURE)
## Project Overview
<!-- hx:continuity -->
""" + CONTINUITY + """<!-- /hx:continuity -->
## Architecture
纯Python taskboard.py，tests/test_taskboard.py负责本地契约测试。
## Coding Conventions
任务状态只看done字段；实现约束见continuity。
## Current State
<!-- hx:recent -->
阶段目标：完成TASK-FILTER的completed_tasks函数及六项回归测试。
阶段验收：空列表、混合状态、顺序/重复ID/不修改输入均通过；当前尚未完成。
上次停点：仅有open_tasks和三项测试，completed_tasks尚未实现。
工作定位：当前项目taskboard.py与tests/test_taskboard.py；这是合成记录，不代表真实历史验证。
下一步：先完成TASK-FILTER，再处理TASK-OLD；后者依赖坏样本。
验证：合成历史不构成实测证据；运行时间、覆盖率、生产状态未知。
<!-- /hx:recent -->
<!-- hx:done -->
<!-- /hx:done -->
<!-- hx:pending -->
- [ ] [P1] TASK-FILTER：实现completed_tasks并补三项测试；负责人测试驱动；当前待完成。
""" + "\n".join(RESIDUAL.values()) + """
<!-- /hx:pending -->
## Known Gotchas
共 0 条；最新：(none)
## Open Questions / Mysteries
坏样本尚未提供，具体非法输入契约待确认。
## Reader Notes
八条旧日志全部为合成测试资料，不是宿主曾经执行的证据。
## Decision Log
共 1 条；最新：`0001-2026-01-01-filter.md`
## Build / Run / Test
python3 -B wip/tmp/run_tests.py
## Testing
纯本地单元测试；覆盖率、生产验证未知。
## Development Log
最近一条：0008-synthetic.md
最早一条：0001-synthetic.md
共 8 条
"""
    put(project / "HANDOFFX.md", main)
    put(project / "GOTCHAS.md", "# Known Gotchas\n\n暂无已确认Gotcha；合成场景不虚构真实事故。\n")
    put(project / "Handoffx_Decisions/0001-2026-01-01-filter.md", """---
schema: 2
type: decision
date: 2026-01-01
number: 0001
title: 合成决策：保留列表与标准库
---
### 2026-01-01 — 合成决策（非真实历史）
- **背景**: 离线安装，重复ID可能是独立事件。
- **选项**: 列表/按ID字典；标准库/外部依赖。
- **选择**: 列表和标准库。
- **拒绝其他方案的原因**: 字典会丢重复ID数据；外部依赖不能保证离线安装。
- **反悔代价**: 中。
""")
    now = dt.datetime.now(dt.timezone.utc)
    year_start = int(now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0).timestamp())
    # Keep all eight synthetic logs in this year so postflight cannot archive
    # the fixture across New Year; equal synthetic epochs are fine, IDs differ.
    anchor = max(year_start, int(now.timestamp()) - 3 * 86400)
    for n in range(1, 9):
        epoch = max(year_start, anchor - (8 - n) * 86400)
        stamp = dt.datetime.fromtimestamp(epoch, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M")
        detail = ("提出TASK-OLD，等待用户坏样本，尚未完成。" if n == 1 else
                  "整理open_tasks的需求样例，completed_tasks尚未实现；本条不是测试执行记录。")
        filename = f"{n:04d}-{stamp.replace(':', '')}-synthetic.md"
        main = main.replace(f"{n:04d}-synthetic.md", filename)
        put(project / "Handoffx_Logs" / filename, f"""---
schema: 2
type: dev-log
number: {n:04d}
date: {stamp}
epoch: {epoch}
title: SYNTHETIC 合成历史 {n}
---
### {stamp} UTC — SYNTHETIC 合成历史 {n}
<!-- hx:recall -->
- 合成测试资料：{detail}
- 验证：未执行；这些日期仅为构造历史，不是实际运行时间。
<!-- /hx:recall -->
**触发**: 构造隔离测试的历史窗口。
**改动**: 合成描述，未执行开发。
**验证**: 无真实验证，不可归因给模型或当前用户。
**关联**: 无。
""")
    put(project / "HANDOFFX.md", main)
    put(project / "taskboard.py", BASE_CODE)
    put(project / "tests/test_taskboard.py", BASE_TESTS)
    put(project / "wip/tmp/run_tests.py", TEST_RUNNER)
    return main


def permissions(project, phase):
    # Test behavior permissions only; never configure MCP/Serena/language servers.
    # If a host creates .serena by itself, retain and report it without cleanup.
    # Host policy is explicit; raw tool events and snapshot audits remain required.
    # loop002 denied a double-quoted runtime path (loop001 used unquoted).
    # Share equivalent spellings with Claude, scoped to this host's skill root;
    # do NOT allow arbitrary scripts or write subcommands during recall.
    shell = {"*": "deny"}
    shell.update({pattern: "allow" for pattern in (
        wrong_root_permission_patterns(project) if phase == "wrong-root" else
        readonly_shell_patterns(project, "opencode"))})
    config = {"permission": {"*": "deny", "external_directory": "deny",
                              "read": "allow", "glob": "allow",
                              "grep": "allow", "list": "allow", "skill": "allow",
                              # Local OpenCode 2.3.0 uses shell (observed in the
                              # prior real host-smoke JSONL); upstream uses bash.
                              "shell": "allow" if phase == "write" else shell,
                              "bash": "allow" if phase == "write" else shell,
                              "edit": "allow" if phase == "write" else "deny",
                              "write": "allow" if phase == "write" else "deny",
                              "task": "deny", "subagent": "deny", "agent": "deny",
                              "external_directory": "deny", "webfetch": "deny",
                              "websearch": "deny"}}
    save(project / "opencode.json", config)


def prompts(project, host):
    skill = project / HOST_ROOTS[host] / "skills/handoffx"
    boundary = (f"仅使用本项目技能 {skill}/SKILL.md 及其中指向的本次操作规范和脚本，"
                f"以磁盘当前规范为准。项目根是 {project}，cwd与PWD都必须在此；"
                "不读父目录/全局技能，不读写git，不联网/部署/发布，不调用子代理，"
                "不执行TODO或测试；你创建的计划、日志、临时草稿只放模拟项目wip/tmp；"
                "产品脚本的原子临时文件按其既有契约创建/清理（整个实例已处于用户项目wip内）。"
                f"不得越出真正用户项目wip边界 {CHECKOUT / 'wip'}；"
                "这不是放宽写入范围或忽略文件改动，驱动仍比较整个模拟项目的文件快照。")
    facts = ("测试驱动刚刚实际完成本场景TASK-FILTER：在taskboard.py新增completed_tasks，"
             "保留顺序/重复ID/原对象且不修改输入；在tests/test_taskboard.py增加三项测试。"
             "用户授权以本条驱动报告将TASK-FILTER标为完成，其他任务没有完成授权。"
             "驱动实际执行python3 -B wip/tmp/run_tests.py，六项测试通过，"
             "原始无计时证据在wip/logs/development-tests.json。"
             "真实测试执行时间（日期、时刻、耗时）未提供，禁止推测；"
             "不能从文件mtime、当前时间或交接记录时间推断。"
             "本次模型没有实测，应正确归因测试驱动报告，不得重跑。"
             "代码已保存但未提交；停点为筛选功能和测试完成，没有其他开发。"
             "下一步处理TASK-OLD，先等待用户坏样本；本轮不执行。"
             "总目标及有效决策未改变。请真实执行一次handoff写入，不是描述计划。")
    write = "$handoffx " if host == "codex" else "/handoffx "
    recall = "$handoffx-recall " if host == "codex" else "/handoffx-recall "
    # Separate the slash-command argument (empty) from harness/environment text.
    # Earlier runs treated the whole boundary paragraph as RAW, then the exact
    # read-only allowlist rejected it. Give the granted invocations, not answers:
    # no project facts, TODOs, expected output wording or previous session ID.
    runtime = shlex.quote(str(skill / "scripts/handoff-runtime.sh"))
    context_command = (f"bash {runtime} context --root {shlex.quote(str(project))} "
                       f"--skill-root {shlex.quote(str(skill))}")
    recall_command = f'bash {runtime} recall ""'
    host_policy = ("\n\n以下是测试环境说明，不是命令参数；本次recall命令参数为空。" + boundary +
                   "宿主只读白名单已授权下面两条原样调用；不要另加变量、pwd/cd前缀、echo或组合shell命令。"
                   "先读取本项目规范，然后依次执行。这里只限定已授权的工具调用，不提供或规定召回内容：\n" +
                   context_command + "\n" + recall_command +
                   "\n请根据实际返回资料，按当前技能默认范围与格式完整汇报；没有资料不得编造。")
    write_preference = "正常写入不要播报进度；仅启动提示和完成确认，异常及时报告。"
    return (write + write_preference + boundary + facts +
            "写入前context使用下面的绝对路径原样调用，不使用shell变量：\n" + context_command,
            recall.rstrip() + host_policy)



def readonly_shell_patterns(project, host):
    """Only installed read-only entrypoints, with equivalent shell spellings.

    trust-loop-001/claude recall was HOST permission-blocked, not a product
    failure: raw line 12 used `pwd && bash ... context ...; echo "exit=$?"`,
    line 13 was system.permission_denied with a STRING message, and the model
    correctly stopped. Never bypass dontAsk or grant blanket Bash to fix this.
    loop002/opencode similarly denied a double-quoted script path. This helper
    emits raw command patterns shared by both hosts, replacing only the skill
    root. Patterns are host permission policy, not an independent shell sandbox.
    """
    def spellings(value):
        value = str(value)
        double = '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`") + '"'
        single = "'" + value.replace("'", "'\"'\"'") + "'"
        return list(dict.fromkeys((shlex.quote(value), double, single)))

    relative = Path(HOST_ROOTS[host]) / "skills/handoffx/scripts"
    scripts = project / relative
    leaves = []
    for path in (scripts / "handoff-runtime.sh", relative / "handoff-runtime.sh"):
        for spelling in spellings(path):
            # Exact default recall forms: no wildcard accepting an extra shell
            # command, another target, or a write operation as a suffix.
            leaves.extend(f"bash {spelling} {operation}" for operation in
                          ("context", "recall", 'recall ""', "recall ''"))
            for root, skill in zip(spellings(project), spellings(scripts.parent)):
                leaves.append(f"bash {spelling} context --root {root} --skill-root {skill}")
    for path in (scripts / "hx.sh", relative / "hx.sh"):
        for spelling in spellings(path):
            leaves.extend((f"bash {spelling} now", f"bash {spelling} now --epoch"))
    # Separate safe components also support hosts that check compound commands
    # component-by-component. No cat/find/full-history fallback is authorized.
    # One canonical cd spelling, NOT cd styles x pwd/echo forms x every leaf.
    # shlex.quote keeps this valid when the project path needs shell quoting.
    cd = f"cd {shlex.quote(str(project))}"
    allowed = ["pwd", 'echo "exit=$?"', cd]
    for leaf in leaves:
        allowed.extend((leaf, f"pwd && {leaf}", f'{leaf}; echo "exit=$?"',
                        f'pwd && {leaf}; echo "exit=$?"', f"{cd} && {leaf}"))
    # Exact observed Claude loop001 wire shape: host prepends canonical cwd to
    # pwd + context with double-quoted root/skill + exit-status echo. Keep script
    # quote variants, but do not multiply every wrapper across every command.
    root = spellings(project)[1]
    skill = spellings(scripts.parent)[1]
    for path in (scripts / "handoff-runtime.sh", relative / "handoff-runtime.sh"):
        for spelling in spellings(path):
            leaf = f"bash {spelling} context --root {root} --skill-root {skill}"
            allowed.append(f'{cd} && pwd && {leaf}; echo "exit=$?"')
    return list(dict.fromkeys(allowed))



def claude_recall_bash_rules(project):
    return [f"Bash({command})" for command in readonly_shell_patterns(project, "claude")]


def wrong_project_directory(project):
    return project / "wip/tmp/iteration-closeout-wrong-project/sibling"


def wrong_root_command(project, host):
    runtime = project / HOST_ROOTS[host] / "skills/handoffx/scripts/handoff-runtime.sh"
    command = "/bin/pwd -P; " + shlex.join(["bash", str(runtime), "--expect-root", str(project), "context"])
    # Claude Bash has no workdir field. Set its effective runtime cwd explicitly
    # inside the already allowed project, not by entering the external parent.
    if host == "claude":
        command = "cd " + shlex.quote(str(wrong_project_directory(project))) + " && " + command
    return command


def wrong_root_permission_patterns(project):
    """Only the already requested readonly combination and its exact children.

    Some hosts authorize compound commands per child. This grants no wildcard
    bash/cd, write operation or external_directory access.
    """
    command = wrong_root_command(project, "opencode")
    return [command] + [shlex.join(segment) for segment in shell_segments(command)[0]]


def wrong_root_prompt(project, host):
    wrong = wrong_project_directory(project)
    return ("这是独立的 wrong-root 负测，不是正常交接。禁止修改任何文件、切换回项目根、重试修复、"
            "调用子代理或改变权限。真实项目根为 " + str(project) + "。只执行一次下面原样 shell 命令；"
            "Codex/OpenCode 必须将工具的 workdir 显式设置为 " + str(wrong) + "；"
            "Claude 使用命令内已有的 cd 子目录前缀。目录已由驱动创建且处于允许的项目内部，"
            "不要进入项目父目录或申请 external_directory 权限。保留原始 cwd 和失败输出，"
            "如果工具自动选回项目根或不支持指定该目录，停止并如实报告不能完成，不能算通过。\n" +
            wrong_root_command(project, host))


ENTRY_WRAPPER = "以下为当前项目安装的主技能入口全文（headless注入；不代表原生slash注册）。\n"


def expand_entry(prompt, entry, content):
    """Inject the same single-read bytes as recorded, without extra behavior hints."""
    return (ENTRY_WRAPPER + f"<installed-skill path={json.dumps(str(entry), ensure_ascii=False)}>\n" +
            content + "\n</installed-skill>\n\n用户本次调用：\n" + prompt)


def commands(host, project, evidence, model, entry_mode="path"):
    write, recall = prompts(project, host)
    if entry_mode == "expanded":
        entry = project / HOST_ROOTS[host] / "skills/handoffx/SKILL.md"
        data = entry.read_bytes()
        (evidence / "expanded-entry.md").write_bytes(data)
        content = data.decode("utf-8")
        write, recall = (expand_entry(p, entry, content) for p in (write, recall))
        save(evidence / "expanded-entry.json", {"path": str(entry), "sha256": hashlib.sha256(data).hexdigest(),
             "method": "single read; exact installed main SKILL.md bytes decoded as UTF-8 including frontmatter; no newline conversion",
             "wrapper": ENTRY_WRAPPER, "wrapper_sha256": hashlib.sha256(ENTRY_WRAPPER.encode()).hexdigest(),
             "prompt_sha256": {"write": hashlib.sha256(write.encode()).hexdigest(), "recall": hashlib.sha256(recall.encode()).hexdigest()},
             "scope": "headless main skill injection with recorded descriptive wrapper, not native slash registration/alias expansion"})
    wrong_root = wrong_root_prompt(project, host)
    for phase, text in (("write", write), ("recall", recall), ("wrong-root", wrong_root)):
        put(evidence / (phase + "-prompt.txt"), text)
    exe = shutil.which(host)
    if not exe:
        raise RuntimeError(f"Selected host executable is absent: {host}")
    if host == "codex":
        # Keep the real user/provider config: ignoring it can drop provider auth.
        # This is not clean-config isolation; sandbox/approval restrictions remain.
        common = [exe, "--ask-for-approval", "never", "exec",
                  "--disable", "multi_agent", "--ephemeral", "--json", "--cd", str(project)]
        return {phase: common + ["--sandbox", "workspace-write" if phase == "write" else "read-only",
                                 "-o", str(evidence / (phase + "-native-final.txt")), prompt]
                for phase, prompt in (("write", write), ("recall", recall), ("wrong-root", wrong_root))}
    if host == "claude":
        common = [exe, "--bare", "-p",
                  "--no-session-persistence", "--output-format", "stream-json", "--verbose",
                  "--permission-mode", "dontAsk", "--disallowedTools", "Task,Agent"]
        recall_command = common + ["--tools", "Read,Bash,Skill", "--allowedTools", "Read", "Skill"] \
            + claude_recall_bash_rules(project) + ["--", recall]
        argv_bytes = sum(len(os.fsencode(arg)) + 1 for arg in recall_command)
        if argv_bytes > CLAUDE_RECALL_ARGV_LIMIT:
            raise RuntimeError(f"Claude recall argv is {argv_bytes} bytes; limit is "
                               f"{CLAUDE_RECALL_ARGV_LIMIT}. Use a shorter fresh --output path; "
                               "permissions are never truncated or widened to fit.")
        return {
            "write": common + ["--tools", "Read,Write,Edit,Bash,Skill", "--allowedTools",
                               "Read", "Write", "Edit", "Bash", "Skill", "--", write],
            "recall": recall_command,
            "wrong-root": common + ["--tools", "Bash", "--allowedTools",
                                     "Bash(" + wrong_root_command(project, host) + ")", "--", wrong_root],
        }

    common = [exe, "run", "--standalone", "--model", model, "--format", "json", "--archived"]
    return {"write": common + [write], "recall": common + [recall], "wrong-root": common + [wrong_root]}


def protect_commands(host, commands_by_phase, project, evidence):
    """Process-local restrictions; never edit the user's MCP configuration."""
    result = {phase: list(command) for phase, command in commands_by_phase.items()}
    policy = {"mode": "project-readonly", "host": host,
              "scope": "process-local launch policy; all project paths still measured; native approval/sandbox unchanged",
              "global_configuration_modified": False,
              "limitation": "Enforced project write prevention, not proof of zero write attempts; global host/cache state outside project remains outside claim"}
    if host == "codex":
        for phase, command in result.items():
            result[phase] = command[:1] + ["-c", "mcp_servers.serena.enabled=false"] + command[1:]
        policy["disabled_mcp"] = ["serena"]
        policy["reason"] = "MCP startup writes bypass Codex tool sandbox; this handoff skill needs native tools only"
    elif host == "opencode":
        executable = shutil.which("sandbox-exec")
        if not executable:
            raise RuntimeError("project-readonly OpenCode profile requires macOS sandbox-exec; no unprotected fallback")
        profile = '(version 1)(allow default)(deny file-write* (subpath (param "PROJECT")))'
        prefix = [executable, "-D", "PROJECT=" + str(project), "-p", profile]
        for phase in ("wrong-root", "recall"):
            result[phase] = prefix + result[phase]
        policy.update(readonly_prefix=prefix, protected_phases=["wrong-root", "recall"],
                      reason="Protect the whole standalone host and its children, including automatic MCP startup")
    else:
        policy["reason"] = "Existing Claude bare/native tool policy retained; no additional host override"
    save(evidence / "host-protection.json", policy)
    return result


def verify_readonly_protection(project, evidence, timeout):
    """A real denied-write control and an allowed-read control, before any model."""
    policy = json.loads((evidence / "host-protection.json").read_text())
    prefix = policy["readonly_prefix"]
    probe = project / "wip/tmp/host-readonly-probe"
    if probe.exists() or probe.is_symlink():
        raise RuntimeError("readonly probe already exists; refusing overwrite")
    before = checkpoint(project, evidence, "readonly-control-before")
    denied = execute(prefix + ["/bin/bash", "-c", 'printf forbidden > "$1"', "probe", str(probe)],
                     project, evidence, "readonly-denial-control", timeout)
    allowed = execute(prefix + ["/bin/cat", str(project / "HANDOFFX.md")],
                      project, evidence, "readonly-read-control", timeout)
    after = checkpoint(project, evidence, "readonly-control-after")
    diagnostic = (evidence / "readonly-denial-control.stderr").read_text()
    checks = {"write_denied": denied.get("exit_code") != 0 and not denied.get("timeout")
              and str(probe) in diagnostic and "Operation not permitted" in diagnostic,
              "read_allowed": succeeded(allowed), "zero_project_changes": not changed(before, after)}
    report = {"checks": checks, "passed": all(checks.values())}
    save(evidence / "readonly-protection-control.json", report)
    return report


def extract_events(raw, host):
    """Transport extraction only; retain native failures BEFORE parsing content."""
    texts, tools, ids, errors, unknown = [], [], [], [], []
    notices, denials = [], []
    parsed_events = []
    tool_event_lines = []
    denied_tool_ids = set()
    final = None
    last_assistant_variants = set()
    for number, line in enumerate(raw.splitlines(keepends=True), 1):
        try:
            event = json.loads(line)
        except (ValueError, UnicodeError):
            unknown.append(number)
            continue
        if not isinstance(event, dict):
            unknown.append(number)
            continue
        parsed_events.append((number, event))
        kind, subtype = event.get("type"), event.get("subtype")
        error_kinds = []
        denied = kind == "system" and subtype == "permission_denied"
        if denied:
            denials.append({"line": number, "event": event})
            error_kinds.append("host_permission_denied")
            if isinstance(event.get("tool_use_id"), str):
                denied_tool_ids.add(event["tool_use_id"])
        if kind in ("error", "turn.failed") or event.get("is_error") or event.get("error") or \
                (kind == "result" and str(subtype or "").startswith("error")):
            error_kinds.append("native_error")
        # Unexpected item/part types must not swallow a native failure event.
        item, part = event.get("item"), event.get("part")
        if item is not None and not isinstance(item, dict):
            unknown.append(number)
        if part is not None and not isinstance(part, dict):
            unknown.append(number)
        item = item if isinstance(item, dict) else {}
        part = part if isinstance(part, dict) else {}
        if host == "codex" and kind == "thread.started":
            if isinstance(event.get("thread_id"), str):
                ids.append({"line": number, "field": "thread_id", "id": event["thread_id"]})
        if host == "claude" and isinstance(event.get("session_id"), str):
            ids.append({"line": number, "field": "session_id", "id": event["session_id"]})
        if host == "opencode":
            for scope, obj in (("event", event), ("part", part)):
                for key in ("sessionID", "sessionId", "session_id"):
                    if isinstance(obj.get(key), str):
                        ids.append({"line": number, "field": scope + "." + key, "id": obj[key]})
        chunks = []
        tool = denied
        message = event.get("message")
        if isinstance(message, str):
            # In particular Claude system.permission_denied is NOT a Message
            # object. Preserve its exact text, separately from assistant prose.
            notices.append({"line": number, "event_type": kind, "subtype": subtype, "text": message})
        if host == "codex":
            if kind == "item.completed" and item.get("type") == "agent_message":
                chunks = [item.get("text", "")]
            tool = tool or bool(item) and item.get("type") not in ("agent_message", "reasoning", "error")
            if item.get("type") == "error":
                diagnostic = item.get("message")
                # Native startup configuration notices are diagnostics, not model tool calls.
                # Only this observed nonfatal envelope is recognized; arbitrary errors fail closed.
                config_notice = isinstance(diagnostic, str) and re.fullmatch(
                    r"Codex is ignoring [1-9][0-9]* unrecognized configuration settings?\. "
                    r"Check for typos or deprecated settings\.\n(?:  [^\n]+ is ignored\.\n?)+", diagnostic)
                notices.append({"line": number, "event_type": kind, "subtype": "configuration_notice" if config_notice else "native_item_error",
                                "text": diagnostic})
                if not config_notice:
                    error_kinds.append("native_item_error")
            if kind == "item.failed" or item.get("status") == "failed":
                error_kinds.append("native_tool_error")
            # Codex completed means the tool finished, not that its command
            # succeeded. Keep the WHOLE original nonzero-exit event, even if a
            # later turn/result or the host process itself reports success.
            if item.get("type") == "command_execution":
                exit_code = item.get("exit_code")
                if isinstance(exit_code, int) and not isinstance(exit_code, bool) and exit_code != 0:
                    error_kinds.append("native_command_exit_nonzero")
                if kind in ("item.completed", "item.failed"):
                    # An explicit native failure with a numeric nonzero exit is
                    # parseable failure, never success. Keep its error events;
                    # status=failed with zero/missing/bool/string exit is unknown.
                    known_terminal = type(exit_code) is int and (
                        item.get("status") == "completed" or
                        item.get("status") == "failed" and exit_code != 0)
                    if not known_terminal:
                        unknown.append(number)
                        error_kinds.append("native_command_terminal_unknown")
                elif kind not in ("item.started", "item.updated") or \
                        item.get("status") != "in_progress" or exit_code is not None:
                    unknown.append(number)
        elif host == "claude":
            content = message.get("content", []) if isinstance(message, dict) else []
            if isinstance(message, dict) and message.get("error"):
                error_kinds.append("native_message_error")
            if kind in ("assistant", "user") and message is not None and not isinstance(message, dict):
                unknown.append(number)
                if kind == "assistant" and isinstance(message, str):
                    chunks.append(message)  # Keep visible text despite an unfamiliar shape.
            if isinstance(content, str):
                if kind == "assistant":
                    chunks.append(content)
            elif isinstance(content, list):
                for c in content:
                    if not isinstance(c, dict):
                        unknown.append(number)
                        continue
                    if kind == "assistant" and c.get("type") == "text":
                        if isinstance(c.get("text"), str):
                            chunks.append(c["text"])
                        else:
                            unknown.append(number)
                    if c.get("type") in ("tool_use", "tool_result"):
                        tool = True
                    if c.get("type") == "tool_result" and c.get("is_error"):
                        tool_id = c.get("tool_use_id")
                        classification = ("host_permission_denied" if isinstance(tool_id, str)
                                          and tool_id in denied_tool_ids else "native_tool_error")
                        error_kinds.append(classification)
            else:
                unknown.append(number)
            if kind == "assistant" and chunks:
                last_assistant_variants = {"".join(chunks), "\n".join(chunks)}
            if kind == "result" and isinstance(event.get("result"), str):
                final = event["result"]
                # A terminal success envelope never erases earlier tool/host errors.
                if final and final not in last_assistant_variants and not any(t["text"] == final for t in texts) and \
                        final != "\n".join(t["text"] for t in texts):
                    chunks.append(final)
        elif host == "opencode":
            if kind == "text":
                chunks = [part.get("text", "")]
            tool = tool or kind in ("tool_use", "tool_result") or part.get("type") == "tool"
            state = part.get("state")
            if isinstance(state, dict) and state.get("status") == "error":
                error_kinds.append("native_tool_error")
        for text in chunks:
            if isinstance(text, str) and text:
                texts.append({"line": number, "event_type": kind, "text": text})
            elif not isinstance(text, str):
                unknown.append(number)
        if tool:
            tools.append(line)
            tool_event_lines.append(number)
        if error_kinds:
            errors.append({"line": number, "classifications": sorted(set(error_kinds)), "event": event})
    return {"texts": texts, "session_observations": ids, "errors": errors,
            "executions": execution_records(parsed_events, host),
            "tool_event_lines": tool_event_lines,
            "host_usage": usage_observations(parsed_events),
            "raw_stream_bytes": len(raw),
            "raw_stream_bytes_scope": "Transport bytes, NOT collector bytes or session tokens.",
            "host_messages": notices, "permission_denials": denials,
            "failure_boundary": ("HOST_PERMISSION_BLOCKED_NOT_PRODUCT_FAILURE" if denials else
                                 "NATIVE_ERRORS_REQUIRE_REVIEW" if errors else None),
            "non_json_or_malformed_lines": sorted(set(unknown)), "tool_lines": tools,
            "final": final if final is not None else (texts[-1]["text"] if texts else "")}




def usage_observations(events):
    """Keep native meters verbatim, without summing snapshots or guessing units."""
    observations = []
    for line, event in events:
        for prefix, obj in (("event", event), ("message", event.get("message")),
                            ("part", event.get("part"))):
            if not isinstance(obj, dict):
                continue
            for key in ("usage", "modelUsage", "model_usage", "tokens", "cost", "total_cost_usd"):
                if key in obj:
                    observations.append({"line": line, "event_type": event.get("type"),
                                         "field": prefix + "." + key, "value": obj[key]})
    return {"status": "observed" if observations else "unknown", "observations": observations,
            "scope": "Native host fields verbatim; event/message/part scopes may overlap. "
                     "No aggregation, unit conversion, or inferred session token total; "
                     "collector/file/transport bytes are not session tokens."}


def execution_records(events, host):
    """Normalize shell events only; prose and tool output never become commands."""
    records, pending = [], {}
    for line, event in events:
        kind = event.get("type")
        if host == "codex":
            item = event.get("item")
            if not isinstance(item, dict) or item.get("type") != "command_execution":
                continue
            if kind not in ("item.completed", "item.failed"):
                continue
            code = item.get("exit_code")
            outcome = ("passed" if kind == "item.completed" and item.get("status") == "completed"
                       and type(code) is int and code == 0 else
                       "failed" if type(code) is int and code != 0 else "unknown")
            records.append({"line": line, "id": item.get("id"), "command": item.get("command"),
                            "output": item.get("aggregated_output", ""), "outcome": outcome,
                            "exit_code": code, "basis": "native_command_exit"})
        elif host == "claude":
            message = event.get("message")
            content = message.get("content", []) if isinstance(message, dict) else []
            if not isinstance(content, list):
                continue
            for part in content:
                if not isinstance(part, dict):
                    continue
                if kind == "assistant" and part.get("type") == "tool_use" and part.get("name") == "Bash":
                    inp = part.get("input")
                    if isinstance(part.get("id"), str) and isinstance(inp, dict):
                        pending[part["id"]] = {"line": line, "id": part["id"],
                                               "command": inp.get("command"),
                                               "run_in_background": inp.get("run_in_background", False)}
                if kind != "user" or part.get("type") != "tool_result":
                    continue
                call = pending.pop(part.get("tool_use_id"), None)
                if call is None:
                    continue  # An unpaired result cannot prove a stage invocation.
                native_result = event.get("tool_use_result")
                native = native_result if isinstance(native_result, dict) else {}
                code = native.get("exit_code")
                failed = part.get("is_error") is True or native.get("interrupted") is True
                if type(code) is int and code != 0:
                    failed = True
                # A successful launch ACK is not completion. Keep this bounded
                # to native task-ID keys and the host's exact background prefix;
                # inspect content too, since native stdout can be empty/masked.
                result_texts = [native.get("stdout"), part.get("content"), native_result]
                content_parts = part.get("content")
                if isinstance(content_parts, list):
                    result_texts.extend(x.get("text") for x in content_parts if isinstance(x, dict))
                native_background = (any(key in native for key in ("backgroundTaskId", "background_task_id"))
                                     or any(isinstance(text, str) and
                                            text.startswith("Command running in background")
                                            for text in result_texts))
                background = call.get("run_in_background") is not False or native_background
                outcome = ("unknown" if background else
                           "failed" if failed else "passed" if part.get("is_error") is False else "unknown")
                # Claude commonly exposes tool success, not an actual numeric exit.
                output = native.get("stdout", part.get("content", ""))
                if isinstance(output, list):
                    output = "\n".join(x.get("text", "") for x in output
                                       if isinstance(x, dict) and isinstance(x.get("text"), str))
                records.append(dict(call, line=line, call_line=call["line"], output=output,
                                    outcome=outcome, exit_code=code, native_exit_present="exit_code" in native,
                                    background=background, stderr=native.get("stderr", ""),
                                    native_result_text=native_result if isinstance(native_result, str) else None,
                                    basis="paired_Bash_tool_result"))
        elif host == "opencode":
            part = event.get("part")
            if not isinstance(part, dict) or part.get("type") != "tool" or \
                    part.get("tool") not in ("shell", "bash"):
                continue
            state = part.get("state")
            if not isinstance(state, dict) or state.get("status") in ("pending", "running"):
                continue
            inp, meta = state.get("input"), state.get("metadata")
            meta = meta if isinstance(meta, dict) else {}
            nested = meta.get("metadata")
            native = nested if isinstance(nested, dict) else meta
            code = native.get("exit", native.get("exit_code"))
            outcome = ("failed" if state.get("status") == "error" or type(code) is int and code != 0
                       else "passed" if state.get("status") == "completed" and type(code) is int
                       and code == 0 else "unknown")
            records.append({"line": line, "id": part.get("id", part.get("callID")),
                            "command": inp.get("command") if isinstance(inp, dict) else None,
                            "output": state.get("output", ""), "exit_code": code,
                            "outcome": outcome, "basis": "native_shell_metadata"})
    records.extend(dict(call, output="", outcome="unknown", exit_code=None,
                        basis="unpaired_Bash_invocation") for call in pending.values())
    return records


def shell_segments(command):
    """A deliberately small shell subset, NOT a shell interpreter.

    Reject control flow, substitutions, functions, heredocs and pipelines.
    set -e does not certify individual command success across host wrappers.
    """
    if not isinstance(command, str):
        raise ValueError("missing command")
    # Unwrap the native Codex login-shell envelope, not arbitrary bash options.
    outer = shlex.split(command)
    if len(outer) == 3 and Path(outer[0]).name in ("bash", "zsh", "sh") and outer[1] in ("-c", "-lc"):
        if command != shlex.join(outer):
            raise ValueError("noncanonical shell envelope may expand before execution")
        command = outer[2]
    # Ignore only the two parameter forms supported by the proof grammar.
    # All glob/brace/tilde expansion is unsupported, even when quoted literally.
    expansion_free = re.sub(r"\$\{[A-Za-z_]\w*\}|\$\?", "", command)
    if any(char in expansion_free for char in "{}*?[]~"):
        raise ValueError("shell expansion syntax not proven")
    if re.search(r"\$\(|`|<<|\\\n", command):
        raise ValueError("substitution/heredoc/continuation not proven")
    # This is a deliberately small proof grammar, not a shell interpreter.
    # shlex comments differ from bash/zsh (including lost newline separators).
    # Reject all hashes, even quoted literals, rather than risk manufacturing
    # an execution or masking a failed stage behind the exit of a later command.
    if "#" in command:
        raise ValueError("comments/hash syntax not proven")
    # Preserve literal dollars/separators before shlex removes quoting. Otherwise
    # echo 'exit=$?' or echo ';' bash ... could masquerade as execution evidence.
    protected, quote, escaped = [], None, False
    for char in command:
        if escaped:
            protected.append("\ue000" if char == "$" else
                             chr(0xe100 + ord(char)) if char in ";&|()<>\n" else char)
            escaped = False
            continue
        if char == "\\" and quote != "'":
            protected.append(char)
            escaped = True
            continue
        if char in ("'", '"') and (quote is None or quote == char):
            quote = char if quote is None else None
        if quote and char in ";&|()<>\n":
            protected.append(chr(0xe100 + ord(char)))
        elif quote == "'" and char == "$":
            protected.append("\ue000")
        else:
            protected.append(char)
    lexer = shlex.shlex("".join(protected), posix=True, punctuation_chars=";&|()<>\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    tokens = list(lexer)
    segments, operators, current = [], [], []
    for token in tokens:
        if token in (";", "&&") or token and set(token) <= {"\n", ";"}:
            if current:
                segments.append(current)
                operators.append("&&" if token == "&&" else ";")
                current = []
        # Reject every other punctuation operator, including zsh disown and
        # combined stderr pipelines. shlex groups these into one token.
        elif token != ">" and token and set(token) <= set(";&|()<>\n"):
            raise ValueError("control flow/pipeline/redirection not proven")
        else:
            current.append(token)
    if current:
        segments.append(current)
    for segment in segments:
        if segment[0] == ">":
            raise ValueError("redirection-only command not proven")
        if segment[0] in ("if", "then", "else", "fi", "for", "while", "until", "case", "!", "{", "}",
                          "function", "eval", "exec", "source", ".", "trap", "exit", "return"):
            raise ValueError("shell control flow not proven")
    return segments, operators


def finalize_arguments(args, root):
    """Only the documented, literal project-bound finalize call is a proof.

    Latest-log selection, write safety and verification equality are enforced
    by the installed runtime, not guessed from stdout or a path's existence.
    """
    def relative_path(value):
        return bool(value) and not value.startswith(("/", "-")) and all(
            part not in ("", ".", "..") for part in value.split("/")) and not any(
                char.isspace() or ord(char) < 32 or 0xe000 <= ord(char) <= 0xe1ff
                or char in "$`\\,;|<>" for char in value)

    if not Path(root).is_absolute() or args[:3] != ["--expect-root", root, "finalize"]:
        return False
    options, log, files = args[3:], None, None
    while options:
        if options[0] == "--log" and len(options) >= 2 and log is None:
            log, options = options[1], options[2:]
        elif options[0].startswith("--files=") and files is None:
            files, options = options[0][len("--files="):], options[1:]
        else:
            return False
    if not log or not relative_path(log) or not re.fullmatch(r"Handoffx_Logs/[0-9]+-[^/]+\.md", log):
        return False
    return files is None or all(relative_path(value) for value in files.split(","))


def context_arguments(args, root, skill):
    """Prove only supported literal context options; no simulated shell state."""
    if not args or args[0] != "context":
        return False
    expected = {"--root": root, "--skill-root": skill}
    seen = set()
    rest = args[1:]
    if len(rest) % 2:
        return False
    for option, value in zip(rest[::2], rest[1::2]):
        if option not in expected or option in seen or value != expected[option]:
            return False
        seen.add(option)
    return True


def required_stage_evidence(records, host, project, phase):
    required = ("context", "regen", "recall", "postflight", "reply") if phase == "write" else ("context", "recall")
    stages = {name: {"status": "unknown", "evidence": []} for name in required}
    unsupported = []
    root = str(project)
    scripts = str(Path(HOST_ROOTS[host]) / "skills/handoffx/scripts")
    script_paths = {name: {scripts + "/" + name, "./" + scripts + "/" + name,
                           root + "/" + scripts + "/" + name}
                    for name in ("handoff-runtime.sh", "hx.sh", "handoff-postflight.sh")}
    for record in records:
        try:
            segments, operators = shell_segments(record["command"])
        except ValueError as exc:
            unsupported.append({"line": record["line"], "reason": str(exc)})
            continue
        # Only an unconditional && chain can propagate success backwards.
        # Host shell wrappers may suppress errexit; set -e is not native proof.
        # A later '; true' must never mask a stage.
        all_and = bool(segments) and all(op == "&&" for op in operators[:len(segments) - 1])
        trusted_prefix = True
        for index, raw_tokens in enumerate(segments):
            # Do not emulate shell state. Assignments (including IFS/ENV) and
            # variable expansion require native evidence, not string replacement.
            tokens = list(raw_tokens)
            if tokens == ["set", "-e"]:
                continue
            assignments = tokens[1:] if tokens[0] == "export" else tokens
            if assignments and all(re.fullmatch(r"[A-Za-z_]\w*=[^$`]*", t) for t in assignments):
                trusted_prefix = False
                continue
            redirected = ">" in tokens
            # Only stdout-to-/dev/null is supported, never input redirection.
            if ">" in tokens:
                if tokens[-2:] == [">", "/dev/null"] and tokens.count(">") == 1:
                    tokens = tokens[:-2]
                else:
                    trusted_prefix = False
            stage = None
            reply_text = None
            if len(tokens) >= 2 and tokens[0] == "bash":
                path, args = tokens[1], tokens[2:]
                original_args = list(args)
                # All three entrypoints accept --expect-root BEFORE their
                # subcommand/options; project-bound installs need no new grant.
                valid_root = not any("$" in arg or "\ue000" in arg for arg in args)
                if args[:1] == ["--expect-root"]:
                    valid_root = valid_root and len(args) >= 2 and args[1] == root
                    args = args[2:]
                valid_root = valid_root and "--expect-root" not in args
                if valid_root and path in script_paths["handoff-runtime.sh"]:
                    if phase == "write" and finalize_arguments(original_args, root):
                        stage = "finalize"
                    elif args and args[0] in ("context", "recall", "reply"):
                        stage = args[0]
                        if stage == "context" and not context_arguments(args, root, root + "/" + scripts.rsplit("/", 1)[0]):
                            stage = None
                        if len(args) == 3 and args[:2] == ["reply", "--text"]:
                            reply_text = args[2]
                elif valid_root and path in script_paths["hx.sh"] and args[:1] == ["regen"]:
                    stage = "regen"
                elif valid_root and path in script_paths["handoff-postflight.sh"] and all(
                        not any(char.isspace() for char in arg) and (
                            arg in ("--brief", "--quiet", "-q") or arg.startswith("--files=")
                            or arg == "HANDOFFX.md") for arg in args) and args.count("HANDOFFX.md") <= 1:
                    stage = "postflight"
            if stage in stages or stage == "finalize":
                outcome, basis = "unknown", "invocation seen; per-stage exit not proven"
                reporter_code = None
                if index + 1 < len(segments) and operators[index] == ";":
                    reporter = segments[index + 1]
                    label = None
                    if len(reporter) == 2 and reporter[0] == "echo":
                        match = re.fullmatch(r"([A-Za-z_]\w*)=\$\?", reporter[1])
                        label = match[1] if match else None
                    if len(reporter) == 3 and reporter[0] == "printf" and reporter[2] == "$?":
                        match = re.fullmatch(r"([A-Za-z_]\w*)=%[sd]\\n", reporter[1])
                        label = match[1] if match else None
                    if label and isinstance(record["output"], str):
                        codes = re.findall(r"(?m)^" + re.escape(label) + r"=(-?\d+)\r?$", record["output"])
                        if len(codes) == 1:
                            reporter_code = int(codes[0])
                if record.get("run_in_background", False) is not False or record.get("background", False):
                    outcome, basis = "unknown", "background launch is not native completion evidence"
                elif stage != "finalize" and trusted_prefix and reporter_code is not None:
                    outcome = "passed" if reporter_code == 0 else "failed"
                    basis = "adjacent $? reporter + unique tool-output status; not native subcommand telemetry"
                elif trusted_prefix and (index == len(segments) - 1 or all_and):
                    if record["outcome"] == "passed":
                        outcome = "passed"
                        basis = (record["basis"] + "; final unconditional command" if index == len(segments) - 1
                                 else "successful simple && chain; inferred, not per-subcommand native exits")
                    elif len(segments) == 1:
                        outcome = record["outcome"]
                evidence = {"line": record["line"], "id": record["id"],
                            "call_line": record.get("call_line", record["line"]),
                            "status": outcome, "basis": basis,
                            "native_exit_code": record["exit_code"], "entrypoint": stage}
                if stage == "finalize":
                    evidence["basis"] += "; controlled finalize composition (not stdout markers)"
                # Aggregated output is not separable for an earlier command in a
                # chain. Only a final, non-redirected invocation may supply reply
                # evidence; retain raw output for manual inspection regardless.
                if stage in ("reply", "finalize"):
                    evidence["output"] = record["output"]
                    evidence["output_is_final_command"] = index == len(segments) - 1 and not redirected
                    evidence["requested_reply"] = reply_text
                for target in (("regen", "recall", "postflight", "reply") if stage == "finalize" else (stage,)):
                    stages[target]["evidence"].append(dict(evidence))
            # Unrecognized commands may change cwd, functions, traps or options;
            # do not propagate a success proof through them.
            safe_reporter = (tokens[0] == "echo" or len(tokens) == 3
                             and tokens[0] == "printf" and tokens[2] == "$?"
                             and re.fullmatch(r"[A-Za-z_]\w*=%[sd]\\n", tokens[1]))
            if stage is None and not safe_reporter:
                trusted_prefix = False
    for stage in stages.values():
        statuses = [e["status"] for e in stage["evidence"]]
        stage["status"] = ("failed" if "failed" in statuses else "passed" if "passed" in statuses else "unknown")
    return {"stages": stages, "unsupported_commands": unsupported,
            "passed": all(s["status"] == "passed" for s in stages.values()),
            "scope": "Matched installed script invocations in actual shell tool events only. "
                     "Unknown is not success. Execution evidence does not certify semantics or chronology."}


FINALIZE_REPLY = "✅ 交接已保存；项目定位、声明一致性、索引、召回预检与写后检查通过。"


def reply_consistency(events, stage_evidence):
    """Compare the actual final text, not a shorter string checked earlier.

    Hosts may merge stderr diagnostics with stdout. For a proven final command,
    use its last output line without stripping text whitespace. Missing or
    unisolatable output remains unknown; no printed success marker is trusted.
    """
    final = events["final"]
    evidence = stage_evidence["stages"].get("reply", {}).get("evidence", [])
    candidates = [e for e in evidence if e["status"] == "passed"]
    report = {"status": "unknown", "actual_final": final,
              "actual_final_characters": len(final), "runtime_reply": None}
    if not candidates:
        return report
    item = candidates[-1]
    report.update(line=item["line"], entrypoint=item["entrypoint"])
    positions = events.get("tool_event_lines")
    if not isinstance(positions, list) or any(type(n) is not int for n in positions):
        report["reason"] = "complete native tool-event positions unavailable"
        return report
    boundary = item["line"]
    allowed = {item["line"], item.get("call_line", item["line"])}
    if item["entrypoint"] == "reply":
        postflight = [e for e in stage_evidence["stages"].get("postflight", {}).get("evidence", [])
                      if e["status"] == "passed" and e["line"] <= item["line"]]
        if postflight:
            boundary = postflight[-1]["line"]
    later_tools = [n for n in positions if n > boundary and n not in allowed]
    report["tools_after_confirmation_check"] = later_tools
    if later_tools:
        report.update(status="failed", reason="tool activity after final check; same final text cannot revalidate it")
        return report
    if not item.get("output_is_final_command") or not isinstance(item.get("output"), str):
        return report
    output = item["output"]
    # Remove exactly the runtime's trailing newline, not arbitrary whitespace.
    output = output[:-1] if output.endswith("\n") else output
    runtime_reply = output.rsplit("\n", 1)[-1]
    if not runtime_reply:
        return report
    report["runtime_reply"] = runtime_reply
    one_line = not any(char in final for char in "\n\r\v\f\u2028\u2029\u0085")
    matches_request = (runtime_reply == FINALIZE_REPLY if item["entrypoint"] == "finalize" else
                       item.get("requested_reply") == runtime_reply)
    report["status"] = "passed" if (one_line and 0 < len(final) <= 120 and
                                    matches_request and final == runtime_reply) else "failed"
    return report


STARTUP = "🚀启动handoffX项目交接流程."


def presentation_contract(events, phase):
    """Literal mechanical checks plus explicit unknowns, never keyword exemptions."""
    texts = events["texts"]
    final = events["final"]
    count = sum(t["text"].count(STARTUP) for t in texts)
    checks = {"startup_not_repeated": "passed" if count <= 1 else "failed"}
    review = []
    if phase == "write":
        prefinal = texts[:-1] if texts and texts[-1]["text"] == final else texts
        normal_shape = len(prefinal) == 1 and prefinal[0]["text"].strip() == STARTUP
        # No keyword (error/warning/异常) grants an exception. Even a native
        # error only makes extra prose a candidate exception for human review.
        has_error = bool(events["errors"] or events["permission_denials"])
        ordinary = normal_shape and not has_error
        checks["normal_startup_and_final_only"] = "passed" if ordinary else "unknown"
        for name, value, limit in (("normal_visible_length", sum(len(t["text"]) for t in texts), 200),
                                   ("normal_final_length", len(final), 120)):
            checks[name] = "passed" if ordinary and 0 < value <= limit else "unknown"
        if any(v == "unknown" for v in checks.values()):
            review.append({"question": "Normal progress/noncanonical startup versus necessary warning, error or confirmation? "
                                       "Normal length limits do not restrict legitimate exception notices.",
                           "native_error_lines": [e["line"] for e in events["errors"]],
                           "visible_lines": [t["line"] for t in texts]})
    else:
        prefinal = texts[:-1] if texts and texts[-1]["text"] == final else texts
        quiet = not prefinal or (len(prefinal) == 1 and prefinal[0]["text"].strip() == STARTUP)
        has_error = bool(events["errors"] or events["permission_denials"])
        checks["recall_no_normal_progress"] = "passed" if quiet and not has_error else "unknown"
        if not quiet or has_error:
            review.append({"question": "Distinguish necessary exception notices from forbidden ordinary recall progress.",
                           "visible_lines": [t["line"] for t in prefinal]})
        titles = ["## 从这里继续", "### 上次停在哪里", "### 当前TODO", "### 下一步"]
        matches = [list(re.finditer(r"(?m)^" + re.escape(h) + r"[ \t]*$", final)) for h in titles]
        ordered = all(len(m) == 1 for m in matches) and \
            [m[0].start() for m in matches] == sorted(m[0].start() for m in matches)
        checks["recall_tail_order_unique"] = "passed" if ordered else "failed"
        if ordered:
            prefix = final[:matches[0][0].start()].strip()
            if prefix:
                review.append({"question": "Check pre-tail final text is report content, not ordinary progress narration.",
                               "text": prefix})
            tail = final[matches[0][0].start():]
            headings = re.findall(r"(?m)^#{1,6} .+$", tail)
            checks["recall_no_extra_tail_heading"] = "passed" if headings == titles else "failed"
            bodies = [final[matches[i][0].end():matches[i + 1][0].start()].strip() for i in (1, 2)]
            # The next-step section is last, so its body has no following heading.
            bodies.append(final[matches[3][0].end():].strip())
            checks["recall_stop_next_nonempty"] = "passed" if all(bodies) else "failed"
            # The TODO section is now the second-to-last: its list is followed by
            # the next-step section, so an unindented line that is neither a list
            # item nor a continuation means an afterword was slipped into it.
            todo = final[matches[2][0].end():matches[3][0].start()].splitlines()
            seen_item, trailing, ambiguous = False, [], []
            for number, line in enumerate(todo, 1):
                if not line.strip():
                    continue
                if re.match(r"^(?:[-*+]|[0-9]+[.)])\s+(?:\[[ xX]\]\s+)?\S", line):
                    seen_item = True
                elif seen_item and re.match(r"^\s+\S", line):
                    ambiguous.append(number)  # Could be task metadata OR an indented afterword.
                else:
                    trailing.append(number)
            checks["recall_todo_items_present"] = "passed" if seen_item else "unknown"
            checks["recall_no_unindented_afterword"] = "failed" if trailing else "passed"
            if ambiguous:
                review.append({"question": "Check indented TODO continuations are metadata, not disguised afterwords.",
                               "todo_relative_lines": ambiguous})
            # The next-step section is terminal. Its body is prose, so only the
            # usual afterword openers are caught mechanically; the rest is review.
            nxt = final[matches[3][0].end():].splitlines()
            late = [i for i, line in enumerate(nxt, 1)
                    if re.match(r"^[ \t]*[（(]?(总结|小结|来源|风险|提示|备注|附注|另|注意)[:：）)]?", line)]
            # An empty next-step section is not "nothing to add" — the spec says
            # an unrecorded plan must be written as 未记录.
            checks["recall_next_step_terminal"] = "failed" if late or not bodies[2] else "passed"
            if late:
                review.append({"question": "The next-step section is the last block: remove the appended section or note.",
                               "next_relative_lines": late})
        review.append({"question": "Verify TODO completeness, provenance, no added advice/afterword inside list items, "
                                   "and correct stop/next semantics; heading/list syntax is not semantic acceptance."})
    return {"checks": checks, "passed": all(v == "passed" for v in checks.values()),
            "startup_literal_occurrences": count, "human_review": review,
            "normal_progress_scope": "Only prefinal messages checked mechanically; final report narration requires semantic review",
            "semantic_status": "REQUIRES_HUMAN_REVIEW"}


def model_host_environment(project, evidence, phase):
    """Keep host runtime files out of fixture measurements, not out of evidence.

    loop002 Codex wrote Node compile cache and .tmp directories under its
    inherited TMPDIR=fixture/wip/tmp. That mixed host startup writes with skill
    read-only behavior. Relocate ONLY the model-host launch environment; do not
    ignore fixture/wip, weaken sandbox flags, alter auth, or repair prior runs.
    Model/tool-created files must still follow the prompt's fixture/wip rule.
    """
    runtime = evidence / ("host-runtime-" + phase)
    runtime.mkdir(parents=True, exist_ok=False)
    env = environment(project)
    overrides = {key: str(runtime) for key in ("TMPDIR", "TMP", "TEMP", "NODE_COMPILE_CACHE")}
    env.update(overrides)
    measurement = {
        "root": str(runtime), "exact_environment_overrides": overrides,
        "cwd": str(project), "PWD": env["PWD"],
        "scope": "model-host process environment only; child tools may inherit it",
        "fixture_measurement": "ALL fixture descendants including wip/ and .serena/; no exclusions",
        "host_runtime_measurement": "separate before/after manifests; retained raw cache; not included in fixture changed_paths",
        "model_temporary_file_instruction": str(project / "wip/tmp"),
        "sandbox_and_approval": "unchanged; no extra writable-root or permission-bypass flags",
        "auth": "actual user HOME/provider/auth environment inherited; no credentials inspected or recorded",
    }
    save(evidence / (phase + "-host-runtime-environment.json"), measurement)
    return env, runtime, measurement


def phase_run(host, phase, command, project, evidence, timeout):
    host_env, runtime, runtime_measurement = model_host_environment(project, evidence, phase)
    before = checkpoint(project, evidence, phase + "-before")
    cache_before = snapshot(runtime)
    save(evidence / (phase + "-host-runtime-before-manifest.json"), cache_before)
    try:
        result = execute(command, project, evidence, phase, timeout, env=host_env)
    finally:
        # Preserve both measurement boundaries even if execution is interrupted;
        # no cache difference is silently folded into or removed from fixture data.
        after = checkpoint(project, evidence, phase + "-after")
        cache_after = snapshot(runtime)
        save(evidence / (phase + "-host-runtime-after-manifest.json"), cache_after)
        runtime_measurement["changed_paths"] = changed(cache_before, cache_after)
        runtime_measurement["before_manifest"] = phase + "-host-runtime-before-manifest.json"
        runtime_measurement["after_manifest"] = phase + "-host-runtime-after-manifest.json"
        save(evidence / (phase + "-host-runtime-status.json"), runtime_measurement)
    result["changed_paths"] = changed(before, after)
    result["host_runtime"] = runtime_measurement
    events = extract_events((evidence / (phase + ".stdout.jsonl")).read_bytes(), host)
    result["tool_event_count"] = len(events["tool_lines"])
    (evidence / (phase + "-tool-events.jsonl")).write_bytes(b"".join(events.pop("tool_lines")))
    text = "\n\n".join(t["text"] for t in events["texts"])
    put(evidence / (phase + "-visible.md"), text)
    put(evidence / (phase + "-final.txt"), events["final"])
    stage_evidence = required_stage_evidence(events["executions"], host, project, phase)
    presentation = presentation_contract(events, phase)
    if phase == "write":
        consistency = reply_consistency(events, stage_evidence)
        result["reply_consistency"] = consistency
        save(evidence / "write-reply-consistency.json", consistency)
    save(evidence / (phase + "-required-stage-evidence.json"), stage_evidence)
    save(evidence / (phase + "-presentation-contract.json"), presentation)
    save(evidence / (phase + "-host-usage.json"), events["host_usage"])
    save(evidence / (phase + "-visible-text.json"), events)
    result.update(required_stage_evidence=stage_evidence, presentation_contract=presentation,
                  host_usage=events["host_usage"], raw_stream_bytes=events["raw_stream_bytes"],
                  raw_stream_bytes_scope=events["raw_stream_bytes_scope"])
    result.update(session_ids=sorted({x["id"] for x in events["session_observations"]}),
                  visible_characters=sum(len(t["text"]) for t in events["texts"]),
                  final_characters=len(events["final"]), actual_final=events["final"], native_errors=events["errors"],
                  permission_denials=events["permission_denials"], failure_boundary=events["failure_boundary"],
                  non_json_or_malformed_lines=events["non_json_or_malformed_lines"])
    save(evidence / (phase + "-status.json"), result)
    return result, text


def unknown_verification(text):
    """Check the requested literal contract, not whether a claim is true."""
    stanzas = re.findall(r"(?ms)^<!-- verification:v1 -->\n(.*?)^<!-- /verification -->", text)
    required = {"source": "runner_report", "performed_at": "unknown",
                "time_basis": "not_provided", "time_evidence": "not_provided"}
    # This fixture has one new verification event; no conflicting event-time claims.
    return len(stanzas) == 1 and all(
        re.findall(r"(?m)^" + key + r": ([^\n]+)$", stanzas[0]) == [value]
        for key, value in required.items())


def saved_checks(project, original, old_logs):
    if (project / "HANDOFFX.md").is_symlink() or (project / "Handoffx_Logs").is_symlink():
        raise RuntimeError("refusing handoff symlinks during audit")
    main = (project / "HANDOFFX.md").read_bytes().decode("utf-8")
    logs = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (project / "Handoffx_Logs").glob("*.md") if p.is_file() and not p.is_symlink()}
    added = sorted(logs.keys() - old_logs.keys())
    pending = block(main, "pending") or ""
    checks = {
        "exactly_one_new_log": len(logs) == 9 and len(added) == 1,
        "eight_old_logs_unchanged": all(logs.get(k) == v for k, v in old_logs.items()),
        "new_log_is_next_number": len(added) == 1 and added[0].startswith("0009-"),
        "goal_block_byte_identical": block(main, "continuity") is not None and
                                     block(main, "continuity") == block(original, "continuity"),
        "target_marked_done_once": len(re.findall(r"(?m)^\s*- \[[xX]\].*\bTASK-FILTER\b", main)) == 1,
        "target_not_open": not re.search(r"(?m)^\s*- \[ \].*\bTASK-FILTER\b", main),
        "recent_updated": block(main, "recent") is not None and
                          block(main, "recent") != block(original, "recent"),
    }
    new_log = ((project / "Handoffx_Logs" / added[0]).read_text(encoding="utf-8")
               if len(added) == 1 else "")
    checks["recent_runner_report_performed_at_unknown"] = unknown_verification(block(main, "recent") or "")
    checks["new_log_runner_report_performed_at_unknown"] = unknown_verification(new_log)
    for task, line in RESIDUAL.items():
        checks[task + "_pending_and_metadata_preserved_exactly"] = line in pending.splitlines()
    return checks, added


def heuristic_checks(report, write, saved):
    tail = re.search(r"(?ms)^## 从这里继续\s*\n(.*)\Z", report)
    # v4.4.0: the TODO list is followed by the terminal next-step section.
    todo = re.search(r"(?ms)^### 当前TODO\s*\n(.*?)(?=^### 下一步\s*$|\Z)", report)
    nxt = re.search(r"(?ms)^### 下一步\s*\n(.*)\Z", report)
    headings = ["### 上次停在哪里", "### 当前TODO", "### 下一步"]
    positions = [report.find(h) for h in headings]
    # loop001 OpenCode passed mechanical checks but its new log reused the
    # pre-development stop point (only open_tasks, completed_tasks not implemented)
    # while recent described the completed work. Keyword hits are REVIEW hints,
    # not semantic verdicts, and must never gate recall or mechanical_pass.
    new_log = saved.get("new_log", "")
    old_state = re.compile(r"尚未实现|未实现|尚未完成|未完成|待完成|未开始|"
                           r"仅有\s*`?open_tasks|仅.{0,40}(?:三|3)项测试|"
                           r"not yet implemented|not implemented|still pending", re.I)
    old_state_lines = [{"line": n, "text": line}
                       for n, line in enumerate(new_log.splitlines(), 1) if old_state.search(line)]
    historical_marker = "本轮开始前" in new_log
    stop_point_review = {
        "classification": "HEURISTIC_REVIEW_HINT_ONLY",
        "attention_required": bool(old_state_lines) and not historical_marker,
        "old_state_lines": old_state_lines,
        "explicit_before_this_round_marker_present": historical_marker,
        "affects_mechanical_pass": False,
        "review_note": "对照新日志停点与recent结束点，确认旧状态是否被误写为交接停点；"
                       "残余任务也可能命中。未命中或存在历史标记均不证明语义一致，仍需人工审阅。",
    }
    def attribution(text):
        return bool(re.search(r"测试驱动|test driver|harness", text, re.I))
    def unknown_time(text):
        return bool(re.search(r"(?:执行|运行|测试).{0,40}(?:时间|日期|时刻).{0,40}(?:未知|未提供|未记录|不详)|"
                              r"(?:时间|日期|时刻).{0,20}(?:未知|未提供|未记录)|"
                              r"(?:time|date).{0,30}(?:unknown|not (?:provided|recorded))", text, re.I))
    return {
        "classification": "HEURISTICS_ONLY_NOT_SEMANTIC_PASS",
        "new_log_stop_point_review": stop_point_review,
        "normal_write_all_visible_le_200": 0 < write["visible_characters"] <= 200,
        "normal_write_final_le_120": 0 < write["final_characters"] <= 120,
        "length_exemption": "Warnings/errors/confirmation require human review; never auto-exempt or truncate.",
        "recall_mentions_dictionary_data_loss_reason": bool(re.search(r"字典|dictionary|dict", report, re.I))
            and bool(re.search(r"丢|损失|lose|loss|overwrite", report, re.I)),
        "recall_mentions_offline_dependency_reason": bool(re.search(r"离线|offline", report, re.I))
            and bool(re.search(r"依赖|标准库|dependenc|standard library", report, re.I)),
        "recall_driver_attribution": attribution(report),
        "recall_unknown_actual_test_time": unknown_time(report),
        "saved_validation": {name: {"driver_attribution": attribution(text),
                                     "unknown_actual_test_time": unknown_time(text)}
                             for name, text in saved.items()},
        "tail_present_and_headings_ordered": bool(tail and todo and nxt) and
            all(p >= 0 for p in positions) and positions == sorted(positions),
        "no_heading_after_next_step": bool(nxt) and not re.search(r"(?m)^#{1,6}\s", nxt.group(1)),
        "all_residual_tasks_in_TODO": bool(todo) and all(t in todo.group(1) for t in RESIDUAL),
        "completed_target_not_in_TODO": bool(todo) and TARGET not in todo.group(1),
        "approval_still_ungranted_in_report": bool(re.search(r"未批准|尚未批准|not approved", report, re.I)),
        "deferred_state_in_TODO": bool(todo) and bool(re.search(r"暂缓|deferred", todo.group(1), re.I)),
        "requires_human_review": True,
    }


def wrong_project_check(project, evidence, skill, timeout):
    """Native driver negative: cwd stays inside the granted fixture project.

    This is NOT a model/tool permission test. Record the real subprocess cwd
    and PWD, and snapshot the entire fixture, including the simulated sibling.
    Never cd to the parent, add writable roots or change host permissions.
    """
    wrong = wrong_project_directory(project)
    wrong.mkdir(parents=True, exist_ok=False)
    env = environment(wrong)  # Create the temp tree BEFORE the zero-write boundary.
    before = checkpoint(project, evidence, "wrong-project-before")
    probe = execute(["/bin/pwd", "-P"], wrong, evidence, "wrong-project-cwd", timeout, env)
    actual_cwd = (evidence / "wrong-project-cwd.stdout.jsonl").read_text(encoding="utf-8").rstrip("\n")
    logs = sorted((project / "Handoffx_Logs").glob("*.md"))
    if not logs:
        raise RuntimeError("wrong-project negative needs a real fixture log")
    command = ["bash", str(skill / "scripts/handoff-runtime.sh"), "--expect-root", str(project),
               "finalize", "--log", "Handoffx_Logs/" + logs[-1].name]
    status = execute(command, wrong, evidence, "wrong-project-finalize", timeout, env)
    after = checkpoint(project, evidence, "wrong-project-after")
    differences = changed(before, after)
    checks = {
        "native_cwd_observed": succeeded(probe) and actual_cwd == str(wrong.resolve()),
        "wrong_cwd_inside_project_not_root": project.resolve() in wrong.resolve().parents,
        "PWD_matches_native_cwd": env["PWD"] == actual_cwd,
        "runtime_rejected": type(status["exit_code"]) is int and status["exit_code"] == 2
                            and not status["timeout"],
        "root_mismatch_diagnostic": "cwd does not match EXPECTED_ROOT" in
            (evidence / "wrong-project-finalize.stderr").read_text(encoding="utf-8", errors="replace"),
        "stdout_empty": not (evidence / "wrong-project-finalize.stdout.jsonl").read_bytes(),
        "zero_project_changes": not differences,
    }
    report = {"checks": checks, "passed": all(checks.values()), "actual_tool_cwd": actual_cwd,
              "evidence_kind": "DRIVER_SUBPROCESS_ONLY_NOT_MODEL_E2E",
              "expected_root": str(project), "PWD": env["PWD"], "changed_paths": differences,
              "scope": "Native driver subprocess, not host model; unchanged host permissions; "
                       "full fixture snapshot (including sibling), no parent-directory cd."}
    save(evidence / "wrong-project-check.json", report)
    return report


def wrong_root_evidence(events, host, project):
    """Expected rejection must come from the actual model's one shell tool call.

    Self-report, a host launch cwd, or OpenCode silently choosing the project
    root never substitutes for pwd from the same invocation as the runtime.
    """
    expected = shell_segments(wrong_root_command(project, host))
    records = events["executions"]
    matched = []
    for record in records:
        try:
            if shell_segments(record["command"]) == expected:
                matched.append(record)
        except ValueError:
            pass
    item = matched[0] if len(matched) == 1 else {}
    output = item.get("output", "")
    output = output if isinstance(output, str) else ""
    stderr = item.get("stderr", "")
    stderr = stderr if isinstance(stderr, str) else ""
    cwd_output, envelope = output, None
    # Observed Claude 2.1.312 native failure transport has two agreeing
    # envelopes. Strip only that exact prefix here, never mutate raw output,
    # search arbitrary lines for a pwd, or override a native numeric field.
    if (host == "claude" and item.get("outcome") == "failed"
            and output.startswith("Exit code 2\n")
            and not item.get("native_exit_present", False)
            and item.get("native_result_text") == "Error: " + output):
        cwd_output, envelope = output[len("Exit code 2\n"):], "Exit code 2"
    cwd = cwd_output.splitlines()[0] if cwd_output.splitlines() else None
    checks = {
        "one_exact_native_tool_call": len(records) == len(matched) == 1,
        "actual_tool_cwd_is_wrong_directory": cwd == str(wrong_project_directory(project).resolve()),
        "actual_tool_cwd_not_project_root": cwd is not None and cwd != str(project.resolve()),
        "native_runtime_rejected": item.get("outcome") == "failed" and (
            type(item.get("exit_code")) is int and item["exit_code"] == 2 or
            host == "claude" and envelope == "Exit code 2"),
        "root_mismatch_diagnostic": "cwd does not match EXPECTED_ROOT" in output + stderr,
        "no_permission_denials": not events["permission_denials"],
        "stream_parseable": not events["non_json_or_malformed_lines"],
    }
    return {"checks": checks, "passed": all(checks.values()), "actual_tool_cwd": cwd,
            "expected_root": str(project), "required_wrong_cwd": str(wrong_project_directory(project)),
            "native_exit_code": item.get("exit_code"),
            "rc2_evidence_basis": "observed_Claude_dual_envelope" if envelope else "native_exit_code",
            "command": item.get("command"),
            "cwd_transport_prefix_removed": envelope,
            "cwd_scope": "command-local cd then pwd" if host == "claude" else "tool workdir then pwd",
            "evidence_kind": "MODEL_NATIVE_TOOL_WRONG_ROOT", "host": host,
            "scope": "Effective runtime cwd from same native tool call's /bin/pwd -P, "
                     "not host launch cwd or model prose; no external-directory permission."}


def wrong_root_run(host, command, project, evidence, timeout):
    status, _ = phase_run(host, "wrong-root", command, project, evidence, timeout)
    events = json.loads((evidence / "wrong-root-visible-text.json").read_text(encoding="utf-8"))
    report = wrong_root_evidence(events, host, project)
    report["checks"].update(host_process_success=succeeded(status),
                            zero_project_changes=not status["changed_paths"])
    report["changed_paths"] = status["changed_paths"]
    report["session_ids"] = status["session_ids"]
    report["passed"] = all(report["checks"].values())
    save(evidence / "wrong-root-model-check.json", report)
    return report


def prepare(host, base, source, timeout):
    project, evidence = base / host / "project", base / host / "evidence"
    evidence.mkdir(parents=True)
    original = seed(project)
    checkpoint(project, evidence, "initial-pending-before-development")
    env = environment(project)
    init = execute(["git", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=roundtrip",
                    "init", "--quiet", "--template="], project, evidence, "git-init", timeout, env)
    if not succeeded(init):
        raise RuntimeError("git init failed; inspect git-init.stderr")
    home = base / host / "installer-home"
    install = execute(["bash", str(source / "install.sh"), "--project", str(project)],
                      project, evidence, "install", timeout, environment(project, home))
    save(evidence / "installer-home-manifest.json", snapshot(home, evidence / "installer-home-snapshot"))
    checkpoint(project, evidence, "installed")
    if not succeeded(install):
        raise RuntimeError("project installation failed; inspect install.stdout.jsonl and install.stderr")
    skill = project / HOST_ROOTS[host] / "skills/handoffx"
    if not (skill / "SKILL.md").is_file():
        raise RuntimeError(f"Installer did not create selected host skill: {skill}")
    binding_file = skill / ".handoffx-install-context"
    binding = dict(line.split("=", 1) for line in binding_file.read_text(encoding="utf-8").splitlines())
    bound = all(binding.get(key) == value for key, value in {
        "schema": "1", "scope": "project", "project_root": str(project),
        "skill_root": str(skill), "host": host}.items())
    save(evidence / "install-binding-check.json", {"fields": binding, "project_binding_matches": bound})
    if not bound:
        raise RuntimeError("installed manifest does not bind the selected project/host/skill")
    expected = snapshot(source / "skills/handoffx", evidence / "source-skill-at-install")
    save(evidence / "source-skill-at-install-manifest.json", expected)
    actual = snapshot(skill)
    integrity = {k: actual.get(k, {}).get("sha256") == v["sha256"]
                 for k, v in expected.items() if v["kind"] == "file"
                 and not k.startswith(("command-shims/", "commands/"))}
    # install.sh intentionally moves/renders command-shims into host entries;
    # those source-only directories must not remain inside the installed skill.
    integrity["source_only_shims_absent"] = not (skill / "command-shims").exists() and not (skill / "commands").exists()
    save(evidence / "installed-source-hash-checks.json", integrity)
    if not integrity or not all(integrity.values()):
        raise RuntimeError("installed skill differs from selected source; no model started")
    put(project / "taskboard.py", BASE_CODE + FEATURE_CODE)
    put(project / "tests/test_taskboard.py", BASE_TESTS.replace(
        "from taskboard import open_tasks", "from taskboard import open_tasks, completed_tasks") + FEATURE_TESTS)
    test = execute([sys.executable, "-B", "wip/tmp/run_tests.py"], project, evidence,
                   "development-tests", timeout, clock=False)
    raw = evidence / "development-tests.stdout.jsonl"
    # Copy original bytes, no timing removal, summary replacement, or fixture answer.
    target = project / "wip/logs/development-tests.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(raw, target)
    report = json.loads(raw.read_bytes())
    if not succeeded(test) or report.get("tests_run") != 6 or len(report.get("passed", [])) != 6:
        raise RuntimeError("six REAL development tests did not pass; no model started")
    before_validation = checkpoint(project, evidence, "fixture-validation-before")
    for label, argv in (
        ("fixture-runtime", ["bash", str(skill / "scripts/handoff-runtime.sh"), "recall", ""]),
        ("fixture-postflight", ["bash", str(skill / "scripts/handoff-postflight.sh")]),
    ):
        status = execute(argv, project, evidence, label, timeout)
        if not succeeded(status):
            raise RuntimeError(f"{label} failed before any model call; inspect raw evidence")
    if changed(before_validation, checkpoint(project, evidence, "fixture-validation-after")):
        raise RuntimeError("fixture validators modified the project; inspect evidence")
    if not wrong_project_check(project, evidence, skill, timeout)["passed"]:
        raise RuntimeError("wrong-project negative failed; inspect cwd and zero-change evidence")
    if host == "opencode":
        permissions(project, "write")
    checkpoint(project, evidence, "developed-still-pending")
    old = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
           for p in (project / "Handoffx_Logs").glob("*.md")}
    save(evidence / "fixture-info.json", {"synthetic_logs": sorted(old), "old_task_origin_log": "0001",
         "initial_target_status": "pending, deliberately stale until real handoff",
         "test_evidence": "wip/logs/development-tests.json", "test_execution_time": "NOT PROVIDED",
         "git": "independent init only, zero commits", "skill": str(skill), "installer_HOME": str(home)})
    return project, evidence, original, old, skill



def recall_readiness(write, checks):
    """Admission to session 2 is NOT a successful-write verdict.

    Recovered/early tool errors remain in write_process_success and the overall
    mechanical verdict. A readable valid saved state may still be recalled by
    an independent session when the host exited 0 without timing out. No repair.
    """
    transcript_checks = {"write_process_success", "write_visible_text_observed",
                         "write_tool_events_observed", "write_stream_parseable"}
    ready = {key: value for key, value in checks.items()
             if key not in transcript_checks and not key.startswith("normal_write_")
             and key not in ("write_required_stages_proven", "write_presentation_contract", "write_reply_matches_final", "wrong_root_model_negative_passed")}
    ready["write_host_exit_zero_no_timeout"] = succeeded(write)
    return ready


def bootstrap_host(host, template, project, evidence, timeout):
    """Record host initialization separately; never hide its filesystem effects."""
    command = list(template)
    command[-1] = "仅回复 HOST_READY，不调用任何工具，不执行交接、召回或开发，不主动创建/修改文件。"
    command = [arg.replace("wrong-root-native-final.txt", "bootstrap-native-final.txt") for arg in command]
    env, runtime, measurement = model_host_environment(project, evidence, "bootstrap")
    before = checkpoint(project, evidence, "bootstrap-before")
    cache_before = snapshot(runtime)
    status = execute(command, project, evidence, "bootstrap", timeout, env=env)
    after = checkpoint(project, evidence, "bootstrap-after")
    events = extract_events((evidence / "bootstrap.stdout.jsonl").read_bytes(), host)
    (evidence / "bootstrap-tool-events.jsonl").write_bytes(b"".join(events["tool_lines"]))
    save(evidence / "bootstrap-visible-text.json", {k: v for k, v in events.items() if k != "tool_lines"})
    save(evidence / "bootstrap-host-runtime-before-manifest.json", cache_before)
    save(evidence / "bootstrap-host-runtime-after-manifest.json", snapshot(runtime))
    delta = changed(before, after)
    serena_delta = [p for p in delta if p == ".serena" or p.startswith(".serena/")]
    initialization_only = not serena_delta or (
        not any(p == ".serena" or p.startswith(".serena/") for p in before)
        and after.get(".serena", {}).get("kind") == "directory"
        and all(row["kind"] in ("directory", "file") for path, row in after.items()
                if path == ".serena" or path.startswith(".serena/")))
    checks = {"host_process_success": succeeded(status),
              "no_model_tool_calls": not events["tool_lines"],
              "no_native_errors": not events["errors"] and not events["permission_denials"],
              "parseable_stream": not events["non_json_or_malformed_lines"],
              "bootstrap_reply_observed": events["final"].strip() == "HOST_READY",
              "one_bootstrap_session": len({x["id"] for x in events["session_observations"]}) == 1,
              "only_new_regular_host_initialization": initialization_only,
              "protected_fixture_unchanged": all(p == ".serena" or p.startswith(".serena/") for p in delta)}
    report = {"checks": checks, "passed": all(checks.values()), "changed_paths": delta,
              "process": status, "session_ids": sorted({x["id"] for x in events["session_observations"]}),
              "host_diagnostics": events["host_messages"],
              "scope": "explicit host bootstrap; any .serena creation remains recorded; subsequent phases measure ALL paths",
              "not_proven": "cold-start zero-write; native slash registration; transient-write absence"}
    measurement["changed_paths"] = changed(cache_before, snapshot(runtime))
    save(evidence / "bootstrap-host-runtime-status.json", measurement)
    save(evidence / "bootstrap-check.json", report)
    return report


def run_host(host, args, base, source):
    project, evidence, original, old, skill = prepare(host, base, source, args.timeout)
    cmd = commands(host, project, evidence, args.opencode_model, args.entry_mode)
    if args.host_protection == "project-readonly":
        cmd = protect_commands(host, cmd, project, evidence)
        if host == "opencode" and not verify_readonly_protection(project, evidence, args.timeout)["passed"]:
            raise RuntimeError("Whole-host read-only protection control failed; no model launched")
    save(evidence / "commands.json", cmd)
    if args.prepare_only:
        return {"host": host, "mode": "PREPARE_ONLY_NO_MODEL", "six_real_tests_passed": True,
                "semantic_status": "NOT_RUN", "mechanical_pass": True}
    result = {"host": host, "semantic_status": "REQUIRES_HUMAN_REVIEW", "entry_scope": ENTRY_SCOPE, "entry_mode": args.entry_mode}
    result["host_lifecycle"] = args.host_lifecycle
    result["host_protection"] = args.host_protection
    if args.host_lifecycle == "initialized":
        if host == "opencode":
            save(project / "opencode.json", {"permission": {"*": "deny", "external_directory": "deny"}})
            checkpoint(project, evidence, "driver-bootstrap-permission-switch")
        result["bootstrap"] = bootstrap_host(host, cmd["wrong-root"], project, evidence, args.timeout)
        if not result["bootstrap"]["passed"]:
            result.update(mechanical_pass=False, stopped="Host bootstrap touched protected fixture or failed; no baseline repair.")
            save(evidence / "result.json", result)
            return result
    if host == "opencode":
        permissions(project, "wrong-root")
        checkpoint(project, evidence, "driver-wrong-root-permission-switch")
    result["wrong_root_model_negative"] = wrong_root_run(
        host, cmd["wrong-root"], project, evidence, args.timeout)
    if host == "opencode":
        permissions(project, "write")
        checkpoint(project, evidence, "driver-write-permission-switch")
    write, _ = phase_run(host, "write", cmd["write"], project, evidence, args.timeout)
    result["write"] = write
    if write["permission_denials"]:
        result["semantic_status"] = "NOT_EVALUATED_HOST_PERMISSION_BLOCKED"
    checks, added = saved_checks(project, original, old)
    checks["wrong_root_model_negative_passed"] = result["wrong_root_model_negative"]["passed"]
    checks["write_process_success"] = succeeded(write) and not write["native_errors"]
    checks["write_visible_text_observed"] = write["visible_characters"] > 0
    checks["write_tool_events_observed"] = write["tool_event_count"] > 0
    checks["write_stream_parseable"] = not write["non_json_or_malformed_lines"]
    checks["write_required_stages_proven"] = write["required_stage_evidence"]["passed"]
    checks["write_presentation_contract"] = write["presentation_contract"]["passed"]
    checks["write_reply_matches_final"] = write["reply_consistency"]["status"] == "passed"
    before = json.loads((evidence / "write-before-manifest.json").read_text())
    after = json.loads((evidence / "write-after-manifest.json").read_text())
    protected = [k for k in before if k.startswith((".agents/", ".claude/", ".opencode/", ".git/"))
                 or k in ("taskboard.py", "tests/test_taskboard.py", "wip/tmp/run_tests.py",
                          "wip/logs/development-tests.json")]
    checks["installed_skills_git_and_development_evidence_unchanged"] = all(
        before[k] == after.get(k) for k in protected)
    # Validation is read-only: never regenerate/repair the model's saved state.
    validation_before = checkpoint(project, evidence, "validation-before")
    # postflight can regenerate pointers/archive: it is the AGENT's write step,
    # never a driver repair. Here invoke only read-only validators on saved state.
    runtime = str(skill / "scripts/handoff-runtime.sh")
    validation_commands = [
        ("runtime-recall", ["bash", runtime, "recall", ""]),
        ("verification-current", ["bash", runtime, "verification-check", "--current", "--require"] +
         (["--match-file", "Handoffx_Logs/" + added[0]] if len(added) == 1 else [])),
    ]
    if len(added) == 1:
        validation_commands.append(("verification-log", ["bash", runtime, "verification-check",
                                    "--file", "Handoffx_Logs/" + added[0], "--require"]))
    for label, argv in validation_commands:
        if not checks["installed_skills_git_and_development_evidence_unchanged"]:
            checks[label + "_exit_zero"] = False
            continue  # Never execute a model-modified runtime or repair its state.
        status = execute(argv, project, evidence, "after-write-" + label, args.timeout)
        checks[label + "_exit_zero"] = succeeded(status)
    validation_after = checkpoint(project, evidence, "validation-after")
    checks["validators_did_not_modify_project"] = not changed(validation_before, validation_after)
    save(evidence / "saved-state-checks.json", {"checks": checks, "added_logs": added})
    result["mechanical_checks"] = checks
    # Keep the write verdict unchanged, but independently test recall whenever
    # the saved state is valid and the host exited cleanly. Early native errors
    # and verbosity failures are NOT repaired or relabelled successful.
    result["write_mechanical_pass"] = all(checks.values())
    ready_checks = recall_readiness(write, checks)
    result["recall_ready_checks"] = ready_checks
    can_recall = all(ready_checks.values())
    result["recall_from_write_with_errors"] = can_recall and bool(write["native_errors"])
    save(evidence / "recall-readiness.json", {
        "ready_checks": ready_checks, "can_recall": can_recall,
        "write_mechanical_pass": result["write_mechanical_pass"],
        "recall_from_write_with_errors": result["recall_from_write_with_errors"],
        "note": "Admission to a separate recall is not write/semantic success; original errors retained, no file repair.",
    })
    if not can_recall:
        result["recall_skipped"] = "Saved handoff/process checks failed; no repair or manufactured recall."
        result["mechanical_pass"] = False
        result["write_length_observation"] = {"all_visible": write["visible_characters"],
                                               "final": write["final_characters"],
                                               "normal_write_limit": 200,
                                               "exception_requires_human_review": True}
        save(evidence / "result.json", result)
        return result
    # Between-phase policy edits are DRIVER permission switches. This one is
    # explicit in evidence and precedes the recall baseline, not hidden as recall.
    if host == "opencode":
        permissions(project, "recall")
        checkpoint(project, evidence, "driver-recall-permission-switch")
    recall, text = phase_run(host, "recall", cmd["recall"], project, evidence, args.timeout)
    result["recall"] = recall
    if recall["permission_denials"]:
        result["semantic_status"] = "NOT_EVALUATED_HOST_PERMISSION_BLOCKED"
    checks.update(recall_process_success=succeeded(recall) and not recall["native_errors"],
                  recall_project_unchanged=not recall["changed_paths"],
                  recall_visible_text_observed=recall["visible_characters"] > 0,
                  recall_tool_events_observed=recall["tool_event_count"] > 0,
                  recall_stream_parseable=not recall["non_json_or_malformed_lines"],
                  recall_required_stages_proven=recall["required_stage_evidence"]["passed"],
                  recall_presentation_contract=recall["presentation_contract"]["passed"],
                  independent_session_ids_observed=len(write["session_ids"]) == 1 and
                    len(recall["session_ids"]) == 1 and
                    not set(write["session_ids"]) & set(recall["session_ids"]))
    # Use the post-write snapshot, not a possibly altered recall artifact.
    saved_main = (evidence / "snapshots/write-after/HANDOFFX.md").read_text(encoding="utf-8")
    saved_log = (evidence / "snapshots/write-after/Handoffx_Logs" / added[0]).read_text(encoding="utf-8")
    # Check the FINAL recall, never headings copied into intermediate messages.
    final_report = (evidence / "recall-final.txt").read_text(encoding="utf-8")
    heuristics = heuristic_checks(final_report, write, {"new_log": saved_log,
                                               "recent": block(saved_main, "recent") or ""})
    save(evidence / "heuristics-NOT-semantic-pass.json", heuristics)
    result["heuristics"] = heuristics
    result["mechanical_pass"] = all(checks.values())
    save(evidence / "result.json", result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", choices=tuple(HOST_ROOTS), action="append", required=True)
    parser.add_argument("--output", required=True, help="NEW directory under the current checkout's wip/")
    parser.add_argument("--source", default=str(CHECKOUT), help="HandoffX source containing install.sh and skills/")
    parser.add_argument("--timeout", type=float, default=420, help="Seconds per subprocess (default: 420)")
    parser.add_argument("--opencode-model", default="tkx/glm-5.3")
    parser.add_argument("--host-protection", choices=("inherited", "project-readonly"), default="inherited",
                        help="project-readonly: process-local Codex Serena disable and whole-host OpenCode read-only phases (macOS); no global config edits")
    parser.add_argument("--host-lifecycle", choices=("cold", "initialized"), default="cold",
                        help="initialized: separately record tool-free host bootstrap, then enforce full zero-change negative/recall checks")
    parser.add_argument("--entry-mode", choices=("path", "expanded"), default="path",
                        help="path: model reads skill; expanded: inject exact installed SKILL.md as headless entry (not native slash registration)")
    parser.add_argument("--prepare-only", action="store_true", help="Install + six real local tests only; NO model calls")
    args = parser.parse_args(argv)
    if not 0 < args.timeout < float("inf"):
        parser.error("--timeout must be finite and positive")
    if args.host_lifecycle == "initialized" and args.host_protection != "inherited":
        parser.error("initialized and project-readonly are separate host profiles; do not combine them")
    source = Path(args.source).expanduser().resolve()
    if not (source / "install.sh").is_file() or not (source / "skills/handoffx/SKILL.md").is_file():
        parser.error("--source must contain install.sh and skills/handoffx/SKILL.md")
    requested_output = Path(args.output).expanduser()
    if requested_output.exists() or requested_output.is_symlink():
        parser.error("--output already exists; refusing reuse or overwrite")
    base = requested_output.resolve()
    wip = (CHECKOUT / "wip").resolve()
    if base == wip or wip not in base.parents:
        parser.error("--output must be a NEW subdirectory of " + str(wip))
    if base.exists():
        parser.error("--output already exists; refusing reuse or overwrite")
    for exe in ["bash", "git"] + list(dict.fromkeys(args.host)):
        if not shutil.which(exe):
            parser.error("required executable is absent: " + exe)
    base.mkdir(parents=True, exist_ok=False)
    driver_bytes = Path(__file__).read_bytes()
    (base / "executed-driver.py").write_bytes(driver_bytes)
    save(base / "driver-version.json", {"sha256": hashlib.sha256(driver_bytes).hexdigest(),
         "source": str(Path(__file__).resolve()), "scope": "driver source at run startup"})
    put(base / "REVIEW-REQUIRED.md", REVIEW)
    source_manifest = {}
    for name in ("skills", "scripts"):
        if (source / name).is_dir():
            for key, value in snapshot(source / name, base / "source-snapshot" / name).items():
                source_manifest[name + "/" + key] = value
    data = (source / "install.sh").read_bytes()
    (base / "source-snapshot/install.sh").write_bytes(data)
    source_manifest["install.sh"] = {"sha256": hashlib.sha256(data).hexdigest()}
    save(base / "source-manifest.json", source_manifest)
    save(base / "run-info.json", {"source": str(source), "output": str(base), "hosts": args.host,
         "entry_scope": ENTRY_SCOPE, "entry_mode": args.entry_mode, "host_lifecycle": args.host_lifecycle, "host_protection": args.host_protection,
         "prepare_only": args.prepare_only, "timeout": args.timeout, "opencode_model": args.opencode_model,
         "auth_isolation": "ONLY installer HOME/XDG isolated; model processes inherit actual user HOME/auth environment; Codex retains user/provider config; NOT clean-home or clean-config isolation",
         "model_host_runtime": "TMPDIR/TMP/TEMP/NODE_COMPILE_CACHE -> each host evidence/host-runtime-<phase>; exact env and cache manifests recorded separately; full fixture/wip remains measured; sandbox unchanged",
         "semantic_status": "NOT_RUN" if args.prepare_only else "REQUIRES_HUMAN_REVIEW"})
    results = {}
    # Serial installations and host runs keep failures/evidence isolated. No agents.
    for host in dict.fromkeys(args.host):
        try:
            results[host] = run_host(host, args, base, source)
        except Exception as exc:
            results[host] = {"host": host, "error": repr(exc), "mechanical_pass": False,
                             "semantic_status": "INCOMPLETE_REQUIRES_REVIEW"}
            put(base / host / "evidence/driver-error.txt", traceback.format_exc())
        save(base / host / "evidence/result.json", results[host])
        save(base / "results.json", results)
        print(json.dumps(results[host], ensure_ascii=False), flush=True)
    return 0 if all(r["mechanical_pass"] for r in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
