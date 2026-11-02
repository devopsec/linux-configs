# RAG evals and quality monitoring

Derived from upstream `devops/ai/rag-observability-evals` (MIT). Rewritten for ragas 0.4.x field names/API (upstream used the pre-0.2 `question/answer/contexts/ground_truth` schema), Prometheus examples kept as rules, GCP options added.

## What to measure

| Area | Metrics |
|---|---|
| Retrieval | recall@k, MRR, context precision (ranking), context recall (coverage), index staleness, embedding model version |
| Generation | faithfulness/groundedness, answer relevancy, hallucination rate per route, citation coverage, format validity |
| Reliability/cost | p50/p95 latency split retrieval vs generation, tokens per stage, cache hit rate, cost per *successful* answer, fallback/abstain rate |

## Dataset

JSONL rows: `user_input`, `reference` (human-written answer), `reference_doc_ids` (for recall@k/MRR), then filled at run time by your pipeline: `retrieved_contexts` (list of strings — not one string), `retrieved_ids`, `response`. Keep a curated set (50–200) plus a held-out set; refresh when the corpus changes.

## Retrieval metrics (no LLM needed)

```python
def recall_at_k(retrieved: list[str], relevant: set[str], k: int) -> float:
    return len(set(retrieved[:k]) & relevant) / len(relevant) if relevant else 0.0

def reciprocal_rank(retrieved: list[str], relevant: set[str]) -> float:
    return next((1.0 / (i + 1) for i, d in enumerate(retrieved) if d in relevant), 0.0)
# MRR = mean(reciprocal_rank) over queries
```

## RAGAS (0.4.3, checked 2026-10-28)

- Field names: `user_input`, `response`, `retrieved_contexts`, `reference`.
- Recommended API: metric classes from `ragas.metrics.collections` (`Faithfulness`, `AnswerRelevancy`, `ContextPrecision`, `ContextRecall`, `ContextUtilization`), scored with `await metric.ascore(...)` / `.score(...)` returning `.value`. Older `ragas.metrics` classes + `SingleTurnSample` / `evaluate(EvaluationDataset)` still work but are deprecated from 0.4 (removal planned for 1.0).
- Pin `ragas==0.4.3` in `pyproject.toml` (`uv add ragas==0.4.3`), checked against the official release list on 2026-10-28. Pin the evaluator LLM and embeddings too; scores are comparable only with the same judge.

| Metric | Needs reference | Diagnoses |
|---|---|---|
| Faithfulness | no | claims unsupported by context (hallucination) |
| AnswerRelevancy | no | answer drifts from question |
| ContextPrecision | yes | relevant chunks not ranked first (re-ranker problem) |
| ContextRecall | yes | retriever missed needed info (chunking/embedding problem) |
| ContextUtilization | no | ranking judged against the answer |

Reading combinations: low recall + high faithfulness → retrieval problem; high recall + low faithfulness → generation/prompt problem; both low → check index freshness and embedding version first.

## Groundedness scoring without RAGAS

Split the response into claims, ask a judge per claim "supported by context? yes/no" (temperature 0), score = supported/total; flag responses < 0.75. Same judge rules as `agent-evals.md` §6.

## Production monitoring

Emit per request: route, retrieval latency, generation latency, tokens per stage, retrieved ids, groundedness (sampled), fallback flag, index version. On GCP: structured JSON logs → Cloud Logging → log sink to BigQuery for offline eval; log-based metrics / Cloud Monitoring alerts. Prometheus equivalents if you run it:

```yaml
groups:
  - name: rag-quality
    rules:
      - alert: GroundednessDropped
        expr: avg_over_time(rag_groundedness_score[10m]) < 0.75
        for: 10m
      - alert: HallucinationSpike
        expr: rate(rag_hallucination_detected_total[15m]) / rate(rag_requests_total[15m]) > 0.10
        for: 5m
      - alert: IndexStale
        expr: rag_index_staleness_seconds > 86400
      - alert: HighFallbackRate
        expr: rate(rag_fallback_triggered_total[10m]) / rate(rag_requests_total[10m]) > 0.20
        for: 10m
      - alert: RetrievalLatencyHigh
        expr: histogram_quantile(0.95, rate(rag_retrieval_duration_seconds_bucket[5m])) > 2
        for: 5m
```

Keep metric labels low-cardinality (route, index — never user id or query text).

## Guardrails worth eval coverage

Forced citations for high-risk domains; abstain/fallback below a confidence threshold; re-ranking before generation; query rewriting only behind regression tests.

## Triage

| Symptom | Check first | Then |
|---|---|---|
| Groundedness dropped | embedding model changed? | chunking/indexing change |
| Irrelevant docs retrieved | index freshness, doc count | embedding version mismatch between index and query |
| Retrieval latency spike | vector DB pool/load | index size growth |
| Cost per answer up | tokens per stage | cache hit rate |
| Hallucination spike | model version / temperature change | context overflow (truncated docs) |
| RAGAS scores all 0 | dataset schema (`retrieved_contexts` must be a list) | evaluator LLM credentials |
