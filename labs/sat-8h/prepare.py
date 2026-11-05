#!/usr/bin/env python3
"""Prepare pinned, disjoint Korean text and image teaching bundles on CPU."""
import argparse
import gzip
import hashlib
import json
import random
import struct
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np
from datasets import load_dataset
from huggingface_hub import HfApi, snapshot_download
from PIL import Image

LABELS = ["IT과학", "경제", "사회", "생활문화", "세계", "스포츠", "정치"]
FASHION = ["티셔츠/상의", "바지", "풀오버", "원피스", "코트", "샌들", "셔츠", "운동화", "가방", "앵클부츠"]
BASE = "https://raw.githubusercontent.com/zalandoresearch/fashion-mnist/master/data/fashion"
MD5 = {
    "train-images-idx3-ubyte.gz": "8d4fb7e6c68d591d4c3dfef9ec88bf0d",
    "train-labels-idx1-ubyte.gz": "25c81989df183df01b3e8a0aad5dffbe",
    "t10k-images-idx3-ubyte.gz": "bef4ecab320f06d8554ea6380940ec79",
    "t10k-labels-idx1-ubyte.gz": "bb300cfdad3c16e7a12a480ee83cd310",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_jsonl(path, rows):
    path.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


def text_bundle(out):
    model_id, data_id = "klue/bert-base", "klue/klue"
    api = HfApi()
    model_rev = api.model_info(model_id).sha
    data_rev = api.dataset_info(data_id).sha
    snapshot_download(
        model_id, revision=model_rev, local_dir=out / "text/model",
        allow_patterns=["*.json", "*.txt", "*.safetensors", "README.md"],
    )
    dataset = load_dataset(data_id, "ynat", revision=data_rev)
    assert dataset["train"].features["label"].names == LABELS
    rng = random.Random(42)
    seen = set()
    splits = {"train": [], "val": [], "test": []}
    for source, targets in [
        ("train", [("train", 300), ("val", 60)]),
        ("validation", [("test", 100)]),
    ]:
        buckets = defaultdict(list)
        for row in dataset[source]:
            title = " ".join(row["title"].split())
            if not title or title in seen:
                continue
            seen.add(title)
            buckets[int(row["label"])].append({"id": row["guid"], "title": title, "label": int(row["label"])})
        for label in range(7):
            rng.shuffle(buckets[label])
            needed = sum(count for _, count in targets)
            assert len(buckets[label]) >= needed, (source, label, len(buckets[label]))
            pos = 0
            for target, count in targets:
                splits[target].extend(buckets[label][pos : pos + count])
                pos += count
    out_dir = out / "text"
    manifest = {"task": "Korean news title classification", "dataset": data_id,
                "dataset_revision": data_rev, "dataset_license": "CC-BY-SA-4.0",
                "model": model_id, "model_revision": model_rev,
                "model_license": "CC-BY-SA-4.0", "seed": 42, "labels": LABELS, "files": {}}
    for name, rows in splits.items():
        rng.shuffle(rows)
        path = out_dir / f"{name}.jsonl"
        write_jsonl(path, rows)
        manifest["files"][name] = {"count": len(rows), "sha256": digest(path)}
    write_jsonl(out_dir / "sample-text.jsonl", splits["train"][:10])
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def fashion_download(folder, name):
    path = folder / name
    if not path.exists():
        urllib.request.urlretrieve(f"{BASE}/{name}", path)
    actual = hashlib.md5(path.read_bytes()).hexdigest()
    if actual != MD5[name]:
        raise ValueError(f"{name}: MD5 {actual} != expected {MD5[name]}")
    return path


def read_idx(path, kind):
    raw = gzip.decompress(path.read_bytes())
    if kind == "image":
        magic, count, height, width = struct.unpack(">IIII", raw[:16])
        assert (magic, height, width) == (2051, 28, 28)
        return np.frombuffer(raw, dtype=np.uint8, offset=16).reshape(count, 28, 28).copy()
    magic, count = struct.unpack(">II", raw[:8])
    assert magic == 2049
    return np.frombuffer(raw, dtype=np.uint8, offset=8, count=count).copy()


def image_bundle(out):
    folder = out / "image"
    source = folder / "source"
    source.mkdir(parents=True, exist_ok=True)
    paths = {name: fashion_download(source, name) for name in MD5}
    x_train = read_idx(paths["train-images-idx3-ubyte.gz"], "image")
    y_train = read_idx(paths["train-labels-idx1-ubyte.gz"], "label")
    x_test = read_idx(paths["t10k-images-idx3-ubyte.gz"], "image")
    y_test = read_idx(paths["t10k-labels-idx1-ubyte.gz"], "label")
    assert (len(x_train), len(x_test)) == (60000, 10000)
    rng = np.random.default_rng(42)
    train_idx, val_idx, test_idx = [], [], []
    for label in range(10):
        selected = rng.permutation(np.flatnonzero(y_train == label))
        train_idx.extend(selected[:1200])
        val_idx.extend(selected[1200:1350])
        test_idx.extend(rng.permutation(np.flatnonzero(y_test == label))[:200])
    assert not (set(train_idx) & set(val_idx))
    subsets = {
        "train": (x_train[train_idx], y_train[train_idx]),
        "val": (x_train[val_idx], y_train[val_idx]),
        "test": (x_test[test_idx], y_test[test_idx]),
    }
    manifest = {"task": "Fashion-MNIST image classification",
                "source": "zalandoresearch/fashion-mnist", "source_revision": "master",
                "source_url": BASE, "license": "MIT", "seed": 42,
                "labels_ko": FASHION, "files": {}}
    for name, (images, labels) in subsets.items():
        path = folder / f"{name}.npz"
        np.savez_compressed(path, images=images, labels=labels)
        manifest["files"][name] = {"count": len(labels), "sha256": digest(path)}
    sample = folder / "sample-images"
    sample.mkdir(exist_ok=True)
    for label in range(10):
        index = int(np.flatnonzero(subsets["test"][1] == label)[0])
        Image.fromarray(subsets["test"][0][index]).save(sample / f"{label:02d}.png")
    (folder / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="/bundle")
    parser.add_argument("--task", choices=("text", "image", "all"), default="all")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.task in ("text", "all"):
        (out / "text").mkdir(exist_ok=True)
        if (out / "text/manifest.json").exists():
            raise SystemExit("Text bundle already exists; choose a fresh directory")
        text_bundle(out)
    if args.task in ("image", "all"):
        (out / "image").mkdir(exist_ok=True)
        if (out / "image/manifest.json").exists():
            raise SystemExit("Image bundle already exists; choose a fresh directory")
        image_bundle(out)
    print("PASS: source hashes, disjoint splits, sample files, and manifests prepared")


if __name__ == "__main__":
    main()
