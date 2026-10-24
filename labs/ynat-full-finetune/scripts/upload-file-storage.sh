#!/usr/bin/env bash
# Existing NFS mount required. Usage: bash scripts/upload-file-storage.sh /mnt/sat-results ynat-v1
set -euo pipefail
[[ $# == 2 ]] || { echo 'Usage: upload-file-storage.sh MOUNT_PATH RELEASE_NAME' >&2; exit 2; }
SAT_MOUNT="$1"
SAT_RELEASE="$2"
[[ "$SAT_RELEASE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || exit 2
mountpoint -q "$SAT_MOUNT" || { echo 'Target is not a mount point; refusing local-disk copy.' >&2; exit 1; }
SAT_FS_TYPE="$(findmnt -n -o FSTYPE --target "$SAT_MOUNT")"
[[ "$SAT_FS_TYPE" == nfs || "$SAT_FS_TYPE" == nfs4 ]] || { echo 'Target must be NFS.' >&2; exit 1; }
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -s "$LAB_DIR/bundle/manifest.json" ]] || { echo 'Prepare bundle first.' >&2; exit 1; }
SAT_DEST="$SAT_MOUNT/releases/$SAT_RELEASE"
mkdir -p "$SAT_MOUNT/releases"
mkdir "$SAT_DEST" # Exclusive release: never overwrite existing code or data.
mkdir "$SAT_DEST/code"
cp "$LAB_DIR/"{common.py,train.py,run.py} "$SAT_DEST/code/"
cp -R "$LAB_DIR/bundle" "$SAT_DEST/bundle"
# Compare every copied file byte-for-byte using SHA256, including model shards.
python3 - "$LAB_DIR" "$SAT_DEST" <<'PYVERIFY'
import hashlib, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:])
def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(8*1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()
pairs = [(src/name, dst/'code'/name) for name in ('common.py','train.py','run.py')]
pairs += [(p, dst/'bundle'/p.relative_to(src/'bundle')) for p in (src/'bundle').rglob('*') if p.is_file()]
for a,b in pairs:
    if digest(a) != digest(b):
        raise SystemExit(f'Copy verification failed: {b}')
(dst/'READY').write_text(f'{len(pairs)} files verified\n')
print(f'PASS: {len(pairs)} uploaded files SHA256 verified: {dst}')
PYVERIFY
echo "Job command: python /results/releases/$SAT_RELEASE/code/run.py --bundle /results/releases/$SAT_RELEASE/bundle --mode smoke --output /results/ynat-smoke-01"
