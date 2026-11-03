# 찾아줘 iOS — 서울대 지도 · 셔틀 · 식단

출시용 브랜치입니다. 앱에는 세 가지 기능만 들어 있습니다.

- **지도** — 카카오맵 기반 관악캠퍼스 지도, 건물 검색, 내 위치.
- **셔틀** — 교내순환(41946) 정류장과 실시간 기반 추정 위치. 원본이 GPS가 아닌 노선도 좌표라서 화면에 "추정"으로 표시합니다.
- **식단** — 식당 핀과 식단 시트, 식당 탭. `https://raw.githubusercontent.com/myunlee133-beep/chajajwo-meals-data/main/meals.json`에서 받고, 실패하면 저장본과 번들(`Resources/meals.json`)을 씁니다.

퀘스트·분실물·사랑방(커뮤니티)과 Supabase 연동은 이 브랜치에서 제거했습니다. 계정과 사용자 작성 콘텐츠가 없으므로 로그인·계정 삭제·신고 기능이 필요 없습니다.

## 구성
- `ios/` — SwiftUI 앱. `xcodegen`으로 `project.yml`에서 프로젝트를 만듭니다.
- `crawler/` — 서울대 식단 크롤러(`chajwo_meals`).

`swift test`로 셔틀 추적 모델을 검사하고, GitHub Actions에서 iOS Simulator 빌드와 홈 화면 실행을 확인합니다.

앱스토어 제출 전 확인 사항은 [`docs/release-checklist.md`](docs/release-checklist.md)를 보세요.
