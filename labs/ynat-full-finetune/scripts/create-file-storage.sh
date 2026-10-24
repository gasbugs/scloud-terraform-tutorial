#!/usr/bin/env bash
# Usage: bash scripts/create-file-storage.sh ZONE [VOLUME_NAME]
set -euo pipefail
umask 077
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$LAB_DIR/tools:$PATH"
if [[ $# -lt 1 || $# -gt 2 || -z "${1:-}" ]]; then
  echo 'Usage: bash scripts/create-file-storage.sh ZONE [VOLUME_NAME]' >&2
  echo 'ZONE must be confirmed to support SAT and HighPerformanceSSD before running this script.' >&2
  exit 2
fi
command -v scp-cli >/dev/null || { echo 'Install scp-cli and configure authentication first.' >&2; exit 1; }
SAT_ZONE="$1"
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
printf '%s\n' "$SAT_ZONE" > "$EVIDENCE_DIR/volume-zone.txt"
printf '%s\n' "$SAT_VOLUME_NAME" > "$EVIDENCE_DIR/volume-name.txt"
printf 'Request evidence: %s\n' "$EVIDENCE_DIR"
# Do not create a billable volume until SAT mount and GPU quotas permit the lab.
# Save the read-only response privately and fail closed on missing or ambiguous data.
scp-cli quota account-quota list --size 1000 --format json > "$EVIDENCE_DIR/account-quotas.json"
python3 - "$EVIDENCE_DIR/account-quotas.json" <<'PYQUOTA'
import json
import sys
from pathlib import Path

quota_items = (
    'SAT.FILE_STORAGE.MOUNT.MAX.COUNT',
    'SAT.H100_GPU.MAX.COUNT',
    'SAT.B300_GPU.MAX.COUNT',
)
data = json.loads(Path(sys.argv[1]).read_text())
quotas = data.get('account_quotas')
if not isinstance(quotas, list):
    raise SystemExit('Quota response has no account_quotas list; no create request sent.')
values = {}
for quota_item in quota_items:
    matches = [item for item in quotas if isinstance(item, dict) and item.get('quota_item') == quota_item]
    if len(matches) != 1:
        raise SystemExit(f'Expected one {quota_item} record, found {len(matches)}; no create request sent.')
    if matches[0].get('request_class') != 'Account':
        raise SystemExit(f'{quota_item} does not have Account scope; no create request sent.')
    applied = matches[0].get('applied_value')
    if isinstance(applied, bool) or not isinstance(applied, int):
        raise SystemExit(f'{quota_item} has invalid applied_value={applied!r}; no create request sent.')
    values[quota_item] = applied
    print(f'{quota_item} applied_value={applied}')
if values[quota_items[0]] < 1 or max(values[quota_items[1]], values[quota_items[2]]) < 1:
    raise SystemExit('SAT File Storage or GPU quota is zero; no billable volume create request sent.')

PYQUOTA
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
# Do not share --debug true output; it can expose authentication headers and tokens.
if scp-cli filestorage volume create \
  --zone "$SAT_ZONE" \
  --type_name HighPerformanceSSD \
  --protocol NFS \
  --name "$SAT_VOLUME_NAME" | tee "$EVIDENCE_DIR/create-response.txt"; then
  :
else
  status=$?
  echo 'Creation failed. If the error is filestorage.BadRequest.Invalid.zone, verify HighPerformanceSSD support for the specified zone before any new attempt.' >&2
  exit "$status"
fi
printf 'Enter volume_id from the response above (not SAT Volume ID): '
read -r SAT_FILE_VOLUME_ID
[[ -n "$SAT_FILE_VOLUME_ID" ]] || { echo 'No ID entered; inspect the response before retrying.' >&2; exit 1; }
scp-cli filestorage volume show --volume_id "$SAT_FILE_VOLUME_ID" | tee "$EVIDENCE_DIR/volume-after.txt"
printf '%s\n' "$SAT_FILE_VOLUME_ID" > "$EVIDENCE_DIR/volume-id.txt"
printf 'Request and lookup recorded in %s\n' "$EVIDENCE_DIR"
echo 'Confirm Available/ready state in the CLI show response above before continuing.'
echo 'File Storage creation does not establish a SAT Volume connection; scp-cli v2.1.0 has no SAT connection command.'
