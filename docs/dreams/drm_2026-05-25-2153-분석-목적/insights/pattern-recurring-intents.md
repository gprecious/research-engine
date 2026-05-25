# recurring intents

## AI Agent SDK · 하네스 비교/선택 (사용자의 #1 관심사)

40개 세션 중 10개 (25%) 가 Anthropic Claude Agent SDK / OpenAI Agents SDK / Mastra / Vercel AI SDK 4종 비교, Claude Code 하네스 6-layer 분해, /handoff·/compact·dreaming 같은 컨텍스트 관리 메커니즘 학습, gstack/Compound Engineering/Karpathy 식 하네스 패턴 흡수 — 모두 '어떤 agent 프레임워크/하네스를 본인 프로젝트에 가져올까' 라는 동일한 의사결정 문제를 다른 각도에서 푸는 시리즈다.

**Evidence:** 2026-05-22-bench-agent-sdk-claude-haiku, 2026-05-22-bench-agent-sdk-claude-opus, 2026-05-22-bench-agent-sdk-claude-sonnet, 2026-05-22-bench-agent-sdk-codex-default, 2026-05-22-bench-agent-sdk-codex-high, 2026-05-22-handoff-is-my-new-favourite-skill, 2026-05-23-anthropic-claude-code-harness-masterclass, 2026-05-23-claude-managed-agents-memory-dreaming, 2026-05-23-my-full-claude-cowork-setup-steal-my-wor, 2026-05-24-compound-engineering-vs-gstack-vs-karpat

**Action:** research-engine 안에 'agent-sdk-comparison' 같은 영구 프로파일을 두고 이 클러스터 세션이 새로 생길 때마다 기존 비교표 (mastra/vercel/openai/anthropic) 에 자동 증분 업데이트 → /research 호출 시 'agent SDK' 키워드 감지하면 그 프로파일을 prior-knowledge 로 주입한다.

## 코드베이스 매핑·인덱싱 도구 채택 검증

Graphify (knowledge graph + multi-agent LLM), Understand-Anything (static analysis + LLM), grill-with-docs (DDD ubiquitous-language) 세 세션 모두 '대규모 코드베이스를 LLM 이 효율적으로 탐색하게 하는 도구' 의 도입 가치를 비교 검증한다. 핵심 질문은 항상 동일하다 — '토큰 비용 vs 정확도 트레이드오프, 기존 grep/RAG 대비 우위, 본인 워크플로에 통합 비용'.

**Evidence:** 2026-05-19-graphify-solves-claudes-biggest-limitati, 2026-05-22-this-ai-tool-maps-any-codebase-before-yo, 2026-05-14-grill-with-docs-replaces-grill-me-matt-p

**Action:** 이 클러스터 세션이 다시 들어오면 자동으로 yamadashy/repomix · mufeedvh/code2prompt · safishamsi/graphify · Lum1104/Understand-Anything 4개 reference repo 를 '비교 대상 prior art' 로 주입하고, 토큰/시간 벤치 표를 README 의 표준 섹션으로 강제한다.

## Self-improving agent / RSI 루프 설계

Ralph Loop (Codex /goal), Hermes 기반 trading agent, Memory/Dreaming, Compound Engineering 모두 'prompt → outcome → 새로운 prompt 로 영구화' 라는 동일한 self-improvement 루프 구조를 다른 도메인에서 재발견하는 시리즈다. 사용자는 이 패턴을 본인 research-engine / 하네스 안에 이식할 단서를 모으는 중.

**Evidence:** 2026-05-15-codex-goal-ralph-loop-mastercourse, 2026-05-23-self-improving-ai-trading-agent, 2026-05-23-claude-managed-agents-memory-dreaming, 2026-05-24-compound-engineering-vs-gstack-vs-karpat

**Action:** /dream 자체가 self-improvement 루프의 한 단계 (insight → action recommendation) 이므로, 이 클러스터의 dream output 은 자동으로 research-engine 의 CLAUDE.md 또는 SKILL.md 에 'learned pattern' 로 append 하는 hook 을 추가한다.

## research-engine 자체 적용 (메타 학습)

이 4개 세션은 intent.purpose 에 명시적으로 'research-engine 에 어떻게 적용/이식할지' 또는 'research-engine skill 검증' 이 들어가 있다 — 즉 사용자는 다른 사람의 자료를 읽으면서 동시에 본인 research-engine 의 진화 단서를 추출하고 있다. 이는 dream output 의 1차 소비자가 사용자 자신임을 강하게 시사한다.

**Evidence:** 2026-05-22-handoff-is-my-new-favourite-skill, 2026-05-23-claude-managed-agents-memory-dreaming, 2026-05-23-anthropic-claude-code-harness-masterclass, 2026-05-22-codex-claude-validation-arxiv-2402-10171

**Action:** /dream 출력에 'research-engine applicability' 전용 섹션을 추가해서, 각 인사이트가 research-engine 의 어떤 컴포넌트 (adapter / harness / skill / spec) 에 매핑되는지 dispatch agent 가 강제 명시하게 한다.

## GPT-2 / nanoGPT 계열 ML 기본기 + long-context 데이터 엔지니어링

self-attention 입문, nanoGPT 두 번 (다른 슬러그, 같은 repo), Long-Context Data Engineering 논문 두 번 (Codex 검증 1회 + 본 분석 1회), TurboQuant KV quantization — 모두 GPT-2 ~ long-context 시대 transformer 의 코어 작동 원리를 다시 짚어보는 ML 펀더멘털 클러스터다. nanoGPT 가 한 주 안에 두 번 슬러그 만들어진 건 dedupe 가 누락된 신호이기도 하다.

**Evidence:** 2026-05-13-self-attention-explained-how-transformer, 2026-05-21-nanogpt, 2026-05-22-nanogpt, 2026-05-22-data-engineering-for-scaling-language-mo, 2026-05-22-codex-claude-validation-arxiv-2402-10171, 2026-05-24-turboquant-kv-cache-quantization

**Action:** manifest 빌더에 '같은 input_url 또는 github repo 가 7일 안에 2번 이상 들어오면 새 세션 대신 기존 세션 followup 으로 라우팅' 룰을 넣고, 이 클러스터 토픽에는 transformer-fundamentals 프리셋 (Attention Is All You Need, Flash Attention, RoPE) 을 기본 prior-art 로 주입한다.

