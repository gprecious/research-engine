---
title: "Let's build GPT: from scratch, in code, spelled out. — 분석"
slug: "2026-05-25-lets-build-gpt-from-scratch-cand"
created: "2026-05-25"
input: "https://www.youtube.com/watch?v=kCc8FmEb1nY"
input_type: "youtube"
intent_mode: "assumed"
---

## 분석 목적 (Intent)

**추정(assumed)**
- 용도: Andrej Karpathy 의 'Let's build GPT from scratch' 강의를 분석해 구현 단계·핵심 메커니즘·한계를 구조화
- 집중: implementation (bigram → self-attention → multi-head → blocks → scaling)
- 배경지식: intermediate

**엔진 해석**
시청자가 nanoGPT 수준의 decoder-only Transformer 를 코드 단위로 재현하도록, 강의가 밟는 구현 단계와 각 단계의 손실 변화·설계 결정을 타임코드 인용과 함께 추적한다.

## 요약 (TL;DR)

이 116분 강의는 ChatGPT 의 기반 Transformer 를 production 재현 대신 tiny Shakespeare(약 1MB) 위 character-level 모델로 처음부터 구현한다 [1] (00:05:30). bigram 베이스라인(초기 손실 4.87, 이론치 4.17)에서 출발해 self-attention 의 핵심인 query/key/value 메커니즘과 value 가중 집계를 도입하고 [1] (00:22:11, 01:02:00), 1/√(head_size) 스케일링·multi-head·feed-forward·residual·LayerNorm 을 차례로 쌓아 검증 손실을 단계적으로 낮춘다 [1] (01:16:56, 01:21:59, 01:26:48). 최종 스케일업(6층·n_embd 384·head 6·block 256·dropout 0.2)으로 A100 15분 학습 시 검증 손실 1.48 을 얻으며, 우리가 만든 것은 triangular mask 기반 decoder-only Transformer 다 [1] (01:37:49, 01:46:22). 마지막으로 ChatGPT 는 대규모 pretraining(GPT-3: 1750억 파라미터·3000억 토큰) 후 SFT→reward model→PPO(RLHF) 정렬을 거치며, 본 강의는 pretraining 단계만 다룬다고 정리한다 [1] (01:48:53).

## 핵심 포인트

- GPT = generatively pre-trained Transformer 이며 핵심은 2017 'Attention Is All You Need' 아키텍처다 [1] (00:03:01).
- 강의는 tiny Shakespeare(≈1MB) 위 character-level 모델을 구현하며 완성본은 각 ~300줄짜리 nanoGPT 두 파일이다 [1] (00:05:30).
- 토크나이저는 어휘 크기 ↔ 시퀀스 길이 트레이드오프: character-level vocab 65 vs tiktoken BPE vocab ≈50,000 [1] (00:09:28).
- block_size 청크 하나에 컨텍스트 1~block_size 의 모든 예제가 packed 되어 학습된다 [1] (00:14:27).
- bigram 베이스라인은 cross-entropy(=NLL)로 측정하며 초기 손실 4.87(이론치 4.17) [1] (00:22:11).
- self-attention 핵심: query("찾는 것")·key("가진 것") 내적으로 affinity 를 만들고 raw x 가 아닌 value 를 가중 집계한다 [1] (01:02:00).
- 1/√(head_size) 스케일링은 weight 분산을 1로 유지해 softmax 가 초기에 one-hot 으로 쏠리는 것을 막는다 [1] (01:16:56).
- multi-head 는 여러 head 병렬+채널 concat(group conv 유사)으로 손실 2.4→2.28 [1] (01:21:59).
- residual('gradient super highway', 손실 2.08) + LayerNorm(pre-norm, 2.06) 이 깊은 망 최적화를 돕는다 [1] (01:26:48).
- 스케일업 → A100 15분 → 검증 손실 1.48, 결과물은 decoder-only Transformer [1] (01:37:49, 01:46:22).
- ChatGPT 는 pretraining(GPT-3 1750억·3000억 토큰) 후 SFT→reward model→PPO(RLHF) 정렬, nanoGPT 는 전자만 다룬다 [1] (01:48:53).

## 상세 분석

### 데이터·토크나이즈·베이스라인

강의는 ChatGPT 재현이 아니라 tiny Shakespeare(약 1MB, 100만 자, 고유 문자 65개) 위에서 character-level 언어 모델을 처음부터 작성하며, 완성 코드는 model.py·train.py 각 약 300줄짜리 nanoGPT 다 [1] (00:05:30). 토크나이저는 어휘 크기와 시퀀스 길이의 트레이드오프로, character-level(vocab 65)은 단순하지만 시퀀스가 길고 실무용 subword(SentencePiece·tiktoken BPE, vocab ≈50,000)는 시퀀스를 압축한다 [1] (00:09:28). 학습은 전체 텍스트 대신 block_size 청크를 무작위 샘플링하며, 길이 9 청크에 컨텍스트 1~8 예제 8개가 packed 되어 모델이 모든 길이의 컨텍스트에 익숙해진다 [1] (00:14:27). 베이스라인 bigram 모델은 vocab×vocab 임베딩 테이블로 logits 를 내고 cross-entropy 로 손실을 재며((B,T,C)→(B*T,C) reshape 필요), 초기 손실 4.87 로 이론치 4.17 대비 약간 편향돼 있다 [1] (00:22:11).

### self-attention 의 메커니즘

self-attention 의 핵심은 모든 토큰이 query("무엇을 찾는가")와 key("무엇을 담는가")를 방출하고 그 내적으로 data-dependent affinity 를 계산하는 것이다 [1] (01:02:00). 집계 대상은 raw 토큰 x 가 아니라 value 벡터로, x 가 토큰의 사적 정보라면 value 는 "내가 흥미로우면 전달할 것" 에 해당한다 [1] (01:02:00). 'scaled' attention 이 1/√(head_size)로 나누는 이유는 분산 제어로, 단위 분산 입력이면 weight 분산이 head_size 규모로 커지고 그 큰 값이 softmax 를 거치면 one-hot 으로 수렴해 한 노드 정보만 집계하게 되기 때문이다 [1] (01:16:56).

### 블록 쌓기: multi-head · FFN · residual · LayerNorm

multi-head attention 은 여러 self-attention head 를 병렬 실행해 결과를 채널 차원으로 concat 하는 것으로(group convolution 유사), 독립적 통신 채널을 늘려 검증 손실이 2.4→2.28 로 개선됐다 [1] (01:21:59). Transformer 블록은 통신(multi-head self-attention)과 계산(per-token feed-forward MLP)을 번갈아 쌓는다 [1] (01:21:59). 깊은 망 최적화를 돕는 두 기법은 residual connection(덧셈 노드가 그래디언트를 양쪽에 동등 분배하는 'gradient super highway', 2015 ResNet 유래)과 LayerNorm 으로, 강의는 원논문과 달리 변환 '이전' 에 norm 을 두는 pre-norm 을 쓴다(residual 후 2.08, LayerNorm 후 2.06) [1] (01:26:48).

### 스케일업과 ChatGPT 와의 거리

스케일업(n_embd 384, head 6, layer 6, block_size 256, batch 64, dropout 0.2)으로 A100 에서 약 15분 학습하니 검증 손실이 2.07→1.48 로 떨어졌고, dropout(2014)은 일부 뉴런을 꺼 sub-network 앙상블을 학습하는 정규화다 [1] (01:37:49). 우리가 구현한 것은 triangular mask 로 미래를 가린 decoder-only Transformer 로, encoder·cross-attention 이 있는 원논문 번역 모델과 다르며 nanoGPT 의 model.py 는 multi-head 를 4차원 텐서로 batched 처리해 동일 수학을 효율화한다 [1] (01:46:22). ChatGPT 는 (1) 인터넷 대량 텍스트 pretraining(GPT-3 1750억 파라미터·3000억 토큰, 강의의 1000만 파라미터·약 30만 토큰 대비 약 100만 배) 으로 'document completer' 를 만들고 (2) SFT→reward model→PPO(RLHF) 로 정렬하며, nanoGPT 는 (1)단계만 다룬다 [1] (01:48:53).

## 챕터별 요약

### 도입 + 데이터 로딩 (00:00:00 – 00:14:27)

ChatGPT 가 확률적 언어 모델임을 보이고 그 핵심이 2017 'Attention Is All You Need' 의 Transformer 임을 소개한다. tiny Shakespeare(1MB, 100만 자)를 토이 데이터셋으로 잡고 character-level 모델을 목표한다. 어휘 65개와 encode/decode 함수로 토크나이즈하며 실무 subword 토크나이저(SentencePiece·tiktoken)와 대조하고, 90/10 train/val 로 분할한다.

### 데이터 로더와 bigram 베이스라인 (00:14:27 – 00:25:33)

block_size 청크를 무작위 샘플링하고 batch 차원을 더해 (B,T) 텐서 하나에 다수 독립 예제를 담는다. vocab×vocab 임베딩으로 bigram 모델을 구현하고 cross-entropy 를 위해 reshape 하며 초기 손실 4.87 을 얻는다. softmax+multinomial 로 생성하고 AdamW 로 학습한 뒤 코드를 스크립트로 정리한다.

### self-attention 으로 가는 길 (00:42:13 – 01:02:00)

과거 컨텍스트 평균을 for 루프(v1)로 보이고 하삼각 행렬 곱(v2)으로 효율화한 뒤 softmax 마스킹(v3)으로 정규화한다. 토큰 임베딩에 position embedding 을 더해 위치 정보를 주입한다. 이로써 핵심 single-head self-attention(v4) 구현의 토대를 만든다.

### 핵심: single-head self-attention 과 6가지 노트 (01:02:00 – 01:19:11)

각 토큰이 query/key/value 를 방출하고 query·key 내적으로 affinity 를 만들어 value 를 가중 집계하는 핵심 메커니즘을 구현한다. attention 을 방향성 그래프 통신으로 재해석하고 위치 무개념(집합처럼 동작)·batch 간 비통신·decoder/encoder·self/cross 구분을 짚는다. 1/√(head_size) 스케일링이 softmax 과수렴을 막는 이유를 설명한다.

### 블록 조립: multi-head + feed-forward + residual + LayerNorm (01:19:11 – 01:37:49)

단일 블록 삽입 후 multi-head(병렬+concat)로 손실을 2.28 까지 낮추고 토큰별 feed-forward(MLP)를 더한다. 블록을 쌓자 생긴 최적화 문제를 residual connection(2.08)과 pre-norm LayerNorm(2.06)으로 푼다. 이 시점에서 decoder-only Transformer 부품이 모두 갖춰진다.

### decoder-only · nanoGPT · ChatGPT 결론 (01:37:49 – 01:56:20)

dropout·스케일업으로 검증 손실 1.48 을 얻고, 구현물이 triangular mask 기반 decoder-only 임을 설명한다(원논문 encoder-decoder 는 번역용). nanoGPT 의 batched causal self-attention 효율화를 훑고, ChatGPT 의 pretraining(GPT-3 1750억·3000억 토큰) vs SFT/reward/PPO(RLHF) 정렬 2단계를 설명하며 nanoGPT 가 전자만 다룸을 정리한다.

## 타임코드 인용

- **[00:03:01]** "GPT is short for generatively pre-trained Transformer ... it comes from this paper in 2017" [1]
- **[01:02:00]** "every single token at each position will emit two vectors it will emit a query and it will emit a key" [1]
- **[01:48:53]** "they run PPO which is a form of policy gradient reinforcement learning Optimizer ... so that the answers ... are expected to score a high reward according to the reward model" [1]

## 연관 자료

### 논문
- [Attention Is All You Need](https://arxiv.org/abs/1706.03762) — Transformer 원논문(2017), 강의 아키텍처의 출처.
- [Language Models are Few-Shot Learners (GPT-3)](https://arxiv.org/abs/2005.14165) — 175B·300B 토큰 pretraining 스케일 비교 근거.
- [Deep Residual Learning (ResNet)](https://arxiv.org/abs/1512.03385) — residual connection 출처.
- [Layer Normalization](https://arxiv.org/abs/1607.06450) — LayerNorm 출처.
- [Dropout (2014)](https://jmlr.org/papers/v15/srivastava14a.html) — dropout 정규화 출처.

### 레포
- [karpathy/nanoGPT](https://github.com/karpathy/nanoGPT) — 강의 완성본(model.py + train.py).
- [karpathy/ng-video-lecture](https://github.com/karpathy/ng-video-lecture) — 강의 중 작성한 from-scratch 코드.
- [openai/tiktoken](https://github.com/openai/tiktoken) — GPT BPE 토크나이저(vocab ~50k).

## 한계 / 미해결

- 강의 모델은 character-level·약 1000만 파라미터의 toy 규모로 GPT-3(1750억) 대비 약 100만 배 작아 생성물은 Shakespeare 풍이지만 무의미하다 [1] (01:37:49).
- ChatGPT 를 만드는 정렬 단계(SFT·reward model·PPO/RLHF)는 개념적으로만 언급되고 구현되지 않는다 [1] (01:48:53).
- 토크나이즈는 character-level 만 다루며 BPE 등 실전 subword 토크나이저 학습은 후속 강의로 미뤄진다 [1] (00:09:28).
- weight initialization 의 세부는 가볍게만 다뤄진다.

## Sources

1. **Let's build GPT: from scratch, in code, spelled out.** — https://www.youtube.com/watch?v=kCc8FmEb1nY (adapter: `youtube`, fetched: 2026-05-25)
