"""Synthetic transport checks, separate from the real stdlib case study."""
import json
import os
import sys
import time

mode = sys.argv[1]
value = json.load(sys.stdin)
if mode == 'echo':
    json.dump(value, sys.stdout)
elif mode == 'argv':
    assert sys.argv[2:] == ['space arg', '中文', 'a"b', '', 'tail\\', '& | > % ! $(literal)']
    json.dump(value, sys.stdout)
elif mode == 'exit':
    sys.exit(7)
elif mode == 'json':
    print('{invalid')
elif mode == 'duplicate':
    print('{"message":"a","message":"b"}')
elif mode == 'utf8':
    sys.stdout.buffer.write(b'\xff')
elif mode == 'large':
    sys.stdout.write('x' * 1100000)
elif mode == 'stderr':
    sys.stderr.write('x' * 1100000)
elif mode == 'timeout':
    time.sleep(10)
elif mode == 'spawn':
    import subprocess
    child = subprocess.Popen([sys.executable, '-I', '-B', '-c', 'import time;time.sleep(20)'])
    with open('child.pid', 'w') as f:
        f.write(str(child.pid))
    time.sleep(10)
elif mode == 'cwd':
    assert os.getcwd().lower().startswith('d:')
    json.dump(value, sys.stdout)
elif mode == 'marker':
    with open('run.marker', 'w') as f:
        f.write('invoked')
    json.dump(value, sys.stdout)
else:
    raise ValueError(mode)
