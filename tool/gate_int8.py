# Gate 4: the shipped INT8 artifact itself must hold the calibration —
# dynamic quantization is not free and must be measured, not assumed.
import os
import sys

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from eval_models import EN_PAIRS, RU_PAIRS  # noqa: E402

tok = Tokenizer.from_file(os.path.join(HERE, "tokenizer_trimmed.json"))
session = ort.InferenceSession(
    os.path.join(HERE, "minilm_multilingual_trimmed_quantized.onnx"),
    providers=["CPUExecutionProvider"],
)


def embed(text):
    ids = np.array([tok.encode(text).ids], dtype=np.int64)
    hidden = session.run(
        ["last_hidden_state"],
        {"input_ids": ids, "attention_mask": np.ones_like(ids)},
    )[0]
    v = hidden[0].mean(axis=0)
    return v / np.linalg.norm(v)


for label, pairs in (("EN", EN_PAIRS), ("RU", RU_PAIRS)):
    offers = np.stack([embed(a) for a, _ in pairs])
    needs = np.stack([embed(b) for _, b in pairs])
    sims = offers @ needs.T
    tp = sorted(np.diag(sims).tolist())
    mask = ~np.eye(len(pairs), dtype=bool)
    neg = sorted(sims[mask].tolist())
    for th in (0.45,):
        recall = sum(x >= th for x in tp) / len(tp)
        false = sum(x >= th for x in neg) / len(neg)
        print(f"{label} int8 th={th}: recall={recall*100:.0f}% "
              f"false={false*100:.1f}% (true min {tp[0]:.3f}, "
              f"neg p95 {neg[int(0.95*len(neg))]:.3f})")
