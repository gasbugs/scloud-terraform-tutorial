"""Run once on CPU, before renting a GPU. Downloads public model and data."""
import argparse
import hashlib
import json
import random
from pathlib import Path
from collections import Counter
from datasets import load_dataset
from huggingface_hub import HfApi, snapshot_download
from transformers import AutoTokenizer
from common import LABELS, normalize, prompt

p = argparse.ArgumentParser()
p.add_argument('--out', default='/bundle')
a = p.parse_args()
out = Path(a.out)
out.mkdir(parents=True, exist_ok=True)
if (out/'manifest.json').exists():
    raise SystemExit('Existing bundle: use a new empty directory, do not overwrite.')
api = HfApi()
model_id, data_id = 'Qwen/Qwen2.5-0.5B', 'klue/klue'
model_rev = api.model_info(model_id).sha
data_rev = api.dataset_info(data_id).sha
snapshot_download(model_id, revision=model_rev, local_dir=out/'model',
                  allow_patterns=['*.json', '*.safetensors', '*.txt', '*.model', '*.tiktoken', '*.md', 'LICENSE*'])
tok = AutoTokenizer.from_pretrained(out/'model', local_files_only=True)
ds = load_dataset(data_id, 'ynat', revision=data_rev)
assert ds['train'].features['label'].names == LABELS
rng = random.Random(42)
seen = set()
counts = Counter()

def clean(split):
    buckets = [[] for _ in LABELS]
    for row in ds[split]:
        title = normalize(row['title'])
        if not title or title in seen:
            counts['empty_or_duplicate'] += 1
            continue
        seen.add(title)
        label = int(row['label'])
        ids = tok.encode(prompt(title), add_special_tokens=False)
        target = tok.encode(LABELS[label], add_special_tokens=False) + [tok.eos_token_id]
        if len(ids) + len(target) > 128:
            counts['over_128_tokens'] += 1
            continue
        buckets[label].append(dict(id=row['guid'], title=title, label=label,
                                   input_ids=ids + target,
                                   labels=[-100]*len(ids) + target))
    for b in buckets:
        rng.shuffle(b)
    return buckets

# Mark all original train titles seen, not only sampled rows: exclude overlap in validation.
train_buckets = clean('train')
valid_buckets = clean('validation')
train, dev, test = [], [], []
for k in range(7):
    assert len(train_buckets[k]) >= 250 and len(valid_buckets[k]) >= 100
    train.extend(train_buckets[k][:200])
    dev.extend(train_buckets[k][200:250])
    test.extend(valid_buckets[k][:100])
manifest = dict(model_id=model_id, model_revision=model_rev, dataset_id=data_id,
                dataset_revision=data_rev, seed=42, labels=LABELS,
                dataset_license='CC-BY-SA-4.0', model_license='Apache-2.0',
                transform='NFKC, deduplicate, exclude >128 tokens, balanced subsample',
                excluded=dict(counts), files={})
for name, rows in [('train', train), ('dev', dev), ('test', test)]:
    rng.shuffle(rows)
    path = out/f'{name}.jsonl'
    path.write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows))
    lens = sorted(len(r['input_ids']) for r in rows)
    manifest['files'][name] = dict(rows=len(rows), sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                                 tokens=sum(lens), p50=lens[len(lens)//2],
                                 p95=lens[int(len(lens)*.95)], max=max(lens))
(out/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
print(json.dumps(manifest, ensure_ascii=False, indent=2))
print('PASS: prepared offline bundle; no GPU used')
