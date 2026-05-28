# recurring intents

## LLM 내부 동작 원리 학습(트랜스포머·GPT-from-scratch)

7개 중 4개(중복 제거 시 2개 영상)가 Karpathy의 GPT-from-scratch와 3Blue1Brown의 Transformer 설명으로, attention·임베딩·multi-head·FFN·residual 같은 동일 메커니즘을 implementation/concepts 양면에서 반복 학습한다. 사용자의 LLM 내부 구조에 대한 지속적·집중적 관심을 보여준다.

**Evidence:** 2026-05-25-lets-build-gpt-from-scratch-in-code-spel, 2026-05-25-transformers-the-tech-behind-llms-deep-l

**Action:** LLM-internals 토픽에 대한 전용 research preset(논문 prior-art 자동 첨부 + 코드/시각자료 균형)을 만들고, 이미 분석된 Karpathy/3B1B 세션을 memory.json similar_sessions로 자동 링크해 중복 분석 대신 증분 심화를 유도할 것.

## YouTube 영상 → 개념·메커니즘 구조화 deep-dive

거의 모든 세션이 단일 YouTube 영상을 입력으로 '핵심 주장·메커니즘·한계를 챕터별로 구조화'하는 동일한 intent shape를 따르며, blog·github로 영상 주장을 보강하는 패턴이 반복된다. 도메인은 달라도(AI 코딩 스킬, 아키텍처) 출력 골격이 동형이다.

**Evidence:** 2026-05-25-grill-skills-9-mistakes, 2026-05-25-the-modular-monolith-scale-without-micro

**Action:** YouTube 입력 시 '영상=주장 골격 / blog=정련판 / repo=코드 강제' 3-소스 보강 패턴을 기본 워크플로 템플릿으로 승격하고, 영상 업로드 당일이면 whisper 로컬 전사 fallback을 자동 발동하도록 youtube 어댑터에 명문화할 것.

