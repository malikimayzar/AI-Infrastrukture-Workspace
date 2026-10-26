# Confidence Calibration

> **Last Updated:** 2026-10-25
> **Target:** ECE < 0.10 on 200+ labeled samples — ECE target met (0.0576 on
> 194 samples); the 200-sample dataset-size target is **not** met (194/200).

## Overview

The `ConfidenceEngine` uses heuristic thresholds (reject=0.35, partial=0.65) to
decide whether to GENERATE, PARTIAL_TRUST, or REJECT a query. These thresholds
were hardcoded and not calibrated to empirical accuracy.

The calibration system maps raw heuristic confidence scores to calibrated
probabilities using **isotonic regression** or **Platt scaling**, so the
decision zones reflect true empirical accuracy.

## Files

| File | Purpose |
|------|---------|
| `src/controller/calibration.py` | `CalibrationEngine` — isotonic + Platt scaling, ECE/Brier metrics, save/load |
| `src/controller/calibrated_confidence_engine.py` | `CalibratedConfidenceEngine` — wraps `ConfidenceEngine`, applies calibration |
| `src/api/config.py` | Settings: `calibrated_reject_threshold`, `calibrated_partial_threshold`, `calibration_method`, `calibration_model_path` |
| `data/evaluation/calibration_dataset.json` | Labeled calibration dataset (194 samples; 6 failed runs kept in `excluded_samples`) |
| `scripts/fit_calibration.py` | Fits both models, refuses ERROR rows, writes the report |
| `models/calibration_isotonic.joblib` | Default production calibration model (build output, not tracked in git) |
| `models/calibration_platt.joblib` | Alternative Platt scaling model (build output) |

The `joblib` artifacts are **not** committed. `rag-research/Dockerfile` runs
`scripts/fit_calibration.py` during the image build, so the model in a container
always matches the dataset revision that produced the image.

## Current Results

Metrics are measured on the 20% holdout split (`random_state=42`) by
`scripts/fit_calibration.py`, dataset revision 2026-10-25.

| Metric | Before calibration | After (isotonic) | After (Platt) | Target |
|--------|-------------------|------------------|---------------|--------|
| ECE (Expected Calibration Error) | 0.1889 | **0.0576** | 0.0789 | < 0.10 ✅ |
| Brier Score | 0.1743 | **0.1291** | 0.1498 | — |
| Labeled samples | 194 | 194 | 194 | 200+ ⚠️ |

Isotonic regression reaches ECE 0.0576 on 194 samples. That is below the 0.10
threshold, but 194 is still short of the documented 200-sample floor.

Six samples were removed from the fitting set because their pipeline run failed
(`raw_decision=ERROR`, `raw_confidence=0.0`, `api_answer=null`). A failed run is
not a low-confidence observation; keeping it would have taught the calibrator
that supported queries score zero. They are preserved under `excluded_samples`
with a reason. Re-running those six queries is the way to restore the count.

## Usage

### Load saved calibration model at startup

The calibration model is loaded automatically at startup from
`models/calibration_isotonic.joblib`. Configure via `.env`:

```
CALIBRATION_METHOD=isotonic
CALIBRATION_MODEL_PATH=models/calibration_isotonic.joblib
```

### Fit a new calibration model

```bash
cd rag-research
PYTHONPATH=. python scripts/fit_calibration.py \
    --dataset data/evaluation/calibration_dataset.json --out models
```

The script fits isotonic and Platt, prints ECE/Brier for each, and writes
`models/calibration_report.json`. It exits non-zero when the dataset contains an
`ERROR` row or when the declared counts disagree with the rows present, because
either condition means the data is not fit for calibration.

Programmatic equivalent:

```python
from src.controller.calibration import CalibrationEngine, CalibrationSample

# Collect labeled samples
samples = [
    CalibrationSample(raw_confidence=0.75, is_supported=True, query_id="q1", query="..."),
    CalibrationSample(raw_confidence=0.10, is_supported=False, query_id="q2", query="..."),
    # ... 200+ samples
]

engine = CalibrationEngine(method="isotonic")
result = engine.fit(samples)
print(f"ECE: {result.ece_before} -> {result.ece_after}")
print(f"Brier: {result.brier_before} -> {result.brier_after}")

engine.save("models/calibration_isotonic.joblib")
```

### Use calibrated engine in code

```python
from src.controller.calibrated_confidence_engine import CalibratedConfidenceEngine

cal_engine = CalibratedConfidenceEngine()
result = cal_engine.calculate_confidence(
    chunks=chunks,
    query="What is self-attention?",
    answer="Self-attention allows the model to attend to different positions.",
)

print(f"Raw confidence: {result['raw_confidence']:.4f}")
print(f"Calibrated confidence: {result['calibrated_confidence']:.4f}")
print(f"Decision: {result['decision']}")
print(f"Is calibrated: {result['is_calibrated']}")
```

## Decision Zones

| Calibrated Probability | Decision | Meaning |
|----------------------|----------|---------|
| < 0.35 | REJECT | Insufficient evidence — do not generate |
| 0.35 – 0.65 | PARTIAL_TRUST | Limited evidence — generate with caution, max 3 chunks |
| ≥ 0.65 | GENERATE | Sufficient evidence — full generation |

These thresholds mirror the original heuristic values but now apply to
calibrated probabilities instead of raw heuristic scores.

## Extending the Dataset

To improve calibration further, add more labeled samples to
`data/evaluation/calibration_dataset.json` and re-fit:

1. Run queries through the RAG API to collect `raw_confidence` scores
2. Label each sample as `is_supported=true/false` based on ground truth
3. Re-fit with `scripts/fit_calibration.py`
4. Rebuild the image, or re-save to `models/calibration_isotonic.joblib` locally

If a query fails during collection, do **not** record it as a sample with
`raw_confidence=0.0`. Either re-run it, or move it to `excluded_samples` with an
`exclusion_reason`; `fit_calibration.py` refuses to fit a dataset that still
contains `ERROR` rows.

## Sample Distribution

| Category | Count | % |
|----------|-------|---|
| Supported (answerable) | 113 | 58.2% |
| Unsupported (unanswerable) | 81 | 41.8% |
| **Fitted total** | **194** | **100%** |
| Excluded (failed run) | 6 | — |
