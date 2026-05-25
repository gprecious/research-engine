---
title: "Let's build GPT: from scratch, in code, spelled out. — 분석"
slug: "2026-05-25-lets-build-gpt-from-scratch-in-code-spel"
created: "2026-05-25"
input: "https://www.youtube.com/watch?v=kCc8FmEb1nY"
input_type: "youtube"
intent_mode: "assumed"
---

## 분석 목적 (Intent)

**추정(assumed)**
- 용도: Andrej Karpathy 의 'Let's build GPT from scratch' 강의를 분석해 구현 단계·핵심 메커니즘·한계를 구조화
- 집중: implementation (bigram → self-attention → multi-head → blocks → scaling 진행)
- 배경지식: intermediate

**엔진 해석**
시청자가 nanoGPT 수준의 decoder-only Transformer 를 코드 단위로 재현할 수 있도록, 강의가 밟는 구현 단계와 각 단계의 손실 변화·설계 결정을 타임코드 인용과 함께 추적한다.

## 요약 (TL;DR)

이 116분 강의는 ChatGPT 의 기반인 Transformer 를 production 재현이 아니라 tiny Shakespeare(약 1MB) 위 character-level 모델로 처음부터 구현한다 [1] (5:30). bigram 베이스라인(손실 ≈4.87)에서 출발해 self-attention 의 핵심인 "행렬곱 = 인과적 가중 집계" 트릭과 query/key/value 메커니즘을 도입하고 [1] (49:30, 64:30), 1/√(head_size) 스케일링·multi-head·feed-forward·residual·layer norm 을 차례로 쌓아 검증 손실을 단계적으로 낮춘다 [1] (77:30, 82:30, 90:30). 최종 스케일업(6층·n_embd 384·head 6·block 256)으로 A100 15분 학습 시 검증 손실 1.48 을 얻으며, 완성본은 nanoGPT 저장소와 동일 구조다 [1] (100:30, 106:22). 마지막으로 ChatGPT 는 대규모 pretraining(GPT-3: 1750억 파라미터·3000억 토큰) 으로 문서 완성기를 만든 뒤 SFT→보상모델→PPO(RLHF) 정렬을 거치며, 본 강의는 pretraining 단계만 다룬다고 정리한다 [1] (110:30).

## 핵심 포인트

- GPT = Generatively Pretrained Transformer 이며, 핵심 Transformer 는 2017 'Attention Is All You Need' 아키텍처가 거의 그대로 확산된 것이다 [1] (3:30).
- 강의는 tiny Shakespeare(≈1MB, 100만 문자) 위 character-level 모델을 구현하며 완성본은 각 ~300줄짜리 nanoGPT 두 파일이다 [1] (5:30).
- 토크나이저는 코드북 크기 ↔ 시퀀스 길이 트레이드오프: character-level vocab 65 vs tiktoken BPE vocab ≈50,257 [1] (11:00).
- bigram 베이스라인은 cross-entropy(=NLL)로 측정하며 vocab 65 기준 기대 손실 ≈4.17, 실측 4.87 [1] (30:00).
- self-attention 효율 구현의 핵심은 하삼각(tril) 정규화 행렬 곱으로 과거 평균을 단일 행렬곱으로 얻는 트릭이다 [1] (49:30).
- query("찾는 것")·key("가진 것") 내적으로 data-dependent affinity 를 만들고 value 를 가중 집계한다 [1] (64:30).
- 1/√(head_size) 스케일링은 weight 분산을 1로 유지해 softmax 가 초기에 one-hot 으로 뾰족해지는 것을 막는다 [1] (77:30).
- residual connection 은 '그래디언트 슈퍼하이웨이' 를, layer norm(pre-norm) 은 토큰별 feature 정규화를 제공한다 [1] (90:30).
- 스케일업(블록 6·n_embd 384·head 6·block 256·dropout 0.2) → A100 15분 → 검증 손실 1.48 [1] (100:30).
- ChatGPT 는 pretraining(GPT-3 1750억 파라미터·3000억 토큰) 후 RLHF 정렬로 문서완성기→질의응답기로 전환되며, nanoGPT 는 전자만 다룬다 [1] (110:30).

## 상세 분석

### 데이터·토크나이즈·베이스라인

강의는 ChatGPT 재현이 아니라 tiny Shakespeare(약 1MB, 고유 문자 65개) 위에서 character-level 언어 모델을 처음부터 구현하며, 완성 코드는 model.py·train.py 각 약 300줄짜리 nanoGPT 로 공개돼 있다 [1] (5:30). 토크나이저는 코드북 크기와 시퀀스 길이의 트레이드오프로, character-level(vocab 65)은 단순하지만 시퀀스가 길고 GPT 의 tiktoken BPE 는 vocab ≈50,257 로 'hi there' 를 정수 3개로 압축한다 [1] (11:00). 베이스라인 bigram 모델은 vocab×vocab 임베딩 테이블로 logits 를 내고 cross-entropy(=negative log likelihood)로 손실을 재며, 무작위 초기화 기대 손실 ≈4.17 대비 실측 4.87 로 초기 예측이 약간 편향돼 있음을 보여준다 [1] (30:00).

### self-attention 의 메커니즘

self-attention 효율 구현은 '행렬곱 = 가중 집계' 트릭에 기반한다: 하삼각(torch.tril) 행렬을 행 합이 1이 되도록 정규화한 뒤 곱하면 과거 토큰들의 인과적 평균을 단일 행렬곱으로 얻어 for-loop 평균을 대체한다 [1] (49:30). 핵심은 각 토큰이 query("내가 찾는 것")와 key("내가 가진 것")를 방출하고 둘의 내적으로 data-dependent affinity 를 만든 뒤, 원본 X 가 아니라 value 벡터를 미래 마스킹+softmax 후 가중 집계해 head 출력을 내는 것이다 [1] (64:30). 'scaled' attention 이 1/√(head_size)로 나누는 이유는 분산 제어로, 단위 분산 Q·K 를 그냥 내적하면 weight 분산이 head_size 만큼 커져 softmax 가 one-hot 처럼 뾰족해지기 때문이다 [1] (77:30).

### 블록 쌓기: multi-head · FFN · residual · layer norm

multi-head attention 은 여러 head 를 병렬로 돌려 출력을 채널 차원으로 concat 하는 것으로(8차원 head 4개 → 32), 독립적 통신 채널을 늘려 검증 손실이 2.4→2.28 로 개선됐다 [1] (82:30). Transformer 블록은 통신(multi-head self-attention)과 계산(per-token feed-forward MLP, 내부 차원 4배)을 번갈아 쌓으며, MLP 추가만으로 손실이 2.28→2.24 로 내려갔다 [1] (85:30). 깊은 망의 최적화를 가능케 하는 두 장치는 residual connection(덧셈 노드가 그래디언트를 그대로 분배하는 '슈퍼하이웨이')과 layer norm 으로, 강의는 원논문과 달리 변환 '이전'에 norm 을 두는 pre-norm 을 쓴다 [1] (90:30).

### 스케일업과 ChatGPT 와의 거리

스케일업(블록 6층, n_embd 384, head 6, block_size 256, dropout 0.2, batch 64)으로 A100 에서 약 15분 학습하니 검증 손실이 2.07→1.48 로 떨어졌고, 우리가 만든 것은 삼각 마스크로 미래를 가린 decoder-only Transformer 로 인코더·cross-attention 이 있는 원논문 번역 모델과 다르다 [1] (100:30). ChatGPT 는 (1) 인터넷 대규모 코퍼스 pretraining(GPT-3 1750억 파라미터·3000억 토큰, 강의의 1000만 파라미터·약 30만 토큰 대비 약 100만 배) 으로 '문서 완성기' 를 만들고 (2) SFT→보상모델→PPO(RLHF) 정렬로 비서로 전환하며, nanoGPT 는 (1)단계만 다룬다 [1] (110:30).

## 챕터별 요약

### 도입: ChatGPT·Transformer·nanoGPT·Shakespeare (0:00 – 7:52)

ChatGPT 가 확률적 언어 모델임을 시연하고 그 뒤의 신경망이 2017 'Attention Is All You Need' 의 Transformer 임을 소개한다. 본 강의 목표는 production 재현이 아니라 tiny Shakespeare 위 character-level Transformer 를 처음부터 구현하는 것이다. 완성 코드는 model.py·train.py(각 ~300줄)로 된 nanoGPT 저장소로, gpt2 124M 재현이 검증됐다.

### 데이터 탐색·토크나이즈·분할 (7:52 – 14:27)

1MB tiny Shakespeare 에서 고유 문자 65개 vocab 을 만들고 encode/decode 룩업으로 정수 시퀀스화한다. subword 토크나이저(SentencePiece·tiktoken)는 vocab~5만으로 시퀀스를 압축하지만 단순함을 위해 문자 단위를 고수한다. 앞 90% 학습 / 뒤 10% 검증으로 분할한다.

### 데이터 로더와 bigram 베이스라인 (14:27 – 38:00)

block_size 청크로 입력 x 와 시프트 타깃 y 를 만들고 batch_size 무작위 시작점으로 (B,T) 배치를 쌓는다. nn.Embedding 한 장으로 bigram 모델을 구현하고 cross_entropy 를 위해 (B,T,C)→(B*T,C) reshape 한다. AdamW 로 학습해 손실을 ≈2.5 로 낮추고 코드를 단일 스크립트로 정리한다.

### self-attention 의 수학과 핵심 (42:13 – 71:38)

인과성 제약 하에 '과거 평균' 을 for-loop bag-of-words 로 보인 뒤, tril 정규화 행렬 곱으로 같은 평균을 단일 행렬곱으로 얻는 트릭(version 1–3)을 전개한다. position embedding 을 더하고, query/key/value 내적 기반 single-head self-attention(version 4)을 구현해 weight 가 데이터·위치마다 달라지게 만든다.

### attention 노트와 네트워크 삽입 (71:38 – 84:25)

attention 을 방향성 그래프 통신으로 재해석하고 삼각 마스크 유무(decoder/encoder)·key·value 출처(self/cross)를 구분한다. 1/√(head_size) 스케일링 근거를 설명한 뒤 Head 모듈을 삽입(손실 2.5→2.4)하고 multi-head 로 확장해 2.28 을 얻는다.

### 블록 완성·스케일업·ChatGPT 결론 (84:25 – 116:20)

feed-forward MLP(손실 2.24), residual(2.08), layer norm(pre-norm, 2.06)으로 Block 을 완성하고 dropout·스케일업으로 검증 손실 1.48 을 얻는다. nanoGPT 의 batched causal self-attention 효율화를 짚고, ChatGPT 의 pretraining(GPT-3 1750억·3000억 토큰) vs RLHF 정렬 2단계를 설명하며 nanoGPT 가 전자만 다룸을 정리한다.

## 타임코드 인용

- **[3:30]** "GPT is short for generatively pre-trained Transformer ... this architecture with minor changes was copy pasted into a huge amount of applications in AI" [1]
- **[64:30]** "the query vector roughly speaking is what am I looking for and the key vector roughly speaking is what do I contain" [1]
- **[90:30]** "you have this gradient super highway that goes directly from the supervision all the way to the input unimpeded" [1]
- **[110:30]** "it takes the model from being a document completer to a question answerer" [1]

## 연관 자료

### 논문
- [Attention Is All You Need](https://arxiv.org/abs/1706.03762) — Transformer 원논문(2017), 강의 아키텍처의 출처.
- [Language Models are Few-Shot Learners (GPT-3)](https://arxiv.org/abs/2005.14165) — 175B·300B 토큰 스케일 비교 기준.
- [Deep Residual Learning (ResNet)](https://arxiv.org/abs/1512.03385) — residual/skip connection 출처.
- [Layer Normalization](https://arxiv.org/abs/1607.06450) — layer norm 출처.

### 레포
- [karpathy/nanoGPT](https://github.com/karpathy/nanoGPT) — 강의 완성본과 동일 구조의 GPT 학습 저장소.
- [karpathy/ng-video-lecture](https://github.com/karpathy/ng-video-lecture) — 본 강의 from-scratch 코드.
- [openai/tiktoken](https://github.com/openai/tiktoken) — GPT BPE 토크나이저(vocab ~50k).

## 한계 / 미해결

- 강의 모델은 character-level·약 1000만 파라미터의 toy 규모로, GPT-3(1750억) 대비 약 100만 배 작아 생성물은 Shakespeare 풍이지만 무의미하다 [1] (100:30).
- ChatGPT 를 만드는 정렬 단계(SFT·보상모델·PPO/RLHF)는 개념적으로만 언급되고 구현되지 않는다 [1] (110:30).
- 토크나이즈는 character-level 만 다루며 BPE 등 실전 subword 토크나이저 학습은 후속 강의로 미뤄진다 [1] (11:00).
- weight initialization 의 세부(예: 출력층 스케일)는 가볍게만 다뤄진다.

## Sources

1. **Let's build GPT: from scratch, in code, spelled out.** — https://www.youtube.com/watch?v=kCc8FmEb1nY (adapter: `youtube`, fetched: 2026-05-25)
