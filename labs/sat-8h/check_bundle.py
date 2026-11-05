#!/usr/bin/env python3
"""CPU-only verification before starting a billable G6 instance."""
import hashlib
import json
from collections import Counter
from pathlib import Path

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer
from train_image import CNN, load as load_image

root = Path("/bundle")
text = root / "text"
manifest = json.loads((text / "manifest.json").read_text(encoding="utf-8"))
splits = {}
for name in ("train", "val", "test"):
    path = text / f"{name}.jsonl"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest["files"][name]["sha256"]
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == manifest["files"][name]["count"]
    assert Counter(row["label"] for row in rows) == {label: len(rows) // 7 for label in range(7)}
    splits[name] = rows
assert len(set().union(*(set(row["title"] for row in rows) for rows in splits.values()))) == sum(map(len, splits.values()))
tokenizer = AutoTokenizer.from_pretrained(text / "model", local_files_only=True)
model = AutoModelForSequenceClassification.from_pretrained(text / "model", local_files_only=True, num_labels=7)
with torch.inference_mode():
    logits = model(**tokenizer(splits["train"][0]["title"], return_tensors="pt")).logits
assert logits.shape == (1, 7)
print("PASS text bundle, balanced disjoint splits, model forward", flush=True)

image = root / "image"
manifest = json.loads((image / "manifest.json").read_text(encoding="utf-8"))
for name, expected in (("train", 12000), ("val", 1500), ("test", 2000)):
    dataset = load_image(image, manifest, name)
    assert len(dataset) == expected
    assert Counter(dataset.tensors[1].tolist()) == {label: expected // 10 for label in range(10)}
with torch.inference_mode():
    logits = CNN()(dataset.tensors[0][:2])
assert logits.shape == (2, 10)
assert len(list((image / "sample-images").glob("*.png"))) == 10
print("PASS image bundle, balanced splits, sample PNG, CNN forward", flush=True)
