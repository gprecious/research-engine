# topic coverage gaps

## Anthropic 비공개 기능 (managed-agents, memory, dreaming) 의 1차 출처 부재

memory-dreaming 세션은 6건의 fetch 실패 (context7 quota + github 404 + blog 404 + arxiv HTML 404) 끝에 platform.claude.com docs 만 신뢰 가능한 1차 출처로 남았고, harness-masterclass 세션도 동일 이유로 sources_count 가 3개에 그쳤다. 사용자가 이 토픽에 반복 진입할수록 어댑터는 같은 404 를 다시 부르며 시간을 낭비한다.

**Evidence:** 2026-05-23-claude-managed-agents-memory-dreaming, 2026-05-23-anthropic-claude-code-harness-masterclass

**Action:** manifest 에 'Anthropic-internal-only' 토픽 태그를 두고, 이 태그가 붙은 세션은 처음부터 platform.claude.com / code.claude.com / docs.claude.com 3개 도메인만 spider 하도록 적응형 라우팅을 추가한다.

## 한국어 커뮤니티/포럼 1차 의견 출처가 어댑터에 없음

한국 시장 관련 4개 세션은 namu.wiki, platum.kr, bizhankook, byline, maily.so 등 한국어 블로그·위키에 의존했지만 r/LocalLLaMA / HN 같은 영어권 커뮤니티 어댑터는 한국 토픽에 무력하다. 결과적으로 '한국 운영자들이 실제로 어떻게 받아들였는지' 같은 sentiment 데이터가 누락된다.

**Evidence:** 2026-05-18-openub-sales-data-acquisition, 2026-05-18-everland-no-planit-tuesday, 2026-05-23-yoonjadong-ai-native-erp-builder-josh, 2026-05-23-ai-offer-sell-hours-tomorrow

**Action:** community 어댑터에 한국어 소스 패널 (theqoo, fmkorea, 클리앙, ppomppu, naver cafe 검색, threads.com/@*kr) 을 추가하고, intent 가 한국어로 작성되거나 한국 도메인 (.kr) 이 input 에 등장하면 자동 활성화한다.

## YouTube 어댑터 메타데이터 스키마 불일치 (실패는 아니지만 다운스트림 분석을 막음)

30개 youtube 세션 중 fetch 실패는 0건이지만 meta 키가 제각각이다 — caption_lang vs language, duration_sec vs duration_seconds vs duration, view_count 유무 등. 그래서 /dream 같은 cross-session 분석에서 'Korean vs English video 비율' 같은 단순 집계조차 어렵다.

**Evidence:** 2026-05-12-7-new-use-cases-of-claudes-live-artifact, 2026-05-15-codex-goal-ralph-loop-mastercourse, 2026-05-23-yoonjadong-ai-native-erp-builder-josh, 2026-05-24-turboquant-kv-cache-quantization

**Action:** youtube 어댑터에 canonical meta 스키마 (video_id, caption_lang, caption_source, duration_sec, channel, upload_date, view_count) 를 강제하고, 누락된 키는 빈 string/null 로라도 항상 포함하도록 schema validator 를 붙인다.

