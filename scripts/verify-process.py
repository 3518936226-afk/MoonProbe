"""End-to-end real tool case plus explicitly synthetic transport failure checks.
Run with an existing Python 3.12+ executable; all generated paths are on D.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True)
options = parser.parse_args()
OUT = Path(options.out).resolve()
if OUT.drive.lower() != 'd:':
    raise SystemExit('--out must be on D:')
OUT.mkdir(parents=True, exist_ok=False)
TMP = OUT / 'transport space 中文'
TMP.mkdir()
env = os.environ.copy()
env.update(TEMP=str(TMP), TMP=str(TMP), PYTHONDONTWRITEBYTECODE='1', PYTHONNOUSERSITE='1')
EXE = ROOT / 'work/bin/moonprobe.exe'
checks = []

def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def check(name, ok):
    checks.append({'id': name, 'status': 'passed' if ok else 'failed'})
    if not ok:
        raise AssertionError(name)

def run(name, args, expected):
    result = subprocess.run([str(EXE), *map(str, args)], cwd=ROOT, env=env,
                            capture_output=True, timeout=45)
    (OUT / (name + '.stdout.log')).write_bytes(result.stdout)
    (OUT / (name + '.stderr.log')).write_bytes(result.stderr)
    check(name, result.returncode == expected)
    save(name + '.command.json', {'argv': [str(EXE), *map(str, args)], 'exit': result.returncode})
    return result

def config(name, tool, args, timeout=2000, family='python_url_form'):
    value = {'family': family, 'version': name, 'executable': sys.executable,
             'args': ['-I', '-B', '-X', 'utf8', str(tool), *args],
             'cwd': str(TMP), 'timeout_ms': timeout}
    save(name + '.config.json', value)
    return OUT / (name + '.config.json')

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

spec = ROOT / 'examples/url-query.json'
default = config('stdlib-default', ROOT / 'tools/url_query.py', [])
fixed = config('stdlib-preserve-empty', ROOT / 'tools/url_query.py', ['--keep-blank-values'])
run('inspect', ['inspect', spec], 0)
run('default-test', ['test', spec, '--process', default, '--cases', '32',
                    '--shrink-budget', '50', '--out', OUT / 'default'], 1)
baseline = read(OUT / 'default/report.json')
check('real-output-contract-failure', baseline['failed'] > 0 and all(
    r['signature'] == {'stage': 'OUTPUT_SCHEMA', 'code': 'MIN_ITEMS', 'path': '/values'}
    for r in baseline['corpus']))
check('minimal-empty-value-found', any(r['reduced_input'] == {'value': ''} for r in baseline['corpus']))
check('context-removed-during-shrink', any(
    len(json.dumps(r['original_input'])) > len(json.dumps(r['reduced_input']))
    and r['reduced_input'] == {'value': ''} for r in baseline['corpus']))
reproduced = run('default-replay', ['replay', spec, OUT / 'default/corpus', '--process', default], 1)
check('same-signatures-reproduced', all(r['status'] == 'reproduced' for r in json.loads(reproduced.stdout)['results']))
replay = run('fixed-replay', ['replay', spec, OUT / 'default/corpus', '--process', fixed], 0)
check('all-saved-failures-fixed', json.loads(replay.stdout)['failed'] == 0)
run('fixed-test', ['test', spec, '--process', fixed, '--cases', '32', '--out', OUT / 'fixed'], 0)
check('fresh-generated-tests-fixed', read(OUT / 'fixed/report.json')['failed'] == 0)
# An independent semantic roundtrip check supplements the engine's shape contract.
semantic = []
for value in ['', 'a&b=c', '+ %', '中文', '🙂', '\x00', 'line\nnext']:
    payload = {'value': value}
    row = {'input': payload}
    for label, args in [('default', []), ('preserve', ['--keep-blank-values'])]:
        p = subprocess.run([sys.executable, '-I', '-B', '-X', 'utf8', str(ROOT / 'tools/url_query.py'), *args],
                           input=json.dumps(payload).encode(), capture_output=True, cwd=TMP, env=env, timeout=5)
        check('semantic-' + label + '-' + str(len(semantic)), p.returncode == 0)
        row[label] = json.loads(p.stdout)
    check('semantic-roundtrip-' + str(len(semantic)), row['preserve']['values'] == [value])
    semantic.append(row)
save('semantic-roundtrip.json', semantic)

# Failure-injection fixtures below verify OS transport, not upstream defects.
fixture = TMP / 'fixture tool.py'
shutil.copy2(ROOT / 'fixtures/process_fixture.py', fixture)
echo = ROOT / 'examples/echo.json'
for mode, expected_code in [('echo', None), ('argv', None), ('cwd', None),
    ('exit', 'PROCESS_EXIT'), ('json', 'PROCESS_JSON'), ('duplicate', 'PROCESS_JSON'),
    ('utf8', 'PROCESS_UTF8'), ('large', 'PROCESS_OUTPUT_LIMIT'),
    ('stderr', 'PROCESS_OUTPUT_LIMIT'), ('timeout', 'PROCESS_TIMEOUT'), ('spawn', 'PROCESS_TIMEOUT')]:
    extra = ['space arg', '中文', 'a"b', '', 'tail\\', '& | > % ! $(literal)'] if mode == 'argv' else []
    cfg = config('transport-' + mode, fixture, [mode, *extra], timeout=500 if mode in ['timeout', 'spawn'] else 2000, family='echo')
    dest = OUT / ('result-' + mode)
    run('transport-' + mode, ['test', echo, '--process', cfg, '--cases', '1', '--shrink-budget', '1', '--out', dest], 1 if expected_code else 0)
    report = read(dest / 'report.json')
    if expected_code:
        check('classified-' + mode, report['results'][0]['failure']['code'] == expected_code)
    else:
        check('successful-' + mode, report['passed'] == 1)
    if mode == 'spawn':
        pid = int((TMP / 'child.pid').read_text())
        api = ctypes.WinDLL('kernel32', use_last_error=True)
        api.OpenProcess.restype = ctypes.c_void_p
        handle = api.OpenProcess(0x100000, False, pid)
        if handle:
            api.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            api.CloseHandle.argtypes = [ctypes.c_void_p]
            check('timeout-kills-child-tree', api.WaitForSingleObject(handle, 3000) == 0)
            api.CloseHandle(handle)
        else:
            check('timeout-kills-child-tree', True)
run('exclusive-transport', ['test', echo, '--process', fixed, '--mock', 'fixed', '--out', OUT / 'invalid'], 2)
run('family-mismatch', ['test', echo, '--process', fixed, '--out', OUT / 'wrong-family'], 2)
missing = read(default)
missing['executable'] = str(TMP / 'not-present.exe')
save('missing-exe.config.json', missing)
run('missing-exe', ['test', spec, '--process', OUT / 'missing-exe.config.json', '--cases', '1',
                    '--shrink-budget', '1', '--out', OUT / 'missing-exe'], 1)
check('missing-exe-classified', read(OUT / 'missing-exe/report.json')['results'][0]['failure']['code'] == 'PROCESS_IO')
marker_cfg = config('transport-marker', fixture, ['marker'], family='echo')
run('marker-first', ['test', echo, '--process', marker_cfg, '--cases', '1', '--out', OUT / 'marker'], 0)
(TMP / 'run.marker').unlink()
run('occupied-output', ['test', echo, '--process', marker_cfg, '--out', OUT / 'marker'], 2)
check('occupied-output-does-not-invoke', not (TMP / 'run.marker').exists())
bad = read(default)
bad['cwd'] = 'C:/Windows/Temp'
save('c-drive-denied.config.json', bad)
run('c-drive-denied', ['test', spec, '--process', OUT / 'c-drive-denied.config.json', '--out', OUT / 'c-drive-result'], 2)
check('transport-temp-files-cleaned', not list(TMP.glob('.moonprobe-*.tmp')))
tracked = subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines()
bindings = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked if (ROOT / p).is_file()}
summary = {'status': 'passed', 'checks': checks, 'source_commit': subprocess.check_output(
    ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'source_files_sha256': bindings,
    'binary_sha256': hashlib.sha256(EXE.read_bytes()).hexdigest(), 'python': sys.version,
    'real_case': {'kind': 'stdlib_configuration_contract_mismatch', 'upstream_bug_claimed': False,
                 'default_failed': baseline['failed'], 'generated': baseline['generated_cases'],
                 'signature_groups': baseline['failure_signature_count'], 'minimal_input': {'value': ''},
                 'fixed_failed': 0},
    'reference': 'https://docs.python.org/3.12/library/urllib.parse.html#urllib.parse.parse_qs',
    'synthetic_transport_modes': 12, 'independent_human_trial': False}
save('summary.json', summary)
print(json.dumps({'status': 'passed', 'checks': len(checks), 'real_case': summary['real_case']}, ensure_ascii=False))
