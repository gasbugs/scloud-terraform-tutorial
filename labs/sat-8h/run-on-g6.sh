#!/usr/bin/env bash
set -euo pipefail
status=/home/ubuntu/sat-8h-status
log=/home/ubuntu/sat-8h-training.log
echo RUNNING > "$status"
finish() { code=$?; if (( code == 0 )); then echo PASS > "$status"; else echo "FAILED:$code" > "$status"; fi; }
trap finish EXIT
docker run --rm --gpus all --shm-size 2g \
  -v /home/ubuntu/sat-8h-bundle:/bundle:ro \
  -v /home/ubuntu/sat-8h-output:/output \
  sat-8h:local /lesson/run_all.sh > "$log" 2>&1
