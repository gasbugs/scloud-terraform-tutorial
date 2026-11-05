#!/usr/bin/env python3
"""Train a small CNN on Fashion-MNIST and compare held-out accuracy."""
import argparse
import hashlib
import json
import random
import time
from pathlib import Path

import numpy as np
import torch
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score
from torch import nn
from torch.utils.data import DataLoader, TensorDataset

def load(bundle, manifest, name):
    path = bundle / f"{name}.npz"
    assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest["files"][name]["sha256"]
    with np.load(path) as data:
        x = torch.from_numpy(data["images"].copy()).unsqueeze(1).float().div_(255)
        y = torch.from_numpy(data["labels"].copy()).long()
    assert len(y) == manifest["files"][name]["count"]
    return TensorDataset(x, y)

class CNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
        )
        self.classifier = nn.Sequential(nn.Flatten(), nn.Linear(64 * 7 * 7, 128),
                                        nn.ReLU(), nn.Dropout(0.2), nn.Linear(128, 10))
    def forward(self, x):
        return self.classifier(self.features(x))

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", default="/bundle")
    p.add_argument("--output", default="/output/image")
    p.add_argument("--epochs", type=int, default=4)
    a = p.parse_args()
    assert torch.cuda.is_available(), "GPU required"
    torch.manual_seed(42)
    random.seed(42)
    bundle, out = Path(a.bundle) / "image", Path(a.output)
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((bundle / "manifest.json").read_text(encoding="utf-8"))
    train = load(bundle, manifest, "train")
    val = load(bundle, manifest, "val")
    test = load(bundle, manifest, "test")
    model = CNN().cuda()
    criterion = nn.CrossEntropyLoss()
    def loader(dataset, shuffle=False):
        return DataLoader(dataset, batch_size=64 if shuffle else 256, shuffle=shuffle,
                          pin_memory=True, num_workers=2)
    def evaluate(name, dataset):
        model.eval()
        gold, pred = [], []
        with torch.inference_mode():
            for x, y in loader(dataset):
                guess = model(x.cuda(non_blocking=True)).argmax(1).cpu()
                gold.extend(y.tolist())
                pred.extend(guess.tolist())
        result = {"count": len(gold), "accuracy": accuracy_score(gold, pred),
                  "macro_f1": f1_score(gold, pred, average="macro")}
        (out / f"{name}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
        if name == "after":
            (out / "confusion_matrix.json").write_text(
                json.dumps({"labels_ko": manifest["labels_ko"],
                            "matrix": confusion_matrix(gold, pred).tolist()}, ensure_ascii=False, indent=2))
        return result
    started = time.time()
    before = evaluate("before", test)
    optimizer = torch.optim.AdamW(model.parameters(), lr=0.001, weight_decay=0.001)
    best = -1
    history = []
    for epoch in range(1, a.epochs + 1):
        model.train()
        losses = []
        for step, (x, y) in enumerate(loader(train, True), 1):
            x, y = x.cuda(non_blocking=True), y.cuda(non_blocking=True)
            optimizer.zero_grad(set_to_none=True)
            loss = criterion(model(x), y)
            assert torch.isfinite(loss), "Non-finite training loss"
            loss.backward()
            optimizer.step()
            losses.append(loss.item())
            if step % 50 == 0:
                print(json.dumps({"task": "image", "epoch": epoch, "step": step, "loss": losses[-1]}), flush=True)
        val_metrics = evaluate(f"val-epoch-{epoch}", val)
        history.append({"epoch": epoch, "train_loss": sum(losses) / len(losses), **val_metrics})
        if val_metrics["macro_f1"] > best:
            best = val_metrics["macro_f1"]
            torch.save(model.state_dict(), out / "model.pt")
        print(json.dumps(history[-1], ensure_ascii=False), flush=True)
    model = CNN().cuda()
    model.load_state_dict(torch.load(out / "model.pt", map_location="cuda", weights_only=True))
    after = evaluate("after", test)
    result = {"task": "image", "before": before, "after": after,
              "accuracy_delta_pp": 100 * (after["accuracy"] - before["accuracy"]),
              "macro_f1_delta": after["macro_f1"] - before["macro_f1"],
              "epochs": a.epochs, "history": history, "elapsed_seconds": time.time() - started,
              "gpu": torch.cuda.get_device_name(0), "checkpoint_reload_verified": True}
    (out / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    main()
