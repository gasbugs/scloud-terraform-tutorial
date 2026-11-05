#!/usr/bin/env bash
set -euo pipefail
: "${BUNDLE:=/bundle}"
: "${OUTPUT:=/output}"
mkdir -p "$OUTPUT"
python /lesson/train_text.py --bundle "$BUNDLE" --output "$OUTPUT/text"
python /lesson/train_image.py --bundle "$BUNDLE" --output "$OUTPUT/image"
python - "$OUTPUT" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
for task in ('text','image'):
    result=json.loads((root/task/'comparison.json').read_text())
    print(task,json.dumps(result,ensure_ascii=False))
print('PASS: both tasks trained and evaluated')
PY
