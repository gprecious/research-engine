# AI 이미지 벡터화 프로토타입

_Started 2026-05-22 09:14 UTC_

---

## User

다음 research 요약을 받아서 **인터랙티브 프로토타입** (Next.js/React 형태) 으로 만들어줘.

== research 요약 시작 ==
---
title: "AI 이미지 벡터화 서비스 — 알고리즘 조사 (당근 비즈니스 포스트 기반)"
input: "https://www.daangn.com/kr/business-posts/698ebd845f07224f42fa130b"
input_type: blog
slug: 2026-05-22-ai-image-vectorization-service
created: 2026-05-22
intent_mode: user
sources_count: 37
---

> 📒 Notion: https://www.notion.so/AI-368c7d8a631181fe8813f095c20a4ca5

## TL;DR

당근 포스트는 **AI 생성 PNG → 인쇄소 통과 가능한 벡터(SVG/AI/EPS)** 로 변환해주는 디자인 서비스다. 동일 서비스 구축의 기술 코어는 **raster→vector 트레이싱**으로, 2026년 현재 두 갈래가 존재한다 — (1) **클래식 트레이서**(potrace/vtracer/autotrace 등)는 1~10초 내 빠르고 MIT/Apache 라이선스로 자유롭게 상용 가능하지만 콘텐츠 인식 부재로 AI 생성 노이즈·그라디언트에 취약하다 [13][27]. (2) **딥러닝 SOTA**(LIVE/VectorFusion/SVGDreamer/StarVector 등)는 품질이 압도적으로 높지만 GPU에서 분 단위(1~13분) 처리 시간이라 현실적 1차 스택은 못 된다 [5][6][8][10][11]. **권장 아키텍처는 vtracer(Rust/Python, MIT)를 1차 엔진으로** 두고, AI 이미지 전처리(배경 제거 rembg + 색 양자화 + 노이즈 제거)와 후처리(svgo 단순화)를 파이프라인으로 묶는 것 — 단, **자동 변환 후 수작업 클린업이 사실상 불가피**하다는 점이 디자이너 시장(딘디자인 포함)의 부가가치 핵심이다 [29][31][32].

## 1. 컨텍스트 — 당근 포스트가 제시한 문제

**서비스 본질** [1]
- 대상: AI(Midjourney/DALL-E/SD)로 만든 PNG/JPG 로고를 인쇄소에 가져갔다가 거절당한 자영업자
- 인쇄소 거절 사유 4가지: ❶ 해상도 부족, ❷ 확대 시 픽셀 깨짐(비트맵 본질), ❸ 로고는 다양한 크기로 쓰임(컬러/흑백/단색 버전 필요), ❹ 배경·외곽선 정리 부족 (컷팅 불가)
- 솔루션: **벡터화 = 픽셀 이미지를 선/곡선 기반 데이터(SVG/AI/EPS)로 변환** + "출력 파일 세트"(로고 벡터 파일 / 인쇄용 / 온라인용)로 패키징 판매
- 명시 한계: "인물 사진·실사 사진은 벡터화하면 그림처럼 변환되고 디테일 감소" → **로고/심볼/일러스트 도메인 전용 서비스**

**시장 신호** [33][34][35]
- 동일 카테고리 상용: Vectorizer.AI($9.99/월 웹 무제한, API 별도), Vector Magic($295 데스크탑·논란), Adobe Image Trace(번들), Recraft V4(native SVG 생성)
- Fiverr/Upwork "vectorize my logo" 인력 시장은 자동 도구 결과를 받아 **수작업 리빌드** 포함 시 $200~600/프로젝트 — 딘디자인 모델과 가장 가까움 [29]

## 2. 알고리즘 분류 체계

벡터화 알고리즘은 5계열로 분류된다.

| 계열 | 대표 | 특징 | 처리 시간 | 라이선스 |
|---|---|---|---|---|
| **클래식 트레이서** | potrace, vtracer, autotrace, imagetracerjs | 색 양자화 → 영역 분리 → 외곽선 추적 → Bézier 피팅. 학습 불필요. | 0.1~10초 (CPU) | 분기 (MIT~GPL) |
| **기하 프리미티브** | primitive | 힐 클라이밍으로 삼각형/원/베지어 반복 추가, MSE 최소화 | 수 초~분 (CPU) | MIT |
| **DL 최적화 (per-image)** | DiffVG, LIVE, O&R | 미분 가능 래스터라이저로 픽셀 손실을 SVG 파라미터에 역전파. 학습 불필요, GPU 필수. | 1~13분/이미지 (GPU) | Apache-2.0 |
| **DL 생성 (text→SVG)** | VectorFusion, SVGDreamer, DiffSketcher, NeuralSVG, T2V-NPR | Diffusion SDS/VSD 손실 + DiffVG. 사전학습 모델 활용. | 수 분~10분+ (GPU) | MIT/Apache 혼재 |
| **LLM 코드 생성** | StarVector | ViT + StarCoder가 SVG 코드를 직접 생성. circle/rect 등 의미적 도형 선택. | 41~74초 (GPU) | unspecified |

→ **프로덕션 1차 선택은 클래식**, **DL은 품질이 핵심인 프리미엄 옵션** [13][16][10].

## 3. 클래식 트레이서 비교 (프로덕션 후보)

### 3.1 vtracer — 권장 1순위
- **알고리즘**: 색 클러스터링 → O(n) Bézier 피팅 → 계층적 스태킹(hole 없는 컴팩트 출력) [13]
- **라이선스/배포**: MIT, Rust 바이너리 + `pip install vtracer` + WASM 웹앱 + 6056 stars, 2026-03 활성 [13]
- **장점**: O(n) 알고리즘으로 potrace(O(n²)) 대비 빠름, 컬러 지원, CLI 1줄 변환
- **약점**: 라인아트(설계도/선화)에서 성능 떨어진다는 HN 평가 — 색 영역 분리에 최적화 [27]
- **권장 파라미터** (실무): `--color_precision 6 --gradient_step 16 --filter_speckle 4 --corner_threshold 60 --segment_length 4 --splice_threshold 45`

### 3.2 potrace (+ mkbitmap)
- **알고리즘**: 이진화 전용, O(n²) Bézier 피팅, Peter Selinger 1997. 컬러는 mkbitmap 전처리로 변환 후 적용 [14]
- **라이선스**: GPL-2.0 → 제품에 정적/동적 링크 시 소스 공개 의무. **SaaS 형태로 호스팅(서버 사이드 실행)만 한다면 AGPL이 아니므로 비공개 가능** [14]
- **포지션**: 흑백 로고·라인아트의 골드 스탠더드. 컬러 일러스트는 vtracer가 우월 [27][35]

### 3.3 autotrace
- **알고리즘**: 아웃라인 + 센터라인 이중 모드, 색 감소·despeckle 내장, 다중 출력(SVG/EPS/DXF) [15]
- **라이선스**: GPL-2.0 — SaaS 권장
- **포지션**: 다중 포맷 익스포트 필요할 때 (특히 레이저커터용 DXF)

### 3.4 imagetracerjs
- **알고리즘**: 색 양자화 → 레이어 분리 → 외곽선 → Bézier. 순수 JS [24]
- **라이선스**: Unlicense (퍼블릭 도메인)
- **포지션**: 클라이언트 사이드 즉시 미리보기, 서버리스 워커. 단 2023년 이후 업데이트 미진

### 3.5 primitive — 보조 도구
- **알고리즘**: 힐 클라이밍 simulated annealing으로 삼각형/원/사각형/베지어 N개 반복 추가, MSE 최소화 [23]
- **포지션**: 정밀 트레이싱이 아니라 **아트 스타일 변환**. 로우폴리/포스터화 효과로 부가 서비스 제공 가능 (13k+ stars MIT)

### 3.6 commercial: Vector Magic / Vectorizer.AI / Adobe Image Trace
- Vector Magic: HN에서 "가장 인상적인 raster-to-vector" 평이 반복되지만 Trustpilot 2.4/5, $295 비판 [27][29]
- Vectorizer.AI: Vector Magic 팀의 후속작, 동급 품질 — **벤치마크 기준점으로 삼아야 함** [33]
- Adobe Image Trace: 파라미터 조정 가능하나 노드 과다 발생 빈번 [35]

## 4. 딥러닝 SOTA — 품질 프리미엄 옵션

### 4.1 DiffVG (2020 SIGGRAPH Asia) — 기반 인프라 [4][16]
- **방법론**: SVG 경로 파라미터에 대한 **미분 가능한 래스터라이저**를 최초 제안. 가우시안 prefiltering + 다중 샘플링 두 방식 지원.
- **임팩트**: LIVE·VectorFusion·DiffSketcher·SVGDreamer·T2V-NPR·NeuralSVG·O&R **전부 DiffVG를 백본으로 사용** — 이 분야의 사실상 표준
- **라이선스**: Apache-2.0, 1235 stars, 2025-05 최신 커밋
- **약점**: CUDA 빌드 필요, GCC 5.x 호환성 이슈 (특히 LIVE 빌드 시 자주 막힘)

### 4.2 LIVE (CVPR 2022 Oral) — raster→vector 직접 변환 [5][17]
- **방법론**: 재구성 손실 높은 영역에 Bézier 경로를 **점진적으로 추가(layer-wise)** + UDF 가중 재구성 손실 + 자기교차 방지 손실. XDoG 엣지 감지로 초기화 가속
- **출력**: 위상 보존 closed Bézier 경로, 5개 경로만으로도 단순 이미지 재현
- **한계**: 빌드 환경 까다로움(GCC 5.x), 이미지당 수 분, 2024-02 이후 업데이트 없음
- **포지션**: **AI 로고 자동 변환 품질의 학술 기준선** — vtracer 출력과 LIVE 출력의 격차가 곧 "수작업 클린업 필요량"

### 4.3 Optimize & Reduce (AAAI 2024) — LIVE 가속 [12]
- **방법론**: 하향식. DBSCAN으로 색 영역 초기화 → DiffVG 전체 동시 최적화 → 중요도 낮은 경로 절반 제거 반복 (256→128→64)
- **결과**: **LIVE 대비 10배 속도**, 이모지/클립아트/NFT/AI 생성 이미지 도메인 무관 동작
- **포지션**: LIVE를 프로덕션 시간에 근접시킨 후속 연구 — 자체 구현 또는 포크가 가성비 최고

### 4.4 VectorFusion (CVPR 2023) — text→SVG의 출발점 [6]
- **방법론**: Stable Diffusion SDS 손실을 잠재 공간으로 확장 + DiffVG. 64개 Bézier 경로 기본. 픽셀아트(32×32) / 선드로잉(16 strokes) 모드 지원
- **벤치마크**: R-Precision 81.3%, CLIP similarity 29.4 (CLIPDraw 77.3% 대비 우위)
- **포지션**: 텍스트→로고 생성 부가 기능의 기준 구현. SVGDreamer/T2V-NPR가 후속 개선

### 4.5 SVGDreamer (CVPR 2024) — text→SVG 품질 SOTA [8]
- **방법론**: SIVE(어텐션 맵 기반 전경/배경 분리) + VPSD(파티클 분포 기반 SDS, 모드 붕괴 방지) + ReFL(미적 점수 RLHF)
- **결과**: FID 59.13 (VectorFusion 100.68 대비 **41% 개선**), Aesthetic 5.54
- **6가지 스타일**: 아이콘그래피, 스케치, 픽셀아트, 저다각형, 회화, 수묵화 — 로고 서비스에 직접 호환 폼팩터
- **라이선스**: Apache-2.0

### 4.6 DiffSketcher (NeurIPS 2023) — 스케치/라인 드로잉 [7]
- **방법론**: 스트로크를 4 제어점 cubic Bézier + 불투명도로 표현. LDM 교차/자기 어텐션 결합으로 초기 위치 지능 배치
- **결과**: CLIP 의미 일관성 0.3494 (CLIPasso 대비 +13.6%), 사용자 혼동 점수 0.65(실제 스케치 0.67)
- **포지션**: 손그림 입력 처리 또는 **라인 아트 스타일 출력** 모드에 적합

### 4.7 NeuralSVG (2025) — 적은 경로로 유연한 표현 [9]
- **방법론**: 전체 SVG 장면을 소형 MLP로 표현(implicit). Nested Dropout 정규화로 추론 시 형태 수 유연하게 조절. 16 shapes 기본
- **결과**: 4개 형태만으로도 거시 구조 포착. 배경색·종횡비 동적 조절 지원
- **포지션**: **변형 가능한 로고**(가로/세로/모노톤/풀컬러 여러 변형 자동 생성)에 적합 — 당근 포스트의 "컬러/흑백/단색 버전 세트" 정확히 매칭

### 4.8 T2V-NPR (SIGGRAPH 2024) — 경로 평활도 SOTA [11]
- **방법론**: 이중 브랜치 VAE(Transformer + CNN) 24차원 잠재 공간. 2단계 최적화(VSD → 저불투명도 제거 → 정제)
- **결과**: 경로 평활도 0.8012 (VF 0.6322), 경로 수 40 (VF 128 대비 68.8% 감소)
- **약점**: **13분/SVG (3090 GPU)** — 비동기 잡 큐 전제

### 4.9 StarVector (NeurIPS 2024) — LLM 패러다임 [10]
- **방법론**: ViT(SigLip 384px) + StarCoder LLM이 SVG 코드를 자기회귀 생성. **circle, rect, polygon, text를 의미적으로 선택** — 원 1개를 `<circle/>` 하나로 표현 (Bézier 수백 개 대신)
- **결과**: 토큰 수 ~3k (LIVE 18k+ 대비 **83% 절감**), DinoScore 0.966~0.984, **다이어그램 생성 유일 성공**
- **한계**: 16k context 제한, 41~74초/샘플, 시각 피드백 최소
- **포지션**: 단순 도형 위주 로고(아이콘) 변환에서 **출력 SVG가 가장 깔끔** — 인쇄소 통과율 향상에 직접 기여 가능

### 4.10 Im2Vec / DeepSVG — 사전학습 생성 모델
- **Im2Vec** [3]: 벡터 감독 없이 래스터만으로 VAE 학습 (이모지·아이콘 도메인). 2022년 이후 업데이트 없음
- **DeepSVG** [2]: 계층적 Transformer VAE로 SVG-Icons8 학습 → 보간/애니메이션. RE 0.012. **out-of-domain 적용 불가** (학습 데이터셋 도메인 한정)
- **포지션**: 직접 트레이싱보다 **로고 변형 자동 생성** (보간으로 컬러/형태 변종 만들기)에 활용 가능

## 5. 입력 타입별 권장 알고리즘 매핑

사용자가 다중 선택한 4가지 입력 타입(AI 생성 로고 / 스캔 / 손그림 / 일러스트) 기준:

| 입력 | 1차 (빠르고 무료) | 2차 (품질 프리미엄) | 전처리 핵심 |
|---|---|---|---|
| **AI 생성 로고** (MJ/DALL-E/SD) | **vtracer** + 노이즈 제거 + 색 양자화 | LIVE 또는 O&R | rembg(배경 제거), `flat design, solid colors, white background` 프롬프트 가이드 — `gradient, texture, shadow, noise, blur` negative [30] |
| **스캔 로고** (종이/명함) | **autotrace** (despeckle 내장) 또는 vtracer | LIVE | 기울기 보정(deskew), 조명 정규화, 이진화(Otsu/Sauvola), mkbitmap |
| **손그림 스케치** | **potrace** + mkbitmap | **DiffSketcher** (스타일링 함께) | 콘트라스트 강화, 펜 두께 통일 |
| **복잡한 일러스트/캐릭터** | **vtracer** color | **LIVE / O&R / SVGDreamer SIVE** | **Segment Anything으로 객체 마스크 분리 후 각각 트레이싱하고 합치는 방식**이 HN에서 제안됨 [27] |

→ **공통**: 자동 변환 후 **수작업 클린업 단계가 필수**이며, 이것이 곧 딘디자인류 서비스의 차별화 포인트이다 [29][31][32].

## 6. 프로덕션 스택 권장

스택 미정 답변 기준, 3가지 구성을 제안 — 알고리즘 선택이 스택을 강제한다.

### 옵션 A — Python 풀스택 (연구 친화, 가장 빠른 출시)
```
[FastAPI] → 전처리(Pillow/OpenCV/rembg)
         → vtracer(pip) [1차 시도, ~1초]
         → 품질 평가(LPIPS or 인간 검토 큐)
         → LIVE/O&R (옵션, GPU 큐) [고품질 재시도]
         → 후처리(svgo via Node subprocess)
         → 출력 패키지(SVG + EPS via Inkscape CLI + PDF)
```
- **장점**: vtracer는 Python 바인딩(MIT) 제공, LIVE/DiffVG는 PyTorch 네이티브. 가장 적은 마찰
- **단점**: 트래픽 처리량은 낮음 → BG 워커(Celery/RQ)로 비동기 필수

### 옵션 B — Rust/Go 백엔드 + Python 워커 (확장성)
```
[Axum/Go API] → vtracer Rust 라이브러리 (in-process) [핫패스]
              → 큐 → Python GPU 워커 (LIVE/DiffVG) [콜드패스]
              → resvg(Rust)로 미리보기 PNG 렌더
```
- **장점**: 핫패스 처리 throughput 10배 이상, 단일 바이너리 배포 가능
- **단점**: 두 언어 운영 비용

### 옵션 C — Node.js 풀스택 (웹 통합 최우선)
```
[Next.js API] → imagetracerjs (즉시 미리보기, 클라이언트 OR 서버)
             → 서버에서 vtracer-wasm 또는 vtracer Rust 바이너리 호출
             → svgo로 후처리
```
- **장점**: 프론트엔드와 단일 코드베이스, Vercel/Cloudflare Workers 배포 가능
- **단점**: GPU 추론은 별도 마이크로서비스로 분리 필요

**라이선스 안전 조합** (상업 클라우드 서비스 전제):
- 1차 엔진: **vtracer (MIT)** — 핵심
- 후처리: **svgo (MIT)** — svgcleaner(GPL) 대체 필수
- 렌더 검증: **resvg (Apache-2.0)**
- 전처리 배경 제거: **rembg (MIT)** — Pillow/OpenCV는 BSD-호환
- GPL 도구(potrace/autotrace/svgcleaner)는 **격리된 SaaS 서버 사이드 실행만** (사용자에 바이너리 배포 금지)

## 7. 인쇄 워크플로우 통합 요구사항 (당근 포스트가 약속한 부분)

자동 변환만으로 끝나면 인쇄소가 다시 거절한다 — 출력 파일 세트에 **반드시 포함**해야 할 항목 [37][32]:

- **컬러 모드**: RGB → **CMYK** 변환 (또는 Pantone Solid Coated spot color, 스크린 인쇄용)
- **선/텍스트 임계값**: 0.5pt 미만 선 / 6pt 미만 텍스트 → 인쇄 불가, 자동 거절·보강 필요
- **텍스트 outline 변환** (expand to outline) — 폰트 누락 방지
- **노드 단순화**: "Every anchor point is a stop your laser or printer has to make. Too many, and you'll get stalls, burns, or overexposure." [32] → svgo + 임계값 simplification 필수
- **컬러 분리** (스크린 인쇄): 색상별 레이어 분리 SVG 또는 PDF 분판
- **다중 버전 자동 생성** [1]: 컬러 / 흑백 / 단색(라인아트) — DiffVG로 색만 최적화하는 후처리 패스로 자동화 가능, NeuralSVG의 변형 메커니즘도 후보
- **출력 포맷 다중 익스포트**: SVG (원본) + AI/EPS (Inkscape CLI 또는 cairosvg→EPS) + PDF/X-1a (인쇄용) + PNG 미리보기

## 8. 시장/가격 벤치마크

| 서비스 | 가격 | 포지션 | 위협/기회 |
== research 요약 끝 ==

## 명확화 없이 다음 사전 결정 그대로 진행해줘 (질문 던지지 마세요)

- **스타일**: modern minimal, 흰 배경에 단일 accent color (#3b82f6 또는 비슷한 saturated blue)
- **페이지**: (1) landing — hero + 핵심 문구 + Try free CTA, (2) /upload — 파일 업로드 input + Convert 버튼 + SVG preview 영역, (3) /health — 단순 OK 응답
- **타입스케일**: H1 56px / H2 28px / body 16px, font-family system-ui
- **CTA selector**: `data-testid="cta-try"` (랜딩의 Try free 버튼), `data-testid="convert"` (업로드 페이지의 변환 버튼), `data-testid="svg-preview"` (변환 결과 영역)
- **인터랙션**: 업로드 → Convert 클릭 → svg-preview 안에 mock SVG 즉시 표시 (실제 변환 알고리즘 불필요, mock 으로 OK)
- **컴포넌트 라이브러리**: 외부 의존성 없이 vanilla React + inline style
- **타겟**: 디자이너 + 마케터 (일러스트 / 로고 raster → SVG 변환 수요)

마지막에 `Hand off to Claude Code` 가능한 상태로 마무리해줘.

## User

위 디자인이 미완성이다. index.html 이 landing.jsx, upload.jsx, health.jsx, app.jsx 4개 파일을 참조하지만 생성되지 않았다.

지금 즉시 다음 4개 파일을 생성해라. 명확화 질문 던지지 말 것. 이미 모든 결정사항은 첫 메시지에 포함되어 있다.

1. landing.jsx — Hero (H1 56px "Vectorize raster art", H2 28px subtitle, primary CTA button Try free with data-testid="cta-try" linking to #/upload). Use Nav and Footer from components.jsx. Inline style. Vanilla React. Background #ffffff, accent VECTRA_BLUE.

2. upload.jsx — Form with file <input type="file" accept="image/*">, Convert button data-testid="convert", svg-preview div data-testid="svg-preview". Clicking Convert renders a mock <svg> inside svg-preview. Use Nav from components.jsx. Inline style.

3. health.jsx — Single page that renders the literal text "OK" centered on screen. Minimal styling.

4. app.jsx — Hash-based router: #/ → Landing, #/upload → Upload, #/health → Health. Use ReactDOM.createRoot(document.getElementById('root')).render(<App />).

각 파일을 ```jsx 블록으로 출력. 질문 금지. 바로 코드만.

## User

landing.jsx, upload.jsx, health.jsx, app.jsx 4개를 지금 생성. PricingCard 같은 새 컴포넌트 추가 금지. 첫 메시지의 사양 그대로:

## Assistant

_[tool: list_files]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: done]_

_[tool: list_files]_

_[tool: done]_

_[tool: eval_js]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: eval_js]_

_[tool: done]_

_[tool: eval_js]_

_[tool: delete_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: done]_

_[tool: fork_verifier_agent]_

4개 파일 모두 생성 완료. 라우팅 정상 동작 (`#/` → Landing, `#/upload` → Upload, `#/health` → Health), 모든 `data-testid` 셀렉터 (`cta-try`, `convert`, `svg-preview`) 부착됨.

Handoff 준비됨 — 필요 시 **Handoff to Claude Code** 스킬로 진행하세요.

