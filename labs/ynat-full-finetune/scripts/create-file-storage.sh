#!/usr/bin/env bash
# Usage: bash scripts/create-file-storage.sh [ZONE] [VOLUME_NAME]
set -euo pipefail
umask 077
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$LAB_DIR/tools:$PATH"
if [[ $# -gt 2 ]]; then
  echo 'Usage: bash scripts/create-file-storage.sh [ZONE] [VOLUME_NAME]' >&2
  exit 2
fi
command -v scp-cli >/dev/null || { echo 'Install scp-cli and configure authentication first.' >&2; exit 1; }
SAT_ZONE="${1:-kr-west1-a}"
SAT_VOLUME_NAME="${2:-satynat$(date -u +%y%m%d%H%M%S)}"
[[ "$SAT_VOLUME_NAME" =~ ^[a-z][a-z0-9_]{2,20}$ ]] || { echo 'Volume name must be 3-21 lowercase letters, digits, or underscores and start with a letter.' >&2; exit 2; }
# Region and availability zone are separate values; reject mismatches before creation.
python3 - "$SAT_ZONE" <<'PYCONFIG'
import json, sys
from pathlib import Path
config = json.loads((Path.home()/'.scp/cli-config.json').read_text())
region = config.get('default_scp_region')
expected = sys.argv[1].rsplit('-', 1)[0]
if region != expected:
    raise SystemExit(f'CLI region {region!r} does not match zone region {expected!r}; no create request sent.')
print(f'CLI region={region}; File Storage zone={sys.argv[1]}')
PYCONFIG
EVIDENCE_DIR="$(mktemp -d "$LAB_DIR/evidence-create-XXXXXXXX")"
printf '%s\n' "$SAT_VOLUME_NAME" > "$EVIDENCE_DIR/volume-name.txt"
printf 'Request evidence: %s\n' "$EVIDENCE_DIR"
# Validate installed CLI options before submitting a billable request.
scp-cli filestorage volume create --help > "$EVIDENCE_DIR/create-help.txt"
for option in zone type_name protocol name; do
  grep -q -- "--$option" "$EVIDENCE_DIR/create-help.txt" || {
    echo "Installed CLI does not document --$option; no create request sent." >&2
    exit 1
  }
done
scp-cli filestorage volume list | tee "$EVIDENCE_DIR/volumes-before.txt"
echo "Creating one NFS HighPerformanceSSD volume: zone=$SAT_ZONE name=$SAT_VOLUME_NAME"
echo 'This may incur storage charges. Do not rerun after a timeout; inspect volume list first.'
# No automatic retry: a timeout can occur after the server has accepted creation.
scp-cli filestorage volume create \
  --zone "$SAT_ZONE" \
  --type_name HighPerformanceSSD \
  --protocol NFS \
  --name "$SAT_VOLUME_NAME" | tee "$EVIDENCE_DIR/create-response.txt"
printf 'Enter volume_id from the response above (not SAT Volume ID): '
read -r SAT_FILE_VOLUME_ID
[[ -n "$SAT_FILE_VOLUME_ID" ]] || { echo 'No ID entered; inspect the response before retrying.' >&2; exit 1; }
scp-cli filestorage volume show --volume_id "$SAT_FILE_VOLUME_ID" | tee "$EVIDENCE_DIR/volume-after.txt"
printf '%s\n' "$SAT_FILE_VOLUME_ID" > "$EVIDENCE_DIR/volume-id.txt"
printf 'Request and lookup recorded in %s\n' "$EVIDENCE_DIR"
echo 'Confirm Available/ready state in the console, then connect this File Storage under SAT > Volume.'
echo 'Mount that SAT Volume at /results in the Training Job. Creation alone does not establish this connection.'
