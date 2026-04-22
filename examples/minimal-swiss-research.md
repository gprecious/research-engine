---
marp: true
theme: default
paginate: true
---

<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;800&display=swap" rel="stylesheet">

<style>
:root {
  --bg: #FFFFFF;
  --surface: #F3F3F3;
  --text: #0D0D0D;
  --a1: #E63946;
  --a2: #0D4F8B;
  --heading-font: "Inter", sans-serif;
  --body-font: "Inter", sans-serif;
}
section {
  background: var(--bg);
  color: var(--text);
  font-family: var(--body-font);
  font-weight: 300;
  font-size: 24pt;
  padding: 64px 56px;
}
section h1, section h2, section h3 {
  font-family: var(--heading-font);
  font-weight: 800;
  color: var(--text);
  letter-spacing: -0.02em;
}
section.title h1 { font-size: 88pt; line-height: 0.95; }
section h1 { font-size: 44pt; line-height: 1.08; }
section h2 { font-size: 32pt; line-height: 1.12; }
section strong { color: var(--a1); font-weight: 800; }
section a { color: var(--a2); text-decoration: none; border-bottom: 2px solid var(--a2); }
section.lead { display: flex; flex-direction: column; justify-content: center; }
section.lead h1 { font-size: 80pt; line-height: 1.0; }
section.divider { background: var(--bg); color: var(--text); display: flex; flex-direction: column; justify-content: center; border-left: 24px solid var(--a1); }
section.divider h1 { font-size: 96pt; line-height: 0.95; }
section.divider p { font-size: 24pt; color: var(--a1); font-weight: 800; letter-spacing: 0.08em; text-transform: uppercase; margin-top: 16px; }
section.bento { display: grid; grid-template-columns: 1.2fr 1fr; gap: 48px; }
section.chart-hero { padding: 48px; }
section.chart-hero img { width: 100%; height: auto; }
section.sources { font-size: 14pt; padding: 64px 80px; }
section.sources h1 { font-size: 44pt; margin-bottom: 24px; }
section.sources ol { columns: 2; column-gap: 48px; padding-left: 24px; }
section.sources li { margin-bottom: 6px; break-inside: avoid; }
section::after { color: var(--text); opacity: 0.4; font-size: 12pt; }
</style>

<!-- _class: title -->

# 텍스트 PPT는 **세 레이어**를 얹어야 덱이 된다

*2026-04-20-ppt-design-improvement-research · 2026-04-20*

---

<!-- _class: lead -->

# **프리셋·평가·QA**를 분리하면 덱이 살아난다

---

<!-- _class: divider -->

# 진단

현재 파이프라인의 구조적 한계

---

<!-- _class: bento -->

## 현 스택은 **얇아서** 텍스트 과다가 구조적 결과다

단일 Marp 템플릿 + QuickChart GET만으로 돌아가면 모든 주제가 같은 레이아웃을 받는다.

- 스타일 라이브러리 없음 [23,25]
- 평가·리파인 루프 없음 [24,27]
- 제목 규약 없음 [27]
- 모델 탓 아님 — 입력 부재 [6]
- POST·backgroundImageUrl 미활용 [17,18]

---

<!-- _class: bento -->

## 커뮤니티 진단은 **모델이 아닌 스토리**를 가리킨다

"The hard part of building a presentation is figuring out the story" — 병목은 프롬프트가 아니라 사고와 편집이다.

- AI는 원본 사고 부재 [5]
- 요구 진화하면 초안 붕괴 [8]
- 200줄 skill로 디자인 시스템 강제 [7]
- 스토리 인터뷰 먼저, 초안은 나중 [6]

---

<!-- _class: divider -->

# 처방

세 갈래 돌파 경로

---

<!-- _class: bento -->

## Anthropic **4축 rubric**을 그대로 이식한다

Design Quality·Originality에 가중치를 싣고, Craft·Functionality는 베이스라인으로 둔다.

- Design Quality 0.35 [1]
- Originality 0.35 [1]
- Craft 0.15, Functionality 0.15 [1]
- 생성자와 평가자 분리 필수 [1]
- <75점이면 자동 리파인 [27]

---

<!-- _class: bento -->

## **5개 참고 스킬**이 우리가 훔칠 레시피를 정의한다

각 레포는 하나씩 다른 축을 해결한다 — 예제·QA·디스커버리·백엔드·평가.

- robonuggets: 22 예제 + "먼저 읽어라" [23]
- ryanbbrown: Playwright + DeckTape QA [24]
- zarazhangrui: 3-preview 디스커버리 [25]
- zl190: 4-백엔드 dispatcher [26]
- daymade: RUBRIC self-refine <75 [27]

---

<!-- _class: bento -->

## **Playwright + DeckTape**로 시각 결함을 닫는다

렌더 후 슬라이드별 스크린샷으로 오버플로우를 자동 검출하고, 실패 슬라이드만 재생성한다.

- 슬라이드별 스크린샷 diff [24]
- Chart.js `?export`로 애니메이션 off [24]
- 고정 pt 단위로 캔버스 통일 [24]
- P1 우선순위 패치로 배치

---

<!-- _class: divider -->

# 제약

하드 코드할 2026 기준선

---

## 2026 트렌드는 **하드 제약**으로 encode해야 한다

- 벤토 그리드 + 비대칭 깊이 [3,4]
- 80pt+ 오버사이즈 헤드라인 [3]
- 다크+네온 또는 Warm+Teal 양극 [3,4]
- 9:16 세로 포맷 성장률 최상위 [3]
- 5-color scale 권고 (bg·surface·text·a1·a2) [4]

---

## 접근성은 **숫자 린터**로 강제한다

- 본문 ≥ **24pt** [4]
- 타이틀 44–64pt [4]
- 본문 대비 **4.5:1**, 헤드라인 3:1 [4]
- 렌더 전 자동 교정 훅 [4]
- 폰트 패밀리 ≤2, variable weight [4]

---

## Assertion-Evidence 제목은 **명사구를 금지**한다

- "Sales Overview" → "Q3 매출 23% 성장" [27]
- 본문은 차트·표·인용으로만 지지 [27]
- 증거 없는 주장은 재작성 [27]
- `visualizer-extractor` 출력 후처리 [27]

---

## Claude Design은 **최종 도구가 아닌 초안 생성기**다

- 자연어 비전 → 초안 → 리파인 [2]
- codebase·Figma 디자인 시스템 추출 [2]
- 출력: PDF·URL·**PPTX**·Canva [2]
- "complement Canva, not replace" [2,8]
- visualize stage의 역할 정의와 동일 [2]

---

<!-- _class: divider -->

# 라이브러리

편집 가능 차트와 스타일 훅

---

## Marp 단일 백엔드로는 **편집 가능 차트**가 안 나온다

- python-pptx `CategoryChartData` [14]
- `XL_CHART_TYPE.COLUMN_CLUSTERED` [14]
- `legend.position = BOTTOM` 표준 [14]
- PowerPoint 안에서 데이터 수정 [14]
- Marp + pptx dual-path 근거 [27]

---

## QuickChart는 **POST + backgroundImageUrl**이 미활용이다

- GET URL은 config 길이 제약 [16]
- POST로 큰 config 우회 [17]
- `backgroundImageUrl`로 브랜드 배경 [18]
- 덱 전체 워터마크 일관성 [18]
- Chart.js v4 고정 권장 [16]

---

## HF 자산이 **닫힌 품질 루프**의 재료가 된다

- ChartMimic few-shot → 차트 다양성 [29]
- docling-layout-heron → 레이아웃 스코어 [30]
- google/deplot → 외부 차트 역공학 [31]
- ChartGalaxy 상업 이용 주의 cc-by-nc [28]
- rubric의 Craft 축 자동화 [30]

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

# 실행

P0 → P3 2주 로드맵

---

## P0·P1·P2를 **2주 안**에 연쇄 배치한다

- P0 — 제목 규약 + Design Rules 8개 + examples/ [23,27]
- P1 — visualizer-judge + Playwright QA [1,24]
- P1 — presets.py 4종 프리셋 분리 [23,4]
- P2 — 3-preview + backend dispatcher [25,26]
- P2 — QuickChart POST + 워터마크 [17,18]
- P3 — ChartMimic·docling 자동 스코어 [29,30]

---

<!-- _class: sources -->

# Sources

1. Anthropic harness-design — anthropic.com/engineering/harness-design-long-running-apps
2. Claude Design launch — techcrunch.com/2026/04/17/anthropic-launches-claude-design
3. SlideEgg 2026 트렌드 — slideegg.com/blog/presentation-tips
4. Slidesgo 2026 트렌드 — slidesgo.com/slidesgo-school/ai-presentations/presentation-design-trends-2026
5. HN Claude Design — news.ycombinator.com/item?id=47806725
6. freeCodeCamp Marp — freecodecamp.org/news/how-to-use-claude-code-and-marp
7. HN UI-stack design system — news.ycombinator.com/item?id=47435063
8. Banani Claude Design review — banani.co/blog/claude-design-review
9. Marpit Directives — github.com/marp-team/marpit/docs/directives.md
10. Marpit Theme CSS — github.com/marp-team/marpit/docs/theme-css.md
11. Marp Core README — github.com/marp-team/marp-core
12. reveal.js plugins — context7.com/hakimel/reveal.js/llms.txt
13. reveal.js backgrounds — github.com/reveal/revealjs.com/backgrounds.md
14. python-pptx charts — github.com/scanny/python-pptx/docs/user/charts.md
15. python-pptx placeholders — python-pptx.readthedocs.io/placeholders-using.html
16. QuickChart GET parameters — quickchart.io/documentation/usage/parameters
17. QuickChart POST endpoint — quickchart.io/documentation/usage/post-endpoint
18. QuickChart backgroundImageUrl — quickchart.io/documentation/add-watermark
19. D3 Getting Started — d3js.org/getting-started
20. d3-axis module — d3js.org/d3-axis
21. Observable Plot llms.txt — context7.com/observablehq/plot/llms.txt
22. Observable Plot auto + facets — github.com/observablehq/plot/docs/marks/auto.md
23. robonuggets/marp-slides — github.com/robonuggets/marp-slides
24. ryanbbrown/revealjs-skill — github.com/ryanbbrown/revealjs-skill
25. zarazhangrui/frontend-slides — github.com/zarazhangrui/frontend-slides
26. zl190/md-slides — github.com/zl190/md-slides
27. daymade/claude-code-skills — github.com/daymade/claude-code-skills
28. ChartGalaxy — huggingface.co/datasets/ChartGalaxy/ChartGalaxy
29. ChartMimic — huggingface.co/datasets/ChartMimic/ChartMimic
30. docling-layout-heron — huggingface.co/docling-project/docling-layout-heron
31. google/deplot — huggingface.co/google/deplot
