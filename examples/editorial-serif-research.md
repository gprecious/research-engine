---
marp: true
theme: default
paginate: true
---

<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display:wght@400&family=DM+Sans:wght@300;400&display=swap" rel="stylesheet">

<style>
:root {
  --bg: #FAF7F2;
  --surface: #FFFFFF;
  --text: #1B1B1E;
  --a1: #B54E3A;
  --a2: #2E5E4E;
  --heading-font: "DM Serif Display", serif;
  --body-font: "DM Sans", sans-serif;
}
section {
  background: var(--bg);
  color: var(--text);
  font-family: var(--body-font);
  font-weight: 300;
  font-size: 24pt;
  line-height: 1.45;
  padding: 96px 72px;
}
section h1, section h2, section h3 {
  font-family: var(--heading-font);
  font-weight: 400;
  color: var(--text);
  letter-spacing: -0.01em;
  line-height: 1.08;
}
section.title h1 { font-size: 88pt; line-height: 0.98; }
section h1 { font-size: 44pt; margin-bottom: 28px; }
section h2 { font-size: 32pt; margin-bottom: 20px; }
section strong { color: var(--a1); font-weight: 400; }
section em { color: var(--a2); font-style: italic; }
section a { color: var(--a2); text-decoration: none; border-bottom: 1px solid var(--a2); }
section h1::after { content: ""; display: block; width: 96px; height: 3px; background: var(--a1); margin-top: 20px; }
section.title h1::after, section.lead h1::after, section.divider h1::after { display: none; }
section.title { padding: 120px 96px; }
section.title p { font-family: var(--body-font); font-style: italic; font-weight: 300; font-size: 26pt; color: var(--a2); margin-top: 48px; }
section.lead { display: flex; flex-direction: column; justify-content: center; padding: 120px 96px; }
section.lead h1 { font-size: 80pt; }
section.divider { background: var(--bg); display: flex; flex-direction: column; justify-content: center; padding: 120px 96px; border-left: 12px solid var(--a1); }
section.divider h1 { font-size: 96pt; color: var(--a1); }
section.divider p { font-family: var(--body-font); font-size: 22pt; font-weight: 300; color: var(--text); opacity: 0.7; letter-spacing: 0.14em; text-transform: uppercase; margin-top: 24px; }
section.divider h1::after { display: none; }
section.bento { display: grid; grid-template-columns: 1.2fr 1fr; gap: 56px; align-items: start; }
section.bento h2 { grid-column: 1 / -1; }
section.chart-hero { padding: 56px 64px; }
section.chart-hero img { width: 100%; height: auto; }
section.chart-hero h2 { font-size: 30pt; margin-bottom: 16px; }
section.sources { font-size: 14pt; padding: 64px 80px; line-height: 1.3; }
section.sources h1 { font-size: 44pt; margin-bottom: 24px; }
section.sources ol { columns: 2; column-gap: 48px; padding-left: 24px; }
section.sources li { margin-bottom: 6px; break-inside: avoid; }
section ul { padding-left: 1.1em; }
section li { margin-bottom: 10px; }
section::after { color: var(--text); opacity: 0.4; font-size: 12pt; font-family: var(--body-font); }
</style>

<!-- _class: title -->

# 텍스트만 담긴 PPT는 **세 레이어**를 더해야 덱이 된다

*2026-04-20-ppt-design-improvement-research · 2026-04-20*

---

<!-- _class: lead -->

# **프리셋·루브릭·QA**를 분리하면 덱이 살아난다

---

<!-- _class: divider -->

# 진단

현재 파이프라인의 구조적 한계

---

<!-- _class: bento -->

## 현 스택은 **얇아서** 텍스트 과다가 구조적 결과다

단일 Marp 템플릿과 QuickChart GET만으로 돌아가면 모든 주제가 같은 얼굴을 받는다.

- 스타일 라이브러리 없음 [23,25]
- 평가·리파인 루프 없음 [24,27]
- Assertion-Evidence 제목 규약 없음 [27]
- 모델 성능이 아니라 *입력 부재* [6]

---

<!-- _class: bento -->

## 커뮤니티 진단은 **모델이 아닌 스토리**를 가리킨다

"The hard part of building a presentation is figuring out the story" — 병목은 프롬프트가 아니라 사고와 편집이다.

- AI는 원본 사고가 부재하다 [5]
- 요구가 진화하면 초안이 무너진다 [8]
- 200줄 스킬로 디자인 시스템을 강제한다 [7]
- 스토리 인터뷰가 먼저, 초안은 나중이다 [6]

---

<!-- _class: divider -->

# 처방

세 갈래 돌파 경로

---

<!-- _class: bento -->

## Anthropic **4축 루브릭**은 그대로 이식 가능하다

Design Quality·Originality에 가중치를 싣고, Craft·Functionality는 베이스라인으로 둔다.

- Design Quality 0.35 [1]
- Originality 0.35 [1]
- Craft·Functionality 각 0.15 [1]
- 생성자와 평가자는 반드시 분리한다 [1]

---

<!-- _class: bento -->

## **다섯 개의 참고 스킬**이 훔칠 레시피를 나눠 갖는다

각 레포가 축 하나씩을 해결한다 — 예제·QA·디스커버리·백엔드·평가.

- robonuggets — 22개 예제 + "먼저 읽어라" [23]
- ryanbbrown — Playwright + DeckTape QA [24]
- zarazhangrui — 3-preview 디스커버리 [25]
- zl190 — 4-백엔드 dispatcher [26]

---

<!-- _class: bento -->

## **Playwright + DeckTape**로 시각 결함을 닫는 루프가 선다

렌더 후 슬라이드별 스크린샷으로 오버플로우를 자동 검출하고, 실패 슬라이드만 다시 생성한다.

- 슬라이드별 스크린샷 diff [24]
- Chart.js `?export`로 애니메이션 off [24]
- 고정 pt 단위로 캔버스 통일 [24]
- P1 우선순위로 배치한다

---

<!-- _class: divider -->

# 제약

2026 기준선을 하드코딩한다

---

## 2026 트렌드는 **하드 제약**으로 encode해야 한다

- 벤토 그리드와 비대칭 깊이 [3,4]
- 80pt 이상 헤드라인을 허용한다 [3]
- 다크+네온 또는 Warm+Teal 양극 [3,4]
- 9:16 세로 포맷이 가장 빠르게 성장한다 [3]

---

## 접근성은 **숫자 린터**로 강제한다

- 본문 **24pt** 이상 [4]
- 타이틀 44–64pt [4]
- 본문 대비 **4.5:1**, 헤드라인 3:1 [4]
- 폰트 패밀리 2개 이하, variable weight [4]

---

## Assertion-Evidence 제목은 **명사구를 금지**한다

- "Sales Overview"를 "Q3 매출 23% 성장"으로 [27]
- 본문은 차트·표·인용으로만 지지한다 [27]
- 증거 없는 주장은 곧바로 재작성한다 [27]
- `visualizer-extractor` 출력을 후처리한다 [27]

---

## Claude Design은 **최종 도구가 아닌 초안 생성기**다

- 자연어 비전에서 초안으로, 다시 리파인으로 [2]
- codebase와 Figma에서 디자인 시스템을 추출한다 [2]
- 출력은 PDF, URL, **PPTX**, Canva 경로 [2]
- "complement Canva, not replace"의 포지션이다 [2,8]

---

<!-- _class: divider -->

# 라이브러리

편집 가능 차트와 스타일 훅

---

## Marp 단일 백엔드로는 **편집 가능 차트**가 안 나온다

- python-pptx `CategoryChartData` [14]
- `XL_CHART_TYPE.COLUMN_CLUSTERED` [14]
- `legend.position = BOTTOM` 표준 [14]
- PowerPoint 안에서 데이터 수정이 가능하다 [14]

---

## QuickChart는 **POST + backgroundImageUrl**이 미활용이다

- GET URL은 config 길이 제약을 받는다 [16]
- POST로 큰 config를 우회한다 [17]
- `backgroundImageUrl`로 브랜드 배경을 주입한다 [18]
- Chart.js v4 고정을 권장한다 [16]

---

## HF 자산은 **닫힌 품질 루프**의 재료가 된다

- ChartMimic few-shot으로 차트 다양성 확보 [29]
- docling-layout-heron으로 레이아웃 스코어링 [30]
- google/deplot으로 외부 차트 역공학 [31]
- ChartGalaxy는 상업 이용 주의 cc-by-nc [28]

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

## robonuggets의 **22개 예제**가 참고 표준을 정한다 [23,25]

![bg fit](figures/chart-04-style-reference-assets.png)

<!-- _footer: 스타일 레퍼런스 에셋 수 — 참고 스킬 비교 -->

---

<!-- _class: divider -->

# 실행

P0에서 P3까지 2주 로드맵

---

## P0·P1·P2를 **2주 안**에 연쇄 배치한다

- P0 — 제목 규약 + Design Rules 8개 + examples/ [23,27]
- P1 — visualizer-judge + Playwright QA [1,24]
- P2 — 3-preview + backend dispatcher [25,26]
- P3 — ChartMimic·docling 자동 스코어링 [29,30]

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
