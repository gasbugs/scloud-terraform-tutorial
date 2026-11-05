#!/usr/bin/env python3
"""Fine-tune Korean news topic classifier and compare held-out performance."""
import argparse
import hashlib
import json
import random
import time
from pathlib import Path

import torch
from sklearn.metrics import accuracy_score, f1_score
from torch.utils.data import DataLoader
from transformers import AutoModelForSequenceClassification, AutoTokenizer

def rows_for(bundle, manifest, name):
    path = bundle / f"{name}.jsonl"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest["files"][name]["sha256"]
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == manifest["files"][name]["count"]
    return rows

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", default="/bundle")
    p.add_argument("--output", default="/output/text")
    p.add_argument("--epochs", type=int, default=2)
    a = p.parse_args()
    torch.manual_seed(42)
    random.seed(42)
    assert torch.cuda.is_available(), "GPU required"
    bundle, out = Path(a.bundle) / "text", Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
    train = rows_for(bundle, manifest, "train")
    val = rows_for(bundle, manifest, "val")
    test = rows_for(bundle, manifest, "test")
    assert not ({r["title"] for r in train} & {r["title"] for r in test})
    labels = manifest["labels"]
    tokenizer = AutoTokenizer.from_pretrained(bundle / "model", local_files_only=True)
    model = AutoModelForSequenceClassification.from_pretrained(
        bundle / "model", local_files_only=True, num_labels=len(labels),
        id2label={i: label for i, label in enumerate(labels)},
        label2id={label: i for i, label in enumerate(labels)},
    ).cuda()
    model.config.use_cache = False
    def batchify(rows):
        tokens = tokenizer([r["title"] for r in rows], padding=True, truncation=True,
                           max_length=64, return_tensors="pt")
        tokens["labels"] = torch.tensor([r["label"] for r in rows])
        return {key: value.cuda(non_blocking=True) for key, value in tokens.items()}
    def evaluate(name, rows):
        model.eval()
        gold, pred = [], []
        with torch.inference_mode():
            for start in range(0, len(rows), 32):
                batch = batchify(rows[start:start + 32])
                with torch.autocast("cuda", dtype=torch.bfloat16):
                    logits = model(**batch).logits
                gold.extend(batch["labels"].cpu().tolist())
                pred.extend(logits.argmax(-1).cpu().tolist())
        result = {"count": len(gold), "accuracy": accuracy_score(gold, pred),
                  "macro_f1": f1_score(gold, pred, average="macro")}
        (out / f"{name}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
        return result
    started = time.time()
    before = evaluate("before", test)
    optimizer = torch.optim.AdamW(model.parameters(), lr=3e-5, weight_decay=0.01)
    train_loader = DataLoader(train, batch_size=16, shuffle=True, collate_fn=batchify,
                              generator=torch.Generator().manual_seed(42))
    best = -1
    history = []
    for epoch in range(1, a.epochs + 1):
        model.train()
        losses = []
        for step, batch in enumerate(train_loader, 1):
            optimizer.zero_grad(set_to_none=True)
            with torch.autocast("cuda", dtype=torch.bfloat16):
                loss = model(**batch).loss
            assert torch.isfinite(loss), "Non-finite training loss"
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            losses.append(loss.item())
            if step % 40 == 0:
                print(json.dumps({"task": "text", "epoch": epoch, "step": step, "loss": losses[-1]}), flush=True)
        val_metrics = evaluate(f"val-epoch-{epoch}", val)
        history.append({"epoch": epoch, "train_loss": sum(losses) / len(losses), **val_metrics})
        if val_metrics["macro_f1"] > best:
            best = val_metrics["macro_f1"]
            model.save_pretrained(out / "model", safe_serialization=True)
            tokenizer.save_pretrained(out / "model")
        print(json.dumps(history[-1], ensure_ascii=False), flush=True)
    model = AutoModelForSequenceClassification.from_pretrained(out / "model", local_files_only=True).cuda()
    after = evaluate("after", test)
    result = {"task": "text", "before": before, "after": after,
              "accuracy_delta_pp": 100 * (after["accuracy"] - before["accuracy"]),
              "macro_f1_delta": after["macro_f1"] - before["macro_f1"],
              "epochs": a.epochs, "history": history, "elapsed_seconds": time.time() - started,
              "gpu": torch.cuda.get_device_name(0), "checkpoint_reload_verified": True,
              "dataset_revision": manifest["dataset_revision"], "model_revision": manifest["model_revision"]}
    (out / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
