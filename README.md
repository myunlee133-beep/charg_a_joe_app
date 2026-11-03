# 찾아줘 iOS + 서울대 식단 크롤러

- `ios/` — SwiftUI 앱. 식당 핀과 식단 시트는 `https://chajajwo-web-mu.vercel.app/api/meals`에서 최신 식단을 받아 오고, 실패하면 저장본/번들(`Resources/meals.json`)을 씁니다. `xcodegen`으로 `project.yml`에서 프로젝트를 만듭니다.
- `crawler/` — 서울대 식단 크롤러(`chajwo_meals`). 웹 저장소의 GitHub Actions가 이 코드로 `data/meals.json`을 하루 3번 갱신합니다.
- `backend/account/` — 공통 계정 UUID, 버전별 개인정보·약관 동의, 퀘스트 의뢰자·수행자·직접 송금 기록과 접근 제어. [설정과 검증](backend/account/README.md)을 확인하세요.

홈 지도에 퀘스트 목록·상세, 교내순환 실시간 기반 추정 위치와 정류장을 표시합니다. 앱을 열면 로그인·회원가입 화면이 먼저 나타납니다. Google·카카오·이메일 로그인을 연결하고 Apple 활성화는 보류했습니다. 계정 설정 후 식단·지도·커뮤니티·분실물·퀘스트를 같은 계정으로 이용합니다. 퀘스트 등록·수락·결과 제출·보상 약정은 서버에 기록됩니다. 보상은 이용자끼리 직접 계좌송금하며 앱의 송금 신고와 실제 입금 확인을 구분합니다. `Quest.demo`는 모델 검증용이며 실서비스 목록으로 대체 표시하지 않습니다.

`swift test`로 지도·추적·퀘스트 계약 모델을 검사하고, GitHub Actions에서 iOS Simulator 빌드, 로그인 입력·정책 열람 UI와 PostgreSQL 권한·거래 상태·보유 기간 테스트를 수행합니다. 이메일 인증·재설정에는 프로젝트의 앱 복귀 URL과 실제 발송 SMTP 설정이 필요합니다.
