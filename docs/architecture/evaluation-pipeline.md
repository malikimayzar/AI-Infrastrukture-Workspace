# Technical Architecture: Non-LLM Judge Evaluation Pipeline

> **Module:** `llm-eval-framework`  
> **Status:** Implemented diagnostic evaluator; not a correctness oracle or calibrated production gate

---

## 1. Overview & Core Philosophy

Traditional RAG evaluation often relies on "LLM-as-a-judge" approaches (asking another powerful LLM if an answer is faithful to the source). However, this introduces circular dependencies, high latency, API costs, and non-deterministic scoring.

`llm-eval-framework` implements a **non-LLM-judge diagnostic architecture** centered around:
1. **Claim Extraction & Enumeration Expansion**: Breaking down compound sentences and enumerated lists into atomic claims.
2. **Semantic & Lexical Evidence Matching**: Measuring factual grounding using embedding cosine similarity (`nomic-embed-text` via Ollama) combined with ROUGE-L overlap.
3. **Technical Conflict Detection**: Overriding high embedding scores when specific technical discrepancies occur (e.g., confusing `PUT` vs `PATCH` HTTP methods).
4. **False Insufficient Context Detection**: Detecting when an LLM refuses to answer ("INSUFFICIENT_CONTEXT") despite clear supporting evidence being present in the source text.

The evaluator uses semantic and lexical heuristics. Its score measures support
under this method; it does not prove factual correctness, guarantee zero
hallucinations, or establish calibrated confidence. Thresholds and model versions
must accompany any reported result.

---

## 2. Pipeline Stages

```
[Dataset Record] ──> [Prompt Template] ──> [Ollama Model Client] ──> [Generated Answer]
                                                                        │
                                                                        ▼
[Artifacts Storage] <── [Provenance & Logging] <── [Evaluator Engine] <──┘
```

### Stage 1: Dataset & Prompt Loading (`pipeline/`)
- Loads clean, distractor, or paraphrase test cases from JSON files under `data/dataset/`.
- Merges parameters and thresholds from `config.yaml` via singleton configuration loader (`pipeline/config_loader.py`).

### Stage 2: Model Execution (`pipeline/model_client.py`)
- Communicates with local Ollama instance (`mistral`, `phi3:mini`).
- Handles retries, dry-runs, checkpoints, and captures latency metrics.

### Stage 3: Evaluator Engine (`evaluators/`)
- **Faithfulness (`faithfulness.py`):** Extracts atomic claims from the answer, matches each claim against the context chunks using semantic similarity, applies technical conflict overrides, and computes the faithfulness score (`0.0` to `1.0`).
- **Consistency (`consistency.py`):** Compares answer stability across paraphrased variants of the same question.
- **Retrieval Dependency (`retrieval_dependency.py`):** Tests model robustness by removing or replacing context (`no_context`, `wrong_context`) to verify if the model relies on actual document retrieval or memorized training data.
- **Sensitivity (`sensitivity.py`):** Measures output variance under prompt perturbations.

### Stage 4: Reporting & Provenance (`reports/`, `pipeline/provenance.py`)
- Injects a strict provenance block (`git_commit`, `config_snapshot`, `dataset_sha256`) into all output results.
- Generates executive HTML reports and Matplotlib visualizations.
