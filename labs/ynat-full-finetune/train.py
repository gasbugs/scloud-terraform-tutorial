import argparse
import csv
import hashlib
import json
import math
import random
import time
from pathlib import Path

import torch
from torch.utils.data import DataLoader
from transformers import AutoModelForCausalLM, AutoTokenizer
from common import LABELS, prompt, score

p = argparse.ArgumentParser()
p.add_argument('--mode', choices=['smoke', 'full'], required=True)
p.add_argument('--output', required=True)
p.add_argument('--bundle', required=True, help='File Storage release bundle directory')
a = p.parse_args()
out, bundle = Path(a.output), Path(a.bundle)
random.seed(42)
torch.manual_seed(42)
assert torch.cuda.is_available(), 'CUDA GPU required'
assert torch.cuda.device_count() == 1, 'Allocate exactly one visible GPU'
assert torch.cuda.is_bf16_supported(), 'This version requires a BF16-capable GPU; do not silently change precision'
manifest = json.loads((bundle/'manifest.json').read_text())

def load(name):
    path = bundle/f'{name}.jsonl'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest['files'][name]['sha256']
    return [json.loads(line) for line in path.read_text().splitlines()]

train, test = load('train'), load('test')
if a.mode == 'smoke':
    # Balanced small subsets: 10/class train => 70 examples => 5 updates at batch 16.
    train = [r for k in range(7) for r in [x for x in train if x['label'] == k][:10]]
    test = [r for k in range(7) for r in [x for x in test if x['label'] == k][:2]]
assert not ({r['title'] for r in train} & {r['title'] for r in test})
tok = AutoTokenizer.from_pretrained(bundle/'model', local_files_only=True)
tok.pad_token = tok.eos_token
model = AutoModelForCausalLM.from_pretrained(bundle/'model', local_files_only=True,
    torch_dtype=torch.float32, attn_implementation='sdpa').to('cuda')
model.config.use_cache = False
for param in model.parameters():
    param.requires_grad_(True)
params = list(model.parameters())
assert all(param.requires_grad for param in params)
# A backbone parameter, not only the output layer, must change.
tracked_name, tracked = next((n, v) for n, v in model.named_parameters() if 'layers.0.self_attn.q_proj.weight' in n)
tracked_before = tracked.detach().cpu().clone()
print(json.dumps(dict(event='START', mode=a.mode, gpu=torch.cuda.get_device_name(),
    train_rows=len(train), test_rows=len(test), total_parameters=sum(v.numel() for v in params),
    trainable_parameters=sum(v.numel() for v in params if v.requires_grad)), ensure_ascii=False), flush=True)

def evaluate(stage):
    model.eval()
    tok.padding_side = 'left'
    predictions, raw = [], []
    start = time.monotonic()
    for i in range(0, len(test), 4):
        batch = test[i:i+4]
        inputs = tok([prompt(r['title']) for r in batch], return_tensors='pt',
                     padding=True, add_special_tokens=False).to('cuda')
        with torch.inference_mode(), torch.autocast('cuda', dtype=torch.bfloat16):
            generated = model.generate(**inputs, max_new_tokens=12, do_sample=False,
                use_cache=True, pad_token_id=tok.pad_token_id, eos_token_id=tok.eos_token_id)
        texts = tok.batch_decode(generated[:, inputs['input_ids'].shape[1]:], skip_special_tokens=True)
        for text in texts:
            answer = text.strip()
            raw.append(answer)
            predictions.append(LABELS.index(answer) if answer in LABELS else -1)
        if i % 100 == 0:
            print(f'{stage}: {min(i+4,len(test))}/{len(test)}', flush=True)
    metrics = score([r['label'] for r in test], predictions)
    metrics['seconds'] = time.monotonic()-start
    (out/f'{stage}.json').write_text(json.dumps(dict(metrics=metrics, predictions=predictions,
                                                   raw=raw), ensure_ascii=False, indent=2))
    print(stage, metrics, flush=True)
    return metrics, predictions, raw

before, bp, br = evaluate('before')
model.train()
model.gradient_checkpointing_enable()
model.config.use_cache = False

def collate(rows):
    n = max(len(r['input_ids']) for r in rows)
    return {k: torch.tensor([r[k]+[pad]*(n-len(r[k])) for r in rows], device='cuda')
            for k, pad in [('input_ids', tok.pad_token_id), ('labels', -100)]} | {
        'attention_mask': torch.tensor([[1]*len(r['input_ids'])+[0]*(n-len(r['input_ids'])) for r in rows], device='cuda')}

loader = DataLoader(train, batch_size=2, shuffle=True, collate_fn=collate, num_workers=0,
                    generator=torch.Generator().manual_seed(42))
optimizer = torch.optim.AdamW(params, lr=2e-5, weight_decay=.01, foreach=False)
updates = min(100, math.ceil(len(loader)/8))
warmup = max(1, math.ceil(updates*.1))
step, group_count, group_loss = 0, 0, 0.0
step_times = []
started = time.monotonic()
optimizer.zero_grad(set_to_none=True)
with (out/'training.jsonl').open('w', buffering=1) as log:
    for i, batch in enumerate(loader):
        group_size = min(8, len(loader)-(i//8)*8)
        with torch.autocast('cuda', dtype=torch.bfloat16):
            loss = model(**batch).loss
        assert torch.isfinite(loss), 'Non-finite loss: abort'
        (loss/group_size).backward()
        group_loss += loss.item()
        group_count += 1
        if group_count == group_size:
            torch.nn.utils.clip_grad_norm_(params, 1.0, error_if_nonfinite=True)
            factor = min((step+1)/warmup, max(0.0, (updates-step)/max(1, updates-warmup)))
            for group in optimizer.param_groups:
                group['lr'] = 2e-5*factor
            optimizer.step()
            optimizer.zero_grad(set_to_none=True)
            torch.cuda.synchronize()
            step += 1
            elapsed = time.monotonic()-started
            step_times.append(elapsed)
            rec = dict(step=step, loss=group_loss/group_count, elapsed_seconds=elapsed,
                       peak_memory_gb=torch.cuda.max_memory_allocated()/1e9)
            log.write(json.dumps(rec)+'\n')
            print(rec, flush=True)
            group_count, group_loss = 0, 0.0
            if step >= updates:
                break
changed = not torch.equal(tracked_before, tracked.detach().cpu())
assert changed, 'Tracked backbone weights did not change'
del optimizer, params, tracked_before
model.gradient_checkpointing_disable()
torch.cuda.empty_cache()
after, ap, ar = evaluate('after')
with (out/'predictions.csv').open('w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id','title','gold','before','after','before_correct','after_correct'])
    for r, b, c, rb, ra in zip(test, bp, ap, br, ar):
        writer.writerow([r['id'],r['title'],LABELS[r['label']],rb,ra,b==r['label'],c==r['label']])
model.config.use_cache = True
model.save_pretrained(out/'model', safe_serialization=True)
tok.save_pretrained(out/'model')
# Release the old model before verifying that saved output can be loaded on CPU.
del tracked, model
import gc
gc.collect()
torch.cuda.empty_cache()
reloaded = AutoModelForCausalLM.from_pretrained(out/'model', local_files_only=True, torch_dtype=torch.float32)
del reloaded
result = dict(mode=a.mode, before=before, after=after,
    accuracy_delta_pp=100*(after['accuracy']-before['accuracy']),
    macro_f1_delta=after['macro_f1']-before['macro_f1'], updates=step,
    train_seconds=step_times[-1], peak_memory_gb=torch.cuda.max_memory_allocated()/1e9,
    backbone_weight_changed=changed, tracked_parameter=tracked_name,
    checkpoint_reload_verified=True, source=manifest)
(out/'comparison.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
(out/'comparison.md').write_text(
    '# 학습 전후 비교\n\n'
    f"모드: {a.mode}. 평가 {len(test)}건. 교육용 표본 결과이며 공식 KLUE 점수가 아닙니다.\n\n"
    '| 지표 | 학습 전 | 학습 후 |\n|---|---:|---:|\n'
    f"| 정확도 | {before['accuracy']:.2%} | {after['accuracy']:.2%} |\n"
    f"| macro-F1 | {before['macro_f1']:.4f} | {after['macro_f1']:.4f} |\n"
    f"| 잘못된 출력 비율 | {before['invalid_rate']:.2%} | {after['invalid_rate']:.2%} |\n\n"
    f"정확도 차이: {result['accuracy_delta_pp']:+.2f}%p. 품질 향상은 보장하지 않습니다.\n")
print('PASS: training, evaluation, save, and CPU checkpoint reload completed', flush=True)
