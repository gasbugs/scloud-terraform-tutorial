#!/usr/bin/env bash
# Usage: bash scripts/push-training-image.sh REPOSITORY_ENDPOINT TAG
set -euo pipefail
if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
  echo 'Usage: bash scripts/push-training-image.sh REPOSITORY_ENDPOINT TAG' >&2
  exit 2
fi
SAT_REPOSITORY_ENDPOINT="$1"
SAT_PUSH_HOST="${SAT_REPOSITORY_ENDPOINT%%/*}"
SAT_IMAGE_TAG="$2"
[[ -n "$SAT_PUSH_HOST" && "$SAT_REPOSITORY_ENDPOINT" != *://* && "$SAT_REPOSITORY_ENDPOINT" == */ynat-full-ft ]] || { echo 'Use the exact private Repository endpoint (host:port/ynat-full-ft), without https://.' >&2; exit 2; }
[[ "$SAT_IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] || { echo 'Invalid Docker tag.' >&2; exit 2; }
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB_DIR"
docker info >/dev/null
# Build only the execution environment; data is uploaded through NFS.
SAT_IMAGE_REF="$SAT_REPOSITORY_ENDPOINT/trainer:$SAT_IMAGE_TAG"
docker build --platform linux/amd64 -f Dockerfile.runtime -t "$SAT_IMAGE_REF" .
docker run --rm --network none "$SAT_IMAGE_REF" python -c 'import torch, transformers, datasets; print(torch.__version__, transformers.__version__, datasets.__version__)'
read -r -s -p 'SCR username: ' SAT_SCR_USER
printf '\n'
read -r -s -p 'SCR password: ' SAT_SCR_PASSWORD
printf '\n'
printf '%s' "$SAT_SCR_PASSWORD" | docker login "$SAT_PUSH_HOST" --username "$SAT_SCR_USER" --password-stdin
unset SAT_SCR_PASSWORD SAT_SCR_USER
# Keep credentials only until this upload attempt ends.
trap 'docker logout "$SAT_PUSH_HOST" >/dev/null 2>&1 || true' EXIT
docker push "$SAT_IMAGE_REF"
echo "Uploaded: $SAT_IMAGE_REF"
echo 'Record the digest above. Use the SAT pull endpoint for the Job image URL.'
