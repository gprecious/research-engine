# youtube-adapter `findings-guidance` 실 bench 진화 사이클 — 리포트

- **일자**: 2026-05-25
- **어댑터 / 영역**: `youtube-adapter` / `findings-guidance`
- **변이(variant)**: timecode 포맷을 영상 **총 길이** 기준으로 결정 — 60분 미만은 `mm:ss`, 60분 이상은 `hh:mm:ss` (zero-padded)
- **출처**: `/tmp/mutator-out.json` `variants[0]` (drm_2026-05-25-2153 의 'YouTube 메타데이터 스키마 불일치' 신호)
- **최종 결정**: **accept** (paired bootstrap CI 하한 > 0)

이 사이클은 직전 mock `/evolve` 사이클이 합성(synthetic) 점수로 `hold` 를 낸 것을 **실제 bench 데이터로 재검증**한 것이다. 모든 점수는 실제 `/research` 실행 + LLM-as-judge 채점에서 나왔다 (mock 없음).

---

## 1. 선정한 토픽과 이유

`bench/topics.yaml` 에는 YouTube 토픽이 **하나뿐**이라(`youtube-3blue1brown-gpt`), 절차의 fallback("pick any 2 youtube topics") 에 따라 장편 영상 1개를 **ad-hoc 토픽**으로 추가했다. baseline_prompt 는 topics.yaml 의 표준 YouTube 템플릿(공정성 규칙상 모든 youtube 토픽이 동일)을 그대로 사용했다.

| topic_id | 영상 | 길이 | 역할 |
|---|---|---|---|
| `youtube-3blue1brown-gpt` | 3Blue1Brown — Transformers, the tech behind LLMs (wjZofJX0v4M) | **27.2분** | **단편**: 변이도 `mm:ss` 를 내므로 포맷 동일 → **비(非)회귀 확인용** |
| `youtube-karpathy-buildgpt` (ad-hoc) | Andrej Karpathy — Let's build GPT from scratch (kCc8FmEb1nY) | **116.3분** | **장편(≥60분, 60분 경계 통과)**: 변이가 `hh:mm:ss` 를 내는 핵심 가치 제안 검증용 |

장편 영상은 챕터가 60분 이후까지 이어져(nanoGPT 1:46, RLHF 1:48, 결론 1:54), 현재 페르소나의 `mm:ss` 가 `106:22`·`110:30` 처럼 "분이 60을 초과하는" 자기충돌을 일으킨다 — 변이가 정확히 이 지점을 겨냥한다.

## 2. 방법론 메모 (중요)

플러그인 캐시의 `agents/youtube-adapter.md` 는 repo 파일의 **사본**(symlink 아님)이며, `bench/run.sh --swap-candidates` 는 **repo 파일만** 교체한다. 따라서 어댑터를 `subagent_type='research-engine:youtube-adapter'` 로 디스패치하면 캐시 페르소나를 읽어 **swap 이 무효화**된다. 이를 피하려고 어댑터를 `general-purpose` 서브에이전트로 띄우되 **repo 의 `agents/youtube-adapter.md` 를 직접 Read 해 그 지침을 따르도록** 했다 — swap 이 mutate 하는 바로 그 파일이므로, current arm = 원본(`mm:ss`), candidate arm = 교체본(`hh:mm:ss`) 이 보장된다.

- swap 은 task 지시대로 **repo 의 `bash bench/run.sh`** 로 실행 (초기에 플러그인 캐시 사본을 잘못 호출해 캐시를 건드렸으나 즉시 `--restore-candidates` 로 복원, 캐시는 원본과 byte-identical 확인).
- **복원 완료**: 사이클 종료 시 `agents/youtube-adapter.md` 는 (promote 전까지) 원본으로 복원됨을 확인. 이후 accept 결정에 따라 정식 promote.
- Notion push 는 `NOTION_TOKEN` 미설정으로 자동 skip (bench 규칙). memory reindex/dream-ledger 갱신은 실험 중 ledger 오염 방지를 위해 의도적으로 생략.

## 3. Judge 점수 (blind, sonnet, A/B/C 무작위 순열)

각 토픽마다 current·candidate·baseline 3개 리포트를 **중립 경로(A/B/C)** 로 복사해 무작위 순열로 제시 → 경로에 arm 이름이 새지 않게 하여 동일 calibration 으로 채점. 축별 0–10, total = 4축 합 (0–40).

### youtube-3blue1brown-gpt (27분, 단편)

| arm | coverage | citation | depth | structure | **total** |
|---|---|---|---|---|---|
| current | 9 | 7 | 8 | 9 | **33** |
| candidate | 9 | 8 | 8 | 9 | **34** |
| baseline | 9 | 5 | 9 | 9 | **32** |

→ delta(cand−cur) = **+1**. 단편이라 두 RE arm 모두 `mm:ss` 로 **포맷이 동일** — 이 +1 은 LLM run-to-run 잡음이며 포맷 효과가 아니다.

### youtube-karpathy-buildgpt (116분, 장편)

| arm | coverage | citation | depth | structure | **total** |
|---|---|---|---|---|---|
| current | 9 | 7 | 8 | 9 | **33** |
| candidate | 9 | **9** | 8 | 9 | **35** |
| baseline | 9 | 7 | 8 | 9 | **33** |

→ delta(cand−cur) = **+2**. **블라인드 judge 가 포맷 차이를 독립적으로 지목**:
- candidate: *"citations use precise HH:MM:SS timecodes (e.g., 01:02:00, 01:16:56) that are unambiguous for a 2-hour video"* → citation **9**
- current: *"ambiguous MM:SS-style timecodes (e.g., 49:30, 110:30) which for a ~2-hour video could be misread as 49 min vs 1h49 min, making traceability weaker"* → citation **7**

이는 변이의 가치 제안(장편 영상 timecode 결정성·추적성)이 어느 arm 인지 모르는 상태에서 그대로 재현된 강력한 정성 신호다.

## 4. 통계 게이트 (paired bootstrap, seed=42, 2000 iters)

- cur scores = `[33, 33]`, cand scores = `[34, 35]` (순서 `[3b1b, karpathy]`)
- deltas = `[+1, +2]`, mean = **1.5**
- **95% CI = [1, 2]** → 하한 **1 > 0**
- `gateDecision`: `ci.lower > 0` → **accept**

n=2 이고 두 delta 가 모두 양수이므로, 복원추출 bootstrap 은 평균 ≤ 0 인 표본을 만들 수 없다(가능한 표본 평균 ∈ {1.0, 1.5, 2.0}). 따라서 하한 = 작은 delta = 1.0 > 0 으로 자동 accept 된다.

## 5. 최종 결정 및 해석

**accept** — `youtube-adapter` 를 v1 으로 promote. `agents/youtube-adapter.md` 의 `findings-guidance` 영역이 duration-based `mm:ss`/`hh:mm:ss` 규칙으로 교체되고 ledger 에 frontier v1 으로 기록됨. (v1 이라 archive 대상 이전 버전 없음.)

해석: 장편 영상에서의 +2 는 **실제 신호**다 — 설계 의도(60분 이상 → `hh:mm:ss`) 가 그대로 동작했고 블라인드 judge 가 정확히 그 이유로 citation 점수를 올렸다. 단편 영상의 +1 은 포맷이 동일하므로 잡음이며, accept 가 성립한 것은 이 잡음이 우연히 양수로 떨어진 덕도 있다.

## 6. n=2 는 충분했는가 — 정직한 평가

**아니다 — accept 는 통계적으로 취약하다.** 게이트 수학상 두 delta 가 모두 양수이기만 하면 n=2 paired bootstrap 은 항상 accept 를 낸다. 만약 단편 영상의 잡음 delta 가 0 이나 음수로 떨어졌다면(`[0,2]` 또는 `[-1,2]`) CI 하한이 0 이하가 되어 **hold** 로 뒤집혔을 것이다 — 즉 결정이 단편 영상의 ±1 잡음에 좌우되는 구조다. mock 사이클이 `hold` 였던 것과 이번이 `accept` 인 것의 차이는 변이 품질이 아니라 **표본이 우연히 같은 방향으로 정렬됐는지** 에 가깝다. 신뢰할 만한 결론을 위해선 장편 영상 비중을 높여 최소 4–6개 paired 토픽(이상적으로 시드별 반복)이 필요하다. 다만 **정성 증거는 정량 증거보다 훨씬 설득력 있다**: 블라인드 judge 가 장편에서 `hh:mm:ss` 의 비모호성을 직접 citation 근거로 든 점은, 변이가 적어도 장편 영상에서는 실질 개선이고 단편에서는 회귀가 없음을 보여준다. 결론적으로 **게이트 결정(accept)은 데이터에 충실히 따랐으나, 그 신뢰구간은 n=2 의 한계로 인해 결정적이지 않으며, promote 의 정당성은 통계보다 정성 메커니즘 증거에 더 기댄다.**

---

### 산출물
- RE/baseline 출력: `bench/runs/2026-05-25-real-evolve-cycle/<topic>/{current,candidate,baseline}/output.md`
- judge 기록: `bench/runs/2026-05-25-real-evolve-cycle/<topic>/judge.json`
- 결정 입력: `cur.json` / `cand.json` (repo 루트, 사이클 산출물)
- ledger: `research/_index/evolve-ledger.json` (frontier v1)
- 원본 research 세션: `research/2026-05-25-transformers-the-tech-behind-llms-deep-l`(current), `-cand`(candidate), `research/2026-05-25-lets-build-gpt-from-scratch-in-code-spel`(current), `-cand`(candidate)
