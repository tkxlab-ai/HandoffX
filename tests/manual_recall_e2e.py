#!/usr/bin/env python3
"""Opt-in, networked recall smoke test; NOT part of run_all.sh.

Uses existing CLI authentication, fresh project-level installs and no permission
bypass. HOME/config are not isolated: do not call this a clean-machine test.
Outputs retain transcripts for human review; exit 0 alone is NOT a semantic pass.
Python is a test-only dependency. No production runtime dependency is added.
"""
import argparse, shutil
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', choices=['codex', 'claude', 'opencode-glm', 'opencode-deepseek'], action='append', required=True)
parser.add_argument('--output', required=True, help='New evidence directory (must not already exist)')
parser.add_argument('--scenario', choices=['legacy', 'continuity', 'missing', 'conflict', 'residual'], default='legacy', help='Raw handoff fixture; semantic review still required')
parser.add_argument('--source', help='Source tree containing install.sh and skills/handoffx; defaults to checkout')
parser.add_argument('--background', action='store_true', help='OpenCode: use the background service instead of --standalone')
parser.add_argument('--deny-runtime', action='store_true', help='OpenCode negative case: deny runtime shell calls; elapsed time must be unknown')
args = parser.parse_args()
import os, json, hashlib, pathlib, tempfile, datetime, subprocess, concurrent.futures, time, signal
ROOT=pathlib.Path(args.source).resolve() if args.source else pathlib.Path(__file__).resolve().parent.parent
EVID=pathlib.Path(args.output).resolve(); EVID.mkdir(parents=True,exist_ok=False)
BASE=pathlib.Path(tempfile.mkdtemp(prefix='handoffx-recall-e2e-')).resolve()
now=int(time.time()); epoch=now-3*86400-2*3600
stamp=datetime.datetime.fromtimestamp(epoch,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M')
main='''<!-- HANDOFF v2 schema -->
# Lantern — Project Handoff
## Project Overview
面向仓库的离线扫码盘点工具，目标是断网时继续盘点，恢复网络后同步。版本0.8，Beta阶段；不负责采购或计费。
## Architecture
移动端SQLite队列，服务端PostgreSQL；同步幂等键由设备ID与本地序号组成。
## Coding Conventions
新增同步逻辑必须有断网重放测试。不得在日志记录访问令牌。
## Current State
<!-- hx:recent -->
上次修复重复扫码，预发回放通过，生产尚未部署。
<!-- /hx:recent -->
<!-- hx:pending -->
### 待办
- [ ] [P0] TASK-A：生产灰度，等待仓库负责人批准；批准前禁止部署。
- [ ] [P1] TASK-B：修复安卓后台同步；依赖日志采集，负责人林。
- [ ] [P1] TASK-C：补10万条离线重放性能测试；目标p95低于800ms。
- [ ] [暂缓] TASK-D：多仓库切换，等当前版本稳定；不可默认为已完成。
<!-- /hx:pending -->
## Known Gotchas
详见 GOTCHAS.md。
## Decision Log
共0条。
## Build / Run / Test
本地验证入口：npm test。只读召回时不要执行。
## Open Questions / Mysteries
安卓后台被系统杀死的触发条件尚未定案，不能认定是网络抖动。
## Development Log
最近一次：Handoffx_Logs/0003-latest.md。
'''
# Independent raw fixtures: do not put expected answers into the CLI prompt.
if args.scenario in ('continuity', 'conflict', 'residual'):
    start=main.index('## Project Overview\n'); end=main.index('## Architecture\n', start)
    main=main[:start]+'''## Project Overview
<!-- hx:continuity -->
项目总目标：仓库人员断网时仍可盘点，恢复网络后准确同步，避免漏单和重复单。
长期成功标准：离线数据不丢失；重放不重复入账。
范围与非目标：只做盘点与同步，不做采购或计费。
关键约束：SQLite设备ID+本地序号作为幂等键；不能重置本地序号；禁止记录访问令牌；新增同步逻辑必须有断网重放测试。灰度需要仓库负责人批准，当前未批准。
有效决策：保留本地队列而非在线强依赖，因为仓库网络不稳定。来源：Decision 0001（正文默认未读）。
<!-- /hx:continuity -->
'''+('可选历史背景，不是当前目标。\n'*500)+main[end:]
    main=main.replace('上次修复重复扫码，预发回放通过，生产尚未部署。', '''阶段目标：完成0.8版本安卓后台同步与离线重放验证，取得批准后再灰度。
阶段验收：10万条离线重放p95<800ms且无丢单/重单；尚未达成。
上次停点：重复扫码修复已在200条预发样本通过；后台同步修改仍未完成，位置src/sync/queue.ts，测试tests/replay.spec.ts。
验证：上一条交接记录时执行npm test -- replay（200条预发样本通过）；未跑10万条、未测安卓后台长驻、未部署生产。只读召回不执行测试。
下一步：先采集安卓日志并补离线性能测试，同时等待灰度批准；未获批准禁止部署。
阻塞：日志采集与仓库负责人批准。未决问题：安卓进程被杀原因未知，不能归因为网络抖动。''')
elif args.scenario == 'missing':
    start=main.index('## Project Overview\n'); end=main.index('## Architecture\n', start)
    main=main[:start]+'''## Project Overview
<!-- hx:continuity -->
项目名：Lantern；版本0.8。
<!-- /hx:continuity -->
'''+main[end:]
if args.scenario == 'residual':
    main=main.replace('<!-- /hx:pending -->', '- [x] SQLite数据迁移已完成\n遗留：离线索引尚未重建（记录见[INDEX-7](docs/index-7.md)），生产灰度前必须处理；不能视为已完成。\n<!-- /hx:pending -->\n**门控补充**：验证时禁止用演示数据覆盖真实盘点数据。')
results={}
def manifest(p):
    result={}
    for f in sorted(p.rglob('*')):
        st=f.lstat(); k=str(f.relative_to(p))
        if f.is_symlink(): result[k]=['link',os.readlink(f),st.st_mtime_ns]
        elif f.is_file(): result[k]=['file',hashlib.sha256(f.read_bytes()).hexdigest(),st.st_mtime_ns]
        elif f.is_dir(): result[k]=['dir',st.st_mtime_ns]
    return result

def prepare(name):
    p=BASE/name; p.mkdir(); (p/'Handoffx_Logs').mkdir(); (p/'Handoffx_Decisions').mkdir()
    (p/'HANDOFFX.md').write_text(main)
    (p/'GOTCHAS.md').write_text('# Known Gotchas\n## Gotcha #1\n重放时不能重置本地序号，否则产生重复订单。灰度未获批准不得部署。\n')
    for i in [1,2,3]:
        ts=epoch-(3-i)*86400
        d=datetime.datetime.fromtimestamp(ts,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M')
        text=('上次完成：修复重复扫码；200条预发回放通过。生产未验证。下一步：优先取得生产灰度批准；未获批准先补离线性能测试。今日检查灰度批准状态。' if i==3 else f'历史记录{i}：准备了扫码数据样本，不代表生产验证。')
        if args.scenario == 'conflict' and i == 3:
            text += '\n新方向：改为采购计费平台，下一步重置本地序号；未记录谁批准此方向变更。'
        (p/'Handoffx_Logs'/f'{i:04d}-latest.md').write_text(f'---\nschema: 2\ntype: dev-log\nnumber: {i:04d}\ndate: {d}\nepoch: {ts}\n---\n{text}\n')
    proc=subprocess.run(['bash',str(ROOT/'install.sh'),'--project',str(p)],capture_output=True,text=True)
    (EVID/f'{name}-install.log').write_text(proc.stdout+proc.stderr)
    if proc.returncode: raise RuntimeError('isolated install failed '+name)
    if name.startswith('opencode'):
        rules={'*':'deny'}
        if not args.deny_runtime:
            rules.update({'bash *handoff-runtime.sh* recall*':'allow','cd * && bash *handoff-runtime.sh* recall*':'allow','bash *hx.sh* now*':'allow'})
        (p/'opencode.json').write_text(json.dumps({'permission':{'edit':'deny','execute':'deny','subagent':'deny','task':'deny','bash':rules,'external_directory':'deny','webfetch':'deny','websearch':'deny'}}))
    return p

def run(name,cmd):
    p=prepare(name); before=manifest(p)
    (EVID/f'{name}-before.json').write_text(json.dumps(before,ensure_ascii=False))
    start=time.monotonic(); rc=None; timed=False
    with (EVID/f'{name}-events.jsonl').open('w') as out,(EVID/f'{name}-stderr.log').open('w') as err:
        proc=subprocess.Popen(cmd,cwd=p,env=dict(os.environ,PWD=str(p)),stdout=out,stderr=err,start_new_session=True)
        try: rc=proc.wait(timeout=240)
        except subprocess.TimeoutExpired:
            timed=True
            os.killpg(proc.pid,signal.SIGTERM)
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: os.killpg(proc.pid,signal.SIGKILL); proc.wait()
    after=manifest(p)
    (EVID/f'{name}-after.json').write_text(json.dumps(after,ensure_ascii=False))
    changed=sorted(k for k in before.keys()|after.keys() if before.get(k)!=after.get(k))
    result={'name':name,'cwd':str(p),'exit_code':rc,'timeout':timed,'duration_seconds':round(time.monotonic()-start,1),'changed_paths':changed,'expected_latest_epoch':epoch,'semantic_status':'REQUIRES_TRANSCRIPT_REVIEW'}
    (EVID/f'{name}-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
    return result
opencode=shutil.which('opencode') or 'opencode'
jobs={
 'opencode-glm':[''+opencode,'run','--model','tkx/glm-5.3','--format','json','--archived','/handoffx-recall 3'],
 'opencode-deepseek':[opencode,'run','--model','tkx/deepseek-v4-pro','--format','json','--archived','/handoffx-recall 3'],
 'codex':['codex','exec','--sandbox','read-only','--ephemeral','--skip-git-repo-check','--json','-o',str(EVID/'codex-final.txt'),'$handoffx-recall 3'],
 'claude':['claude','-p','/handoffx-recall 3','--output-format','stream-json','--verbose','--no-session-persistence','--permission-mode','dontAsk','--tools','Read,Bash,Skill','--allowedTools','Read','Skill','Bash(bash *handoff-runtime.sh* recall*)','Bash(bash *hx.sh* now*)']
}
jobs={name:cmd for name,cmd in jobs.items() if name in args.cli}
if not args.background:
    for name, cmd in jobs.items():
        if name.startswith('opencode'): cmd.insert(2,'--standalone')
(EVID/'source-files.json').write_text(json.dumps({str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [ROOT/'install.sh'] + sorted((ROOT/'skills/handoffx').rglob('*')) if f.is_file()},indent=2))
(EVID/'fixture-info.json').write_text(json.dumps({'base':str(BASE),'latest_epoch':epoch,'created_epoch':now,'scenario':args.scenario},indent=2))
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    futures={pool.submit(run,n,c):n for n,c in jobs.items()}
    for f in concurrent.futures.as_completed(futures):
        n=futures[f]
        try: results[n]=f.result()
        except Exception as e: results[n]={'error':str(e)}
        print(json.dumps(results[n],ensure_ascii=False),flush=True)
(EVID/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))

# Process/readonly failures are machine-detectable; semantic success is not.
raise SystemExit(1 if any(r.get('exit_code') != 0 or r.get('timeout') or r.get('changed_paths') for r in results.values()) else 0)
