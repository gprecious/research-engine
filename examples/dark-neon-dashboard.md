---
marp: true
theme: default
paginate: true
---

<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@700&family=IBM+Plex+Mono:wght@300&display=swap" rel="stylesheet">

<style>
:root {
  --bg: #0A0A0F;
  --surface: #14141C;
  --text: #E6E8EF;
  --a1: #B6FF3C;
  --a2: #3DA9FF;
  --heading-font: "Space Grotesk", sans-serif;
  --body-font: "IBM Plex Mono", sans-serif;
}
section {
  background: var(--bg);
  color: var(--text);
  font-family: var(--body-font);
  font-size: 24pt;
  padding: 120px 80px;
}
section h1, section h2, section h3 {
  font-family: var(--heading-font);
  color: var(--text);
  letter-spacing: -0.01em;
}
section.title h1 { font-size: 88pt; line-height: 0.95; }
section h1 { font-size: 44pt; }
section h2 { font-size: 32pt; }
section strong { color: var(--a1); }
section a { color: var(--a2); text-decoration: none; border-bottom: 2px solid var(--a2); }
section.lead { display: flex; flex-direction: column; justify-content: center; }
section.lead h1 { font-size: 80pt; }
section.divider { background: var(--a1); color: var(--bg); }
section.divider h1 { font-size: 96pt; }
section.bento { display: grid; grid-template-columns: 1.2fr 1fr; gap: 48px; }
section.chart-hero { padding: 48px; }
section.chart-hero img { width: 100%; height: auto; }
section::after { color: var(--text); opacity: 0.4; font-size: 12pt; }
</style>

<!-- _class: title -->

# 텍스트만 찬 PPT는 **세 갈래 루프**로 뚫는다

*2026-04-20-ppt-design-improvement-research · 2026-04-20*

---

<!-- _class: lead -->

# **평가·프리셋·QA**를 분리하면 덱이 살아난다

---

<!-- _class: divider -->

# 핵심 3가지

---

<!-- _class: bento -->

## Anthropic 4축 rubric을 **그대로 이식**할 수 있다

생성자와 평가자를 분리하고 <75점이면 자동 리파인.

- Design Quality 0.35 [1]
- Originality 0.35 [1]
- Craft / Functionality 0.15+0.15 [1]
- Self-eval 금지 — 자화자찬 편향 [1]
- daymade도 같은 게이트 [27]

---

<!-- _class: bento -->

## 현 스택은 **얇아서** 텍스트 과다가 구조적 결과다

단일 Marp 템플릿 + QuickChart GET만으로 돌아간다.

- 스타일 라이브러리 없음 [23,25]
- 평가/리파인 루프 없음 [24,27]
- 제목 규약 없음 [27]
- 모델 탓 아님 — 입력 부재 [6]

---

<!-- _class: bento -->

## **Playwright + DeckTape**로 시각 결함을 닫는다

ryanbbrown은 렌더 후 오버플로우를 자동 검출한다.

- 슬라이드별 스크린샷 [24]
- Chart.js `?export`로 애니메이션 off [24]
- 실패 슬라이드만 재생성 [24]
- P1 우선순위 패치

---

<!-- _class: divider -->

# 상세 분석

---

## Anthropic은 **Design Quality·Originality에 가중치**를 싣는다

- Craft는 Claude가 이미 잘 함 — 베이스라인 [1]
- "template layouts, library defaults"가 원죄 [1]
- rubric 어휘가 생성자 행동을 끌고 감 [1]
- "museum quality" 같은 말은 시각 수렴 유발 [1]

---

## Claude Design은 **최종 도구가 아닌 초안 생성기**다

- 자연어 비전 → 초안 → 리파인 [2]
- codebase·Figma 디자인 시스템 자동 추출 [2]
- 출력: PDF, URL, **PPTX**, Canva [2]
- "complement Canva, not replace" [2]

---

## 2026 트렌드는 **하드 제약**으로 encode해야 한다

- 벤토 그리드 + 비대칭 깊이 [3,4]
- 80pt+ 오버사이즈 헤드라인 [3]
- 다크 + 라임/일렉트릭 블루 네온 [3]
- Warm neutrals + Transformative Teal [4]

---

## 접근성은 **숫자 린터**로 강제한다

- 본문 ≥ **24pt** [4]
- 타이틀 44–64pt [4]
- 본문 대비 **4.5:1**, 헤드라인 3:1 [4]
- 렌더 전 자동 교정 훅 [4]

---

## 훔쳐올 스킬은 **5개**로 좁혀진다

- robonuggets — 22 예제 + "먼저 읽어라" [23]
- ryanbbrown — Playwright + DeckTape QA [24]
- zarazhangrui — 3-preview 디스커버리 [25]
- zl190 — 4-백엔드 dispatcher [26]
- daymade — RUBRIC self-refine <75 [27]

---

## Marp 단일 백엔드로는 **편집 가능 차트**가 안 나온다

- python-pptx `CategoryChartData` + `XL_CHART_TYPE` [14]
- `chart.legend.position = BOTTOM` 표준 [14]
- PowerPoint 안에서 데이터 수정 [14]
- dual-path (Marp + pptx) 근거 [27]

---

## QuickChart는 **POST + backgroundImageUrl**이 미활용이다

- GET URL은 config 길이 제약 [16]
- POST로 큰 config 우회 [17]
- `backgroundImageUrl`로 워터마크/브랜드 배경 [18]
- 덱 전체 브랜드 일관성 확보 [18]

---

## HF 데이터셋·모델이 **닫힌 품질 루프**의 재료가 된다

- ChartMimic few-shot → 차트 다양성 [29]
- docling-layout-heron → 레이아웃 스코어 [30]
- google/deplot → 외부 차트 역공학 [31]
- ChartGalaxy 상업 이용 주의(cc-by-nc) [28]

---

## 커뮤니티 진단은 **모델이 아니라 스토리**를 가리킨다

- "AI is wholly incapable of original thought" [5]
- 병목 = 명확한 사고 + 무자비한 편집 [6]
- 200줄 skill로 디자인 시스템 강제 [7]
- 요구 진화하면 AI 초안이 무너짐 [8]

---

<!-- _class: chart-hero -->

## Design Quality·Originality가 **가중치 70%**를 차지한다 [1]

![bg fit](figures/chart-01-anthropic-rubric-weights.png)

<!-- _footer: Anthropic harness-design 4축 rubric 가중치 -->

---

<!-- _class: chart-hero -->

## WCAG AA는 **타협 불가능한 하드 제약**이다 [4]

![bg fit](figures/chart-02-wcag-aa-contrast.png)

<!-- _footer: 2026 WCAG AA 접근성 — 최소 대비 하드 제약 -->

---

<!-- _class: chart-hero -->

## 본문 24pt·타이틀 80pt+가 **2026 기본선**이다 [3,4]

![bg fit](figures/chart-03-typography-sizes-pt.png)

<!-- _footer: 2026 타이포그래피 권고 크기 (pt) -->

---

<!-- _class: chart-hero -->

## robonuggets의 **22 예제**가 참고 표준을 정한다 [23,25]

![bg fit](figures/chart-04-style-reference-assets.png)

<!-- _footer: 스타일 레퍼런스 에셋 수 — 참고 스킬 비교 -->

---

<!-- _class: divider -->

# 실행 순서

---

## P0·P1·P2를 **2주 안**에 연쇄 배치한다

- P0 — 제목 규칙 + Design Rules 8개 + examples/ [23,27]
- P1 — visualizer-judge + Playwright QA + presets.py [1,24]
- P2 — 3-preview + backend dispatcher + POST [25,26,17]
- P3 — ChartMimic + docling 자동 스코어 [29,30]

---

<!-- _class: lead -->

# Sources

1. Anthropic harness-design — anthropic.com/engineering/harness-design-long-running-apps
2. Claude Design launch — techcrunch.com/2026/04/17/anthropic-launches-claude-design
3. SlideEgg 2026 트렌드 — slideegg.com/blog/presentation-tips
4. Slidesgo 2026 트렌드 — slidesgo.com/slidesgo-school/ai-presentations/presentation-design-trends-2026
5. HN Claude Design — news.ycombinator.com/item?id=47806725
6. freeCodeCamp Marp — freecodecamp.org/news/how-to-use-claude-code-and-marp
23. robonuggets/marp-slides — github.com/robonuggets/marp-slides
24. ryanbbrown/revealjs-skill — github.com/ryanbbrown/revealjs-skill
25. zarazhangrui/frontend-slides — github.com/zarazhangrui/frontend-slides
26. zl190/md-slides — github.com/zl190/md-slides
27. daymade/claude-code-skills — github.com/daymade/claude-code-skills
29. ChartMimic — huggingface.co/datasets/ChartMimic/ChartMimic
30. docling-layout-heron — huggingface.co/docling-project/docling-layout-heron
