---
title: "Transformers, the tech behind LLMs | Deep Learning Chapter 5 — 분석"
slug: "2026-05-25-transformers-the-tech-behind-llms-deep-l"
created: "2026-05-25"
input: "https://www.youtube.com/watch?v=wjZofJX0v4M"
input_type: "youtube"
intent_mode: "assumed"
---

## 분석 목적 (Intent)

**추정(assumed)**
- 용도: 3Blue1Brown 의 Transformer/LLM 작동 원리 시각적 설명 영상을 분석해 핵심 개념·주장·한계를 구조화
- 집중: concepts (개념 흐름 — embedding → attention → unembedding → softmax)
- 배경지식: intermediate

**엔진 해석**
시청자가 트랜스포머 내부 데이터 흐름을 "수식 없이도 정확한 직관"으로 잡을 수 있도록, 영상이 제시한 개념 사슬과 GPT-3 규모 수치를 추적 가능한 인용과 함께 정리한다.

## 요약 (TL;DR)

이 영상은 GPT 를 Generative·Pretrained·**Transformer** 로 분해하며 마지막 단어가 핵심임을 강조하고, ChatGPT 류 모델을 "다음 토큰 확률분포 예측 → 샘플링 → 이어붙이기" 의 반복 루프로 설명한다 [1]. 데이터는 토큰화 → 의미 벡터(임베딩) → attention 블록 ↔ MLP 블록 교대 → unembedding → softmax 순으로 흐르며, attention 은 벡터 간 문맥 교환을, MLP 는 병렬 변환을 담당한다 [1]. 임베딩 공간에서 방향이 의미를 가지며(woman−man ≈ king−queen), dot product 가 정렬도를 측정하는 핵심 도구로 쓰인다 [1]. GPT-3 의 1,750억 파라미터는 약 28,000개 행렬·8개 범주로 조직되고, 임베딩/언임베딩 행렬이 각각 약 6.17억 파라미터를 차지한다 [1]. 마지막으로 softmax 와 온도(temperature) 상수가 확률분포의 날카로움을 조절하는 방식을 설명하며 attention 을 다룰 다음 챕터의 기초를 닦는다 [1].

## 핵심 포인트

- GPT 의 세 글자 중 **Transformer** 가 현재 AI 붐의 핵심 발명이며, 나머지(Generative·Pretrained)는 보조 수식어다 [1].
- 생성의 본질은 다음 토큰 확률분포를 예측해 샘플링한 뒤 전체를 반복하는 predict-sample-repeat 루프다 [1] (01:38).
- 동일 구조라도 GPT-2(로컬)는 비일관적이지만 훨씬 큰 GPT-3 는 일관된 이야기를 생성 — 규모가 품질을 가른다 [1] (02:42).
- attention 블록은 벡터 간 문맥 정보를 교환하고, MLP(feed-forward) 블록은 벡터들을 병렬·독립적으로 변환한다 [1] (03:55).
- 딥러닝 파라미터는 데이터와 가중합으로만 상호작용하므로 거의 모든 연산이 행렬-벡터 곱이며, GPT-3 의 175B 가중치는 약 28,000개 행렬·8범주로 조직된다 [1] (09:41).
- 임베딩 공간의 방향이 의미를 띠며(woman−man ≈ king−queen), dot product 가 정렬도를 측정한다 [1] (14:58).
- 임베딩 벡터는 단어가 아니라 문맥을 흡수하는 그릇이며, GPT-3 컨텍스트 크기는 2048 이다 [1] (18:25).
- softmax + 온도 T 가 분포의 날카로움을 조절하고(T=0 → 최댓값 독점), softmax 입력값을 로짓(logits)이라 부른다 [1] (23:39).

## 상세 분석

### 생성 루프와 트랜스포머의 위상

ChatGPT 류 모델은 입력 텍스트 다음에 올 청크의 확률분포를 산출하고, 거기서 무작위 샘플을 뽑아 이어붙인 뒤 같은 과정을 반복한다 [1] (01:38). 트랜스포머는 2017년 구글이 번역용으로 처음 도입한 신경망 종류로, 음성 전사·합성과 DALL·E/Midjourney 류 텍스트-이미지 생성에도 쓰인다 [1]. 같은 predict-sample 루프라도 로컬 GPT-2 는 횡설수설하지만 규모를 키운 GPT-3 는 거의 일관된 이야기를 내놓아 규모의 결정적 영향을 보여준다 [1] (02:42).

### 데이터 흐름: 토큰 → 벡터 → attention/MLP

데이터는 토큰화 → 각 토큰의 의미 벡터화 → attention 블록과 MLP 블록의 교대 반복 → 마지막 벡터로 다음 토큰 확률분포 산출 순서로 흐른다 [1] (03:19). attention 블록은 벡터끼리 정보를 주고받아 문맥상 어떤 단어가 다른 단어의 의미 갱신에 관여하는지 결정하는 반면, MLP 블록은 벡터들이 서로 대화하지 않고 동일 연산을 병렬 통과시킨다 [1] (03:55).

### 파라미터 = 가중치, 그리고 행렬 곱

딥러닝 모델의 파라미터는 '가중치(weights)' 라 불리며 데이터와 오직 가중합으로만 상호작용하기에 거의 모든 연산이 행렬-벡터 곱으로 표현된다 [1] (09:41). GPT-3 의 1,750억 가중치는 약 28,000개 행렬·8개 범주로 조직되고, 임베딩 행렬 W_E(50,257 × 12,288 ≈ 6.17억)와 언임베딩 행렬 W_U(약 6.17억)가 그 누계의 양 끝을 이룬다 [1] (18:00).

### 임베딩의 기하학과 unembedding

학습된 임베딩 공간에서 방향은 의미를 가지며 woman−man ≈ king−queen, Italy−Germany+Hitler ≈ Mussolini 같은 관계가 성립하고, dot product 가 두 벡터의 정렬도(양수=같은 방향, 0=수직, 음수=반대)를 측정한다 [1] (14:58). 임베딩 벡터는 개별 단어가 아니라 문맥을 흡수하는 그릇으로, 'king' 벡터가 네트워크를 거치며 풍부한 방향으로 끌려갈 수 있다(GPT-3 컨텍스트 2048) [1] (18:25). 끝단의 unembedding 행렬은 마지막 벡터를 어휘 크기(약 50,000) 로짓으로 매핑하며, 최종 층의 모든 벡터가 각자 다음 토큰을 동시에 예측하도록 학습된다 [1] (20:22).

### softmax 와 온도

softmax 는 임의 수열을 유효 확률분포(각 0~1, 합 1)로 변환하며, 지수 분모에 온도 상수 T 를 넣어 T 가 크면 분포가 균일해지고 T=0 이면 최댓값에 전부 몰린다 [1] (23:39). API 가 T 를 2로 제한하는 것은 수학적 근거가 아닌 임의 제약이며, softmax 의 정규화되지 않은 원시 입력값을 머신러닝에서는 '로짓(logits)' 이라 부른다 [1] (25:33).

## 챕터별 요약

### Predict, sample, repeat (0:00 – 3:03)

GPT = Generative Pretrained Transformer 로 분해하며 Transformer 가 핵심임을 강조한다. ChatGPT 류 모델은 다음 토큰의 확률분포를 예측하고 샘플링·이어붙이기를 반복하는 생성 루프임을 설명한다. 트랜스포머는 음성 전사·합성, 텍스트-이미지 생성에도 쓰이며 2017년 구글이 번역용으로 도입했다. 로컬 GPT-2 는 엉성하지만 더 큰 GPT-3 는 일관된 이야기를 내놓아 규모의 중요성을 보여준다.

### Inside a transformer (3:03 – 6:36)

데이터 흐름의 고수준 미리보기: 입력을 토큰으로 쪼개 각 토큰을 의미 벡터로 변환한다. attention 블록에서 벡터들이 문맥 정보를 교환해 의미를 갱신하고, MLP 블록에서는 벡터들이 병렬로 동일 연산을 통과한다. 두 블록을 번갈아 반복한 뒤 마지막 벡터로 다음 토큰 확률분포를 산출한다. 챗봇은 system prompt + 사용자 입력으로 어시스턴트 응답을 예측하게 만든 것이다.

### The premise of Deep Learning (7:27 – 12:27)

딥러닝은 절차를 명시 코딩하는 대신 튜닝 가능한 파라미터를 데이터로 조정하는 ML 접근이며 선형회귀가 가장 단순한 형태다. GPT-3 는 1,750억 파라미터를 가지며 backpropagation 으로 잘 확장되려면 특정 포맷을 따라야 한다. 파라미터는 데이터와 가중합으로만 상호작용해 거의 모든 연산이 행렬-벡터 곱이 된다. 175B 가중치는 약 28,000개 행렬·8개 범주로 조직된다.

### Word embeddings (12:27 – 18:25)

임베딩 행렬 W_E 의 각 열이 단어를 벡터로 변환하며 값은 학습으로 결정된다(GPT-3: 12,288차원). 학습된 공간에서 방향이 의미를 띠어 woman−man ≈ king−queen 같은 관계가 성립한다. dot product 는 벡터 정렬도를 측정하며 가중합 형태라 딥러닝 패러다임에 부합한다. 임베딩 행렬은 약 6.17억 가중치다.

### Unembedding (20:22 – 22:22)

네트워크 끝단에서 마지막 벡터를 Unembedding 행렬 W_U 로 어휘 크기(약 50,000) 값 리스트에 매핑한다. 마지막 벡터만 쓰는 이유는 학습 시 최종 층의 모든 벡터가 각자 다음 토큰을 동시 예측하는 편이 효율적이기 때문이다. W_U 는 임베딩 행렬과 순서만 바뀐 형태로 약 6.17억 파라미터를 추가한다.

### Softmax with temperature (22:22 – 26:03)

softmax 는 임의 수열을 합이 1인 유효 확률분포로 변환한다(e 지수 후 합으로 나눔). 온도 T 를 지수 분모에 넣으면 T 가 클수록 분포가 균일, T=0 이면 최댓값에 전부 몰린다. GPT-3 'once upon a time' 데모로 T=0 은 진부하고 높은 T 는 독창적이나 무의미로 붕괴함을 보인다. API 의 T≤2 제한은 임의적이며 softmax 원시 입력값은 로짓이라 부른다.

## 타임코드 인용

- **[01:38]** "have it take a random sample from the distribution it just generated, append that sample to the text, and then run the whole process again" [1]
- **[14:58]** "the difference between the vectors for woman and man ... is very similar to the difference between king and queen" [1]
- **[23:39]** "There's no mathematical reason for this, it's just an arbitrary constraint imposed to keep their tool from being seen generating things that are too nonsensical." [1]

## 연관 자료

### 논문
- [Attention Is All You Need](https://arxiv.org/abs/1706.03762) — 영상이 언급한 2017 구글 원조 트랜스포머 논문.

### 블로그 / 문서
- [3Blue1Brown — But what is a GPT?](https://www.3blue1brown.com/lessons/gpt) — 이 영상의 본문 레슨 페이지(Python word2vec 데모 안내 포함).

## 한계 / 미해결

- attention 메커니즘 자체는 이 영상(Chapter 5)에서 다루지 않고 다음 챕터로 미뤄져, 트랜스포머의 "심장" 에 대한 구체 설명은 본 분석 범위 밖이다.
- 모든 수치(175B, 12,288, 2048, 50,257)는 GPT-3 기준으로, 이후 세대 모델에는 그대로 적용되지 않는다.
- 영상은 개념적 직관에 집중하며 실제 학습 과정(loss·optimizer·backprop 세부)은 블랙박스로 남겨 둔다.

## Sources

1. **Transformers, the tech behind LLMs | Deep Learning Chapter 5** — https://www.youtube.com/watch?v=wjZofJX0v4M (adapter: `youtube`, fetched: 2026-05-25)
