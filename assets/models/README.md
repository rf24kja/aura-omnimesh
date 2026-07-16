# Model assets — provenance and regeneration

| File | What it is |
|---|---|
| `minilm_multilingual_quantized.onnx` | paraphrase-multilingual-MiniLM-L12-v2, **vocabulary-trimmed** to Latin/Cyrillic/punctuation pieces (141,731 of 250,002), embedding matrix sliced accordingly, exported to ONNX opset 17 and dynamically quantized to int8. ~76 MB. |
| `xlmr_unigram_vocab.tsv` | The matching trimmed Unigram vocabulary, one `piece\tscore` per line; **line index == token id**. Consumed by `lib/inference/sentencepiece_tokenizer.dart`. |
| `vocab.txt` | bert-base-uncased WordPiece vocabulary (all-MiniLM-L6-v2 heritage). Kept for the WordPiece tokenizer + its tests; not used by the shipped embedding path. |

Provenance: original weights from `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` (HuggingFace), trimmed and exported locally by `tool/trim_model.py` — no third-party model mirrors involved.

Trimming safety argument: for text made ONLY of kept-script characters,
pieces containing other scripts can never appear in a Unigram
segmentation, so tokenization — and therefore the embedding — is
**identical** to the full model (verified: cos(full, trimmed) = 1.0000
across the whole calibration corpus). Other scripts degrade to `<unk>`
on every device equally.

Regenerate (needs python + torch + transformers + tokenizers + onnxruntime):

```bash
python tool/trim_model.py        # artifacts + quality gates + goldens data
python tool/gate_int8.py         # int8 calibration gate
```

Then copy the artifacts over the two asset files above and regenerate
`test/sentencepiece_goldens.json` (trim_model.py prints how). The
calibrated `similarityThreshold` lives in `lib/matching/ring_matcher.dart`
— revisit it whenever the model changes (tool/calibrate_threshold.mjs).
