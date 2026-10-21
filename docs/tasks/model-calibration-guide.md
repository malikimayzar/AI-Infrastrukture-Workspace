# Model Calibration & Threshold Tuning Guide

> **Scope:** `llm-eval-framework` Configuration (`config.yaml`)  
> **Audience:** ML Engineers, AI Researchers  

---

## 1. Purpose of Calibration

When migrating to a new LLM backbone (e.g., transitioning from `mistral` to `phi3:mini`) or adapting the RAG system to a new document domain (e.g., financial legal text vs. technical API documentation), default evaluation thresholds may result in false positives or false negatives.

All calibration parameters are centralized in `llm-eval-framework/config.yaml`.

---

## 2. Key Thresholds in `config.yaml`

| Parameter Key | Default Value | Description | Tuning Guidance |
|---|---|---|---|
| `thresholds.faithfulness_evidence` | `0.65` | Minimum cosine similarity required to match an extracted claim to a source evidence span. | **Lower** if domain uses paraphrased terminology; **Raise** if strict verbatim matching is required. |
| `thresholds.retrieval_dependency_change` | `0.85` | Semantic similarity threshold below which an answer is considered changed when context is removed. | **Raise** to be more sensitive to context changes; **Lower** to tolerate minor stylistic variations. |
| `thresholds.consistency_semantic` | `0.80` | Minimum similarity between answers across paraphrased questions. | Adjust based on query variance tolerance. |

---

## 3. Calibration Workflow

1. **Run Baseline Evaluation:**
   ```bash
   make eval-clean
   make eval-distractor
   ```
2. **Inspect Failure Analysis:**
   - Review `reports/analysis.md` and generated JSON results in `reports/results/`.
   - Identify cases where correct answers were incorrectly flagged as unfaithful due to strict embedding thresholds.
3. **Adjust `config.yaml`:**
   - Modify the target threshold incrementally (e.g., from `0.65` to `0.62`).
4. **Re-verify Reproducibility:**
   - Run `make verify` to ensure provenance and threshold snapshot alignment.
   - Run `make test` to verify unit test suite stability.
