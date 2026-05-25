# adapter failure modes

## context7 MCP 월간 quota 고갈이 라이브러리 리서치 세션을 반복적으로 무력화한다

3개 세션 모두 'Context7 MCP monthly quota exceeded' 로 resolve-library-id 호출이 전부 실패했고, 그 결과 Agent SDK·Claude Code 플러그인·MCP 같은 핵심 라이브러리 문서를 inline citation 으로 보강하지 못한 채 블로그·GitHub raw 만으로 보고서를 합성해야 했다. 이는 단일 세션의 일시 오류가 아니라 한 달치 quota 가 모두 소진된 구조적 한계라서, /research 가 매번 context7 부터 호출하는 한 매월 말마다 같은 실패가 반복된다.

**Evidence:** 2026-05-22-bench-agent-sdk-claude-opus, 2026-05-23-anthropic-claude-code-harness-masterclass, 2026-05-23-claude-managed-agents-memory-dreaming

**Action:** context7 어댑터에 quota-aware 백오프와 'docs 사이트 직접 fetch (docs.claude.com, openai.github.io 등) 로 자동 fallback' 경로를 추가하고, manifest 단계에서 이번 달 quota 잔량을 미리 체크해 0이면 어댑터 자체를 스킵하도록 한다.

## Anthropic 내부/서버사이드 기능 (managed-agents, dreaming) 은 공개 repo·blog 가 없어 거의 항상 404 로 빠진다

memory-dreaming 세션 한 곳에서만 anthropics/managed-agents (404), anthropic.com/news/{claude-managed-agents,memory-dreaming} 4개 경로 (404), anthropic-sdk-typescript 의 dreaming endpoint 미존재 등 5건의 '있다고 가정했지만 공개되지 않은' 리소스 fetch 가 연쇄적으로 깨졌고, harness-masterclass 도 같은 패턴으로 Claude Code 내부 구조 docs 가 비공개라 context7 fallback 으로 강제 우회했다. /research 가 'anthropics/{topic}' 류 repo 존재를 낙관적으로 가정하는 패턴이 반복 손실의 원인이다.

**Evidence:** 2026-05-23-claude-managed-agents-memory-dreaming, 2026-05-23-anthropic-claude-code-harness-masterclass

**Action:** github 어댑터에 'anthropics/* 또는 openai/* 추정 repo 는 fetch 전에 HEAD 로 존재 확인 → 실패 시 platform.claude.com / code.claude.com / engineering 블로그 카테고리만 우선 탐색' 라우팅을 넣고, 비공개 추정 토픽(메모리/dreaming/managed-agents)은 source-of-truth 화이트리스트로 platform.claude.com docs 만 사용하도록 한다.

## 커뮤니티 어댑터 (Reddit / HN / 한국어 블로그) 가 throttle·차단으로 자주 빈손으로 돌아온다

local-fine-tuning 세션은 r/LocalLLaMA 스레드를 찾지 못하고 startupfortune.com 이 403 으로 차단됐고, bench-agent-sdk-opus 는 HN 스레드 3건이 동시에 429 (rate limit) 를 맞고 Reddit/Lobsters 검색도 빈 결과였다. 의견·실측 데이터의 일차 출처가 커뮤니티인데 이 어댑터 신뢰도가 낮으면 비교형 세션의 평가 깊이가 떨어진다.

**Evidence:** 2026-05-13-why-you-should-bet-on-local-ai-fine-tuning, 2026-05-22-bench-agent-sdk-claude-opus

**Action:** community 어댑터에 (a) HN Algolia API 로 우선 조회 후 실패 시 firecrawl, (b) Reddit 은 old.reddit.com + JSON 엔드포인트 직접 호출, (c) 403/429 시 캐시된 archive.org 스냅샷으로 fallback — 3단계 retry 체인을 도입한다.

