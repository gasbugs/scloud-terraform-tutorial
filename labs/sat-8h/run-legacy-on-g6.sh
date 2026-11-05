#!/usr/bin/env bash
set -euo pipefail
status=/home/ubuntu/sat-ynat-legacy-status
log=/home/ubuntu/sat-ynat-legacy.log
echo RUNNING > "$status"
finish() { code=$?; if (( code == 0 )); then echo PASS > "$status"; else echo "FAILED:$code" > "$status"; fi; }
trap finish EXIT
docker run --rm --gpus all --shm-size 4g \
  -v /home/ubuntu/sat-ynat-legacy:/opt/legacy:ro \
  -v /home/ubuntu/sat-ynat-legacy-bundle:/bundle:ro \
  -v /home/ubuntu/sat-ynat-legacy-output:/output \
  -w /opt/legacy sat-8h:local \
  timeout 600 python /opt/legacy/train.py --mode smoke --output /output --bundle /bundle > "$log" 2>&1
