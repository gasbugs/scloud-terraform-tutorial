#!/usr/bin/env bash
# Usage: bash scripts/push-training-image.sh PUSH_HOST TAG
set -euo pipefail
if [[ $# != 2 || -z "$1" || -z "$2" ]]; then
  echo 'Usage: bash scripts/push-training-image.sh PUSH_HOST TAG' >&2
  exit 2
fi
SAT_PUSH_HOST="$1"
SAT_IMAGE_TAG="$2"
[[ "$SAT_PUSH_HOST" != *://* && "$SAT_PUSH_HOST" != */* ]] || { echo 'Use hostname[:port], without https:// or path.' >&2; exit 2; }
[[ "$SAT_IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] || { echo 'Invalid Docker tag.' >&2; exit 2; }
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB_DIR"
[[ -s bundle/manifest.json ]] || { echo 'Prepare bundle first using guide section 7.' >&2; exit 1; }
docker info >/dev/null
# Dockerfile uses this exact local base tag.
docker image inspect sat-ynat-runtime:v1 >/dev/null
SAT_IMAGE_REF="$SAT_PUSH_HOST/ynat-full-ft:$SAT_IMAGE_TAG"
docker build --platform linux/amd64 -t "$SAT_IMAGE_REF" .
docker run --rm --network none "$SAT_IMAGE_REF" python -c 'from transformers import AutoTokenizer; AutoTokenizer.from_pretrained("/opt/bundle/model", local_files_only=True); print("PASS: offline tokenizer")'
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
