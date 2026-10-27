# 찾아줘 iOS + 서울대 식단 크롤러

- `ios/` — SwiftUI 앱. 식당 핀과 식단 시트는 `https://chajajwo-web-mu.vercel.app/api/meals`에서 최신 식단을 받아 오고, 실패하면 저장본/번들(`Resources/meals.json`)을 씁니다. `xcodegen`으로 `project.yml`에서 프로젝트를 만듭니다.
- `crawler/` — 서울대 식단 크롤러(`chajwo_meals`). 웹 저장소의 GitHub Actions가 이 코드로 `data/meals.json`을 하루 3번 갱신합니다.

홈 지도에 퀘스트 목록·상세, 교내순환 실시간 기반 추정 위치와 정류장을 표시합니다. 식단은 식당 탭에서 조회하며 커뮤니티 탭의 본문은 비워 두었습니다. 퀘스트 수락·등록·제출은 실행 중의 로컬 시연 기능입니다. [화면 범위, 셔틀 데이터와 검증 방법](design-drafts/quest-home/README.md)을 확인하세요.

`swift test`로 지도·추적·퀘스트 모델을 검사하고, GitHub Actions에서 iOS Simulator 빌드와 홈 화면 실행을 확인합니다.
