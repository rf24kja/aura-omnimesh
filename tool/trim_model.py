# Vocabulary trimming for paraphrase-multilingual-MiniLM-L12-v2:
# keep Latin/Cyrillic/punctuation pieces (RU+EN product scope), slice the
# embedding matrix accordingly, re-export ONNX + dynamic int8.
#
# Correctness protocol:
#  - The reference trimmed tokenizer is built by EDITING the original
#    tokenizer.json (vocab replaced, normalizer/pre/post untouched), so
#    reference tokenization semantics stay exactly HF-canonical.
#  - Ship/no-ship gates printed at the end: <unk> count on the corpus,
#    cosine(full, trimmed) distribution, and the EN/RU calibration table
#    recomputed on the trimmed model.
import json
import os
import sys

import numpy as np
import torch
from tokenizers import Tokenizer
from transformers import AutoModel, AutoTokenizer

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_ID = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
TOKENIZER_JSON = os.path.join(HERE, "tokenizer.json")
OUT_FP32 = os.path.join(HERE, "minilm_multilingual_trimmed_fp32.onnx")
OUT_INT8 = os.path.join(HERE, "minilm_multilingual_trimmed_quantized.onnx")
OUT_TSV = os.path.join(HERE, "xlmr_trimmed_vocab.tsv")
OUT_TOKJSON = os.path.join(HERE, "tokenizer_trimmed.json")
MAX_KEPT = 10**9  # keep every script-allowed piece: in-scope tokenization is provably unchanged

sys.path.insert(0, HERE)
from eval_models import EN_PAIRS, RU_PAIRS  # noqa: E402


def rune_allowed(cp: int) -> bool:
    return (
        cp == 0x2581  # metaspace
        or 0x20 <= cp <= 0x7E  # ASCII
        or 0xA1 <= cp <= 0x17F  # Latin-1 supplement + Extended-A
        or 0x400 <= cp <= 0x4FF  # Cyrillic
        or 0x2000 <= cp <= 0x206F  # general punctuation
        or cp in (0x20AC, 0x20BD, 0x2116)  # € ₽ №
    )


def piece_allowed(piece: str) -> bool:
    return all(rune_allowed(ord(c)) for c in piece)


spec = json.load(open(TOKENIZER_JSON, encoding="utf-8"))
vocab = spec["model"]["vocab"]  # [[piece, score], ...], index == id

# --- selection ------------------------------------------------------------
specials = [0, 1, 2, 3]  # <s> <pad> </s> <unk>
candidates = [
    (i, p, s) for i, (p, s) in enumerate(vocab)
    if i not in specials and piece_allowed(p)
]
print(f"pieces passing script filter: {len(candidates)} of {len(vocab)}")
candidates.sort(key=lambda t: -t[2])  # highest unigram log-prob first
kept_tail = sorted(candidates[: MAX_KEPT - len(specials)], key=lambda t: t[0])
kept_ids = specials + [i for i, _, _ in kept_tail]
print(f"kept total: {len(kept_ids)}")

new_vocab = [vocab[i] for i in kept_ids]

# --- reference trimmed tokenizer (pipeline untouched) ---------------------
spec["model"]["vocab"] = new_vocab
spec["model"]["unk_id"] = 3
spec["added_tokens"] = [t for t in spec["added_tokens"] if t["id"] <= 3]
json.dump(spec, open(OUT_TOKJSON, "w", encoding="utf-8"), ensure_ascii=False)
trimmed_tok = Tokenizer.from_file(OUT_TOKJSON)

with open(OUT_TSV, "w", encoding="utf-8", newline="\n") as f:
    for piece, score in new_vocab:
        f.write(f"{piece}\t{score}\n")

# --- model surgery ---------------------------------------------------------
full_tok = AutoTokenizer.from_pretrained(MODEL_ID)
model = AutoModel.from_pretrained(MODEL_ID)
model.eval()

old_emb = model.get_input_embeddings()
idx = torch.tensor(kept_ids, dtype=torch.long)
new_emb = torch.nn.Embedding(len(kept_ids), old_emb.weight.shape[1],
                             padding_idx=1)
with torch.no_grad():
    new_emb.weight.copy_(old_emb.weight[idx])

full_model = AutoModel.from_pretrained(MODEL_ID)
full_model.eval()
model.set_input_embeddings(new_emb)
model.config.vocab_size = len(kept_ids)


def embed_full(text):
    enc = full_tok(text, return_tensors="pt", truncation=True, max_length=256)
    with torch.no_grad():
        h = full_model(**enc).last_hidden_state
    m = enc["attention_mask"].unsqueeze(-1).float()
    v = (h * m).sum(1) / m.sum(1)
    return torch.nn.functional.normalize(v, dim=1)[0]


def embed_trimmed(text):
    ids = trimmed_tok.encode(text).ids
    t = torch.tensor([ids])
    with torch.no_grad():
        h = model(input_ids=t, attention_mask=torch.ones_like(t)
                  ).last_hidden_state
    v = h.mean(1)
    return torch.nn.functional.normalize(v, dim=1)[0]


texts = [t for p in EN_PAIRS + RU_PAIRS for t in p]

# Gate 1: zero <unk> on the corpus.
unk_hits = sum(3 in trimmed_tok.encode(t).ids[1:-1] for t in texts)
print(f"corpus texts with <unk>: {unk_hits} of {len(texts)}")

# Gate 2: full-vs-trimmed embedding agreement.
cosines = sorted(
    float(embed_full(t) @ embed_trimmed(t)) for t in texts
)
print(f"cos(full,trimmed): min={cosines[0]:.4f} "
      f"p10={cosines[len(cosines)//10]:.4f} "
      f"mean={sum(cosines)/len(cosines):.4f}")

# Gate 3: calibration table on the trimmed model.
for label, pairs in (("EN", EN_PAIRS), ("RU", RU_PAIRS)):
    offers = torch.stack([embed_trimmed(a) for a, _ in pairs])
    needs = torch.stack([embed_trimmed(b) for _, b in pairs])
    sims = offers @ needs.T
    tp = sorted(sims.diag().tolist())
    neg = sorted(sims[~torch.eye(len(pairs), dtype=bool)].tolist())
    for th in (0.45,):
        recall = sum(x >= th for x in tp) / len(tp)
        false = sum(x >= th for x in neg) / len(neg)
        print(f"{label} th={th}: recall={recall*100:.0f}% "
              f"false={false*100:.1f}%  (true min {tp[0]:.3f})")

# --- export ----------------------------------------------------------------
enc = trimmed_tok.encode("пример текста для экспорта")
ids = torch.tensor([enc.ids])
dynamic = {0: "batch", 1: "sequence"}
torch.onnx.export(
    model,
    (ids, torch.ones_like(ids)),
    OUT_FP32,
    input_names=["input_ids", "attention_mask"],
    output_names=["last_hidden_state"],
    dynamic_axes={"input_ids": dynamic, "attention_mask": dynamic,
                  "last_hidden_state": dynamic},
    opset_version=17,
)
from onnxruntime.quantization import QuantType, quantize_dynamic  # noqa: E402

quantize_dynamic(OUT_FP32, OUT_INT8, weight_type=QuantType.QInt8)
print(f"fp32: {os.path.getsize(OUT_FP32)/1e6:.1f} MB | "
      f"int8: {os.path.getsize(OUT_INT8)/1e6:.1f} MB | "
      f"tsv: {os.path.getsize(OUT_TSV)/1e6:.1f} MB")

# Device parity beacon through the int8 artifact.
import onnxruntime as ort  # noqa: E402

session = ort.InferenceSession(OUT_INT8, providers=["CPUExecutionProvider"])
w = trimmed_tok.encode("warm up")
wi = np.array([w.ids], dtype=np.int64)
hidden = session.run(["last_hidden_state"],
                     {"input_ids": wi,
                      "attention_mask": np.ones_like(wi)})[0]
vec = hidden[0].mean(axis=0)
vec = vec / np.linalg.norm(vec)
print("int8 beacon:", ",".join(f"{v:.6f}" for v in vec[:4]))
print("warmup ids:", w.ids)
