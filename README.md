# 찾아줘 iOS + 서울대 식단 크롤러

- `ios/` — SwiftUI 앱. 식당 핀과 식단 시트는 `https://chajajwo-web-mu.vercel.app/api/meals`에서 최신 식단을 받아 오고, 실패하면 저장본/번들(`Resources/meals.json`)을 씁니다. `xcodegen`으로 `project.yml`에서 프로젝트를 만듭니다.
- `crawler/` — 서울대 식단 크롤러(`chajwo_meals`). 웹 저장소의 GitHub Actions가 이 코드로 `data/meals.json`을 하루 3번 갱신합니다.

홈 지도에 퀘스트 목록·상세, 교내순환 실시간 기반 추정 위치와 정류장을 표시합니다. 식단은 식당 탭에서 조회하며 커뮤니티 탭의 본문은 비워 두었습니다. 퀘스트 수락·등록·제출은 실행 중의 로컬 시연 기능입니다. [화면 범위, 셔틀 데이터와 검증 방법](design-drafts/quest-home/README.md)을 확인하세요.

`swift test`로 지도·추적·퀘스트 모델을 검사하고, GitHub Actions에서 iOS Simulator 빌드와 홈 화면 실행을 확인합니다.

길찾기 버튼(검색한 건물·식당·셔틀 정류장)은 앱 안의 전체 화면에서 카카오맵 웹 길찾기를 엽니다. 카카오 연결 화면이 나오면 **설치없이 지도보기**를 선택해 출발지를 입력하고 경로를 확인할 수 있습니다. 외부 지도 앱·브라우저·앱스토어로 이동하는 링크는 차단합니다. 상단에서 뒤로 가기·새로고침·닫기를 사용할 수 있고, 연결에 실패하면 다시 시도할 수 있습니다. 길찾기 화면을 닫으면 이전 장소 화면으로 돌아갑니다.

홈 상단 **길찾기**에서 출발·도착 건물을 각각 검색해 선택할 수 있습니다. 건물 검색 결과 카드의 **건물 간 길찾기**는 해당 건물을 도착지로 미리 선택합니다. 출발·도착 바꾸기와 도보(기본)·대중교통·자동차 선택을 지원하며, **경로 보기**로 앱 내부에서 두 건물 사이의 경로를 엽니다. 같은 위치를 두 번 선택한 경우 경로 조회를 막고 안내합니다.

카카오의 [공식 길찾기 웹 URL](https://apis.map.kakao.com/web/guide/#routeurl)을 사용하며 별도 경로 API 키는 필요하지 않습니다. 카카오가 제공하는 연결 화면은 유지합니다. iOS Simulator에서 `-preview-directions`, `-preview-building-directions`, `-preview-building-route` 실행 인자로 관련 화면을 확인할 수 있으며, CI의 `native-home-preview` 아티팩트에 `directions.png`, `building-directions.png`, `building-route.png`를 포함합니다.
