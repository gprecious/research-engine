---
title: "Transformers, the tech behind LLMs | Deep Learning Chapter 5 — 분석"
slug: "2026-05-25-transformers-the-tech-behind-llms-cand"
created: "2026-05-25"
input: "https://www.youtube.com/watch?v=wjZofJX0v4M"
input_type: "youtube"
intent_mode: "assumed"
---

## 분석 목적 (Intent)

**추정(assumed)**
- 용도: 3Blue1Brown 의 Transformer/LLM 작동 원리 시각적 설명 영상을 분석해 핵심 개념·주장·한계를 구조화
- 집중: concepts (embedding → attention → unembedding → softmax 흐름)
- 배경지식: intermediate

**엔진 해석**
시청자가 트랜스포머 내부 데이터 흐름을 수식 없이도 정확히 직관하도록, 영상의 개념 사슬과 GPT-3 규모 수치를 추적 가능한 인용과 함께 정리한다.

## 요약 (TL;DR)

이 영상은 GPT 를 Generative·Pretrained·**Transformer** 로 풀이하며 transformer 가 현재 AI 붐의 핵심 발명임을 강조하고, 텍스트 생성을 "다음 토큰 확률분포 예측 → 샘플링 → 이어붙이고 반복" 의 루프로 설명한다 [1] (00:00, 02:26). 내부 흐름은 토큰화 → 의미 벡터(임베딩) → attention 블록(문맥에 따른 의미 갱신) ↔ MLP 블록(병렬 처리) 반복 → unembedding → softmax 순이다 [1] (03:55). 학습된 임베딩 공간의 방향이 의미를 담아 woman−man ≈ king−queen 같은 벡터 산술이 성립하며, dot product 가 정렬도를 측정한다 [1] (14:21, 16:34). GPT-3 의 1,750억 파라미터는 약 28,000개 행렬·8범주로 조직되고 임베딩·언임베딩 행렬이 각각 약 6.17억을 차지한다 [1] (11:06, 18:00). 끝으로 softmax 와 온도 T 가 확률분포의 날카로움을 조절하는 방식을 설명하며 attention 을 다룰 다음 챕터의 기초를 닦는다 [1] (24:09).

## 핵심 포인트

- transformer 는 GPT 세 글자 중 핵심 발명이며 2017 구글 번역용 원조의 변형이 ChatGPT 계열이다 [1] (00:00).
- 생성은 다음 토큰 확률분포 예측 → 샘플링 → 반복 루프이며, GPT-2(횡설수설) 대 GPT-3(일관성) 대비로 규모의 효과를 보인다 [1] (02:26).
- attention 블록은 문맥상 의미 갱신을, MLP(feed-forward) 블록은 벡터 간 상호작용 없는 병렬 처리를 담당한다 [1] (03:55).
- 'machine learning model' 의 model 과 'fashion model' 의 model 은 attention 을 거치며 다른 의미 벡터로 갈라진다 [1] (04:04).
- 딥러닝 파라미터(weights)는 데이터와 오직 weighted sum 으로만 상호작용해 거의 모든 연산이 행렬-벡터 곱이다 [1] (09:16).
- GPT-3 의 175B weights 는 약 28,000개 행렬·8범주로 조직된다 [1] (11:06).
- 임베딩 공간의 방향이 의미를 담아 woman−man ≈ king−queen, Italy−Germany+Hitler ≈ Mussolini 가 성립한다 [1] (14:21).
- dot product 는 정렬도(같은 방향 양수·직교 0·반대 음수)를 측정하는 핵심 도구다 [1] (16:34).
- GPT-3 어휘 50,257·임베딩 12,288차원·컨텍스트 2048, 임베딩 행렬만 약 6.17억 weights [1] (18:00, 19:49).
- softmax + 온도 T 가 분포를 조절(T=0 → 최댓값 독점, 큰 T → 균일·붕괴), API 는 T≤2 로 임의 제한한다 [1] (24:09).

## 상세 분석

### 생성 루프와 transformer 의 위상

GPT 의 세 글자 중 transformer 가 핵심 발명으로, 2017년 구글이 기계 번역용으로 발표한 원조의 변형이 '다음 텍스트 예측' 에 맞춰 학습된 ChatGPT 계열이다 [1] (00:00). 텍스트 생성은 본질적으로 다음 토큰 확률분포를 예측해 샘플링한 뒤 이어붙이고 반복하는 루프이며, 같은 기본 구조라도 작은 GPT-2 는 횡설수설하지만 훨씬 큰 GPT-3 는 거의 일관된 이야기를 내놓아 규모의 효과를 드러낸다 [1] (02:26).

### 데이터 흐름: 토큰 → 벡터 → attention/MLP

내부 흐름은 토큰화 → 각 토큰을 의미 벡터로 매핑 → attention 블록 ↔ MLP 블록 반복 → 마지막 벡터에 핵심 의미 응축 순이다 [1] (03:55). attention 블록은 문맥상 어떤 단어가 다른 단어의 의미 갱신에 관여하는지와 그 갱신 방식을 결정하는 반면, MLP(feed-forward) 블록은 벡터들이 상호작용 없이 병렬 처리된다 [1] (04:04). 'machine learning model' 의 model 과 'fashion model' 의 model 이 attention 을 거치며 서로 다른 의미 벡터로 갈라지는 것이 대표 예다 [1] (04:04).

### 파라미터 = weights, 그리고 행렬 곱

딥러닝은 동작을 코드로 명시하는 대신 조절 가능한 파라미터(weights)를 데이터로 튜닝하며, backpropagation 이 대규모에서 작동하려면 입력을 실수 텐서로 두고 파라미터가 데이터와 오직 weighted sum(행렬-벡터 곱)으로만 상호작용해야 한다 [1] (09:16). GPT-3 의 1,750억 weights 는 약 28,000개 행렬·8개 범주로 조직되며, 학습된 weights 와 입력별로 흐르는 처리 데이터를 명확히 구분해야 한다 [1] (11:06).

### 임베딩의 기하학과 unembedding

임베딩 행렬 W_E 는 어휘의 각 단어마다 열을 가지며, 학습 후 공간의 방향이 의미를 담아 woman−man ≈ king−queen, Italy−Germany+Hitler ≈ Mussolini 같은 벡터 산술이 성립한다 [1] (14:21). dot product 는 정렬도(같은 방향 양수·직교 0·반대 음수)를 측정하며 weighted sum 형태라 딥러닝 연산과 맞아떨어진다 [1] (16:34). GPT-3 어휘는 50,257, 임베딩 12,288차원이고 임베딩 행렬만 약 6.17억 weights 이며, 컨텍스트 크기 2048 이 한 번에 처리하는 벡터 수를 제한한다 [1] (18:00, 19:49). 예측은 마지막 벡터를 Unembedding 행렬 W_U(약 6.17억) 로 약 50,000개 logits 에 매핑한 뒤 softmax 로 확률분포화하는 두 단계다 [1] (19:49).

### softmax 와 온도

softmax 는 임의의 실수 리스트에 e 의 거듭제곱을 취한 뒤 총합으로 나눠 유효 확률분포로 바꾸며 최댓값을 '부드럽게' 선택한다 [1] (23:00). 지수 분모에 온도 T 를 넣어 분포를 조절하는데 T 가 크면 균일해져 덜 가능한 단어 여지가 생기고 T=0 이면 최댓값에 전부 쏠리며, API 가 T 를 2 이하로 제한하는 것은 임의 제약이다 [1] (24:09).

## 챕터별 요약

### Predict, sample, repeat (00:00 – 03:03)

GPT 를 풀이하며 transformer 가 AI 붐의 핵심 발명임을 소개한다. 2017 구글 번역용 원조와 달리 ChatGPT 계열은 다음 텍스트 확률분포 예측에 맞춰 학습된 변형이다. 다음 단어 예측을 '예측→샘플링→이어붙이기' 루프로 돌려 긴 텍스트를 생성한다. GPT-2(횡설수설) 대 GPT-3(일관성) 대비로 규모의 위력을 시연한다.

### Inside a transformer (03:03 – 06:36)

내부 데이터 흐름의 고수준 개요: 입력을 토큰으로 쪼개 각 토큰을 의미 벡터로 매핑하고 비슷한 의미는 가까이 위치시킨다. attention 블록에서 벡터들이 문맥에 맞게 의미를 교환·갱신하고 MLP 블록에서 병렬 처리된다. attention↔MLP 반복 뒤 마지막 벡터에서 다음 토큰 분포를 뽑으며, 챗봇은 system prompt+사용자 입력을 시드로 반복한다.

### The premise of Deep Learning (07:20 – 12:27)

딥러닝은 절차 코딩 대신 조절 가능한 파라미터를 데이터로 튜닝하며 선형회귀가 가장 단순한 형태다. GPT-3 는 1,750억 파라미터를 가지며 backpropagation 에 맞는 형식(실수 텐서, weighted sum 중심)을 따라야 한다. weights 는 약 28,000개 행렬·8범주로 조직되고, 학습 weights 와 처리 데이터를 색으로 구분한다.

### Word embeddings (12:27 – 18:25)

임베딩 행렬 W_E 는 어휘(50,257)마다 열을 가지며 단어를 12,288차원 벡터로 변환하고 값은 학습된다. 공간의 방향이 의미를 담아 woman−man ≈ king−queen 같은 산술이 성립한다. dot product 가 정렬도를 재는 도구임을 복수형 방향 예로 다지고, 임베딩 행렬이 약 6.17억 weights 임을 집계한다.

### Unembedding (20:22 – 22:22)

마지막 벡터를 Unembedding 행렬 W_U 로 어휘 크기(약 50,000) 값 리스트에 매핑한 뒤 softmax 로 정규화한다. 마지막 벡터만 쓰는 이유는 학습 시 각 위치에서 다음 토큰을 동시 예측하는 것이 효율적이기 때문이다. W_U 는 약 6.17억 파라미터를 더해 누적 약 10억을 넘긴다.

### Softmax with temperature (22:22 – 26:03)

softmax 는 e 지수 후 총합으로 나눠 유효 확률분포를 만들며 최댓값을 부드럽게 고른다. 온도 T 를 지수 분모에 넣어 분포를 조절(큰 T → 균일·창의적이나 붕괴, T=0 → 예측 가능한 단어). API 는 T 를 2로 제한하며 입력값을 logits 라 부른다.

## 타임코드 인용

- **[00:00]** "A transformer is a specific kind of neural network, a machine learning model, and it's the core invention underlying the current boom in AI." [1]
- **[14:21]** "if you take the difference between the vectors for woman and man ... it's very similar to the difference between king and queen" [1]
- **[16:34]** "the dot product is positive when vectors point in similar directions, it's zero if they're perpendicular, and it's negative whenever they point in opposite directions" [1]

## 연관 자료

### 논문
- [Attention Is All You Need](https://arxiv.org/abs/1706.03762) — 영상이 언급한 2017 구글 원조 트랜스포머 논문.

### 블로그 / 문서
- [3Blue1Brown — Transformers / GPT lesson](https://www.3blue1brown.com/lessons/gpt) — 이 영상의 본문 레슨 페이지.

## 한계 / 미해결

- attention 메커니즘 자체는 이 영상(Chapter 5)에서 다루지 않고 다음 챕터로 미뤄진다.
- 모든 수치(175B, 12,288, 2048, 50,257)는 GPT-3 기준으로 이후 세대에 그대로 적용되지 않는다.
- 영상은 개념적 직관에 집중하며 실제 학습 과정(loss·optimizer·backprop 세부)은 블랙박스로 남긴다.

## Sources

1. **Transformers, the tech behind LLMs | Deep Learning Chapter 5** — https://www.youtube.com/watch?v=wjZofJX0v4M (adapter: `youtube`, fetched: 2026-05-25)
