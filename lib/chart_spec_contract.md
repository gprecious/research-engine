# Chart Spec Contract

Produced by `agents/visualizer-extractor.md`. Consumed by `scripts/render_chart.sh`.

## Schema

```json
{
  "charts": [
    {
      "id": "c1",
      "title": "차트 제목 (리포트 언어)",
      "kind": "bar | line | pie | scatter | horizontal_bar | table",
      "rationale": "이 차트를 만든 이유 (한 문장)",
      "data": {
        "labels": ["항목A", "항목B", "..."],
        "datasets": [
          { "label": "시리즈 이름", "values": [1.0, 2.0, 3.0] }
        ]
      },
      "evidence": [
        { "source_id": 3, "quote_verbatim": "원문 인용 — 숫자 포함" }
      ],
      "axis": { "x": "x축 레이블", "y": "y축 레이블" }
    }
  ],
  "rejected": [
    { "reason": "왜 차트화하지 못했는지", "excerpt": "원문 일부" }
  ]
}
```

## Hard constraints (extractor MUST enforce)

1. Every number in any `datasets[].values[]` MUST appear as a substring of at least one `quote_verbatim` in the same chart's `evidence[]`. If not, reject that chart into `rejected[]`.
2. Every `evidence[].source_id` MUST be a positive integer present in the consuming session's `sources.json`.
3. Reject vague numerics ("약", "대략", "roughly", "~"). Quote the surrounding context verbatim — no paraphrase.
4. `charts[]` length ≤ 5. Empty is valid.
5. Per chart, total data points (Σ labels × datasets) ≤ 12.
6. `kind` MUST be one of the six listed. Any other value → reject chart.
7. For `kind: "scatter"`, `datasets[].values[]` is an array of `{x: number, y: number}` objects; otherwise plain numbers.

## Rendering (`scripts/render_chart.sh`)

Maps the spec to a Chart.js v4 config and calls QuickChart.io:

- `bar`            → `{ type: "bar", data, options: { scales: {...} } }`
- `horizontal_bar` → `{ type: "bar", ..., options: { indexAxis: "y" } }`
- `line`           → `{ type: "line", ..., options: { elements: { line: { tension: 0.2 } } } }`
- `pie`            → `{ type: "pie", data }`
- `scatter`        → `{ type: "scatter", data }`
- `table`          → QuickChart `chart: "table"` via the `/chart?c=...` table variant

URL form: `https://quickchart.io/chart?c=<url-encoded>&width=800&height=400&backgroundColor=white&version=4`

## Meta sidecar

For each rendered chart, write `figures/chart-NN-<slug>.meta.json` with `{id, title, spec, rendered_at, quickchart_url, source_ids}` so the chart is fully reconstructible without re-running the extractor.
