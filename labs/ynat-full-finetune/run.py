"""Bound the worker lifetime; output directory is exclusive to prevent retry overwrite."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import threading

p = argparse.ArgumentParser()
p.add_argument('--mode', choices=['smoke', 'full'], required=True)
p.add_argument('--output', required=True)
p.add_argument('--bundle', default='/opt/bundle')
a = p.parse_args()
if int(os.environ.get('WORLD_SIZE', '1')) != 1 or int(os.environ.get('RANK', '0')) != 0:
    raise SystemExit('ERR: this example requires a single process on one GPU')
out = Path(a.output).resolve()
if not Path('/results').is_mount() or Path('/results') not in out.parents:
    raise SystemExit('ERR: mount persistent File Storage at /results and choose an output below it')
out.mkdir(parents=True, exist_ok=False)
seconds = 600 if a.mode == 'smoke' else 1800
start = time.time()
(out/'status.json').write_text(json.dumps(dict(status='RUNNING', started=start, limit_seconds=seconds)))
with (out/'run.log').open('w', buffering=1) as log:
    try:
        proc = subprocess.Popen([sys.executable, '-u', str(Path(__file__).resolve().with_name('train.py')), '--mode', a.mode,
                                 '--output', str(out), '--bundle', a.bundle], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1, start_new_session=True)
        def relay():
            for line in proc.stdout:
                log.write(line)
                print(line, end='', flush=True)
        reader = threading.Thread(target=relay, daemon=True)
        reader.start()
        code = proc.wait(timeout=seconds)
        status = 'COMPLETED' if code == 0 else 'FAILED'
    except subprocess.TimeoutExpired:
        import signal
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        code, status = 124, 'TIMEOUT'
    reader.join(timeout=5)
(out/'status.json').write_text(json.dumps(dict(status=status, exit_code=code,
    started=start, elapsed_seconds=time.time()-start, limit_seconds=seconds), indent=2))
print(f'{status}: {out}')
sys.exit(code)
