# Model Calibration & Threshold Tuning Guide

> **Scope:** `llm-eval-framework` evaluator thresholds in `config.yaml`
> **Audience:** ML Engineers, AI Researchers
> **Status:** Thresholds are heuristic defaults, not calibrated production cutoffs. The config file is the source of truth for current values.

---

## 1. Purpose of Calibration

When changing the embedding model, evaluator implementation, or document domain, existing thresholds may produce false positives or false negatives. A threshold is not calibrated merely because it is configurable or because a test passes.

All calibration parameters are centralized in `llm-eval-framework/config.yaml`.

---

## 2. Key Thresholds in `config.yaml`

| Parameter Key | Default Value | Description | Tuning Guidance |
|---|---|---|---|
| `thresholds.faithfulness_evidence` | `0.68` | Similarity cutoff for claim-to-evidence support. | Current heuristic value; validate on reviewed positive and negative claim/evidence pairs before changing. |
| `thresholds.insufficient_ctx_validation` | `0.65` | Validation cutoff used for insufficient-context behavior. | Inspect implementation and labeled cases before tuning. |
| `thresholds.consistency_semantic` | `0.72` | Semantic similarity cutoff for paraphrase consistency. | Evaluate against reviewed paraphrase pairs; do not tune on the small built-in set alone. |
| `thresholds.consistency_rouge_l` | `0.40` | ROUGE-L floor for consistency checks. | Interpret alongside semantic score and answer length. |
| `thresholds.robustness_sensitivity` | `0.85` | Sensitivity threshold for prompt perturbation analysis. | Confirm direction and meaning in the evaluator before tuning. |
| `thresholds.retrieval_dependency_change` | `0.70` | Threshold for change when context is removed or replaced. | Confirm decision semantics with labeled control cases. |
| `thresholds.short_answer_max_words` / `short_answer_char_sim` | `5` / `0.85` | Selects and compares short-answer handling. | Keep exact-match behavior conservative; review false accepts and false rejects. |

---

## 3. Calibration Workflow

1. **Freeze the evaluation inputs:** record evaluator version, embedding model, config snapshot, dataset version/hash, and context construction.
2. **Run a baseline on a reviewed dataset:**
   ```bash
   make eval-clean
   make eval-distractor
   ```
3. **Inspect failure analysis:**
   - Review `reports/analysis.md` and generated JSON results in `reports/results/`.
   - Identify cases where correct answers were incorrectly flagged as unfaithful due to strict embedding thresholds.
4. **Adjust one threshold at a time:** record the expected tradeoff and compare false-support and false-rejection rates on held-out examples. Avoid tuning and reporting on the same small sample.
5. **Re-verify reproducibility:**
   - Run `make verify` to ensure provenance and threshold snapshot alignment.
   - Run `make test` to verify unit test suite stability.

6. **Report limitations:** current RAG confidence is explicitly heuristic and the available retrieval sets are too small for reliable calibration. Do not describe these thresholds as statistically calibrated until a sufficiently broad labeled set and held-out calibration report exist.
