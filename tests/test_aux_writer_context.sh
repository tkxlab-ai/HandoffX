#!/usr/bin/env bash
# Offline root-intent contract. Fake installations; all artifacts in wip/.
set -euo pipefail
unset CDPATH
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$ROOT" <<'PY'
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
original_home = str(Path.home().resolve())
base = repo / 'wip/tmp/aux-writer-context'
base.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='test-', dir=base)).resolve()
print('Aux writer evidence:', work, flush=True)
passed = failed = 0
names = subprocess.check_output(['bash', '-c', '. "$1"; printf "%s\\n" "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR" "$HX_GOTCHAS_FILE" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR"', 'bash', str(repo / 'scripts/lib/handoff-schema.sh')], text=True).splitlines()
main, logs, decisions, gotchas, oldmain, oldlogs, olddecisions = names


def check(label, ok):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
    print(('PASS ' if ok else 'FAIL ') + label, flush=True)


def snapshot(*roots):
    result = {}
    for root in roots:
        for path in sorted(root.rglob('*')):
            info = path.lstat()
            result[str(path)] = (info.st_mode, info.st_mtime_ns,
                os.readlink(path) if path.is_symlink() else
                hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
    return result


def seed(root):
    root.mkdir(parents=True, exist_ok=True)
    (root / main).write_text('''# Synthetic handoff

## Project Overview
Offline fixture.




## Architecture
Local files.
## Current State
<!-- hx:recent -->
Ready.
<!-- /hx:recent -->
## 📜 Development Log
### 2026-01-02 10:00 — New
**触发**: test
**改动**: none
**验证**: fixture
**关联**: none

### 2026-01-01 10:00 — Old
**触发**: test
**改动**: none
**验证**: fixture
**关联**: none

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
''')


def old_seed(root):
    root.mkdir(parents=True, exist_ok=True)
    (root / oldmain).write_text('<!-- HANDOFF v2 schema -->\n# Legacy synthetic project\n')
    (root / oldlogs).mkdir(exist_ok=True)
    (root / olddecisions).mkdir(exist_ok=True)
    (root / gotchas).write_text('# Gotchas\n')


def install(source, destination, scope, root=None):
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination / 'scripts')
    if scope:
        (destination / '.handoffx-install-context').write_text(
            f'schema=1\nscope={scope}\nproject_root={root or ""}\nskill_root={destination}\nhost=codex\n')
    return destination / 'scripts'


for source in (repo / 'scripts', repo / 'skills/handoffx/scripts'):
    label = 'source' if source == repo / 'scripts' else 'mirror'
    w = work / label
    home, temp, binpath = w / 'home', w / 'tmp', w / 'bin'
    a, b, bound = w / 'projects/a', w / 'projects/b', w / 'projects/bound'
    for p in (home, temp, binpath): p.mkdir(parents=True)
    for p in (a, b, bound): seed(p)
    global_scripts = install(source, home / '.agents/skills/handoffx', 'global')
    project_scripts = install(source, bound / '.agents/skills/handoffx', 'project', bound)
    source_scripts = install(source, w / 'unbound', None)
    marker = w / 'mktemp-called'
    real_mktemp = shutil.which('mktemp')
    (binpath / 'mktemp').write_text('#!/bin/bash\nprintf called >> "$AUX_MKTEMP_MARKER"\nexec "$AUX_REAL_MKTEMP" "$@"\n')
    (binpath / 'mktemp').chmod(0o755)
    env = dict(os.environ, HOME=str(home), HOME_OVERRIDE=str(home), HX_SYNC_MACHINE='box', TMPDIR=str(temp),
               TMP=str(temp), TEMP=str(temp), HANDOFF_TIDY_SKIP_V2_GATE='1',
               AUX_MKTEMP_MARKER=str(marker), AUX_REAL_MKTEMP=real_mktemp,
               PATH=str(binpath) + os.pathsep + os.environ['PATH'])
    counter = 0

    def run(script, args, cwd=a, extra=None):
        global counter
        counter += 1
        marker.unlink(missing_ok=True)
        actual_env = dict(env, PWD=str(cwd))
        # As in trust integration: global children need the real HOME only for
        # read-only ancestor-peer classification. Never install/write there;
        # sync's HOME_OVERRIDE, all targets, TMPDIR and manifests stay isolated.
        if script.parent == global_scripts:
            actual_env['HOME'] = original_home
        actual_env.update(extra or {})
        result = subprocess.run(['bash', str(script)] + [str(x) for x in args], cwd=cwd,
                                env=actual_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=45)
        (w / f'call-{counter:03d}.log').write_text(result.stdout)
        return result

    def reject(title, script, args, cwd=a):
        before = snapshot(a, b, bound, temp)
        result = run(script, args, cwd)
        check(label + ': ' + title + ' rejected before temp/write',
              result.returncode == 2 and before == snapshot(a, b, bound, temp) and not marker.exists())
        if result.returncode != 2: print(result.stdout)

    for tool, args in (('tidy-handoff.sh', [main]), ('archive-devlog.sh', [main, '1']),
                       ('sync-memory.sh', ['on']), ('sync-memory.sh', ['off']), ('sync-memory.sh', ['sync'])):
        script = global_scripts / tool
        reject(tool + ' ' + str(args) + ' global requires flag', script, args)
        reject(tool + ' wrong cwd', script, ['--expect-root', a] + args, b)
        reject(tool + ' relative intent', script, ['--expect-root', '.'] + args)
        reject(tool + ' missing intent', script, ['--expect-root'])
        check(label + ': ' + tool + ' global help without flag', run(script, ['--help']).returncode == 0)

    for tool in ('tidy-handoff.sh', 'archive-devlog.sh'):
        tail = ['1'] if tool == 'archive-devlog.sh' else []
        reject(tool + ' global wrong file target', global_scripts / tool,
               ['--expect-root', a, b / main] + tail)
        reject(tool + ' project wrong file target', project_scripts / tool, [a / main] + tail, bound)
        reject(tool + ' project wrong cwd', project_scripts / tool, [bound / main] + tail)
        reject(tool + ' misplaced flag', global_scripts / tool, [main, '--expect-root', a])
        reject(tool + ' extra target', global_scripts / tool, ['--expect-root', a, main, b / main, '1'])
    reject('archive global wrong directory', global_scripts / 'archive-devlog.sh', ['--expect-root', a, b])
    reject('archive project wrong directory', project_scripts / 'archive-devlog.sh', [a], bound)
    reject('sync does not accept another target', global_scripts / 'sync-memory.sh', ['--expect-root', a, 'on', b])
    reject('sync project wrong cwd', project_scripts / 'sync-memory.sh', ['on'])
    check(label + ': sync global status is read-only without flag', run(global_scripts / 'sync-memory.sh', ['status']).returncode == 0)
    check(label + ': sync global default is status', run(global_scripts / 'sync-memory.sh', []).returncode == 0)

    # Prove successful writes, not merely exit-zero no-ops.
    for scope, scripts, root, flag in (('global', global_scripts, a, ['--expect-root', a]),
                                       ('project', project_scripts, bound, []),
                                       ('source_unbound', source_scripts, b, [])):
        seed(root)
        old = (root / main).read_bytes()
        result = run(scripts / 'tidy-handoff.sh', flag + [main], root)
        check(label + ': ' + scope + ' tidy writes successfully', result.returncode == 0 and
              (root / main).read_bytes() != old and (root / (main + '.bak')).is_file())
        result = run(scripts / 'archive-devlog.sh', flag + [main, '1'], root)
        check(label + ': ' + scope + ' archive file writes successfully', result.returncode == 0 and
              (root / (Path(main).stem + '.archive.md')).is_file())
        encoded = subprocess.check_output(['bash', str(scripts / 'encode-cc-path.sh'), str(root)], text=True).strip()
        memory_source = home / '.claude/projects' / encoded / 'memory'
        memory_source.mkdir(parents=True, exist_ok=True)
        (memory_source / 'note.md').write_text('Offline synthetic memory.\n')
        for mode in ('on', 'off', 'sync'):
            result = run(scripts / 'sync-memory.sh', flag + [mode], root)
            check(label + ': ' + scope + ' sync ' + mode + ' succeeds', result.returncode == 0 and
                  (root / '.agent-sessions-sync-hx/machines/box/claude-code/memory/note.md').read_text() == 'Offline synthetic memory.\n' and
                  (root / '.agent-sessions-sync-hx/.sync-disabled').exists() == (mode != 'on'))  # sync ignores and keeps the flag off set

    # Check v2 directory and explicit-file archive dispatch without relying on v1 counting.
    for target_is_file in (False, True):
        root = w / ('yearly-file' if target_is_file else 'yearly-dir')
        root.mkdir(); (root / main).write_text('<!-- HANDOFF v2 schema -->\n')
        (root / logs).mkdir()
        entry = '0001-2000-01-01-old.md'
        (root / logs / entry).write_text('Synthetic old entry.\n')
        result = run(global_scripts / 'archive-devlog.sh', ['--expect-root', root, root / main if target_is_file else root], root)
        check(label + ': global v2 archive ' + ('file' if target_is_file else 'directory'),
              result.returncode == 0 and (root / (logs + '.archive') / '2000' / entry).is_file() and
              not (root / logs / entry).exists())

    # Schema dry-run/help use the real migrator but do not require global intent.
    legacy, other = w / 'legacy', w / 'other-legacy'
    old_seed(legacy); old_seed(other)
    tidy = global_scripts / 'tidy-handoff.sh'
    for args in (['schema-upgrade', '--root', legacy],
                 ['schema-upgrade', '--apply', '--dry-run', '--root', legacy],
                 ['schema-upgrade', '--help']):
        before = snapshot(legacy, other, temp)
        result = run(tidy, args)
        check(label + ': schema read-only mode ' + str(args), result.returncode == 0 and
              before == snapshot(legacy, other, temp) and not marker.exists())
    for args, cwd in ((['schema-upgrade', '--apply', '--root', legacy], legacy),
                      (['--expect-root', legacy, 'schema-upgrade', '--apply', '--root', legacy], a),
                      (['--expect-root', legacy, 'schema-upgrade', '--apply', '--root', other], legacy),
                      (['schema-upgrade', '--dry-run', '--apply', '--root', legacy], legacy)):
        before = snapshot(legacy, other, temp)
        result = run(tidy, args, cwd)
        check(label + ': schema apply intent/cwd/actual-root rejection', result.returncode == 2 and
              before == snapshot(legacy, other, temp) and not marker.exists())
    before = snapshot(legacy, other, temp)
    result = run(project_scripts / 'tidy-handoff.sh', ['schema-upgrade', '--apply', '--root', legacy], bound)
    check(label + ': project schema apply wrong root rejected', result.returncode == 2 and
          before == snapshot(legacy, other, temp) and not marker.exists())
    result = run(tidy, ['--expect-root', legacy, 'schema-upgrade', '--apply', '--root', legacy], legacy)
    check(label + ': global schema apply valid root writes', result.returncode == 0 and
          (legacy / main).is_file() and not (legacy / oldmain).exists())
    result = run(source_scripts / 'tidy-handoff.sh', ['schema-upgrade', '--apply', '--root', other], a)
    check(label + ': source_unbound schema explicit different root remains compatible', result.returncode == 0 and
          (other / main).is_file() and not (other / oldmain).exists())

    project_legacy = w / 'project-legacy'
    old_seed(project_legacy)
    project_legacy_scripts = install(source, project_legacy / '.agents/skills/handoffx', 'project', project_legacy)
    result = run(project_legacy_scripts / 'tidy-handoff.sh', ['schema-upgrade', '--apply', '--root', project_legacy], project_legacy)
    check(label + ': project schema apply without flag remains compatible', result.returncode == 0 and
          (project_legacy / main).is_file() and not (project_legacy / oldmain).exists())
    for tool in ('tidy-handoff.sh', 'archive-devlog.sh'):
        reject(tool + ' source explicit intent still binds target', source_scripts / tool,
               ['--expect-root', a, b / main])
    broken = w / 'incomplete/scripts'
    broken.mkdir(parents=True)
    for tool, args in (('tidy-handoff.sh', [main]), ('archive-devlog.sh', [main, '1']), ('sync-memory.sh', ['on'])):
        shutil.copyfile(source / tool, broken / tool)
        reject(tool + ' missing context library fails closed', broken / tool, args)
    # An implicit memory target cannot redirect a valid root's writes elsewhere.
    shutil.rmtree(a / '.agent-sessions-sync-hx')
    (a / '.agent-sessions-sync-hx').symlink_to(b / '.agent-sessions-sync-hx', target_is_directory=True)
    for mode in ('on', 'off', 'sync'):
        reject('sync ' + mode + ' symlinked implicit target', global_scripts / 'sync-memory.sh', ['--expect-root', a, mode])
    (a / '.agent-sessions-sync-hx').unlink()

    # CDPATH must neither redirect actual targets nor pollute SCRIPT_DIR capture.
    seed(a)
    result = run(global_scripts / 'archive-devlog.sh', ['--expect-root', a, '.', '1'], a,
                 {'CDPATH': str(b) + ':' + str(home)})
    check(label + ': CDPATH ignored with relative directory target', result.returncode == 0)
    alias = a / 'other-root'; alias.symlink_to(b, target_is_directory=True)
    reject('archive symlinked root', global_scripts / 'archive-devlog.sh', ['--expect-root', a, alias])
    alias.unlink()
    link = a / 'other-main.md'; link.symlink_to(b / main)
    for tool in ('tidy-handoff.sh', 'archive-devlog.sh'):
        reject(tool + ' selected symlink file', global_scripts / tool, ['--expect-root', a, link])
    link.unlink()

for name in ('tidy-handoff.sh', 'archive-devlog.sh', 'sync-memory.sh'):
    check('mirror byte identity: ' + name, (repo / 'scripts' / name).read_bytes() ==
          (repo / 'skills/handoffx/scripts' / name).read_bytes())
print(f'{passed} passed, {failed} failed; fixtures/logs: {work}')
sys.exit(1 if failed else 0)
PY
