# 찾아줘 iOS + 서울대 식단 크롤러

- `ios/` — SwiftUI 앱. 식당 핀과 식단 시트는 `https://chajajwo-web-mu.vercel.app/api/meals`에서 최신 식단을 받아 오고, 실패하면 저장본/번들(`Resources/meals.json`)을 씁니다. `xcodegen`으로 `project.yml`에서 프로젝트를 만듭니다.
- `crawler/` — 서울대 식단 크롤러(`chajwo_meals`). 웹 저장소의 GitHub Actions가 이 코드로 `data/meals.json`을 하루 3번 갱신합니다.
