# adapter failure modes

## blog/community fetch가 리뷰·포럼 사이트에서 봇 차단(HTTP 403/402)·본문 truncation에 반복적으로 막힘

3D 프린터 세션에서 all3dp.com·toms3d.org·3druck.com·jeffgeerling.com이 HTTP 403, forum.bambulab.com이 HTTP 402로 차단됐고 tomshardware·techradar는 본문이 nav-only로 truncate됐다. grill 세션에서도 aihero.dev의 JS 렌더 페이지(뉴스레터 가입 폼)에서 콘텐츠를 못 건졌다. 즉 컨슈머 리뷰 매체·커뮤니티 포럼·JS-heavy 마케팅 페이지가 blog/community 어댑터의 공통 사각지대다.

**Evidence:** 2026-05-26-best-home-3d-printer-under-2-million-won, 2026-05-25-grill-skills-9-mistakes

**Action:** /evolve로 blog·community 어댑터에 봇 차단(403/402) 및 nav-only truncation 감지 → 즉시 WebSearch 스니펫/캐시/리더 모드(r.jina.ai 등) fallback으로 폴백하는 단계를 명시하고, 알려진 차단 도메인(all3dp, toms3d, tomshardware, forum.bambulab)을 어댑터 프롬프트에 사전 경고로 박아둘 것.

## 동일 입력에 candidate 어댑터(general-purpose repo-persona)와 prod 어댑터가 중복 실행돼 세션이 이중 생성됨

kCc8FmEb1nY(GPT)와 wjZofJX0v4M(Transformers) 영상이 각각 -cand(`general-purpose(repo-persona)` 모델)와 일반 버전으로 수 분 간격에 두 번씩 처리돼 4개 세션을 만들었다. candidate 쪽은 intent_mode=assumed에 sources 1건뿐이고 notion_url도 null이라, bench/evolve용 swap 실행이 정식 세션으로 manifest에 흘러든 정황이다.

**Evidence:** 2026-05-25-lets-build-gpt-from-scratch-cand, 2026-05-25-transformers-the-tech-behind-llms-cand

**Action:** bench --swap-candidates로 생성된 candidate 세션을 manifest에서 격리(예: dreamed_in/notion_url null + intent_mode=assumed 조합을 candidate 태그로 마킹)해 /dream·/research 다운스트림이 prod 세션만 집계하도록 분리할 것.

