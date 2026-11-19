#!/usr/bin/env python3
"""Offline synthetic contract tests. No host/model, credentials or network.

Run: python3 -B tests/test_roundtrip_contract.py
Temporary artifacts, if any, stay under this checkout's wip/.
"""
import importlib.util
import json
from pathlib import Path
import shlex
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("roundtrip_driver", ROOT / "tests/manual_handoff_roundtrip.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
PROJECT = ROOT / "wip/tmp/roundtrip-contract/synthetic-project"


def setUpModule():
    (ROOT / "wip").mkdir(parents=True, exist_ok=True)



def stream(*events, host="codex"):
    return driver.extract_events(b"\n".join(json.dumps(e).encode() for e in events), host)


def command_event(command, code=0, status="completed", kind="item.completed", output=""):
    return {"type": kind, "item": {"type": "command_execution", "id": "c1", "command": command,
                                     "status": status, "exit_code": code, "aggregated_output": output}}


def path(host="codex", name="handoff-runtime.sh"):
    return f"{driver.HOST_ROOTS[host]}/skills/handoffx/scripts/{name}"


def invoke(stage, host="codex"):
    name = "hx.sh" if stage == "regen" else "handoff-postflight.sh" if stage == "postflight" else "handoff-runtime.sh"
    return "bash " + path(host, name) + ("" if stage == "postflight" else " " + stage)


def stage_report(command, host="codex", output="", code=0, phase="write"):
    if host == "codex":
        events = stream(command_event(command, code, output=output))
    elif host == "claude":
        events = stream(
            {"type": "assistant", "message": {"content": [
                {"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": command}}]}},
            {"type": "user", "message": {"content": [
                {"type": "tool_result", "tool_use_id": "b1", "is_error": code != 0, "content": output}]}},
            host=host)
    else:
        events = stream({"type": "tool_use", "part": {"type": "tool", "id": "o1", "tool": "shell",
            "state": {"status": "completed", "input": {"command": command}, "output": output,
                      "metadata": {"metadata": {"exit": code}}}}}, host=host)
    return driver.required_stage_evidence(events["executions"], host, PROJECT, phase)


def presentation(*texts, phase="write", errors=()):
    events = {"texts": [{"line": n + 1, "text": text} for n, text in enumerate(texts)],
              "final": texts[-1] if texts else "", "errors": list(errors), "permission_denials": []}
    return driver.presentation_contract(events, phase)


TAIL = "## 从这里继续\n\n### 上次停在哪里\n已保存。\n### 下一步\n等待样本。\n### 当前TODO\n- [ ] TASK-OLD：等待样本。\n"


class HostProtectionTests(unittest.TestCase):
    def test_process_local_profile_preserves_native_flags_and_original_commands(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "wip") as temp:
            evidence = Path(temp)
            commands = {phase: ["/bin/host", "--sandbox", "read-only", "--ask-for-approval", "never", "prompt"]
                        for phase in ("wrong-root", "write", "recall")}
            for host in ("codex", "claude"):
                protected = driver.protect_commands(host, commands, PROJECT, evidence)
                for phase, argv in protected.items():
                    self.assertIn("read-only", argv)
                    self.assertIn("never", argv)
                    self.assertNotIn("danger-full-access", argv)
                    self.assertNotIn("--yolo", argv)
                    if host == "codex":self.assertIn("mcp_servers.serena.enabled=false", argv)
                    else:self.assertEqual(argv, commands[phase])
                self.assertNotIn("-c", commands["write"])

    def test_opencode_protects_only_readonly_phases_and_never_falls_back(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "wip") as temp:
            commands = {phase: ["opencode", "run", "--standalone", "prompt"]
                        for phase in ("wrong-root", "write", "recall")}
            with mock.patch.object(driver.shutil, "which", return_value="/usr/bin/sandbox-exec"):
                result = driver.protect_commands("opencode", commands, PROJECT, Path(temp))
            self.assertEqual(result["write"], commands["write"])
            for phase in ("wrong-root", "recall"):
                self.assertEqual(result[phase][0], "/usr/bin/sandbox-exec")
                self.assertIn("PROJECT=" + str(PROJECT), result[phase])
                self.assertEqual(result[phase][-4:], commands[phase])
            with mock.patch.object(driver.shutil, "which", return_value=None):
                with self.assertRaises(RuntimeError):
                    driver.protect_commands("opencode", commands, PROJECT, Path(temp))


class BootstrapTests(unittest.TestCase):
    def bootstrap(self, mutation, tool=False, symlink=False, existing=False):
        with tempfile.TemporaryDirectory(dir=ROOT / "wip") as temp:
            project = Path(temp) / "project"
            evidence = Path(temp) / "evidence"
            project.mkdir(); evidence.mkdir()
            (project / "HANDOFFX.md").write_text("protected original")
            if existing:
                (project / ".serena").mkdir()
                (project / ".serena/project.yml").write_text("existing protected config")
            def execute(command, root, out, label, timeout, env=None):
                target = project / mutation
                target.parent.mkdir(parents=True, exist_ok=True)
                if symlink:
                    target.symlink_to(evidence)
                else:
                    target.write_text("host initialization")
                events = [{"type": "thread.started", "thread_id": "bootstrap-independent"},
                          {"type": "item.completed", "item": {"type": "agent_message", "text": "HOST_READY"}}]
                if tool:
                    events.append(command_event("pwd"))
                (out / "bootstrap.stdout.jsonl").write_text("\n".join(json.dumps(x) for x in events))
                return {"exit_code": 0, "timeout": False}
            with mock.patch.object(driver, "execute", side_effect=execute):
                return driver.bootstrap_host("codex", ["codex", "original prompt"], project, evidence, 1)

    def test_host_initialization_is_recorded_and_does_not_exempt_later_snapshots(self):
        report = self.bootstrap(".serena/project.yml")
        self.assertTrue(report["passed"])
        self.assertIn(".serena/project.yml", report["changed_paths"])
        self.assertIn("cold-start", report["not_proven"])
        self.assertTrue(driver.changed({".serena/project.yml": {"sha256": "old"}},
                                       {".serena/project.yml": {"sha256": "new"}}))

    def test_bootstrap_rejects_links_and_existing_state_mutation(self):
        self.assertFalse(self.bootstrap(".serena", symlink=True)["passed"])
        self.assertFalse(self.bootstrap(".serena/link", symlink=True)["passed"])
        self.assertFalse(self.bootstrap(".serena/project.yml", existing=True)["passed"])

    def test_bootstrap_cannot_modify_protected_handoff_or_call_tools(self):
        self.assertFalse(self.bootstrap("HANDOFFX.md")["passed"])
        self.assertFalse(self.bootstrap(".serena/project.yml", tool=True)["passed"])


class ContextArgumentsTests(unittest.TestCase):
    def test_wrong_root_help_duplicate_and_unknown_options_never_prove_context(self):
        for host in driver.HOST_ROOTS:
            for options in ("--help", "--root /elsewhere --skill-root /elsewhere/skill", "--root",
                            "--root " + str(PROJECT) + " --root " + str(PROJECT), "--unknown value"):
                with self.subTest(host=host, options=options):
                    result = stage_report(invoke("context", host) + " " + options, host)
                    self.assertNotEqual(result["stages"]["context"]["status"], "passed")

    def test_supported_literal_context_options(self):
        for host in driver.HOST_ROOTS:
            options = " --root " + str(PROJECT) + " --skill-root " + str(PROJECT / driver.HOST_ROOTS[host] / "skills/handoffx")
            self.assertEqual(stage_report(invoke("context", host) + options, host)["stages"]["context"]["status"], "passed")


class NativeEventsTests(unittest.TestCase):
    def test_codex_configuration_notice_is_not_a_model_tool_call(self):
        text = "Codex is ignoring 1 unrecognized configuration setting. Check for typos or deprecated settings.\n  user (config.toml): `obsolete_option` is ignored."
        events = stream({"type": "item.completed", "item": {"type": "error", "message": text}})
        self.assertFalse(events["tool_lines"])
        self.assertFalse(events["errors"])
        self.assertEqual(events["host_messages"][0]["text"], text)
        for message in ("Fatal: cannot execute", "Codex is ignoring 1 unrecognized configuration setting. unrelated", None):
            events = stream({"type": "item.completed", "item": {"type": "error", "message": message}})
            self.assertTrue(events["errors"])
            self.assertFalse(events["tool_lines"])


    def test_codex_unknown_terminal_is_fail_closed(self):
        for status, code in (("completed", None), ("declined", None), ("unexpected", 0),
                             (None, 0), ("completed", False), ("completed", "0")):
            with self.subTest(status=status, code=code):
                events = stream(command_event(invoke("context"), code, status))
                self.assertTrue(events["errors"])
                self.assertEqual(events["non_json_or_malformed_lines"], [1])
                self.assertEqual(events["executions"][0]["outcome"], "unknown")

    def test_codex_explicit_failed_nonzero_is_parseable_failure_not_success(self):
        for kind in ("item.completed", "item.failed"):
            events = stream(command_event(invoke("context"), 2, "failed", kind))
            self.assertFalse(events["non_json_or_malformed_lines"])
            self.assertTrue(events["errors"])
            classifications = set(events["errors"][0]["classifications"])
            self.assertIn("native_command_exit_nonzero", classifications)
            self.assertIn("native_tool_error", classifications)
            self.assertNotIn("native_command_terminal_unknown", classifications)
            self.assertEqual(events["executions"][0]["outcome"], "failed")
            report = driver.required_stage_evidence(events["executions"], "codex", PROJECT, "write")
            self.assertEqual(report["stages"]["context"]["status"], "failed")
            self.assertFalse(report["passed"])
        for code in (0, None, False, "2"):
            events = stream(command_event(invoke("context"), code, "failed"))
            self.assertTrue(events["non_json_or_malformed_lines"])
            self.assertTrue(events["errors"])
            self.assertNotEqual(events["executions"][0]["outcome"], "passed")

    def test_codex_normal_started_is_not_failure(self):
        events = stream(command_event(invoke("context"), None, "in_progress", "item.started"))
        self.assertFalse(events["errors"])
        self.assertFalse(events["non_json_or_malformed_lines"])
        self.assertFalse(events["executions"])

    def test_codex_nonzero_survives_success_envelope(self):
        events = stream(command_event(invoke("context"), 7), {"type": "turn.completed"})
        self.assertIn("native_command_exit_nonzero", events["errors"][0]["classifications"])
        self.assertEqual(events["executions"][0]["outcome"], "failed")

    def test_claude_background_launch_is_not_completed_stage(self):
        for operation in ("regen", "postflight", "finalize"):
            command = finalize("claude") if operation == "finalize" else invoke(operation, "claude")
            events = stream({"type": "assistant", "message": {"content": [
                {"type": "tool_use", "id": "b1", "name": "Bash", "input": {
                    "command": command, "run_in_background": True}}]}},
                {"type": "user", "message": {"content": [
                    {"type": "tool_result", "tool_use_id": "b1", "is_error": False,
                     "content": "Command running in background with ID: x"}]}}, host="claude")
            self.assertEqual(events["executions"][0]["outcome"], "unknown")
            report = driver.required_stage_evidence(events["executions"], "claude", PROJECT, "write")
            self.assertFalse(any(v["status"] == "passed" for v in report["stages"].values()))

    def test_background_status_reporter_cannot_restore_completion_proof(self):
        command = invoke("regen", "claude") + "; echo exit=$?"
        events = stream({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "b1",
            "name": "Bash", "input": {"command": command, "run_in_background": True}}]}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "b1",
             "is_error": False, "content": "exit=0\n"}]}}, host="claude")
        report = driver.required_stage_evidence(events["executions"], "claude", PROJECT, "write")
        self.assertEqual(report["stages"]["regen"]["status"], "unknown")

    def test_claude_result_background_ack_is_unknown_without_request_flag(self):
        # Auto-background results cannot certify completion, even with a numeric
        # zero exit or an adjacent status reporter. Known keys/prefix only.
        variants = [({"backgroundTaskId": "task-1"}, "exit=0\n"),
                    ({"background_task_id": "task-1"}, "exit=0\n"),
                    ({}, "Command running in background with ID: task-1\nexit=0\n")]
        for operation in ("regen", "postflight", "finalize"):
            for native, text in variants:
                for error in (False, True):
                    for reporter in ("", "; echo exit=$?"):
                        with self.subTest(operation=operation, native=native, text=text, error=error, reporter=reporter):
                            command = finalize("claude") if operation == "finalize" else invoke(operation, "claude")
                            events = stream({"type": "assistant", "message": {"content": [{
                                "type": "tool_use", "id": "b1", "name": "Bash",
                                "input": {"command": command + reporter}}]}},
                                {"type": "user", "message": {"content": [{"type": "tool_result",
                                 "tool_use_id": "b1", "is_error": error, "content": text}]},
                                 "tool_use_result": dict(native, stdout="exit=0\n", exit_code=0)}, host="claude")
                            self.assertEqual(events["executions"][0]["outcome"], "unknown")
                            report = driver.required_stage_evidence(events["executions"], "claude", PROJECT, "write")
                            self.assertFalse(any(v["status"] == "passed" for v in report["stages"].values()))
                            if error:
                                self.assertTrue(events["errors"])

    def test_claude_background_text_not_fuzzy_matched(self):
        events = stream({"type": "assistant", "message": {"content": [{"type": "tool_use",
            "id": "b1", "name": "Bash", "input": {"command": invoke("regen", "claude")}}]}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "b1",
             "is_error": False, "content": "No Command running in background; completed."}]},
             "tool_use_result": {"stdout": "completed", "background_note": "unrelated text"}}, host="claude")
        self.assertEqual(events["executions"][0]["outcome"], "passed")

    def test_claude_requires_pair_and_explicit_result_flag(self):
        result = {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "b1", "content": "context passed"}]}}
        self.assertFalse(stream(result, host="claude")["executions"])
        call = {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": invoke("context", "claude")}}]}}
        for data in ((call,), (call, result)):
            self.assertEqual(stream(*data, host="claude")["executions"][0]["outcome"], "unknown")

    def test_claude_denial_string_and_error_result_survive(self):
        events = stream({"type": "system", "subtype": "permission_denied", "tool_use_id": "b1",
                         "message": "Denied"},
                        {"type": "user", "message": {"content": [
                            {"type": "tool_result", "tool_use_id": "b1", "is_error": True}]}}, host="claude")
        self.assertTrue(events["permission_denials"])
        self.assertEqual(events["host_messages"][0]["text"], "Denied")
        self.assertIn("host_permission_denied", events["errors"][-1]["classifications"])

    def test_opencode_unknown_exit_is_not_success(self):
        event = {"type": "tool_use", "part": {"type": "tool", "tool": "shell", "state": {
            "status": "completed", "input": {"command": invoke("context", "opencode")}}}}
        self.assertEqual(stream(event, host="opencode")["executions"][0]["outcome"], "unknown")

    def test_assistant_self_report_is_not_native_denial(self):
        events = stream({"type": "item.completed", "item": {"type": "agent_message", "text": "命令被安全策略拒绝"}})
        self.assertFalse(events["errors"])
        self.assertFalse(events["permission_denials"])
        self.assertFalse(events["executions"])


class StageTests(unittest.TestCase):
    def test_postflight_requires_canonical_main_target(self):
        # Real candidate-3 CLI: other.md passes even when HANDOFFX.md is invalid.
        for host in driver.HOST_ROOTS:
            for args in (" --brief other.md", " HANDOFFX.md other.md", " other.md HANDOFFX.md"):
                with self.subTest(host=host, args=args):
                    self.assertNotEqual(stage_report(invoke("postflight", host) + args, host)
                                        ["stages"]["postflight"]["status"], "passed")
            for args in ("", " --brief HANDOFFX.md", " --quiet HANDOFFX.md --files=taskboard.py"):
                self.assertEqual(stage_report(invoke("postflight", host) + args, host)
                                 ["stages"]["postflight"]["status"], "passed")

    def test_redirect_only_segment_is_unknown_not_a_crash(self):
        for host in ("codex", "claude", "opencode"):
            report = stage_report(invoke("regen", host) + '; > /dev/null', host=host)
            self.assertNotEqual(report["stages"]["regen"]["status"], "passed")
            self.assertTrue(report["unsupported_commands"])

    def test_errexit_is_not_a_cross_host_native_exit_proof(self):
        for host in ("codex", "claude", "opencode"):
            cmd = 'set -e; ' + invoke("regen", host) + '; true'
            self.assertNotEqual(stage_report(cmd, host=host)["stages"]["regen"]["status"], "passed")

    def test_ifs_assignment_cannot_disguise_postflight_help(self):
        for host in ("codex", "claude", "opencode"):
            cmd = 'IFS=,; F=--files=a,--help; ' + invoke("postflight", host) + ' $F'
            self.assertNotEqual(stage_report(cmd, host=host)["stages"]["postflight"]["status"], "passed")

    def test_printf_assignment_and_unknown_variables_are_not_proof(self):
        for host in ("codex", "claude", "opencode"):
            for prefix in ('printf -v F %s --help; ', ''):
                cmd = prefix + invoke("postflight", host) + ' $F'
                self.assertNotEqual(stage_report(cmd, host=host)["stages"]["postflight"]["status"], "passed")

    def test_expanding_outer_shell_cannot_prove_reporter_status(self):
        for host in ("codex", "claude", "opencode"):
            cmd = 'bash -c "' + invoke("regen", host) + '; echo r=$?"'
            report = stage_report(cmd, host=host, output="r=0\n")
            self.assertNotEqual(report["stages"]["regen"]["status"], "passed")
            self.assertTrue(report["unsupported_commands"])

    def test_shell_expansion_cannot_disguise_postflight_help(self):
        for host in ("codex", "claude", "opencode"):
            for suffix in (" -{h,h}", " --hel?", " --hel[p]", " --hel*"):
                with self.subTest(host=host, suffix=suffix):
                    report = stage_report(invoke("postflight", host) + suffix, host=host)
                    self.assertNotEqual(report["stages"]["postflight"]["status"], "passed")

    def test_word_split_option_cannot_disguise_postflight_help(self):
        for host in ("codex", "claude", "opencode"):
            for flags in ("--help --brief", "x --help", "--files=x --help"):
                with self.subTest(host=host, flags=flags):
                    cmd = 'FLAGS="' + flags + '"; ' + invoke("postflight", host) + ' $FLAGS'
                    report = stage_report(cmd, host=host)
                    self.assertNotEqual(report["stages"]["postflight"]["status"], "passed")

    def test_hash_comments_cannot_mask_or_invent_stage_execution(self):
        for host in ("codex", "claude", "opencode"):
            cmd = invoke("regen", host)
            for shell in (cmd + " # note\ntrue", cmd + "#x; true", "true # ; " + cmd):
                with self.subTest(host=host, command=shell):
                    report = stage_report(shell, host=host)
                    self.assertNotEqual(report["stages"]["regen"]["status"], "passed")
                    self.assertTrue(report["unsupported_commands"])

    def test_compound_punctuation_cannot_prove_stage_success(self):
        for host in ("codex", "claude", "opencode"):
            for suffix in (" |& cat", " &|", " >| /dev/null", " ;& true", " &> /dev/null"):
                with self.subTest(host=host, suffix=suffix):
                    report = stage_report(invoke("regen", host) + suffix, host=host)
                    self.assertNotEqual(report["stages"]["regen"]["status"], "passed")
                    self.assertTrue(report["unsupported_commands"])

    def test_help_is_not_a_postflight_check(self):
        for host in ("codex", "claude", "opencode"):
            for option in ("--help", "-h", "--brief --help"):
                report = stage_report(invoke("postflight", host) + " " + option, host)
                self.assertEqual(report["stages"]["postflight"]["status"], "unknown")

    def test_all_hosts_all_required_stages(self):
        for host in driver.HOST_ROOTS:
            with self.subTest(host=host):
                report = stage_report(" && ".join(invoke(s, host) for s in
                                      ("context", "regen", "recall", "postflight", "reply")), host)
                self.assertTrue(report["passed"], report)
                if host == "claude":
                    self.assertIsNone(report["stages"]["context"]["evidence"][0]["native_exit_code"])

    def test_started_only_or_empty_never_passes(self):
        report = driver.required_stage_evidence([], "codex", PROJECT, "write")
        self.assertFalse(report["passed"])
        self.assertEqual({s["status"] for s in report["stages"].values()}, {"unknown"})

    def test_reading_docs_or_printing_commands_is_not_execution(self):
        examples = ["cat " + path(), "echo " + shlex.quote(invoke("context")),
                    "printf '%s\\n' " + shlex.quote(invoke("regen")),
                    "python3 -c " + shlex.quote("print('" + invoke("context") + "')"),
                    "cat <<'EOF'\n" + invoke("context") + "\nEOF",
                    "echo ';' " + invoke("context") + " ';' echo exit=$?",
                    "true # " + invoke("context")]
        for command in examples:
            with self.subTest(command=command):
                report = stage_report(command, output="exit=0\ncontext=ok\n")
                self.assertFalse(any(s["status"] == "passed" for s in report["stages"].values()))

    def test_wrong_installation_path_not_evidence(self):
        for command in ("bash /other/handoff-runtime.sh context", "bash /other/hx.sh regen"):
            self.assertFalse(any(s["status"] == "passed" for s in stage_report(command)["stages"].values()))

    def test_set_e_simple_list_and_codex_envelope(self):
        body = "set -e\n" + invoke("regen") + "\n" + invoke("recall") + ' "" >/dev/null'
        report = stage_report("/bin/zsh -lc " + shlex.quote(body))
        self.assertEqual(report["stages"]["regen"]["status"], "unknown", report)
        self.assertEqual(report["stages"]["recall"]["status"], "passed", report)
        self.assertIn("final unconditional", report["stages"]["recall"]["evidence"][0]["basis"])

    def test_export_prefix_is_not_shell_state_proof(self):
        report = stage_report('export TMPDIR="$PWD/wip/tmp"\n' + invoke("postflight"))
        self.assertEqual(report["stages"]["postflight"]["status"], "unknown")

    def test_complex_shell_never_claims_set_e_certifies_children(self):
        for command in ("set -e; f() { " + invoke("regen") + "; }; f || true",
                        "set -e; if false; then " + invoke("regen") + "; fi",
                        "set -e; " + invoke("regen") + " || true",
                        "bash -n " + path("codex", "hx.sh") + " regen",
                        "bash -c " + shlex.quote("set -e; f() { " + invoke("regen") + "; }; f")):
            with self.subTest(command=command):
                self.assertNotEqual(stage_report(command)["stages"]["regen"]["status"], "passed")

    def test_masked_failure_does_not_prove_stage_success(self):
        for command in (invoke("regen") + "; true", invoke("regen") + "; echo exit=0",
                        invoke("regen") + "; echo 'exit=$?'", invoke("regen") + '; echo "exit=\\$?"',
                        invoke("regen") + " && true; true", "set +e; " + invoke("regen")):
            with self.subTest(command=command):
                self.assertEqual(stage_report(command, output="exit=0\n")["stages"]["regen"]["status"], "unknown")

    def test_adjacent_status_reporter(self):
        for host in driver.HOST_ROOTS:
            for reporter in ('echo "exit=$?"', "printf 'exit=%s\\n' $?"):
                command = invoke("recall", host) + ' "" >/dev/null; ' + reporter
                for code in (0, 3):
                    with self.subTest(host=host, reporter=reporter, code=code):
                        report = stage_report(command, host, output=f"exit={code}\n")
                        self.assertEqual(report["stages"]["recall"]["status"], "passed" if code == 0 else "failed")

    def test_ambiguous_status_output_unknown(self):
        command = invoke("regen") + '; echo "exit=$?"'
        for output in ("", "exit=unknown\n", "exit=0\nexit=1\n", "documentation exit=0"):
            self.assertEqual(stage_report(command, output=output)["stages"]["regen"]["status"], "unknown")

    def test_literal_variable_not_expanded(self):
        command = "S=" + str(PROJECT / driver.HOST_ROOTS['codex'] / 'skills/handoffx/scripts')
        for quote in ("'", '"'):
            report = stage_report(command + "; bash " + quote + "$S/hx.sh" + quote + ' regen; echo "exit=$?"', output="exit=0\n")
            self.assertEqual(report["stages"]["regen"]["status"], "unknown")

    def test_project_binding_and_global_expect_root(self):
        for operation in ("context", "recall", "reply"):
            command = f"bash {path()} --expect-root {shlex.quote(str(PROJECT))} {operation}"
            self.assertEqual(stage_report(command)["stages"][operation]["status"], "passed")
        for name, operation in (("hx.sh", "regen"), ("handoff-postflight.sh", "")):
            command = f"bash {path(name=name)} --expect-root {shlex.quote(str(PROJECT))} {operation}"
            stage = operation or "postflight"
            self.assertEqual(stage_report(command)["stages"][stage]["status"], "passed")
        wrong = f"bash {path()} --expect-root /elsewhere context"
        self.assertEqual(stage_report(wrong)["stages"]["context"]["status"], "unknown")
        misplaced = f"bash {path()} context --expect-root {shlex.quote(str(PROJECT))}"
        # Native zero alone cannot make an invalid global-option position valid.
        self.assertNotEqual(stage_report(misplaced)["stages"]["context"]["status"], "passed")

    def test_recall_requires_only_context_and_recall(self):
        report = stage_report(invoke("context") + " && " + invoke("recall"), phase="recall")
        self.assertTrue(report["passed"])
        self.assertEqual(set(report["stages"]), {"context", "recall"})


def finalize(host="codex", extra=""):
    return (f"bash {path(host)} --expect-root {shlex.quote(str(PROJECT))} "
            "finalize --log Handoffx_Logs/0009-entry.md" + extra)


class FinalizeTests(unittest.TestCase):
    def test_native_finalize_composes_four_stages_but_not_context(self):
        for host in driver.HOST_ROOTS:
            with self.subTest(host=host):
                report = stage_report(finalize(host), host)
                self.assertFalse(report["passed"])
                self.assertEqual(report["stages"]["context"]["status"], "unknown")
                for stage in ("regen", "recall", "postflight", "reply"):
                    self.assertEqual(report["stages"][stage]["status"], "passed")
                    self.assertEqual(report["stages"][stage]["evidence"][0]["entrypoint"], "finalize")
                self.assertTrue(stage_report(invoke("context", host) + " && " + finalize(host), host)["passed"])
                self.assertFalse(stage_report(finalize(host), host, phase="recall")["passed"])

    def test_strict_literal_arguments(self):
        for host in driver.HOST_ROOTS:
            for suffix in ("", " --files=taskboard.py,tests/test_taskboard.py"):
                self.assertEqual(stage_report(finalize(host, suffix), host)["stages"]["reply"]["status"], "passed")
            base = finalize(host)
            invalid = [base.replace("--expect-root " + shlex.quote(str(PROJECT)) + " ", ""),
                       base.replace(str(PROJECT), "/wrong"),
                       base.replace(str(PROJECT), "relative/project"),
                       base.replace("finalize --log", "--help finalize --log"),
                       base.replace("--log Handoffx_Logs/0009-entry.md", "--log"),
                       base.replace("--log Handoffx_Logs/0009-entry.md", "--log=Handoffx_Logs/0009-entry.md")]
            for log in ("/tmp/0009-entry.md", "Handoffx_Logs/../0009-entry.md", "Handoffx_Logs/archive/0009-entry.md",
                        "Handoffx_Logs/not-numbered.md", "./Handoffx_Logs/0009-entry.md", "Handoffx_Logs/0009-a,b.md"):
                invalid.append(base.replace("Handoffx_Logs/0009-entry.md", log))
            invalid.extend(base + suffix for suffix in (
                " --help", " --unknown", " extra", " --log Handoffx_Logs/0010-entry.md",
                " --expect-root " + shlex.quote(str(PROJECT)), " --files=", " --files=a,,b",
                " --files=a,", " --files=,a", " --files=../x", " --files=/tmp/x",
                " --files=./x", " --files=a/../x", " --files=a//x", " --files=a --files=b",
                " --files a", " --files='$FILES'", ' --files="a b"'))
            for command in invalid:
                with self.subTest(host=host, command=command):
                    self.assertFalse(any(v["status"] == "passed" for v in stage_report(command, host)["stages"].values()))

    def test_native_failure_unknown_or_printed_marker_never_proves_finalize(self):
        for host in driver.HOST_ROOTS:
            self.assertEqual(stage_report(finalize(host), host, output="regen=ok\nreply=ok\n", code=7)
                             ["stages"]["regen"]["status"], "failed")
            for command in ("echo " + shlex.quote(finalize(host)),
                            "cat " + path(host), finalize(host) + "; true",
                            finalize(host) + "; echo exit=$?", "set -e; " + finalize(host) + " || true",
                            "unknown && " + finalize(host), "cd /wrong && " + finalize(host),
                            finalize(host) + " | cat", "if true; then " + finalize(host) + "; fi",
                            finalize(host) + " # marker\ntrue"):
                with self.subTest(host=host, command=command):
                    self.assertNotEqual(stage_report(command, host, output="exit=0\nfinalize=ok\n")
                                        ["stages"]["regen"]["status"], "passed")
        report = stage_report(finalize(), code=None)
        self.assertEqual(report["stages"]["reply"]["status"], "unknown")


class ReplyConsistencyTests(unittest.TestCase):
    def check(self, command, actual, output, host="codex", code=0):
        stages = stage_report(command, host, output=output, code=code)
        return driver.reply_consistency({"final": actual, "tool_event_lines": []}, stages)

    def test_actual_final_equals_reply_or_finalize_output_all_hosts(self):
        for host in driver.HOST_ROOTS:
            for final, command in (("已保存，检查通过。", invoke("reply", host) + " --text 已保存，检查通过。"),
                                   (driver.FINALIZE_REPLY, finalize(host))):
                with self.subTest(host=host, command=command):
                    report = self.check(command, final, "diagnostic on merged stderr\n" + final + "\n", host)
                    self.assertEqual(report["status"], "passed")
                    self.assertEqual(report["actual_final"], final)
                    self.assertEqual(report["runtime_reply"], final)

    def test_any_later_tool_invalidates_confirmation_all_hosts(self):
        text = driver.FINALIZE_REPLY
        for host in driver.HOST_ROOTS:
            if host == "codex":
                raw = [command_event(finalize(host), output=text)]
                later = {"type": "item.completed", "item": {"type": "file_change", "status": "completed",
                         "changes": [{"path": "HANDOFFX_GOTCHAS.md", "kind": "update"}]}}
            elif host == "claude":
                raw = [{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "b1",
                        "name": "Bash", "input": {"command": finalize(host)}}]}},
                       {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "b1",
                        "is_error": False, "content": text}]}}]
                later = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "edit1",
                         "name": "Edit", "input": {"file_path": "HANDOFFX_GOTCHAS.md", "new_string": "changed"}}]}}
            else:
                raw = [{"type": "tool_use", "part": {"type": "tool", "tool": "shell", "state": {
                    "status": "completed", "input": {"command": finalize(host)}, "output": text,
                    "metadata": {"exit": 0}}}}]
                later = {"type": "tool_use", "part": {"type": "tool", "tool": "edit", "state": {
                    "status": "completed", "input": {"filePath": "HANDOFFX_GOTCHAS.md"}}}}
            for trailing in (later, command_event("echo later") if host == "codex" else later):
                events = stream(*raw, trailing, host=host)
                events["final"] = text
                stages = driver.required_stage_evidence(events["executions"], host, PROJECT, "write")
                self.assertEqual(driver.reply_consistency(events, stages)["status"], "failed")

    def test_short_checked_reply_cannot_license_expanded_final(self):
        checked = "验" * 85
        for host in driver.HOST_ROOTS:
            for command in (invoke("reply", host) + " --text " + checked, finalize(host)):
                for actual in (checked + "额外说明", checked + "扩" * 40, " " + checked, checked + "\n"):
                    with self.subTest(host=host, length=len(actual)):
                        self.assertEqual(self.check(command, actual, checked + "\n", host)["status"], "failed")

    def test_missing_masked_redirected_unisolated_output_unknown(self):
        for command, output, code in ((finalize(), "", 0), (finalize(), "ok\n", 1),
                                      (finalize() + " >/dev/null", "ok\n", 0),
                                      (finalize() + " && echo ok", "ok\n", 0),
                                      (finalize() + "; echo exit=$?", "exit=0\nok\n", 0),
                                      ("echo ok", "ok\n", 0)):
            with self.subTest(command=command):
                self.assertEqual(self.check(command, "ok", output, code=code)["status"], "unknown")

    def test_reply_arguments_must_match_not_just_any_output(self):
        self.assertEqual(self.check(invoke("reply") + " --text checked", "other", "other\n")["status"], "failed")
        self.assertEqual(self.check(invoke("reply"), "ok", "ok\n")["status"], "failed")
        self.assertEqual(self.check(finalize(), "字" * 121, "字" * 121 + "\n")["status"], "failed")



class WrongRootModelTests(unittest.TestCase):
    def events(self, host, cwd=None, code=2, command=None):
        command = command or driver.wrong_root_command(PROJECT, host)
        cwd = str(driver.wrong_project_directory(PROJECT)) if cwd is None else cwd
        output = cwd + "\nhandoffx context: cwd does not match EXPECTED_ROOT\n"
        if host == "codex":
            return stream(command_event(command, code, output=output))
        if host == "claude":
            return stream({"type": "assistant", "message": {"content": [
                {"type": "tool_use", "id": "b1", "name": "Bash", "input": {"command": command}}]}},
                {"type": "user", "message": {"content": [
                    {"type": "tool_result", "tool_use_id": "b1", "is_error": code != 0}]},
                 "tool_use_result": {"exit_code": code, "stdout": cwd + "\n", "stderr": "cwd does not match EXPECTED_ROOT"}},
                host=host)
        return stream({"type": "tool_use", "part": {"type": "tool", "tool": "shell", "state": {
            "status": "completed", "input": {"command": command}, "output": output,
            "metadata": {"exit": code}}}}, host=host)

    def test_three_hosts_require_same_call_pwd_native_rejection(self):
        for host in driver.HOST_ROOTS:
            with self.subTest(host=host):
                report = driver.wrong_root_evidence(self.events(host), host, PROJECT)
                self.assertTrue(report["passed"], report)
                self.assertEqual(report["evidence_kind"], "MODEL_NATIVE_TOOL_WRONG_ROOT")
                self.assertNotEqual(report["actual_tool_cwd"], str(PROJECT))
                wrong = driver.wrong_project_directory(PROJECT)
                self.assertIn(PROJECT, wrong.parents)
                self.assertNotIn(["cd", str(PROJECT.parent)],
                                 driver.shell_segments(driver.wrong_root_command(PROJECT, host))[0])

    def test_wrong_root_native_exit_must_be_exact_integer_two(self):
        for host in driver.HOST_ROOTS:
            for code in (1, 127, None, True, "2"):
                with self.subTest(host=host, code=code):
                    report = driver.wrong_root_evidence(self.events(host, code=code), host, PROJECT)
                    self.assertFalse(report["passed"], report)
                    self.assertFalse(report["checks"]["native_runtime_rejected"])

    def test_auto_selected_project_root_never_passes_even_with_error_marker(self):
        for host in driver.HOST_ROOTS:
            report = driver.wrong_root_evidence(self.events(host, cwd=str(PROJECT)), host, PROJECT)
            self.assertFalse(report["passed"])
            self.assertFalse(report["checks"]["actual_tool_cwd_not_project_root"])

    def test_missing_cwd_success_echo_spoof_extra_command_and_denial_fail(self):
        for host in driver.HOST_ROOTS:
            for events in (self.events(host, cwd=""), self.events(host, code=0),
                           self.events(host, command="echo 'cwd does not match EXPECTED_ROOT'"),
                           self.events(host, command=driver.wrong_root_command(PROJECT, host) + "; true")):
                self.assertFalse(driver.wrong_root_evidence(events, host, PROJECT)["passed"])
            events = self.events(host)
            events["permission_denials"].append({"line": 1})
            self.assertFalse(driver.wrong_root_evidence(events, host, PROJECT)["passed"])
            events = self.events(host)
            events["executions"].append(dict(events["executions"][0]))
            self.assertFalse(driver.wrong_root_evidence(events, host, PROJECT)["passed"])

    def test_claude_observed_failure_envelope_only_is_unwrapped(self):
        # Shape copied from real Claude 2.1.312 wrong-root event (2026-11-17
        # local run); only fixture paths/session IDs are replaced. Both native
        # envelopes must agree. Do not search arbitrary text for a plausible pwd.
        cwd = str(driver.wrong_project_directory(PROJECT))
        body = "Exit code 2\n" + cwd + "\nhandoffx context: cwd does not match EXPECTED_ROOT"
        call = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "native1",
                "name": "Bash", "input": {"command": driver.wrong_root_command(PROJECT, "claude")}}]}}
        result = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result",
                  "content": body, "is_error": True, "tool_use_id": "native1"}]},
                  "tool_use_result": "Error: " + body}
        events = stream(call, result, host="claude")
        report = driver.wrong_root_evidence(events, "claude", PROJECT)
        self.assertTrue(report["passed"], report)
        self.assertEqual(report["actual_tool_cwd"], cwd)
        self.assertTrue(events["errors"])
        self.assertEqual(events["executions"][0]["output"], body)  # Raw output unchanged.
        for envelope in (None, "Error: different", "Error: " + body.replace("Exit code 2", "Exit code 0")):
            result["tool_use_result"] = envelope
            self.assertFalse(driver.wrong_root_evidence(stream(call, result, host="claude"), "claude", PROJECT)["passed"])

    def test_driver_negative_real_runtime_requires_root_mismatch(self):
        temp_root = ROOT / "wip/tmp"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="iteration-closeout-real-runtime-", dir=temp_root) as directory:
            base = Path(directory)
            project, evidence = base / "project", base / "evidence"
            evidence.mkdir()
            driver.seed(project)
            skill = project / ".agents/skills/handoffx"
            shutil.copytree(ROOT / "skills/handoffx", skill)
            (skill / ".handoffx-install-context").write_text(
                f"schema=1\nscope=project\nproject_root={project}\nskill_root={skill}\nhost=codex\n")
            report = driver.wrong_project_check(project, evidence, skill, 10)
            self.assertTrue(report["passed"], report)
            self.assertTrue(report["checks"]["root_mismatch_diagnostic"])
            self.assertEqual(report["changed_paths"], [])

    def test_wrong_root_permission_only_exact_readonly_commands(self):
        temp_root = ROOT / "wip/tmp"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="iteration-closeout-permission-test-", dir=temp_root) as directory:
            project = Path(directory)
            driver.permissions(project, "wrong-root")
            config = json.loads((project / "opencode.json").read_text())["permission"]
            command = driver.wrong_root_command(project, "opencode")
            children = [shlex.join(segment) for segment in driver.shell_segments(command)[0]]
            for tool in ("shell", "bash"):
                granted = {k for k,v in config[tool].items() if v == "allow"}
                self.assertEqual(granted, {command, *children})
                self.assertEqual(config[tool]["*"], "deny")
                self.assertFalse(any("*" in k or k.startswith("cd ") for k in granted))
            self.assertEqual(config["external_directory"], "deny")
            self.assertEqual(config["edit"], "deny")
            self.assertEqual(config["write"], "deny")

    def test_driver_subprocess_not_reported_as_model_e2e(self):
        temp_root = ROOT / "wip/tmp"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="iteration-closeout-driver-negative-", dir=temp_root) as directory:
            base = Path(directory)
            project, evidence, skill = base / "project", base / "evidence", base / "project/skill"
            (project / "Handoffx_Logs").mkdir(parents=True)
            evidence.mkdir()
            (skill / "scripts").mkdir(parents=True)
            (project / "Handoffx_Logs/0001-fixture.md").write_text("fixture")
            (skill / "scripts/handoff-runtime.sh").write_text("#!/bin/bash\nexit 2\n")
            report = driver.wrong_project_check(project, evidence, skill, 5)
            self.assertFalse(report["passed"], report)
            self.assertFalse(report["checks"]["root_mismatch_diagnostic"])
            self.assertEqual(report["evidence_kind"], "DRIVER_SUBPROCESS_ONLY_NOT_MODEL_E2E")
            self.assertEqual(report["changed_paths"], [])
            process = json.loads((evidence / "wrong-project-finalize-process.json").read_text())
            self.assertEqual(process["cwd"], report["actual_tool_cwd"])



class PresentationTests(unittest.TestCase):
    def test_todo_list_style_is_not_a_semantic_requirement(self):
        for item in ("- TASK-OLD：等待样本。", "1. TASK-OLD：等待样本。"):
            report = presentation(TAIL.replace("- [ ] TASK-OLD：等待样本。", item), phase="recall")
            self.assertTrue(report["passed"])
            self.assertEqual(report["semantic_status"], "REQUIRES_HUMAN_REVIEW")

    def test_normal_write(self):
        self.assertTrue(presentation(driver.STARTUP, "已记录，检查通过。")["passed"])

    def test_duplicate_startup_not_hidden_by_warning_keyword(self):
        result = presentation(driver.STARTUP, "异常 " + driver.STARTUP, "已记录。")
        self.assertEqual(result["checks"]["startup_not_repeated"], "failed")
        self.assertFalse(result["passed"])

    def test_progress_and_warning_both_require_review_not_keyword_exemption(self):
        for extra in ("正在检查文件。", "异常警告：需要用户确认。", "失败 " * 150):
            result = presentation(driver.STARTUP, extra, "已记录。")
            self.assertEqual(result["checks"]["normal_startup_and_final_only"], "unknown")
            self.assertFalse(result["passed"])
            self.assertTrue(result["human_review"])

    def test_native_error_notice_not_subject_to_normal_length_verdict(self):
        result = presentation(driver.STARTUP, "出错详情" * 100, "操作已停止。", errors=[{"line": 2}])
        self.assertEqual(result["checks"]["normal_visible_length"], "unknown")
        self.assertNotIn("failed", result["checks"].values())
        self.assertEqual(result["human_review"][0]["native_error_lines"], [2])

    def test_noncanonical_startup_unknown(self):
        self.assertEqual(presentation("开始检查。", "已记录。")["checks"]["normal_startup_and_final_only"], "unknown")

    def test_valid_final_tail(self):
        result = presentation(driver.STARTUP, TAIL, phase="recall")
        self.assertTrue(result["passed"], result)
        self.assertEqual(result["semantic_status"], "REQUIRES_HUMAN_REVIEW")

    def test_tail_cannot_come_from_intermediate_message(self):
        result = presentation(TAIL, "这是最终回复。", phase="recall")
        self.assertEqual(result["checks"]["recall_tail_order_unique"], "failed")

    def test_reject_afterword_heading_or_plain_paragraph(self):
        for suffix in ("\n（另有一项已完成，略。）", "\n提示：没有异常。", "\n## 附注\n内容"):
            result = presentation(TAIL + suffix, phase="recall")
            self.assertFalse(result["passed"])
            self.assertEqual(result["checks"]["recall_no_unindented_afterword"], "failed")

    def test_duplicate_and_out_of_order_headings(self):
        for text in (TAIL + "\n### 当前TODO\n- [ ] x", TAIL.replace("### 下一步", "### 当前TODO", 1),
                     TAIL.replace("### 上次停在哪里", "### temp").replace("### 下一步", "### 上次停在哪里").replace("### temp", "### 下一步")):
            self.assertFalse(presentation(text, phase="recall")["passed"])

    def test_indented_metadata_and_list_semantics_explicitly_manual(self):
        result = presentation(TAIL + "  - 负责人：林\n", phase="recall")
        self.assertTrue(result["passed"])
        self.assertTrue(any("indented" in r["question"] for r in result["human_review"]))
        result = presentation(TAIL + "- [ ] 额外建议\n", phase="recall")
        self.assertIn("semantics", result["human_review"][-1]["question"])

    def test_claude_duplicate_result_envelope_not_duplicate_visible_output(self):
        final = "已记录。"
        events = stream({"type": "assistant", "message": {"content": [{"type": "text", "text": driver.STARTUP}]}},
                        {"type": "assistant", "message": {"content": [{"type": "text", "text": final}]}},
                        {"type": "result", "result": final}, host="claude")
        self.assertEqual(len(events["texts"]), 2)
        self.assertTrue(driver.presentation_contract(events, "write")["passed"])


class UsageAndIntegrationTests(unittest.TestCase):
    def test_recall_progress_is_not_hidden_by_valid_tail(self):
        for prefix in ("开始读取项目状态。", "已完成检查，正在总结。"):
            result = presentation(driver.STARTUP, prefix, TAIL, phase="recall")
            self.assertFalse(result["passed"])
            self.assertEqual(result["checks"]["recall_no_normal_progress"], "unknown")
        self.assertTrue(presentation(TAIL, phase="recall")["passed"])
        self.assertTrue(presentation(driver.STARTUP, TAIL, phase="recall")["passed"])

    def test_expanded_entry_is_exact_installed_skill_not_fixture_facts(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "wip") as temp:
            project = Path(temp)
            entry = project / ".claude/skills/handoffx/SKILL.md"
            entry.parent.mkdir(parents=True)
            original = "---\nname: handoffx\n---\n" + driver.STARTUP + "\nUse references.\n"
            entry.write_text(original)
            expanded = driver.expand_entry("/handoffx", entry, original)
            self.assertIn(original, expanded)
            self.assertIn(str(entry), expanded)
            self.assertNotIn(driver.FINALIZE_REPLY, expanded)
            self.assertNotIn("TASK-", expanded)

    def test_expansion_preserves_crlf_and_has_no_extra_behavior_instruction(self):
        content = "---\r\nname: handoffx\r\n---\r\nstartup\r\n"
        result = driver.expand_entry("/handoffx", PROJECT / "SKILL.md", content)
        self.assertIn(content, result)
        self.assertNotIn("开场白逐字", driver.ENTRY_WRAPPER)
        self.assertNotIn("无需再次读取", driver.ENTRY_WRAPPER)

    def test_final_body_progress_is_explicit_semantic_review(self):
        report = presentation("正在读取资料。\n" + TAIL, phase="recall")
        self.assertTrue(any("pre-tail final text" in item["question"] for item in report["human_review"]))
        self.assertIn("prefinal", report["normal_progress_scope"])

    def test_write_context_has_literal_absolute_paths(self):
        for host in driver.HOST_ROOTS:
            write, _ = driver.prompts(PROJECT, host)
            self.assertIn("context --root " + str(PROJECT), write)
            self.assertNotIn("$PWD", write)

    def test_write_display_preference_is_input_not_expected_answer(self):
        preference = "正常写入不要播报进度；仅启动提示和完成确认，异常及时报告。"
        for host in driver.HOST_ROOTS:
            write, recall = driver.prompts(PROJECT, host)
            self.assertIn(preference, write)
            self.assertNotIn(preference, recall)
            self.assertIn("按当前技能默认范围与格式完整汇报", recall)
            for prompt in (write, recall):
                self.assertNotIn(driver.FINALIZE_REPLY, prompt)
                for todo in driver.RESIDUAL.values():
                    self.assertNotIn(todo, prompt)
            self.assertNotIn("TASK-", preference)
            self.assertNotIn("TASK-", recall)

    def test_prompt_separates_model_scratch_from_product_atomic_files(self):
        for host in driver.HOST_ROOTS:
            write, recall = driver.prompts(PROJECT, host)
            for prompt in (write, recall):
                self.assertIn("你创建的计划、日志、临时草稿只放模拟项目wip/tmp", prompt)
                self.assertIn("产品脚本的原子临时文件按其既有契约创建/清理", prompt)
                self.assertIn("整个实例已处于用户项目wip内", prompt)
                self.assertIn("不得越出真正用户项目wip边界", prompt)
                self.assertIn(str(driver.CHECKOUT / "wip"), prompt)
                self.assertNotIn("所有临时文件只放项目wip/tmp", prompt)
                self.assertIn("不调用子代理", prompt)
                self.assertIn("不执行TODO或测试", prompt)

    def test_usage_preserved_without_summing_or_byte_conversion(self):
        usage = {"input_tokens": 37, "cached_input_tokens": 11, "output_tokens": 9, "future_field": {"x": None}}
        events = stream({"type": "turn.completed", "usage": usage})
        self.assertEqual(events["host_usage"]["observations"][0]["value"], usage)
        self.assertIn("not session tokens", events["host_usage"]["scope"])
        self.assertNotIn("session_tokens", events)
        self.assertGreater(events["raw_stream_bytes"], 0)

    def test_usage_missing_unknown_and_overlapping_records_retained(self):
        self.assertEqual(stream({"type": "turn.completed"})["host_usage"]["status"], "unknown")
        for host, event in (("claude", {"type": "result", "usage": {"input_tokens": 10}, "modelUsage": {"m": {"inputTokens": 10}}}),
                            ("opencode", {"type": "step_finish", "part": {"type": "step-finish", "tokens": {"input": 10}, "cost": 0.01}})):
            self.assertEqual(len(stream(event, host=host)["host_usage"]["observations"]), 2)

    def test_unknown_write_gate_does_not_stop_independent_recall_admission(self):
        checks = {"write_required_stages_proven": False, "write_presentation_contract": False,
                  "exactly_one_new_log": True, "write_process_success": False}
        ready = driver.recall_readiness({"exit_code": 0, "timeout": False}, checks)
        self.assertTrue(all(ready.values()))
        self.assertFalse(all(checks.values()))

    def test_write_phase_retains_actual_final_and_rejects_expansion(self):
        temp_root = ROOT / "wip/tmp"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="iteration-closeout-final-text-", dir=temp_root) as directory:
            base = Path(directory)
            project, evidence = base / "project", base / "evidence"
            project.mkdir(); evidence.mkdir()
            checked, actual = "验" * 85, "验" * 85 + "扩写后的最终文本"
            raw = "\n".join(json.dumps(event, ensure_ascii=False) for event in [
                {"type": "item.completed", "item": {"type": "agent_message", "text": driver.STARTUP}},
                command_event(invoke("reply") + " --text " + checked, output=checked + "\n"),
                {"type": "item.completed", "item": {"type": "agent_message", "text": actual}}]).encode()
            def execute(*args, **kwargs):
                (evidence / "write.stdout.jsonl").write_bytes(raw)
                return {"exit_code": 0, "timeout": False}
            with mock.patch.object(driver, "execute", side_effect=execute), \
                    mock.patch.object(driver, "checkpoint", return_value={}):
                status, _ = driver.phase_run("codex", "write", ["not-executed"], project, evidence, 1)
            self.assertEqual(status["actual_final"], actual)
            self.assertEqual((evidence / "write-final.txt").read_text(), actual)
            self.assertEqual(status["reply_consistency"]["status"], "failed")
            self.assertTrue(status["presentation_contract"]["passed"])  # Length alone is insufficient.
            self.assertEqual(json.loads((evidence / "write-reply-consistency.json").read_text())["runtime_reply"], checked)
            self.assertEqual((evidence / "write.stdout.jsonl").read_bytes(), raw)

    def test_initialized_serena_is_not_excluded_from_recall_or_wrong_root(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "wip") as temp:
            project = Path(temp) / "project"; evidence = Path(temp) / "evidence"
            project.mkdir(); evidence.mkdir()
            serena = project / ".serena"; serena.mkdir()
            config = serena / "project.yml"; config.write_text("initial")
            def execute(command, root, out, phase, timeout, **kwargs):
                config.write_text("changed during " + phase)
                event = {"type": "item.completed", "item": {"type": "agent_message", "text": TAIL}}
                (out / (phase + ".stdout.jsonl")).write_text(json.dumps(event))
                return {"exit_code": 0, "timeout": False}
            with mock.patch.object(driver, "execute", side_effect=execute):
                status, _ = driver.phase_run("codex", "recall", ["synthetic"], project, evidence, 1)
                self.assertIn(".serena/project.yml", status["changed_paths"])
                self.assertFalse(not status["changed_paths"])
                report = driver.wrong_root_run("codex", ["synthetic"], project, evidence, 1)
                self.assertFalse(report["passed"])
                self.assertFalse(report["checks"]["zero_project_changes"])

    def test_phase_saves_usage_and_gate_evidence(self):
        temp_root = ROOT / "wip/tmp"
        temp_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="iteration-closeout-contract-", dir=temp_root) as directory:
            base = Path(directory)
            project, evidence = base / "project", base / "evidence"
            project.mkdir(); evidence.mkdir()
            raw = (json.dumps(command_event("echo no-stages")) + "\n" + json.dumps(
                {"type": "item.completed", "item": {"type": "agent_message", "text": TAIL}})).encode()
            def execute(*args, **kwargs):
                (evidence / "recall.stdout.jsonl").write_bytes(raw)
                return {"exit_code": 0, "timeout": False}
            with mock.patch.object(driver, "execute", side_effect=execute), \
                    mock.patch.object(driver, "checkpoint", return_value={}):
                status, text = driver.phase_run("codex", "recall", ["not-executed"], project, evidence, 1)
            self.assertEqual((evidence / "recall.stdout.jsonl").read_bytes(), raw)
            self.assertFalse(status["required_stage_evidence"]["passed"])
            self.assertTrue(status["presentation_contract"]["passed"])
            self.assertEqual(status["host_usage"]["status"], "unknown")
            for name in ("recall-host-usage.json", "recall-required-stage-evidence.json", "recall-presentation-contract.json"):
                self.assertTrue((evidence / name).is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
