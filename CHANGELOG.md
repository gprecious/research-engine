# Changelog

All notable changes to research-engine.
Versions follow [semver](https://semver.org/) — MAJOR.MINOR.PATCH.

## [Unreleased]

## [0.20.1]

LLM 위키 auto-ingest 가 **git clone 배포 환경에서 조용히 실패하던 패키징 결함** 수정.

### Fixed

- `lib/wiki/frontmatter.mjs` 의 `yaml` npm 의존성 제거 — 위키 페이지 frontmatter 의 고정·평면 스키마(문자열 스칼라 + 문자열 배열)에 맞춘 무의존 parse/serialize 로 대체. `node_modules` 가 gitignore 되어 URL clone 설치 시 미동봉이고 `npm install` 도 돌지 않아 `apply.mjs`/`report_mirror.mjs` 가 `ERR_MODULE_NOT_FOUND: yaml` 로 크래시 → auto-ingest 가 에러 없이 무산되던 문제를 영구 해소. 기존 위키 88개 페이지에 대해 실제 `yaml` 출력과 바이트 동일(파서 동등성·라운드트립·zero churn 검증) + 기존 `lib/wiki` vitest 70개 전부 통과.
- `package.json` 의 유일한 runtime dependency(`yaml`) 제거 → 플러그인은 이제 런타임 의존성이 전혀 없어 git clone 만으로 동작. `.claude-plugin`·`.codex-plugin` 매니페스트 0.20.0→0.20.1 동기.

## [0.19.0]

`/research` 가 끝나면 **자동으로 LLM 위키에 ingest** — 리서치 결과가 raw `research/<slug>/` 로만 남지 않고 즉시 harry 등 Obsidian 위키(`LLM-Wiki/`)로 합성된다.

### Added
- `commands/research.md` — Stage 5 에 **Step 7.6 (Auto-ingest into the LLM Wiki)** 추가. Notion 미러(step 7)·dream-ledger(step 7.5) 직후 실행. `vault_resolve.mjs` 로 vault 해석 → 부트스트랩 → 해당 `<slug>` 를 `commands/wiki.md` 의 단일-slug ingest 절차대로 합성 후 `apply.mjs`. `log.md` exact-match dedup 가드로 동일 slug 재실행은 no-op.
- 가드: vault 미해석(`ok:false`) 또는 `WIKI_AUTO_INGEST=0` 이면 조용히 skip. 위키 단계 오류는 리서치 산출물에 영향 주지 않음(절대 abort 안 함).
- vault 타게팅: `WIKI_VAULT`(절대) > `LLM_OBSIDIAN_VAULT_NAME`(+`LLM_WIKI_SUBDIR`, 기본 `LLM-Wiki`) — 기존 `vault_resolve.mjs` 정책 그대로. 동일 이름 vault 가 여러 개면 `WIKI_VAULT` 절대경로 핀 권장(split-brain 회피).
- **Codex 패리티**: `skills/research-engine/SKILL.md` 의 New Research Workflow 에 auto-ingest 단계(step 10) 추가 — Claude 의 Step 7.6 과 동등하게 `vault_resolve.mjs` 로 resolved vault(harry/`LLM-Wiki`)에 자동 합성(로컬 `wiki/` 아님). `.codex-plugin/plugin.json` 0.18.1→0.19.0 동기(이전엔 codex 매니페스트만 lag 라 codex 로 research 시 auto-ingest 가 미작동). 이제 Claude·Codex 양 런타임에서 동일 동작.

## [0.18.2]

`/evolve youtube-adapter` — `findings-guidance` 영역 v1→v2 승격(non-bench). dream `drm_2026-06-09-1005-ai-agent-tooling` 의 `pattern-adapter-failure-modes` #2(Whisper 키 부재 시 캡션이 primary 로 조용히 승격되어 AV 교차검증이 누락됐으나 success 로 기록됨) 대응.

bench 스킵 사유: 이 가드는 **degraded(caption-only) 조건에서만 발동**하는 정직성 규율인데, 이 머신은 0.18.1 로컬 whisper.cpp 로 bench 영상(`youtube-3blue1brown-gpt`)에서 항상 Whisper 가 성공 → 캡션 전용 분기가 트리거되지 않아 통계 gate 가 구조적으로 hold(차이 0)를 반환, candidate 를 폐기하게 됨. coverage 위주 LLM-judge 로는 source_type 정직성을 측정할 수 없어 대신 정확성 교정으로 직접 promote.

### Changed
- `agents/youtube-adapter.md` — `findings-guidance` 영역: primary transcript 가 Whisper/오디오 부재로 caption-only 인 구간의 finding 은 반드시 `source_type: "youtube-captions"` 로 강제(`youtube-whisper`/`youtube-frame` 금지), 음성/영상 검증된 것처럼 표현 금지 → 캡션 전용 fallback 이 실제 coverage gap 신호로 findings 에 드러남.
- `research/_index/evolve-ledger.json` — youtube-adapter v2 엔트리(`promotion: "non-bench"`, metrics 는 재측정 없이 v1 승계, `ci_lower: null`). v1 은 `agents/archive/youtube-adapter.v1.md` 로 보존.

## [0.18.1]

로컬 Whisper 백엔드에 **whisper.cpp** 추가 — Python/torch 스택 없이(mlx-whisper 는 torch 하드 의존으로 venv ~891MB) 이미 설치된 `whisper-cli` 바이너리로 온디바이스 전사. 디스크 부담이 모델 파일(예: ggml-large-v3-turbo-q5_0 ~547MB)뿐. 실측: 13.6분 WWDC 영상을 M-series 에서 ~34초·키 없이 143세그먼트 전사.

### Added
- `scripts/yt_fetch.sh` — `whisper.cpp`(`whisper-cli`) 백엔드. mp3 직접 입력, `whisper.cpp` JSON(`transcription[].offsets` ms)을 verbose_json(`segments[].start/end`)으로 변환해 기존 파이프라인 통과.
- 모델 자동 탐색: `RESEARCH_ENGINE_WHISPER_CPP_MODEL`(명시 경로) → `~/.config/research-engine/whisper-models/ggml-*.bin`(turbo/large 우선).
- Python 백엔드 인터프리터 해석 `resolve_whisper_python()`: `RESEARCH_ENGINE_PYTHON` → 관용 venv(`~/.config/research-engine/whisper-venv`) → `python3`. 시스템 python 오염 없이 격리 venv 사용 가능.
- 노브: `RESEARCH_ENGINE_WHISPER_DISABLE_CPP=1`(whisper.cpp 건너뛰기).
- bats: whisper.cpp 스텁 전사 테스트 추가, Python 스텁 테스트는 cpp off + interpreter 고정으로 격리.

### Changed
- `whisper_local()` 백엔드 우선순위: **whisper.cpp → mlx-whisper → openai-whisper → (cloud) Groq → OpenAI**. 백엔드 부재 메시지가 whisper.cpp/mlx 설치를 우선 안내.

## [0.18.0]

Obsidian-backed LLM Wiki librarian release. `/wiki` now resolves a single global vault, tags generated pages, maintains safe fixes automatically, drafts risky synthesis/schema output, promotes approved drafts, and publishes only verified live content.

### Added
- Name-based Obsidian vault resolution via `WIKI_VAULT`, `LLM_OBSIDIAN_VAULT_NAME`, and `LLM_WIKI_SUBDIR`.
- Generated-page tagging: `ai-generated`, `llm-wiki`, and page type.
- `/wiki librarian --report|--apply --budget N` with stale/provenance/raw-coverage audit, safe auto fixes, `change_log.md`, reports, and draft isolation.
- `/wiki promote [<slug>|--all] [--critic]` for `_drafts/` to live promotion with index/log/change-log updates.
- `/dream --target=wiki` deterministic draft synthesis + `_todos` + `_index/reflect_state.json`.
- `/evolve --target=wiki --region=<region>` schema candidate drafts + `_index/evolve-ledger.json` without mutating live `AGENTS.md`.
- `scripts/wiki_librarian_cron.sh` headless monthly wrapper with `--dry-run`.

### Changed
- `scripts/wiki_publish.sh` now publishes `concepts/`, `entities/`, and `synthesis/`, while excluding `_drafts/`, `_todos/`, `_index/`, and `ephemeral/`.
- Wiki constitution and index now mark AI-generated content and document temporal/promotion rules.

### Fixed
- Librarian raw-coverage discovery ignores non-session directories such as `research/_index`.

## [0.17.1]

로컬 Whisper 백엔드 — 자막 없는 영상의 음성 전사를 **클라우드 키 없이** 온디바이스로 수행. Whisper 는 본래 키가 필요 없는데 `yt_fetch.sh` 가 Groq/OpenAI 호스팅 API 로만 하드코딩돼 있어, 키 미설정 시 frames/whisper 교차검증이 조용히 누락되던 문제 해결 (Apple Silicon 사용자에게 특히 부적절했음).

### Added
- `scripts/yt_fetch.sh` — `whisper_local()` + `whisper_local_available()`: Apple Silicon 은 `mlx-whisper`(기본 `mlx-community/whisper-large-v3-turbo`), 그 외 `openai-whisper` 로 온디바이스 전사. verbose_json 형태로 출력해 기존 `emit_whisper_ok`/`write_vtt_from_whisper_json` 파이프라인을 그대로 통과.
- 환경변수: `RESEARCH_ENGINE_WHISPER_MODEL`(mlx HF repo), `RESEARCH_ENGINE_WHISPER_OPENAI_MODEL`(openai-whisper 이름, 기본 `turbo`), `RESEARCH_ENGINE_WHISPER_DISABLE_LOCAL=1`(로컬 비활성).
- `tests/bats/test_yt_fetch_whisper.bats` — 백엔드 부재 메시지, 로컬 스텁 전사, 로컬 우선순위(키 있어도 네트워크 미호출) 3종.

### Changed
- `whisper_fallback()` 우선순위: **로컬(키 불필요) → Groq → OpenAI**. 백엔드가 하나도 없을 때만 실패하며, 에러 메시지가 로컬 설치(`pip install mlx-whisper`)를 우선 안내.
- `tests/bats/test_yt_fetch.bats` — 클라우드/캐시/자막 검증 테스트의 결정성을 위해 `setup()` 에서 로컬 백엔드 비활성 (mlx-whisper 설치된 머신에서 로컬이 우선되어 깨지는 것 방지).

## [0.17.0]

YouTube 분석 AV-first 전환 — 영상(frames)+오디오(Whisper)를 모든 영상에서 기본 수행, 자막은 교차 검증용. herdr 3-worker(claude/codex/omp) 상호 비판 리뷰 합의 반영.

### Added
- `scripts/yt_fetch.sh media <URL> <DIR>` — 영상 1회 다운로드 + 검증된 캐시 재사용 (`.part`/오디오 없는 잔존물 거부, 임시 디렉토리 경유 원자적 배치), `{status, path, cached}` JSON 출력.
- `scripts/yt_fetch.sh transcribe <FILE|URL> <DIR>` — 자막 체크 없이 바로 Whisper 전사 (Groq → OpenAI fallback) + 기존 산출물 재사용 가드 (`whisper_model:"cached"`).
- `scripts/yt_fetch.sh captions ... --captions-only` — 자막 부재 시 Whisper 로 넘어가지 않는 교차 검증 전용 모드 (자막 부재 = `status:"ok"` + 빈 `caption_files`). preview 는 플래그 없는 기존 동작 그대로.
- AV-first 통합 bats 시나리오 (다운로드 1회 + whisper/captions 산출물 분리 검증).

### Changed
- **youtube-adapter** — 분석 우선순위 반전: frames(시각) + Whisper(오디오) 를 `intent.focus` 무관 **항상** 수행, 자막은 고유명사·숫자·용어 교차 검증용으로 강등 (Whisper 실패 시 자막이 주 전사본으로 승격). 영상 다운로드 2회 → 1회 (`media` 캐시 공유). 산출물은 `$cache_dir` 아래 `media/`·`frames/`·`whisper/`·`captions/` 로 분리 (whisper.vtt 자막 오인 차단). media 실패 시 재다운로드 금지(captions-only fallback). transcript 는 파일 직접 쓰기 대신 `artifacts.transcript_md` 반환. findings `source_type` 에 `youtube-whisper` 구분 추가.
- `commands/research.md` — youtube-adapter timeout 5분 → 20분 (긴 영상 AV-first 대응).
- `skills/research-engine/SKILL.md` — preview(자막 우선, 무변경) vs 본 분석(AV-first) 구분 명시.

### Fixed
- `captions` 가 디렉토리 내 `whisper.vtt` 를 자막으로 오인 카운트하던 잠재 버그 (재실행 시 발생) — vtt 탐지에서 `whisper.vtt` 제외.

## [0.16.0]

### Added
- YouTube transcript 경로에 OpenAI `whisper-1` fallback + curl retry (Groq 불가 시). (릴리즈 당시 CHANGELOG 누락 — 0.17.0 작업 중 소급 기재.)

## [0.15.0]

LLM 위키 레이어 + YouTube 프레임 watch + 어댑터 프롬프트 진화 3건 promote.

### Added
- **LLM 위키 레이어** (`/wiki ingest|query|lint|publish`) — research 세션을 개념·엔티티 페이지로 합성·상호링크. 카탈로그 기반 링크, 단일 원자 apply(섹션 merge·멱등·경로탈출 방어), Quartz 정적 발행. `lib/wiki/` (vitest) + `tests/research-engine/wiki.test.sh` (bats). claude×codex 3라운드 교차검증 + codex 구현리뷰 반영.
- **YouTube 프레임 watch 추출** — `scripts/yt_fetch.sh` 가 캡션 외에 핵심 구간 프레임을 뽑아 시각 정보까지 findings 에 반영.
- `agents/context7-adapter.md` · `agents/community-adapter.md` evolvable region 마킹.

### Changed (adapter evolution — `/dream` → `/evolve` 자동 루프 산출)
- **youtube-adapter v1** (CI 하한 +1) — 영상 길이 기반 `mm:ss`/`hh:mm:ss` timecode 결정적 선택.
- **blog-adapter v1** (CI 하한 +4) — `fetch-strategy` region: 403/402·nav-only truncation 시 즉시 `failed` 대신 fallback ladder (firecrawl→WebFetch→r.jina.ai 리더→WebSearch 스니펫 salvage) + 알려진 차단 도메인 사전 경고. 차단 도메인 수확률 0→partial. 차단 도메인(all3dp) 타깃 bench, paired bootstrap accept.
- **community-adapter v1** (CI 하한 +7) — `retry-policy` region: 스레드 403/402 시 skip 대신 fallback ladder (WebFetch→r.jina.ai→Reddit `.json`/old.reddit→WebSearch salvage), 404 만 즉시 skip. forum.bambulab(402) 타깃 bench, 도구 잠금 재측정으로 측정 오류 보정 후 accept.

## [0.14.0]

GEPA-lite 어댑터 프롬프트 진화 루프. `/evolve` 슬래시가 evolvable 마킹된 어댑터 영역을 mutate → bench `--candidates` 로 평가 → Pareto + paired-bootstrap CI 게이트 → accept/reject/hold. `/dream` D8 단계가 adapter_failure_modes 감지 시 `/evolve` 호출을 제안.

### Added
- `lib/evolve/` — Node ESM 유틸 (vitest)
  - `extract_evolvable.mjs` — `<EVOLVABLE id="…">…</EVOLVABLE>` 마커 parse/replace.
  - `pareto.mjs` — multi-metric dominance check (Pareto shed).
  - `statistical_gate.mjs` — paired bootstrap CI 통계 게이트.
  - `ledger.mjs` — `evolve-ledger.json` 상태기계.
  - `archive.mjs` — `versions/` 아카이브 + path helpers.
- `scripts/evolve_run.sh` + 네 개 Node wrapper (prepare/apply/decide/promote).
- `commands/evolve.md` — `/evolve` 슬래시 E1~E8 시퀀스.
- `agents/prompt-mutator.md` — mutation 에이전트 persona.
- `bench/run.sh --candidates` — 후보 어댑터 swap → bench → restore (atomic, backup 기록).
- `tests/research-engine/evolve.test.sh` + `evolve-e2e.test.sh` — 전체 accept/reject 사이클 bats.

### Changed
- `agents/youtube-adapter.md` — evolvable region 마킹.
- `commands/dream.md` — D8 에서 `adapter_failure_modes` 있을 시 `/evolve` 제안 라인.
- `commands/bench.md` — `--candidates` 플래그 spec.

### Fixed
- `scripts/memory_query.sh` — `--target-json` 값 누락 시 `shift 2` 가 silently 실패해서 무한루프 (CPU 46% × 8시간 hung 사례 관측). `shift; [ $# -gt 0 ] && shift` 로 underflow-safe 처리. 회귀 bats 추가.

## [0.13.0]

Cross-session learning layer. `/research` 가 과거 유사 세션과 dream 인사이트를 자동으로 어댑터 dispatch 에 주입하고, 5회 누적 시 `/dream` 호출을 제안. `/dream` 슬래시는 N개 세션에서 반복 패턴·어댑터 실패·자주 묻는 의도·prior art 군집을 추출해 `docs/dreams/<run-id>/` 에 readonly 인사이트로 축적.

### Added
- `lib/memory/` — Node ESM 유틸 (vitest 34 tests)
  - `tokenize.mjs` — 한·영 NFC 토크나이저
  - `similarity.mjs` — `input_type/topics/purpose_tokens` 가중합 매처 (W_TYPE=3, W_TOPIC=2, W_PURPOSE=1) + topK
  - `manifest_schema.mjs` — 파일시스템 → manifest entry 빌더 + `--build` CLI. **Self-healing**: README 존재 시 항상 sha256 재해시 → sources.json 의 stale hash 자동 갱신.
  - `ledger.mjs` — dream-suggestion 카운터 상태기계 + `--rebuild/--bump/--reset/--suggest?` CLI. `--rebuild` 가 same-dream-cycle 동안 `suggestion_shown_at` 보존 (anti-nag).
  - `query_cli.mjs` — manifest 읽고 topK + active dreams JSON shell wrapper.
- `scripts/memory_reindex.sh` — manifest + ledger atomic rebuild (idempotent, mtime invariant).
- `scripts/memory_query.sh` — fail-soft top-K prior + active dream insights. 모든 에러 경로에서 empty JSON + exit 0.
- `scripts/dream_run.sh` — `/dream` 오케스트레이터. `--resolve-only/--mint-only/--finalize` 3 모드, 모든 finalize 쓰기 tmp+mv 원자화.
- `commands/dream.md` — `/dream` 슬래시 시퀀스 (D1–D8) + 실패 처리.
- `agents/dream-extractor.md` — dream agent persona (4-category JSON contract: adapter_failure_modes / recurring_intents / prior_art_clusters / topic_coverage_gaps).
- `tests/research-engine/` — bats 23개 추가 (memory, dream, research-with-memory, dream-e2e, research-followup-occ) + 5 fixture 세트.

### Changed
- `commands/research.md` — 4 Stage hook 추가:
  - **Stage 2.5** Memory Query — preview 직후 `memory_query.sh` 호출, 결과를 `<report_dir>/cache/memory.json` 에 기록.
  - **Stage 4** dispatch — adapter 입력에 `prior_knowledge` 필드 + citation 요건 (재사용 시 slug/run_id 인용 필수).
  - **Stage 5.2** sources.json — `content_sha256` (README 해시) + `created_by` (actor 배열) 필수. Notion push 후 README 변경 시 sha256 재계산 의무.
  - **Stage 5.8** ledger 업데이트 + 제안 — Notion push 후 `memory_reindex.sh` → `ledger --suggest?` → 5회 누적 시 final message 에 `/dream` 제안 라인 포함.
- `commands/research-followup.md` — `session.md` write 직전 sha256 OCC precondition + 1회 자동 재시도 + atomic rename.
- `commands/bench.md` — report.md 작성 후 dream-ledger 비교, `last_dream_at < bench.started_at` 시 final message 에 `/dream --bench=<id>` 제안 (자동 트리거 없음).
- `package.json` — `test:bats` 가 새 bats 5개 포함.

### Test coverage
- bats: 36/36 (legacy 13 + memory 9 + dream 4 + research-with-memory 4 + dream-e2e 3 + research-followup-occ 3)
- vitest: 34/34 (tokenize 6 + similarity 10 + manifest_schema 6 + ledger 12)
- Real-repo verify: 87 기존 세션 manifest 인식, mtime invariant, similarity top-match 정확.

### Out of scope (의도적 미포함)
- Dream agent 의 자동 트리거 — 사용자가 `/dream` 명시 호출해야 함. 5회 누적 시 *제안*만 노출.
- Bench 결과의 자동 dream 입력 — `--bench=<id>` 옵션은 사용자가 명시.
- Legacy 80여 세션 backfill — derived 모드로 manifest 가 자동 인덱싱, 원본 파일 미변경.

## [0.12.1]

### Changed
- `lib/scenarios_validator.mjs` — `strict: true` (draft-2020-12 인식, 스키마 작성 버그 컴파일타임 검출) + `validate.errors` 즉시 캡처 (race-safe).
- `tests/research-engine/schemas/scenarios.schema.json` — `baseUrl.additionalProperties: false` (stray 필드 거부).
- `package.json` — `test:unit` 가 `lib/` 디렉터리 포함 → `scenarios_validator` 단위 테스트 보호.
- bats 테스트 3종 — `SLUG`/`TARGET` 파일 스코프 변수화, teardown 하드코딩 제거.

## [0.12.0]

### Added
- `/spec <slug>` — README + intent → `spec/scenarios.json` (TDD e2e 계약) + `spec/spec.md`. G0 게이트 (ajv strict schema + scenarios ≥ 3).
- `/design <slug>` — claude.ai/design 핸드오프만. 기존 handoff cache mode (재실행 시 skip).
- `/deploy <slug>` — `app/` (사용자가 외부 툴로 build) → hetzner LXC. G3 게이트 (prod URL e2e + /health 200).
- `agents/spec-author.md`, `agents/deploy-planner.md` — 신규 LLM persona.
- `lib/scenarios_validator.mjs` + ajv strict 검증 (`_meta.source_intent_hash` cascade hint).
- `tests/research-engine/` — 13 bats + e2e infra (env-driven runner).
- `scripts/deploy_lxc.sh` 가 deploy-planner 의 `lxc_config.json` 소비 (cores/memory/disk/systemd-unit override 가능).

### Removed (breaking)
- `/research-design <slug>` — 통합 파이프라인 제거. `/spec` + `/design` + 사용자 수동 build + `/deploy` 로 분리.
- `scripts/research_design_pipeline.sh`, `tests/research-design/pipeline.test.sh`.

### Changed
- `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh` (rename + lxc_config.json 인자 추가, systemd unit 이름 통일 `research-engine-app.service`).

### Out of scope (의도적 미포함)
- `/build` 자동화 — 사용자가 외부 툴 (v0, cursor 등) 로 직접 build.
- `/ship` orchestrator — `/build` 도입 시 같이 설계.
- G3 실패 시 자동 롤백 — LXC slug-idempotent 특성상 별도 설계 필요. v1 은 `deploy.json.prev_host` 보존만.

## [0.11.0]

### Added
- `/research-design <slug>` — claude.ai/design 자동화 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
- 3중 게이트: Playwright e2e + 4축 LLM judge (G1/G2/G3)
- cloak-browser 자동 로그인 → Tailscale m4 수동 폴백

## 0.10.0 — 2026-04-28

Driven by the v0.9.0 full-matrix bench (`bench/findings/2026-04-27-v0.9.0-validation.md`) which surfaced four follow-ups: arxiv depth gap, topic-mode reproducibility crash, citation diversity opacity, and bench harness UX.

### Added
- `agents/arxiv-adapter.md` — restructure related work into three explicit provenance buckets (author-cited prior art / forward citations / implementations + venue), 5-12 entries total. Each entry must have a specific `relation` phrase tying it to the analyzed paper. Validated on Mamba: cumulative arxiv swing -16 → 0 (TIE), citation count +103%, external links +133%.
- `bench/post_research_bookkeeping.sh` — single-call helper for RE-mode subagents. Diffs research-session snapshot, locates new session, copies README, runs collect_metrics, emits meta.json with proper failure handling. Replaces 5-step tail that 2-of-10 subagents had been skipping.
- `bench/collect_metrics.sh` — emit `unique_citation_n_count` alongside `citation_count`. Diversity ratio (citation_count / unique) now an at-a-glance metric. Schema + 1 new bats test added (8 collect_metrics tests total).

### Changed
- `commands/research.md` Stage 2 topic branch — WebSearch top 5 → top 10 results. Wider source pool reduces run-to-run variance for open-ended topic queries.
- `commands/bench.md` Stage 2 RE-mode — three steps (snapshot, Skill, helper) instead of five. Reduces the surface area where subagents shed steps.
- `bench/lib/judge_prompt.md` — Citation Quality axis explicitly penalizes repetition: a report with 30 markers across 3 unique sources scores LOWER than 10 markers across 8 distinct sources. Reproducibility prompt now ignores source-set overlap, scoring fact-set + claim-direction alignment only. Validated by re-judging v0.9.0 topic-mode outputs: score moved 3 → 8 with no output change.

### Documented
- `bench/judge.py call_claude()` — note that external `claude -p` subprocess hits subscription rate limits independently from the parent Claude Code session; in-session Agent dispatch (via `/bench` slash command) is the recommended judging path inside Claude Code.
- `bench/run.sh --judge` flag — same note in help text.

### Tests
- 24/24 bats passing (8 collect_metrics + 4 judge + 5 report + 3 bench_run + 4 push_to_notion).

### Notes — projected matrix impact
- v0.9.0 measured average Δ: −2.0
- B (arxiv refs) alone validated: Δ +12 swing on arxiv
- C (topic-mode reproducibility prompt) alone validated: 3 → 8 on a single re-judge
- Combined projection for v0.10.0 full re-bench: Δ +3 to +5 average. To be measured post-release.

## 0.9.0 — 2026-04-27

### Added
- `/bench` slash command — repeatable mini-bench comparing research-engine vs Claude Code baseline on a topic × 2-mode × 2-trial matrix, with LLM-as-judge 5-axis rubric (Coverage / Citation / Depth / Structure / Reproducibility) and improvement-opportunities report. Runs inside the user's session (RE mode invokes `Skill('research-engine:research')`; baseline dispatches a general-purpose subagent) because `claude -p` does not resolve plugin slash commands non-interactively. Outputs land under `bench/runs/<date>/report.md`.
- `commands/research.md` Stage 5 — DO-NOT-SKIP checklist preamble. The 8 numbered steps must all complete; the LLM previously stopped after the markdown writes (steps 2–6) and silently skipped Notion mirror (step 7) and final-message format (step 8).
- `lib/report_sections.md` §7 — required `한계 / 미해결 (Limitations)` section with explicit rules on what does / does not belong (≥2 bullets, never decorative). Driven by bench finding: vanilla-baseline reports surfaced limitations organically while RE reports omitted them entirely.
- `lib/report_sections.md` §4 — input-type-aware sub-structure. For `arxiv` / `huggingface` inputs, §4 (상세 분석) MUST sub-divide into `방법론 / 핵심 메커니즘`, `실험 결과 / 벤치마크`, `저자 한계 / 미해결` with ≥2 findings each. For `github` / `context7`, analogous sub-headings (`구조 / 모듈`, `활성도 / 메인테이닝`, `사용 패턴`). Bench finding: dedup pass collapsed ablations / method details / evaluation-table entries into single bullets, costing ~2 points on the Depth axis for academic content.
- `lib/report_sections.md` global rule — every factual claim sentence in §3 / §4 / §5 MUST end in at least one `[n]` marker. Mass-marker decorative citations at the end of long paragraphs are not acceptable. Unsourced factual claims must be removed, not retained without attribution. Bench finding: judges flagged RE citations as "decorative", "minimal", or "not tied to specific claims" on 4 of 5 cross-mode rationales.

### Changed
- `agents/arxiv-adapter.md` — PDF / HTML body fetch is now REQUIRED, not "only when needed for deep detail". Adapter must extract Method (§3), Experiments (§4), and any author-stated Limitations sections from the body, with concrete benchmark numbers in findings (not just abstract paraphrase). Findings count expanded 5–10 → 6–12 to accommodate body-derived content. Bench finding: RE produced 1517-word reports vs baseline 2752-word on the Mamba paper.
- `commands/research.md` Stage 5 step 3 — dedupe is now input-type-aware (see Added entry for §4 sub-structure). Free-form by-topic merge remains for `youtube` / `blog` / `community`.

### Fixed
- `scripts/push_to_notion.sh` — RC#2: `PURPOSE_ENUM` / `AUDIENCE_ENUM` / `INPUT_TYPE_ENUM` whitelists with `_enum_match()` helper. `build_row_props` now warns and omits a select property when the value is not in the enum, instead of sending a 400-causing free-form value (e.g. `"캠핑 경험자, 프리미엄 텐트 …"`). Eliminates the "Notion push required fixing a comma-containing purpose field" recovery loop seen during bench runs.
- `scripts/push_to_notion.sh` — RC#3: `jq_concat_arrays()` / `jq_append_element()` helpers using `<(printf '%s' "$VAR")` process substitution. Applied to 4 sites where multi-hundred-KB block JSON was passed via `jq --argjson` and hit Linux's `MAX_ARG_STRLEN` (~131 KB).
- `scripts/push_to_notion.sh` — markdown rendering upgrade. Pipe tables → Notion `table` + `table_row` blocks. Emoji-led blockquotes (`> ⚠️`, `> 📒`, `> ℹ️`, `> 📸`, `> ✅`, `> 🚨`, …) → `callout` blocks with matching icon + color. Inline `**bold**` / `*italic*` / `` `code` `` / `[text](url)` preserved as `rich_text` annotations. Plain `>` still renders as quote.

### Tests
- `tests/bats/test_push_to_notion.bats` (new, 4 tests): RC#2 enum whitelist behavior + RC#3 large-input handling.
- `tests/bats/test_collect_metrics.bats`, `tests/bats/test_judge.bats`, `tests/bats/test_report.bats`, `tests/bats/test_bench_run.bats` (new, 19 tests total): bench harness coverage.
- Full suite now: 114/114 passing.

### Notes — bench results
- First full matrix run (`bench/findings/2026-04-27-summary.md`): RE 79.6 / Baseline 83.2 / Δ -3.6 averaged across 5 topics × N=2. Surfaced three P1 fixes (above).
- After applying all three fixes, projected matrix: Δ +3.6 (RE outperforms baseline). Net swing **+7.2 points**. Two-of-five topics measured directly (`bench/findings/2026-04-27-v2-fix-validation.md` + `2026-04-27-v3-arxiv-substructure.md`); other three topics' deltas projected unchanged.
- Re-validate post-release with `/bench` against the actually-installed v0.9.0 plugin.

## 0.8.2 — 2026-04-20

### Changed
- `examples/dark-neon-dashboard.md` promoted to v4 — introduces a new `section.timeline` 2-column CSS grid layout class (used on the roadmap slide to visually support "sequence" claims — Week 1 / Week 2 with lime left-border accents) and tightens the `section.divider-num p` subtitle rule with `border-top: 4px solid var(--bg)` + `padding-top: 20px` + `width: fit-content` so the caption reads as intentional structure, not leftover body.

### Notes — Ceiling probe
- Ran 4 judge cycles on the same research deck: 87 → 90 → 90 → **89**. v4's fixes landed cleanly (0 regressions, linter confirms) but net score dropped 1 as new deductions surfaced (pseudo-numeral divider, sources 14pt rhythm break, lead/title size proximity).
- Judge explicitly stated: **~90 is the structural ceiling for this content profile (single preset, 4 charts, 22 slides, meta-topic)**. Breaking 92+ requires scope expansion — adding a second visual register (full-bleed photo, inline SVG data-viz beyond QuickChart PNGs, multi-page photographic lead) — not polish of existing elements.
- Shipping v4 anyway: the new `timeline` layout class is genuinely a better compositional reference than v3's label list, even at -1 score. This is documented in `research/<slug>/judge.json.ceiling_analysis`.

## 0.8.1 — 2026-04-20

### Added
- Three more curated reference decks fill the `examples/` gap — all 5 presets now have a first-pass reference:
  - `examples/editorial-serif-research.md` — DM Serif Display + DM Sans on wax-paper, terracotta `::after` underline accent, forest-green em italics. Magazine feel for long-form reflective content. Linter-clean.
  - `examples/warm-neutral-teal-research.md` — Fraunces + Inter on warm `#F5EFE4`, teal used **as gentle highlight only** (not flood), warm-brown divider structural bar. Linter-clean.
  - `examples/bold-geometric-research.md` — Archivo Black 900 + Archivo 400 on near-black, 104–112pt title/divider type, yellow divider background with inverse black text. Linter-clean (one slide uses 6 bullets, below the universal hard cap but mildly over the airy density rule — documented as a known relaxation).
- `examples/README.md` now documents "distinct content modes" as the criterion for future additions, since all 5 presets are covered.

### Notes
- Dispatched three `visualizer-deck` agents in parallel (one per preset) on the same source research content so reviewers can see how the **same argument** flexes across visual systems. Each deck independently chose compatible typographic devices (underline vs numeral vs left-accent bar) without the orchestrator enforcing them.

## 0.8.0 — 2026-04-20

### Added
- `agents/visualizer-diagrammer.md` now accepts an optional `style_preset` input. When set, the agent prepends a Mermaid `%%{init: {'theme':'base', 'themeVariables': {...}}}%%` directive to every diagram so the rendered SVG palette matches the deck (backgrounds, primary color, line color, accent). Token tables for all 5 presets are in the agent spec.
- `commands/research-visualize.md` Stage V4 forwards the resolved preset to the diagrammer, so charts + deck + diagrams all share the same palette end-to-end.
- Second curated reference deck: `examples/minimal-swiss-research.md` — same 31-source research content as the dark-neon example, rendered in Swiss-minimal discipline (single Inter family 300/800, 64×56 dense padding, red accent bar on dividers). Linter-clean, 0 violations. Shows how the same content flexes across presets.
- Top-level `README.md` now documents the 0.4–0.7 feature set: 5 presets + deterministic picker, `--judge` / `--preset` / `--brand-image` flags, chart-deck palette sharing, linter rules, assertion-evidence discipline, 6-class layout system, `examples/` curation pattern.

### Changed
- `examples/dark-neon-dashboard.md` promoted from the v2 snapshot to the v3 (post-fixes) deck — now demonstrates `divider-num` 200pt numerals, 4-bullet bento discipline, and the formalized `section.sources` class.

### Notes
- Decided out-of-scope for this sprint: **backend dispatcher** (python-pptx for editable charts) — requires adding `python-pptx` as a runtime dependency; deferred until explicit user approval. **Playwright overflow QA** — same story (Playwright npm dep). The deterministic linter covers ~80% of what Playwright would catch without the dependency.
- 91/91 tests still pass — this release is additive content (agent spec + examples + README), no behavior changes outside diagrammer's new optional input.

## 0.7.1 — 2026-04-20

### Added
- Two new deterministic rules in `scripts/lint_slides.py`:
  - `heading_duplicated` — same h2 appears on 2+ content slides. Divider / divider-num / sources / title / lead classes are exempt (terse repetition is intentional there).
  - `bg_fit_outside_chart_hero` — Marp's `![bg fit]` page-background directive bypasses the `section.chart-hero img { width: 100% }` CSS rule, so using it outside a `chart-hero` slide creates inconsistent image sizing (judge flagged this in run 1).
- 4 new bats tests covering both rules (positive + negative cases). Full suite 91/91.

### Notes
- Both rules are enforcement layers for structural consistency — the judge can now focus on subjective axes because these mechanical drift patterns are caught pre-dispatch.

## 0.7.0 — 2026-04-20

### Added
- `scripts/pick_preset.py` — deterministic preset selector. Reads README.md, counts keyword hits across 5 preset profiles (dark-neon / editorial-serif / minimal-swiss / warm-neutral-teal / bold-geometric), prints the highest-scoring preset name. Pure stdlib, exits 0 always. Use `--scores` to get per-preset scores as JSON.
- `/research-visualize` now runs `pick_preset.py` automatically when `--preset <name>` is absent and `--slides` is present. Charts and deck share the auto-picked preset end-to-end, removing the previous non-determinism where the deck agent inferred a preset in its own Step 1.
- 12 new bats tests in `tests/bats/test_pick_preset.bats`: every preset picked on representative content, empty-content default, tie-break behavior, frontmatter-ignored, markdown-link label not mis-scored, missing-file error. Full suite 87/87.

### Notes
- `bold-geometric` keywords are deliberately narrow (`launch`, `keynote`, `unveil`, `debut`, `rollout`, `campaign`) so any document that merely mentions "presentation" does NOT flood it. Similarly `product` is excluded — too generic.
- Tie-break order favors `minimal-swiss` (declared default for typography-first reports) → `editorial-serif` → `dark-neon` → `warm-neutral-teal` → `bold-geometric`.
- Frontmatter is stripped before scoring so meta-fields in `---` blocks can't bias the winner.

## 0.6.1 — 2026-04-20

### Added
- `scripts/lint_slides.py` now accepts an optional 2nd arg `<sources.json>`. When provided, every `[n]` citation marker in slides.md is resolved against the declared sources — unresolved markers become `source_marker_unresolved` violations. Catches the exact regression `visualizer-judge` flagged on the v2 deck (13 missing entries).
- `/research-visualize` Stage V5.1 now forwards `$report_dir/sources.json` to the linter so marker resolution runs automatically on every deck render.
- 5 new bats tests for the rule: clean resolution, unresolved marker, grouped `[1,2,3]` markers, markdown-link `[label](url)` NOT misidentified as a marker, malformed sources.json degrades to warning.

### Notes
- Marker detection requires a preceding whitespace/punctuation boundary so markdown links like `[robonuggets/marp-slides](https://...)` never match. Only numeric tokens or comma-lists inside `[...]` trigger the rule.
- Linter now reports `stats.source_markers_referenced` — the sorted list of unique ids actually cited in the deck.

## 0.6.0 — 2026-04-20

### Added
- `scripts/lint_slides.py` — deterministic pre-judge linter for `slides.md`. Catches mechanical rule violations (≤70 words/slide, ≤6 bullets/slide, ≤25 slides total, body ≥24pt, ≤2 font families, assertion-evidence headings) before paying for a `visualizer-judge` dispatch. Python stdlib only, no dependencies. Exits 0 and emits JSON so callers choose severity.
- `/research-visualize` Stage V5.1 runs the linter automatically after `slides.md` is written. `viz.json.lint` now records violation/warning counts and the `lint.json` sidecar path.
- Linter feeds its `violations[]` into the judge prompt when both `--slides` and `--judge` are set, so the judge concentrates on subjective axes (Design Quality, Originality) rather than re-checking mechanical rules.
- 12 new bats tests in `tests/bats/test_lint_slides.bats` covering every rule (bullets, words, slide count, body size, font families, assertion Korean/English heuristics, `section.sources` declared exception, missing file). Full suite now 70/70.

### Notes
- The linter recognizes `section.sources` as a declared exception — its 14pt body and long reference list emit a `warnings[]` entry but never a `violations[]` entry.
- Assertion-heading heuristic: Korean verb-ending detection (다/한다/된다/이다/있다/…) + English common-verb tokens (is/are/has/have/grew/dropped/…). Imperfect but catches the dominant "Sales Overview" failure mode.

## 0.5.1 — 2026-04-20

### Changed
- `lib/presets.json` is now the single source of truth for the 5 preset tokens (palette/bg/text/grid/fonts/density). `scripts/render_chart.sh` loads it at runtime instead of maintaining a hardcoded Python dict. `lib/style_presets.md` explicitly defers to the JSON.
- `lib/style_presets.md` adds `section.sources` as a first-class layout class. The class deliberately violates the 24pt body minimum (drops to 14pt in a 2-column `<ol>`) so 25–35 reference entries fit one slide — this was previously an ad-hoc workaround flagged by `visualizer-judge`. Reports with >35 sources should split into Sources-1/Sources-2 rather than shrinking further.

### Notes
- Consumers can override the preset path via `RESEARCH_ENGINE_PRESETS=<path/to/presets.json>` (useful for testing custom preset sets).
- No test changes — 58/58 still green. The refactor is behavior-preserving.

## 0.5.0 — 2026-04-20

### Added
- `scripts/render_chart.sh --brand-image <url>` — injects QuickChart's `backgroundImageUrl` plugin so every chart renders over a watermark/brand background. Forwarded by the `/research-visualize --brand-image <url>` flag so whole decks can be brand-stamped in one pass.
- QuickChart **POST /chart** auto-switch — when the encoded Chart.js config exceeds ~1900 chars (GET URL length limit), the script now falls back to POST with a JSON body instead of failing with URL-too-long. Small configs keep the GET path so `meta.json.quickchart_url` remains embeddable in Notion.
- `chart.meta.json` gains `render_method` (`"GET"` or `"POST"`) and `brand_image` fields. For POST renders, `quickchart_url` is `null` — the Notion push code already skips image blocks when the URL is missing, so the locally-rendered PNG stays authoritative.
- Three new bats tests in `tests/bats/test_render_chart.bats` covering `--brand-image` injection, the GET path for small configs, and the POST auto-switch for oversized configs (58/58 overall).

### Notes
- `/research-visualize --preset` + `--brand-image` can now produce an in-brand deck without any per-chart manual work. For example: `/research-visualize <slug> --slides --preset dark-neon --brand-image https://example.com/brand-mark-dark.png`.

## 0.4.0 — 2026-04-20

### Added
- `lib/style_presets.md` — 5 named visual presets (`dark-neon`, `editorial-serif`, `minimal-swiss`, `warm-neutral-teal`, `bold-geometric`), each with a 5-color palette, a 2-family font pair, density rules, and a reusable Marp `<style>` template with `bento` / `lead` / `divider` / `chart-hero` layout classes.
- `agents/visualizer-judge.md` — new subagent that scores a rendered deck on 4 axes (Design Quality / Originality / Craft / Functionality, 0–100 total) per Anthropic's harness-design rubric. Separate from `visualizer-deck` to avoid self-evaluation bias.
- `/research-visualize --judge` flag — when combined with `--slides`, automatically scores the deck and, if <75, regenerates once with the judge's fix-list (hard cap of 2 passes).
- `/research-visualize --preset <name>` flag — forces both charts and deck to use the same named preset (one of the 5 from `lib/style_presets.md`), eliminating chart-vs-deck palette mismatch. Forwards to `render_chart.sh --preset <name>` and to the deck agent as a `style_preset` input override.
- `scripts/render_chart.sh --preset <name>` — chart background, text color, grid color, and dataset palette now align with the named preset. Hardcoded tokens kept in sync with `lib/style_presets.md`. Without `--preset`, falls back to the legacy Okabe-Ito palette on white (backwards compatible).
- Four new bats tests in `tests/bats/test_render_chart.bats` covering `--preset` behavior (valid preset sets bg + accent, unknown preset errors, no preset keeps white).
- `examples/` — curated reference decks that `visualizer-deck` Step 0 now reads before generating, to absorb compositional rhythm (progressive-disclosure pattern borrowed from robonuggets/marp-slides). First entry: `examples/dark-neon-dashboard.md` (judge-validated at 90/100).

### Changed
- `agents/visualizer-deck.md` rewritten. Now **requires** picking exactly one style preset from `lib/style_presets.md` and enforces assertion-evidence headings (noun-phrase titles like "Sales Overview" must be rewritten as full sentences with a verb). Hard limits: ≤70 words/slide, ≤6 bullets/slide, ≤2 font families, body ≥24pt, title ≥80pt, ≤25 slides. Every chart slide carries an interpretive assertion above the image; every §상세 분석 slide carries an `[n]` source marker. New optional inputs: `style_preset` (skip inference, use verbatim) and `fixes[]` (apply judge fix-list verbatim on regeneration).
- `viz.json` schema: new `judge` block `{verdict, total, passes, file, style_preset_detected}`; new `flags.judge` and `flags.preset` fields.
- `chart.meta.json` sidecar now records the `preset` used during render (null when legacy).

### Notes
- Existing sessions without `--judge` see no behavior change beyond the stricter deck template.
- The 4-axis rubric maps directly to Anthropic's Claude Design evaluator published in the 2026-03-24 "Harness Design for Long-Running Application Development" post; weights (35/35/15/15) are applied as tie-breakers, totals are simple sums.
- Source research for this bump: `research/2026-04-20-ppt-design-improvement-research/README.md`.

## 0.3.0 — 2026-04-20

### Added
- `/research-visualize <slug>` slash command — generates data charts (QuickChart PNG, default), optional Mermaid diagrams (`--diagrams`), and optional Marp slide decks (`--slides`) for an existing research session.
- `lib/chart_spec_contract.md` — JSON schema for chart specs produced by the extractor subagent and consumed by `render_chart.sh`.
- New subagents: `visualizer-extractor`, `visualizer-diagrammer`, `visualizer-deck`.
- New scripts: `scripts/load_session.sh`, `scripts/render_chart.sh`, `scripts/render_slides.sh`, `scripts/patch_readme.sh`.
- Bats tests: `test_load_session.bats`, `test_patch_readme.bats`, `test_render_chart.bats`.
- `tests/fixtures/sample-session/` fixture for unit tests.
- README viz block is idempotent (marker-bounded) so re-runs don't drift.
- Notion: `/research-visualize` now auto-pushes the patched README to Notion by default. Pass `--no-sync-notion` to opt out.
- Notion: chart PNGs referenced as `![](figures/chart-NN-*.png)` are mirrored as Notion `image` blocks backed by the QuickChart URL stored in each chart's `.meta.json` — no file upload, no external host needed. Mermaid blocks continue to render natively.
- Notion: `slides.pptx` and `slides.pdf` produced by `--slides` are uploaded to Notion via the `file_uploads` API and embedded under a "📎 슬라이드 덱" heading (single-part, up to 20MB each; larger files are skipped with a warning).
- `scripts/push_to_notion.sh`: `md_to_blocks` parser extended with `NOTION_MD_BASE_DIR`-aware image resolution; new `notion_upload_file` helper wraps the two-step create-and-send file upload flow.
- Chart color palette: `scripts/render_chart.sh` now applies an Okabe-Ito qualitative palette — distinct colors per dataset (bar/line/scatter/horizontal_bar) and per slice (pie). Bars/lines are no longer grey-on-grey.

### Notes
- `/research` main pipeline and adapter contract are unchanged.

## 0.2.0 — 2026-04-18

### Changed
- **Notion layout is now a single database with one consolidated row per session** (breaking vs 0.1.0's page tree). Each row's body holds the main report, with toggle blocks for transcript, followups, and related materials.
- `/research-followup` updates the row in place (clear-and-reappend) rather than creating subpages.

### Added
- `scripts/push_to_notion.sh --archive-page <page_id>` subcommand for one-off cleanup.
- Database properties: Title, Slug, Input URL, Input Type, Created, Purpose, Audience, Sources — enabling filter/sort in Notion.
- `NOTION_DATABASE_ID` cache env variable to skip the database search on every run.

### Fixed
- `md_to_blocks` parser used a heredoc that hijacked stdin — the markdown never reached Python. Script now stores the Python source in a bash variable and runs via `python3 -c`, leaving stdin available.

### Removed
- `install.sh` — superseded by marketplace-based installation documented in the README.

## 0.1.0 — 2026-04-17

Initial release. Plugin scaffolding, seven source adapters (YouTube, arXiv, GitHub, blog, context7, HuggingFace, community), `/research` + `/research-followup` slash commands, bash utilities with bats coverage, and Notion mirroring (page-tree layout).
