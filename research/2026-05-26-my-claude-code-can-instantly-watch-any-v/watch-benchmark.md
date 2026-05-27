# watch 프레임 벤치마크

## 목적

`youtube-adapter`의 기존 캡션 전용 분석과 신규 `frames+transcript` 분석을 같은 영상 구간에서 비교했다. 성공 지표는 **시각 전용 사실 커버리지**다. 화면에는 보이지만 0-90초 자막 텍스트에는 없는 사실을 정답셋으로 만들고, 각 모드가 그 사실을 근거 있게 포착할 수 있는지 세었다.

## 실행 환경

- 날짜: 2026-05-27
- 브랜치: `feat/youtube-watch-frames`
- 스크립트: `scripts/yt_fetch.sh`
- 프레임 설정: `scale=512:-2`, `-q:v 4`, `YT_FETCH_MAX_FRAMES=54` 기본값, 테스트 구간 `--start 0 --end 90`
- 검증 파일:
  - `/tmp/re-watch-verify/frames/frames.json`
  - `/tmp/re-watch-verify/frames/frame_0001.jpg`
  - `/tmp/re-watch-bench2/frames/frames.json`
  - `/tmp/re-watch-bench2/frames/frame_0001.jpg`

## 사용 영상

| ID | URL | 제목 | 구간 | 추출 프레임 |
|---|---|---|---:|---:|
| V1 | `https://youtu.be/KW0_c23gCss` | My Claude Code Can INSTANTLY Watch Any Video (Here's How) | 0-90초 | 42 |
| V2 | `https://youtu.be/O_z9vDLgvoY` | Claude Skills Tutorial (2026): Build, Run, and Share | 0-90초 | 42 |

## 정답셋

### V1: KW0_c23gCss

| # | 화면 전용 사실 | 프레임 근거 |
|---:|---|---|
| 1 | 데모 UI 상단에 YouTube URL 입력칸과 `SUMMARIZE` 버튼이 있다. | `frame_0016`, `00:32` |
| 2 | 데모 결과 패널 제목이 `Video Summary - Basic Walkthrough`로 보인다. | `frame_0016`, `00:32` |
| 3 | 검은 배경의 채팅 화면에 `Moonlit chat?` 문구가 표시된다. | `frame_0011`-`frame_0013`, 약 `00:21`-`00:26` |
| 4 | 3파트 카드의 세부 부제에 `yt-dlp + ffmpeg + whisper + claude`가 적혀 있다. | `frame_0031`, `01:04` |
| 5 | 3파트 카드의 세 번째 항목 부제가 `Trend Scout + Notion`이다. | `frame_0031`, `01:04` |
| 6 | 후반 화면에 `Script updated`와 `Asset dashboard` 체크리스트가 보인다. | `frame_0042`, `01:27` |

### V2: O_z9vDLgvoY

| # | 화면 전용 사실 | 프레임 근거 |
|---:|---|---|
| 1 | 예시 이메일 제목은 `Building a custom skill`이고 오른쪽에 `Thread Reply` 초안 패널이 보인다. | `frame_0002`, 약 `00:02` |
| 2 | VS Code 탐색기에서 `.claude/skills/thread-reply/SKILL.md`를 편집한다. | `frame_0006`, 약 `00:11` |
| 3 | 같은 VS Code 프로젝트에는 `business-overview.md`, `financials.yml`, `partner-proposal-thread.txt`, `README.md`, `team-roster.md`가 보인다. | `frame_0006`, 약 `00:11` |
| 4 | Claude 홈 화면 모델 선택이 `Opus 4.7 Adaptive`로 보인다. | `frame_0018`, 약 `00:36` |
| 5 | Claude 사이드바에는 `New chat`, `Search`, `Chats`, `Projects`, `Code`, `Customize`, `Design` 항목이 보인다. | `frame_0018`, 약 `00:36` |
| 6 | `dashboard-updater` 스킬 상세 화면에는 `Allowed Tools: Read, Write, Edit`가 보인다. | `frame_0031`, 약 `01:04` |

## 결과

| 모드 | V1 포착 | V1 커버리지 | V2 포착 | V2 커버리지 | 전체 포착 | 전체 커버리지 |
|---|---:|---:|---:|---:|---:|---:|
| 캡션 전용 | 0/6 | 0% | 0/6 | 0% | 0/12 | 0% |
| frames+transcript | 6/6 | 100% | 6/6 | 100% | 12/12 | 100% |

향상폭: **+100 percentage points** (`0%` → `100%`). 분모가 0에서 시작하므로 배수 개선율 대신 절대 커버리지 개선폭을 핵심 지표로 사용했다.

## 방법론

1. `yt_fetch.sh captions`로 각 영상의 VTT를 받은 뒤 0-90초 자막을 평문으로 추출했다.
2. 같은 구간에 `yt_fetch.sh frames <url> <dir> --start 0 --end 90`을 실행했다.
3. `frames.json`의 JPEG 경로를 Read/image viewer로 열어 화면 텍스트와 UI 상태를 확인했다.
4. 정답셋은 “화면에는 명확히 보이나 해당 구간 자막 텍스트만으로는 특정 값을 알 수 없는 사실”만 포함했다.
5. 캡션 전용 모드는 자막 텍스트에 해당 고유 UI 라벨·파일명·버튼명·화면 상태가 없으면 미포착으로 계산했다.

## 관찰

- V1은 말로는 “3파트”와 “라이브 데모”를 설명하지만, `SUMMARIZE` 버튼, `Moonlit chat?`, `Trend Scout + Notion`, `Asset dashboard` 같은 화면 텍스트는 프레임 없이는 포착할 수 없었다.
- V2는 자막이 “Customize”와 “Dashboard Updater”를 일부 언급하지만, 실제 프로젝트 파일명, Claude 모델 선택, 사이드바 항목, 스킬의 허용 도구는 화면 전용 정보였다.
- 두 영상 모두 512px 프레임에서도 UI 라벨을 충분히 읽을 수 있었다. 작은 본문 텍스트는 512px에서 일부 흐려져, 필요 시 특정 구간만 `YT_FETCH_FRAME_WIDTH=768` 이상으로 재추출하는 후속 튜닝이 유효하다.
